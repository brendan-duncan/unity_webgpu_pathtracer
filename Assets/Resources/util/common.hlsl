#ifndef __UNITY_PATHTRACER_COMMON__
#define __UNITY_PATHTRACER_COMMON__

#define PI         3.14159265358979323
#define INV_PI     0.31830988618379067
#define TWO_PI     6.28318530717958648
#define INV_TWO_PI 0.15915494309189533
#define INV_4_PI   0.07957747154594766

#define DEGREES_TO_RADIANS (PI / 180.0f)

float Luminance(float3 color)
{
    return dot(color, float3(0.299f, 0.587f, 0.114f));
}

uint MaxRayBounces;
uint TotalRays;
uint CurrentSample;
float FarPlane;

uint OutputWidth;
uint OutputHeight;
RWTexture2D<float4> Output;
Texture2D<float4> AccumulatedOutput;

struct ScatterSampleRec
{
    float3 L;
    float3 f;
    float pdf;
};

struct LightSampleRec
{
    float3 normal;
    float3 emission;
    float3 direction;
    float dist;
    float pdf;
};

float Select(float f, float t, bool c)
{
    if (c)
        return t;
    else
        return f;
}

float3 Select(float3 f, float3 t, bool c)
{
    if (c)
        return t;
    else
        return f;
}

// Heaviside step function
float chiPlus(float x)
{
	return step(0.0f, x);
}


#define ONB_METHOD 1

/// Calculate an orthonormal basis from a given z direction.
float3x3 GetONB(float3 z)
{
    z = normalize(z);
#if ONB_METHOD == 0
    // https://www.jcgt.org/published/0006/01/01/paper-lowres.pdf
    float s = Select(-1.0f, 1.0f, z.z >= 0.0f);
    float a = -1.0f / (s + z.z);
    float b = z.x * z.y * a;
    float3 x = float3(1.0f + s * z.x * z.x * a, s * b, -s * z.x);
    float3 y = float3(b, s + z.y * z.y * a, -z.y);
#elif ONB_METHOD == 1
    //MBR frizvald but attempts to deal with z == -1
    // From https://www.shadertoy.com/view/tlVczh
    float k = 1.0f / max(1.0f + z.z, 0.00001);
    // k = min(k, 99995.0);
    float a =  z.y * k;
    float b =  z.y * a;
    float c = -z.x * a;
    
    float3 x = float3(z.z + b, c, -z.x);
    float3 y = float3(c, 1.0f - b, -z.y);
#else
    float3 x = Select(float3(1.0, 0.0, 0.0), float3(0.0, 1.0, 0.0), abs(z.x) > 0.5f);
	x -= z * dot(x, z);
	x = normalize(x);
	float3 y = cross(z, x);
#endif
    return float3x3(x, y, z);
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
