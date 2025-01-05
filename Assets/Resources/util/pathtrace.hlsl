#ifndef __UNITY_PATHTRACER_PATHTRACE_HLSL__
#define __UNITY_PATHTRACER_PATHTRACE_HLSL__

#include "bvh.hlsl"
#include "common.hlsl"
#include "disney_brdf.hlsl"
#include "light.hlsl"
#include "material.hlsl"
#include "ray.hlsl"
#include "sky.hlsl"

float3 PathTrace(Ray ray, inout uint rngState)
{
    float3 radiance = 0.0f;
    float3 throughput = 1.0f;

    LightSampleRec lightSample = { (float3)0.0f, (float3)0.0f, (float3)0.0f, 0.0f, 0.0f };
    ScatterSampleRec scatterSample = { (float3)0.0f, (float3)0.0f, 0.0f };

    // For medium tracking
    bool inMedium = false;
    bool mediumSampled = false;
    bool surfaceScatter = false;

    const uint maxRayBounces = max(MaxRayBounces, 1u);
    
    for (uint rayDepth = 0; ; ++rayDepth)
    {
        RayHit hit = RayIntersect(ray);
        bool didHit = hit.distance < FarPlane;

        if (!didHit)
        {
            float4 skyColorPDf = SampleSkyRadiance(ray.direction, rayDepth);
            float misWeight = 1.0;
            // Gather radiance from envmap and use scatterSample.pdf from previous bounce for MIS
            if (rayDepth > 0)
                misWeight = PowerHeuristic(scatterSample.pdf, skyColorPDf.w);
            if (misWeight > 0)
                radiance += misWeight * skyColorPDf.rgb * throughput;
            break;
        }

        DisneyMaterial material = GetDisneyMaterial(ray, hit);

        // Gather radiance from emissive objects. Emission from meshes is not importance sampled
        radiance += material.emission * throughput;

        if (rayDepth == maxRayBounces)
            break;

        surfaceScatter = true;

        // Ignore intersection and continue ray based on alpha test
        if ((material.alphaMode == ALPHA_MODE_MASK && material.opacity < material.alphaCutoff) ||
            (material.alphaMode == ALPHA_MODE_BLEND && RandomFloat(rngState) > material.opacity))
        {
            scatterSample.L = ray.direction;
            rayDepth--;
        }
        else
        {
            // Next event estimation
            radiance += DirectLight(ray, hit, material, rngState) * throughput;
            //return radiance;

            // Sample BSDF for color and outgoing direction
            scatterSample.f = DisneySample(hit, material, -ray.direction, hit.ffnormal, scatterSample.L, scatterSample.pdf, rngState);
            if (scatterSample.pdf > 0.0)
                throughput *= scatterSample.f / scatterSample.pdf;
            else
                break;
        }

        // Move ray origin to hit point and set direction for next bounce
        ray.direction = scatterSample.L;
        ray.origin = hit.position + ray.direction * EPSILON;
    }

    return radiance;
}

#endif // __UNITY_PATHTRACER_PATHTRACE_HLSL__
