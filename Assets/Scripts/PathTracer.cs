using System;
using System.Collections.Generic;
using Unity.Collections;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Experimental;

public enum TonemapMode {
    None = 0,
    Aces = 1,
    Filmic = 2,
    Reinhard = 3,
    Lottes = 4
}

public enum EnvironmentMode {
    Environment,
    Basic,
}

[RequireComponent(typeof(Camera))]
public class PathTracer : MonoBehaviour
{
    public int samplesPerPass = 1;
    public int maxSamples = 100000;
    public int maxRayBounces = 5;
    public bool backfaceCulling = false;
    public float focalLength = 10.0f;
    public float aperture = 0.0f;
    public float skyTurbidity = 1.0f;
    public EnvironmentMode environmentMode = EnvironmentMode.Environment;
    public Color environmentColor = Color.white;
    public float environmentIntensity = 1.0f;
    public Texture2D environmentTexture;
    public float environmentMapRotation = 0.0f;
    public float exposure = 1.0f;
    public TonemapMode tonemapMode = TonemapMode.Lottes;
    public bool sRGB = false;

    LocalKeyword _hasTexturesKeyword;
    LocalKeyword _hasEnvironmentTextureKeyword;
    LocalKeyword _hasLightsKeyword;

    Camera _camera;
    BVHScene _bvhScene;
    CommandBuffer _cmd;

    ComputeShader _pathTracerShader;
    Material _presentationMaterial;

    int _outputWidth;
    int _outputHeight;
    RenderTexture[] _outputRT = { null, null };
    ComputeBuffer _rngStateBuffer;

    //ComputeBuffer _skyStateBuffer;
    //SkyState _skyState;
    ComputeBuffer _environmentCdfBuffer;
    NativeArray<Color> _envTextureCPU;
    RenderTexture _envTextureCopy;
    DateTime _environmentReadbackStartTime;
    bool _environmentTextureReady = false;

    float _lastEnvironmentMapRotation = 0.0f;
    float _lastAperture = 0.0f;
    float _lastFocalLength = 0.0f;

    int _currentRT = 0;
    int _currentSample = 0;

    Vector3 _lightDirection = new Vector3(1.0f, 1.0f, 1.0f).normalized;
    Vector4 _lightColor = new Vector4(1.0f, 1.0f, 1.0f, 1.0f);

    Light[] _lights;
    ComputeBuffer _lightBuffer;
    float[] _lightData;
    int _lightCount = 0;

    // Struct sizes in bytes
    const int RayStructSize = 24;
    const int RayHitStructSize = 20;
    const int LightStructSize = 16;

    Matrix4x4 _cameraToWorldMatrix;
    Matrix4x4 _cameraProjectionMatrix;

    void Start()
    {
        _camera = GetComponent<Camera>();

        // Disable normal camera rendering since we will be replacing the image with our own
        _camera.cullingMask = 0;
        _camera.clearFlags = CameraClearFlags.SolidColor;

        _bvhScene = new BVHScene();
        _cmd = new CommandBuffer();

        _bvhScene.Start();

        _pathTracerShader = Resources.Load<ComputeShader>("PathTracer");
        _presentationMaterial = new Material(Resources.Load<Shader>("Presentation"));

        _hasTexturesKeyword = _pathTracerShader.keywordSpace.FindKeyword("HAS_TEXTURES");
        _hasEnvironmentTextureKeyword = _pathTracerShader.keywordSpace.FindKeyword("HAS_ENVIRONMENT_TEXTURE");
        _hasLightsKeyword = _pathTracerShader.keywordSpace.FindKeyword("HAS_LIGHTS");

        _lastEnvironmentMapRotation = environmentMapRotation;
        _lastAperture = aperture;
        _lastFocalLength = focalLength;

        //bool hasLight = false;
        Light[] lights = FindObjectsByType<Light>(FindObjectsSortMode.None);
        foreach (Light light in lights)
        {
            if (light.type == LightType.Directional)
            {
                _lightDirection = -light.transform.forward;
                _lightColor = light.color * light.intensity;
                //hasLight = true;
                break;
            }
        }

        _lightDirection.Normalize();

        //_skyStateBuffer = new ComputeBuffer(40, 4);
        //_skyState = new SkyState();
        float[] direction = { _lightDirection.x, _lightDirection.y, _lightDirection.z };
        float[] groundAlbedo = { 1.0f, 1.0f, 1.0f };

        //_skyState.Init(direction, groundAlbedo, skyTurbidity);
        //_skyState.UpdateBuffer(_skyStateBuffer);

        if (environmentTexture != null)
        {
            _environmentReadbackStartTime = DateTime.Now;
            _environmentTextureReady = false;
            _pathTracerShader.EnableKeyword(_hasEnvironmentTextureKeyword);

            // We need to be able to read the data from the environment texture on the CPU.
            // There are a lot of restrictions for texture format types, partuclarly for compressed formats.
            // Blit the teture to a render texture, which decompressed any potentially compressed formats.
            // AsyncGPUReadback then needs to be used to copy the GPU texture to the CPU.
            // TODO This adds quite a bit to the start-up time, we could check if the texture is read-write and already ARGBFloat and read it directly.
            Utilities.PrepareRenderTexture(ref _envTextureCopy, environmentTexture.width, environmentTexture.height, RenderTextureFormat.ARGBFloat);
            Graphics.Blit(environmentTexture, _envTextureCopy);

            _pathTracerShader.SetTexture(0, "EnvironmentTexture", _envTextureCopy);
            
            _envTextureCPU = new NativeArray<Color>(environmentTexture.width * environmentTexture.height, Allocator.Persistent, NativeArrayOptions.UninitializedMemory);
            const int mipLevel = 0;
            const TextureFormat format = TextureFormat.RGBAFloat;
            AsyncGPUReadback.RequestIntoNativeArray(ref _envTextureCPU, _envTextureCopy, mipLevel, format, OnEnvTexReadback);
        }
        else
        {
            _environmentTextureReady = true;
            _pathTracerShader.DisableKeyword(_hasEnvironmentTextureKeyword);
        }

        UpdateLights();
    }

