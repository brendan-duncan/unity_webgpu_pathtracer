#ifndef __UNITY_PATHTRACER_BRDF_HLSL__
#define __UNITY_PATHTRACER_BRDF_HLSL__

#include "common.hlsl"
#include "random.hlsl"
#include "ray.hlsl"
#include "sampling.hlsl"
#include "sky.hlsl"

void TintColors(in Material mat, float eta, out float F0, out float3 Csheen, out float3 Cspec0)
{
    float lum = Luminance(mat.baseColor);
    float3 ctint;
    if (lum > 0.0f)
        ctint = mat.baseColor / lum;
    else
        ctint = 1.0f;

    F0 = (1.0f - eta) / (1.0f + eta);
    F0 *= F0;

    Cspec0 = F0 * lerp((float3)1.0f, ctint, mat.specularTint);
    Csheen = lerp((float3)1.0f, ctint, mat.sheenTint);
}

float3 EvalDiffuse(in Material mat, float3 Csheen, float3 V, float3 L, float3 H, out float pdf)
{
    pdf = 0.0f;
    if (L.z <= 0.0f)
        return 0.0f;
    else
    {
        float LDotH = dot(L, H);

        float Rr = 2.0f * mat.roughness * LDotH * LDotH;

        // Diffuse
        float FL = SchlickWeight(L.z);
        float FV = SchlickWeight(V.z);
        float Fretro = Rr * (FL + FV + FL * FV * (Rr - 1.0));
        float Fd = (1.0f - 0.5f * FL) * (1.0f - 0.5f * FV);

        // Fake subsurface
        float Fss90 = 0.5f * Rr;
        float Fss = lerp(1.0f, Fss90, FL) * lerp(1.0f, Fss90, FV);
        float ss = 1.25f * (Fss * (1.0f / (L.z + V.z) - 0.5f) + 0.5f);

        // Sheen
        float FH = SchlickWeight(LDotH);
        float3 Fsheen = FH * mat.sheen * Csheen;

        pdf = L.z * INV_PI;
        return INV_PI * mat.baseColor * lerp(Fd + Fretro, ss, mat.subsurface) + Fsheen;
    }
}

float3 EvalMicrofacetReflection(in Material mat, float3 V, float3 L, float3 H, float3 F, out float pdf)
{
    pdf = 0.0f;
    if (L.z <= 0.0f)
        return 0.0f;
    else
    {
        float D = GTR2Aniso(H.z, H.x, H.y, mat.ax, mat.ay);
        float G1 = SmithGAniso(abs(V.z), V.x, V.y, mat.ax, mat.ay);
        float G2 = G1 * SmithGAniso(abs(L.z), L.x, L.y, mat.ax, mat.ay);

        pdf = G1 * D / (4.0f * V.z);
        return F * D * G2 / (4.0f * L.z * V.z);
    }
}

float3 EvalMicrofacetRefraction(in Material mat, float eta, float3 V, float3 L, float3 H, float3 F, out float pdf)
{
    pdf = 0.0;
    if (L.z >= 0.0)
        return 0.0f;
    else
    {
        float LDotH = dot(L, H);
        float VDotH = dot(V, H);

        float D = GTR2Aniso(H.z, H.x, H.y, mat.ax, mat.ay);
        float G1 = SmithGAniso(abs(V.z), V.x, V.y, mat.ax, mat.ay);
        float G2 = G1 * SmithGAniso(abs(L.z), L.x, L.y, mat.ax, mat.ay);
        float denom = LDotH + VDotH * eta;
        denom *= denom;
        float eta2 = eta * eta;
        float jacobian = abs(LDotH) / denom;

        pdf = G1 * max(0.0, VDotH) * D * jacobian / V.z;
        return pow(mat.baseColor, (float3)(0.5)) * (1.0 - F) * D * G2 * abs(VDotH) * jacobian * eta2 / abs(L.z * V.z);
    }
}

float3 EvalClearcoat(in Material mat, float3 V, float3 L, float3 H, out float pdf)
{
    pdf = 0.0;
    if (L.z <= 0.0)
        return 0.0f;
    else
    {
        float VDotH = dot(V, H);

        float F = lerp(0.04, 1.0, SchlickWeight(VDotH));
        float D = GTR1(H.z, mat.clearcoatRoughness);
        float G = SmithG(L.z, 0.25) * SmithG(V.z, 0.25);
        float jacobian = 1.0 / (4.0 * VDotH);

        pdf = D * H.z * jacobian;
        return (float3)(F) * D * G;
    }
}

