#ifndef __UNITY_PATHTRACER_MATERIAL_HLSL__
#define __UNITY_PATHTRACER_MATERIAL_HLSL__

struct Material
{
    float4 albedoTransmission;
    float4 emission;
    float2 metallicRoughness;
    float mode;
    float ior;
    float4 textures;
};
StructuredBuffer<Material> Materials;

struct TextureDescriptor
{
    uint width;
    uint height;
    uint offset;
    uint padding;
};

#if HAS_TEXTURES
StructuredBuffer<TextureDescriptor> TextureDescriptors;
StructuredBuffer<uint> TextureData;
#endif

float3 GetAlbedoColor(Material material, float2 uv)
{
#if HAS_TEXTURES
    if (material.textures.x < 0.0f)
    {
        return material.albedoTransmission.rgb + material.emission.rgb;
    }
    
    uint textureIndex = (uint)material.textures.x;

    uint offset = TextureDescriptors[textureIndex].offset;
    uint width = TextureDescriptors[textureIndex].width;
    uint height = TextureDescriptors[textureIndex].height;

    uv.x = fmod(abs(uv.x), 1.0f);
    uv.y = fmod(abs(uv.y), 1.0f);

    uint x = (uint)(uv.x * (width - 1));
    uint y = (uint)(uv.y * (height - 1));
    uint pixelOffset = offset + (y * width + x);

    uint pixelData = TextureData[pixelOffset];
    uint r = (pixelData >> 0) & 0xFF;
    uint g = (pixelData >> 8) & 0xFF;
    uint b = (pixelData >> 16) & 0xFF;

    return float3(r / 255.0f, g / 255.0f, b / 255.0f) + material.emission.rgb;
#else
    return material.albedoTransmission.rgb + material.emission.rgb;
#endif
}

#endif // __UNITY_PATHTRACER_MATERIAL_HLSL__
