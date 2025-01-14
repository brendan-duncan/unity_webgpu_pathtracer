#define USE_TLAS

using System;
using System.Collections.Generic;
using Unity.Collections;
using Unity.Collections.LowLevel.Unsafe;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Experimental.Rendering;

#if USE_TLAS
// Instance data passed to the GPU for rendering.
struct GPUInstance
{
    public int materialIndex; 
    public int bvhOffset;
    public int triOffset;
    public int triAttributeOffset;
    public Matrix4x4 transform;
    public Matrix4x4 inverseTransform;
};

// Instance data passed to TinyBVH for building the TLAS.
struct BLASInstance
{
    public Matrix4x4 transform;
    public Matrix4x4 inverseTransform;
    public Vector3 aabbMin;
    public int blasIndex;
    public Vector3 aabbMax;
    public int padding;
};
#endif

public class BVHScene
{
    ComputeShader _meshProcessingShader;

    LocalKeyword _hasIndexBufferKeyword;
    LocalKeyword _has32BitIndicesKeyword;
    LocalKeyword _hasNormalsKeyword;
    LocalKeyword _hasUVsKeyword;
    LocalKeyword _hasTangentsKeyword;

    int _totalVertexCount = 0;
    int _totalTriangleCount = 0;
    DateTime _readbackStartTime;
    ComputeBuffer _vertexPositionBufferGPU;
    NativeArray<Vector4> _vertexPositionBufferCPU;
    ComputeBuffer _triangleAttributesBuffer;
    ComputeBuffer _materialsBuffer;

    ComputeShader _textureCopyShader;
    ComputeBuffer _textureDescriptorBuffer;
    ComputeBuffer _textureDataBuffer;

    // BVH data
    ComputeBuffer _bvhNodesBuffer;
    ComputeBuffer _bvhTrianglesBuffer;

    List<Material> _materials = new();

    // Struct sizes in bytes
    const int kVertexPositionSize = 16;
    const int kTriangleAttributeSize = 100;
    const int kGPUInstanceSize = 144;
    const int kBVHNodeSize = 80;
    const int kBVHTriSize = 16;
    // Number of float values in material.hlsl
    const int kMaterialSize = 32;
    const int kTextureOffset = 24;

    List<MeshRenderer> _sceneMeshRenderers = new();
    List<Mesh> _meshes = new();
    // List of MeshRenderers for each Mesh, for debugging purposes.
    List<MeshRenderer> _meshRenderers = new();
    List<int> _meshStartIndices = new();
    List<int> _meshTriangleCount = new();
    List<int> _triangleAttributeOffsets = new();
    List<int> _vertexPositionOffsets = new();

#if USE_TLAS
    // List of instance data passed to TinyBVH. This is kept persistent so we can update transforms
    // and rebuild the TLAS as necessary.
    BLASInstance[] _blasInstances;
    // List of instance data passed to the GPU for rendering/
    GPUInstance[] _gpuInstances;

    int _gpuInstanceCount = 0;
    ComputeBuffer _tlasNodesBuffer;
    ComputeBuffer _gpuInstancesBuffer;
#endif

    public void Start()
    {
        // Load compute shader
        _meshProcessingShader = Resources.Load<ComputeShader>("MeshProcessing");
        _hasIndexBufferKeyword = _meshProcessingShader.keywordSpace.FindKeyword("HAS_INDEX_BUFFER");
        _has32BitIndicesKeyword = _meshProcessingShader.keywordSpace.FindKeyword("HAS_32_BIT_INDICES");
        _hasNormalsKeyword = _meshProcessingShader.keywordSpace.FindKeyword("HAS_NORMALS");
        _hasUVsKeyword = _meshProcessingShader.keywordSpace.FindKeyword("HAS_UVS");
        _hasTangentsKeyword = _meshProcessingShader.keywordSpace.FindKeyword("HAS_TANGENTS");

        _textureCopyShader = Resources.Load<ComputeShader>("CopyTextureData");

       ProcessMeshes();
    }

