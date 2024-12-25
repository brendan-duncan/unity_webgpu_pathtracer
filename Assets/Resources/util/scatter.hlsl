#ifndef __UNITY_PATHTRACER_SCATTER_HLSL__
#define __UNITY_PATHTRACER_SCATTER_HLSL__

bool ScatterLambertian(RayHit hit, inout Ray ray, inout float3 attenuation, inout uint rngSeed)
{
    ray.origin = hit.position + hit.normal * 0.001f;
    ray.direction = normalize(ray.direction + rngInSphere(rngSeed));
    attenuation = GetAlbedoColor(hit.material, hit.uv);
    return true;
}

bool ScatterMetal(RayHit hit, inout Ray ray, inout float3 attenuation, inout uint rngSeed)
{
    ray.origin = hit.position + hit.normal * 0.001f;
    float3 reflected = reflect(normalize(ray.direction), hit.normal);
    float smoothness = 1.0f - hit.material.metalicSmoothness.g;
    ray.direction = normalize(reflected + smoothness * rngInSphere(rngSeed));
    attenuation = GetAlbedoColor(hit.material, hit.uv);

    return dot(ray.direction, hit.normal) >= 0;
}

float reflectance(float cosine, float refractionIndex)
{
    // Use Schlick's approximation for reflectance.
    float r0 = (1.0f - refractionIndex) / (1.0f + refractionIndex);
    r0 *= r0;
    return r0 + (1.0 - r0) * pow((1.0 - cosine), 5.0);
}

bool ScatterDielectric(RayHit hit, inout Ray ray, inout float3 attenuation, inout uint rngSeed)
{
    attenuation = (float3)1.0f;
    //attenuation = GetAlbedoColor(hit.material, hit.uv);

    float refractRatio = 1.0f / hit.material.ior;
    float3 unitDirection = normalize(ray.direction);
    
    float cosTheta = dot(-unitDirection, hit.normal);
    float sinTheta = sqrt(1.0f - cosTheta * cosTheta);
    bool cannotRefract = (refractRatio * sinTheta) > 1.0f;

    float rnd = rngNextFloat(rngSeed);

    if (cannotRefract || reflectance(cosTheta, refractRatio) > rnd)
    {
        ray.direction = normalize(reflect(unitDirection, hit.normal));
    }
    else
    {
        ray.direction = normalize(refract(unitDirection, hit.normal, refractRatio));
    }

    ray.origin = hit.position + ray.direction * 0.001f;
    
    return true;
}

#endif // __UNITY_PATHTRACER_SCATTER_HLSL__
