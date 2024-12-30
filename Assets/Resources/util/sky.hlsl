#ifndef __UNITY_PATHTRACER_SKY_HLSL__
#define __UNITY_PATHTRACER_SKY_HLSL__

#include "common.hlsl"

int EnvironmentMode;
float EnvironmentIntensity;

#if HAS_ENVIRONMENT_TEXTURE
Texture2D<float4> EnvironmentTexture;
SamplerState samplerEnvironmentTexture;
StructuredBuffer<float> EnvironmentCDF;
float EnvironmentCdfSum;
#endif

#define TERRESTRIAL_SOLAR_RADIUS (0.255f * DEGREES_TO_RADIANS)
#define SOLAR_COS_THETA_MAX cos(TERRESTRIAL_SOLAR_RADIUS)
#define SOLAR_INV_PDF (2.0f * PI * (1.0f - SOLAR_COS_THETA_MAX))

float3 BackgroundColor(float3 rayDirection)
{
#if HAS_ENVIRONMENT_TEXTURE
    float2 longlat = float2(atan2(rayDirection.x, rayDirection.z) + PI, acos(-rayDirection.y));
    float2 uv = longlat / float2(2.0 * PI, PI);
    uv.x = fmod(abs(uv.x), 1.0f);
    uv.y = fmod(abs(uv.y), 1.0f);
    return EnvironmentTexture.SampleLevel(samplerEnvironmentTexture, uv, 0).rgb;
#else
    float yHeight = 0.5f * (-rayDirection.y + 1.0f);
    return ((1.0f - yHeight) * float3(1.0f, 1.0f, 1.0f) + yHeight * float3(0.5f, 0.7f, 1.0f));
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
    //float3 X = 0.0f;
    //float3 Y = 0.0f;
    //GetONB(sunDirection, X, Y);
    //float3 res = ToLocal(X, Y, sunDirection, v);
    float3x3 onb = GetONB(sunDirection);
    float3 res = ToLocal(onb, v);
    return res;
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


float3 SampleSkyRadiance(float3 direction, int rayDepth)
{
    float3 radiance = 0.0f;
    if (EnvironmentMode == 1)
    {
        float3 sunDirection = SkyStateBuffer[0].sunDirection;

        float theta = acos(direction.y);
        float gamma = acos(clamp(dot(direction, sunDirection), -1.0, 1.0));

        radiance = float3(
            SkyRadiance(theta, gamma, 0),
            SkyRadiance(theta, gamma, 1),
            SkyRadiance(theta, gamma, 2)
        );

        if (rayDepth == 0)
        {
            radiance *= 0.25f;
        }
    }
    else
    {
        radiance = BackgroundColor(direction);
    }

    if (rayDepth > 0)
    {
        radiance *= EnvironmentIntensity;
    }

    return radiance;
}

#endif // __UNITY_PATHTRACER_SKY_HLSL__
