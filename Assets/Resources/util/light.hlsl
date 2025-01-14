#ifndef __UNITY_PATHRACER_LIGHT_HLSL__
#define __UNITY_PATHRACER_LIGHT_HLSL__

#include "common.hlsl"

#define LIGHT_TYPE_SPOT 0
#define LIGHT_TYPE_DIRECTIONAL 1
#define LIGHT_TYPE_POINT 2
#define LIGHT_TYPE_RECTANGLE 3
#define LIGHT_TYPE_DISC 4
#define LIGHT_TYPE_PYRAMID 5
#define LIGHT_TYPE_BOX 6
#define LIGHT_TYPE_TUBE 7

struct Light
{
    float3 position;
    float type;
    float3 emission;
    float range;
    float3 u;
    float area;
    float3 v;
    float spotAngle;
};

int LightCount;
StructuredBuffer<Light> Lights;

void SampleRectLight(in Light light, in float3 scatterPos, inout LightSampleRec lightSample, inout uint rngState)
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
}

void SamplePointLight(in Light light, in float3 scatterPos, inout LightSampleRec lightSample)
{
    lightSample.normal = normalize(scatterPos - light.position);
    lightSample.emission = light.emission;
    lightSample.direction = -lightSample.normal;
    lightSample.distance = length(scatterPos - light.position);
    lightSample.pdf = 0.0f;
}

void SampleSpotLight(in Light light, in float3 scatterPos, inout LightSampleRec lightSample)
{
    lightSample.normal = normalize(cross(light.u, light.v));
    lightSample.emission = light.emission;
    lightSample.direction = normalize(scatterPos - light.position);
    lightSample.distance = length(light.position - scatterPos);
    lightSample.pdf = 0.0f;
}

void SampleOneLight(in Light light, in float3 scatterPos, inout LightSampleRec lightSample, inout uint rngState)
{
    int type = int(light.type);
    if (type == LIGHT_TYPE_RECTANGLE)
    {
        SampleRectLight(light, scatterPos, lightSample, rngState);
    }
    else if (type == LIGHT_TYPE_POINT)
    {
        SamplePointLight(light, scatterPos, lightSample);
    }
    else if (type == LIGHT_TYPE_SPOT)
    {
        SampleSpotLight(light, scatterPos, lightSample);
    }
}

float3 EvalLight(in Ray ray, in RayHit hit, in DisneyMaterial mat, in Light light, in float3 scatterPos, in LightSampleRec lightSample)
{
    float3 Ld = 0.0f;

    float falloff = 0.0f;
    if (lightSample.distance <= light.range)
    {
        // How does Unity falloff work?
        float r = lightSample.distance / light.range;
        float atten = saturate(1.0 / (1.0 + 25.0 * r * r) * saturate((1 - r) * 5.0));
        falloff = atten;
    }

    if (light.type == LIGHT_TYPE_SPOT)
    {
        /*float3 lightDir = lightSample.normal;
        float cosTheta = dot(lightDir, lightSample.direction);
        float cosAlpha = dot(-lightSample.direction, lightSample.normal);
        float cosBeta = dot(lightDir, lightSample.normal);
        float spot = ;
        falloff *= spot;*/
    }

    float3 Li = light.emission * falloff;

    Ray shadowRay = {scatterPos, lightSample.direction};
    bool inShadow = ShadowRayIntersect(shadowRay);
    if (!inShadow)
    {
        float pdf;
        float3 f = DisneyEval(hit, mat, -ray.direction, hit.normal, lightSample.direction, pdf);
        float lightPdf = 1.0f;
        if (lightSample.pdf > 0.0f)
            lightPdf = lightSample.pdf;
        float3 L = Li * f / lightPdf;
        Ld += L;
    }

    return Ld;
}

