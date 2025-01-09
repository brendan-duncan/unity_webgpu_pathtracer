using System;
using System.Collections.Generic;
using Unity.Collections;
using Unity.Collections.LowLevel.Unsafe;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Experimental.Rendering;

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
    const int kBVHNodeSize = 80;
    const int kBVHTriSize = 16;
    // Number of float/uint values in material.hlsl
    const int kMaterialSize = 28;
    const int kTextureOffset = 24;

    List<Mesh> _meshes = new();
    List<int> _meshStartIndices = new();
    List<int> _meshTriangleCount = new();
    int _totalVertexCount2 = 0;
    int _totalTriangleCount2 = 0;
    DateTime _readbackStartTime2;
    ComputeBuffer _vertexPositionBufferGPU2;
    NativeArray<Vector4> _vertexPositionBufferCPU2;
    ComputeBuffer _triangleAttributesBuffer2;
    ComputeBuffer _bvhNodesBuffer2;
    ComputeBuffer _bvhTrianglesBuffer2;

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

        //ProcessMeshes2();
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

        _vertexPositionBufferGPU2?.Release();
        _triangleAttributesBuffer2?.Release();
        _vertexPositionBufferCPU2.Dispose();
        _bvhNodesBuffer2?.Release();
        _bvhTrianglesBuffer2?.Release();
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

        cmd.SetComputeBufferParam(shader, kernelIndex, "BVHNodes", _bvhNodesBuffer);
        cmd.SetComputeBufferParam(shader, kernelIndex, "BVHTris", _bvhTrianglesBuffer);
        cmd.SetComputeBufferParam(shader, kernelIndex, "TriangleAttributesBuffer", _triangleAttributesBuffer);
        cmd.SetComputeBufferParam(shader, kernelIndex, "Materials", _materialsBuffer);
        cmd.SetComputeIntParam(shader, "TriangleCount", 2);

        if (_textureDataBuffer != null)
        {
            cmd.SetComputeBufferParam(shader, kernelIndex, "TextureDescriptors", _textureDescriptorBuffer);
            cmd.SetComputeBufferParam(shader, kernelIndex, "TextureData", _textureDataBuffer);
        }
    }

    public void UpdateMaterialData(bool updateTextures)
    {
        List<Texture> textures = new();
        float[] materialData = new float[_materials.Count * kMaterialSize];
        for (int i = 0; i < _materials.Count; i++)
        {
            Color baseColor = 
                _materials[i].HasProperty("_Color") ? _materials[i].color
                : _materials[i].HasProperty("baseColorFactor") ? _materials[i].GetColor("baseColorFactor")
                : new Color(0.8f, 0.8f, 0.8f, 1.0f);
            Color emission = 
                _materials[i].HasProperty("_EmissionColor") ? _materials[i].GetColor("_EmissionColor")
                : _materials[i].HasProperty("emissiveFactor") ? _materials[i].GetColor("emissiveFactor")
                : Color.black;
            float metallic = 
                _materials[i].HasProperty("_Metallic") ? _materials[i].GetFloat("_Metallic")
                : _materials[i].HasProperty("metallicFactor") ? _materials[i].GetFloat("metallicFactor")
                : 0.0f;
            float roughness =
                _materials[i].HasProperty("_Glossiness") ? 1.0f - _materials[i].GetFloat("_Glossiness")
                : _materials[i].HasProperty("roughnessFactor") ? _materials[i].GetFloat("roughnessFactor")
                : 0.0f;
            float ior = 
                _materials[i].HasProperty("_IOR") ? _materials[i].GetFloat("_IOR")
                : _materials[i].HasProperty("ior") ? _materials[i].GetFloat("ior")
                : 1.0f;
            float normalScale = 
                _materials[i].HasProperty("_BumpScale") ? _materials[i].GetFloat("_BumpScale")
                : _materials[i].HasProperty("normalScale") ? _materials[i].GetFloat("normalScale")
                : 1.0f;
            int alphaMode = 
                _materials[i].HasProperty("_Mode") ? ((int)_materials[i].GetFloat("_Mode") == 1 ? 2 : 0)
                : _materials[i].HasProperty("alphaMode") ? (int)_materials[i].GetFloat("alphaMode")
                : 0;
            float alphaCutoff = 
                _materials[i].HasProperty("_Cutoff") ? _materials[i].GetFloat("_Cutoff")
                : _materials[i].HasProperty("alphaCutoff") ? _materials[i].GetFloat("alphaCutoff")
                : 0.5f;
            float anisotropic = 
                _materials[i].HasProperty("anisotropicFactor") ? _materials[i].GetFloat("anisotropicFactor")
                : 0.0f;
            float specular = 
                _materials[i].HasProperty("specularFactor") ? _materials[i].GetFloat("specularFactor")
                : 0.0f;
            float specularTint = 
                _materials[i].HasProperty("specularTint") ? _materials[i].GetFloat("specularTint")
                : 0.0f;
            float sheen = 
                _materials[i].HasProperty("sheenFactor") ? _materials[i].GetFloat("sheenFactor")
                : 0.0f;
            float sheenTint =
                _materials[i].HasProperty("sheenTint") ? _materials[i].GetFloat("sheenTint")
                : 0.0f;
            float subsurface =
                _materials[i].HasProperty("subsurfaceFactor") ? _materials[i].GetFloat("subsurfaceFactor")
                : 0.0f;
            float clearCoat =
                _materials[i].HasProperty("clearCoatFactor") ? _materials[i].GetFloat("clearCoatFactor")
                : 0.0f;
            float clearCoatGloss =
                _materials[i].HasProperty("clearCoatGloss") ? _materials[i].GetFloat("clearCoatGloss")
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

            // BaseColor texture
            Texture mainTex = _materials[i].HasProperty("_MainTex") ? _materials[i].GetTexture("_MainTex")
                : _materials[i].HasProperty("baseColorTexture") ? _materials[i].GetTexture("baseColorTexture")
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
            Texture metallicRoughnessTex = _materials[i].HasProperty("_MetallicRoughnessMap") ? _materials[i].GetTexture("_MetallicRoughnessMap")
                : _materials[i].HasProperty("metallicRoughnessTexture") ? _materials[i].GetTexture("metallicRoughnessTexture")
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
            Texture normalTex = _materials[i].HasProperty("_BumpMap") ? _materials[i].GetTexture("_BumpMap")
                : _materials[i].HasProperty("normalTexture") ? _materials[i].GetTexture("normalTexture")
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
            Texture emissionTex = _materials[i].HasProperty("_EmissionMap") ? _materials[i].GetTexture("_EmissionMap")
                : _materials[i].HasProperty("emissiveTexture") ? _materials[i].GetTexture("emissiveTexture")
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

    public void ProcessMeshes2()
    {
        _totalVertexCount2 = 0;
        _totalTriangleCount2 = 0;

        // Populate list of mesh renderers to trace against
        var meshRenderers = UnityEngine.Object.FindObjectsByType<MeshRenderer>(FindObjectsSortMode.None);

        _meshes.Clear();
        _meshStartIndices.Clear();
        _meshTriangleCount.Clear();

        // Gather info on the meshes we'll be using
        foreach (MeshRenderer renderer in meshRenderers)
        {
            Mesh mesh = renderer.gameObject.GetComponent<MeshFilter>().sharedMesh;
            if (mesh == null || _meshes.Contains(mesh))
                continue;

            int triangleCount = Utilities.GetTriangleCount(mesh);

            _meshes.Add(mesh);
            _meshStartIndices.Add(_totalTriangleCount2);
            _meshTriangleCount.Add(triangleCount);

            _totalVertexCount2 += triangleCount * 3;
        }

        if (_totalVertexCount2 == 0)
        {
            Debug.LogError("No meshes found to process.");
            return;
        }

        Debug.Log($"Total Vertices: {_totalVertexCount2:n0} Triangles: {_totalTriangleCount2:n0}");

        // Allocate buffers
        _vertexPositionBufferGPU2 = new ComputeBuffer(_totalVertexCount2, kVertexPositionSize);
        _vertexPositionBufferCPU2 = new NativeArray<Vector4>(_totalVertexCount2 * kVertexPositionSize, Allocator.Persistent);
        _triangleAttributesBuffer2 = new ComputeBuffer(_totalVertexCount2 / 3, kTriangleAttributeSize);

        int meshIndex = 0;

        // Gather the data for each mesh to pass to TinyBVH. This is done in a compute shader with async readback
        // to avoid each mesh having to have read/write access.
        foreach (Mesh mesh in _meshes)
        {
            int triangleCount = Utilities.GetTriangleCount(mesh);

            Debug.Log($"Processing Mesh {meshIndex + 1}/{_meshes.Count} Triangles: {triangleCount:n0}");

            GraphicsBuffer vertexBuffer = mesh.GetVertexBuffer(0);
            GraphicsBuffer indexBuffer = mesh.GetIndexBuffer();

            // Determine where in the Unity vertex buffer each vertex attribute is
            //int vertexStride, positionOffset, normalOffset, uvOffset, tangentOffset;
            Utilities.FindVertexAttribute(mesh, VertexAttribute.Position, out int positionOffset, out int vertexStride);
            Utilities.FindVertexAttribute(mesh, VertexAttribute.Normal, out int normalOffset, out vertexStride);
            Utilities.FindVertexAttribute(mesh, VertexAttribute.Tangent, out int tangentOffset, out vertexStride);
            Utilities.FindVertexAttribute(mesh, VertexAttribute.TexCoord0, out int uvOffset, out vertexStride);

            // Material will be stored in the TLAS instance info
            int materialIndex = -1;

            _meshProcessingShader.SetBuffer(0, "VertexBuffer", vertexBuffer);
            if (indexBuffer != null)
                _meshProcessingShader.SetBuffer(0, "IndexBuffer", indexBuffer);
            _meshProcessingShader.SetBuffer(0, "VertexPositionBuffer", _vertexPositionBufferGPU2);
            _meshProcessingShader.SetBuffer(0, "TriangleAttributesBuffer", _triangleAttributesBuffer2);
            _meshProcessingShader.SetInt("VertexStride", vertexStride);
            _meshProcessingShader.SetInt("PositionOffset", positionOffset);
            _meshProcessingShader.SetInt("NormalOffset", normalOffset);
            _meshProcessingShader.SetInt("TangentOffset", tangentOffset);
            _meshProcessingShader.SetInt("UVOffset", uvOffset);
            _meshProcessingShader.SetInt("TriangleCount", triangleCount);
            _meshProcessingShader.SetInt("OutputTriangleStart", _totalTriangleCount2);
            _meshProcessingShader.SetInt("MaterialIndex", materialIndex);
            _meshProcessingShader.SetMatrix("LocalToWorld", Matrix4x4.identity);

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

            _totalTriangleCount2 += triangleCount;
        }

        Debug.Log($"Meshes processed.");

        // Initiate async readback of vertex buffer to pass to TinyBVH to build
        _readbackStartTime2 = DateTime.UtcNow;
        AsyncGPUReadback.RequestIntoNativeArray(ref _vertexPositionBufferCPU2, _vertexPositionBufferGPU2, OnCompleteReadback2);
    }

    unsafe void OnCompleteReadback2(AsyncGPUReadbackRequest request)
    {
        if (request.hasError)
        {
            Debug.LogError("Mesh GPU Readback Error.");
            return;
        }

        TimeSpan readbackTime = DateTime.UtcNow - _readbackStartTime2;
        Debug.Log($"Mesh GPU Readback Took: {readbackTime.TotalMilliseconds:n0}ms");

        // In the editor if we exit play mode before the bvh is finished building the memory will be freed
        // and TinyBVH will illegal access and crash everything. 
        #if UNITY_EDITOR
            NativeArray<Vector4> persistentBuffer = new(_vertexPositionBufferCPU2.Length, Allocator.Persistent);
            persistentBuffer.CopyFrom(_vertexPositionBufferCPU2);
            IntPtr dataPointer = (IntPtr)NativeArrayUnsafeUtility.GetUnsafeReadOnlyPtr(persistentBuffer);
        #else
            IntPtr dataPointer = (IntPtr)NativeArrayUnsafeUtility.GetUnsafeReadOnlyPtr(_vertexPositionBufferCPU2);
        #endif

        DateTime bvhStartTime = DateTime.UtcNow;

        int totalNodeSize = 0;
        int totalTriSize = 0;

        List<int> bvhList = new();

        for (int i = 0; i < _meshes.Count; i++)
        {
            int meshStartIndex = _meshStartIndices[i];
            int meshTriangleCount = _meshTriangleCount[i];
            int dataPointerOffset = meshStartIndex * 4 * 4 * 3;

            Debug.Log($"Building BVH for Mesh {i + 1}/{_meshes.Count} Triangles: {meshTriangleCount:n0} Offset: {dataPointerOffset:n0}");

            IntPtr meshPtr = IntPtr.Add(dataPointer, dataPointerOffset);

            int bvhIndex = TinyBVH.BuildBVH(meshPtr, meshTriangleCount);
            bvhList.Add(bvhIndex);

            // Get the sizes of the arrays
            int nodesSize = TinyBVH.GetCWBVHNodesSize(bvhIndex);
            int trisSize = TinyBVH.GetCWBVHTrisSize(bvhIndex);

            Debug.Log($"!!!! BVH Data Size: nodeSize:{nodesSize:n0} triangleSize:{trisSize:n0}");

            totalNodeSize += nodesSize;
            totalTriSize += trisSize;
        }

        Debug.Log($"!!!! Total BVH Data Size: nodeSize:{totalNodeSize:n0} triangleSize:{totalTriSize:n0}");
        _bvhNodesBuffer2 = new ComputeBuffer(totalNodeSize / 4, 4);
        _bvhTrianglesBuffer2 = new ComputeBuffer(totalTriSize / 4, 4);

        int nodeOffset = 0;
        int triOffset = 0;
        for (int i = 0; i < bvhList.Count; ++i)
        {
            int bvhIndex = bvhList[i];
            int nodesSize = TinyBVH.GetCWBVHNodesSize(bvhIndex);
            int trisSize = TinyBVH.GetCWBVHTrisSize(bvhIndex);

            if (TinyBVH.GetCWBVHData(bvhIndex, out IntPtr nodesPtr, out IntPtr trisPtr))
            {
                Utilities.UploadFromPointer2(ref _bvhNodesBuffer2, nodesPtr, nodesSize, 4/*kBVHNodeSize*/, totalNodeSize, nodeOffset);
                Utilities.UploadFromPointer2(ref _bvhTrianglesBuffer2, trisPtr, trisSize, /*kBVHTriSize*/4, totalTriSize, triOffset);
            }

            nodeOffset += nodesSize;
            triOffset += trisSize;

            TinyBVH.DestroyBVH(bvhIndex);
        }

        TimeSpan bvhTime = DateTime.UtcNow - bvhStartTime;

        Debug.Log($"Building BVH took: {bvhTime.TotalMilliseconds:n0}ms");

        #if UNITY_EDITOR
            persistentBuffer.Dispose();
        #endif
    }

    public void ProcessMeshes()
    {
        _totalVertexCount = 0;
        _totalTriangleCount = 0;

        // Populate list of mesh renderers to trace against
        var meshRenderers = UnityEngine.Object.FindObjectsByType<MeshRenderer>(FindObjectsSortMode.None);

        // Gather info on the meshes we'll be using
        foreach (MeshRenderer renderer in meshRenderers)
        {
            Mesh mesh = renderer.gameObject.GetComponent<MeshFilter>().sharedMesh;
            if (mesh == null)
                continue;

            _totalVertexCount += Utilities.GetTriangleCount(mesh) * 3;
        }

        if (_totalVertexCount == 0)
        {
            Debug.LogError("No meshes found to process.");
            return;
        }

        // Allocate buffers
        _vertexPositionBufferGPU = new ComputeBuffer(_totalVertexCount, kVertexPositionSize);
        _vertexPositionBufferCPU = new NativeArray<Vector4>(_totalVertexCount * kVertexPositionSize, Allocator.Persistent);
        _triangleAttributesBuffer = new ComputeBuffer(_totalVertexCount / 3, kTriangleAttributeSize);

        _materials.Clear();

        // Gather the data for each mesh to pass to tinybvh. This is done in a compute shader with async readback
        // to avoid each mesh having to have read/write access.
        foreach (MeshRenderer renderer in meshRenderers)
        {
            Mesh mesh = renderer.gameObject.GetComponent<MeshFilter>().sharedMesh;
            if (mesh == null)
                continue;

            Material material = renderer.material;
            if (!_materials.Contains(material))
                _materials.Add(material);

            int materialIndex = _materials.IndexOf(material);

            Debug.Log($"Processing mesh: {renderer.gameObject.name}");

            GraphicsBuffer vertexBuffer = mesh.GetVertexBuffer(0);
            GraphicsBuffer indexBuffer = mesh.GetIndexBuffer();

            int triangleCount = Utilities.GetTriangleCount(mesh);

            // Determine where in the Unity vertex buffer each vertex attribute is
            int vertexStride, positionOffset, normalOffset, uvOffset, tangentOffset;
            Utilities.FindVertexAttribute(mesh, VertexAttribute.Position, out positionOffset, out vertexStride);
            Utilities.FindVertexAttribute(mesh, VertexAttribute.Normal, out normalOffset, out vertexStride);
            Utilities.FindVertexAttribute(mesh, VertexAttribute.Tangent, out tangentOffset, out vertexStride);
            Utilities.FindVertexAttribute(mesh, VertexAttribute.TexCoord0, out uvOffset, out vertexStride);

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
            _meshProcessingShader.SetInt("OutputTriangleStart", _totalTriangleCount);
            _meshProcessingShader.SetInt("MaterialIndex", materialIndex);
            _meshProcessingShader.SetMatrix("LocalToWorld", renderer.localToWorldMatrix);

            // Set keywords based on format/attributes of this mesh
            _meshProcessingShader.SetKeyword(_has32BitIndicesKeyword, mesh.indexFormat == IndexFormat.UInt32);
            _meshProcessingShader.SetKeyword(_hasNormalsKeyword, mesh.HasVertexAttribute(VertexAttribute.Normal));
            _meshProcessingShader.SetKeyword(_hasUVsKeyword, mesh.HasVertexAttribute(VertexAttribute.TexCoord0));
            _meshProcessingShader.SetKeyword(_hasTangentsKeyword, mesh.HasVertexAttribute(VertexAttribute.Tangent));
            _meshProcessingShader.SetKeyword(_hasIndexBufferKeyword, indexBuffer != null);

            _meshProcessingShader.Dispatch(0, Mathf.CeilToInt(triangleCount / 64.0f), 1, 1);

            _totalTriangleCount += triangleCount;

            vertexBuffer?.Release();
            indexBuffer?.Release();
        }

        Debug.Log($"Meshes processed. Total triangles: {_totalTriangleCount:n0}");

        List<Texture> textures = new();

        _materialsBuffer = new ComputeBuffer(_materials.Count, kMaterialSize * 4);

        Debug.Log($"Total _materials: {_materials.Count}");

        UpdateMaterialData(true);

        // Initiate async readback of vertex buffer to pass to tinybvh to build
        _readbackStartTime = DateTime.UtcNow;
        AsyncGPUReadback.RequestIntoNativeArray(ref _vertexPositionBufferCPU, _vertexPositionBufferGPU, OnCompleteReadback);
    }

    unsafe void OnCompleteReadback(AsyncGPUReadbackRequest request)
    {
        if (request.hasError)
        {
            Debug.LogError("GPU readback error.");
            return;
        }

        TimeSpan readbackTime = DateTime.UtcNow - _readbackStartTime;
        Debug.Log($"GPU readback took: {readbackTime.TotalMilliseconds:n0}ms");

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
        int bvhIndex = TinyBVH.BuildBVH(dataPointer, _totalTriangleCount);
        TimeSpan bvhTime = DateTime.UtcNow - bvhStartTime;

        Debug.Log($"Building BVH took: {bvhTime.TotalMilliseconds:n0}ms");

        #if UNITY_EDITOR
            persistentBuffer.Dispose();
        #endif

        // Get the sizes of the arrays
        int nodesSize = TinyBVH.GetCWBVHNodesSize(bvhIndex);
        int trisSize = TinyBVH.GetCWBVHTrisSize(bvhIndex);

        if (TinyBVH.GetCWBVHData(bvhIndex, out IntPtr nodesPtr, out IntPtr trisPtr))
        {
            Utilities.UploadFromPointer(ref _bvhNodesBuffer, nodesPtr, nodesSize, kBVHNodeSize);
            Utilities.UploadFromPointer(ref _bvhTrianglesBuffer, trisPtr, trisSize, kBVHTriSize);
            Debug.Log("BVH Uploaded");
        } 
        else
        {
            Debug.LogError("Failed to fetch updated BVH data.");
        }

        // We're all done with this BVH data
        TinyBVH.DestroyBVH(bvhIndex);
    }
}
