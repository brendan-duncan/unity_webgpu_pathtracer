#ifndef __UNITY_PATHTRACER_COMMON__
#define __UNITY_PATHTRACER_COMMON__

#define PI 3.14159265359f

uint TotalRays;
uint CurrentSample;
float FarPlane;
uint OutputWidth;
uint OutputHeight;
RWTexture2D<float4> Output;
Texture2D<float4> AccumulatedOutput;

#endif // __UNITY_PATHTRACER_COMMON__
