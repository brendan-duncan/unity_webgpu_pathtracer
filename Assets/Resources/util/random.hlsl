#ifndef __UNITY_PATHTRACER_RANDOM_HLSL__
#define __UNITY_PATHTRACER_RANDOM_HLSL__

RWStructuredBuffer<uint> RNGStateBuffer;

void rngNextInt(inout uint state)
{
    // PCG random number generator
    uint oldState = state + 747796405u + 2891336453u;
    uint word = ((oldState >> ((oldState >> 28u) + 4u)) ^ oldState) * 277803737u;
    state = (word >> 22u) ^ word;
}

float RandomFloat(inout uint state)
{
    rngNextInt(state);
    return (float)state / (float)0xffffffffu;
}

float RandomRange(float min, float max, inout uint state)
{
    return min + RandomFloat(state) * (max - min);
}

float3 RandomSphere(inout uint state)
{
    float3 p = float3(0.0f, 0.0f, 0.0f);
    do
    {
        p = 2.0f * float3(RandomFloat(state), RandomFloat(state), RandomFloat(state)) - float3(1.0f, 1.0f, 1.0f);
    } while (length(p * p) > 1.0f);

    return p;
}

float3 RandomCosineHemisphere(float3 normal, inout uint state)
{
    // See https://ameye.dev/notes/sampling-the-hemisphere/
	float theta = acos(sqrt(RandomFloat(state)));
	float phi = 2.0f * PI * RandomFloat(state);

    //float3 X = 0.0f;
    //float3 Y = 0.0f;
    //GetONB(normal, X, Y);
	//return sin(theta) * (cos(phi) * X + sin(phi) * Y + cos(theta) * normal);
    float3x3 onb = GetONB(normal);
    return sin(theta) * (cos(phi) * onb[0] + sin(phi) * onb[1] + cos(theta) * onb[2]);
}

#endif // __UNITY_PATHTRACER_RANDOM_HLSL__