float3 _EvalBRDF(in RayHit hit, in Material mat, float3 V, float3 N, float3 L, in float3x3 onb, out float pdf)
{
    pdf = 0.0;
    float3 f = 0.0f;

    V = ToLocal(onb, V);
    L = ToLocal(onb, L);

    float3 H;
    if (L.z > 0.0)
        H = normalize(L + V);
    else
        H = normalize(L + V * hit.eta);

    if (H.z < 0.0)
        H = -H;

    // Tint colors
    float3 Csheen, Cspec0;
    float F0;
    TintColors(mat, hit.eta, F0, Csheen, Cspec0);

    // Model weights
    float dielectricWt = (1.0 - mat.metallic) * (1.0 - mat.specTrans);
    float metalWt = mat.metallic;
    float glassWt = (1.0 - mat.metallic) * mat.specTrans;

    // Lobe probabilities
    float schlickWt = SchlickWeight(V.z);

    float diffPr = dielectricWt * Luminance(mat.baseColor);
    float dielectricPr = dielectricWt * Luminance(lerp(Cspec0, (float3)1.0f, schlickWt));
    float metalPr = metalWt * Luminance(lerp(mat.baseColor, (float3)1.0f, schlickWt));
    float glassPr = glassWt;
    float clearCtPr = 0.25 * mat.clearcoat;

    // Normalize probabilities
    float invTotalWt = 1.0 / (diffPr + dielectricPr + metalPr + glassPr + clearCtPr);
    diffPr *= invTotalWt;
    dielectricPr *= invTotalWt;
    metalPr *= invTotalWt;
    glassPr *= invTotalWt;
    clearCtPr *= invTotalWt;

    bool reflect = L.z * V.z > 0;

    float tmpPdf = 0.0;
    float VDotH = abs(dot(V, H));

    // Diffuse
    if (diffPr > 0.0 && reflect)
    {
        f += EvalDiffuse(mat, Csheen, V, L, H, tmpPdf) * dielectricWt;
        pdf += tmpPdf * diffPr;
    }

    // Dielectric Reflection
    if (dielectricPr > 0.0 && reflect)
    {
        // Normalize for interpolating based on Cspec0
        float F = 0.0f;
        if (F0 != 1.0f && mat.ior != 0.0f)
        {
            float invEta = rcp(mat.ior);
            float invF0 = 1.0f - F0;
            invF0 = rcp(invF0);
            F = (DielectricFresnel(VDotH, invEta) - F0) * invF0;
        }

        f += EvalMicrofacetReflection(mat, V, L, H, lerp(Cspec0, (float3)1.0f, F), tmpPdf) * dielectricWt;
        pdf += tmpPdf * dielectricPr;
    }

    // Metallic Reflection
    if (metalPr > 0.0 && reflect)
    {
        // Tinted to base color
        float3 F = lerp(mat.baseColor, (float3)1.0f, SchlickWeight(VDotH));

        f += EvalMicrofacetReflection(mat, V, L, H, F, tmpPdf) * metalWt;
        pdf += tmpPdf * metalPr;
    }

    // Glass/Specular BSDF
    if (glassPr > 0.0)
    {
        // Dielectric fresnel (achromatic)
        float F = DielectricFresnel(VDotH, hit.eta);

        if (reflect)
        {
            f += EvalMicrofacetReflection(mat, V, L, H, float3(F, F, F), tmpPdf) * glassWt;
            pdf += tmpPdf * glassPr * F;
        }
        else
        {
            f += EvalMicrofacetRefraction(mat, hit.eta, V, L, H, float3(F, F, F), tmpPdf) * glassWt;
            pdf += tmpPdf * glassPr * (1.0 - F);
        }
    }

    // Clearcoat
    if (clearCtPr > 0.0 && reflect)
    {
        f += EvalClearcoat(mat, V, L, H, tmpPdf) * 0.25 * mat.clearcoat;
        pdf += tmpPdf * clearCtPr;
    }

    return f * abs(L.z);
}

