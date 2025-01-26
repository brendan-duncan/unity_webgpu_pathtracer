#ifndef __UNITY_PATHRACER_LIGHT_HLSL__
#define __UNITY_PATHRACER_LIGHT_HLSL__

#include "globals.hlsl"

#if HAS_LIGHTS
bool SampleRectLight(in Light light, in float3 scatterPos, inout LightSampleRec lightSample, inout uint rngState)
{
    float r1 = RandomFloat(rngState);
    float r2 = RandomFloat(rngState);

    float3 lightSurfacePos = light.position + light.u.xyz * r1 + light.v.xyz * r2;
    lightSample.direction = lightSurfacePos - scatterPos;
    lightSample.distance = length(lightSample.direction);

    float distSq = lightSample.distance * lightSample.distance;
    lightSample.direction /= lightSample.distance;
    lightSample.normal = normalize(cross(light.u, light.v));
    lightSample.emission = light.emission * float(LightCount);
    lightSample.pdf = distSq / (light.area * abs(dot(lightSample.normal, lightSample.direction)));

    return true;
}

bool SamplePointLight(in Light light, in float3 scatterPos, inout LightSampleRec lightSample)
{
    lightSample.normal = normalize(scatterPos - light.position);
    lightSample.emission = light.emission;
    lightSample.direction = -lightSample.normal;
    lightSample.distance = length(scatterPos - light.position);
    lightSample.pdf = 0.0f;

    return true;
}

bool SampleSpotLight(in Light light, in float3 scatterPos, inout LightSampleRec lightSample)
{
    lightSample.normal = normalize(light.u);
    lightSample.emission = light.emission;
    lightSample.direction = -normalize(scatterPos - light.position);
    lightSample.distance = length(light.position - scatterPos);
    lightSample.pdf = 0.0f;

    return true;
}

bool SampleOneLight(in Light light, in float3 scatterPos, inout LightSampleRec lightSample, inout uint rngState)
{
    uint type = light.type;
    bool result = false;
    if (type == LIGHT_TYPE_SPOT)
        result = SampleSpotLight(light, scatterPos, lightSample);
    else if (type == LIGHT_TYPE_RECTANGLE)
        result = SampleRectLight(light, scatterPos, lightSample, rngState);
    else if (type == LIGHT_TYPE_POINT)
        result = SamplePointLight(light, scatterPos, lightSample);
    return result;
}

float3 EvalLight(in Ray ray, in RayHit hit, in Material mat, in Light light, in float3 scatterPos, in LightSampleRec lightSample)
{
    float falloff = 1.0f;
    if (lightSample.distance > light.range)
    {
        falloff = 0.0f;
    }
    else
    {
        // How does Unity falloff work?
        float r = lightSample.distance / light.range;
        float atten = saturate(1.0 / (1.0 + 25.0 * r * r) * saturate((1 - r) * 5.0));
        falloff *= atten;
    }

    if (light.type == LIGHT_TYPE_RECTANGLE)
    {
        // Only light in the forward direction of the light.
        float cosTheta = dot(normalize(-lightSample.direction), normalize(lightSample.normal));
        falloff = cosTheta < 0 ? 0.0f : falloff;
    }

    if (light.type == LIGHT_TYPE_SPOT)
    {
        float cosTheta = dot(normalize(-lightSample.direction), normalize(lightSample.normal));
        // v.x is the cosine of the outer spotlight angle.
        // v.y is the cosine of the inner spotlight angle.
        // If cosTheta is > than the inner angle, then it's fully in the spotlight.
        // If cosTheta is < than the outer angle, then it's fully out of the spotlight.
        // If cosTheta is between the inner and outer angles, we fade from 1 to 0 as it approaches the outer angle.
        if (cosTheta < light.v.x)
            falloff = 0.0f;
        else if (cosTheta > light.v.x && cosTheta < light.v.y)
            falloff *= (cosTheta - light.v.x) / (light.v.y - light.v.x);
    }

    float3 Li = light.emission * falloff;
    float3 Ld = 0.0f;

    Ray shadowRay = {scatterPos, 0.0f, lightSample.direction, 0.0f};
    bool inShadow = ShadowRayIntersect(shadowRay);
    if (!inShadow)
    {
        //Ld = Li;
        float pdf = 0.0f;
        float3 f = EvalBRDF(hit, mat, -ray.direction, hit.normal, lightSample.direction, pdf);
        float lightPdf = 1.0f;
        if (lightSample.pdf > 0.0f)
            lightPdf = lightSample.pdf;
        float3 L = Li * f / lightPdf;
        Ld += L;
    }

    return Ld;
}
#endif // HAS_LIGHTS

float3 DirectLight(in Ray ray, in RayHit hit, in Material mat, inout uint rngState)
{
    float3 Ld = 0.0f;
    float3 scatterPos = hit.position + hit.normal * EPSILON;

    ScatterSampleRec scatterSample = (ScatterSampleRec)0;
    if (EnvironmentMode == 0)
    {
#if HAS_ENVIRONMENT_TEXTURE
        float3 Li = 0.0f;
        float4 dirPdf = SampleEnvMap(Li, rngState);
        float3 lightDir = dirPdf.xyz;
        float lightPdf = dirPdf.w;
        Ray shadowRay = {scatterPos, 0.0f, lightDir, 0.0f};
        bool inShadow = ShadowRayIntersect(shadowRay);
        if (!inShadow)
        {
            scatterSample.f = EvalBRDF(hit, mat, -ray.direction, hit.ffnormal, lightDir, scatterSample.pdf);
            if (scatterSample.pdf > 0.0)
            {
                float misWeight = PowerHeuristic(lightPdf, scatterSample.pdf);
                if (misWeight > 0.0)
                    Ld += misWeight * Li * scatterSample.f * EnvironmentIntensity / lightPdf;
            }
        }
#else // HAS_ENVIRONMENT_TEXTURE
        float3 Li = EnvironmentColor * EnvironmentIntensity;
        float lightPdf = 1.0f / (4.0f * PI);
        float3 lightDir = normalize(RandomCosineHemisphere(hit.normal, rngState));
        Ray shadowRay = {scatterPos, 0.0f, lightDir, 0.0f};
        bool inShadow = ShadowRayIntersect(shadowRay);
        if (!inShadow)
        {
            scatterSample.f = EvalBRDF(hit, mat, -ray.direction, hit.ffnormal, lightDir, scatterSample.pdf);
            if (scatterSample.pdf > 0.0)
            {
                float misWeight = PowerHeuristic(lightPdf, scatterSample.pdf);
                if (misWeight > 0.0)
                    Ld += misWeight * Li * scatterSample.f / lightPdf;
            }
        }
#endif // HAS_ENVIRONMENT_TEXTURE
    }

#if HAS_LIGHTS
    LightSampleRec lightSample = (LightSampleRec)0;

    // Pick a light to sample
    int lightIndex = int(RandomFloat(rngState) * float(LightCount));
    Light light = Lights[lightIndex];

    if (SampleOneLight(light, scatterPos, lightSample, rngState))
        Ld += EvalLight(ray, hit, mat, light, scatterPos, lightSample);
#endif // HAS_LIGHTS

    return Ld;
}

#endif // __UNITY_PATHRACER_LIGHT_HLSL__
