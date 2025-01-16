#ifndef __UNITY_PATHTRACER_MATERIAL_HLSL__
#define __UNITY_PATHTRACER_MATERIAL_HLSL__

struct MaterialData
{
    float4 data1;
    float4 data2;
    float4 data3;
    float4 data4;
    float4 data5;
    float4 data6;
    float4 textures;
    float4 texture1Transform;
};
StructuredBuffer<MaterialData> Materials;

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

struct Material
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

#endif // __UNITY_PATHTRACER_MATERIAL_HLSL__
