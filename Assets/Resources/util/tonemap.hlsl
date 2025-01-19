#ifndef __UNITY_PATHTRACER_TONEMAP_HLSL__
#define __UNITY_PATHTRACER_TONEMAP_HLSL__

// Narkowicz 2015, "ACES Filmic Tone Mapping Curve"
float3 Aces(float3 x)
{
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    //x = saturate(x);
    return saturate(x * (a * x + b)) / (x * (c * x + d) + e);
}

static const float3x3 ACESInputMat =
{
    {0.59719, 0.35458, 0.04823},
    {0.07600, 0.90834, 0.01566},
    {0.02840, 0.13383, 0.83777}
};

// ODT_SAT => XYZ => D60_2_D65 => sRGB
static const float3x3 ACESOutputMat =
{
    { 1.60475, -0.53108, -0.07367},
    {-0.10208,  1.10813, -0.00605},
    {-0.00327, -0.07276,  1.07602}
};

float3 RRTAndODTFit(float3 v)
{
    float3 a = v * (v + 0.0245786f) - 0.000090537f;
    float3 b = v * (0.983729f * v + 0.4329510f) + 0.238081f;
    return a / b;
}

float3 ACESFitted(float3 color)
{
    color = mul(ACESInputMat, color);

    // Apply RRT and ODT
    color = RRTAndODTFit(color);

    color = mul(ACESOutputMat, color);

    // Clamp to [0, 1]
    color = saturate(color);

    return color;
}

// Filmic Tonemapping Operators http://filmicworlds.com/blog/filmic-tonemapping-operators/
float3 Filmic(float3 x)
{
    float3 X = max(float3(0.0, 0.0, 0.0), x - 0.004);
    float3 result = (X * (6.2 * X + 0.5)) / (X * (6.2 * X + 1.7) + 0.06);
    return pow(result, float3(2.2, 2.2, 2.2));
}

// Lottes 2016, "Advanced Techniques and Optimization of HDR Color Pipelines"
float3 Lottes(float3 x)
{
    const float3 a = float3(1.6, 1.6, 1.6);
    const float3 d = float3(0.977, 0.977, 0.977);
    const float3 hdrMax = float3(8.0, 8.0, 8.0);
    const float3 midIn = float3(0.18, 0.18, 0.18);
    const float3 midOut = float3(0.267, 0.267, 0.267);

    float3 b =
        (-pow(midIn, a) + pow(hdrMax, a) * midOut) /
        ((pow(hdrMax, a * d) - pow(midIn, a * d)) * midOut);
    float3 c =
        (pow(hdrMax, a * d) * pow(midIn, a) - pow(hdrMax, a) * pow(midIn, a * d) * midOut) /
        ((pow(hdrMax, a * d) - pow(midIn, a * d)) * midOut);

    return pow(x, a) / (pow(x, a * d) * b + c);
}

float3 Reinhard(float3 x)
{
    return x / (1.0 + x);
}

#endif // __UNITY_PATHTRACER_TONEMAP_HLSL__