    unsafe void OnEnvTexReadback(AsyncGPUReadbackRequest request)
    {
        if (request.hasError)
        {
            _envTextureCPU.Dispose();
            Debug.LogError("GPU readback error detected.");
            return;
        }

        if (request.done)
        {
            DateTime endTime = DateTime.Now;
            TimeSpan duration = endTime - _environmentReadbackStartTime;

            Debug.Log($"EnvironmentTexture GPU readback completed in {duration.TotalMilliseconds:n0}ms");
            var data = request.GetData<Color>();

            _environmentCdfBuffer = new ComputeBuffer(data.Length, 4);
            float[] cdf = new float[data.Length];
            float sum = 0.0f;
            for (int i = 0; i < data.Length; i++)
            {
                sum += data[i].grayscale;
                cdf[i] = sum;
            }
            _environmentCdfBuffer.SetData(cdf);
            _pathTracerShader.SetInt("EnvironmentTextureWidth", environmentTexture.width);
            _pathTracerShader.SetInt("EnvironmentTextureHeight", environmentTexture.height);
            _pathTracerShader.SetBuffer(0, "EnvironmentCDF", _environmentCdfBuffer);
            _pathTracerShader.SetFloat("EnvironmentCdfSum", sum);
            _environmentTextureReady = true;

            _envTextureCPU.Dispose();
        }
    }

    void OnDestroy()
    {
        _bvhScene?.OnDestroy();
        _bvhScene = null;
        _rngStateBuffer?.Release();
        _outputRT[0]?.Release();
        _outputRT[1]?.Release();
        _cmd?.Release();
        //_skyStateBuffer?.Release();
        _environmentCdfBuffer?.Release();
        _envTextureCopy?.Release();
        _envTextureCopy = null;
        _lightBuffer?.Release();
    }

    void Update()
    {
        if (_bvhScene.UpdateTLAS())
            Reset();

        if (_lastEnvironmentMapRotation != environmentMapRotation ||
            _lastAperture != aperture ||
            _lastFocalLength != focalLength)
        {
            _lastEnvironmentMapRotation = environmentMapRotation;
            _lastAperture = aperture;
            _lastFocalLength = focalLength;
            Reset();
        }

        _pathTracerShader.DisableKeyword(_hasLightsKeyword);
        //UpdateLights();

        _bvhScene.Update();
        _pathTracerShader.SetKeyword(_hasTexturesKeyword, _bvhScene.HasTextures());
    }

    public void Reset()
    {
        _currentSample = 0;
    }

