#ifndef __UNITY_PATHTRACER_CAMERA_HLSL__
#define __UNITY_PATHTRACER_CAMERA_HLSL__

#include "ray.hlsl"

float4x4 CamToWorld;
float4x4 CamInvProj;

Ray GetScreenRay(float2 pixelCoords)
{
    float3 origin = mul(CamToWorld, float4(0.0f, 0.0f, 0.0f, 1.0f)).xyz;

    // Compute world space direction
    float2 uv = float2(pixelCoords.xy / float2(OutputWidth, OutputHeight) * 2.0f - 1.0f);
    float3 direction = mul(CamInvProj, float4(uv, 0.0f, 1.0f)).xyz;
    direction = mul(CamToWorld, float4(direction, 0.0f)).xyz;
    direction = normalize(direction);

    Ray ray = {origin, direction};
    return ray;
}

#endif // __UNITY_PATHTRACER_CAMERA_HLSL__
