#ifndef __UNITY_PATHTRACER_SKY_HLSL__
#define __UNITY_PATHTRACER_SKY_HLSL__

#include "common.hlsl"

#define SKY_MODE_ENVIRONMENT 0
#define SKY_MODE_BASIC 1
#define SKY_MODE_PHYSICAL 2

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

#define TERRESTRIAL_SOLAR_RADIUS 0.0044505896f // (0.255f * DEGREES_TO_RADIANS)
#define SOLAR_COS_THETA_MAX 0.99999009614f // cos(TERRESTRIAL_SOLAR_RADIUS)
#define SOLAR_INV_PDF 0.00006222777f // (2.0f * PI * (1.0f - SOLAR_COS_THETA_MAX))

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
    else if (EnvironmentMode == SKY_MODE_PHYSICAL)
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

    return radiance;
}

#endif // __UNITY_PATHTRACER_SKY_HLSL__
