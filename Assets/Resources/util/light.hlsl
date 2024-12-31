#ifndef __UNITY_PATHRACER_LIGHT_HLSL__
#define __UNITY_PATHRACER_LIGHT_HLSL__

struct Light
{
    float3 position;
    float type;
    float4 params; 
};

#endif // __UNITY_PATHRACER_LIGHT_HLSL__
