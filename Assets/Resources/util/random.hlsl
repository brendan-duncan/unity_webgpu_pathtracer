#ifndef __UNITY_PATHTRACER_RANDOM_HLSL__
#define __UNITY_PATHTRACER_RANDOM_HLSL__

RWStructuredBuffer<uint> RNGStateBuffer;

void rngNextInt(inout uint state)
{
    // PCG random number generator
    // Based on https://www.shadertoy.com/view/XlGcRh
    uint oldState = state + 747796405u + 2891336453u;
    uint word = ((oldState >> ((oldState >> 28u) + 4u)) ^ oldState) * 277803737u;
    state = (word >> 22u) ^ word;
}

float rngNextFloat(inout uint state)
{
    rngNextInt(state);
    return (float)state / (float)(0xffffffffu);
}

float rngInRange(float min, float max, inout uint state) {
    return min + rngNextFloat(state) * (max - min);
}

float3 rngInSphere(inout uint state)
{
    float3 p = float3(0.0f, 0.0f, 0.0f);
    do
    {
        p = 2.0f * float3(rngNextFloat(state), rngNextFloat(state), rngNextFloat(state)) - float3(1.0f, 1.0f, 1.0f);
    } while (length(p * p) > 1.0f);

    return p;
}

#endif // __UNITY_PATHTRACER_RANDOM_HLSL__
