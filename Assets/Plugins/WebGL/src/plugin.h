#pragma once

#ifdef _WIN32
#define PLUGIN_FN __declspec(dllexport)
#else
#define PLUGIN_FN
#endif

#include "tinybvh/tiny_bvh.h"

extern "C" 
{
    extern PLUGIN_FN int BuildBVH(tinybvh::bvhvec4* vertices, int triangleCount);
    extern PLUGIN_FN void DestroyBVH(int index);
    extern PLUGIN_FN bool IsBVHReady(int index);
    extern PLUGIN_FN tinybvh::Intersection Intersect(int index, tinybvh::bvhvec3 origin, tinybvh::bvhvec3 direction);
    extern PLUGIN_FN int GetCWBVHNodesSize(int index);
    extern PLUGIN_FN int GetCWBVHTrisSize(int index);
    extern PLUGIN_FN bool GetCWBVHData(int index, tinybvh::bvhvec4** bvhNodes, tinybvh::bvhvec4** bvhTris);
}
