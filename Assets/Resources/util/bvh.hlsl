#ifndef __UNITY_PATHTRACER_BVH_HLSL__
#define __UNITY_PATHTRACER_BVH_HLSL__

#include "common.hlsl"
#include "intersect.hlsl"
#include "material.hlsl"
#include "random.hlsl"
#include "triangle_attributes.hlsl"

struct BVHInstance
{
    float4x4 localToWorld;
    float4x4 worldToLocal;
    int materialIndex;
    int bvhOffset;
    int triOffset;
    int triAttributeOffset;
};

// Nodes in CWBVH format.
struct BVHNode
{
    float4 n0;
    float4 n1;
    float4 n2;
    float4 n3;
    float4 n4;
};

struct TLASNode
{
    float4 lminLeft;
    float4 lmaxRight;
    float4 rminBlasCount;
    float4 rmaxFirstBlas;
};

uint TLASInstanceCount;
StructuredBuffer<BVHNode> BVHNodes;
StructuredBuffer<float4> BVHTris;
StructuredBuffer<TriangleAttributes> TriangleAttributesBuffer;

// Stack size for BVH traversal
#define BVH_STACK_SIZE 32

float2 InterpolateAttribute(float2 barycentric, float2 attr0, float2 attr1, float2 attr2)
{
    return attr0 * (1.0f - barycentric.x - barycentric.y) + attr1 * barycentric.x + attr2 * barycentric.y;
}

float3 InterpolateAttribute(float2 barycentric, float3 attr0, float3 attr1, float3 attr2)
{
    return attr0 * (1.0f - barycentric.x - barycentric.y) + attr1 * barycentric.x + attr2 * barycentric.y;
}

void IntersectTriangle(int triAddr, const Ray ray, inout RayHit hit)
{
    float3 v0 = BVHTris[triAddr + 2].xyz;
    float3 e1 = BVHTris[triAddr + 1].xyz;
    float3 e2 = BVHTris[triAddr + 0].xyz;

    float3 r = cross(ray.direction.xyz, e2);
    float a = dot(e1, r);

    if (abs(a) > 0.0000001f)
    {
        float f = 1.0f / a;
        float3 s = ray.origin.xyz - v0;
        float u = f * dot(s, r);

        if (u >= 0.0f && u <= 1.0f)
        {
            float3 q = cross(s, e1);
            float v = f * dot(ray.direction.xyz, q);

            if (v >= 0.0f && u + v <= 1.0f)
            {
                float d = f * dot(e2, q);

                if (d > 0.0001f && d < hit.distance)
                {
                    uint triIndex = asuint(BVHTris[triAddr + 2].w);
                    float2 barycentric = float2(u, v);
                    hit.barycentric = barycentric;
                    hit.triAddr = triAddr;
                    hit.triIndex = triIndex;
                    hit.distance = d;
                }
            }
        }
    }
}

float3 GetNodeInvDir(float n0w, float3 invDir)
{
    uint packed = asuint(n0w);

    // Extract each byte and sign extend
    uint e_x = (ExtractByte(packed, 0) ^ 0x80) - 0x80;
    uint e_y = (ExtractByte(packed, 1) ^ 0x80) - 0x80;
    uint e_z = (ExtractByte(packed, 2) ^ 0x80) - 0x80;

    return float3(
        asfloat((e_x + 127) << 23) * invDir.x,
        asfloat((e_y + 127) << 23) * invDir.y,
        asfloat((e_z + 127) << 23) * invDir.z
    );
}

uint IntersectCWBVHNode(float3 origin, float3 invDir, uint octinv4, float tmax, const BVHNode node)
{
    uint hitmask = 0;
    float3 nodeInvDir = GetNodeInvDir(node.n0.w, invDir);
    float3 nodePos = (node.n0.xyz - origin) * invDir;

    // i = 0 checks the first 4 children, i = 1 checks the second 4 children.
    [unroll]
    for (int i = 0; i < 2; ++i)
    {
        uint meta = asuint(i == 0 ? node.n1.z : node.n1.w);

        float4 lox = ExtractBytes(invDir.x < 0.0f ? (i == 0 ? node.n3.z : node.n3.w) : (i == 0 ? node.n2.x : node.n2.y));
        float4 loy = ExtractBytes(invDir.y < 0.0f ? (i == 0 ? node.n4.x : node.n4.y) : (i == 0 ? node.n2.z : node.n2.w));
        float4 loz = ExtractBytes(invDir.z < 0.0f ? (i == 0 ? node.n4.z : node.n4.w) : (i == 0 ? node.n3.x : node.n3.y));
        float4 hix = ExtractBytes(invDir.x < 0.0f ? (i == 0 ? node.n2.x : node.n2.y) : (i == 0 ? node.n3.z : node.n3.w));
        float4 hiy = ExtractBytes(invDir.y < 0.0f ? (i == 0 ? node.n2.z : node.n2.w) : (i == 0 ? node.n4.x : node.n4.y));
        float4 hiz = ExtractBytes(invDir.z < 0.0f ? (i == 0 ? node.n3.x : node.n3.y) : (i == 0 ? node.n4.z : node.n4.w));

        float4 tminx = lox * nodeInvDir.x + nodePos.x;
        float4 tmaxx = hix * nodeInvDir.x + nodePos.x;
        float4 tminy = loy * nodeInvDir.y + nodePos.y;
        float4 tmaxy = hiy * nodeInvDir.y + nodePos.y;
        float4 tminz = loz * nodeInvDir.z + nodePos.z;
        float4 tmaxz = hiz * nodeInvDir.z + nodePos.z;

        float4 cmin = max(max(max(tminx, tminy), tminz), 0.0f);
        float4 cmax = min(min(min(tmaxx, tmaxy), tmaxz), tmax);

        uint isInner = (meta & (meta << 1)) & 0x10101010;
        uint innerMask = (isInner >> 4) * 0xffu;
        uint bitIndex = (meta ^ (octinv4 & innerMask)) & 0x1F1F1F1F;
        uint childBits = (meta >> 5) & 0x07070707;

        [unroll]
        for (int j = 0; j < 4; ++j)
        {
            if (cmin[j] <= cmax[j])
            {
                uint shiftBits = (childBits >> (j * 8)) & 255;
                uint bitShift = (bitIndex >> (j * 8)) & 31;
                hitmask |= shiftBits << bitShift;
            }
        }
    }

    return hitmask;
}

