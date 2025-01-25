#include <deque>

#include "plugin.h"

static std::deque<tinybvh::BVH8_CWBVH*> gBVHList;
static std::deque<tinybvh::BVH_GPU*> gTLASList;

static int AddBVH(tinybvh::BVH8_CWBVH* newBVH)
{
    for (size_t i = 0; i < gBVHList.size(); ++i) 
    {
        if (gBVHList[i] == nullptr) 
        {
            gBVHList[i] = newBVH;
            return static_cast<int>(i);
        }
    }

    gBVHList.push_back(newBVH);
    return static_cast<int>(gBVHList.size() - 1);
}

extern "C" tinybvh::BVH8_CWBVH* GetBVH(int index)
{
    if (index >= 0 && index < static_cast<int>(gBVHList.size())) 
        return gBVHList[index];
    return nullptr;
}

extern "C" void* GetBVHPtr(int index)
{
    return GetBVH(index);
}

extern "C" int BuildBVH(tinybvh::bvhvec4* vertices, int triangleCount)
{
    tinybvh::BVH8_CWBVH* cwbvh = new tinybvh::BVH8_CWBVH();
    cwbvh->Build(vertices, triangleCount);
    return AddBVH(cwbvh);
}

extern "C" void DestroyBVH(int index) 
{
    if (index >= 0 && index < static_cast<int>(gBVHList.size())) 
    {
        if (gBVHList[index] != nullptr)
        {
            delete gBVHList[index];
            gBVHList[index] = nullptr;
        }
    }
}

extern "C" bool IsBVHReady(int index)
{
    tinybvh::BVH8_CWBVH* bvh = GetBVH(index);
    return (bvh != nullptr);
}

extern "C" int GetCWBVHNodesSize(int index)
{
    tinybvh::BVH8_CWBVH* bvh = GetBVH(index);
    return bvh != nullptr ? bvh->usedBlocks * 16 : 0;
}

extern "C" int GetCWBVHTrisSize(int index) 
{
    tinybvh::BVH8_CWBVH* bvh = GetBVH(index);
    return bvh != nullptr ? bvh->triCount * 3 * 16 : 0;
}

extern "C" bool GetCWBVHData(int index, tinybvh::bvhvec4** bvhNodes, tinybvh::bvhvec4** bvhTris) 
{
    tinybvh::BVH8_CWBVH* bvh = GetBVH(index);
    if (bvh == nullptr)
        return false;

    if (bvh->bvh8Data != nullptr && bvh->bvh8Tris != nullptr)
    {
        *bvhNodes = bvh->bvh8Data;
        *bvhTris  = bvh->bvh8Tris;
        return true;
    }

    return false;
}


static int AddTLAS(tinybvh::BVH_GPU* newBVH)
{
    for (size_t i = 0; i < gTLASList.size(); ++i) 
    {
        if (gTLASList[i] == nullptr) 
        {
            gTLASList[i] = newBVH;
            return static_cast<int>(i);
        }
    }

    gTLASList.push_back(newBVH);
    return static_cast<int>(gTLASList.size() - 1);
}

tinybvh::BVH_GPU* GetTLAS(int index)
{
    if (index >= 0 && index < static_cast<int>(gTLASList.size())) 
        return gTLASList[index];
    return nullptr;
}

extern "C" int BuildTLAS(tinybvh::BLASInstance* instances, int instanceCount)
{
    tinybvh::BVH_GPU* tlasGPU = new tinybvh::BVH_GPU();
    // Use the BVH owned by the BVH_GPU so we don't need to keep the seperate BVH around.
    tlasGPU->bvh.Build(instances, instanceCount, nullptr, 0);
    tlasGPU->ConvertFrom(tlasGPU->bvh);
    return AddTLAS(tlasGPU);
}

extern "C" void DestroyTLAS(int index)
{
    if (index >= 0 && index < static_cast<int>(gTLASList.size())) 
    {
        if (gTLASList[index] != nullptr)
        {
            delete gTLASList[index];
            gTLASList[index] = nullptr;
        }
    }
}

extern "C" bool IsTLASReady(int index)
{
    tinybvh::BVH_GPU* bvh = GetTLAS(index);
    return bvh != nullptr;
}

extern "C" int GetTLASNodesSize(int index)
{
    tinybvh::BVH_GPU* bvh = GetTLAS(index);
    return bvh != nullptr ? bvh->usedNodes * 16 * 4 : 0;
}

extern "C" bool GetTLASData(int index, tinybvh::bvhvec4** tlasNodes, uint32_t** tlasIndices)
{
    tinybvh::BVH_GPU* tlas = GetTLAS(index);
    if (tlas == nullptr)
        return false;

    if (tlas->bvhNode)
    {
        *tlasNodes = (tinybvh::bvhvec4*)tlas->bvhNode;
        *tlasIndices = tlas->bvh.primIdx;
        return true;
    }

    return false;
}
