using System;
using System.Collections.Generic;
using System.Threading;
using Unity.Collections;
using Unity.Collections.LowLevel.Unsafe;
using UnityEngine;
using UnityEngine.Rendering;

public class BVHScene
{
    MeshRenderer[] meshRenderers;
    ComputeShader meshProcessingShader;
    LocalKeyword hasIndexBufferKeyword;
    LocalKeyword has32BitIndicesKeyword;
    LocalKeyword hasNormalsKeyword;
    LocalKeyword hasUVsKeyword;
    LocalKeyword hasTangentsKeyword;

    int totalVertexCount = 0;
    int totalTriangleCount = 0;
    DateTime readbackStartTime;

    public ComputeBuffer vertexPositionBufferGPU;
    public NativeArray<Vector4> vertexPositionBufferCPU;
    ComputeBuffer triangleAttributesBuffer;
    ComputeBuffer materialsBuffer;

    ComputeShader textureCopyShader;
    ComputeBuffer textureDescriptorBuffer;
    ComputeBuffer textureDataBuffer;

    // BVH data
    tinybvh.BVH sceneBVH;
    bool buildingBVH = false;
    ComputeBuffer bvhNodes;
    ComputeBuffer bvhTris;

    // Struct sizes in bytes
    const int VertexPositionSize = 16;
    const int TriangleAttributeSize = 100;
    const int BVHNodeSize = 80;
    const int BVHTriSize = 16;

    public void Start()
    {
        sceneBVH = new tinybvh.BVH();

        // Load compute shader
        meshProcessingShader = Resources.Load<ComputeShader>("MeshProcessing");
        hasIndexBufferKeyword = meshProcessingShader.keywordSpace.FindKeyword("HAS_INDEX_BUFFER");
        has32BitIndicesKeyword = meshProcessingShader.keywordSpace.FindKeyword("HAS_32_BIT_INDICES");
        hasNormalsKeyword = meshProcessingShader.keywordSpace.FindKeyword("HAS_NORMALS");
        hasUVsKeyword = meshProcessingShader.keywordSpace.FindKeyword("HAS_UVS");
        hasTangentsKeyword = meshProcessingShader.keywordSpace.FindKeyword("HAS_TANGENTS");

        textureCopyShader = Resources.Load<ComputeShader>("CopyTextureData");

        ProcessMeshes();
    }

    public void OnDestroy()
    {
        vertexPositionBufferGPU?.Release();
        triangleAttributesBuffer?.Release();
        vertexPositionBufferCPU.Dispose();
        sceneBVH?.Destroy();
        bvhNodes?.Release();
        bvhTris?.Release();
        materialsBuffer?.Release();
        textureDescriptorBuffer?.Release();
        textureDataBuffer?.Release();
    }

    public tinybvh.BVH GetBVH()
    {
        return sceneBVH;
    }

    public void Update()
    {
        if (buildingBVH && sceneBVH.IsReady())
        {
            Debug.Log("BVH Uploaded");
            // Get the sizes of the arrays
            int nodesSize = sceneBVH.GetCWBVHNodesSize();
            int trisSize = sceneBVH.GetCWBVHTrisSize();

            IntPtr nodesPtr, trisPtr;
            if (sceneBVH.GetCWBVHData(out nodesPtr, out trisPtr))
            {
                Utilities.UploadFromPointer(ref bvhNodes, nodesPtr, nodesSize, BVHNodeSize);
                Utilities.UploadFromPointer(ref bvhTris, trisPtr, trisSize, BVHTriSize);
            } 
            else
            {
                Debug.LogError("Failed to fetch updated BVH data.");
            }

            buildingBVH = false;
        }
    }

    public bool CanRender()
    {
        return (bvhNodes != null && bvhTris != null);
    }

    public bool HasTextures()
    {
        return textureDataBuffer != null;
    }

    public void PrepareShader(CommandBuffer cmd, ComputeShader shader, int kernelIndex)
    {
        if (bvhNodes == null || bvhTris == null || triangleAttributesBuffer == null)
        {
            return;
        }

        cmd.SetComputeBufferParam(shader, kernelIndex, "BVHNodes", bvhNodes);
        cmd.SetComputeBufferParam(shader, kernelIndex, "BVHTris", bvhTris);
        cmd.SetComputeBufferParam(shader, kernelIndex, "TriangleAttributesBuffer", triangleAttributesBuffer);
        cmd.SetComputeBufferParam(shader, kernelIndex, "Materials", materialsBuffer);

        if (textureDataBuffer != null)
        {
            cmd.SetComputeBufferParam(shader, kernelIndex, "TextureDescriptors", textureDescriptorBuffer);
            cmd.SetComputeBufferParam(shader, kernelIndex, "TextureData", textureDataBuffer);
        }
    }

