#ifndef __UNITY_TINYBVH_COMMON__
#define __UNITY_TINYBVH_COMMON__

struct Ray
{
    float3 origin;
    float3 direction;
};

// NOTE: These could be quantized and packed better
struct TriangleAttributes
{
    float3 normal0;
    float3 normal1;
    float3 normal2;
    
    float2 uv0;
    float2 uv1;
    float2 uv2;

    uint materialIndex;
};

struct Material
{
    float4 albedo;
    float2 metalicSmoothness;
    float mode;
    float ior;
};

struct RayHit
{
    float t;
    float2 barycentric;
    uint triIndex;
    uint steps;
    float3 position;
    float3 normal;
    float2 uv;
    Material material;
};

uint TotalRays;
RWStructuredBuffer<Ray> RayBuffer;
RWStructuredBuffer<RayHit> RayHitBuffer;
RWStructuredBuffer<TriangleAttributes> TriangleAttributesBuffer;
RWStructuredBuffer<Material> MaterialBuffer;
RWStructuredBuffer<uint> RNGStateBuffer;

uint CurrentSample;
float FarPlane;
uint OutputWidth;
uint OutputHeight;
RWTexture2D<float4> Output;
Texture2D<float4> AccumulatedOutput;

uint AlbedoTextureCount;
Texture2D<float4> AlbedoTexture1;
SamplerState samplerAlbedoTexture1;
Texture2D<float4> AlbedoTexture2;
SamplerState samplerAlbedoTexture2;
Texture2D<float4> AlbedoTexture3;
SamplerState samplerAlbedoTexture3;
Texture2D<float4> AlbedoTexture4;
SamplerState samplerAlbedoTexture4;
Texture2D<float4> AlbedoTexture5;
SamplerState samplerAlbedoTexture5;
Texture2D<float4> AlbedoTexture6;
SamplerState samplerAlbedoTexture6;
Texture2D<float4> AlbedoTexture7;
SamplerState samplerAlbedoTexture7;
Texture2D<float4> AlbedoTexture8;
SamplerState samplerAlbedoTexture8;

/*Texture2D<float4> GetAlbedoTexture(uint index)
{
    switch (index)
    {
        case 0: return AlbedoTexture1;
        case 1: return AlbedoTexture2;
        case 2: return AlbedoTexture3;
        case 3: return AlbedoTexture4;
        case 4: return AlbedoTexture5;
        case 5: return AlbedoTexture6;
        case 6: return AlbedoTexture7;
        case 7: return AlbedoTexture8;
        default: return AlbedoTexture1;
    }
}*/

/*SamplerState GetAlbedoSampler(uint index)
{
    switch (index)
    {
        case 0: return sampler_AlbedoTexture1;
        case 1: return sampler_AlbedoTexture1;
        case 2: return sampler_AlbedoTexture1;
        case 3: return sampler_AlbedoTexture1;
        case 4: return sampler_AlbedoTexture1;
        case 5: return sampler_AlbedoTexture1;
        case 6: return sampler_AlbedoTexture1;
        case 7: return sampler_AlbedoTexture1;
        default: return sampler_AlbedoTexture1;
    }
}*/

float3 GetAlbedoColor(RayHit hit)
{
    if (hit.material.albedo.a < 0.0f)
    {
        return hit.material.albedo.rgb;
    }
    
    uint index = (uint)(hit.material.albedo.a);
    switch (index)
    {
        case 0: return AlbedoTexture1.SampleLevel(samplerAlbedoTexture1, hit.uv, 0).rgb;
        case 1: return AlbedoTexture2.SampleLevel(samplerAlbedoTexture2, hit.uv, 0).rgb;
        case 2: return AlbedoTexture3.SampleLevel(samplerAlbedoTexture3, hit.uv, 0).rgb;
        case 3: return AlbedoTexture4.SampleLevel(samplerAlbedoTexture4, hit.uv, 0).rgb;
        case 4: return AlbedoTexture5.SampleLevel(samplerAlbedoTexture5, hit.uv, 0).rgb;
        case 5: return AlbedoTexture6.SampleLevel(samplerAlbedoTexture6, hit.uv, 0).rgb;
        case 6: return AlbedoTexture7.SampleLevel(samplerAlbedoTexture7, hit.uv, 0).rgb;
        case 7: return AlbedoTexture8.SampleLevel(samplerAlbedoTexture8, hit.uv, 0).rgb;
        default: return AlbedoTexture1.SampleLevel(samplerAlbedoTexture1, hit.uv, 0).rgb;
    }

    return hit.material.albedo.rgb;
}

// Narkowicz 2015, "ACES Filmic Tone Mapping Curve"
float3 aces(float3 x)
{
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    return saturate(x * (a * x + b)) / (x * (c * x + d) + e);
}

// Filmic Tonemapping Operators http://filmicworlds.com/blog/filmic-tonemapping-operators/
float3 filmic(float3 x)
{
    float3 X = max(float3(0.0, 0.0, 0.0), x - 0.004);
    float3 result = (X * (6.2 * X + 0.5)) / (X * (6.2 * X + 1.7) + 0.06);
    return pow(result, float3(2.2, 2.2, 2.2));
}

// Lottes 2016, "Advanced Techniques and Optimization of HDR Color Pipelines"
float3 lottes(float3 x)
{
    const float3 a = float3(1.6, 1.6, 1.6);
    const float3 d = float3(0.977, 0.977, 0.977);
    const float3 hdrMax = float3(8.0, 8.0, 8.0);
    const float3 midIn = float3(0.18, 0.18, 0.18);
    const float3 midOut = float3(0.267, 0.267, 0.267);

    float3 b =
        (-pow(midIn, a) + pow(hdrMax, a) * midOut) /
        ((pow(hdrMax, a * d) - pow(midIn, a * d)) * midOut);
    float3 c =
        (pow(hdrMax, a * d) * pow(midIn, a) - pow(hdrMax, a) * pow(midIn, a * d) * midOut) /
        ((pow(hdrMax, a * d) - pow(midIn, a * d)) * midOut);

    return pow(x, a) / (pow(x, a * d) * b + c);
}

float3 reinhard(float3 x)
{
    return x / (1.0 + x);
}

#endif