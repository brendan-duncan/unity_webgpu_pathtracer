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

void WalkBVHTree(tinybvh::BVH& tlas, tinybvh::BVH::BVHNode* node, int depth)
{
    printf("NODE depth:%d bound: %g %g %g x %g %g %g\n", depth, node->aabbMin.x, node->aabbMin.y, node->aabbMin.z, node->aabbMax.x, node->aabbMax.y, node->aabbMax.z);
    if (node->isLeaf())
    {
        for (unsigned int i = 0; i < node->triCount; ++i)
            printf("** LEAF count:%d blas:%d\n", node->triCount, tlas.triIdx[node->leftFirst + i]);
    }
    else
    {
        tinybvh::BVH::BVHNode* child1 = &tlas.bvhNode[node->leftFirst];
        tinybvh::BVH::BVHNode* child2 = &tlas.bvhNode[node->leftFirst + 1];
        WalkBVHTree(tlas, child1, depth + 1);
        WalkBVHTree(tlas, child2, depth + 1);
    }
}

void WalkBVHTree(tinybvh::BVH_GPU& tlas, tinybvh::BVH_GPU::BVHNode* node, int depth)
{
    //printf("NODE depth:%d bound: %g %g %g x %g %g %g\n", depth, node->aabbMin.x, node->aabbMin.y, node->aabbMin.z, node->aabbMax.x, node->aabbMax.y, node->aabbMax.z);
    if (node->isLeaf())
    {
        unsigned int firstTri = node->firstTri;
        for (unsigned int i = 0; i < node->triCount; ++i)
            printf("** LEAF depth:%d count:%d blas:%d\n", depth, node->triCount, firstTri + i);
    }
    else
    {
        tinybvh::BVH_GPU::BVHNode* child1 = &tlas.bvhNode[node->left];
        printf("NODE depth:%d LEFT:%g %g %g x %g %g %g\n", depth, node->lmin.x, node->lmin.y, node->lmin.z, node->lmax.x, node->lmax.y, node->lmax.z);
        WalkBVHTree(tlas, child1, depth + 1);

        tinybvh::BVH_GPU::BVHNode* child2 = &tlas.bvhNode[node->right];
        printf("NODE depth:%d RIGHT:%g %g %g x %g %g %g\n", depth, node->rmin.x, node->rmin.y, node->rmin.z, node->rmax.x, node->rmax.y, node->rmax.z);
        WalkBVHTree(tlas, child2, depth + 1);
    }
}

extern "C" int BuildTLAS(tinybvh::BLASInstance* instances, int instanceCount)
{
    for (int i = 0; i < instanceCount; ++i)
    {
        // We store the CWBVH but we need to access the BVH for building the TLAS.
        //tinybvh::BVH8_CWBVH* cwbvh = (tinybvh::BVH8_CWBVH*)instances[i].blas;
        //tinybvh::BVH* bvh = &cwbvh->bvh8.bvh;
        //instances[i].blas = bvh;

        printf("BLAS Instance %d blas:%d transform:\n%g %g %g %g\n%g %g %g %g\n%g %g %g %g\n%g %g %g %g\n%g %g %g x %g %g %g\n--------\n", i, instances[i].blasIdx,
            instances[i].transform[0], instances[i].transform[1], instances[i].transform[2], instances[i].transform[3],
            instances[i].transform[4], instances[i].transform[5], instances[i].transform[6], instances[i].transform[7],
            instances[i].transform[8], instances[i].transform[9], instances[i].transform[10], instances[i].transform[11],
            instances[i].transform[12], instances[i].transform[13], instances[i].transform[14], instances[i].transform[15],
            instances[i].aabbMin.x, instances[i].aabbMin.y, instances[i].aabbMin.z,
            instances[i].aabbMax.x, instances[i].aabbMax.y, instances[i].aabbMax.z);
    }

    tinybvh::BVH_GPU* tlasGPU = new tinybvh::BVH_GPU();
    // Use the BVH owned by the BVH_GPU so we don't need to keep the seperate BVH around.
    tlasGPU->bvh.Build(instances, instanceCount, nullptr, 0);
    tlasGPU->ConvertFrom(tlasGPU->bvh);
    //WalkBVHTree(*tlasGPU, &tlasGPU->bvhNode[0], 0);
    /*printf("-------------------- TLAS Node Data:\n");
    for (unsigned int i = 0; i < tlasGPU->usedNodes; ++i)
    {
        printf("%g %g %g %g\n", tlasGPU->bvhNode[i].lmin.x, tlasGPU->bvhNode[i].lmin.y, tlasGPU->bvhNode[i].lmin.z, (float)tlasGPU->bvhNode[i].left);
        printf("%g %g %g %g\n", tlasGPU->bvhNode[i].lmax.x, tlasGPU->bvhNode[i].lmax.y, tlasGPU->bvhNode[i].lmax.z, (float)tlasGPU->bvhNode[i].right);
        printf("%g %g %g %g\n", tlasGPU->bvhNode[i].rmin.x, tlasGPU->bvhNode[i].rmin.y, tlasGPU->bvhNode[i].rmin.z, (float)tlasGPU->bvhNode[i].triCount);
        printf("%g %g %g %g\n", tlasGPU->bvhNode[i].rmax.x, tlasGPU->bvhNode[i].rmax.y, tlasGPU->bvhNode[i].rmax.z, (float)tlasGPU->bvhNode[i].firstTri);
    }
    printf("--------------------\n");*/

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

extern "C" bool GetTLASData(int index, tinybvh::bvhvec4** bvhNodes)
{
    tinybvh::BVH_GPU* bvh = GetTLAS(index);
    if (bvh == nullptr)
        return false;

    if (bvh->bvhNode)
    {
        *bvhNodes = (tinybvh::bvhvec4*)bvh->bvhNode;
        return true;
    }

    return false;
}
