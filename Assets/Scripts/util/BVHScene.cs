using System;
using System.Collections.Generic;
using System.Threading;
using Unity.Collections;
using Unity.Collections.LowLevel.Unsafe;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Experimental.Rendering;

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

    ComputeBuffer vertexPositionBufferGPU;
    NativeArray<Vector4> vertexPositionBufferCPU;
    ComputeBuffer triangleAttributesBuffer;
    ComputeBuffer materialsBuffer;

    ComputeShader textureCopyShader;
    ComputeBuffer textureDescriptorBuffer;
    ComputeBuffer textureDataBuffer;

    // BVH data
    public tinybvh.BVH sceneBVH;
    bool buildingBVH = false;
    ComputeBuffer bvhNodes;
    ComputeBuffer bvhTris;

    List<Material> materials = new List<Material>();

    // Struct sizes in bytes
    const int VertexPositionSize = 16;
    const int TriangleAttributeSize = 100;
    const int BVHNodeSize = 80;
    const int BVHTriSize = 16;
    // Number of float/uint values in material.hlsl
    const int MaterialSize = 28;
    const int TextureOffset = 24;

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
            return;

        cmd.SetComputeBufferParam(shader, kernelIndex, "BVHNodes", bvhNodes);
        cmd.SetComputeBufferParam(shader, kernelIndex, "BVHTris", bvhTris);
        cmd.SetComputeBufferParam(shader, kernelIndex, "TriangleAttributesBuffer", triangleAttributesBuffer);
        cmd.SetComputeBufferParam(shader, kernelIndex, "Materials", materialsBuffer);
        cmd.SetComputeIntParam(shader, "TriangleCount", 2);

        if (textureDataBuffer != null)
        {
            cmd.SetComputeBufferParam(shader, kernelIndex, "TextureDescriptors", textureDescriptorBuffer);
            cmd.SetComputeBufferParam(shader, kernelIndex, "TextureData", textureDataBuffer);
        }
    }

    public void UpdateMaterialData(bool updateTextures)
    {
        List<Texture> textures = new List<Texture>();
        float[] materialData = new float[materials.Count * MaterialSize];
        for (int i = 0; i < materials.Count; i++)
        {
            Color baseColor = 
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
            float ior = 
                materials[i].HasProperty("_IOR") ? materials[i].GetFloat("_IOR")
                : materials[i].HasProperty("ior") ? materials[i].GetFloat("ior")
                : 1.1f;
            float normalScale = 
                materials[i].HasProperty("_BumpScale") ? materials[i].GetFloat("_BumpScale")
                : materials[i].HasProperty("normalScale") ? materials[i].GetFloat("normalScale")
                : 1.0f;
            int alphaMode = 
                materials[i].HasProperty("alphaMode") ? (int)materials[i].GetFloat("alphaMode")
                : 0;
            float alphaCutoff = 
                materials[i].HasProperty("alphaCutoff") ? materials[i].GetFloat("alphaCutoff")
                : 0.5f;
            float anisotropic = 
                materials[i].HasProperty("anisotropicFactor") ? materials[i].GetFloat("anisotropicFactor")
                : 0.0f;
            float specular = 
                materials[i].HasProperty("specularFactor") ? materials[i].GetFloat("specularFactor")
                : 0.0f;
            float specularTint = 
                materials[i].HasProperty("specularTint") ? materials[i].GetFloat("specularTint")
                : 0.0f;
            float sheen = 
                materials[i].HasProperty("sheenFactor") ? materials[i].GetFloat("sheenFactor")
                : 0.0f;
            float sheenTint =
                materials[i].HasProperty("sheenTint") ? materials[i].GetFloat("sheenTint")
                : 0.0f;
            float subsurface =
                materials[i].HasProperty("subsurfaceFactor") ? materials[i].GetFloat("subsurfaceFactor")
                : 0.0f;
            float clearCoat =
                materials[i].HasProperty("clearCoatFactor") ? materials[i].GetFloat("clearCoatFactor")
                : 0.0f;
            float clearCoatGloss =
                materials[i].HasProperty("clearCoatGloss") ? materials[i].GetFloat("clearCoatGloss")
                : 0.0f;

            int mdi = i * MaterialSize;
            int mti = mdi + TextureOffset;

            materialData[mdi + 0] = baseColor.r; // data1
            materialData[mdi + 1] = baseColor.g;
            materialData[mdi + 2] = baseColor.b;
            materialData[mdi + 3] = baseColor.a;

            materialData[mdi + 4] = emission.r; // data2
            materialData[mdi + 5] = emission.g;
            materialData[mdi + 6] = emission.b;
            materialData[mdi + 7] = alphaCutoff;

            materialData[mdi + 8] = metallic; // data3
            materialData[mdi + 9] = roughness;
            materialData[mdi + 10] = normalScale;
            materialData[mdi + 11] = ior;

            materialData[mdi + 12] = alphaMode; // data4
            materialData[mdi + 13] = anisotropic;
            materialData[mdi + 14] = specular;
            materialData[mdi + 15] = specularTint;

            materialData[mdi + 16] = sheen; // data5
            materialData[mdi + 17] = sheenTint;
            materialData[mdi + 18] = subsurface;
            materialData[mdi + 19] = clearCoat;

            materialData[mdi + 20] = clearCoatGloss; // data6
            materialData[mdi + 21] = 1.0f - baseColor.a;
            materialData[mdi + 22] = 0.0f;
            materialData[mdi + 23] = 0.0f;

            materialData[mti + 0] = -1.0f; // baseColorOpacity texture
            materialData[mti + 1] = -1.0f; // metallicRoughness texture
            materialData[mti + 2] = -1.0f; // normal texture
            materialData[mti + 3] = -1.0f; // emission texture

            // BaseColor texture
            Texture mainTex = materials[i].HasProperty("_MainTex") ? materials[i].GetTexture("_MainTex")
                : materials[i].HasProperty("baseColorTexture") ? materials[i].GetTexture("baseColorTexture")
                : null;
            if (mainTex)
            {
                if (textures.Contains(mainTex))
                {
                    materialData[mti + 0] = textures.IndexOf(mainTex);
                }
                else
                {
                    textures.Add(mainTex);
                    materialData[mti + 0] = textures.Count - 1;
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
                    materialData[mti + 1] = textures.IndexOf(metallicRoughnessTex);
                }
                else
                {
                    textures.Add(metallicRoughnessTex);
                    materialData[mti + 1] = textures.Count - 1;
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
                    materialData[mti + 2] = textures.IndexOf(normalTex);
                }
                else
                {
                    textures.Add(normalTex);
                    materialData[mti + 2] = textures.Count - 1;
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
                    materialData[mti + 3] = textures.IndexOf(emissionTex);
                }
                else
                {
                    textures.Add(emissionTex);
                    materialData[mti + 3] = textures.Count - 1;
                }
            }
        }
        materialsBuffer.SetData(materialData);

        if (updateTextures)
        {
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
                    bool hasAlpha = GraphicsFormatUtility.HasAlphaChannel(texture.graphicsFormat);

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
                    textureCopyShader.SetInt("TextureHasAlpha", hasAlpha ? 1 : 0);

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
        }
    }

    public void ProcessMeshes()
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

        materials.Clear();

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
                materials.Add(material);

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

        List<Texture> textures = new List<Texture>();

        materialsBuffer = new ComputeBuffer(materials.Count, MaterialSize * 4);

        Debug.Log("Total materials: " + materials.Count);

        UpdateMaterialData(true);

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
            IntPtr dataPointer = (IntPtr)NativeArrayUnsafeUtility.GetUnsafeReadOnlyPtr(persistentBuffer);
        #else
            IntPtr dataPointer = (IntPtr)NativeArrayUnsafeUtility.GetUnsafeReadOnlyPtr(vertexPositionBufferCPU);
        #endif
        
        // Build BVH in thread.
        #if !PLATFORM_WEBGL
        //Thread thread = new Thread(() => {
        #endif
            DateTime bvhStartTime = DateTime.UtcNow;
            sceneBVH.Build(dataPointer, totalTriangleCount);
            TimeSpan bvhTime = DateTime.UtcNow - bvhStartTime;

            Debug.Log("BVH built in: " + bvhTime.TotalMilliseconds + "ms");

            #if UNITY_EDITOR
                persistentBuffer.Dispose();
            #endif
        #if !PLATFORM_WEBGL
        //});
        #endif

        buildingBVH = true;
        #if !PLATFORM_WEBGL
        //thread.Start();
        #endif
    }
}