    void ProcessMeshes()
    {
        totalVertexCount = 0;
        totalTriangleCount = 0;

        // Populate list of mesh renderers to trace against
        meshRenderers = UnityEngine.Object.FindObjectsByType<MeshRenderer>(FindObjectsSortMode.None);

        // Gather info on the meshes we'll be using
        foreach (MeshRenderer renderer in meshRenderers)
        {
            Mesh mesh = renderer.gameObject.GetComponent<MeshFilter>().sharedMesh;
            if (mesh == null)
            {
                continue;
            }

            totalVertexCount += Utilities.GetTriangleCount(mesh) * 3;
        }

        if (totalVertexCount == 0)
        {
            Debug.LogError("No meshes found to process.");
            return;
        }

        // Allocate buffers
        vertexPositionBufferGPU = new ComputeBuffer(totalVertexCount, VertexPositionSize);
        vertexPositionBufferCPU = new NativeArray<Vector4>(totalVertexCount * VertexPositionSize, Allocator.Persistent);
        triangleAttributesBuffer = new ComputeBuffer(totalVertexCount / 3, TriangleAttributeSize);

        List<Material> materials = new List<Material>();

        // Pack each mesh into global vertex buffer via compute shader
        // Note: this avoids the need for every mesh to have cpu read/write access.
        foreach (MeshRenderer renderer in meshRenderers)
        {
            Mesh mesh = renderer.gameObject.GetComponent<MeshFilter>().sharedMesh;
            if (mesh == null)
            {
                continue;
            }

            Material material = renderer.material;
            if (!materials.Contains(material))
            {
                materials.Add(material);
            }
            int materialIndex = materials.IndexOf(material);

            Debug.Log("Processing mesh: " + renderer.gameObject.name);

            GraphicsBuffer vertexBuffer = mesh.GetVertexBuffer(0);
            GraphicsBuffer indexBuffer = mesh.GetIndexBuffer();
            
            int triangleCount = Utilities.GetTriangleCount(mesh);

            // Determine where in the Unity vertex buffer each vertex attribute is
            int vertexStride, positionOffset, normalOffset, uvOffset, tangentOffset;
            Utilities.FindVertexAttribute(mesh, VertexAttribute.Position, out positionOffset, out vertexStride);
            Utilities.FindVertexAttribute(mesh, VertexAttribute.Normal, out normalOffset, out vertexStride);
            Utilities.FindVertexAttribute(mesh, VertexAttribute.Tangent, out tangentOffset, out vertexStride);
            Utilities.FindVertexAttribute(mesh, VertexAttribute.TexCoord0, out uvOffset, out vertexStride);

            meshProcessingShader.SetBuffer(0, "VertexBuffer", vertexBuffer);
            if (indexBuffer != null)
            {
                meshProcessingShader.SetBuffer(0, "IndexBuffer", indexBuffer);
            }
            meshProcessingShader.SetBuffer(0, "VertexPositionBuffer", vertexPositionBufferGPU);
            meshProcessingShader.SetBuffer(0, "TriangleAttributesBuffer", triangleAttributesBuffer);
            meshProcessingShader.SetInt("VertexStride", vertexStride);
            meshProcessingShader.SetInt("PositionOffset", positionOffset);
            meshProcessingShader.SetInt("NormalOffset", normalOffset);
            meshProcessingShader.SetInt("TangentOffset", tangentOffset);
            meshProcessingShader.SetInt("UVOffset", uvOffset);
            meshProcessingShader.SetInt("TriangleCount", triangleCount);
            meshProcessingShader.SetInt("OutputTriangleStart", totalTriangleCount);
            meshProcessingShader.SetInt("MaterialIndex", materialIndex);
            meshProcessingShader.SetMatrix("LocalToWorld", renderer.localToWorldMatrix);

            // Set keywords based on format/attributes of this mesh
            meshProcessingShader.SetKeyword(has32BitIndicesKeyword, (mesh.indexFormat == IndexFormat.UInt32));
            meshProcessingShader.SetKeyword(hasNormalsKeyword, mesh.HasVertexAttribute(VertexAttribute.Normal));
            meshProcessingShader.SetKeyword(hasUVsKeyword, mesh.HasVertexAttribute(VertexAttribute.TexCoord0));
            meshProcessingShader.SetKeyword(hasTangentsKeyword, mesh.HasVertexAttribute(VertexAttribute.Tangent));
            meshProcessingShader.SetKeyword(hasIndexBufferKeyword, indexBuffer != null);

            meshProcessingShader.Dispatch(0, Mathf.CeilToInt(triangleCount / 64.0f), 1, 1);

            totalTriangleCount += triangleCount;

            vertexBuffer?.Release();
            indexBuffer?.Release();
        }

        Debug.Log("Meshes processed. Total triangles: " + totalTriangleCount);

        // Number of float/uint values in material.hlsl
        const int materialSize = 16;

        List<Texture> textures = new List<Texture>();

        materialsBuffer = new ComputeBuffer(materials.Count, materialSize * 4);
        textures.Clear();

        Debug.Log("Total materials: " + materials.Count);

        float[] materialData = new float[materials.Count * materialSize];
        for (int i = 0; i < materials.Count; i++)
        {
            Color color = 
                materials[i].HasProperty("_Color") ? materials[i].color
                : materials[i].HasProperty("baseColorFactor") ? materials[i].GetColor("baseColorFactor")
                : new Color(0.8f, 0.8f, 0.8f, 1.0f);
            Color emission = 
                materials[i].HasProperty("_EmissionColor") ? materials[i].GetColor("_EmissionColor")
                : materials[i].HasProperty("emissiveFactor") ? materials[i].GetColor("emissiveFactor")
                : Color.black;
            float metallic = 
                materials[i].HasProperty("_Metallic") ? materials[i].GetFloat("_Metallic")
                : materials[i].HasProperty("metallicFactor") ? materials[i].GetFloat("metallicFactor")
                : 0.0f;
            float roughness =
                materials[i].HasProperty("_Glossiness") ? 1.0f - materials[i].GetFloat("_Glossiness")
                : materials[i].HasProperty("roughnessFactor") ? materials[i].GetFloat("roughnessFactor")
                : 0.0f;
            int mode = 
                materials[i].HasProperty("_Mode") ? materials[i].GetInt("_Mode")
                : materials[i].HasProperty("mode") ? materials[i].GetInt("mode")
                : 0;
            float ior = 
                materials[i].HasProperty("_IOR") ? materials[i].GetFloat("_IOR")
                : materials[i].HasProperty("ior") ? materials[i].GetFloat("ior")
                : 1.1f;

            int mdi = i * materialSize;

            materialData[mdi + 0] = color.r;
            materialData[mdi + 1] = color.g;
            materialData[mdi + 2] = color.b;
            materialData[mdi + 3] = 1.0f - color.a; // transmission

            materialData[mdi + 4] = emission.r;
            materialData[mdi + 5] = emission.g;
            materialData[mdi + 6] = emission.b;
            materialData[mdi + 7] = 0.0f;

            materialData[mdi + 8] = metallic;
            materialData[mdi + 9] = roughness;
            materialData[mdi + 10] = (float)mode;
            materialData[mdi + 11] = ior;

            materialData[mdi + 12] = -1.0f; // baseColor texture
            materialData[mdi + 13] = -1.0f; // metallicRoughness texture
            materialData[mdi + 14] = -1.0f; // normal texture
            materialData[mdi + 15] = -1.0f; // emission texture

            // BaseColor texture
            Texture mainTex = materials[i].HasProperty("_MainTex") ? materials[i].GetTexture("_MainTex")
                : materials[i].HasProperty("baseColorTexture") ? materials[i].GetTexture("baseColorTexture")
                : null;

            if (mainTex)
            {
                if (textures.Contains(mainTex))
                {
                    materialData[mdi + 12] = textures.IndexOf(mainTex);
                }
                else
                {
                    textures.Add(mainTex);
                    materialData[mdi + 12] = textures.Count - 1;
                }
            }

            // MetallicRoughness texture
            Texture metallicRoughnessTex = materials[i].HasProperty("_MetallicRoughnessMap") ? materials[i].GetTexture("_MetallicRoughnessMap")
                : materials[i].HasProperty("metallicRoughnessTexture") ? materials[i].GetTexture("metallicRoughnessTexture")
                : null;
            if (metallicRoughnessTex)
            {
                if (textures.Contains(metallicRoughnessTex))
                {
                    materialData[mdi + 13] = textures.IndexOf(metallicRoughnessTex);
                }
                else
                {
                    textures.Add(metallicRoughnessTex);
                    materialData[mdi + 13] = textures.Count - 1;
                }
            }

            // Normal texture
            Texture normalTex = materials[i].HasProperty("_BumpMap") ? materials[i].GetTexture("_BumpMap")
                : materials[i].HasProperty("normalTexture") ? materials[i].GetTexture("normalTexture")
                : null;
            if (normalTex)
            {
                if (textures.Contains(normalTex))
                {
                    materialData[mdi + 14] = textures.IndexOf(normalTex);
                }
                else
                {
                    textures.Add(normalTex);
                    materialData[mdi + 14] = textures.Count - 1;
                }
            }

            // Emission texture
            Texture emissionTex = materials[i].HasProperty("_EmissionMap") ? materials[i].GetTexture("_EmissionMap")
                : materials[i].HasProperty("emissiveTexture") ? materials[i].GetTexture("emissiveTexture")
                : null;
            if (emissionTex)
            {
                if (textures.Contains(emissionTex))
                {
                    materialData[mdi + 15] = textures.IndexOf(emissionTex);
                }
                else
                {
                    textures.Add(emissionTex);
                    materialData[mdi + 15] = textures.Count - 1;
                }
            }
        }
        materialsBuffer.SetData(materialData);

        Debug.Log("Total Textures: " + textures.Count);

        int totalTextureSize = 0;
        foreach (Texture texture in textures)
        {
            int width = texture.width;
            int height = texture.height;
            int textureSize = width * height;
            totalTextureSize += textureSize;
        }

        if (totalTextureSize > 0)
        {
            textureDataBuffer = new ComputeBuffer(totalTextureSize, 4);

            textureDescriptorBuffer = new ComputeBuffer(textures.Count, 16);

            textureCopyShader.SetBuffer(0, "TextureData", textureDataBuffer);

            uint[] textureDescriptorData = new uint[textures.Count * 4];
            int ti = 0;
            int textureDataOffset = 0;
            int textureIndex = 0;
            foreach (Texture texture in textures)
            {
                int width = texture.width;
                int height = texture.height;
                int totalPixels = width * height;

                Debug.Log("Texture: " + texture.name + " " + textureIndex + " " + width + "x" + height + " offset:" + textureDataOffset + " " + (totalPixels * 4) + " bytes");
                textureIndex++;

                textureDescriptorData[ti++] = (uint)width;
                textureDescriptorData[ti++] = (uint)height;
                textureDescriptorData[ti++] = (uint)textureDataOffset;
                textureDescriptorData[ti++] = (uint)0;
                
                textureCopyShader.SetTexture(0, "Texture", texture);
                textureCopyShader.SetInt("TextureWidth", width);
                textureCopyShader.SetInt("TextureHeight", height);
                textureCopyShader.SetInt("TextureDataOffset", textureDataOffset);

                int dispatchX = Mathf.CeilToInt(totalPixels / 128.0f);
                textureCopyShader.Dispatch(0, dispatchX, 1, 1);

                textureDataOffset += totalPixels;
            }
            
            textureDescriptorBuffer.SetData(textureDescriptorData);

            Debug.Log("Total texture data size: " + totalTextureSize * 16 + " bytes");
        }
        else
        {
            textureDataBuffer?.Release();
            textureDescriptorBuffer?.Release();
            textureDataBuffer = null;
            textureDescriptorBuffer = null;
        }

        // Initiate async readback of vertex buffer to pass to tinybvh to build
        readbackStartTime = DateTime.UtcNow;
        AsyncGPUReadback.RequestIntoNativeArray(ref vertexPositionBufferCPU, vertexPositionBufferGPU, OnCompleteReadback);
    }