float3 DirectLight(in Ray ray, in RayHit hit, in DisneyMaterial mat, inout uint rngState)
{
    float3 Ld = 0.0f;
    float3 scatterPos = hit.position + hit.normal * EPSILON;
    ScatterSampleRec scatterSample = { (float3)0.0f, (float3)0.0f, 0.0f };

    /*if (EnvironmentMode == 0)
    {
        #if HAS_ENVIRONMENT_TEXTURE
        float3 Li = 0.0f;
        float4 dirPdf = SampleEnvMap(Li, rngState);
        float3 lightDir = dirPdf.xyz;
        float lightPdf = dirPdf.w;
        Ray shadowRay = {scatterPos, lightDir};
        bool inShadow = ShadowRayIntersect(shadowRay);
        if (!inShadow)
        {
            scatterSample.f = DisneyEval(hit, mat, -ray.direction, hit.ffnormal, lightDir, scatterSample.pdf);
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
        Ray shadowRay = {scatterPos, lightDir};
        bool inShadow = ShadowRayIntersect(shadowRay);
        if (!inShadow)
        {
            scatterSample.f = DisneyEval(hit, mat, -ray.direction, hit.ffnormal, lightDir, scatterSample.pdf);
            if (scatterSample.pdf > 0.0)
            {
                float misWeight = PowerHeuristic(lightPdf, scatterSample.pdf);
                if (misWeight > 0.0)
                    Ld += misWeight * Li * scatterSample.f / lightPdf;
            }
        }
        #endif // HAS_ENVIRONMENT_TEXTURE
    }
    else if (EnvironmentMode == 1)
    {
        float3 lightDir = normalize(RandomCosineHemisphere(hit.normal, rngState));
        float4 lightColorPdf = StandardSky(lightDir, EnvironmentIntensity);
        float3 Li = lightColorPdf.rgb;
        float lightPdf = lightColorPdf.w;
        Ray shadowRay = {scatterPos, lightDir};
        bool inShadow = ShadowRayIntersect(shadowRay);
        if (!inShadow)
        {
            scatterSample.f = DisneyEval(hit, mat, -ray.direction, hit.ffnormal, lightDir, scatterSample.pdf);
            if (scatterSample.pdf > 0.0)
            {
                float misWeight = PowerHeuristic(lightPdf, scatterSample.pdf);
                if (misWeight > 0.0)
                    Ld += misWeight * Li * scatterSample.f / lightPdf;
            }
        }
    }
    else
    {
        float lightPdf = 1.0f / (4.0f * PI);
        float2 uv = float2(RandomFloat(rngState), RandomFloat(rngState));
        float3 lightDir = SampleSolarDiskDirection(uv, SOLAR_COS_THETA_MAX, SkyStateBuffer[0].sunDirection);
        float3 Li = float3(
            SkyStateBuffer[0].solarRadiances[0],
            SkyStateBuffer[0].solarRadiances[1],
            SkyStateBuffer[0].solarRadiances[2]
        );
        Ray shadowRay = {scatterPos, lightDir};
        bool inShadow = ShadowRayIntersect(shadowRay);
        if (!inShadow)
        {
            scatterSample.f = DisneyEval(hit, mat, -ray.direction, hit.ffnormal, lightDir, scatterSample.pdf);
            if (scatterSample.pdf > 0.0)
            {
                float misWeight = PowerHeuristic(lightPdf, scatterSample.pdf);
                if (misWeight > 0.0)
                    Ld += misWeight * Li * scatterSample.f / lightPdf;
            }
        }
    }*/

#if HAS_LIGHTS
    LightSampleRec lightSample = { (float3)0.0f, (float3)0.0f, (float3)0.0f, 0.0f, 0.0f };

    // Pick a light to sample
    int lightIndex = int(RandomFloat(rngState) * float(LightCount));
    Light light = Lights[lightIndex];

    SampleOneLight(light, scatterPos, lightSample, rngState);

    if (dot(lightSample.direction, lightSample.normal) <= 0.0f)
    {
        int type = int(light.type);
        if (type == LIGHT_TYPE_POINT || type == LIGHT_TYPE_RECTANGLE || type == LIGHT_TYPE_SPOT)
            Ld += EvalLight(ray, hit, mat, light, scatterPos, lightSample);
    }
#endif // HAS_LIGHTS

    return Ld;
}

#endif // __UNITY_PATHRACER_LIGHT_HLSL__