    public void OnDestroy()
    {
        _vertexPositionBufferGPU?.Release();
        _triangleAttributesBuffer?.Release();
        _vertexPositionBufferCPU.Dispose();
        _bvhNodesBuffer?.Release();
        _bvhTrianglesBuffer?.Release();
        _materialsBuffer?.Release();
        _textureDescriptorBuffer?.Release();
        _textureDataBuffer?.Release();

#if USE_TLAS
        _tlasNodesBuffer?.Release();
        _gpuInstancesBuffer?.Release();
#endif
    }

    public void Update()
    {
    }

    public bool CanRender()
    {
        return _bvhNodesBuffer != null && _bvhTrianglesBuffer != null;
    }

    public bool HasTextures()
    {
        return _textureDataBuffer != null;
    }

    public void PrepareShader(CommandBuffer cmd, ComputeShader shader, int kernelIndex)
    {
        if (_bvhNodesBuffer == null || _bvhTrianglesBuffer == null || _triangleAttributesBuffer == null)
            return;

        LocalKeyword hasTLASKeyword = shader.keywordSpace.FindKeyword("HAS_TLAS");
#if USE_TLAS
        shader.EnableKeyword(hasTLASKeyword);
#else
        shader.DisableKeyword(hasTLASKeyword);
#endif
        cmd.SetComputeBufferParam(shader, kernelIndex, "BVHNodes", _bvhNodesBuffer);
        cmd.SetComputeBufferParam(shader, kernelIndex, "BVHTris", _bvhTrianglesBuffer);
        cmd.SetComputeBufferParam(shader, kernelIndex, "TriangleAttributesBuffer", _triangleAttributesBuffer);
        cmd.SetComputeBufferParam(shader, kernelIndex, "Materials", _materialsBuffer);
#if USE_TLAS
        cmd.SetComputeBufferParam(shader, kernelIndex, "TLASNodes", _tlasNodesBuffer);
        cmd.SetComputeBufferParam(shader, kernelIndex, "TLASInstances", _gpuInstancesBuffer);
        cmd.SetComputeIntParam(shader, "TLASInstanceCount", _gpuInstanceCount);
#endif

        if (_textureDataBuffer != null)
        {
            cmd.SetComputeBufferParam(shader, kernelIndex, "TextureDescriptors", _textureDescriptorBuffer);
            cmd.SetComputeBufferParam(shader, kernelIndex, "TextureData", _textureDataBuffer);
        }
    }

