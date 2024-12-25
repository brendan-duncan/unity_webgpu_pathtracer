using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

[RequireComponent(typeof(Camera))]
public class Raytracer : MonoBehaviour
{
    Camera sourceCamera;
    BVHScene bvhScene;
    CommandBuffer cmd;

    ComputeShader pathTracerShader;
    Material presentationMaterial;

    int outputWidth;
    int outputHeight;
    int totalRays;
    RenderTexture[] outputRT = { null, null };
    ComputeBuffer rngStateBuffer = null;
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
        bvhScene = FindFirstObjectByType<BVHScene>();
        cmd = new CommandBuffer();

        if (bvhScene == null)
        {
            Debug.LogError("BVHManager was not found in the scene!");
        }

        pathTracerShader = Resources.Load<ComputeShader>("PathTracer");
        Shader presentationShader = Resources.Load<Shader>("Presentation");
        presentationMaterial = new Material(presentationShader);

        // Find the directional light in the scene for NDotL
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
    }

    void OnDestroy()
    {
        rngStateBuffer?.Release();
        outputRT[0]?.Release();
        outputRT[1]?.Release();
        cmd?.Release();
    }

    public void ResetSamples()
    {
        currentSample = 0;
    }

    void OnRenderImage(RenderTexture source, RenderTexture destination)
    {
        if (bvhScene == null || !bvhScene.CanRender())
        {
            Graphics.Blit(source, destination);
            return;
        }

        outputWidth = sourceCamera.scaledPixelWidth;
        outputHeight = sourceCamera.scaledPixelHeight;
        totalRays = outputWidth * outputHeight;
        int dispatchX = Mathf.CeilToInt(totalRays / 256.0f);

        // Prepare buffers and output texture
        if (Utilities.PrepareRenderTexture(ref outputRT[0], outputWidth, outputHeight, RenderTextureFormat.ARGBFloat))
        {
            ResetSamples();
        }
        if (Utilities.PrepareRenderTexture(ref outputRT[1], outputWidth, outputHeight, RenderTextureFormat.ARGBFloat))
        {
            ResetSamples();
        }

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
                rngStateData[i] = (uint)Random.Range(0, uint.MaxValue);
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

        presentationMaterial.SetTexture("_MainTex", outputRT[currentRT]);
        presentationMaterial.SetInt("OutputWidth", outputWidth);
        presentationMaterial.SetInt("OutputHeight", outputHeight);
        presentationMaterial.SetInt("Samples", currentSample);

        // Overwrite image with output from raytracer
        cmd.Blit(outputRT[currentRT], destination, presentationMaterial);

        currentRT = 1 - currentRT;
        currentSample++;

        Graphics.ExecuteCommandBuffer(cmd);
        cmd.Clear();
    }

    void PrepareShader(CommandBuffer cmd, ComputeShader shader, int kernelIndex)
    {
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
    }
}
