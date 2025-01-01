using System;
using UnityEngine;
using UnityEngine.Rendering;

public enum TonemapMode {
    None = 0,
    Aces = 1,
    Filmic = 2,
    Reinhard = 3,
    Lottes = 4
}

public enum EnvironmentMode {
    Standard,
    Physical
}

[RequireComponent(typeof(Camera))]
public class PathTracer : MonoBehaviour
{
    public int samplesPerPass = 1;
    public int maxSamples = 100000;
    public int maxRayBounces = 5;
    public bool backfaceCulling = false;
    public float folalLength = 10.0f;
    public float aperature = 0.0f;
    public float skyTurbidity = 1.0f;
    public EnvironmentMode environmentMode = EnvironmentMode.Standard;
    public float environmentIntensity = 1.0f;
    public Texture2D environmentTexture;
    public float exposure = 1.0f;
    public TonemapMode tonemapMode = TonemapMode.Lottes;
    public bool sRGB = false;

    LocalKeyword hasTexturesKeyword;
    LocalKeyword hasEnvironmentTextureKeyword;

    Camera sourceCamera;
    BVHScene bvhScene;
    CommandBuffer cmd;

    ComputeShader pathTracerShader;
    Material presentationMaterial;

    int outputWidth;
    int outputHeight;
    int totalRays;
    RenderTexture[] outputRT = { null, null };
    ComputeBuffer rngStateBuffer;

    ComputeBuffer skyStateBuffer;
    SkyState skyState;
    ComputeBuffer environmentCdfBuffer;
    
    int currentRT = 0;
    int currentSample = 0;

    // Sun for NDotL
    Vector3 lightDirection = new Vector3(1.0f, 1.0f, 1.0f).normalized;
    Vector4 lightColor = new Vector4(1.0f, 1.0f, 1.0f, 1.0f);

    // Struct sizes in bytes
    const int RayStructSize = 24;
    const int RayHitStructSize = 20;

    void Start()
    {
        sourceCamera = GetComponent<Camera>();

        bvhScene = new BVHScene();
        cmd = new CommandBuffer();

        bvhScene.Start();

        pathTracerShader = Resources.Load<ComputeShader>("PathTracer");
        Shader presentationShader = Resources.Load<Shader>("Presentation");
        presentationMaterial = new Material(presentationShader);

        hasTexturesKeyword = pathTracerShader.keywordSpace.FindKeyword("HAS_TEXTURES");
        hasEnvironmentTextureKeyword = pathTracerShader.keywordSpace.FindKeyword("HAS_ENVIRONMENT_TEXTURE");

        //bool hasLight = false;

        Light[] lights = FindObjectsByType<Light>(FindObjectsSortMode.None);
        foreach (Light light in lights)
        {
            if (light.type == LightType.Directional)
            {
                lightDirection = -light.transform.forward;
                lightColor = light.color * light.intensity;
                //hasLight = true;
                break;
            }
        }

        lightDirection.Normalize();

        skyStateBuffer = new ComputeBuffer(40, 4);
        skyState = new SkyState();
        float[] direction = { lightDirection.x, lightDirection.y, lightDirection.z };
        float[] groundAlbedo = { 1.0f, 1.0f, 1.0f };

        skyState.Init(direction, groundAlbedo, skyTurbidity);
        skyState.UpdateBuffer(skyStateBuffer);

        if (environmentTexture != null)
        {
            pathTracerShader.EnableKeyword(hasEnvironmentTextureKeyword);
            pathTracerShader.SetTexture(0, "EnvironmentTexture", environmentTexture);

            var pixelData = environmentTexture.GetPixelData<Color>(0);

            environmentCdfBuffer = new ComputeBuffer(pixelData.Length, 4);
            float[] cdf = new float[pixelData.Length];
            float sum = 0.0f;
            for (int i = 0; i < pixelData.Length; i++)
            {
                sum += pixelData[i].grayscale;
                cdf[i] = sum;
            }
            environmentCdfBuffer.SetData(cdf);
            pathTracerShader.SetInt("EnvironmentTextureWidth", environmentTexture.width);
            pathTracerShader.SetInt("EnvironmentTextureHeight", environmentTexture.height);
            pathTracerShader.SetBuffer(0, "EnvironmentCdf", environmentCdfBuffer);
            pathTracerShader.SetFloat("EnvironmentCdfSum", sum);
        }
        else
        {
            pathTracerShader.DisableKeyword(hasEnvironmentTextureKeyword);
        }
    }