    public void UpdateLights()
    {
        _lights = FindObjectsByType<Light>(FindObjectsSortMode.None);
        if (_lights.Length == 0)
        {
            _pathTracerShader.DisableKeyword(_hasLightsKeyword);
            if (_lightCount > 0)
            {
                _lightBuffer.Release();
                _lightBuffer = null;
                _lightCount = 0;
                Reset();
            }
            return;
        }

        if (_lightBuffer != null && _lightCount != _lights.Length)
        {
            _lightBuffer.Release();
            _lightBuffer = null;
            Reset();
        }

        Utilities.PrepareBuffer(ref _lightBuffer, _lights.Length, LightStructSize * 4);

        if (_lightData == null || _lightCount != _lights.Length)
        {
            _lightData = new float[_lights.Length * LightStructSize];
            Reset();
        }

        bool dirty = false;

        _lightCount = _lights.Length;
        for (int i = 0; i < _lights.Length; ++i)
        {
            Light light = _lights[i];
            int li = i * LightStructSize;

            Vector3 lightPosition = light.transform.position;
            Vector3 u = light.transform.right.normalized * light.areaSize.x;
            Vector3 v = light.transform.up.normalized * light.areaSize.y; 
            float area = light.areaSize.x * light.areaSize.y;

            if (_lightData[li + 0] != lightPosition.x || _lightData[li + 1] != lightPosition.y || _lightData[li + 2] != lightPosition.z ||
                _lightData[li + 3] != (float)light.type || _lightData[li + 4] != light.color.r * light.intensity ||
                _lightData[li + 5] != light.color.g * light.intensity || _lightData[li + 6] != light.color.b * light.intensity ||
                _lightData[li + 7] != light.range || _lightData[li + 8] != u.x || _lightData[li + 9] != u.y || _lightData[li + 10] != u.z ||
                _lightData[li + 11] != area || _lightData[li + 12] != v.x || _lightData[li + 13] != v.y || _lightData[li + 14] != v.z)
            {
                dirty = true;
            }

            _lightData[li + 0] = lightPosition.x;
            _lightData[li + 1] = lightPosition.y;
            _lightData[li + 2] = lightPosition.z;
            _lightData[li + 3] = (float)light.type;

            _lightData[li + 4] = light.color.r * light.intensity;
            _lightData[li + 5] = light.color.g * light.intensity;
            _lightData[li + 6] = light.color.b * light.intensity;
            _lightData[li + 7] = light.range;

            _lightData[li + 8] = u.x;
            _lightData[li + 9] = u.y;
            _lightData[li + 10] = u.z;
            _lightData[li + 11] = area;

            _lightData[li + 12] = v.x;
            _lightData[li + 13] = v.y;
            _lightData[li + 14] = v.z;
            _lightData[li + 15] = light.spotAngle;
        }

        if (dirty)
        {
            _lightBuffer.SetData(_lightData);
            Reset();
        }

        _pathTracerShader.EnableKeyword(_hasLightsKeyword);
        _pathTracerShader.SetInt("LightCount", _lights.Length);
        _pathTracerShader.SetBuffer(0, "Lights", _lightBuffer);
    }

    public void UpdateMaterialData()
    {
        _bvhScene.UpdateMaterialData(false);
        Reset();
    }

