#include <deque>
//#include <mutex>
#include <vector>

#include "plugin.h"

struct BVHContainer
{
    tinybvh::BVH8_CWBVH* cwbvh = nullptr;
};

// Global container for BVHs and a mutex for thread safety
std::deque<tinybvh::BVH8_CWBVH*> gBVHs;
//std::mutex gBVHMutex;

// Adds a bvh to the global list either reusing an empty slot or making a new one.
int AddBVH(tinybvh::BVH8_CWBVH* newBVH)
{
    //std::lock_guard<std::mutex> lock(gBVHMutex);

    // Look for a free entry to reuse
    for (size_t i = 0; i < gBVHs.size(); ++i) 
    {
        if (gBVHs[i] == nullptr) 
        {
            gBVHs[i] = newBVH;
            return static_cast<int>(i);
        }
    }

    // If no free entry is found, append a new one
    gBVHs.push_back(newBVH);
    return static_cast<int>(gBVHs.size() - 1);
}

// Fetch a pointer to a BVH by index, or nullptr if the index is invalid
tinybvh::BVH8_CWBVH* GetBVH(int index)
{
    //std::lock_guard<std::mutex> lock(gBVHMutex);
    if (index >= 0 && index < static_cast<int>(gBVHs.size())) 
        return gBVHs[index];
    return nullptr;
}

int BuildBVH(tinybvh::bvhvec4* vertices, int triangleCount)
{
    tinybvh::BVH8_CWBVH* cwbvh = new tinybvh::BVH8_CWBVH();
    //cwbvh->BuildHQ(vertices, triangleCount);
    cwbvh->Build(vertices, triangleCount);
    
    return AddBVH(cwbvh);
}

void DestroyBVH(int index) 
{
    //std::lock_guard<std::mutex> lock(gBVHMutex);
    if (index >= 0 && index < static_cast<int>(gBVHs.size())) 
    {
        if (gBVHs[index] != nullptr)
        {
            delete gBVHs[index];
            gBVHs[index] = nullptr;
        }
    }
}

bool IsBVHReady(int index)
{
    tinybvh::BVH8_CWBVH* bvh = GetBVH(index);
    return (bvh != nullptr);
}

int GetCWBVHNodesSize(int index)
{
    tinybvh::BVH8_CWBVH* bvh = GetBVH(index);
    return bvh != nullptr ? bvh->usedBlocks * 16 : 0;
}

int GetCWBVHTrisSize(int index) 
{
    tinybvh::BVH8_CWBVH* bvh = GetBVH(index);
    return bvh != nullptr ? bvh->triCount * 3 * 16 : 0;
}

bool GetCWBVHData(int index, tinybvh::bvhvec4** bvhNodes, tinybvh::bvhvec4** bvhTris) 
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
