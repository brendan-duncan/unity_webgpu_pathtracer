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
    return saturate(x * (a * x + b)) / (x * (c * x + d) + e);
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
