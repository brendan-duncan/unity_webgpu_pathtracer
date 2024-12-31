#ifndef __UNITY_PATHTRACER_DISNEY_HLSL__
#define __UNITY_PATHTRACER_DISNEY_HLSL__

#include "common.hlsl"
#include "material.hlsl"

void TintColors(DisneyMaterial mat, float eta, out float F0, out float3 Csheen, out float3 Cspec0)
{
    float lum = Luminance(mat.baseColor);
    float3 ctint = lum > 0.0f ? mat.baseColor / lum : 1.0f;

    F0 = (1.0f - eta) / (1.0f + eta);
    F0 *= F0;
    
    Cspec0 = F0 * mix((float3)1.0f, ctint, mat.specularTint);
    Csheen = mix((float3)1.0f, ctint, mat.sheenTint);
}

float3 EvalDisneyDiffuse(DisneyMaterial mat, float3 Csheen, float3 V, float3 L, float3 H, out float pdf)
{
    pdf = 0.0f;
    if (L.z <= 0.0f)
    {
        return (float3)0.0f;
    }

    float LDotH = dot(L, H);

    float Rr = 2.0f * mat.roughness * LDotH * LDotH;

    // Diffuse
    float FL = SchlickWeight(L.z);
    float FV = SchlickWeight(V.z);
    float Fretro = Rr * (FL + FV + FL * FV * (Rr - 1.0));
    float Fd = (1.0f - 0.5f * FL) * (1.0f - 0.5f * FV);

    // Fake subsurface
    float Fss90 = 0.5f * Rr;
    float Fss = mix(1.0f, Fss90, FL) * mix(1.0f, Fss90, FV);
    float ss = 1.25f * (Fss * (1.0f / (L.z + V.z) - 0.5f) + 0.5f);

    // Sheen
    float FH = SchlickWeight(LDotH);
    float3 Fsheen = FH * mat.sheen * Csheen;

    pdf = L.z * INV_PI;
    return INV_PI * mat.baseColor * mix(Fd + Fretro, ss, mat.subsurface) + Fsheen;
}

float3 EvalMicrofacetReflection(DisneyMaterial mat, float3 V, float3 L, float3 H, float3 F, out float pdf)
{
    pdf = 0.0f;
    if (L.z <= 0.0f)
        return (float3)0.0f;

    float D = GTR2Aniso(H.z, H.x, H.y, mat.ax, mat.ay);
    float G1 = SmithGAniso(abs(V.z), V.x, V.y, mat.ax, mat.ay);
    float G2 = G1 * SmithGAniso(abs(L.z), L.x, L.y, mat.ax, mat.ay);

    pdf = G1 * D / (4.0f * V.z);
    return F * D * G2 / (4.0f * L.z * V.z);
}

float3 EvalMicrofacetRefraction(DisneyMaterial mat, float eta, float3 V, float3 L, float3 H, float3 F, out float pdf)
{
    pdf = 0.0;
    if (L.z >= 0.0)
        return (float3)(0.0);

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
    return pow(mat.baseColor, float3(0.5)) * (1.0 - F) * D * G2 * abs(VDotH) * jacobian * eta2 / abs(L.z * V.z);
}

float3 EvalClearcoat(DisneyMaterial mat, float3 V, float3 L, float3 H, out float pdf)
{
    pdf = 0.0;
    if (L.z <= 0.0)
        return (float3)(0.0);

    float VDotH = dot(V, H);

    float F = mix(0.04, 1.0, SchlickWeight(VDotH));
    float D = GTR1(H.z, mat.clearcoatRoughness);
    float G = SmithG(L.z, 0.25) * SmithG(V.z, 0.25);
    float jacobian = 1.0 / (4.0 * VDotH);

    pdf = D * H.z * jacobian;
    return (float3)(F) * D * G;
}

