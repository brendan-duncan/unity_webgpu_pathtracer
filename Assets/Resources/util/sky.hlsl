#ifndef __UNITY_PATHTRACER_SKY_HLSL__
#define __UNITY_PATHTRACER_SKY_HLSL__

#include "common.hlsl"

float3 BackgroundColor(float3 rayDirection)
{
    float yHeight = 0.5f * (-rayDirection.y + 1.0f);
    return (1.0f - yHeight) * float3(1.0f, 1.0f, 1.0f) + yHeight * float3(0.5f, 0.7f, 1.0f);
}

// From https://github.com/Nelarius/rayfinder
struct SkyState
{
    float params[27];
    float skyRadiances[3];
    float solarRadiances[3];
    float3 sunDirection;
};

StructuredBuffer<SkyState> skyState;

float3x3 pixarOnb(float3 n)
{
    // https://www.jcgt.org/published/0006/01/01/paper-lowres.pdf
    float s = n.z >= 0.0f ? -1.0f : 1.0f;
    float a = -1.0f / (s + n.z);
    float b = n.x * n.y * a;
    float3 u = float3(1.0f + s * n.x * n.x * a, s * b, -s * n.x);
    float3 v = float3(b, s + n.y * n.y * a, -n.y);

    return float3x3(u, v, n);
}

// `u` is a random number in [0, 1].
float3 directionInCone(float2 u, float cosThetaMax)
{
    float cosTheta = 1.0f - u.x * (1.0f - cosThetaMax);
    float sinTheta = sqrt(1.0f - cosTheta * cosTheta);
    float phi = 2.0f * PI * u.y;

    float x = cos(phi) * sinTheta;
    float y = sin(phi) * sinTheta;
    float z = cosTheta;

    return float3(x, y, z);
}

float3 sampleSolarDiskDirection(float2 u, float cosThetaMax, float3 sunDirection)
{
    float3 v = directionInCone(u, cosThetaMax);
    float3x3 onb = pixarOnb(sunDirection);
    float3 res = mul(onb, v);
    return res;
}

float skyRadiance(float theta, float gamma, uint channel)  {
    float r = skyState[0].skyRadiances[channel];
    uint idx = 9u * channel;
    float p0 = skyState[0].params[idx + 0u];
    float p1 = skyState[0].params[idx + 1u];
    float p2 = skyState[0].params[idx + 2u];
    float p3 = skyState[0].params[idx + 3u];
    float p4 = skyState[0].params[idx + 4u];
    float p5 = skyState[0].params[idx + 5u];
    float p6 = skyState[0].params[idx + 6u];
    float p7 = skyState[0].params[idx + 7u];
    float p8 = skyState[0].params[idx + 8u];

    float cosGamma = cos(gamma);
    float cosGamma2 = cosGamma * cosGamma;
    float cosTheta = abs(cos(theta));

    float expM = exp(p4 * gamma);
    float rayM = cosGamma2;
    float mieMLhs = 1.0f + cosGamma2;
    float mieMRhs = (float)pow(1.0 + p8 * p8 - 2.0 * p8 * cosGamma, 1.5f);
    float mieM = mieMLhs / mieMRhs;
    float zenith = sqrt(cosTheta);
    float radianceLhs = 1.0 + p0 * exp(p1 / (cosTheta + 0.01));
    float radianceRhs = p2 + p3 * expM + p5 * rayM + p6 * mieM + p7 * zenith;
    float radianceDist = radianceLhs * radianceRhs;

    return r * radianceDist;
}

#endif // __UNITY_PATHTRACER_SKY_HLSL__
