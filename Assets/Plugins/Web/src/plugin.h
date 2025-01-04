#pragma once

#ifdef _WIN32
#define PLUGIN_FN __declspec(dllexport)
#else
#define PLUGIN_FN
#endif

#define TINYBVH_IMPLEMENTATION
#define TINYBVH_NO_SIMD
#include "tinybvh/tiny_bvh.h"

extern "C" 
{
    extern PLUGIN_FN int BuildBVH(tinybvh::bvhvec4* vertices, int triangleCount);
    extern PLUGIN_FN void DestroyBVH(int index);
    extern PLUGIN_FN bool IsBVHReady(int index);
    extern PLUGIN_FN int GetCWBVHNodesSize(int index);
    extern PLUGIN_FN int GetCWBVHTrisSize(int index);
    extern PLUGIN_FN bool GetCWBVHData(int index, tinybvh::bvhvec4** bvhNodes, tinybvh::bvhvec4** bvhTris);
}