bool RayIntersectBvh(const Ray ray, inout RayHit hit, bool isShadowRay)
{
    float3 invDir = SafeRcp(ray.direction.xyz);
    uint octinv4 = (7 - ((ray.direction.x < 0 ? 4 : 0) | (ray.direction.y < 0 ? 2 : 0) | (ray.direction.z < 0 ? 1 : 0))) * 0x1010101;

    uint2 stack[BVH_STACK_SIZE];
    uint stackPtr = 0;
    // 0x80000000 gets mis-compiled because FXC changes it to -0.0f, and Tint throws away the sign bit.
    // Use 0x80000001 instead.
    uint2 nodeGroup = uint2(0, 0x80000001);
    uint2 triGroup = uint2(0, 0);
    int count = 0;

    const int nodeOffset = 0;

    while (true)
    {
        if (nodeGroup.y > 0x00FFFFFF)
        {
            // Convert the 0x80000001 back to 0x80000000
            if (nodeGroup.y == 0x80000001)
                nodeGroup.y -= 1;

            count += 1;
            uint mask = nodeGroup.y;
            uint childBitIndex = firstbithigh(mask);
            uint childNodeBaseIndex = nodeGroup.x;

            nodeGroup.y &= ~(1 << childBitIndex);
            if (nodeGroup.y > 0x00FFFFFF) 
                stack[stackPtr++] = nodeGroup;

            uint slotIndex = (childBitIndex - 24) ^ (octinv4 & 255);
            uint relativeIndex = countbits(mask & ~(0xFFFFFFFF << slotIndex));
            uint childNodeIndex = childNodeBaseIndex + relativeIndex;

            BVHNode node = BVHNodes[nodeOffset + childNodeIndex];
            uint hitmask = IntersectCWBVHNode(ray.origin, invDir, octinv4, hit.distance, node);

            nodeGroup.x = asuint(node.n1.x);
            nodeGroup.y = (hitmask & 0xFF000000) | (asuint(node.n0.w) >> 24);
            triGroup.x = asuint(node.n1.y);
            triGroup.y = hitmask & 0x00FFFFFF;
            hit.steps++;
        }
        else
        {
            triGroup = nodeGroup;
            nodeGroup = uint2(0, 0);
        }

        // Process all triangles in the current group
        while (triGroup.y != 0)
        {
            count += 4;
            int triangleIndex = firstbithigh(triGroup.y);
            int triAddr = triGroup.x + (triangleIndex * 3);

            // Check intersection and update hit if its closer
            IntersectTriangle(triAddr, ray, hit);

            triGroup.y -= 1 << triangleIndex;
        }

        if (nodeGroup.y <= 0x00FFFFFF)
        {
            if (stackPtr > 0) 
                nodeGroup = stack[--stackPtr];
            else
                break;
        }
    }

    hit.steps = count;

    if (!isShadowRay && hit.distance < FAR_PLANE)
    {
        TriangleAttributes triAttr = TriangleAttributesBuffer[hit.triIndex];

        hit.position = ray.origin + hit.distance * ray.direction;
        hit.tangent = normalize(InterpolateAttribute(hit.barycentric, triAttr.tangent0, triAttr.tangent1, triAttr.tangent2));
        hit.normal = normalize(InterpolateAttribute(hit.barycentric, triAttr.normal0, triAttr.normal1, triAttr.normal2));
        hit.ffnormal = dot(hit.normal, ray.direction) <= 0.0 ? hit.normal : -hit.normal;
        hit.uv = InterpolateAttribute(hit.barycentric, triAttr.uv0, triAttr.uv1, triAttr.uv2);
        hit.material = GetMaterial(Materials[triAttr.materialIndex], ray, hit);
        hit.eta = (dot(ray.direction, hit.normal) < 0.0) ? 1.0f / hit.material.ior : hit.material.ior;
        hit.intersectType = INTERSECT_TRIANGLE;
    }

    return hit.distance < FAR_PLANE;
}

bool RayIntersect(in Ray ray, inout RayHit hit)
{
    hit.distance = FAR_PLANE;

    RayIntersectBvh(ray, hit, false);

    IntersectLights(ray, hit);

    return hit.distance < FAR_PLANE;
}

bool ShadowRayIntersect(in Ray ray)
{
    RayHit hit = (RayHit)0;
    hit.distance = FAR_PLANE;
    return RayIntersectBvh(ray, hit, true);
}

#endif // __UNITY_PATHTRACER_BVH_HLSL__