float3 EvalBRDF(in RayHit hit, in Material mat, float3 V, float3 N, float3 L, out float pdf)
{
    float3x3 onb = GetONB(N);
    // This is causing rendering issues. Perhaps normal and tangent are not orthogonal?
    //float3 bitangent = normalize(cross(hit.normal, hit.tangent));
    //float3x3 onb = float3x3(hit.tangent, bitangent, hit.normal);

    //V = ToLocal(onb, V);
    //L = ToLocal(onb, L);

    return _EvalBRDF(hit, mat, V, N, L, onb, pdf);
}

float3 SampleBRDF(RayHit hit, Material mat, float3 V, float3 N, out float3 L, out float pdf, inout uint rngState)
{
    pdf = 0.0;

    float r1 = RandomFloat(rngState);
    float r2 = RandomFloat(rngState);

    float3x3 onb = GetONB(N);
    // This is causing rendering issues. Perhaps normal and tangent are not orthogonal?
    //float3 bitangent = normalize(cross(normalize(hit.normal), normalize(hit.tangent)));
    //float3x3 onb = float3x3(hit.tangent, bitangent, hit.normal);

    V = ToLocal(onb, V);

    // Tint colors
    float3 Csheen, Cspec0;
    float F0;
    TintColors(mat, hit.eta, F0, Csheen, Cspec0);

    // Model weights
    float dielectricWt = (1.0 - mat.metallic) * (1.0 - mat.specTrans);
    float metalWt = mat.metallic;
    float glassWt = (1.0 - mat.metallic) * mat.specTrans;

    // Lobe probabilities
    float schlickWt = SchlickWeight(V.z);

    float diffPr = dielectricWt * Luminance(mat.baseColor);
    float dielectricPr = dielectricWt * Luminance(lerp(Cspec0, (float3)1.0f, schlickWt));
    float metalPr = metalWt * Luminance(lerp(mat.baseColor, (float3)1.0f, schlickWt));
    float glassPr = glassWt;
    float clearCtPr = 0.25f * mat.clearcoat;

    // Normalize probabilities
    float invTotalWt = 1.0 / (diffPr + dielectricPr + metalPr + glassPr + clearCtPr);
    diffPr *= invTotalWt;
    dielectricPr *= invTotalWt;
    metalPr *= invTotalWt;
    glassPr *= invTotalWt;
    clearCtPr *= invTotalWt;

    // CDF of the sampling probabilities
    float cdf0 = diffPr;
    float cdf1 = cdf0 + dielectricPr;
    float cdf2 = cdf1 + metalPr;
    float cdf3 = cdf2 + glassPr;
    float cdf4 = cdf3 + clearCtPr;

    // Sample a lobe based on its importance
    float r3 = RandomFloat(rngState);

    if (r3 < cdf0) // Diffuse
    {
        L = CosineSampleHemisphere(r1, r2);
        //return float3(1.0f, 0.0f, 0.0f);
    }
    else if (r3 < cdf2) // Dielectric + Metallic reflection
    {
        float3 H = SampleGGXVNDF(V, mat.ax, mat.ay, r1, r2);

        if (H.z < 0.0)
            H = -H;

        L = normalize(reflect(-V, H));
        //return float3(0.0f, 1.0f, 0.0f);
    }
    else if (r3 < cdf3) // Glass
    {
        float3 H = SampleGGXVNDF(V, mat.ax, mat.ay, r1, r2);
        float F = DielectricFresnel(abs(dot(V, H)), hit.eta);

        if (H.z < 0.0)
            H = -H;

        // Rescale random number for reuse
        r3 = (r3 - cdf2) / (cdf3 - cdf2);

        // Reflection
        if (r3 < F)
            L = normalize(reflect(-V, H));
        else // Transmission
            L = normalize(refract(-V, H, hit.eta));

        //return float3(0.0f, 0.0f, 1.0f);
    }
    else // Clearcoat
    {
        float3 H = SampleGTR1(mat.clearcoatRoughness, r1, r2);

        if (H.z < 0.0)
            H = -H;

        L = normalize(reflect(-V, H));
        //return float3(1.0f, 1.0f, 0.0f);
    }

    L = ToWorld(onb, L);
    V = ToWorld(onb, V);

    return _EvalBRDF(hit, mat, V, N, L, onb, pdf);
}

#endif // __UNITY_PATHTRACER_BRDF_HLSL__
