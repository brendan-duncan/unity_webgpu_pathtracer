#ifndef __UNITY_PATHTRACER_TLAS_HLSL__
#define __UNITY_PATHTRACER_TLAS_HLSL__

#include "common.hlsl"
#include "ray.hlsl"
#include "bvh.hlsl"

StructuredBuffer<float4> alt4Node;

#define BVH4_STACK_SIZE 32

uint4 asuint4(float4 v)
{
    return uint4(asuint(v.x), asuint(v.y), asuint(v.z), asuint(v.w));
}

RayHit RayIntersectTLAS(const Ray ray, bool isShadowRay)
{
    RayHit hit = (RayHit)0;
    hit.distance = FarPlane;

    float3 rD = rcp(ray.direction.xyz);

    const float4 zero4 = (float4)0;

    uint offset = 0;
    uint stackPtr = 0;
    uint stack[BVH4_STACK_SIZE];
    while (true)
    {
        // vectorized 4-wide quantized aabb intersection
		const float4 data0 = alt4Node[offset];
		const float4 data1 = alt4Node[offset + 1];
		const float4 data2 = alt4Node[offset + 2];

		const float4 cminx4 = ExtractBytes(data0.w);
		const float4 cmaxx4 = ExtractBytes(data1.w);
		const float4 cminy4 = ExtractBytes(data2.x);
		const float3 bminO = (ray.origin - data0.xyz) * rD;
        const float3 rDe = rD * data1.xyz;
		const float4 cmaxy4 = ExtractBytes(data2.y);
		const float4 cminz4 = ExtractBytes(data2.z);
		const float4 cmaxz4 = ExtractBytes(data2.w);
		const float4 t1x4 = cminx4 * rDe.xxxx - bminO.xxxx, t2x4 = cmaxx4 * rDe.xxxx - bminO.xxxx;
		const float4 t1y4 = cminy4 * rDe.yyyy - bminO.yyyy, t2y4 = cmaxy4 * rDe.yyyy - bminO.yyyy;
		const float4 t1z4 = cminz4 * rDe.zzzz - bminO.zzzz, t2z4 = cmaxz4 * rDe.zzzz - bminO.zzzz;
		uint4 data3 = asuint4(alt4Node[offset + 3]);
		const float4 mintx4 = min(t1x4, t2x4);
        const float4 maxtx4 = max(t1x4, t2x4);
		const float4 minty4 = min(t1y4, t2y4);
        const float4 maxty4 = max(t1y4, t2y4);
		const float4 mintz4 = min(t1z4, t2z4);
        const float4 maxtz4 = max(t1z4, t2z4);
		const float4 maxxy4 = Select(mintx4, minty4, isless(mintx4, minty4));
		const float4 maxyz4 = Select(maxxy4, mintz4, isless(maxxy4, mintz4));
		float4 dst4 = Select(maxyz4, zero4, isless(maxyz4, zero4));
		const float4 minxy4 = Select(maxtx4, maxty4, isgreater(maxtx4, maxty4));
		const float4 minyz4 = Select(minxy4, maxtz4, isgreater(minxy4, maxtz4));
		const float4 tmax4 = Select(minyz4, (float4)hit.distance, isgreater(minyz4, (float4)hit.distance));
		dst4 = Select(dst4, (float4)(1e30f), isgreater(dst4, tmax4));

		// sort intersection distances - TODO: handle single-intersection case separately.
		if (dst4.x < dst4.z)
        {
            dst4 = dst4.zyxw;
            data3 = data3.zyxw; // bertdobbelaere.github.io/sorting_networks.html
        }
		if (dst4.y < dst4.w)
        {
            dst4 = dst4.xwzy;
            data3 = data3.xwzy;
        }
		if (dst4.x < dst4.y)
        {
            dst4 = dst4.yxzw;
            data3 = data3.yxzw;
        }
		if (dst4.z < dst4.w)
        {
            dst4 = dst4.xywz;
            data3 = data3.xywz;
        }
		if (dst4.y < dst4.z)
        {
            dst4 = dst4.xzyw;
            data3 = data3.xzyw;
        }

        // process results, starting with farthest child, so nearest ends on top of stack
		uint nextNode = 0;
		if (dst4.x < 1e30f) 
		{
			if ((data3.x >> 31) == 0) nextNode = data3.x; else
			{
				const uint blasCount = (data3.x >> 16) & 0x7fff;
				for (uint i = 0; i < blasCount; i++)
                {
                    //IntersectTri((data3.x & 0xffff) + offset + i * STRIDE, &O, &D, &hit, alt4Node);
                }
			}
		}
		if (dst4.y < 1e30f) 
		{
			if (data3.y >> 31)
			{
				const uint blasCount = (data3.y >> 16) & 0x7fff;
				for (uint i = 0; i < blasCount; i++) 
                {
                    //IntersectTri((data3.y & 0xffff) + offset + i * STRIDE, &O, &D, &hit, alt4Node);
                }
			}
			else
			{
				if (nextNode)
                    stack[stackPtr++] = nextNode;
				nextNode = data3.y;
			}
		}
		if (dst4.z < 1e30f) 
		{
			if (data3.z >> 31) 
			{
				const uint blasCount = (data3.z >> 16) & 0x7fff;
				for (uint i = 0; i < blasCount; i++)
                {
                    //IntersectTri((data3.z & 0xffff) + offset + i * STRIDE, &O, &D, &hit, alt4Node);
                }
			}
			else
			{
				if (nextNode)
                    stack[stackPtr++] = nextNode;
				nextNode = data3.z;
			}
		}
		if (dst4.w < 1e30f) 
		{
			if (data3.w >> 31) 
			{
				const uint blasCount = (data3.w >> 16) & 0x7fff;
				for (uint i = 0; i < blasCount; i++)
                {
                    //IntersectTri((data3.w & 0xffff) + offset + i * STRIDE, &O, &D, &hit, alt4Node);
                }
			}
			else
			{
				if (nextNode)
                    stack[stackPtr++] = nextNode;
				nextNode = data3.w;
			}
		}
		// continue with nearest node or first node on the stack
		if (nextNode)
        {
            offset = nextNode;
        }
        else
		{
			if (!stackPtr)
                break;
			offset = stack[--stackPtr];
		}
    }
}


#endif // __UNITY_PATHTRACER_TLAS_HLSL__