float3 DisneySample(DisneyMaterial mat, float3 V, float3 N, out float3 L, out float pdf, inout rngState)
{
    pdf = 0.0;

    float r1 = RandomFloat(rngState);
    float r2 = RandomFloat(rngState);

    // TODO: Tangent and bitangent should be calculated from mesh (provided, the mesh has proper uvs)
    //float3 T, B;
    //Onb(N, T, B);
    float3x3 onb = GetONB(N);

    // Transform to shading space to simplify operations (NDotL = L.z; NDotV = V.z; NDotH = H.z)
    V = ToLocal(onb, V);

    // Tint colors
    float3 Csheen, Cspec0;
    float F0;
    TintColors(mat, mat.eta, F0, Csheen, Cspec0);

    // Model weights
    float dielectricWt = (1.0 - mat.metallic) * (1.0 - mat.specTrans);
    float metalWt = mat.metallic;
    float glassWt = (1.0 - mat.metallic) * mat.specTrans;

    // Lobe probabilities
    float schlickWt = SchlickWeight(V.z);

    float diffPr = dielectricWt * Luminance(mat.baseColor);
    float dielectricPr = dielectricWt * Luminance(mix(Cspec0, (float3)(1.0), schlickWt));
    float metalPr = metalWt * Luminance(mix(mat.baseColor, (float3)(1.0), schlickWt));
    float glassPr = glassWt;
    float clearCtPr = 0.25 * mat.clearcoat;

    // Normalize probabilities
    float invTotalWt = 1.0 / (diffPr + dielectricPr + metalPr + glassPr + clearCtPr);
    diffPr *= invTotalWt;
    dielectricPr *= invTotalWt;
    metalPr *= invTotalWt;
    glassPr *= invTotalWt;
    clearCtPr *= invTotalWt;

    // CDF of the sampling probabilities
    float cdf[5];
    cdf[0] = diffPr;
    cdf[1] = cdf[0] + dielectricPr;
    cdf[2] = cdf[1] + metalPr;
    cdf[3] = cdf[2] + glassPr;
    cdf[4] = cdf[3] + clearCtPr;

    // Sample a lobe based on its importance
    float r3 = RandomFloat(rngState);

    if (r3 < cdf[0]) // Diffuse
    {
        L = CosineSampleHemisphere(r1, r2);
    }
    else if (r3 < cdf[2]) // Dielectric + Metallic reflection
    {
        float3 H = SampleGGXVNDF(V, mat.ax, mat.ay, r1, r2);

        if (H.z < 0.0)
            H = -H;

        L = normalize(reflect(-V, H));
    }
    else if (r3 < cdf[3]) // Glass
    {
        float3 H = SampleGGXVNDF(V, mat.ax, mat.ay, r1, r2);
        float F = DielectricFresnel(abs(dot(V, H)), mat.eta);

        if (H.z < 0.0)
            H = -H;

        // Rescale random number for reuse
        r3 = (r3 - cdf[2]) / (cdf[3] - cdf[2]);

        // Reflection
        if (r3 < F)
        {
            L = normalize(reflect(-V, H));
        }
        else // Transmission
        {
            L = normalize(refract(-V, H, mar.eta));
        }
    }
    else // Clearcoat
    {
        float3 H = SampleGTR1(mat.clearcoatRoughness, r1, r2);

        if (H.z < 0.0)
            H = -H;

        L = normalize(reflect(-V, H));
    }

    L = ToWorld(onb, L);
    V = ToWorld(onb, V);

    return DisneyEval(mat, V, N, L, pdf);
}

float3 DisneyEval(DisneyMaterial mat, float3 V, float3 N, float3 L, out float pdf)
{
    pdf = 0.0;
    float3 f = 0.0f;

    // TODO: Tangent and bitangent should be calculated from mesh (provided, the mesh has proper uvs)
    float3x3 onb = GetOnb(N);

    // Transform to shading space to simplify operations (NDotL = L.z; NDotV = V.z; NDotH = H.z)
    V = ToLocal(onb, V);
    L = ToLocal(onb, L);

    float3 H;
    if (L.z > 0.0)
        H = normalize(L + V);
    else
        H = normalize(L + V * mar.eta);

    if (H.z < 0.0)
        H = -H;

    // Tint colors
    float3 Csheen, Cspec0;
    float F0;
    TintColors(mat, mat.eta, F0, Csheen, Cspec0);

    // Model weights
    float dielectricWt = (1.0 - mat.metallic) * (1.0 - mat.specTrans);
    float metalWt = mat.metallic;
    float glassWt = (1.0 - mat.metallic) * mat.specTrans;

    // Lobe probabilities
    float schlickWt = SchlickWeight(V.z);

    float diffPr = dielectricWt * Luminance(mat.baseColor);
    float dielectricPr = dielectricWt * Luminance(mix(Cspec0, onb, schlickWt));
    float metalPr = metalWt * Luminance(mix(mat.baseColor, (float3)1.0f, schlickWt));
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
        f += EvalDisneyDiffuse(mat, Csheen, V, L, H, tmpPdf) * dielectricWt;
        pdf += tmpPdf * diffPr;
    }

    // Dielectric Reflection
    if (dielectricPr > 0.0 && reflect)
    {
        // Normalize for interpolating based on Cspec0
        float F = (DielectricFresnel(VDotH, 1.0 / mat.ior) - F0) / (1.0 - F0);

        f += EvalMicrofacetReflection(mat, V, L, H, mix(Cspec0, (float3)1.0f, F), tmpPdf) * dielectricWt;
        pdf += tmpPdf * dielectricPr;
    }

    // Metallic Reflection
    if (metalPr > 0.0 && reflect)
    {
        // Tinted to base color
        float3 F = mix(mat.baseColor, (float3)1.0f, SchlickWeight(VDotH));

        f += EvalMicrofacetReflection(mat, V, L, H, F, tmpPdf) * metalWt;
        pdf += tmpPdf * metalPr;
    }

    // Glass/Specular BSDF
    if (glassPr > 0.0)
    {
        // Dielectric fresnel (achromatic)
        float F = DielectricFresnel(VDotH, state.eta);

        if (reflect)
        {
            f += EvalMicrofacetReflection(mat, V, L, H, float3(F, F, F), tmpPdf) * glassWt;
            pdf += tmpPdf * glassPr * F;
        }
        else
        {
            f += EvalMicrofacetRefraction(mat, state.eta, V, L, H, float3(F, F, F), tmpPdf) * glassWt;
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

#endif // __UNITY_PATHTRACER_DISNEY_HLSL__
