#ifndef __UNITY_PATHRACER_BRDF_HLSL__
#define __UNITY_PATHRACER_BRDF_HLSL__

#include "common.hlsl"

float3 Fresnel(float3 f0, float3 f90, float VdotH)
{
    return f0 + (f90 - f0) * pow(max(0.0f, 1.0f - abs(VdotH)), 5.0f);
}

float3 CookTorranceGGX(float3 N, float3 L, float3 V, float3 baseColor, float metallic, float roughness,
    float ior, float transmission)
{
    N = normalize(N);
    L = normalize(L);
    V = normalize(V);

    float3 Lt = L - 2.0f * N * dot(L, N);

    float3 H = normalize(V + L);
    float3 Ht = normalize(V + Lt);

    float VdotN = dot(V, N); // always >= 0.0
    float VdotH = dot(V, H); // == LdotH
    float LdotN = dot(L, N);
    float NdotH = dot(N, H);

    float VdotHt = dot(V, Ht);
    float LdotHt = dot(L, Ht);
    float NdotHt = dot(N, Ht);

    float alpha = roughness * roughness;
    float alpha2 = alpha * alpha;

    // normal Distribution term
    float D = 0.0f;
    if (NdotH > 0.0f && alpha2 != 0.0f)
    {
        D = alpha2 / PI / pow(NdotH * NdotH * (alpha2 - 1.0f) + 1.0f, 2.0f);
    }
    float Dt = 0.0f;
    if (NdotHt > 0.0f && alpha2 != 0.0f)
    {
        Dt = alpha2 / PI / pow(NdotHt * NdotHt * (alpha2 - 1.0f) + 1.0f, 2.0f);
    }
    //float D = alpha2 / PI / pow(NdotH * NdotH * (alpha2 - 1.0f) + 1.0f, 2.0f);
    //float Dt = alpha2 / PI / pow(NdotHt * NdotHt * (alpha2 - 1.0f) + 1.0f, 2.0f) * chiPlus(NdotHt);

    // Visibility x Geometry term
    float visVDen = (abs(VdotN) + sqrt(alpha2 + (1.0f - alpha2) * VdotN * VdotN));
    float visV = 0.0f;
    if (visVDen != 0.0f)
    {
        visV = 1.0f / visVDen;
    }
    float visLDen = (abs(LdotN) + sqrt(alpha2 + (1.0f - alpha2) * LdotN * LdotN));
    float visL = 0.0f;
    if (visLDen != 0.0f)
    {
        visL = 1.0f / visLDen;
    }

    float vis = visV * visL;

    float3 specularBrdf = 0.0f;
    if (VdotN > 0.0f && LdotN > 0.0f)
    {
        specularBrdf = (float3)(D * vis);
    }
    //float3 specularBrdf = vec3f(D * vis) * chiPlus(VdotN) * chiPlus(LdotN);

    float f0 = pow((1.0f - ior) / (1.0f + ior), 2.0f);

    float3 transmissionFresnel = saturate(Fresnel((float3)f0, (float3)1.0f, VdotHt));
    float3 transmissionBtdf = 0.0f;
    if (LdotN < 0.0f && VdotN > 0.0f)
    {
        transmissionBtdf = baseColor * Dt * vis;
    }
    //float3 transmissionBtdf = baseColor * Dt * vis * chiPlus(-LdotN) * chiPlus(VdotN);

    float3 metallicFresnel = Fresnel(baseColor, (float3)1.0, VdotH);
    float3 metallicBrdf = metallicFresnel * specularBrdf;

    //float3 diffuseBrdf = baseColor / PI * chiPlus(LdotN);
    float3 diffuseBrdf = 0.0f;
    if (LdotN > 0.0f)
    {
        diffuseBrdf = baseColor / PI;
    }

    float3 dielectricFresnel = saturate(Fresnel((float3)f0, (float3)1.0f, VdotH));

    float3 opaqueDielectricBrdf = lerp(diffuseBrdf, specularBrdf, dielectricFresnel);
    float3 transparentDielectricBrdf = specularBrdf * dielectricFresnel + transmissionBtdf * (1.0f - transmissionFresnel);

    float3 dielectricBrdf = lerp(opaqueDielectricBrdf, transparentDielectricBrdf, transmission);

    float3 resultBrdf = lerp(dielectricBrdf, metallicBrdf, saturate(metallic));

    return resultBrdf;
}

