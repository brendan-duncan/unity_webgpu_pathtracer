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

    int totalVertexCount = 0;
    int totalTriangleCount = 0;
    DateTime readbackStartTime;

    public ComputeBuffer vertexPositionBufferGPU;
    public NativeArray<Vector4> vertexPositionBufferCPU;
    ComputeBuffer triangleAttributesBuffer;
    ComputeBuffer materialsBuffer;

    ComputeShader textureCopyShader;
    List<Texture> textures = new List<Texture>();
    ComputeBuffer textureDescriptorBuffer;
    ComputeBuffer textureDataBuffer;

    // BVH data
    tinybvh.BVH sceneBVH;
    bool buildingBVH = false;
    ComputeBuffer bvhNodes;
    ComputeBuffer bvhTris;

    // Struct sizes in bytes
    const int VertexPositionSize = 16;
    const int TriangleAttributeSize = 64;
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

        textureCopyShader = Resources.Load<ComputeShader>("CopyTextureData");

        ProcessMeshes();
    }

    public void OnDestroy()
    {
        vertexPositionBufferGPU?.Release();
        triangleAttributesBuffer?.Release();

        if (vertexPositionBufferCPU.IsCreated)
        {
            vertexPositionBufferCPU.Dispose();
        }

        sceneBVH.Destroy();
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
        cmd.SetComputeBufferParam(shader, kernelIndex, "TextureDescriptors", textureDescriptorBuffer);
        cmd.SetComputeBufferParam(shader, kernelIndex, "TextureData", textureDataBuffer);
        
        /*for (int i = 0; i < textures.Count; i++)
        {
            cmd.SetComputeTextureParam(shader, 0, $"AlbedoTexture{i + 1}", textures[i]);
        }
        for (int i = textures.Count; i < 8; i++)
        {
            cmd.SetComputeTextureParam(shader, 0, $"AlbedoTexture{i + 1}", Texture2D.whiteTexture);
        }*/
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
            int vertexStride, positionOffset, normalOffset, uvOffset;
            Utilities.FindVertexAttribute(mesh, VertexAttribute.Position, out positionOffset, out vertexStride);
            Utilities.FindVertexAttribute(mesh, VertexAttribute.Normal, out normalOffset, out vertexStride);
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
            meshProcessingShader.SetInt("UVOffset", uvOffset);
            meshProcessingShader.SetInt("TriangleCount", triangleCount);
            meshProcessingShader.SetInt("OutputTriangleStart", totalTriangleCount);
            meshProcessingShader.SetInt("MaterialIndex", materialIndex);
            meshProcessingShader.SetMatrix("LocalToWorld", renderer.localToWorldMatrix);

            // Set keywords based on format/attributes of this mesh
            meshProcessingShader.SetKeyword(has32BitIndicesKeyword, (mesh.indexFormat == IndexFormat.UInt32));
            meshProcessingShader.SetKeyword(hasNormalsKeyword, mesh.HasVertexAttribute(VertexAttribute.Normal));
            meshProcessingShader.SetKeyword(hasUVsKeyword, mesh.HasVertexAttribute(VertexAttribute.TexCoord0));
            meshProcessingShader.SetKeyword(hasIndexBufferKeyword, indexBuffer != null);

            meshProcessingShader.Dispatch(0, Mathf.CeilToInt(triangleCount / 64.0f), 1, 1);

            totalTriangleCount += triangleCount;
        }

        Debug.Log("Meshes processed. Total triangles: " + totalTriangleCount);

        materialsBuffer = new ComputeBuffer(materials.Count, 32);
        textures.Clear();

        Debug.Log("Total materials: " + materials.Count);

        float[] materialData = new float[materials.Count * 8];
        for (int i = 0; i < materials.Count; i++)
        {
            Color color = 
                materials[i].HasProperty("_Color") ? materials[i].color
                : materials[i].HasProperty("baseColorFactor") ? materials[i].GetColor("baseColorFactor")
                : new Color(0.8f, 0.8f, 0.8f, 1.0f);
            Color emission = 
                materials[i].HasProperty("_EmissionColor") ? materials[i].GetColor("_EmissionColor")
                : materials[i].HasProperty("emissionFactor") ? materials[i].GetColor("emissionFactor")
                : Color.black;
            color += emission;
            float metalic = 
                materials[i].HasProperty("_Metallic") ? materials[i].GetFloat("_Metallic")
                : materials[i].HasProperty("metallicFactor") ? materials[i].GetFloat("metallicFactor")
                : 0.0f;
            float smoothness =
                materials[i].HasProperty("_Glossiness") ? materials[i].GetFloat("_Glossiness")
                : materials[i].HasProperty("roughnessFactor") ? 1.0f - materials[i].GetFloat("roughnessFactor")
                : 0.0f;
            int mode = 
                materials[i].HasProperty("_Mode") ? materials[i].GetInt("_Mode")
                : materials[i].HasProperty("mode") ? materials[i].GetInt("mode")
                : 0;
            materialData[i * 8 + 0] = color.r;
            materialData[i * 8 + 1] = color.g;
            materialData[i * 8 + 2] = color.b;
            materialData[i * 8 + 3] = -1.0f;
            materialData[i * 8 + 4] = metalic;
            materialData[i * 8 + 5] = smoothness;
            materialData[i * 8 + 6] = (float)mode;
            materialData[i * 8 + 7] = 1.3f;

            Texture mainTex = materials[i].HasProperty("_MainTex") ? materials[i].GetTexture("_MainTex")
                : materials[i].HasProperty("baseColorTexture") ? materials[i].GetTexture("baseColorTexture")
                : null;

            if (mainTex)
            {
                if (textures.Contains(mainTex))
                {
                    materialData[i * 8 + 3] = textures.IndexOf(mainTex);
                }
                else
                {
                    textures.Add(mainTex);
                    materialData[i * 8 + 3] = textures.Count - 1;
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

        textureDataBuffer = new ComputeBuffer(totalTextureSize, 4*4);
        textureDescriptorBuffer = new ComputeBuffer(textures.Count, 16);

        textureCopyShader.SetBuffer(0, "TextureData", textureDataBuffer);

        uint[] textureDescriptorData = new uint[textures.Count * 4];
        int ti = 0;
        int textureOffset = 0;
        int textureIndex = 0;
        foreach (Texture texture in textures)
        {
            int width = texture.width;
            int height = texture.height;
            int totalPixels = width * height;
            int textureSize = totalPixels;

            Debug.Log("Texture: " + texture.name + " " + textureIndex + " " + width + "x" + height + " offset:" + textureOffset + " " + (textureSize * 16) + " bytes");
            textureIndex++;

            textureDescriptorData[ti++] = (uint)width;
            textureDescriptorData[ti++] = (uint)height;
            textureDescriptorData[ti++] = (uint)textureOffset;
            textureDescriptorData[ti++] = (uint)0;
            
            textureCopyShader.SetTexture(0, "Texture", texture);
            textureCopyShader.SetInt("TextureWidth", width);
            textureCopyShader.SetInt("TextureHeight", height);
            textureCopyShader.SetInt("Offset", textureOffset);

            int dispatchX = Mathf.CeilToInt(totalPixels / 128.0f);
            textureCopyShader.Dispatch(0, dispatchX, 1, 1);

            textureOffset += textureSize;
        }
        
        textureDescriptorBuffer.SetData(textureDescriptorData);

        Debug.Log("Total texture data size: " + totalTextureSize * 16 + " bytes");

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
