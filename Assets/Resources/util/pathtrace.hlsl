#ifndef __UNITY_PATHTRACER_PATHTRACE_HLSL__
#define __UNITY_PATHTRACER_PATHTRACE_HLSL__

#include "common.hlsl"
#include "brdf.hlsl"
#include "light.hlsl"
#include "material.hlsl"
#include "ray.hlsl"
#include "sky.hlsl"

float3 PathTrace(Ray ray, inout uint rngState)
{
    float3 radiance = 0.0f;
    float3 throughput = 1.0f;

    LightSampleRec lightSample = (LightSampleRec)0;
    ScatterSampleRec scatterSample = (ScatterSampleRec)0;

    // For medium tracking
    //bool inMedium = false;
    //bool mediumSampled = false;
    //bool surfaceScatter = false;

    const uint maxRayBounces = max(MaxRayBounces, 1u);

    uint rayDepth = 0;
    for (; ; ++rayDepth)
    {
        RayHit hit = RayIntersect(ray);
        bool didHit = hit.distance < FAR_PLANE;

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

        // Test if the normal and tangent are orthogonal to each other.
        /*float3 N = normalize(hit.normal);
        float3 T = normalize(hit.tangent);
        if (abs(dot(N, T)) < EPSILON)
        {
            radiance = float3(1.0f, 0.0f, 0.0f);
            break;
        }*/

        Material material = hit.material;

        // Debug a material or intersection property
        //radiance = material.baseColor;
        //break;

        // Gather radiance from emissive objects. Emission from meshes is not importance sampled
        radiance += material.emission * throughput;

        if (rayDepth >= maxRayBounces)
            break;

        //surfaceScatter = true;

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
            //radiance += DirectLight(ray, hit, material, rngState) * throughput;

            // Sample BSDF for color and outgoing direction
            scatterSample.f = SampleBRDF(hit, material, -ray.direction, hit.ffnormal, scatterSample.L, scatterSample.pdf, rngState);

            if (isnan(scatterSample.f.x) || isnan(scatterSample.f.y) || isnan(scatterSample.f.z))
            {
                radiance = float3(0.0f, 1.0f, 0.0f);
                break;
            }

            //radiance = scatterSample.f;
            //break;

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
