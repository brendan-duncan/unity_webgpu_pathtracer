#ifndef __UNITY_PATHTRACER_COMMON__
#define __UNITY_PATHTRACER_COMMON__

#define PI  3.14159265359f
#define DEGREES_TO_RADIANS (PI / 180.0f)

uint TotalRays;
uint CurrentSample;
float FarPlane;

uint OutputWidth;
uint OutputHeight;
RWTexture2D<float4> Output;
Texture2D<float4> AccumulatedOutput;

float3x3 GetBasisMatrix(float3 n)
{
    // https://www.jcgt.org/published/0006/01/01/paper-lowres.pdf
    float s = n.z >= 0.0f ? -1.0f : 1.0f;
    float a = -1.0f / (s + n.z);
    float b = n.x * n.y * a;
    float3 u = float3(1.0f + s * n.x * n.x * a, s * b, -s * n.x);
    float3 v = float3(b, s + n.y * n.y * a, -n.y);
    return float3x3(u, v, n);
}

#endif // __UNITY_PATHTRACER_COMMON__
