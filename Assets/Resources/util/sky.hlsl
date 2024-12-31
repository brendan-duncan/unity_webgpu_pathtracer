#ifndef __UNITY_PATHTRACER_SKY_HLSL__
#define __UNITY_PATHTRACER_SKY_HLSL__

#include "common.hlsl"

int EnvironmentMode;
float EnvironmentIntensity;

#if HAS_ENVIRONMENT_TEXTURE
Texture2D<float4> EnvironmentTexture;
SamplerState samplerEnvironmentTexture;
StructuredBuffer<float> EnvironmentCDF;
int EnvironmentTextureWidth;
int EnvironmentTextureHeight;
float EnvironmentCdfSum;
#endif

#define TERRESTRIAL_SOLAR_RADIUS (0.255f * DEGREES_TO_RADIANS)
#define SOLAR_COS_THETA_MAX cos(TERRESTRIAL_SOLAR_RADIUS)
#define SOLAR_INV_PDF (2.0f * PI * (1.0f - SOLAR_COS_THETA_MAX))

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
        {
            upper = mid;
        }
        else
        {
            lower = mid + 1;
        }
    }

    int y = clamp(lower, 0, EnvironmentTextureHeight - 1);

    lower = 0;
    upper = EnvironmentTextureWidth - 1;
    while (lower < upper)
    {
        int mid = (lower + upper) >> 1;
        int idx = y * EnvironmentTextureWidth + mid;
        if (value < EnvironmentCDF[idx])
        {
            upper = mid;
        }
        else
        {
            lower = mid + 1;
        }
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
    float2 uv = float2((PI + r_atan) * INV_TWO_PI, 1.0f - theta * INV_PI);// + float2(envMapRot, 0.0);

    uv.x = fmod(abs(uv.x), 1.0f);
    uv.y = fmod(abs(uv.y), 1.0f);

    float3 color = EnvironmentTexture.SampleLevel(samplerEnvironmentTexture, uv, 0).rgb;
    float pdf = Luminance(color) / EnvironmentCdfSum;
    pdf = (pdf * EnvironmentTextureWidth * EnvironmentTextureHeight) / (TWO_PI * PI * sin(theta));
    return float4(color * intensity, pdf);
#else
  return 0.0f;
#endif
}

float4 SampleEnvMap(inout float3 color, inout uint rngSeed)
{
#if HAS_ENVIRONMENT_TEXTURE
    float rnd = RandomFloat(rngSeed) * EnvironmentCdfSum;
    float2 uv = BinarySearch(rnd);

    color = EnvironmentTexture.SampleLevel(samplerEnvironmentTexture, uv, 0).rgb;
    float pdf = Luminance(color) / EnvironmentCdfSum;

    //uv.x -= envMapRot;
    float phi = uv.x * TWO_PI;
    float theta = uv.y * PI;

    if (sin(theta) == 0.0)
    {
        pdf = 0.0;
    }

    return float4(-sin(theta) * cos(phi), cos(theta), -sin(theta) * sin(phi), (pdf * EnvironmentTextureWidth * EnvironmentTextureHeight) / (TWO_PI * PI * sin(theta)));
#else
  return 0.0f;
#endif
}

float4 BackgroundColor(float3 r, float intensity)
{
#if HAS_ENVIRONMENT_TEXTURE
    return EvalEnvMap(r, rayDepth);
#else
    float pdf = 1.0f / (4.0f * PI);
    float yHeight = 0.5f * (-r.y + 1.0f);
    return float4(((1.0f - yHeight) * (float3)1.0f + yHeight * float3(0.5f, 0.7f, 1.0f)) * intensity, pdf);
#endif
}

// From https://github.com/Nelarius/rayfinder
struct SkyState
{
    float params[27];
    float skyRadiances[3];
    float solarRadiances[3];
    float3 sunDirection;
};

StructuredBuffer<SkyState> SkyStateBuffer;

// `u` is a random number in [0, 1].
float3 DirectionInCone(float2 u, float cosThetaMax)
{
    float cosTheta = 1.0f - u.x * (1.0f - cosThetaMax);
    float sinTheta = sqrt(1.0f - cosTheta * cosTheta);
    float phi = 2.0f * PI * u.y;

    float x = cos(phi) * sinTheta;
    float y = sin(phi) * sinTheta;
    float z = cosTheta;

    return float3(x, y, z);
}

float3 SampleSolarDiskDirection(float2 u, float cosThetaMax, float3 sunDirection)
{
    float3 v = DirectionInCone(u, cosThetaMax);
    float3x3 onb = GetONB(sunDirection);
    return ToLocal(onb, v);
}

float SkyRadiance(float theta, float gamma, uint channel)  {
    SkyState skyState = SkyStateBuffer[0];
    float r = skyState.skyRadiances[channel];
    uint idx = 9u * channel;
    float p0 = skyState.params[idx + 0u];
    float p1 = skyState.params[idx + 1u];
    float p2 = skyState.params[idx + 2u];
    float p3 = skyState.params[idx + 3u];
    float p4 = skyState.params[idx + 4u];
    float p5 = skyState.params[idx + 5u];
    float p6 = skyState.params[idx + 6u];
    float p7 = skyState.params[idx + 7u];
    float p8 = skyState.params[idx + 8u];

    float cosGamma = cos(gamma);
    float cosGamma2 = cosGamma * cosGamma;
    float cosTheta = abs(cos(theta));

    float expM = exp(p4 * gamma);
    float rayM = cosGamma2;
    float mieMLhs = 1.0f + cosGamma2;
    float mieMRhs = (float)pow(abs(1.0 + p8 * p8 - 2.0 * p8 * cosGamma), 1.5f);
    float mieM = mieMLhs / mieMRhs;
    float zenith = sqrt(cosTheta);
    float radianceLhs = 1.0 + p0 * exp(p1 / (cosTheta + 0.01));
    float radianceRhs = p2 + p3 * expM + p5 * rayM + p6 * mieM + p7 * zenith;
    float radianceDist = radianceLhs * radianceRhs;

    return (r * radianceDist);
}


float4 SampleSkyRadiance(float3 direction, int rayDepth)
{
    float4 radiance = 0.0f;
    if (EnvironmentMode == 1)
    {
        float3 sunDirection = SkyStateBuffer[0].sunDirection;

        float theta = acos(direction.y);
        float gamma = acos(clamp(dot(direction, sunDirection), -1.0, 1.0));
        float pdf = SOLAR_INV_PDF;
        float scale = 1.0f;
        if (rayDepth == 0)
            scale = 0.25f; // The sky is a bit bright for display
        else
            scale = EnvironmentIntensity;

        radiance = float4(
            SkyRadiance(theta, gamma, 0) * scale,
            SkyRadiance(theta, gamma, 1) * scale,
            SkyRadiance(theta, gamma, 2) * scale,
            pdf
        );
    }
    else
    {
        float intensity = 1.0f;
        if (rayDepth > 0)
            intensity = EnvironmentIntensity;
        radiance = BackgroundColor(direction, intensity);
    }

    return radiance;
}

#endif // __UNITY_PATHTRACER_SKY_HLSL__
