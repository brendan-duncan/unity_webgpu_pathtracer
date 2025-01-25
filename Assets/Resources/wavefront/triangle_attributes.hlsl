#ifndef __UNITY_PATHTRACER_TRIANGLE_ATTRIBUTES_HLSL__
#define __UNITY_PATHTRACER_TRIANGLE_ATTRIBUTES_HLSL__

// NOTE: These could be quantized and packed better
struct TriangleAttributes
{
    float3 normal0;
    float3 normal1;
    float3 normal2;

    float3 tangent0;
    float3 tangent1;
    float3 tangent2;

    float2 uv0;
    float2 uv1;
    float2 uv2;

    uint materialIndex;
};

#endif // __UNITY_PATHTRACER_TRIANGLE_ATTRIBUTES_HLSL__