// Reflected direction sampling algorithm well-suited for the Cook-Torrance specular term, see
//    Eric Heitz, Sampling the GGX Distribution of Visible Normals (2018)
float3 SampleVNDF(float3 N, float3 V, float roughness, inout uint rngSeed)
{
    N = normalize(N);
    V = normalize(V);
    roughness = saturate(roughness);

    float3x3 onb = GetONB(N);

    float alpha = roughness * roughness;

    float3 Vlocal = normalize(ToLocal(onb, V));

    float3 Vh = normalize(float3(alpha, alpha, 1.0f) * Vlocal);

    float3 T1 = 0.0f;
    if (alpha == 0.0f)
    {
        T1 = normalize(cross(float3(1.0f, 0.0f, 0.0f), Vh));
    }
    else
    {
        T1 = normalize(cross(float3(0.0f, 0.0f, 1.0f), Vh));
    }

    float3 T2 = cross(Vh, T1);

    float r = sqrt(RandomFloat(rngSeed));
    float phi = 2.0f * PI * RandomFloat(rngSeed);
    float t1 = r * cos(phi);
    float t2 = r * sin(phi);
    float s = 0.5f * (1.0f + Vh.z);
    t2 = (1.0f - s) * sqrt(max(0.0, 1.0 - t1 * t1)) + s * t2;

    float3 Nh = t1 * T1 + t2 * T2 + sqrt(max(0.0, 1.0 - t1 * t1 - t2 * t2)) * Vh;

    float3 Ne = normalize(float3(alpha * Nh.x, alpha * Nh.y, max(0.0, Nh.z)));

    float3 L = normalize(2.0f * Ne * dot(Ne, Vlocal) - Vlocal);

    return ToWorld(onb, L);
}

float3 SampleTransmissionVNDF(float3 N, float3 V, float roughness, inout uint rngSeed)
{
    N = normalize(N);
    float3 R = normalize(SampleVNDF(N, V, roughness, rngSeed));
    //return R;
    //return reflect(R, N);
    return R - (2.0f * dot(R, N) * N);
}

float ProbabilityVNDF(float3 N, float3 V, float3 L, float roughness)
{
    N = normalize(N);
    V = normalize(V);
    L = normalize(L);

    float3x3 onb = GetONB(N);

    float alpha = roughness * roughness;
    float alpha2 = alpha * alpha;

    float3 Vlocal = normalize(ToLocal(onb, V));
    float3 Llocal = normalize(ToLocal(onb, L));

    float3 H = normalize(Llocal + Vlocal);

    float powAlpha2 = pow((alpha2 - 1.0) * H.z * H.z + 1.0, 2.0);
    float D = 0.0f;
    if (H.z > 0.0f && powAlpha2 != 0.0f)
    {
        D = alpha2 / PI / powAlpha2;
    }
    //float D = alpha2 / PI / powAlpha2 * chiPlus(H.z);

    if (Vlocal.z <= 0.0f)
    {
        return 0.0f;
    }
    else
    {   
        //float visV = 2.0 * abs(Vlocal.z) / (abs(Vlocal.z) + sqrt(alpha2 + (1.0 - alpha2) * Vlocal.z * Vlocal.z)) * chiPlus(Vlocal.z);
        float denom = (abs(Vlocal.z) + sqrt(alpha2 + (1.0 - alpha2) * Vlocal.z * Vlocal.z));
        if (denom == 0.0f)
        {
            return 0.0f;
        }
        else
        {
            float visV = 2.0 * abs(Vlocal.z) / denom;
            return D * visV / 4.0 / Vlocal.z;
        }
    }
}

float ProbabilityTransmissionVNDF(float3 N, float3 V, float3 L, float roughness)
{    
    float3 reflectedDirection = L - 2.0f * dot(L, N) * N;
    return ProbabilityVNDF(N, V, reflectedDirection, roughness);
}


#endif // __UNITY_PATHRACER_BRDF_HLSL__
