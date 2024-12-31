#ifndef __UNITY_PATHTRACER_RAY_HLSL__
#define __UNITY_PATHTRACER_RAY_HLSL__

#include "material.hlsl"

struct Ray
{
    float3 origin;
    float3 direction;
};

struct RayHit
{
    float distance;
    float2 barycentric;
    uint triIndex;
    uint triAddr;
    uint steps;
    float3 position;
    float3 normal;
    float3 tangent;
    float2 uv;
    Material material;
    //float eta;
};

#endif // __UNITY_PATHTRACER_RAY_HLSL__
