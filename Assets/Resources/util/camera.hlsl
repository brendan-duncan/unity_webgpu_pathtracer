#ifndef __UNITY_PATHTRACER_CAMERA_HLSL__
#define __UNITY_PATHTRACER_CAMERA_HLSL__

#include "common.hlsl"
#include "random.hlsl"

float4x4 CamToWorld;
float4x4 CamInvProj;
float Aperture;
float FocalLength;


Ray GetScreenRay(float2 pixelCoords, inout uint rngState)
{
    float3 origin = mul(CamToWorld, float4(0.0f, 0.0f, 0.0f, 1.0f)).xyz;

    // Compute world space direction
    float2 uv = float2(pixelCoords.xy / float2(OutputWidth, OutputHeight) * 2.0f - 1.0f);
    float3 direction = mul(CamInvProj, float4(uv, 0.0f, 1.0f)).xyz;
    direction = normalize(mul(CamToWorld, float4(direction, 0.0f)).xyz);

    if (Aperture > 0 && FocalLength > 0)
    {
        float sampleLensU = RandomFloat(rngState);
        float sampleLensV = RandomFloat(rngState);
        float lensU, lensV;
        ConcentricSampleDisk(sampleLensU, sampleLensV, lensU, lensV);

        float lensRadius = Aperture * 0.5f;
        lensU *= lensRadius;
        lensV *= lensRadius;

        float ft = FocalLength;
        float3 focalPoint = origin + direction * ft;

        origin = mul(CamToWorld, float4(lensU, lensV, 0.0f, 1.0f)).xyz;
        direction = normalize(focalPoint - origin);
    }

    Ray ray = {origin, 0.0f, direction, 0.0f};
    return ray;
}

#endif // __UNITY_PATHTRACER_CAMERA_HLSL__
