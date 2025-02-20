#ifndef __UNITY_PATHTRACER_COMMON__
#define __UNITY_PATHTRACER_COMMON__

#define EPSILON    0.0001f
#define PI         3.14159265358979323
#define INV_PI     0.31830988618379067
#define TWO_PI     6.28318530717958648
#define INV_TWO_PI 0.15915494309189533
#define INV_4_PI   0.07957747154594766
#define FAR_PLANE  100000.0f

// Nodes in CWBVH format.
struct BVHNode
{
    float4 n0;
    float4 n1;
    float4 n2;
    float4 n3;
    float4 n4;
};

#if HAS_TLAS
struct BLASInstance
{
    float4x4 localToWorld;
    float4x4 worldToLocal;
    int bvhOffset;
    int triOffset;
    int triAttributeOffset;
    int materialIndex;
};

// This node struct is stored in the TLASData buffer, left here for reference
// of how the floats in that struct are laid out.
/*struct TLASNode
{
    float3 lmin;
    uint left;

    float3 lmax;
    uint right;

    float3 rmin;
    uint instanceCount;

    float3 rmax;
    uint firstInstance;
};*/
#define TLASNodeSize 16
#endif // HAS_TLAS

struct ScatterSampleRec
{
    float3 L;
    float pdf;
    float3 f;
    float padding;
};

struct LightSampleRec
{
    float3 normal;
    float pdf;

    float3 emission;
    float distance;

    float3 direction;
    float padding;
};

struct MaterialData
{
    float4 data1;
    float4 data2;
    float4 data3;
    float4 data4;
    float4 data5;
    float2 data6;
    float2 textures1;
    float4 textures2;
    float4 texture1Transform;
};

#define SKY_MODE_ENVIRONMENT 0
#define SKY_MODE_BASIC 1

#define ALPHA_MODE_OPAQUE 0
#define ALPHA_MODE_BLEND 1
#define ALPHA_MODE_MASK 2

#define MEDIUM_NONE 0
#define MEDIUM_ABSORB 1
#define MEDIUM_SCATTER 2
#define MEDIUM_EMISSIVE 3

/*struct Medium
{
    float3 color;
    float anisotropy;
    float type;
    float density;
    float2 padding;
};*/

struct Material
{
    float3 baseColor;
    float opacity;

    float3 emission;
    float alphaMode;

    float alphaCutoff;
    float anisotropic;
    float metallic;
    float roughness;

    float subsurface;
    float specularTint;
    float sheen;
    float sheenTint;

    float clearcoat;
    float clearcoatRoughness;
    float specTrans;
    float ior;

    float ax;
    float ay;
    float eta;
    float occlusion;

    //Medium medium;
};

#define LIGHT_TYPE_SPOT 0
#define LIGHT_TYPE_DIRECTIONAL 1
#define LIGHT_TYPE_POINT 2
#define LIGHT_TYPE_RECTANGLE 3
#define LIGHT_TYPE_DISC 4
#define LIGHT_TYPE_PYRAMID 5
#define LIGHT_TYPE_BOX 6
#define LIGHT_TYPE_TUBE 7
#define LIGHT_TYPE_SPHERE 8

struct Light
{
    float3 position;
    uint type;

    float3 emission;
    float range;

    float3 u; // For spot and directional lights, u is the forward direction of the light
    float area;

    float3 v; // For spot lights, v is the cosine of the outter and inner angles.
    float padding;
};

struct Ray
{
    float3 origin;
    float padding1;
    float3 direction;
    float padding2;
};

#define INTERSECT_TRIANGLE 0
#define INTERSECT_LIGHT 1

struct RayHit
{
    float3 position;
    float distance;

    float2 barycentric;
    uint triIndex;
    uint triAddr;

    float3 normal;
    uint steps;

    float3 tangent;
    int materialIndex;

    float3 ffnormal;
    uint intersectType;

    float2 uv;
    float2 padding2;
};

float Luminance(float3 color)
{
    return dot(color, float3(0.299f, 0.587f, 0.114f));
}

float Sqr(float x)
{
    return x * x;
}

float3 SafeRcp(float3 v)
{
    return rcp(v);
    /*float x = v.x == 0.0f ? 0.0f : 1.0f / v.x;
    float y = v.y == 0.0f ? 0.0f : 1.0f / v.y;
    float z = v.z == 0.0f ? 0.0f : 1.0f / v.z;
    return float3(x, y, z);*/
}

uint ExtractByte(uint value, uint byteIndex)
{
    return (value >> (byteIndex * 8)) & 0xFF;
}

