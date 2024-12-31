#ifndef __UNITY_PATHTRACER_MATERIAL_HLSL__
#define __UNITY_PATHTRACER_MATERIAL_HLSL__

#define ALPHA_MODE_OPAQUE 0
#define ALPHA_MODE_BLEND 1
#define ALPHA_MODE_MASK 2

#define MEDIUM_NONE 0
#define MEDIUM_ABSORB 1
#define MEDIUM_SCATTER 2
#define MEDIUM_EMISSIVE 3

/*struct Medium
{
    float type;
    float density;
    float3 color;
    float anisotropy;
};*/

struct DisneyMaterial
{
    float3 baseColor;
    float opacity;
    float alphaMode;
    float alphaCutoff;
    float3 emission;
    float anisotropic;
    float metallic;
    float roughness;
    float subsurface;
    float specularTint;
    float sheen;
    float sheenTint;
    float clearcoat;
    float clearcoatRoughness;
    float specTrans;
    float ior;
    float ax;
    float ay;
    //Medium medium;
};

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
    uint a = (pixelData >> 24) & 0xFF;
    //r = pow(r, 2.2f);
    //g = pow(g, 2.2f);
    //b = pow(b, 2.2f);
    if (a == 255)
    {
        return float4(r, g, b, 0.0f);
    }
    else if (a == 0)
    {
        return float4(r, g, b, 1.0f);
    }
    else
    {
        float t = (float)a / 255.0f;
        return float4(r, g, b, 1.0f - t);
    }
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
        return material.emission.rgb;
    }
    else
    {
        float4 pixel = SampleTexture((int)material.textures.w, uv, true);
        return pixel.rgb;
    }
#else
    return material.emission.rgb;
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
        return material.metallicRoughness;
    }
    else
    {
        float4 pixel = SampleTexture((int)material.textures.y, uv, true);
        return pixel.bg;
    }
#else
    return material.metallicRoughness;
#endif
}

float4 GetAlbedoTransmission(Material material, float2 uv)
{
#if HAS_TEXTURES
    if (material.textures.x < 0.0f)
    {
        return material.albedoTransmission;
    }
    else
    {  
        float4 pixel = SampleTexture((int)material.textures.x, uv, true);
        return pixel;
    }
#else
    return material.albedoTransmission;
#endif
}

float3 GetAlbedoColor(Material material, float2 uv)
{
    return GetAlbedoTransmission(material, uv).rgb;
}

float GetTransmission(Material material, float2 uv)
{
    return GetAlbedoTransmission(material, uv).a;
}

DisneyMaterial GetDisneyMaterial(Material material, float2 uv)
{
    DisneyMaterial disneyMaterial;
    disneyMaterial.baseColor = GetAlbedoColor(material, uv);
    disneyMaterial.opacity = 1.0f - material.albedoTransmission.a;
    disneyMaterial.alphaMode = ALPHA_MODE_OPAQUE;
    disneyMaterial.alphaCutoff = 0.0f;
    disneyMaterial.emission = GetEmission(material, uv);
    float2 metallicRoughness = GetMetallicRoughness(material, uv);
    disneyMaterial.metallic = metallicRoughness.x;
    disneyMaterial.roughness = metallicRoughness.y * metallicRoughness.y;
    disneyMaterial.subsurface = 0.0f;
    disneyMaterial.specularTint = 0.0f;
    disneyMaterial.sheen = 0.0f;
    disneyMaterial.sheenTint = 0.0f;
    disneyMaterial.clearcoat = 0.0f;
    disneyMaterial.clearcoatRoughness = 0.0f;
    disneyMaterial.specTrans = material.albedoTransmission.a;
    disneyMaterial.ior = material.ior;
    disneyMaterial.anisotropic = 0.0f;
    float aspect = sqrt(1.0 - disneyMaterial.anisotropic * 0.9);
    disneyMaterial.ax = max(0.001, disneyMaterial.roughness / aspect);
    disneyMaterial.ay = max(0.001, disneyMaterial.roughness * aspect);
    return disneyMaterial;
}

#endif // __UNITY_PATHTRACER_MATERIAL_HLSL__
