#ifndef __UNITY_PATHTRACER_COMMON__
#define __UNITY_PATHTRACER_COMMON__

uint TotalRays;
uint CurrentSample;
float FarPlane;
uint OutputWidth;
uint OutputHeight;
RWTexture2D<float4> Output;
Texture2D<float4> AccumulatedOutput;

#endif // __UNITY_PATHTRACER_COMMON__
