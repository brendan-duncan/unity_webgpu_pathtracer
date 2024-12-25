#ifndef __UNITY_PATHTRACER_MATERIAL_HLSL__
#define __UNITY_PATHTRACER_MATERIAL_HLSL__

struct Material
{
    float4 albedo;
    float2 metalicSmoothness;
    float mode;
    float ior;
};

RWStructuredBuffer<Material> MaterialBuffer;

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

float3 GetAlbedoColor(Material material, float2 uv)
{
    if (material.albedo.a < 0.0f)
    {
        return material.albedo.rgb;
    }
    
    const uint index = (uint)material.albedo.a;
    switch (index)
    {
        case 0: return AlbedoTexture1.SampleLevel(samplerAlbedoTexture1, uv, 0).rgb;
        case 1: return AlbedoTexture2.SampleLevel(samplerAlbedoTexture2, uv, 0).rgb;
        case 2: return AlbedoTexture3.SampleLevel(samplerAlbedoTexture3, uv, 0).rgb;
        case 3: return AlbedoTexture4.SampleLevel(samplerAlbedoTexture4, uv, 0).rgb;
        case 4: return AlbedoTexture5.SampleLevel(samplerAlbedoTexture5, uv, 0).rgb;
        case 5: return AlbedoTexture6.SampleLevel(samplerAlbedoTexture6, uv, 0).rgb;
        case 6: return AlbedoTexture7.SampleLevel(samplerAlbedoTexture7, uv, 0).rgb;
        case 7: return AlbedoTexture8.SampleLevel(samplerAlbedoTexture8, uv, 0).rgb;
        default: return AlbedoTexture1.SampleLevel(samplerAlbedoTexture1, uv, 0).rgb;
    }

    return material.albedo.rgb;
}

#endif // __UNITY_PATHTRACER_MATERIAL_HLSL__
