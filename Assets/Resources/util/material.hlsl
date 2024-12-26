#ifndef __UNITY_PATHTRACER_MATERIAL_HLSL__
#define __UNITY_PATHTRACER_MATERIAL_HLSL__

struct Material
{
    float4 albedo;
    float2 metalicSmoothness;
    float mode;
    float ior;
};
StructuredBuffer<Material> Materials;

struct TextureDescriptor
{
    uint width;
    uint height;
    uint offset;
    uint padding;
};
StructuredBuffer<TextureDescriptor> TextureDescriptors;
StructuredBuffer<float4> TextureData;

float3 GetAlbedoColor(Material material, float2 uv)
{
    if (material.albedo.a < 0.0f)
    {
        return material.albedo.rgb;
    }
    
    uint index = (uint)material.albedo.a;

    uint offset = TextureDescriptors[index].offset;
    uint width = TextureDescriptors[index].width;
    uint height = TextureDescriptors[index].height;

    uint x = (uint)(uv.x * (width - 1));
    uint y = (uint)(uv.y * (height - 1));
    uint pixelOffset = offset + (y * width + x);

    return TextureData[pixelOffset].rgb;

    /*uint pixelData = TextureData.Load(pixelOffset);
    uint r = (pixelData >> 0) & 0xFF;
    uint g = (pixelData >> 8) & 0xFF;
    uint b = (pixelData >> 16) & 0xFF;

    return float3(r / 255.0f, g / 255.0f, b / 255.0f);*/
    //return material.albedo.rgb;
}

#endif // __UNITY_PATHTRACER_MATERIAL_HLSL__
