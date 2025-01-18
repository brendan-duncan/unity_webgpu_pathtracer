#ifndef __UNITY_PATHTRACER_RAY_HLSL__
#define __UNITY_PATHTRACER_RAY_HLSL__

#include "common.hlsl"

struct Ray
{
    float3 origin;
    float3 direction;
};

struct RayHit
{
    float3 position;
    float distance;

    float2 barycentric;
    uint triIndex;
    uint triAddr;

    float3 normal;
    uint steps;

    float3 tangent;
    float eta;

    float3 ffnormal;
    float padding;

    float2 uv;
    float2 padding2;

    Material material;
};

#endif // __UNITY_PATHTRACER_RAY_HLSL__