    public void UpdateMaterialData(bool updateTextures)
    {
        List<Material> materials = _materials;
        List<Texture> textures = new();
        float[] materialData = new float[materials.Count * kMaterialSize];
        for (int i = 0; i < materials.Count; i++)
        {
            Material material = materials[i];

            Color baseColor = 
                material.HasProperty("_Color") ? material.color
                : material.HasProperty("baseColorFactor") ? material.GetColor("baseColorFactor")
                : new Color(0.8f, 0.8f, 0.8f, 1.0f);
            Color emission = 
                material.HasProperty("_EmissionColor") ? material.GetColor("_EmissionColor")
                : material.HasProperty("emissiveFactor") ? material.GetColor("emissiveFactor")
                : Color.black;
            float metallic = 
                material.HasProperty("_Metallic") ? material.GetFloat("_Metallic")
                : material.HasProperty("metallicFactor") ? material.GetFloat("metallicFactor")
                : 0.0f;
            float roughness =
                material.HasProperty("_Glossiness") ? 1.0f - material.GetFloat("_Glossiness")
                : material.HasProperty("roughnessFactor") ? material.GetFloat("roughnessFactor")
                : 0.0f;
            float ior = 
                material.HasProperty("_IOR") ? material.GetFloat("_IOR")
                : material.HasProperty("ior") ? material.GetFloat("ior")
                : 1.1f;
            float normalScale = 
                material.HasProperty("_BumpScale") ? material.GetFloat("_BumpScale")
                : material.HasProperty("normalScale") ? material.GetFloat("normalScale")
                : 1.0f;
            int alphaMode = 
                material.HasProperty("_Mode") ? ((int)material.GetFloat("_Mode") == 1 ? 2 : 0)
                : material.HasProperty("alphaMode") ? (int)material.GetFloat("alphaMode")
                : 0;
            float alphaCutoff = 
                material.HasProperty("_Cutoff") ? material.GetFloat("_Cutoff")
                : material.HasProperty("alphaCutoff") ? material.GetFloat("alphaCutoff")
                : 0.5f;
            float anisotropic = 
                material.HasProperty("anisotropicFactor") ? material.GetFloat("anisotropicFactor")
                : 0.0f;
            float specular = 
                material.HasProperty("specularFactor") ? material.GetFloat("specularFactor")
                : 0.0f;
            float specularTint = 
                material.HasProperty("specularTint") ? material.GetFloat("specularTint")
                : 0.0f;
            float sheen = 
                material.HasProperty("sheenFactor") ? material.GetFloat("sheenFactor")
                : 0.0f;
            float sheenTint =
                material.HasProperty("sheenTint") ? material.GetFloat("sheenTint")
                : 0.0f;
            float subsurface =
                material.HasProperty("subsurfaceFactor") ? material.GetFloat("subsurfaceFactor")
                : 0.0f;
            float clearCoat =
                material.HasProperty("clearCoatFactor") ? material.GetFloat("clearCoatFactor")
                : 0.0f;
            float clearCoatGloss =
                material.HasProperty("clearCoatGloss") ? material.GetFloat("clearCoatGloss")
                : 0.0f;

            int mdi = i * kMaterialSize;
            int mti = mdi + kTextureOffset;

            materialData[mdi + 0] = Mathf.Pow(baseColor.r, 2.2f); // data1
            materialData[mdi + 1] = Mathf.Pow(baseColor.g, 2.2f);
            materialData[mdi + 2] = Mathf.Pow(baseColor.b, 2.2f);
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

            Vector2 uvScale = material.HasTexture("_MainTex") ? material.mainTextureScale : Vector2.one;
            Vector2 uvOffset = material.HasTexture("_MainTex") ? material.mainTextureOffset : Vector2.zero;

            materialData[mti + 4] = uvScale.x;
            materialData[mti + 5] = uvScale.y;
            materialData[mti + 6] = uvOffset.x;
            materialData[mti + 7] = uvOffset.y;

            // BaseColor texture
            Texture mainTex = material.HasProperty("_MainTex") ? material.GetTexture("_MainTex")
                : material.HasProperty("baseColorTexture") ? material.GetTexture("baseColorTexture")
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
            Texture metallicRoughnessTex = material.HasProperty("_MetallicRoughnessMap") ? material.GetTexture("_MetallicRoughnessMap")
                : material.HasProperty("metallicRoughnessTexture") ? material.GetTexture("metallicRoughnessTexture")
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
            Texture normalTex = material.HasProperty("_BumpMap") ? material.GetTexture("_BumpMap")
                : material.HasProperty("normalTexture") ? material.GetTexture("normalTexture")
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
            Texture emissionTex = material.HasProperty("_EmissionMap") ? material.GetTexture("_EmissionMap")
                : material.HasProperty("emissiveTexture") ? material.GetTexture("emissiveTexture")
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
        _materialsBuffer.SetData(materialData);

        if (updateTextures)
        {
            Debug.Log($"Total Textures: {textures.Count}");

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
                _textureDataBuffer = new ComputeBuffer(totalTextureSize, 4);

                _textureDescriptorBuffer = new ComputeBuffer(textures.Count, 16);

                _textureCopyShader.SetBuffer(0, "TextureData", _textureDataBuffer);

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

                    Debug.Log($"Texture {textureIndex}: {texture.name} {width}x{height} offset:{textureDataOffset} {(totalPixels * 4):n0} bytes");
                    textureIndex++;

                    textureDescriptorData[ti++] = (uint)width;
                    textureDescriptorData[ti++] = (uint)height;
                    textureDescriptorData[ti++] = (uint)textureDataOffset;
                    textureDescriptorData[ti++] = (uint)0;

                    _textureCopyShader.SetTexture(0, "Texture", texture);
                    _textureCopyShader.SetInt("TextureWidth", width);
                    _textureCopyShader.SetInt("TextureHeight", height);
                    _textureCopyShader.SetInt("TextureDataOffset", textureDataOffset);
                    _textureCopyShader.SetInt("TextureHasAlpha", hasAlpha ? 1 : 0);

                    int dispatchX = Mathf.CeilToInt(totalPixels / 128.0f);
                    _textureCopyShader.Dispatch(0, dispatchX, 1, 1);

                    textureDataOffset += totalPixels;
                }

                _textureDescriptorBuffer.SetData(textureDescriptorData);

                Debug.Log($"Total texture data size: {(totalTextureSize * 16):n0} bytes");
            }
            else
            {
                _textureDataBuffer?.Release();
                _textureDescriptorBuffer?.Release();
                _textureDataBuffer = null;
                _textureDescriptorBuffer = null;
            }
        }
    }

    public void ProcessMeshes()
    {
        _totalVertexCount = 0;
        _totalTriangleCount = 0;

        _meshes.Clear();
        _meshRenderers.Clear();
        _sceneMeshRenderers.Clear();
        _meshStartIndices.Clear();
        _meshTriangleCount.Clear();
        _materials.Clear();
        _triangleAttributeOffsets.Clear();
        _vertexPositionOffsets.Clear();

        // Populate list of mesh renderers to trace against
        var meshRenderers = UnityEngine.Object.FindObjectsByType<MeshRenderer>(FindObjectsSortMode.None);

        // Gather info on the meshes we'll be using
        foreach (MeshRenderer renderer in meshRenderers)
        {
            Mesh mesh = renderer.gameObject.GetComponent<MeshFilter>().sharedMesh;
            if (mesh == null)
                continue;

            _sceneMeshRenderers.Add(renderer);
#if USE_TLAS
            if (_meshes.Contains(mesh))
                continue;
#endif
            int triangleCount = Utilities.GetTriangleCount(mesh);

            _meshes.Add(mesh);
            _meshRenderers.Add(renderer);
            _meshStartIndices.Add(_totalTriangleCount);
            _meshTriangleCount.Add(triangleCount);

            _totalTriangleCount += triangleCount;
            _totalVertexCount += triangleCount * 3;
        }

        if (_totalVertexCount == 0)
        {
            Debug.LogError("No meshes found to process.");
            return;
        }

        Debug.Log($"Total Vertices: {_totalVertexCount:n0} Triangles: {_totalTriangleCount:n0}");

        // Allocate buffers
        _vertexPositionBufferGPU = new ComputeBuffer(_totalVertexCount, kVertexPositionSize);
        _vertexPositionBufferCPU = new NativeArray<Vector4>(_totalVertexCount * kVertexPositionSize, Allocator.Persistent);
        _triangleAttributesBuffer = new ComputeBuffer(_totalTriangleCount, kTriangleAttributeSize);

        int vertexOffset = 0;
        int triangleOffset = 0;

        // Gather the data for each mesh to pass to TinyBVH. This is done in a compute shader with async readback
        // to avoid each mesh having to have read/write access.
        for (int meshIndex = 0; meshIndex < _meshes.Count; ++meshIndex)
        {
            Mesh mesh = _meshes[meshIndex];
            int triangleCount = Utilities.GetTriangleCount(mesh);

#if USE_TLAS
            int materialIndex = 0; // materialIndex is stored in GPUInstance
#else
            MeshRenderer renderer = _meshRenderers[meshIndex];
            Material material = renderer.sharedMaterial;
            if (!_materials.Contains(material))
                _materials.Add(material);

            int materialIndex = _materials.IndexOf(material);
#endif

            Debug.Log($"Processing Mesh {meshIndex + 1}/{_meshes.Count} Triangles: {triangleCount:n0} Material: {materialIndex}");

            GraphicsBuffer vertexBuffer = mesh.GetVertexBuffer(0);
            GraphicsBuffer indexBuffer = mesh.GetIndexBuffer();

            // Determine where in the Unity vertex buffer each vertex attribute is
            Utilities.FindVertexAttribute(mesh, VertexAttribute.Position, out int positionOffset, out int vertexStride);
            Utilities.FindVertexAttribute(mesh, VertexAttribute.Normal, out int normalOffset, out vertexStride);
            Utilities.FindVertexAttribute(mesh, VertexAttribute.Tangent, out int tangentOffset, out vertexStride);
            Utilities.FindVertexAttribute(mesh, VertexAttribute.TexCoord0, out int uvOffset, out vertexStride);

            _triangleAttributeOffsets.Add(triangleOffset * kTriangleAttributeSize);
            _vertexPositionOffsets.Add(vertexOffset * kVertexPositionSize);

            _meshProcessingShader.SetBuffer(0, "VertexBuffer", vertexBuffer);
            if (indexBuffer != null)
                _meshProcessingShader.SetBuffer(0, "IndexBuffer", indexBuffer);
            _meshProcessingShader.SetBuffer(0, "VertexPositionBuffer", _vertexPositionBufferGPU);
            _meshProcessingShader.SetBuffer(0, "TriangleAttributesBuffer", _triangleAttributesBuffer);
            _meshProcessingShader.SetInt("VertexStride", vertexStride);
            _meshProcessingShader.SetInt("PositionOffset", positionOffset);
            _meshProcessingShader.SetInt("NormalOffset", normalOffset);
            _meshProcessingShader.SetInt("TangentOffset", tangentOffset);
            _meshProcessingShader.SetInt("UVOffset", uvOffset);
            _meshProcessingShader.SetInt("TriangleCount", triangleCount);
            _meshProcessingShader.SetInt("OutputTriangleStart", triangleOffset);
            _meshProcessingShader.SetInt("MaterialIndex", materialIndex);
#if USE_TLAS
            _meshProcessingShader.SetMatrix("LocalToWorld", Matrix4x4.identity);
#else
            _meshProcessingShader.SetMatrix("LocalToWorld", renderer.localToWorldMatrix);
#endif

            // Set keywords based on format/attributes of this mesh
            _meshProcessingShader.SetKeyword(_has32BitIndicesKeyword, mesh.indexFormat == IndexFormat.UInt32);
            _meshProcessingShader.SetKeyword(_hasNormalsKeyword, mesh.HasVertexAttribute(VertexAttribute.Normal));
            _meshProcessingShader.SetKeyword(_hasUVsKeyword, mesh.HasVertexAttribute(VertexAttribute.TexCoord0));
            _meshProcessingShader.SetKeyword(_hasTangentsKeyword, mesh.HasVertexAttribute(VertexAttribute.Tangent));
            _meshProcessingShader.SetKeyword(_hasIndexBufferKeyword, indexBuffer != null);

            int dispatchX = Mathf.CeilToInt(triangleCount / 64.0f);
            _meshProcessingShader.Dispatch(0, dispatchX, 1, 1);

            vertexBuffer?.Release();
            indexBuffer?.Release();

            triangleOffset += triangleCount;
            vertexOffset += triangleCount * 3;
        }

        Debug.Log($"Meshes processed.");

        // Initiate async readback of vertex buffer to pass to TinyBVH to build
        _readbackStartTime = DateTime.UtcNow;
        AsyncGPUReadback.RequestIntoNativeArray(ref _vertexPositionBufferCPU, _vertexPositionBufferGPU, OnCompleteReadback);
    }

    unsafe void OnCompleteReadback(AsyncGPUReadbackRequest request)
    {
        if (request.hasError)
        {
            Debug.LogError("Mesh GPU Readback Error.");
            return;
        }

        TimeSpan readbackTime = DateTime.UtcNow - _readbackStartTime;
        Debug.Log($"Mesh GPU Readback Took: {readbackTime.TotalMilliseconds:n0}ms");

        // In the editor if we exit play mode before the bvh is finished building the memory will be freed
        // and TinyBVH will illegal access and crash everything. 
        #if UNITY_EDITOR
            NativeArray<Vector4> persistentBuffer = new(_vertexPositionBufferCPU.Length, Allocator.Persistent);
            persistentBuffer.CopyFrom(_vertexPositionBufferCPU);
            IntPtr dataPointer = (IntPtr)NativeArrayUnsafeUtility.GetUnsafeReadOnlyPtr(persistentBuffer);
        #else
            IntPtr dataPointer = (IntPtr)NativeArrayUnsafeUtility.GetUnsafeReadOnlyPtr(_vertexPositionBufferCPU);
        #endif

        DateTime bvhStartTime = DateTime.UtcNow;

        int totalNodeSize = 0;
        int totalTriSize = 0;

        List<int> bvhList = new();
        List<int> nodeSizeList = new();
        List<int> triSizeList = new();

#if USE_TLAS
        for (int i = 0; i < _meshes.Count; i++)
        {
            int meshTriangleCount = _meshTriangleCount[i];
            int dataPointerOffset = _vertexPositionOffsets[i];

            MeshRenderer renderer = _meshRenderers[i];
            Debug.Log($"Building BVH for Mesh {i + 1}/{_meshes.Count} {renderer.gameObject.name} Triangles: {meshTriangleCount:n0} Offset: {dataPointerOffset:n0} / {_vertexPositionBufferCPU.Length:n0}");

            IntPtr meshPtr = IntPtr.Add(dataPointer, dataPointerOffset);

            int bvhIndex = TinyBVH.BuildBVH(meshPtr, meshTriangleCount);
            bvhList.Add(bvhIndex);

            // Get the sizes of the arrays
            int nodesSize = TinyBVH.GetCWBVHNodesSize(bvhIndex);
            int trisSize = TinyBVH.GetCWBVHTrisSize(bvhIndex);
            nodeSizeList.Add(nodesSize);
            triSizeList.Add(trisSize);

            totalNodeSize += nodesSize;
            totalTriSize += trisSize;
            Debug.Log($"BVH Nodes Size: {nodesSize:n0} Triangles Size: {trisSize:n0}");
        }
#else
        {
            int bvhIndex = TinyBVH.BuildBVH(dataPointer, _totalTriangleCount);
            bvhList.Add(bvhIndex);
            int nodesSize = TinyBVH.GetCWBVHNodesSize(bvhIndex);
            int trisSize = TinyBVH.GetCWBVHTrisSize(bvhIndex);
            nodeSizeList.Add(nodesSize);
            triSizeList.Add(trisSize);
            totalNodeSize += nodesSize;
            totalTriSize += trisSize;
            Debug.Log($"BVH Nodes Size: {nodesSize:n0} Triangles Size: {trisSize:n0}");
        }
#endif

        _bvhNodesBuffer = new ComputeBuffer(totalNodeSize / 4, 4);
        _bvhTrianglesBuffer = new ComputeBuffer(totalTriSize / 4, 4);

        List<int> nodeOffsetList = new();
        List<int> triOffsetList = new();

        int nodeOffset = 0;
        int triOffset = 0;
        for (int i = 0; i < bvhList.Count; ++i)
        {
            int bvhIndex = bvhList[i];
            int nodesSize = nodeSizeList[i];
            int trisSize = triSizeList[i];

            //Debug.Log($"Uploading BVH Data for Mesh {i + 1}/{_meshes.Count} Offset:{nodeOffset:n0}-{(nodeOffset + nodesSize):n0}/{totalNodeSize:n0} TriOffset:{triOffset:n0}-{(triOffset + trisSize):n0}/{totalTriSize:n0}");

            if (TinyBVH.GetCWBVHData(bvhIndex, out IntPtr nodesPtr, out IntPtr trisPtr))
            {
                Utilities.UploadFromPointer(ref _bvhNodesBuffer, nodesPtr, nodesSize, 4, totalNodeSize, nodeOffset);
                Utilities.UploadFromPointer(ref _bvhTrianglesBuffer, trisPtr, trisSize, 4, totalTriSize, triOffset);
            }

            nodeOffsetList.Add(nodeOffset);
            triOffsetList.Add(triOffset);

            nodeOffset += nodesSize;
            triOffset += trisSize;
        }

#if USE_TLAS
        _gpuInstances = new GPUInstance[_sceneMeshRenderers.Count];
        _blasInstances = new BLASInstance[_sceneMeshRenderers.Count];

        int totalInstancedTriangles = 0;

        for (int instanceIndex = 0; instanceIndex < _sceneMeshRenderers.Count; ++instanceIndex)
        {
            MeshRenderer renderer = _sceneMeshRenderers[instanceIndex];
            Mesh mesh = renderer.gameObject.GetComponent<MeshFilter>().sharedMesh;
            int meshIndex = _meshes.IndexOf(mesh);

            Material material = renderer.sharedMaterial;
            if (!_materials.Contains(material))
                _materials.Add(material);

            int materialIndex = _materials.IndexOf(material);

            Matrix4x4 transform = renderer.localToWorldMatrix;
            Matrix4x4 inverseTransform = renderer.worldToLocalMatrix;
            Bounds bounds = renderer.bounds;

            int bvhIndex = bvhList[meshIndex];
            _blasInstances[instanceIndex].transform = transform;
            _blasInstances[instanceIndex].inverseTransform = inverseTransform;
            _blasInstances[instanceIndex].aabbMin = bounds.min;
            _blasInstances[instanceIndex].blasIndex = bvhIndex;
            _blasInstances[instanceIndex].aabbMax = bounds.max;

            _gpuInstances[instanceIndex].materialIndex = materialIndex;
            _gpuInstances[instanceIndex].bvhOffset = nodeOffsetList[meshIndex] / kBVHNodeSize;
            _gpuInstances[instanceIndex].triOffset = triOffsetList[meshIndex] / kBVHTriSize;
            _gpuInstances[instanceIndex].triAttributeOffset = _triangleAttributeOffsets[meshIndex] / kTriangleAttributeSize;
            _gpuInstances[instanceIndex].transform = transform;
            _gpuInstances[instanceIndex].inverseTransform = inverseTransform;

            totalInstancedTriangles += _meshTriangleCount[meshIndex];
        }
#endif

        Debug.Log($"Total Materials: {_materials.Count} Buffer size: {_materials.Count * kMaterialSize * 4:n0} bytes");
        _materialsBuffer = new ComputeBuffer(_materials.Count, kMaterialSize * 4);
        UpdateMaterialData(true);

#if USE_TLAS
        _gpuInstancesBuffer = new ComputeBuffer(_gpuInstances.Length, kGPUInstanceSize);
        _gpuInstancesBuffer.SetData(_gpuInstances);
        _gpuInstanceCount = _gpuInstances.Length;

        NativeArray<BLASInstance> blasInstancesPtr = new(_blasInstances, Allocator.Persistent);
        IntPtr blasInstancesCPtr = (IntPtr)NativeArrayUnsafeUtility.GetUnsafeReadOnlyPtr(blasInstancesPtr);

        int tlasIndex = TinyBVH.BuildTLAS(blasInstancesCPtr, _blasInstances.Length);
        Debug.Log($"Total Instances: {_blasInstances.Length} Instanced Triangles: {totalInstancedTriangles:n0}");

        if (TinyBVH.GetTLASData(tlasIndex, out IntPtr tlasNodesPtr))
        {
            int tlasNodeSize = TinyBVH.GetTLASNodesSize(tlasIndex);
            Debug.Log($"TLAS Nodes Size: {tlasNodeSize:n0}  Buffer Size: {tlasNodeSize:n0} bytes");
            Utilities.UploadFromPointer(ref _tlasNodesBuffer, tlasNodesPtr, tlasNodeSize, 4);
        }

        blasInstancesPtr.Dispose();

        // We will rebuild a TLAS if the scene changes, so we don't need to keep the CPU memory of the current
        // TLAS, as the data has already been uploaded to the GPU.
        TinyBVH.DestroyTLAS(tlasIndex);

        // BVH data is now on the GPU, we can free the CPU memory
        for (int i = 0; i < bvhList.Count; ++i)
            TinyBVH.DestroyBVH(bvhList[i]);
#endif

        TimeSpan bvhTime = DateTime.UtcNow - bvhStartTime;

        Debug.Log($"Building BVH took: {bvhTime.TotalMilliseconds:n0}ms");

        #if UNITY_EDITOR
            persistentBuffer.Dispose();
        #endif
    }

    public unsafe bool UpdateTLAS()
    {
#if !USE_TLAS
        return false;
#else
        if (_sceneMeshRenderers == null || _gpuInstances == null)
            return false;

        bool isDirty = false;
        int instanceIndex = 0;
        foreach (MeshRenderer renderer in _sceneMeshRenderers)
        {
            Mesh mesh = renderer.gameObject.GetComponent<MeshFilter>().sharedMesh;
            if (mesh == null || !_meshes.Contains(mesh))
                continue;

            int meshIndex = _meshes.IndexOf(mesh);

            Matrix4x4 transform = renderer.localToWorldMatrix;

            // Check if the object's transform has changed since the last update.
            // If it hasn't, we don't need to update the TLAS.
            if (transform == _gpuInstances[instanceIndex].transform)
            {
                instanceIndex++;
                continue;
            }

            // A TLAS instance has been updated, we'll need to rebuild the TLAS structure.
            isDirty = true;

            Matrix4x4 inverseTransform = renderer.worldToLocalMatrix;

            Bounds bounds = renderer.bounds;

            _blasInstances[instanceIndex].transform = transform;
            _blasInstances[instanceIndex].inverseTransform = inverseTransform;
            _blasInstances[instanceIndex].aabbMin = bounds.min;
            _blasInstances[instanceIndex].aabbMax = bounds.max;

            _gpuInstances[instanceIndex].transform = transform;
            _gpuInstances[instanceIndex].inverseTransform = inverseTransform;

            instanceIndex++;
        }

        if (!isDirty)
            return false;

        _gpuInstancesBuffer.SetData(_gpuInstances);

        NativeArray<BLASInstance> blasInstancesPtr = new(_blasInstances, Allocator.Persistent);
        IntPtr blasInstancesCPtr = (IntPtr)NativeArrayUnsafeUtility.GetUnsafeReadOnlyPtr(blasInstancesPtr);

        int tlasIndex = TinyBVH.BuildTLAS(blasInstancesCPtr, _gpuInstanceCount);

        if (TinyBVH.GetTLASData(tlasIndex, out IntPtr tlasNodesPtr))
        {
            int tlasNodeSize = TinyBVH.GetTLASNodesSize(tlasIndex);
            Utilities.UploadFromPointer(ref _tlasNodesBuffer, tlasNodesPtr, tlasNodeSize, 4);
        }

        blasInstancesPtr.Dispose();

        TinyBVH.DestroyTLAS(tlasIndex);

        return true;
#endif
    }
}
