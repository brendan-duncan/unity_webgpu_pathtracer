#ifndef __UNITY_PATHTRACER_SKY_HLSL__
#define __UNITY_PATHTRACER_SKY_HLSL__

#include "common.hlsl"

#define SKY_MODE_ENVIRONMENT 0
#define SKY_MODE_BASIC 1

int EnvironmentMode;
float3 EnvironmentColor;
float EnvironmentIntensity;

#if HAS_ENVIRONMENT_TEXTURE
Texture2D<float4> EnvironmentTexture;
SamplerState samplerEnvironmentTexture;
StructuredBuffer<float> EnvironmentCDF;
int EnvironmentTextureWidth;
int EnvironmentTextureHeight;
float EnvironmentCdfSum;
float EnvironmentMapRotation;
#endif

float2 BinarySearch(float value)
{
#if HAS_ENVIRONMENT_TEXTURE
    int lower = 0;
    int upper = EnvironmentTextureHeight - 1;
    while (lower < upper)
    {
        int mid = (lower + upper) >> 1;
        int idx = mid * EnvironmentTextureWidth + EnvironmentTextureWidth - 1;
        if (value < EnvironmentCDF[idx])
            upper = mid;
        else
            lower = mid + 1;
    }

    int y = clamp(lower, 0, EnvironmentTextureHeight - 1);

    lower = 0;
    upper = EnvironmentTextureWidth - 1;
    while (lower < upper)
    {
        int mid = (lower + upper) >> 1;
        int idx = y * EnvironmentTextureWidth + mid;
        if (value < EnvironmentCDF[idx])
            upper = mid;
        else
            lower = mid + 1;
    }

    int x = clamp(lower, 0, EnvironmentTextureWidth - 1);
    return float2(x, y) / float2(EnvironmentTextureWidth, EnvironmentTextureHeight);
#else
  return 0.0f;
#endif
}

float4 EvalEnvMap(float3 r, float intensity)
{
#if HAS_ENVIRONMENT_TEXTURE
    float theta = acos(clamp(r.y, -1.0, 1.0));
    float r_atan = atan2(r.z, r.x);
    float2 uv = float2((PI + r_atan) * INV_TWO_PI, 1.0f - theta * INV_PI) + float2(EnvironmentMapRotation, 0.0);

    uv.x = fmod(uv.x, 1.0f);
    uv.y = fmod(uv.y, 1.0f);
    if (uv.x < 0.0f)
        uv.x += 1.0f;
    if (uv.y < 0.0f)
        uv.y += 1.0f;

    float3 color = EnvironmentTexture.SampleLevel(samplerEnvironmentTexture, uv, 0).rgb;
    float pdf = Luminance(color) / EnvironmentCdfSum;
    pdf = (pdf * EnvironmentTextureWidth * EnvironmentTextureHeight) / (TWO_PI * PI * sin(theta));
    return float4(color * intensity, pdf);
#else
  return 0.0f;
#endif
}

float4 SampleEnvMap(out float3 color, inout uint rngState)
{
#if HAS_ENVIRONMENT_TEXTURE
    float rnd = RandomFloat(rngState) * EnvironmentCdfSum;
    float2 uv = BinarySearch(rnd);
    uv.y = 1.0f - uv.y;

    color = EnvironmentTexture.SampleLevel(samplerEnvironmentTexture, uv, 0).rgb;
    float pdf = Luminance(color) / EnvironmentCdfSum;

    uv.x -= EnvironmentMapRotation;
    float phi = uv.x * TWO_PI;
    float theta = uv.y * PI;

    float sinTheta = sin(theta);
    if (sinTheta == 0.0)
        pdf = 0.0;

    return float4(-sinTheta * cos(phi), cos(theta), -sinTheta * sin(phi), (pdf * EnvironmentTextureWidth * EnvironmentTextureHeight) / (TWO_PI * PI * sinTheta));
#else
  return 0.0f;
#endif
}

float4 EnvironmentSky(float3 r, float intensity)
{
#if HAS_ENVIRONMENT_TEXTURE
    return EvalEnvMap(r, intensity);
#else
    float pdf = 1.0f / (4.0f * PI);
    return float4(EnvironmentColor * intensity, pdf);
#endif
}

// From https://raytracing.github.io/books/RayTracingInOneWeekend.html#rays,asimplecamera,andbackground/sendingraysintothescene
float4 BasicSky(float3 r, float intensity)
{
    float pdf = 1.0f / (4.0f * PI);
    float a = saturate(0.5f * (r.y + 1.0f));
    // Todo: Do we need to convert colors to linear space?
    float3 color = (1.0f - a) * (float3)1.0f + a * pow(float3(0.5f, 0.7f, 1.0f), 2.2f);
    return float4(color * intensity, pdf);
}

float4 SampleSkyRadiance(float3 direction, int rayDepth)
{
    float4 radiance = 0.0f;
    if (EnvironmentMode == SKY_MODE_ENVIRONMENT)
    {
        float intensity = 1.0f;
        if (rayDepth > 0)
            intensity = EnvironmentIntensity;
        radiance = EnvironmentSky(direction, intensity);
    }
    else if (EnvironmentMode == SKY_MODE_BASIC)
    {
        float intensity = 1.0f;
        if (rayDepth > 0)
            intensity = EnvironmentIntensity;
        radiance = BasicSky(direction, intensity);
    }

    return radiance;
}

#endif // __UNITY_PATHTRACER_SKY_HLSL__