    unsafe void OnCompleteReadback(AsyncGPUReadbackRequest request)
    {
        if (request.hasError)
        {
            Debug.LogError("GPU readback error.");
            return;
        }

        TimeSpan readbackTime = DateTime.UtcNow - readbackStartTime;
        Debug.Log("GPU readback took: " + readbackTime.TotalMilliseconds + "ms");

        // In the editor if we exit play mode before the bvh is finished building the memory will be freed
        // and tinybvh will illegal access and crash everything. 
        #if UNITY_EDITOR
            NativeArray<Vector4> persistentBuffer = new NativeArray<Vector4>(vertexPositionBufferCPU.Length, Allocator.Persistent);
            persistentBuffer.CopyFrom(vertexPositionBufferCPU);
            var dataPointer = (IntPtr)NativeArrayUnsafeUtility.GetUnsafeReadOnlyPtr(persistentBuffer);
        #else
            var dataPointer = (IntPtr)NativeArrayUnsafeUtility.GetUnsafeReadOnlyPtr(vertexPositionBufferCPU);
        #endif
        
        // Build BVH in thread.
        #if !PLATFORM_WEBGL
        Thread thread = new Thread(() =>
        {
        #endif
            DateTime bvhStartTime = DateTime.UtcNow;
            sceneBVH.Build(dataPointer, totalTriangleCount, true);
            TimeSpan bvhTime = DateTime.UtcNow - bvhStartTime;

            Debug.Log("BVH built in: " + bvhTime.TotalMilliseconds + "ms");

            #if UNITY_EDITOR
                persistentBuffer.Dispose();
            #endif
        #if !PLATFORM_WEBGL
        });
        #endif

        buildingBVH = true;
        #if !PLATFORM_WEBGL
        thread.Start();
        #endif
    }
}
