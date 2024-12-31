#ifndef __UNITY_PATHTRACER_PATHTRACE_HLSL__
#define __UNITY_PATHTRACER_PATHTRACE_HLSL__

#include "brdf.hlsl"
#include "common.hlsl"
#include "material.hlsl"
#include "ray.hlsl"

float3 TraceRay(Ray ray, inout uint rngSeed)
{
    uint rayBounces = 0;
    float3 color = (float3)1.0f;

    while (rayBounces < MaxRayBounces)
    {
        RayHit hit = RayIntersect(ray);
        bool didHit = hit.distance < FarPlane;
        if (didHit)
        {
            float3 attenuation = (float3)0;
            if (hit.material.mode == 3)
            {
                if (!ScatterDielectric(hit, ray, attenuation, rngSeed))
                {
                    return color;
                }
            }
            else
            {
                float metallic = hit.material.metallicRoughness.r;
                if (metallic > 0.0f)
                {
                    Ray lambertRay = {ray.origin, ray.direction};
                    if (!ScatterMetal(hit, ray, attenuation, rngSeed))
                    {
                        return color;
                    }
                    if (metallic < 1.0f)
                    {
                        float3 lambert = (float3)0;
                        if (!ScatterLambertian(hit, lambertRay, lambert, rngSeed))
                        {
                            return color;
                        }

                        ray.direction = lerp(ray.direction, lambertRay.direction, metallic);

                        attenuation = lerp(attenuation, lambert, metallic);
                    }
                }
                else 
                {
                    if (!ScatterLambertian(hit, ray, attenuation, rngSeed))
                    {
                        return color;
                    }
                }
            }

            color *= attenuation;
            
            rayBounces++;
        }
        else
        {
            color *= SampleSkyRadiance(ray.direction, rayBounces);
            break;
        }
    }

    return color;
}

#endif // __UNITY_PATHTRACER_PATHTRACE_HLSL__
