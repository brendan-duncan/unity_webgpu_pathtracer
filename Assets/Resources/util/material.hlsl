#ifndef __UNITY_PATHTRACER_MATERIAL_HLSL__
#define __UNITY_PATHTRACER_MATERIAL_HLSL__

struct Material
{
    float4 data1;
    float4 data2;
    float4 data3;
    float4 data4;
    float4 data5;
    float4 data6;
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

float4 GetTexturePixel(uint textureDataOffset, uint width, uint height, uint x, uint y)
{
#if HAS_TEXTURES
    x = min(x, width - 1);
    y = min(y, height - 1);

    uint pixelOffset = textureDataOffset + (y * width + x);

    uint pixelData = TextureData[pixelOffset];
    float r = (pixelData & 0xFF) / 255.0f;
    float g = ((pixelData >> 8) & 0xFF) / 255.0f;
    float b = ((pixelData >> 16) & 0xFF) / 255.0f;
    float a = ((pixelData >> 24) & 0xFF) / 255.0f;
    return float4(r, g, b, a);
#else
    return float4(0.0f, 0.0f, 0.0f, 1.0f);
#endif
}

float4 SampleTexture(int textureIndex, float2 uv, bool linearSample)
{
#if HAS_TEXTURES
    if (textureIndex < 0)
    {
        return 0.0f;
    }
    else
    {
        uint offset = TextureDescriptors[textureIndex].offset;
        uint width = TextureDescriptors[textureIndex].width;
        uint height = TextureDescriptors[textureIndex].height;

        uv.x = fmod(uv.x, 1.0f);
        uv.y = fmod(uv.y, 1.0f);
        if (uv.x < 0.0f)
        {
            uv.x += 1.0f;
        }
        if (uv.y < 0.0f)
        {
            uv.y += 1.0f;
        }

        float u = uv.x * (width - 1.0f);
        float v = uv.y * (height - 1.0f);

        uint x = (uint)(u);
        uint y = (uint)(v);

        float4 p1 = GetTexturePixel(offset, width, height, x, y);

        if (!linearSample)
        {
            return p1;
        }
        else
        {
            float uFraction = u - x;
            float vFraction = v - y;
            float4 p2 = GetTexturePixel(offset, width, height, x + 1, y);
            float4 p3 = GetTexturePixel(offset, width, height, x, y + 1);
            float4 p4 = GetTexturePixel(offset, width, height, x + 1, y + 1);

            float4 pixel = lerp(lerp(p1, p2, uFraction), lerp(p3, p4, uFraction), vFraction);

            return pixel;
        }
    }
#else
    return 0.0f;
#endif
}

float3 GetEmission(Material material, float2 uv)
{
    #if HAS_TEXTURES
    if (material.textures.w < 0.0f)
    {
        return material.data2.rgb;
    }
    else
    {
        float4 pixel = SampleTexture((int)material.textures.w, uv, true);
        return pixel.rgb;
    }
#else
    return material.data2.rgb;
#endif
}

float3 GetNormalMapSample(Material material, float2 uv)
{
#if HAS_TEXTURES
    if (material.textures.z < 0.0f)
    {
        return float3(0.0f, 0.0f, 1.0f);
    }
    else
    {
        float4 pixel = SampleTexture((int)material.textures.z, uv, false);
        return normalize(2.0f * pixel.rgb - 1.0f);
    }
#else
    return float3(0.0f, 0.0f, 1.0f);
#endif
}

float2 GetMetallicRoughness(Material material, float2 uv)
{
#if HAS_TEXTURES
    if (material.textures.y < 0.0f)
    {
        return material.data3.rg;
    }
    else
    {
        float4 pixel = SampleTexture((int)material.textures.y, uv, true);
        return float2(pixel.b, pixel.g * pixel.g);
    }
#else
    return material.data3.rg;
#endif
}

float4 GetBaseColorOpacity(Material material, float2 uv)
{
#if HAS_TEXTURES
    if (material.textures.x < 0.0f)
    {
        return material.data1;
    }
    else
    {  
        return SampleTexture((int)material.textures.x, uv, true);
    }
#else
    return material.data1;
#endif
}

#endif // __UNITY_PATHTRACER_MATERIAL_HLSL__
