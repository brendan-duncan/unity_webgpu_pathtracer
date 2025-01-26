#ifndef __UNITY_PATHTRACER_GLOBALS_HLSL__
#define __UNITY_PATHTRACER_GLOBALS_HLSL__

#include "common.hlsl"
#include "triangle_attributes.hlsl"

uint MaxRayBounces;
uint CurrentSample;
uint OutputWidth;
uint OutputHeight;
uint RngSeedRoot;
int SamplesPerPass;

int EnvironmentMode;
float3 EnvironmentColor;
float EnvironmentIntensity;

RWTexture2D<float4> Output;
Texture2D<float4> AccumulatedOutput;

// Need to keep the total number of structured buffers at a max of 10 for WebGPU.

StructuredBuffer<MaterialData> Materials;

#if HAS_ENVIRONMENT_TEXTURE
int EnvironmentTextureWidth;
int EnvironmentTextureHeight;
float EnvironmentCdfSum;
float EnvironmentMapRotation;
Texture2D<float4> EnvironmentTexture;
SamplerState samplerEnvironmentTexture;

StructuredBuffer<float> EnvironmentCDF;
#endif

#if HAS_TEXTURES
StructuredBuffer<uint> TextureData;
#endif

#if HAS_LIGHTS
int LightCount;
StructuredBuffer<Light> Lights;
#endif

#if HAS_TLAS
StructuredBuffer<TLASNode> TLASNodes;
StructuredBuffer<uint> TLASIndices;
StructuredBuffer<BLASInstance> BLASInstances;

StructuredBuffer<BVHNode> BVHNodes;
StructuredBuffer<float4> BVHTris;
StructuredBuffer<TriangleAttributes> TriangleAttributesBuffer;
#else
StructuredBuffer<BVHNode> BVHNodes;
StructuredBuffer<float4> BVHTris;
StructuredBuffer<TriangleAttributes> TriangleAttributesBuffer;
#endif

#endif // __UNITY_PATHTRACER_GLOBALS_HLSL__
