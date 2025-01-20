#ifndef __UNITY_PATHTRACER_INTERSECT_HLSL__
#define __UNITY_PATHTRACER_INTERSECT_HLSL__

#include "common.hlsl"

float RectIntersect(in float3 pos, in float3 u, in float3 v, in float4 plane, in Ray r)
{
    float3 n = plane.xyz;
    float dt = dot(r.direction, n);
    float t = (plane.w - dot(n, r.origin)) / dt;
    float res = FAR_PLANE;

    if (t > EPSILON)
    {
        float3 p = r.origin + r.direction * t;
        float3 vi = p - pos;
        float a1 = dot(u, vi);
        if (a1 >= 0.0 && a1 <= 1.0)
        {
            float a2 = dot(v, vi);
            if (a2 >= 0.0 && a2 <= 1.0)
                res = t;
        }
    }

    return res;
}

void IntersectLights(const Ray ray, inout RayHit hit)
{
#if HAS_LIGHTS
    for (int i = 0; i < LightCount; ++i)
    {
        Light light = Lights[i];
        if (light.type == LIGHT_TYPE_RECTANGLE)
        {
            float3 normal = normalize(cross(light.u, light.v));
            float4 plane = float4(normal, dot(normal, light.position));
            float3 u = light.u / dot(light.u, light.u);
            float3 v = light.v / dot(light.v, light.v);
            float d = RectIntersect(light.position, u, v, plane, ray);
            if (d > 0.0 && d < hit.distance && dot(normal, ray.direction) < 0.0)
            {
                hit.distance = d;
                hit.position = ray.origin + d * ray.direction;
                hit.normal = normal;
                hit.ffnormal = dot(hit.normal, ray.direction) <= 0.0 ? hit.normal : -hit.normal;
                hit.triIndex = i;
                hit.intersectType = INTERSECT_LIGHT;
            }
        }
    }
#endif
}

#endif // __UNITY_PATHTRACER_INTERSECT_HLSL__
