#ifndef __UNITY_PATHRACER_TEXTURE_HLSL__
#define __UNITY_PATHRACER_TEXTURE_HLSL__

#include "globals.hlsl"

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
        uint descriptorOffset = textureIndex * 4;
        uint width = TextureData[descriptorOffset + 0];
        uint height = TextureData[descriptorOffset + 1];
        uint offset = TextureData[descriptorOffset + 2];

        float u = uv.x;
        float v = uv.y;
        if (u > 1.0f)
            u -= 1.0f;
        if (v > 1.0f)
            v -= 1.0f;
        if (u < 0.0f)
            u += 1.0f;
        if (v < 0.0f)
            v += 1.0f;

        float tu = u * (width - 1.0f);
        float tv = v * (height - 1.0f);

        uint tx = (uint)tu;
        uint ty = (uint)tv;

        float4 p1 = GetTexturePixel(offset, width, height, tx, ty);

        if (!linearSample)
        {
            return p1;
        }
        else
        {
            float uFraction = tu - tx;
            float vFraction = tv - ty;
            float4 p2 = GetTexturePixel(offset, width, height, tx + 1, ty);
            float4 p3 = GetTexturePixel(offset, width, height, tx, ty + 1);
            float4 p4 = GetTexturePixel(offset, width, height, tx + 1, ty + 1);
            float4 pixel = lerp(lerp(p1, p2, uFraction), lerp(p3, p4, uFraction), vFraction);
            return pixel;
        }
    }
#else
    return 0.0f;
#endif
}

#endif // __UNITY_PATHRACER_TEXTURE_HLSL__
