#ifndef __UNITY_PATHRACER_MATERIAL_HLSL__
#define __UNITY_PATHRACER_MATERIAL_HLSL__

#include "brdf.hlsl"
#include "globals.hlsl"
#include "texture.hlsl"

float3 GetEmission(MaterialData material, float2 uv)
{
#if HAS_TEXTURES
    if (material.textures2.y < 0.0f)
        return material.data2.rgb;
    else
    {
        float4 pixel = SampleTexture((int)material.textures2.y, uv, true);
        return pixel.rgb;
    }
#else
    return material.data2.rgb;
#endif
}

float3 GetNormalMapSample(MaterialData material, float2 uv)
{
#if HAS_TEXTURES
    if (material.textures2.x < 0.0f)
        return float3(0.0f, 0.0f, 1.0f);
    else
    {
        float4 pixel = SampleTexture((int)material.textures2.x, uv, false);
        return pixel.rgb * 2.0f - 1.0f;
    }
#else
    return float3(0.0f, 0.0f, 1.0f);
#endif
}

float2 GetMetallicRoughness(MaterialData material, float2 uv)
{
#if HAS_TEXTURES
    if (material.textures1.y < 0.0f)
        return material.data3.rg;
    else
    {
        float4 pixel = SampleTexture((int)material.textures1.y, uv, true);
        return float2(pixel.b, pixel.g * pixel.g);
    }
#else
    return material.data3.rg;
#endif
}

float4 GetBaseColorOpacity(MaterialData material, float2 uv)
{
#if HAS_TEXTURES
    if (material.textures1.x < 0.0f)
        return material.data1;
    else
    {
        uv = uv * material.texture1Transform.xy + material.texture1Transform.zw;
        float4 pixel = SampleTexture((int)material.textures1.x, uv, true);
        return pixel * material.data1;
    }
#else
    return material.data1;
#endif
}

float GetOcclusion(MaterialData material, float2 uv)
{
#if HAS_TEXTURES
    if (material.textures2.z < 0.0f)
        return 1.0f;
    else
    {
        float pixel = SampleTexture((int)material.textures2.z, uv, true).r;
        return 1.0f + (pixel - 1.0f);
    }
#else
    return 1.0f;
#endif
}

Material GetMaterial(in MaterialData materialData, in Ray ray, inout RayHit hit)
{
    float2 uv = hit.uv;

    float4 baseColorOpacity = GetBaseColorOpacity(materialData, uv);

    Material material;
    material.baseColor = baseColorOpacity.rgb;
    material.opacity = baseColorOpacity.a;
    material.alphaMode = materialData.data4.r;
    material.alphaCutoff = materialData.data2.w;
    material.emission = GetEmission(materialData, uv);
    float2 metallicRoughness = GetMetallicRoughness(materialData, uv);
    material.metallic = metallicRoughness.x;
    material.roughness = max(metallicRoughness.y, 0.001);
    material.subsurface = materialData.data5.z;
    material.specularTint = materialData.data4.w;
    material.sheen = materialData.data5.x;
    material.sheenTint = materialData.data5.y;
    material.clearcoat = materialData.data5.w;
    material.clearcoatRoughness = lerp(0.1, 0.001, materialData.data6.x);
    material.specTrans = 1.0f - saturate(baseColorOpacity.a);
    material.ior = clamp(materialData.data3.w, 1.001f, 2.0f);
    material.anisotropic = clamp(materialData.data4.y, -0.9, 0.9);
    material.occlusion = GetOcclusion(materialData, uv);

    float aspect = sqrt(1.0 - material.anisotropic * 0.9);
    material.ax = max(0.001, material.roughness / aspect);
    material.ay = max(0.001, material.roughness * aspect);

    // Why can't I get normal maps to work?
    /*if (materialData.textures2.x >= 0.0)
    {
        float3 origNormal = hit.normal;

        float3 normalMap = GetNormalMapSample(materialData, uv);
        //normalMap *= float3(materialData.normalScale, materialData.normalScale, 1.0f);
        float3 bitangent = normalize(cross(hit.tangent, hit.normal));
        float3x3 tbn = float3x3(normalize(hit.tangent), bitangent, normalize(hit.normal));
        hit.normal = normalize(mul(normalMap, tbn));
        //hit.normal = normalMap;

        // Update tangent to the perturbed normal, ensuring it's orthogonal to the normal
        bitangent = normalize(cross(hit.normal, hit.tangent));
        float bitangentSign = dot(bitangent, cross(hit.tangent, hit.normal)) < 0 ? -1 : 1;
        bitangent *= bitangentSign;
        hit.tangent = normalize(cross(bitangent, hit.normal)) * bitangentSign;

        hit.ffnormal = dot(origNormal, ray.direction) <= 0.0 ? hit.normal : -hit.normal;
    }*/

    material.eta = (dot(ray.direction, hit.normal) < 0.0) ? 1.0f / material.ior : material.ior;

    return material;
}

#endif // __UNITY_PATHRACER_MATERIAL_HLSL__
