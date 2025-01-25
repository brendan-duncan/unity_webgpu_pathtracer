#ifndef __UNITY_PATHTRACER_TRIANGLE_ATTRIBUTES_HLSL__
#define __UNITY_PATHTRACER_TRIANGLE_ATTRIBUTES_HLSL__

// NOTE: These could be quantized and packed better
struct TriangleAttributes
{
    float3 normal0;
    float padding0;

    float3 normal1;
    float padding1;

    float3 normal2;
    float padding2;

    float3 tangent0;
    float padding3;

    float3 tangent1;
    float padding4;

    float3 tangent2;
    float padding5;

    float2 uv0;
    float2 uv1;

    float2 uv2;
    uint materialIndex;
    float padding6;
};

#endif // __UNITY_PATHTRACER_TRIANGLE_ATTRIBUTES_HLSL__