    void OnDestroy()
    {
        bvhScene?.OnDestroy();
        bvhScene = null;
        rngStateBuffer?.Release();
        outputRT[0]?.Release();
        outputRT[1]?.Release();
        cmd?.Release();
        skyStateBuffer?.Release();
        environmentCdfBuffer?.Release();
    }

    void Update()
    {
        bvhScene.Update();
        pathTracerShader.SetKeyword(hasTexturesKeyword, bvhScene.HasTextures());

        /*float mouseX = Input.mousePosition.x;
        float mouseY = Screen.height - 1 - Input.mousePosition.y;

        Matrix4x4 CamInvProj = sourceCamera.projectionMatrix.inverse;
        Matrix4x4 CamToWorld = sourceCamera.cameraToWorldMatrix;

        //float3 origin = mul(CamToWorld, float4(0.0f, 0.0f, 0.0f, 1.0f)).xyz;
        Vector4 origin = sourceCamera.transform.position;

        // Compute world space direction
        float u = (mouseX / Screen.width) * 2.0f - 1.0f;
        float v = (mouseY / Screen.height) * 2.0f - 1.0f;

        Vector4 direction4 = CamInvProj * new Vector4(u, v, 0.0f, 1.0f);
        direction4.w = 0.0f;
        direction4 = CamToWorld * direction4;
        Vector3 direction = new Vector3(direction4.x, direction4.y, direction4.z);
        direction.Normalize();

        var isect = bvhScene.sceneBVH.Intersect(origin, direction);
        if (isect.t < 1.0e30f)
            Debug.Log("Intersection at: " + isect.t);*/
    }

    public void Reset()
    {
        currentSample = 0;
    }

    public void UpdateMaterialData()
    {
        bvhScene.UpdateMaterialData(false);
        Reset();
    }

