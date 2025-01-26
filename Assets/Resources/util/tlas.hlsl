#ifndef __UNITY_PATHTRACER_TLAS_HLSL__
#define __UNITY_PATHTRACER_TLAS_HLSL__

#include "globals.hlsl"
#include "intersect.hlsl"
#include "material.hlsl"
#include "random.hlsl"
#include "triangle_attributes.hlsl"

#define BVH_STACK_SIZE 32

float2 InterpolateAttribute(float2 barycentric, float2 attr0, float2 attr1, float2 attr2)
{
    return attr0 * (1.0f - barycentric.x - barycentric.y) + attr1 * barycentric.x + attr2 * barycentric.y;
}

float3 InterpolateAttribute(float2 barycentric, float3 attr0, float3 attr1, float3 attr2)
{
    return attr0 * (1.0f - barycentric.x - barycentric.y) + attr1 * barycentric.x + attr2 * barycentric.y;
}

bool IntersectTriangle(const BLASInstance instance, int triAddr, const Ray ray, inout RayHit hit)
{
    bool hitFound = false;
    float3 v0 = BVHTris[triAddr + 2].xyz;
    float3 e1 = BVHTris[triAddr + 1].xyz;
    float3 e2 = BVHTris[triAddr + 0].xyz;

    float3 r = cross(ray.direction, e2);
    float a = dot(e1, r);

    if (abs(a) > 0.0000001f)
    {
        float f = 1.0f / a;
        float3 s = ray.origin - v0;
        float u = f * dot(s, r);

        if (u >= 0.0f && u <= 1.0f)
        {
            float3 q = cross(s, e1);
            float v = f * dot(ray.direction, q);

            if (v >= 0.0f && u + v <= 1.0f)
            {
                float distance = f * dot(e2, q);

                if (distance > 0.0f && distance < hit.distance)
                {
                    uint triIndex = instance.triAttributeOffset + asuint(BVHTris[triAddr + 2].w);
                    hit.barycentric = float2(u, v);
                    hit.triAddr = triAddr;
                    hit.triIndex = triIndex;
                    hit.distance = distance;
                    hitFound = true;
                }
            }
        }
    }

    return hitFound;
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

bool RayIntersectBvh(const Ray worldRay, in BLASInstance instance, bool isShadowRay, inout RayHit hit)
{
    const float4x4 worldToLocal = instance.worldToLocal;
    const float3 localOrigin = mul(worldToLocal, float4(worldRay.origin, 1.0f)).xyz;
    // To handle instance scale, transform the ray direction to local space but do not normalize it
    const float3 localDirection = mul(worldToLocal, float4(worldRay.direction, 0.0f)).xyz;
    const Ray localRay = { localOrigin, 0.0f, localDirection, 0.0f };

    float3 invDir = rcp(localRay.direction);
    uint octinv4 = (7 - ((localRay.direction.x < 0 ? 4 : 0) | (localRay.direction.y < 0 ? 2 : 0) | (localRay.direction.z < 0 ? 1 : 0))) * 0x1010101;

    bool hitFound = false;

    uint2 stack[BVH_STACK_SIZE];
    uint stackPtr = 0;
    // 0x80000000 gets mis-compiled because FXC changes it to -0.0f, and Tint throws away the sign bit.
    // Use 0x80000001 instead.
    uint2 nodeGroup = uint2(0, 0x80000001);
    uint2 triGroup = uint2(0, 0);

    const int nodeOffset = instance.bvhOffset;

    while (true)
    {
        if (nodeGroup.y > 0x00FFFFFF)
        {
            // Convert the 0x80000001 back to 0x80000000
            if (nodeGroup.y == 0x80000001)
                nodeGroup.y -= 1;

            hit.steps++;
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
            uint hitmask = IntersectCWBVHNode(localRay.origin, invDir, octinv4, hit.distance, node);

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
            hit.steps += 4;
            int triangleIndex = firstbithigh(triGroup.y);
            int triAddr = triGroup.x + (triangleIndex * 3);

            // Check intersection and update hit if its closer
            hitFound = IntersectTriangle(instance, instance.triOffset + triAddr, localRay, hit) | hitFound;

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

    if (!isShadowRay && hitFound)
    {
        TriangleAttributes triAttr = TriangleAttributesBuffer[hit.triIndex];

        hit.intersectType = INTERSECT_TRIANGLE;

        // To handle instance scale, get the local space hit position and transform it back to world space
        hit.position = mul(instance.localToWorld, float4(localRay.origin + hit.distance * localRay.direction, 1.0f)).xyz;
        hit.distance = length(hit.position - worldRay.origin);

        hit.uv = InterpolateAttribute(hit.barycentric, triAttr.uv0, triAttr.uv1, triAttr.uv2);

        float3 normal = normalize(InterpolateAttribute(hit.barycentric, triAttr.normal0, triAttr.normal1, triAttr.normal2));
        // Use the transposed inverse to transform the normal to world space
        hit.normal = normalize(mul(float4(normal, 0.0f), instance.worldToLocal).xyz);

        float3 tangent = normalize(InterpolateAttribute(hit.barycentric, triAttr.tangent0, triAttr.tangent1, triAttr.tangent2));
        hit.tangent = normalize(mul(instance.localToWorld, float4(tangent, 0.0f)).xyz);

        hit.ffnormal = dot(hit.normal, worldRay.direction) <= 0.0 ? hit.normal : -hit.normal;

        hit.materialIndex = instance.materialIndex;
    }

    return hit.distance < FAR_PLANE;
}

bool RayIntersectTLAS(const Ray ray, inout RayHit hit, bool isShadowRay)
{
    const float3 O = ray.origin;
    const float3 D = normalize(ray.direction);
    const float3 rD = rcp(D);

    bool hitFound = false;
    uint stack[BVH_STACK_SIZE];
    uint nodeIndex = 0;
    uint stackPtr = 0;
    //const Ray worldRay = ray;

    while (true)
    {
        const TLASNode node = TLASNodes[nodeIndex];
        const uint instanceCount = node.instanceCount;

        if (instanceCount == 0)
        {
            uint left = node.left;
            const float3 lmin = node.lmin;
            const float3 lmax = node.lmax;;
            uint right = node.right;
            const float3 rmin = node.rmin;
            const float3 rmax = node.rmax;

            // child AABB intersection tests
            const float3 t1a = (lmin - O) * rD;
            const float3 t2a = (lmax - O) * rD;
            const float3 t1b = (rmin - O) * rD;
            const float3 t2b = (rmax - O) * rD;

            const float3 minta = min3(t1a, t2a);
            const float3 maxta = max3(t1a, t2a);
            const float3 mintb = min3(t1b, t2b);
            const float3 maxtb = max3(t1b, t2b);

            const float tmina = max(max(max(minta.x, minta.y), minta.z), 0);
            const float tmaxa = min(min(min(maxta.x, maxta.y), maxta.z), hit.distance);

            const float tminb = max(max(max(mintb.x, mintb.y), mintb.z), 0);
            const float tmaxb = min(min(min(maxtb.x, maxtb.y), maxtb.z), hit.distance);

            float dist1 = select(tmina, FAR_PLANE, tmina > tmaxa);
            float dist2 = select(tminb, FAR_PLANE, tminb > tmaxb);

            // traverse nearest child first
            if (dist1 > dist2)
            {
                float h = dist1;
                dist1 = dist2;
                dist2 = h;
                uint t = left;
                left = right;
                right = t;
            }

            if (dist1 == FAR_PLANE)
            {
                if (stackPtr > 0)
                    nodeIndex = stack[--stackPtr];
                else
                    break;
            }
            else
            {
                nodeIndex = left;
                if (dist2 != FAR_PLANE)
                    stack[stackPtr++] = right;
            }
        }


        if (instanceCount > 0)
        {
            const uint firstInstance = node.firstInstance;

            //uint i = 0;
            for (uint i = 0; i < instanceCount; ++i)
            {
                const uint instanceIndex = TLASIndices[firstInstance + i];
                const BLASInstance instance = BLASInstances[instanceIndex];
                hitFound = RayIntersectBvh(ray, instance, isShadowRay, hit) | hitFound;

                /*const float4x4 worldToLocal = instance.worldToLocal;
                const float3 localOrigin = mul(worldToLocal, float4(worldRay.origin, 1.0f)).xyz;
                // To handle instance scale, transform the ray direction to local space but do not normalize it
                const float3 localDirection = mul(worldToLocal, float4(worldRay.direction, 0.0f)).xyz;
                const Ray localRay = { localOrigin, localDirection };

                float3 invDir = rcp(localRay.direction);
                uint octinv4 = (7 - ((localRay.direction.x < 0 ? 4 : 0) | (localRay.direction.y < 0 ? 2 : 0) | (localRay.direction.z < 0 ? 1 : 0))) * 0x1010101;

                bool hitFound = false;

                stackPtr++;
                const uint startStackPtr = stackPtr;
                // 0x80000000 gets mis-compiled because FXC changes it to -0.0f, and Tint throws away the sign bit.
                // Use 0x80000001 instead.
                uint2 nodeGroup = uint2(0, 0x80000001);
                uint2 triGroup = uint2(0, 0);

                const int nodeOffset = instance.bvhOffset;

                while (true)
                {
                    if (nodeGroup.y > 0x00FFFFFF)
                    {
                        // Convert the 0x80000001 back to 0x80000000
                        if (nodeGroup.y == 0x80000001)
                            nodeGroup.y -= 1;

                        hit.steps++;
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
                        uint hitmask = IntersectCWBVHNode(localRay.origin, invDir, octinv4, hit.distance, node);

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
                        hit.steps += 4;
                        int triangleIndex = firstbithigh(triGroup.y);
                        int triAddr = triGroup.x + (triangleIndex * 3);

                        // Check intersection and update hit if its closer
                        hitFound = IntersectTriangle(instance, instance.triOffset + triAddr, localRay, hit) | hitFound;

                        triGroup.y -= 1 << triangleIndex;
                    }

                    if (nodeGroup.y <= 0x00FFFFFF)
                    {
                        if (stackPtr > startStackPtr) 
                            nodeGroup = stack[--stackPtr];
                        else
                            break;
                    }
                }

                if (!isShadowRay && hitFound)
                {
                    TriangleAttributes triAttr = TriangleAttributesBuffer[hit.triIndex];

                    hit.intersectType = INTERSECT_TRIANGLE;

                    // To handle instance scale, get the local space hit position and transform it back to world space
                    hit.position = mul(instance.localToWorld, float4(localRay.origin + hit.distance * localRay.direction, 1.0f)).xyz;
                    hit.distance = length(hit.position - worldRay.origin);

                    hit.uv = InterpolateAttribute(hit.barycentric, triAttr.uv0, triAttr.uv1, triAttr.uv2);

                    float3 normal = normalize(InterpolateAttribute(hit.barycentric, triAttr.normal0, triAttr.normal1, triAttr.normal2));
                    // Use the transposed inverse to transform the normal to world space
                    hit.normal = normalize(mul(float4(normal, 0.0f), instance.worldToLocal).xyz);

                    float3 tangent = normalize(InterpolateAttribute(hit.barycentric, triAttr.tangent0, triAttr.tangent1, triAttr.tangent2));
                    hit.tangent = normalize(mul(instance.localToWorld, float4(tangent, 0.0f)).xyz);

                    hit.material = GetMaterial(Materials[instance.materialIndex], worldRay, hit);

                    hit.ffnormal = dot(hit.normal, worldRay.direction) <= 0.0 ? hit.normal : -hit.normal;
                    hit.eta = (dot(worldRay.direction, hit.normal) < 0.0) ? 1.0f / hit.material.ior : hit.material.ior;
                }

                stackPtr--;*/
            }

            if (stackPtr > 0)
                nodeIndex = stack[--stackPtr];
            else
                break;
        }
    }

    return hitFound;
}

bool RayIntersect(in Ray ray, inout RayHit hit)
{
    hit.steps = 0;
    hit.distance = FAR_PLANE;

    RayIntersectTLAS(ray, hit, false);

    IntersectLights(ray, hit);

    return hit.distance < FAR_PLANE;
}

bool ShadowRayIntersect(in Ray ray)
{
    RayHit hit = (RayHit)0;
    hit.distance = FAR_PLANE;
    hit.steps = 0;
    return RayIntersectTLAS(ray, hit, true);
}

#endif // __UNITY_PATHTRACER_TLAS_HLSL__