// Extracts each byte from the float into the channel of a float4
float4 ExtractBytes(float value)
{
    uint packed = asuint(value);

    float4 channels = float4(
        ExtractByte(packed, 0),
        ExtractByte(packed, 1),
        ExtractByte(packed, 2),
        ExtractByte(packed, 3)
    );

    return channels;
}

float select(float f, float t, bool c)
{
    return c ? t : f;
}

float3 select(float3 f, float3 t, bool c)
{
    return c ? t : f;
}

float4 select(float4 f, float4 t, bool c)
{
    return c ? t : f;
}

bool isless(float4 a, float4 b)
{
    return all(a < b);
}

float3 min3(float3 a, float3 b)
{
    return float3(min(a.x, b.x), min(a.y, b.y), min(a.z, b.z));
}

float3 max3(float3 a, float3 b)
{
    return float3(max(a.x, b.x), max(a.y, b.y), max(a.z, b.z));
}

bool isgreater(float4 a, float4 b)
{
    return all(a > b);
}

float3 greaterThan(float3 a, float3 b)
{
    return float3(a.x > b.x ? 1.0f : 0.0f, a.y > b.y ? 1.0f : 0.0f, a.z > b.z ? 1.0f : 0.0f);
}

uint4 asuint4(float4 v)
{
    return uint4(asuint(v.x), asuint(v.y), asuint(v.z), asuint(v.w));
}

// Heaviside step function
float chiPlus(float x)
{
	return step(0.0f, x);
}

void ConcentricSampleDisk(float u1, float u2, out float dx, out float dy)
{
    // Map uniform random numbers to [-1,1]^2
    float sx = 2.0f * u1 - 1.0f;
    float sy = 2.0f * u2 - 1.0f;

    // Map square to (r,\theta)

    // Handle degeneracy at the origin
    if (sx == 0.0f && sy == 0.0f)
    {
        dx = 0.0f;
        dy = 0.0f;
    }
    else
    {
        float r, theta;
        if (sx >= -sy)
        {
            if (sx > sy)
            {
                // Handle first region of disk
                r = sx;
                if (sy > 0.0)
                    theta = sy / r;
                else
                    theta = 8.0 + sy / r;
            }
            else
            {
                // Handle second region of disk
                r = sy;
                theta = 2.0 - sx / r;
            }
        }
        else
        {
            if (sx <= sy)
            {
                // Handle third region of disk
                r = -sx;
                theta = 4.0 - sy / r;
            }
            else
            {
                // Handle fourth region of disk
                r = -sy;
                theta = 6.0 + sx / r;
            }
        }

        theta *= PI / 4.0;

        dx = r * cos(theta);
        dy = r * sin(theta);
    }
}

#define ONB_METHOD 1

/// Calculate an orthonormal basis from a given z direction.
float3x3 GetONB(float3 z)
{
    float lenSq = dot(z, z);
    if (lenSq == 0.0f)
    {
        return float3x3(1.0f, 0.0f, 0.0f,
                        0.0f, 1.0f, 0.0f,
                        0.0f, 0.0f, 1.0f);
    }
    else
    {
        z = normalize(z);
#if ONB_METHOD == 0
        // https://www.jcgt.org/published/0006/01/01/paper-lowres.pdf
        float s = select(-1.0f, 1.0f, z.z >= 0.0f);
        float a = -1.0f / (s + z.z);
        float b = z.x * z.y * a;
        float3 x = normalize(float3(1.0f + s * z.x * z.x * a, s * b, -s * z.x));
        float3 y = normalize(float3(b, s + z.y * z.y * a, -z.y));
#elif ONB_METHOD == 1
        // MBR frizvald but attempts to deal with z == -1
        // From https://www.shadertoy.com/view/tlVczh
        float k = 1.0f / max(1.0f + z.z, 0.00001);
        // k = min(k, 99995.0);
        float a =  z.y * k;
        float b =  z.y * a;
        float c = -z.x * a;

        float3 x = normalize(float3(z.z + b, c, -z.x));
        float3 y = normalize(float3(c, 1.0f - b, -z.y));
#else
        float3 x = select(float3(1.0, 0.0, 0.0), float3(0.0, 1.0, 0.0), abs(z.x) > 0.5f);
        x -= z * dot(x, z);
        x = normalize(x);
        float3 y = cross(z, x);
#endif
        return float3x3(x, y, z);
    }
}

float3 ToWorld(float3x3 basis, float3 local)
{
    return basis[0] * local.x + basis[1] * local.y + basis[2] * local.z;
}

float3 ToLocal(float3x3 basis, float3 world)
{
    return float3(dot(basis[0], world), dot(basis[1], world), dot(basis[2], world));
}

#endif // __UNITY_PATHTRACER_COMMON__
