#ifndef __UNITY_PATHTRACER_PATHTRACE_HLSL__
#define __UNITY_PATHTRACER_PATHTRACE_HLSL__

#include "common.hlsl"
#include "brdf.hlsl"
#include "light.hlsl"
#include "material.hlsl"
#include "sky.hlsl"

float3 PathTrace(Ray ray, inout uint rngState)
{
    float3 radiance = 0.0f;
    float3 throughput = 1.0f;

    LightSampleRec lightSample = (LightSampleRec)0;
    ScatterSampleRec scatterSample = (ScatterSampleRec)0;

    const uint maxRayBounces = max(MaxRayBounces, 1u);

    RayHit hit = (RayHit)0;

    float maxRoughness = 0.0f;

    uint rayDepth = 0;
    for (; ; ++rayDepth)
    {
        bool didHit = RayIntersect(ray, hit);

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

#if HAS_LIGHTS
        if (hit.intersectType == INTERSECT_LIGHT)
        {
            Light light = Lights[hit.triIndex];
            radiance += light.emission * throughput;
            break;
        }
#endif

        // Debug hit properties
        //radiance = hit.normal;
        //break;

        /*float3 N = hit.normal;
        float3 T = normalize(hit.tangent);
        if (abs(dot(N, T)) < EPSILON)
        {
            radiance = float3(1.0f, 0.0f, 0.0f);
            break;
        }*/

        //Material material = hit.material;
        Material material = GetMaterial(Materials[hit.materialIndex], ray, hit);

        // Keep track of the maximum roughness to prevent firefly artifacts
        // by forcing subsequent bounces to be at least as rough
        maxRoughness = max(maxRoughness, material.roughness);
        material.roughness = maxRoughness;

        //radiance = hit.normal;
        //break;

        // Debug a material or intersection property
        //radiance = material.occlusion;
        //break;

        // Gather radiance from emissive objects. Emission from meshes is not importance sampled
        radiance += material.emission * throughput;

        if (rayDepth >= maxRayBounces)
            break;

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
            // Break here to debug direct lighting
            //break;

            // Sample BSDF for color and outgoing direction
            scatterSample.f = SampleBRDF(hit, material, -ray.direction, hit.ffnormal, scatterSample.L, scatterSample.pdf, rngState);

            if (isnan(scatterSample.f.x) || isnan(scatterSample.f.y) || isnan(scatterSample.f.z))
            {
                radiance = float3(0.0f, 1.0f, 0.0f);
                break;
            }

            // Debug the result of SampleBRDF.
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

        // Russian roulette termination
        if (UseRussianRoulette)
        {
            float rrPcont = min(max(throughput.x, max(throughput.y, throughput.z)) + 0.001f, 0.95f);
            if (RandomFloat(rngState) >= rrPcont)
                break;
            throughput /= rrPcont;
        }
    }

    return radiance;
}

#endif // __UNITY_PATHTRACER_PATHTRACE_HLSL__