    void OnRenderImage(RenderTexture source, RenderTexture destination)
    {
        if (!bvhScene.CanRender())
        {
            Graphics.Blit(source, destination);
            return;
        }

        outputWidth = sourceCamera.scaledPixelWidth;
        outputHeight = sourceCamera.scaledPixelHeight;
        totalRays = outputWidth * outputHeight;
        int dispatchX = Mathf.CeilToInt(totalRays / 128.0f);

        if (currentSample < maxSamples)
        {
            Vector3 lastDirection = lightDirection;
            Light[] lights = FindObjectsByType<Light>(FindObjectsSortMode.None);
            foreach (Light light in lights)
            {
                if (light.type == LightType.Directional)
                {
                    lightDirection = -light.transform.forward;
                    lightColor = light.color * light.intensity;
                    break;
                }
            }

            if ((lastDirection - lightDirection).sqrMagnitude > 0.0001f)
            {
                skyState.Init(new float[] { lightDirection.x, lightDirection.y, lightDirection.z }, new float[] { 0.3f, 0.2f, 0.1f }, skyTurbidity);
                skyState.UpdateBuffer(skyStateBuffer);
                Reset();
            }

            // Prepare buffers and output texture
            if (Utilities.PrepareRenderTexture(ref outputRT[0], outputWidth, outputHeight, RenderTextureFormat.ARGBFloat))
                Reset();

            if (Utilities.PrepareRenderTexture(ref outputRT[1], outputWidth, outputHeight, RenderTextureFormat.ARGBFloat))
                Reset();

            if (rngStateBuffer != null && (rngStateBuffer.count != totalRays || currentSample == 0))
            {
                rngStateBuffer?.Release();
                rngStateBuffer = null;
            }

            if (rngStateBuffer == null)
            {
                rngStateBuffer = new ComputeBuffer(totalRays, 4);
                uint[] rngStateData = new uint[totalRays];
                for (int i = 0; i < totalRays; i++)
                {
                    rngStateData[i] = (uint)UnityEngine.Random.Range(0, uint.MaxValue);
                }
                rngStateBuffer.SetData(rngStateData);
            }
        
            cmd.BeginSample("Path Tracer");
            {
                PrepareShader(cmd, pathTracerShader, 0);
                bvhScene.PrepareShader(cmd, pathTracerShader, 0);
                cmd.SetComputeMatrixParam(pathTracerShader, "CamInvProj", sourceCamera.projectionMatrix.inverse);
                cmd.SetComputeMatrixParam(pathTracerShader, "CamToWorld", sourceCamera.cameraToWorldMatrix);
    
                cmd.DispatchCompute(pathTracerShader, 0, dispatchX, 1, 1);
            }
            cmd.EndSample("Path Tracer");
        }

        presentationMaterial.SetTexture("_MainTex", outputRT[currentRT]);
        presentationMaterial.SetInt("OutputWidth", outputWidth);
        presentationMaterial.SetInt("OutputHeight", outputHeight);
        presentationMaterial.SetFloat("Exposure", exposure);
        presentationMaterial.SetInt("Mode", (int)tonemapMode);
        presentationMaterial.SetInt("sRGB", sRGB ? 1 : 0);
        // Overwrite image with output from raytracer, applying tonemapping
        cmd.Blit(outputRT[currentRT], destination, presentationMaterial);

        if (currentSample <= maxSamples)
        {
            currentRT = 1 - currentRT;
            currentSample += Math.Max(1, samplesPerPass);
        }

        Graphics.ExecuteCommandBuffer(cmd);
        cmd.Clear();

        // Unity complains if destination is not set as the current render target,
        // which doesn't happen using the command buffer.
        Graphics.SetRenderTarget(destination);
    }

    void PrepareShader(CommandBuffer cmd, ComputeShader shader, int kernelIndex)
    {
        cmd.SetComputeIntParam(shader, "MaxRayBounces", Math.Max(maxRayBounces, 1));
        cmd.SetComputeIntParam(shader, "SamplesPerPass", samplesPerPass);
        cmd.SetComputeIntParam(shader, "BackfaceCulling", backfaceCulling ? 1 : 0);
        cmd.SetComputeVectorParam(shader, "LightDirection", lightDirection);
        cmd.SetComputeVectorParam(shader, "LightColor", lightColor);
        cmd.SetComputeFloatParam(shader, "FarPlane", sourceCamera.farClipPlane);
        cmd.SetComputeIntParam(shader, "OutputWidth", outputWidth);
        cmd.SetComputeIntParam(shader, "OutputHeight", outputHeight);
        cmd.SetComputeIntParam(shader, "TotalRays", totalRays);
        cmd.SetComputeIntParam(shader, "CurrentSample", currentSample);
        cmd.SetComputeTextureParam(shader, kernelIndex, "Output", outputRT[currentRT]);
        cmd.SetComputeTextureParam(shader, kernelIndex, "AccumulatedOutput", outputRT[1 - currentRT]);
        cmd.SetComputeBufferParam(shader, 0, "RNGStateBuffer", rngStateBuffer);
        cmd.SetComputeBufferParam(shader, 0, "SkyStateBuffer", skyStateBuffer);
        cmd.SetComputeIntParam(shader, "EnvironmentMode", (int)environmentMode);
        cmd.SetComputeFloatParam(shader, "EnvironmentIntensity", environmentIntensity);
    }
}
