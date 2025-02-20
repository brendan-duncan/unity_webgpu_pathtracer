#ifndef __UNITY_PATHRACER_SAMPLING_HLSL__
#define __UNITY_PATHRACER_SAMPLING_HLSL__

#include "common.hlsl"

float GTR1(float NDotH, float a)
{
    if (a >= 1.0)
    {
        return INV_PI;
    }
    else
    {
        float a2 = a * a;
        float t = 1.0 + (a2 - 1.0) * NDotH * NDotH;
        return (a2 - 1.0) / (PI * log(a2) * t);
    }
}

float3 SampleGTR1(float rgh, float r1, float r2)
{
    float a = max(0.001, rgh);
    float a2 = a * a;

    float phi = r1 * TWO_PI;

    float cosTheta = sqrt((1.0 - pow(a2, 1.0 - r2)) / (1.0 - a2));
    float sinTheta = clamp(sqrt(1.0 - (cosTheta * cosTheta)), 0.0, 1.0);
    float sinPhi = sin(phi);
    float cosPhi = cos(phi);

    return float3(sinTheta * cosPhi, sinTheta * sinPhi, cosTheta);
}

float GTR2(float NDotH, float a)
{
    float a2 = a * a;
    float t = 1.0 + (a2 - 1.0) * NDotH * NDotH;
    return a2 / (PI * t * t);
}

float3 SampleGTR2(float rgh, float r1, float r2)
{
    float a = max(0.001, rgh);

    float phi = r1 * TWO_PI;

    float cosTheta = sqrt((1.0 - r2) / (1.0 + (a * a - 1.0) * r2));
    float sinTheta = clamp(sqrt(1.0 - (cosTheta * cosTheta)), 0.0, 1.0);
    float sinPhi = sin(phi);
    float cosPhi = cos(phi);

    return float3(sinTheta * cosPhi, sinTheta * sinPhi, cosTheta);
}

float3 SampleGGXVNDF(float3 V, float ax, float ay, float r1, float r2)
{
    float3 Vh = normalize(float3(ax * V.x, ay * V.y, V.z));

    float lensq = Vh.x * Vh.x + Vh.y * Vh.y;
    float3 T1 = lensq > 0 ? float3(-Vh.y, Vh.x, 0) * rsqrt(lensq) : float3(1, 0, 0);
    float3 T2 = cross(Vh, T1);

    float r = sqrt(r1);
    float phi = 2.0 * PI * r2;
    float t1 = r * cos(phi);
    float t2 = r * sin(phi);
    float s = 0.5 * (1.0 + Vh.z);
    t2 = (1.0 - s) * sqrt(1.0 - t1 * t1) + s * t2;

    float3 Nh = t1 * T1 + t2 * T2 + sqrt(max(0.0, 1.0 - t1 * t1 - t2 * t2)) * Vh;

    return normalize(float3(ax * Nh.x, ay * Nh.y, max(0.0, Nh.z)));
}

float GTR2Aniso(float NDotH, float HDotX, float HDotY, float ax, float ay)
{
    float a = HDotX / ax;
    float b = HDotY / ay;
    float c = a * a + b * b + NDotH * NDotH;
    return 1.0 / (PI * ax * ay * c * c);
}

float3 SampleGTR2Aniso(float ax, float ay, float r1, float r2)
{
    float phi = r1 * TWO_PI;

    float sinPhi = ay * sin(phi);
    float cosPhi = ax * cos(phi);
    float tanTheta = sqrt(r2 / (1 - r2));

    return float3(tanTheta * cosPhi, tanTheta * sinPhi, 1.0);
}

float SmithG(float NDotV, float alphaG)
{
    float a = alphaG * alphaG;
    float b = NDotV * NDotV;
    return (2.0 * NDotV) / (NDotV + sqrt(a + b - a * b));
}

float SmithGAniso(float NDotV, float VDotX, float VDotY, float ax, float ay)
{
    float a = VDotX * ax;
    float b = VDotY * ay;
    float c = NDotV;
    return (2.0 * NDotV) / (NDotV + sqrt(a * a + b * b + c * c));
}

float SchlickWeight(float u)
{
    float m = clamp(1.0 - u, 0.0, 1.0);
    float m2 = m * m;
    return m2 * m2 * m;
}

float DielectricFresnel(float cosThetaI, float eta)
{
    float sinThetaTSq = eta * eta * (1.0f - cosThetaI * cosThetaI);

    // Total internal reflection
    if (sinThetaTSq > 1.0)
    {
        return 1.0;
    }
    else
    {
        float cosThetaT = sqrt(max(1.0 - sinThetaTSq, 0.0));

        float rs = (eta * cosThetaT - cosThetaI) / (eta * cosThetaT + cosThetaI);
        float rp = (eta * cosThetaI - cosThetaT) / (eta * cosThetaI + cosThetaT);

        return 0.5f * (rs * rs + rp * rp);
    }
}

float3 CosineSampleHemisphere(float r1, float r2)
{
    float3 dir;
    float r = sqrt(r1);
    float phi = TWO_PI * r2;
    dir.x = r * cos(phi);
    dir.y = r * sin(phi);
    dir.z = sqrt(max(0.0, 1.0 - dir.x * dir.x - dir.y * dir.y));
    return dir;
}

float3 UniformSampleHemisphere(float r1, float r2)
{
    float r = sqrt(max(0.0, 1.0 - r1 * r1));
    float phi = TWO_PI * r2;
    return float3(r * cos(phi), r * sin(phi), r1);
}

float3 UniformSampleSphere(float r1, float r2)
{
    float z = 1.0 - 2.0 * r1;
    float r = sqrt(max(0.0, 1.0 - z * z));
    float phi = TWO_PI * r2;
    return float3(r * cos(phi), r * sin(phi), z);
}

float PowerHeuristic(float a, float b)
{
    float t = a * a;
    return t / (b * b + t);
}

float3 SampleHG(float3 V, float g, float r1, float r2)
{
    float cosTheta;

    if (abs(g) < 0.001)
    {
        cosTheta = 1 - 2 * r2;
    }
    else 
    {
        float sqrTerm = (1 - g * g) / (1 + g - 2 * g * r2);
        cosTheta = -(1 + g * g - sqrTerm * sqrTerm) / (2 * g);
    }

    float phi = r1 * TWO_PI;
    float sinTheta = clamp(sqrt(1.0 - (cosTheta * cosTheta)), 0.0, 1.0);
    float sinPhi = sin(phi);
    float cosPhi = cos(phi);

    float3x3 onb = GetONB(V);

    return sinTheta * cosPhi * onb[0] + sinTheta * sinPhi * onb[1] + cosTheta * onb[2];
}

float PhaseHG(float cosTheta, float g)
{
    float denom = 1 + g * g + 2 * g * cosTheta;
    return INV_4_PI * (1 - g * g) / (denom * sqrt(denom));
}

#endif // __UNITY_PATHRACER_SAMPLING_HLSL__
