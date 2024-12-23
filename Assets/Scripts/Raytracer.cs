using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

[RequireComponent(typeof(Camera))]
public class Raytracer : MonoBehaviour
{
    private Camera sourceCamera;
    private BVHScene bvhScene;
    private CommandBuffer cmd;

    private ComputeShader pathTracerShader;
    private Material presentationMaterial;

    private int outputWidth;
    private int outputHeight;
    private int totalRays;
    private RenderTexture[] outputRT = { null, null };
    private int currentRT = 0;
    private int currentSample = 0;

    // Sun for NDotL
    private Vector3 lightDirection = new Vector3(1.0f, 1.0f, 1.0f).normalized;
    private Vector4 lightColor = new Vector4(1.0f, 1.0f, 1.0f, 1.0f);

    // Struct sizes in bytes
    private const int RayStructSize = 24;
    private const int RayHitStructSize = 20;

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
        outputRT[0]?.Release();
        outputRT[1]?.Release();
        cmd?.Release();
    }

    public void ResetSamples()
    {
        currentSample = 0;
    }

    private void OnRenderImage(RenderTexture source, RenderTexture destination)
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
        presentationMaterial.SetInt("Samples", currentSample);

        // Overwrite image with output from raytracer
        cmd.Blit(outputRT[currentRT], destination, presentationMaterial);
        currentRT = 1 - currentRT;
        currentSample++;

        Graphics.ExecuteCommandBuffer(cmd);
        cmd.Clear();
    }

    private void PrepareShader(CommandBuffer cmd, ComputeShader shader, int kernelIndex)
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
        
    }
}