    void OnRenderImage(RenderTexture source, RenderTexture destination)
    {
        if (!_bvhScene.CanRender() || !_environmentTextureReady)
        {
            Graphics.Blit(source, destination);
            return;
        }

        _outputWidth = _camera.scaledPixelWidth;
        _outputHeight = _camera.scaledPixelHeight;
        int totalPixels = _outputWidth * _outputHeight;

        // Using a 2D dispatch causes a warning for exceeding the number of temp variable registers.
        // Using a 1D dispatch instead.
        int dispatchX = Mathf.CeilToInt(totalPixels / 128.0f);
        int dispatchY = 1;

        Vector3 lastDirection = _lightDirection;
        Light[] lights = FindObjectsByType<Light>(FindObjectsSortMode.None);
        foreach (Light light in lights)
        {
            if (light.type == LightType.Directional)
            {
                _lightDirection = -light.transform.forward;
                _lightColor = light.color * light.intensity;
                break;
            }
        }

        /*if ((lastDirection - _lightDirection).sqrMagnitude > 0.0001f)
        {
            _skyState.Init(new float[] { _lightDirection.x, _lightDirection.y, _lightDirection.z }, new float[] { 0.3f, 0.2f, 0.1f }, skyTurbidity);
            _skyState.UpdateBuffer(_skyStateBuffer);
            Reset();
        }*/

        // Prepare buffers and output texture
        if (Utilities.PrepareRenderTexture(ref _outputRT[0], _outputWidth, _outputHeight, RenderTextureFormat.ARGBFloat))
            Reset();

        if (Utilities.PrepareRenderTexture(ref _outputRT[1], _outputWidth, _outputHeight, RenderTextureFormat.ARGBFloat))
            Reset();

        if (_rngStateBuffer != null && (_rngStateBuffer.count != totalPixels || _currentSample == 0))
        {
            _rngStateBuffer?.Release();
            _rngStateBuffer = null;
        }

        if (_rngStateBuffer == null)
        {
            _rngStateBuffer = new ComputeBuffer(totalPixels, 4);
            // Initialize the random number generator state buffer to random values
            uint[] rngStateData = new uint[totalPixels];
            for (int i = 0; i < totalPixels; i++)
                rngStateData[i] = (uint)UnityEngine.Random.Range(0, uint.MaxValue);
            _rngStateBuffer.SetData(rngStateData);
        }

        if (_cameraToWorldMatrix != _camera.cameraToWorldMatrix || _cameraProjectionMatrix != _camera.projectionMatrix)
        {
            _cameraToWorldMatrix = _camera.cameraToWorldMatrix;
            _cameraProjectionMatrix = _camera.projectionMatrix;
            Reset();
        }

        if (_currentSample < maxSamples)
        {
            _cmd.BeginSample("Path Tracer");
            {
                PrepareShader(_cmd, _pathTracerShader, 0);
                _bvhScene.PrepareShader(_cmd, _pathTracerShader, 0);
                _cmd.SetComputeMatrixParam(_pathTracerShader, "CamInvProj", _cameraProjectionMatrix.inverse);
                _cmd.SetComputeMatrixParam(_pathTracerShader, "CamToWorld", _cameraToWorldMatrix);

                _cmd.DispatchCompute(_pathTracerShader, 0, dispatchX, dispatchY, 1);
            }
            _cmd.EndSample("Path Tracer");
        }

        _presentationMaterial.SetTexture("_MainTex", _outputRT[_currentRT]);
        _presentationMaterial.SetInt("OutputWidth", _outputWidth);
        _presentationMaterial.SetInt("OutputHeight", _outputHeight);
        _presentationMaterial.SetFloat("Exposure", exposure);
        _presentationMaterial.SetInt("Mode", (int)tonemapMode);
        _presentationMaterial.SetInt("sRGB", sRGB ? 1 : 0);
        // Overwrite image with output from raytracer, applying tonemapping
        _cmd.Blit(_outputRT[_currentRT], destination, _presentationMaterial);

        if (_currentSample <= maxSamples)
        {
            _currentRT = 1 - _currentRT;
            _currentSample += Math.Max(1, samplesPerPass);
        }

        Graphics.ExecuteCommandBuffer(_cmd);
        _cmd.Clear();

        // Unity complains if destination is not set as the current render target,
        // which doesn't happen using the command buffer.
        Graphics.SetRenderTarget(destination);
    }

    void PrepareShader(CommandBuffer _cmd, ComputeShader shader, int kernelIndex)
    {
        _cmd.SetComputeIntParam(shader, "MaxRayBounces", Math.Max(maxRayBounces, 1));
        _cmd.SetComputeIntParam(shader, "SamplesPerPass", samplesPerPass);
        _cmd.SetComputeIntParam(shader, "BackfaceCulling", backfaceCulling ? 1 : 0);
        _cmd.SetComputeVectorParam(shader, "LightDirection", _lightDirection);
        _cmd.SetComputeVectorParam(shader, "LightColor", _lightColor);
        _cmd.SetComputeFloatParam(shader, "FarPlane", _camera.farClipPlane);
        _cmd.SetComputeIntParam(shader, "OutputWidth", _outputWidth);
        _cmd.SetComputeIntParam(shader, "OutputHeight", _outputHeight);
        _cmd.SetComputeIntParam(shader, "CurrentSample", _currentSample);
        _cmd.SetComputeTextureParam(shader, kernelIndex, "Output", _outputRT[_currentRT]);
        _cmd.SetComputeTextureParam(shader, kernelIndex, "AccumulatedOutput", _outputRT[1 - _currentRT]);
        _cmd.SetComputeBufferParam(shader, 0, "RNGStateBuffer", _rngStateBuffer);
        //_cmd.SetComputeBufferParam(shader, 0, "SkyStateBuffer", _skyStateBuffer);
        _cmd.SetComputeIntParam(shader, "EnvironmentMode", (int)environmentMode);
        _cmd.SetComputeFloatParam(shader, "EnvironmentIntensity", environmentIntensity);
        _cmd.SetComputeVectorParam(shader, "EnvironmentColor", environmentColor);
        _cmd.SetComputeFloatParam(shader, "EnvironmentMapRotation", environmentMapRotation);

        _cmd.SetComputeFloatParam(shader, "FocalLength", focalLength);
        _cmd.SetComputeFloatParam(shader, "Aperture", aperture);
    }
}
