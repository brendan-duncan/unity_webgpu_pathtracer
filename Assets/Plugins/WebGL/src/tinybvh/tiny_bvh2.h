#ifndef TINY_BVH_H_
#define TINY_BVH_H_

// Binned BVH building: bin count.
#define BVHBINS 8

// SAH BVH building: Heuristic parameters
// CPU builds: C_INT = 1, C_TRAV = 1 seems optimal.
#define C_INT	1
#define C_TRAV	1

// 'Infinity' values
#define BVH_FAR	1e30f		// actual valid ieee range: 3.40282347E+38
#define BVH_DBL_FAR 1e300	// actual valid ieee range: 1.797693134862315E+308

// Features
#define DOUBLE_PRECISION_SUPPORT

// We'll use this whenever a layout has no specialized shadow ray query.
#define FALLBACK_SHADOW_QUERY( s ) { Ray r = s; float d = s.hit.t; Intersect( r ); return r.hit.t < d; }

// library version
#define TINY_BVH_VERSION_MAJOR	1
#define TINY_BVH_VERSION_MINOR	1
#define TINY_BVH_VERSION_SUB	1

// ============================================================================
//
//        P R E L I M I N A R I E S
//
// ============================================================================

// needful includes
#ifdef _MSC_VER // Visual Studio / C11
#include <malloc.h> // for alloc/free
#include <stdio.h> // for fprintf
#include <math.h> // for sqrtf, fabs
#include <string.h> // for memset
#include <stdlib.h> // for exit(1)
#else // Emscripten / gcc / clang
#include <cstdlib>
#include <cstdio>
#include <cmath>
#include <cstring>
#endif
#include <cstdint>

// aligned memory allocation
// note: formally size needs to be a multiple of 'alignment'. See:
// https://en.cppreference.com/w/c/memory/aligned_alloc
// EMSCRIPTEN enforces this.
// Copy of the same construct in tinyocl, different namespace.
namespace tinybvh {

inline size_t make_multiple_64( size_t x ) { return (x + 63) & ~0x3f; }

} // namespace tinybvh

#ifdef _MSC_VER // Visual Studio / C11
#define ALIGNED( x ) __declspec( align( x ) )
namespace tinybvh {
inline void* malloc64( size_t size, void* = nullptr )
{
	return size == 0 ? 0 : _aligned_malloc( make_multiple_64( size ), 64 );
}
inline void free64( void* ptr, void* = nullptr ) { _aligned_free( ptr ); }
}
#else // EMSCRIPTEN / gcc / clang
#define ALIGNED( x ) __attribute__( ( aligned( x ) ) )
namespace tinybvh {
inline void* malloc64( size_t size, void* = nullptr )
{
	return size == 0 ? 0 : aligned_alloc( 64, make_multiple_64( size ) );
}
inline void free64( void* ptr, void* = nullptr ) { free( ptr ); }
}
#endif

namespace tinybvh {

#ifdef _MSC_VER
// Suppress a warning caused by the union of x,y,.. and cell[..] in vectors.
// We need this union to address vector components either by name or by index.
// The warning is re-enabled right after the definition of the data types.
#pragma warning ( push )
#pragma warning ( disable: 4201 /* nameless struct / union */ )
#endif

#ifndef TINYBVH_USE_CUSTOM_VECTOR_TYPES

struct bvhvec3;
struct ALIGNED( 16 ) bvhvec4
{
	// vector naming is designed to not cause any name clashes.
	bvhvec4() = default;
	bvhvec4( const float a, const float b, const float c, const float d ) : x( a ), y( b ), z( c ), w( d ) {}
	bvhvec4( const float a ) : x( a ), y( a ), z( a ), w( a ) {}
	bvhvec4( const bvhvec3 & a );
	bvhvec4( const bvhvec3 & a, float b );
	float& operator [] ( const int32_t i ) { return cell[i]; }
	union { struct { float x, y, z, w; }; float cell[4]; };
};

struct ALIGNED( 8 ) bvhvec2
{
	bvhvec2() = default;
	bvhvec2( const float a, const float b ) : x( a ), y( b ) {}
	bvhvec2( const float a ) : x( a ), y( a ) {}
	bvhvec2( const bvhvec4 a ) : x( a.x ), y( a.y ) {}
	float& operator [] ( const int32_t i ) { return cell[i]; }
	union { struct { float x, y; }; float cell[2]; };
};

struct bvhvec3
{
	bvhvec3() = default;
	bvhvec3( const float a, const float b, const float c ) : x( a ), y( b ), z( c ) {}
	bvhvec3( const float a ) : x( a ), y( a ), z( a ) {}
	bvhvec3( const bvhvec4 a ) : x( a.x ), y( a.y ), z( a.z ) {}
	float halfArea() { return x < -BVH_FAR ? 0 : (x * y + y * z + z * x); } // for SAH calculations
	float& operator [] ( const int32_t i ) { return cell[i]; }
	union { struct { float x, y, z; }; float cell[3]; };
};

struct bvhint3
{
	bvhint3() = default;
	bvhint3( const int32_t a, const int32_t b, const int32_t c ) : x( a ), y( b ), z( c ) {}
	bvhint3( const int32_t a ) : x( a ), y( a ), z( a ) {}
	bvhint3( const bvhvec3& a ) { x = (int32_t)a.x, y = (int32_t)a.y, z = (int32_t)a.z; }
	int32_t& operator [] ( const int32_t i ) { return cell[i]; }
	union { struct { int32_t x, y, z; }; int32_t cell[3]; };
};

struct bvhint2
{
	bvhint2() = default;
	bvhint2( const int32_t a, const int32_t b ) : x( a ), y( b ) {}
	bvhint2( const int32_t a ) : x( a ), y( a ) {}
	int32_t x, y;
};

struct bvhuint2
{
	bvhuint2() = default;
	bvhuint2( const uint32_t a, const uint32_t b ) : x( a ), y( b ) {}
	bvhuint2( const uint32_t a ) : x( a ), y( a ) {}
	uint32_t x, y;
};

#endif // TINYBVH_USE_CUSTOM_VECTOR_TYPES

struct bvhaabb
{
	bvhvec3 minBounds; uint32_t dummy1;
	bvhvec3 maxBounds; uint32_t dummy2;
};

struct bvhvec4slice
{
	bvhvec4slice() = default;
	bvhvec4slice( const bvhvec4* data, uint32_t count, uint32_t stride = sizeof( bvhvec4 ) );
	operator bool() const { return !!data; }
	const bvhvec4& operator [] ( size_t i ) const;
	const int8_t* data = nullptr;
	uint32_t count, stride;
};

#ifdef _MSC_VER
#pragma warning ( pop )
#endif

// Math operations.
// Note: Since this header file is expected to be included in a source file
// of a separate project, the static keyword doesn't provide sufficient
// isolation; hence the tinybvh_ prefix.
inline float tinybvh_safercp( const float x ) { return x > 1e-12f ? (1.0f / x) : (x < -1e-12f ? (1.0f / x) : BVH_FAR); }
inline bvhvec3 tinybvh_safercp( const bvhvec3 a ) { return bvhvec3( tinybvh_safercp( a.x ), tinybvh_safercp( a.y ), tinybvh_safercp( a.z ) ); }
static inline float tinybvh_min( const float a, const float b ) { return a < b ? a : b; }
static inline float tinybvh_max( const float a, const float b ) { return a > b ? a : b; }
static inline double tinybvh_min( const double a, const double b ) { return a < b ? a : b; }
static inline double tinybvh_max( const double a, const double b ) { return a > b ? a : b; }
static inline int32_t tinybvh_min( const int32_t a, const int32_t b ) { return a < b ? a : b; }
static inline int32_t tinybvh_max( const int32_t a, const int32_t b ) { return a > b ? a : b; }
static inline uint32_t tinybvh_min( const uint32_t a, const uint32_t b ) { return a < b ? a : b; }
static inline uint32_t tinybvh_max( const uint32_t a, const uint32_t b ) { return a > b ? a : b; }
static inline bvhvec3 tinybvh_min( const bvhvec3& a, const bvhvec3& b ) { return bvhvec3( tinybvh_min( a.x, b.x ), tinybvh_min( a.y, b.y ), tinybvh_min( a.z, b.z ) ); }
static inline bvhvec4 tinybvh_min( const bvhvec4& a, const bvhvec4& b ) { return bvhvec4( tinybvh_min( a.x, b.x ), tinybvh_min( a.y, b.y ), tinybvh_min( a.z, b.z ), tinybvh_min( a.w, b.w ) ); }
static inline bvhvec3 tinybvh_max( const bvhvec3& a, const bvhvec3& b ) { return bvhvec3( tinybvh_max( a.x, b.x ), tinybvh_max( a.y, b.y ), tinybvh_max( a.z, b.z ) ); }
static inline bvhvec4 tinybvh_max( const bvhvec4& a, const bvhvec4& b ) { return bvhvec4( tinybvh_max( a.x, b.x ), tinybvh_max( a.y, b.y ), tinybvh_max( a.z, b.z ), tinybvh_max( a.w, b.w ) ); }
static inline float tinybvh_clamp( const float x, const float a, const float b ) { return x < a ? a : (x > b ? b : x); }
static inline int32_t tinybvh_clamp( const int32_t x, const int32_t a, const int32_t b ) { return x < a ? a : (x > b ? b : x); }
template <class T> inline static void tinybvh_swap( T& a, T& b ) { T t = a; a = b; b = t; }

// Operator overloads.
// Only a minimal set is provided.
#ifndef TINYBVH_USE_CUSTOM_VECTOR_TYPES

inline bvhvec2 operator-( const bvhvec2& a ) { return bvhvec2( -a.x, -a.y ); }
inline bvhvec3 operator-( const bvhvec3& a ) { return bvhvec3( -a.x, -a.y, -a.z ); }
inline bvhvec4 operator-( const bvhvec4& a ) { return bvhvec4( -a.x, -a.y, -a.z, -a.w ); }
inline bvhvec2 operator+( const bvhvec2& a, const bvhvec2& b ) { return bvhvec2( a.x + b.x, a.y + b.y ); }
inline bvhvec3 operator+( const bvhvec3& a, const bvhvec3& b ) { return bvhvec3( a.x + b.x, a.y + b.y, a.z + b.z ); }
inline bvhvec4 operator+( const bvhvec4& a, const bvhvec4& b ) { return bvhvec4( a.x + b.x, a.y + b.y, a.z + b.z, a.w + b.w ); }
inline bvhvec4 operator+( const bvhvec4& a, const bvhvec3& b ) { return bvhvec4( a.x + b.x, a.y + b.y, a.z + b.z, a.w ); }
inline bvhvec2 operator-( const bvhvec2& a, const bvhvec2& b ) { return bvhvec2( a.x - b.x, a.y - b.y ); }
inline bvhvec3 operator-( const bvhvec3& a, const bvhvec3& b ) { return bvhvec3( a.x - b.x, a.y - b.y, a.z - b.z ); }
inline bvhvec4 operator-( const bvhvec4& a, const bvhvec4& b ) { return bvhvec4( a.x - b.x, a.y - b.y, a.z - b.z, a.w - b.w ); }
inline void operator+=( bvhvec2& a, const bvhvec2& b ) { a.x += b.x; a.y += b.y; }
inline void operator+=( bvhvec3& a, const bvhvec3& b ) { a.x += b.x; a.y += b.y; a.z += b.z; }
inline void operator+=( bvhvec4& a, const bvhvec4& b ) { a.x += b.x; a.y += b.y; a.z += b.z; a.w += b.w; }
inline bvhvec2 operator*( const bvhvec2& a, const bvhvec2& b ) { return bvhvec2( a.x * b.x, a.y * b.y ); }
inline bvhvec3 operator*( const bvhvec3& a, const bvhvec3& b ) { return bvhvec3( a.x * b.x, a.y * b.y, a.z * b.z ); }
inline bvhvec4 operator*( const bvhvec4& a, const bvhvec4& b ) { return bvhvec4( a.x * b.x, a.y * b.y, a.z * b.z, a.w * b.w ); }
inline bvhvec2 operator*( const bvhvec2& a, float b ) { return bvhvec2( a.x * b, a.y * b ); }
inline bvhvec3 operator*( const bvhvec3& a, float b ) { return bvhvec3( a.x * b, a.y * b, a.z * b ); }
inline bvhvec4 operator*( const bvhvec4& a, float b ) { return bvhvec4( a.x * b, a.y * b, a.z * b, a.w * b ); }
inline bvhvec2 operator*( float b, const bvhvec2& a ) { return bvhvec2( b * a.x, b * a.y ); }
inline bvhvec3 operator*( float b, const bvhvec3& a ) { return bvhvec3( b * a.x, b * a.y, b * a.z ); }
inline bvhvec4 operator*( float b, const bvhvec4& a ) { return bvhvec4( b * a.x, b * a.y, b * a.z, b * a.w ); }
inline bvhvec2 operator/( float b, const bvhvec2& a ) { return bvhvec2( b / a.x, b / a.y ); }
inline bvhvec3 operator/( float b, const bvhvec3& a ) { return bvhvec3( b / a.x, b / a.y, b / a.z ); }
inline bvhvec4 operator/( float b, const bvhvec4& a ) { return bvhvec4( b / a.x, b / a.y, b / a.z, b / a.w ); }
inline void operator*=( bvhvec3& a, const float b ) { a.x *= b; a.y *= b; a.z *= b; }

#endif // TINYBVH_USE_CUSTOM_VECTOR_TYPES

// Vector math: cross and dot.
static inline bvhvec3 cross( const bvhvec3& a, const bvhvec3& b )
{
	return bvhvec3( a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x );
}
static inline float dot( const bvhvec2& a, const bvhvec2& b ) { return a.x * b.x + a.y * b.y; }
static inline float dot( const bvhvec3& a, const bvhvec3& b ) { return a.x * b.x + a.y * b.y + a.z * b.z; }
static inline float dot( const bvhvec4& a, const bvhvec4& b ) { return a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w; }

// Vector math: common operations.
static float length( const bvhvec3& a ) { return sqrtf( a.x * a.x + a.y * a.y + a.z * a.z ); }
static bvhvec3 normalize( const bvhvec3& a )
{
	float l = length( a ), rl = l == 0 ? 0 : (1.0f / l);
	return a * rl;
}

#ifdef DOUBLE_PRECISION_SUPPORT
// Double-precision math

#ifndef TINYBVH_USE_CUSTOM_VECTOR_TYPES

struct bvhdbl3
{
	bvhdbl3() = default;
	bvhdbl3( const double a, const double b, const double c ) : x( a ), y( b ), z( c ) {}
	bvhdbl3( const double a ) : x( a ), y( a ), z( a ) {}
	bvhdbl3( const bvhvec3 a ) : x( (double)a.x ), y( (double)a.y ), z( (double)a.z ) {}
	double halfArea() { return x < -BVH_FAR ? 0 : (x * y + y * z + z * x); } // for SAH calculations
	double& operator [] ( const int32_t i ) { return cell[i]; }
	union { struct { double x, y, z; }; double cell[3]; };
};

#endif // TINYBVH_USE_CUSTOM_VECTOR_TYPES

static inline bvhdbl3 tinybvh_min( const bvhdbl3& a, const bvhdbl3& b ) { return bvhdbl3( tinybvh_min( a.x, b.x ), tinybvh_min( a.y, b.y ), tinybvh_min( a.z, b.z ) ); }
static inline bvhdbl3 tinybvh_max( const bvhdbl3& a, const bvhdbl3& b ) { return bvhdbl3( tinybvh_max( a.x, b.x ), tinybvh_max( a.y, b.y ), tinybvh_max( a.z, b.z ) ); }

#ifndef TINYBVH_USE_CUSTOM_VECTOR_TYPES

inline bvhdbl3 operator-( const bvhdbl3& a ) { return bvhdbl3( -a.x, -a.y, -a.z ); }
inline bvhdbl3 operator+( const bvhdbl3& a, const bvhdbl3& b ) { return bvhdbl3( a.x + b.x, a.y + b.y, a.z + b.z ); }
inline bvhdbl3 operator-( const bvhdbl3& a, const bvhdbl3& b ) { return bvhdbl3( a.x - b.x, a.y - b.y, a.z - b.z ); }
inline void operator+=( bvhdbl3& a, const bvhdbl3& b ) { a.x += b.x; a.y += b.y; a.z += b.z; }
inline bvhdbl3 operator*( const bvhdbl3& a, const bvhdbl3& b ) { return bvhdbl3( a.x * b.x, a.y * b.y, a.z * b.z ); }
inline bvhdbl3 operator*( const bvhdbl3& a, double b ) { return bvhdbl3( a.x * b, a.y * b, a.z * b ); }
inline bvhdbl3 operator*( double b, const bvhdbl3& a ) { return bvhdbl3( b * a.x, b * a.y, b * a.z ); }
inline bvhdbl3 operator/( double b, const bvhdbl3& a ) { return bvhdbl3( b / a.x, b / a.y, b / a.z ); }
inline bvhdbl3 operator*=( bvhdbl3& a, const double b ) { return bvhdbl3( a.x * b, a.y * b, a.z * b ); }

#endif // TINYBVH_USE_CUSTOM_VECTOR_TYPES

static inline bvhdbl3 cross( const bvhdbl3& a, const bvhdbl3& b )
{
	return bvhdbl3( a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x );
}
static inline double dot( const bvhdbl3& a, const bvhdbl3& b ) { return a.x * b.x + a.y * b.y + a.z * b.z; }

#endif // DOUBLE_PRECISION_SUPPORT

typedef bvhvec4 SIMDVEC4;
#define SIMD_SETVEC(a,b,c,d) bvhvec4( d, c, b, a )
#define SIMD_SETRVEC(a,b,c,d) bvhvec4( a, b, c, d )

// error handling
#define FATAL_ERROR_IF(c,s) if (c) { fprintf( stderr, \
	"Fatal error in tiny_bvh.h, line %i:\n%s\n", __LINE__, s ); exit( 1 ); }

// ============================================================================
//
//        T I N Y _ B V H   I N T E R F A C E
//
// ============================================================================

struct Intersection
{
	// An intersection result is designed to fit in no more than
	// four 32-bit values. This allows efficient storage of a result in
	// GPU code. The obvious missing result is an instance id; consider
	// squeezing this in the 'prim' field in some way.
	// Using this data and the original triangle data, all other info for
	// shading (such as normal, texture color etc.) can be reconstructed.
	float t, u, v;	// distance along ray & barycentric coordinates of the intersection
	uint32_t prim;	// primitive index
};

struct Ray
{
	// Basic ray class. Note: For single blas traversal it is expected
	// that Ray::rD is properly initialized. For tlas/blas traversal this
	// field is typically updated for each blas.
	Ray() = default;
	Ray( bvhvec3 origin, bvhvec3 direction, float t = BVH_FAR )
	{
		memset( this, 0, sizeof( Ray ) );
		O = origin, D = normalize( direction ), rD = tinybvh_safercp( D );
		hit.t = t;
	}
	ALIGNED( 16 ) bvhvec3 O; uint32_t dummy1;
	ALIGNED( 16 ) bvhvec3 D; uint32_t dummy2;
	ALIGNED( 16 ) bvhvec3 rD; uint32_t dummy3;
	ALIGNED( 16 ) Intersection hit;
};

#ifdef DOUBLE_PRECISION_SUPPORT

struct RayEx
{
	// Double-precision ray definition.
	RayEx() = default;
	RayEx( bvhdbl3 origin, bvhdbl3 direction, double tmax = BVH_DBL_FAR )
	{
		memset( this, 0, sizeof( RayEx ) );
		O = origin, D = direction;
		double rl = 1.0 / sqrt( D.x * D.x + D.y * D.y + D.z * D.z );
		D.x *= rl, D.y *= rl, D.z *= rl;
		rD.x = 1.0 / D.x, rD.y = 1.0 / D.y, rD.z = 1.0 / D.z;
		u = v = 0, t = tmax;
	}
	bvhdbl3 O, D, rD;
	double t, u, v;
	uint64_t primIdx;
};

#endif

struct BVHContext
{
	void* (*malloc)(size_t size, void* userdata) = malloc64;
	void (*free)(void* ptr, void* userdata) = free64;
	void* userdata = nullptr;
};

enum TraceDevice : uint32_t { USE_CPU = 1, USE_GPU };

class BVHBase
{
public:
	struct Fragment
	{
		// A fragment stores the bounds of an input primitive. The name 'Fragment' is from
		// "Parallel Spatial Splits in Bounding Volume Hierarchies", 2016, Fuetterling et al.,
		// and refers to the potential splitting of these boxes for SBVH construction.
		bvhvec3 bmin;				// AABB min x, y and z
		uint32_t primIdx;			// index of the original primitive
		bvhvec3 bmax;				// AABB max x, y and z
		uint32_t clipped = 0;		// Fragment is the result of clipping if > 0.
		bool validBox() { return bmin.x < BVH_FAR; }
	};
	// BVH flags, maintainted by tiny_bvh.
	bool rebuildable = true;		// rebuilds are safe only if a tree has not been converted.
	bool refittable = true;			// refits are safe only if the tree has no spatial splits.
	bool frag_min_flipped = false;	// AVX builders flip aabb min.
	bool may_have_holes = false;	// threaded builds and MergeLeafs produce BVHs with unused nodes.
	bool bvh_over_aabbs = false;	// a BVH over AABBs is useful for e.g. TLAS traversal.
	BVHContext context;				// context used to provide user-defined allocation functions
	// Keep track of allocated buffer size to avoid repeated allocation during layout conversion.
	uint32_t allocatedNodes = 0;	// number of nodes allocated for the BVH.
	uint32_t usedNodes = 0;			// number of nodes used for the BVH.
	uint32_t triCount = 0;			// number of primitives in the BVH.
	uint32_t idxCount = 0;			// number of primitive indices; can exceed triCount for SBVH.
	// Custom memory allocation
	void* AlignedAlloc( size_t size );
	void AlignedFree( void* ptr );
	// Common methods
	void CopyBasePropertiesFrom( const BVHBase& original );	// copy flags from one BVH to another
protected:
	void IntersectTri( Ray& ray, const bvhvec4slice& verts, const uint32_t triIdx ) const;
	bool TriOccludes( const Ray& ray, const bvhvec4slice& verts, const uint32_t idx ) const;
	static float IntersectAABB( const Ray& ray, const bvhvec3& aabbMin, const bvhvec3& aabbMax );
	static void PrecomputeTriangle( const bvhvec4slice& vert, uint32_t triIndex, float* T );
	static float SA( const bvhvec3& aabbMin, const bvhvec3& aabbMax );
};

class BLASInstance;
class BVH_Verbose;
class BVH : public BVHBase
{
public:
	enum BuildFlags : uint32_t {
		NONE = 0,			// Default building behavior (binned, SAH-driven).
		FULLSPLIT = 1		// Split as far as possible, even when SAH doesn't agree.
	};
	struct BVHNode
	{
		// 'Traditional' 32-byte BVH node layout, as proposed by Ingo Wald.
		// When aligned to a cache line boundary, two of these fit together.
		bvhvec3 aabbMin; uint32_t leftFirst; // 16 bytes
		bvhvec3 aabbMax; uint32_t triCount;	// 16 bytes, total: 32 bytes
		bool isLeaf() const { return triCount > 0; /* empty BVH leaves do not exist */ }
		float Intersect( const Ray& ray ) const { return BVH::IntersectAABB( ray, aabbMin, aabbMax ); }
		float SurfaceArea() const { return BVH::SA( aabbMin, aabbMax ); }
	};
	BVH( BVHContext ctx = {} ) { context = ctx; }
	BVH( const BVH_Verbose& original ) { ConvertFrom( original ); }
	BVH( const bvhvec4* vertices, const uint32_t primCount ) { Build( vertices, primCount ); }
	BVH( const bvhvec4slice& vertices ) { Build( vertices ); }
	~BVH();
	void ConvertFrom( const BVH_Verbose& original );
	float SAHCost( const uint32_t nodeIdx = 0 ) const;
	int32_t NodeCount() const;
	int32_t PrimCount( const uint32_t nodeIdx = 0 ) const;
	void Compact();
	void BuildDefault( const bvhvec4* vertices, const uint32_t primCount )
	{
		BuildDefault( bvhvec4slice{ vertices, primCount * 3, sizeof( bvhvec4 ) } );
	}
	void BuildDefault( const bvhvec4slice& vertices )
	{
	#if defined(BVH_USEAVX)
		BuildAVX( vertices );
	#elif defined(BVH_USENEON)
		BuildNEON( vertices );
	#else
		Build( vertices );
	#endif
	}
	void BuildQuick( const bvhvec4* vertices, const uint32_t primCount );
	void BuildQuick( const bvhvec4slice& vertices );
	void Build( const bvhvec4* vertices, const uint32_t primCount );
	void Build( const bvhvec4slice& vertices );
	void BuildHQ( const bvhvec4* vertices, const uint32_t primCount );
	void BuildHQ( const bvhvec4slice& vertices );
#ifdef BVH_USEAVX
	void BuildAVX( const bvhvec4* vertices, const uint32_t primCount );
	void BuildAVX( const bvhvec4slice& vertices );
#elif defined BVH_USENEON
	void BuildNEON( const bvhvec4* vertices, const uint32_t primCount );
	void BuildNEON( const bvhvec4slice& vertices );
#endif
	void BuildTLAS( const bvhaabb* aabbs, const uint32_t aabbCount );
	void BuildTLAS( const BLASInstance* bvhs, const uint32_t instCount );
	void Refit( const uint32_t nodeIdx = 0 );
	int32_t Intersect( Ray& ray ) const;
	int32_t IntersectTLAS( Ray& ray ) const;
	bool IsOccluded( const Ray& ray ) const;
	void Intersect256Rays( Ray* first ) const;
	void Intersect256RaysSSE( Ray* packet ) const; // requires BVH_USEAVX
private:
	bool ClipFrag( const Fragment& orig, Fragment& newFrag, bvhvec3 bmin, bvhvec3 bmax, bvhvec3 minDim );
	void RefitUpVerbose( uint32_t nodeIdx );
	uint32_t FindBestNewPosition( const uint32_t Lid );
	void ReinsertNodeVerbose( const uint32_t Lid, const uint32_t Nid, const uint32_t origin );
	uint32_t CountSubtreeTris( const uint32_t nodeIdx, uint32_t* counters );
	void MergeSubtree( const uint32_t nodeIdx, uint32_t* newIdx, uint32_t& newIdxPtr );
public:
	// Basic BVH data
	bvhvec4slice verts = {};		// pointer to input primitive array: 3x16 bytes per tri.
	uint32_t* triIdx = 0;			// primitive index array.
	BVHNode* bvhNode = 0;			// BVH node pool, Wald 32-byte format. Root is always in node 0.
	Fragment* fragment = 0;			// input primitive bounding boxes.
	BuildFlags buildFlag = NONE;	// hint to the builder: currently, NONE or FULLSPLIT.
};

#ifdef DOUBLE_PRECISION_SUPPORT

class BVH_Double : public BVHBase
{
public:
	enum BuildFlags : uint32_t {
		NONE = 0,			// Default building behavior (binned, SAH-driven).
		FULLSPLIT = 1		// Split as far as possible, even when SAH doesn't agree.
	};
	struct BVHNode
	{
		// Double precision 'traditional' BVH node layout.
		// Compared to the default BVHNode, child node indices and triangle indices
		// are also expanded to 64bit values to support massive scenes.
		bvhdbl3 aabbMin, aabbMax; // 2x24 bytes
		uint64_t leftFirst; // 8 bytes
		uint64_t triCount; // 8 bytes, total: 64 bytes
		bool isLeaf() const { return triCount > 0; /* empty BVH leaves do not exist */ }
		double Intersect( const RayEx& ray ) const;
		double SurfaceArea() const;
	};
	struct Fragment
	{
		// Double-precision version of the fragment sruct.
		bvhdbl3 bmin, bmax;			// AABB
		uint64_t primIdx;			// index of the original primitive
	};
	BVH_Double( BVHContext ctx = {} ) { context = ctx; }
	~BVH_Double();
	void Build( const bvhdbl3* vertices, const uint32_t primCount );
	double SAHCost( const uint64_t nodeIdx = 0 ) const;
	int32_t Intersect( RayEx& ray ) const;
	bvhdbl3* verts = 0;				// pointer to input primitive array, double-precision, 3x24 bytes per tri.
	Fragment* fragment = 0;			// input primitive bounding boxes, double-precision.
	BVHNode* bvhNode = 0;			// BVH node, double precision format.
	uint64_t* triIdx = 0;			// primitive index array for double-precision bvh.
	BuildFlags buildFlag = NONE;	// hint to the builder: currently, NONE or FULLSPLIT.
};

#endif

class BVH_GPU : public BVHBase
{
public:
	struct BVHNode
	{
		// Alternative 64-byte BVH node layout, which specifies the bounds of
		// the children rather than the node itself. This layout is used by
		// Aila and Laine in their seminal GPU ray tracing paper.
		bvhvec3 lmin; uint32_t left;
		bvhvec3 lmax; uint32_t right;
		bvhvec3 rmin; uint32_t triCount;
		bvhvec3 rmax; uint32_t firstTri; // total: 64 bytes
		bool isLeaf() const { return triCount > 0; }
	};
	BVH_GPU( BVHContext ctx = {} ) { context = ctx; }
	BVH_GPU( const BVH& original ) { /* DEPRICATED */ ConvertFrom( original ); }
	~BVH_GPU();
	void Build( const bvhvec4* vertices, const uint32_t primCount );
	void Build( const bvhvec4slice& vertices );
	void ConvertFrom( const BVH& original );
	int32_t Intersect( Ray& ray ) const;
	bool IsOccluded( const Ray& ray ) const { FALLBACK_SHADOW_QUERY( ray ); }
	// BVH data
	BVHNode* bvhNode = 0;			// BVH node in Aila & Laine format.
	BVH bvh;						// BVH4 is created from BVH and uses its data.
	bool ownBVH = true;				// False when ConvertFrom receives an external bvh.
};

class BVH_SoA : public BVHBase
{
public:
	struct BVHNode
	{
		// Second alternative 64-byte BVH node layout, same as BVHAilaLaine but
		// with child AABBs stored in SoA order.
		SIMDVEC4 xxxx, yyyy, zzzz;
		uint32_t left, right, triCount, firstTri; // total: 64 bytes
		bool isLeaf() const { return triCount > 0; }
	};
	BVH_SoA( BVHContext ctx = {} ) { context = ctx; }
	BVH_SoA( const BVH& original ) { /* DEPRICATED */ ConvertFrom( original ); }
	~BVH_SoA();
	void Build( const bvhvec4* vertices, const uint32_t primCount );
	void Build( const bvhvec4slice& vertices );
	void ConvertFrom( const BVH& original );
	int32_t Intersect( Ray& ray ) const;
	bool IsOccluded( const Ray& ray ) const;
	// BVH data
	BVHNode* bvhNode = 0;			// BVH node in 'structure of arrays' format.
	BVH bvh;						// BVH_SoA is created from BVH and uses its data.
	bool ownBVH = true;				// False when ConvertFrom receives an external bvh.
};

class BVH_Verbose : public BVHBase
{
public:
	struct BVHNode
	{
		// This node layout has some extra data per node: It stores left and right
		// child node indices explicitly, and stores the index of the parent node.
		// This format exists primarily for the BVH optimizer.
		bvhvec3 aabbMin; uint32_t left;
		bvhvec3 aabbMax; uint32_t right;
		uint32_t triCount, firstTri, parent, dummy;
		bool isLeaf() const { return triCount > 0; }
	};
	BVH_Verbose( BVHContext ctx = {} ) { context = ctx; }
	BVH_Verbose( const BVH& original ) { /* DEPRECATED */ ConvertFrom( original ); }
	~BVH_Verbose() { AlignedFree( bvhNode ); }
	void ConvertFrom( const BVH& original );
	float SAHCost( const uint32_t nodeIdx = 0 ) const;
	int32_t NodeCount() const;
	int32_t PrimCount( const uint32_t nodeIdx = 0 ) const;
	void Refit( const uint32_t nodeIdx );
	void Compact();
	void SplitLeafs( const uint32_t maxPrims = 1 );
	void MergeLeafs();
	void Optimize( const uint32_t iterations );
private:
	void RefitUpVerbose( uint32_t nodeIdx );
	uint32_t FindBestNewPosition( const uint32_t Lid );
	void ReinsertNodeVerbose( const uint32_t Lid, const uint32_t Nid, const uint32_t origin );
	uint32_t CountSubtreeTris( const uint32_t nodeIdx, uint32_t* counters );
	void MergeSubtree( const uint32_t nodeIdx, uint32_t* newIdx, uint32_t& newIdxPtr );
public:
	// BVH data
	bvhvec4slice verts = {};		// pointer to input primitive array: 3x16 bytes per tri.
	Fragment* fragment = 0;			// input primitive bounding boxes, double-precision.
	uint32_t* triIdx = 0;			// primitive index array - pointer copied from original.
	BVHNode* bvhNode = 0;			// BVH node with additional info, for BVH optimizer.
};

class BVH4 : public BVHBase
{
public:
	struct BVHNode
	{
		// 4-wide (aka 'shallow') BVH layout.
		bvhvec3 aabbMin; uint32_t firstTri;
		bvhvec3 aabbMax; uint32_t triCount;
		uint32_t child[4];
		uint32_t childCount, dummy1, dummy2, dummy3; // dummies are for alignment.
		bool isLeaf() const { return triCount > 0; }
	};
	BVH4( BVHContext ctx = {} ) { context = ctx; }
	BVH4( const BVH& original ) { /* DEPRECATED */ ConvertFrom( original ); }
	~BVH4();
	void Build( const bvhvec4* vertices, const uint32_t primCount );
	void Build( const bvhvec4slice& vertices );
	void ConvertFrom( const BVH& original );
	int32_t Intersect( Ray& ray ) const;
	bool IsOccluded( const Ray& ray ) const { FALLBACK_SHADOW_QUERY( ray ); }
	// BVH data
	BVHNode* bvh4Node = 0;			// BVH node for 4-wide BVH.
	BVH bvh;						// BVH4 is created from BVH and uses its data.
	bool ownBVH = true;				// False when ConvertFrom receives an external bvh.
};

class BVH8 : public BVHBase
{
public:
	struct BVHNode
	{
		// 8-wide (aka 'shallow') BVH layout.
		bvhvec3 aabbMin; uint32_t firstTri;
		bvhvec3 aabbMax; uint32_t triCount;
		uint32_t child[8];
		uint32_t childCount, dummy1, dummy2, dummy3; // dummies are for alignment.
		bool isLeaf() const { return triCount > 0; }
	};
	BVH8( BVHContext ctx = {} ) { context = ctx; }
	BVH8( const BVH& original ) { /* DEPRECATED */ ConvertFrom( original ); }
	~BVH8();
	void Build( const bvhvec4* vertices, const uint32_t primCount );
	void Build( const bvhvec4slice& vertices );
	void ConvertFrom( const BVH& original );
	int32_t Intersect( Ray& ray ) const;
	bool IsOccluded( const Ray& ray ) const { FALLBACK_SHADOW_QUERY( ray ); }
	// Helpers
	void SplitBVH8Leaf( const uint32_t nodeIdx, const uint32_t maxPrims );
	// BVH8 data
public:
	BVHNode* bvh8Node = 0;			// BVH node for 8-wide BVH.
	BVH bvh;						// BVH8 is created from BVH and uses its data.
	bool ownBVH = true;				// False when ConvertFrom receives an external bvh.
};

class BVH4_GPU : public BVHBase
{
public:
	struct BVHNode
	{
		// 4-way BVH node, optimized for GPU rendering
		struct aabb8 { uint8_t xmin, ymin, zmin, xmax, ymax, zmax; }; // quantized
		bvhvec3 aabbMin; uint32_t c0Info;			// 16
		bvhvec3 aabbExt; uint32_t c1Info;			// 16
		aabb8 c0bounds, c1bounds; uint32_t c2Info;	// 16
		aabb8 c2bounds, c3bounds; uint32_t c3Info;	// 16; total: 64 bytes
		// childInfo, 32bit:
		// msb:        0=interior, 1=leaf
		// leaf:       16 bits: relative start of triangle data, 15 bits: triangle count.
		// interior:   31 bits: child node address, in float4s from BVH data start.
		// Triangle data: directly follows nodes with leaves. Per tri:
		// - bvhvec4 vert0, vert1, vert2
		// - uint vert0.w stores original triangle index.
		// We can make the node smaller by storing child nodes sequentially, but
		// there is no way we can shave off a full 16 bytes, unless aabbExt is stored
		// as chars as well, as in CWBVH.
	};
	BVH4_GPU( BVHContext ctx = {} ) { context = ctx; }
	BVH4_GPU( const BVH4& original ) { /* DEPRECATED */ ConvertFrom( bvh4 ); }
	~BVH4_GPU();
	void Build( const bvhvec4* vertices, const uint32_t primCount );
	void Build( const bvhvec4slice& vertices );
	void ConvertFrom( const BVH4& original );
	int32_t Intersect( Ray& ray ) const;
	bool IsOccluded( const Ray& ray ) const { FALLBACK_SHADOW_QUERY( ray ); }
	// BVH data
	bvhvec4* bvh4Data = 0;			// 64-byte 4-wide BVH node for efficient GPU rendering.
	uint32_t allocatedBlocks = 0;	// node data and triangles are stored in 16-byte blocks.
	uint32_t usedBlocks = 0;		// actually used storage.
	BVH4 bvh4;						// BVH4_CPU is created from BVH4 and uses its data.
	bool ownBVH4 = true;			// False when ConvertFrom receives an external bvh.
};

class BVH4_CPU : public BVHBase
{
public:
	struct BVHNode
	{
		// 4-way BVH node, optimized for CPU rendering.
		// Based on: "Faster Incoherent Ray Traversal Using 8-Wide AVX Instructions",
		// Áfra, 2013.
		SIMDVEC4 xmin4, ymin4, zmin4;
		SIMDVEC4 xmax4, ymax4, zmax4;
		uint32_t childFirst[4];
		uint32_t triCount[4];
	};
	BVH4_CPU( BVHContext ctx = {} ) { context = ctx; }
	BVH4_CPU( const BVH4& original ) { /* DEPRECATED */ ConvertFrom( bvh4 ); }
	~BVH4_CPU();
	void Build( const bvhvec4* vertices, const uint32_t primCount );
	void Build( const bvhvec4slice& vertices );
	void ConvertFrom( const BVH4& original );
	int32_t Intersect( Ray& ray ) const;
	bool IsOccluded( const Ray& ray ) const;
	// BVH data
	BVHNode* bvh4Node = 0;			// 128-byte 4-wide BVH node for efficient CPU rendering.
	bvhvec4* bvh4Tris = 0;			// triangle data for BVHNode4Alt2 nodes.
	BVH4 bvh4;						// BVH4_CPU is created from BVH4 and uses its data.
	bool ownBVH4 = true;			// False when ConvertFrom receives an external bvh4.
};

class BVH4_WiVe : public BVHBase
{
public:
	struct BVHNode
	{
		// 4-way BVH node, optimized for CPU rendering.
		// Based on: "Accelerated Single Ray Tracing for Wide Vector Units",
		// Fuetterling1 et al., 2017.
		union { SIMDVEC4 xmin4; float xmin[4]; };
		union { SIMDVEC4 xmax4; float xmax[4]; };
		union { SIMDVEC4 ymin4; float ymin[4]; };
		union { SIMDVEC4 ymax4; float ymax[4]; };
		union { SIMDVEC4 zmin4; float zmin[4]; };
		union { SIMDVEC4 zmax4; float zmax[4]; };
		// ORSTRec rec[4];
	};
	BVH4_WiVe( BVHContext ctx = {} ) { context = ctx; }
	~BVH4_WiVe() { AlignedFree( bvh4Node ); }
	BVH4_WiVe( const bvhvec4* vertices, const uint32_t primCount );
	BVH4_WiVe( const bvhvec4slice& vertices );
	int32_t Intersect( Ray& ray ) const;
	bool IsOccluded( const Ray& ray ) const;
	// BVH4 data
	bvhvec4slice verts = {};		// pointer to input primitive array: 3x16 bytes per tri.
	uint32_t* triIdx = 0;			// primitive index array - pointer copied from original.
	BVHNode* bvh4Node = 0;			// 128-byte 4-wide BVH node for efficient CPU rendering.
};

class BVH8_CWBVH : public BVHBase
{
public:
	BVH8_CWBVH( BVHContext ctx = {} ) { context = ctx; }
	BVH8_CWBVH( BVH8& original ) { /* DEPRECATED */ ConvertFrom( bvh8 ); }
	~BVH8_CWBVH();
	void Build( const bvhvec4* vertices, const uint32_t primCount );
	void Build( const bvhvec4slice& vertices );
	void ConvertFrom( BVH8& original ); // NOTE: Not const; this may change some nodes in the original.
	int32_t Intersect( Ray& ray ) const;
	bool IsOccluded( const Ray& ray ) const { FALLBACK_SHADOW_QUERY( ray ); }
	// BVH8 data
	bvhvec4* bvh8Data = 0;			// nodes in CWBVH format.
	bvhvec4* bvh8Tris = 0;			// triangle data for CWBVH nodes.
	uint32_t allocatedBlocks = 0;	// node data is stored in blocks of 16 byte.
	uint32_t usedBlocks = 0;		// actually used blocks.
	BVH8 bvh8;						// BVH8_CWBVH is created from BVH8 and uses its data.
	bool ownBVH8 = true;			// False when ConvertFrom receives an external bvh8.
};

// BLASInstance: A TLAS is built over BLAS instances, where a single BLAS can be
// used with multiple transforms, and multiple BLASses can be combined in a complex
// scene. The TLAS is built over the world-space AABBs of the BLAS root nodes.
class BLASInstance
{
public:
	BLASInstance( BVH* bvh ) : blas( bvh ) {}
	void Update();					// Update the world bounds based on the current transform.
	BVH* blas = 0;					// Bottom-level acceleration structure.
	bvhaabb worldBounds;			// World-space AABB over the transformed blas root node.
	float transform[16] = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 }; // identity
	bvhvec3 TransformPoint( const bvhvec3& v ) const;
	bvhvec3 TransformVector( const bvhvec3& v ) const;
};

} // namespace tinybvh

// ============================================================================
//
//        I M P L E M E N T A T I O N
//
// ============================================================================

#ifdef TINYBVH_IMPLEMENTATION

#include <assert.h>			// for assert
#ifdef _MSC_VER
#include <intrin.h>			// for __lzcnt
#endif

// We need quite a bit of type reinterpretation, so we'll 
// turn off the gcc warning here until the end of the file.
#ifdef __GNUC__
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wstrict-aliasing"
#endif

namespace tinybvh {

static uint32_t __bfind( uint32_t x ) // https://github.com/mackron/refcode/blob/master/lzcnt.c
{
#if defined(_MSC_VER) && !defined(__clang__)
	return 31 - __lzcnt( x );
#elif defined(__EMSCRIPTEN__)
	return 31 - __builtin_clz( x );
#elif defined(__GNUC__) || defined(__clang__)
#ifndef __APPLE__
	uint32_t r;
	__asm__ __volatile__( "lzcnt{l %1, %0| %0, %1}" : "=r"(r) : "r"(x) : "cc" );
	return 31 - r;
#else
	return 31 - __builtin_clz( x ); // TODO: unverified.
#endif
#endif
}

#ifndef TINYBVH_USE_CUSTOM_VECTOR_TYPES

bvhvec4::bvhvec4( const bvhvec3& a ) { x = a.x; y = a.y; z = a.z; w = 0; }
bvhvec4::bvhvec4( const bvhvec3& a, float b ) { x = a.x; y = a.y; z = a.z; w = b; }

#endif

bvhvec4slice::bvhvec4slice( const bvhvec4* data, uint32_t count, uint32_t stride ) :
	data{ reinterpret_cast<const int8_t*>(data) },
	count{ count }, stride{ stride } {}

const bvhvec4& bvhvec4slice::operator[]( size_t i ) const
{
#ifdef PARANOID
	FATAL_ERROR_IF( i >= count, "bvhvec4slice::[..], Reading outside slice." );
#endif
	return *reinterpret_cast<const bvhvec4*>(data + stride * i);
}

void* BVHBase::AlignedAlloc( size_t size )
{
	return context.malloc ? context.malloc( size, context.userdata ) : nullptr;
}

void BVHBase::AlignedFree( void* ptr )
{
	if (context.free)
		context.free( ptr, context.userdata );
}

void BVHBase::CopyBasePropertiesFrom( const BVHBase& original )
{
	this->rebuildable = original.rebuildable;
	this->refittable = original.refittable;
	this->frag_min_flipped = original.frag_min_flipped;
	this->may_have_holes = original.may_have_holes;
	this->bvh_over_aabbs = original.bvh_over_aabbs;
	this->context = original.context;
	this->triCount = original.triCount;
	this->idxCount = original.idxCount;
}

void BLASInstance::Update()
{
	// transform the eight corners of the root node aabb using the instance
	// transform and calculate the worldspace aabb over these.
	worldBounds.minBounds = bvhvec3( BVH_FAR ), worldBounds.maxBounds = bvhvec3( -BVH_FAR );
	bvhvec3 bmin = blas->bvhNode[0].aabbMin, bmax = blas->bvhNode[0].aabbMax;
	for (int32_t i = 0; i < 8; i++)
	{
		const bvhvec3 p( i & 1 ? bmax.x : bmin.x, i & 2 ? bmax.y : bmin.y, i & 4 ? bmax.z : bmin.z );
		const bvhvec3 t = TransformPoint( p );
		worldBounds.minBounds = tinybvh_min( worldBounds.minBounds, t );
		worldBounds.maxBounds = tinybvh_max( worldBounds.maxBounds, t );
	}
}

// BVH implementation
// ----------------------------------------------------------------------------

BVH::~BVH()
{
	AlignedFree( bvhNode );
	AlignedFree( triIdx );
	AlignedFree( fragment );
}

void BVH::ConvertFrom( const BVH_Verbose& original )
{
	// allocate space
	const uint32_t spaceNeeded = original.usedNodes;
	if (allocatedNodes < spaceNeeded)
	{
		AlignedFree( bvhNode );
		bvhNode = (BVHNode*)AlignedAlloc( triCount * 2 * sizeof( BVHNode ) );
		allocatedNodes = spaceNeeded;
	}
	memset( bvhNode, 0, sizeof( BVHNode ) * spaceNeeded );
	CopyBasePropertiesFrom( original );
	this->verts = original.verts;
	this->triIdx = original.triIdx;
	// start conversion
	uint32_t srcNodeIdx = 0, dstNodeIdx = 0, newNodePtr = 2;
	uint32_t srcStack[64], dstStack[64], stackPtr = 0;
	while (1)
	{
		const BVH_Verbose::BVHNode& orig = original.bvhNode[srcNodeIdx];
		bvhNode[dstNodeIdx].aabbMin = orig.aabbMin;
		bvhNode[dstNodeIdx].aabbMax = orig.aabbMax;
		if (orig.isLeaf())
		{
			bvhNode[dstNodeIdx].triCount = orig.triCount;
			bvhNode[dstNodeIdx].leftFirst = orig.firstTri;
			if (stackPtr == 0) break;
			srcNodeIdx = srcStack[--stackPtr];
			dstNodeIdx = dstStack[stackPtr];
		}
		else
		{
			bvhNode[dstNodeIdx].leftFirst = newNodePtr;
			uint32_t srcRightIdx = orig.right;
			srcNodeIdx = orig.left, dstNodeIdx = newNodePtr++;
			srcStack[stackPtr] = srcRightIdx;
			dstStack[stackPtr++] = newNodePtr++;
		}
	}
	usedNodes = original.usedNodes;
}

float BVH::SAHCost( const uint32_t nodeIdx ) const
{
	// Determine the SAH cost of the tree. This provides an indication
	// of the quality of the BVH: Lower is better.
	const BVHNode& n = bvhNode[nodeIdx];
	if (n.isLeaf()) return C_INT * n.SurfaceArea() * n.triCount;
	float cost = C_TRAV * n.SurfaceArea() + SAHCost( n.leftFirst ) + SAHCost( n.leftFirst + 1 );
	return nodeIdx == 0 ? (cost / n.SurfaceArea()) : cost;
}

int32_t BVH::PrimCount( const uint32_t nodeIdx ) const
{
	// Determine the total number of primitives / fragments in leaf nodes.
	const BVHNode& n = bvhNode[nodeIdx];
	return n.isLeaf() ? n.triCount : (PrimCount( n.leftFirst ) + PrimCount( n.leftFirst + 1 ));
}

// BVH builder entry point for arrays of aabbs.
void BVH::BuildTLAS( const bvhaabb* aabbs, const uint32_t aabbCount )
{
	// the aabb array must be cacheline aligned.
	FATAL_ERROR_IF( aabbCount == 0, "BVH::BuildTLAS( .. ), aabbCount == 0." );
	FATAL_ERROR_IF( ((long long)(void*)aabbs & 31) != 0, "BVH::Build( bvhaabb* ), array not cacheline aligned." );
	// take the array and process it
	fragment = (Fragment*)aabbs;
	triCount = aabbCount;
	// build the BVH
	Build( (bvhvec4*)0, aabbCount ); // TODO: for very large scenes, use BuildAVX. Mind fragment sign flip!
}

void BVH::BuildTLAS( const BLASInstance* bvhs, const uint32_t instCount )
{
	FATAL_ERROR_IF( instCount == 0, "BVH::BuildTLAS( .. ), instCount == 0." );
	if (!fragment) fragment = (Fragment*)AlignedAlloc( instCount );
	else FATAL_ERROR_IF( instCount != triCount, "BVH::BuildTLAS( .. ), blas count changed." );
	// copy relevant data from instance array
	triCount = instCount;
	for (uint32_t i = 0; i < instCount; i++)
		fragment[i].bmin = bvhs[i].worldBounds.minBounds, fragment[i].primIdx = i,
		fragment[i].bmax = bvhs[i].worldBounds.maxBounds, fragment[i].clipped = 0;
}

// Basic single-function BVH builder, using mid-point splits.
// This builder yields a correct BVH in little time, but the quality of the
// structure will be low. Use this only if build time is the bottleneck in
// your application (e.g., when you need to trace few rays).
void BVH::BuildQuick( const bvhvec4* vertices, const uint32_t primCount )
{
	// build the BVH with a continuous array of bvhvec4 vertices:
	// in this case, the stride for the slice is 16 bytes.
	BuildQuick( bvhvec4slice{ vertices, primCount * 3, sizeof( bvhvec4 ) } );
}
void BVH::BuildQuick( const bvhvec4slice& vertices )
{
	FATAL_ERROR_IF( vertices.count == 0, "BVH::BuildQuick( .. ), primCount == 0." );
	// allocate on first build
	const uint32_t primCount = vertices.count / 3;
	const uint32_t spaceNeeded = primCount * 2; // upper limit
	if (allocatedNodes < spaceNeeded)
	{
		AlignedFree( bvhNode );
		AlignedFree( triIdx );
		AlignedFree( fragment );
		bvhNode = (BVHNode*)AlignedAlloc( spaceNeeded * sizeof( BVHNode ) );
		allocatedNodes = spaceNeeded;
		memset( &bvhNode[1], 0, 32 );	// node 1 remains unused, for cache line alignment.
		triIdx = (uint32_t*)AlignedAlloc( primCount * sizeof( uint32_t ) );
		fragment = (Fragment*)AlignedAlloc( primCount * sizeof( Fragment ) );
	}
	else FATAL_ERROR_IF( !rebuildable, "BVH::BuildQuick( .. ), bvh not rebuildable." );
	verts = vertices; // note: we're not copying this data; don't delete.
	idxCount = triCount = primCount;
	// reset node pool
	uint32_t newNodePtr = 2;
	// assign all triangles to the root node
	BVHNode& root = bvhNode[0];
	root.leftFirst = 0, root.triCount = triCount, root.aabbMin = bvhvec3( BVH_FAR ), root.aabbMax = bvhvec3( -BVH_FAR );
	// initialize fragments and initialize root node bounds
	for (uint32_t i = 0; i < triCount; i++)
	{
		fragment[i].bmin = tinybvh_min( tinybvh_min( verts[i * 3], verts[i * 3 + 1] ), verts[i * 3 + 2] );
		fragment[i].bmax = tinybvh_max( tinybvh_max( verts[i * 3], verts[i * 3 + 1] ), verts[i * 3 + 2] );
		root.aabbMin = tinybvh_min( root.aabbMin, fragment[i].bmin );
		root.aabbMax = tinybvh_max( root.aabbMax, fragment[i].bmax ), triIdx[i] = i;
	}
	// subdivide recursively
	uint32_t task[256], taskCount = 0, nodeIdx = 0;
	while (1)
	{
		while (1)
		{
			BVHNode& node = bvhNode[nodeIdx];
			// in-place partition against midpoint on longest axis
			uint32_t j = node.leftFirst + node.triCount, src = node.leftFirst;
			bvhvec3 extent = node.aabbMax - node.aabbMin;
			uint32_t axis = 0;
			if (extent.y > extent.x && extent.y > extent.z) axis = 1;
			if (extent.z > extent.x && extent.z > extent.y) axis = 2;
			float splitPos = node.aabbMin[axis] + extent[axis] * 0.5f, centroid;
			bvhvec3 lbmin( BVH_FAR ), lbmax( -BVH_FAR ), rbmin( BVH_FAR ), rbmax( -BVH_FAR ), fmin, fmax;
			for (uint32_t fi, i = 0; i < node.triCount; i++)
			{
				fi = triIdx[src], fmin = fragment[fi].bmin, fmax = fragment[fi].bmax;
				centroid = (fmin[axis] + fmax[axis]) * 0.5f;
				if (centroid < splitPos)
					lbmin = tinybvh_min( lbmin, fmin ), lbmax = tinybvh_max( lbmax, fmax ), src++;
				else
				{
					rbmin = tinybvh_min( rbmin, fmin ), rbmax = tinybvh_max( rbmax, fmax );
					tinybvh_swap( triIdx[src], triIdx[--j] );
				}
			}
			// create child nodes
			const uint32_t leftCount = src - node.leftFirst, rightCount = node.triCount - leftCount;
			if (leftCount == 0 || rightCount == 0) break; // split did not work out.
			const int32_t lci = newNodePtr++, rci = newNodePtr++;
			bvhNode[lci].aabbMin = lbmin, bvhNode[lci].aabbMax = lbmax;
			bvhNode[lci].leftFirst = node.leftFirst, bvhNode[lci].triCount = leftCount;
			bvhNode[rci].aabbMin = rbmin, bvhNode[rci].aabbMax = rbmax;
			bvhNode[rci].leftFirst = j, bvhNode[rci].triCount = rightCount;
			node.leftFirst = lci, node.triCount = 0;
			// recurse
			task[taskCount++] = rci, nodeIdx = lci;
		}
		// fetch subdivision task from stack
		if (taskCount == 0) break; else nodeIdx = task[--taskCount];
	}
	// all done.
	refittable = true; // not using spatial splits: can refit this BVH
	frag_min_flipped = false; // did not use AVX for binning
	may_have_holes = false; // the reference builder produces a continuous list of nodes
	usedNodes = newNodePtr;
}

// Basic single-function binned-SAH-builder.
// This is the reference builder; it yields a decent tree suitable for ray
// tracing on the CPU. This code uses no SIMD instructions.
// Faster code, using SSE/AVX, is available for x64 CPUs.
// For GPU rendering: The resulting BVH should be converted to a more optimal
// format after construction, e.g. BVH::AILA_LAINE.
void BVH::Build( const bvhvec4* vertices, const uint32_t primCount )
{
	// build the BVH with a continuous array of bvhvec4 vertices:
	// in this case, the stride for the slice is 16 bytes.
	Build( bvhvec4slice{ vertices, primCount * 3, sizeof( bvhvec4 ) } );
}
void BVH::Build( const bvhvec4slice& vertices )
{
	FATAL_ERROR_IF( vertices.count == 0, "BVH::Build( .. ), primCount == 0." );
	// allocate on first build
	const uint32_t primCount = vertices.count / 3;
	const uint32_t spaceNeeded = primCount * 2; // upper limit
	if (allocatedNodes < spaceNeeded)
	{
		AlignedFree( bvhNode );
		AlignedFree( triIdx );
		AlignedFree( fragment );
		bvhNode = (BVHNode*)AlignedAlloc( spaceNeeded * sizeof( BVHNode ) );
		allocatedNodes = spaceNeeded;
		memset( &bvhNode[1], 0, 32 );	// node 1 remains unused, for cache line alignment.
		triIdx = (uint32_t*)AlignedAlloc( primCount * sizeof( uint32_t ) );
		if (vertices) fragment = (Fragment*)AlignedAlloc( primCount * sizeof( Fragment ) );
		else FATAL_ERROR_IF( fragment == 0, "BVH::Build( 0, .. ), not called from ::Build( aabb )." );
	}
	else FATAL_ERROR_IF( !rebuildable, "BVH::Build( .. ), bvh not rebuildable." );
	verts = vertices;
	idxCount = triCount = primCount;
	// reset node pool
	uint32_t newNodePtr = 2;
	// assign all triangles to the root node
	BVHNode& root = bvhNode[0];
	root.leftFirst = 0, root.triCount = triCount, root.aabbMin = bvhvec3( BVH_FAR ), root.aabbMax = bvhvec3( -BVH_FAR );
	// initialize fragments and initialize root node bounds
	if (verts)
	{
		// building a BVH over triangles specified as three 16-byte vertices each.
		for (uint32_t i = 0; i < triCount; i++)
		{
			const bvhvec4 v0 = verts[i * 3], v1 = verts[i * 3 + 1], v2 = verts[i * 3 + 2];
			const bvhvec4 fmin = tinybvh_min( v0, tinybvh_min( v1, v2 ) );
			const bvhvec4 fmax = tinybvh_max( v0, tinybvh_max( v1, v2 ) );
			fragment[i].bmin = fmin, fragment[i].bmax = fmax;
			root.aabbMin = tinybvh_min( root.aabbMin, fragment[i].bmin );
			root.aabbMax = tinybvh_max( root.aabbMax, fragment[i].bmax ), triIdx[i] = i;
		}
	}
	else
	{
		// we are building the BVH over aabbs we received from ::Build( tinyaabb* ): vertices == 0.
		for (uint32_t i = 0; i < triCount; i++)
		{
			root.aabbMin = tinybvh_min( root.aabbMin, fragment[i].bmin );
			root.aabbMax = tinybvh_max( root.aabbMax, fragment[i].bmax ), triIdx[i] = i; // here: aabb index.
		}
	}
	// subdivide recursively
	uint32_t task[256], taskCount = 0, nodeIdx = 0;
	bvhvec3 minDim = (root.aabbMax - root.aabbMin) * 1e-20f, bestLMin = 0, bestLMax = 0, bestRMin = 0, bestRMax = 0;
	while (1)
	{
		while (1)
		{
			BVHNode& node = bvhNode[nodeIdx];
			// find optimal object split
			bvhvec3 binMin[3][BVHBINS], binMax[3][BVHBINS];
			for (uint32_t a = 0; a < 3; a++) for (uint32_t i = 0; i < BVHBINS; i++) binMin[a][i] = BVH_FAR, binMax[a][i] = -BVH_FAR;
			uint32_t count[3][BVHBINS];
			memset( count, 0, BVHBINS * 3 * sizeof( uint32_t ) );
			const bvhvec3 rpd3 = bvhvec3( BVHBINS / (node.aabbMax - node.aabbMin) ), nmin3 = node.aabbMin;
			for (uint32_t i = 0; i < node.triCount; i++) // process all tris for x,y and z at once
			{
				const uint32_t fi = triIdx[node.leftFirst + i];
				bvhint3 bi = bvhint3( ((fragment[fi].bmin + fragment[fi].bmax) * 0.5f - nmin3) * rpd3 );
				bi.x = tinybvh_clamp( bi.x, 0, BVHBINS - 1 );
				bi.y = tinybvh_clamp( bi.y, 0, BVHBINS - 1 );
				bi.z = tinybvh_clamp( bi.z, 0, BVHBINS - 1 );
				binMin[0][bi.x] = tinybvh_min( binMin[0][bi.x], fragment[fi].bmin );
				binMax[0][bi.x] = tinybvh_max( binMax[0][bi.x], fragment[fi].bmax ), count[0][bi.x]++;
				binMin[1][bi.y] = tinybvh_min( binMin[1][bi.y], fragment[fi].bmin );
				binMax[1][bi.y] = tinybvh_max( binMax[1][bi.y], fragment[fi].bmax ), count[1][bi.y]++;
				binMin[2][bi.z] = tinybvh_min( binMin[2][bi.z], fragment[fi].bmin );
				binMax[2][bi.z] = tinybvh_max( binMax[2][bi.z], fragment[fi].bmax ), count[2][bi.z]++;
			}
			// calculate per-split totals
			float splitCost = BVH_FAR, rSAV = 1.0f / node.SurfaceArea();
			uint32_t bestAxis = 0, bestPos = 0;
			for (int32_t a = 0; a < 3; a++) if ((node.aabbMax[a] - node.aabbMin[a]) > minDim[a])
			{
				bvhvec3 lBMin[BVHBINS - 1], rBMin[BVHBINS - 1], l1 = BVH_FAR, l2 = -BVH_FAR;
				bvhvec3 lBMax[BVHBINS - 1], rBMax[BVHBINS - 1], r1 = BVH_FAR, r2 = -BVH_FAR;
				float ANL[BVHBINS - 1], ANR[BVHBINS - 1];
				for (uint32_t lN = 0, rN = 0, i = 0; i < BVHBINS - 1; i++)
				{
					lBMin[i] = l1 = tinybvh_min( l1, binMin[a][i] );
					rBMin[BVHBINS - 2 - i] = r1 = tinybvh_min( r1, binMin[a][BVHBINS - 1 - i] );
					lBMax[i] = l2 = tinybvh_max( l2, binMax[a][i] );
					rBMax[BVHBINS - 2 - i] = r2 = tinybvh_max( r2, binMax[a][BVHBINS - 1 - i] );
					lN += count[a][i], rN += count[a][BVHBINS - 1 - i];
					ANL[i] = lN == 0 ? BVH_FAR : ((l2 - l1).halfArea() * (float)lN);
					ANR[BVHBINS - 2 - i] = rN == 0 ? BVH_FAR : ((r2 - r1).halfArea() * (float)rN);
				}
				// evaluate bin totals to find best position for object split
				for (uint32_t i = 0; i < BVHBINS - 1; i++)
				{
					const float C = C_TRAV + rSAV * C_INT * (ANL[i] + ANR[i]);
					if (C < splitCost)
					{
						splitCost = C, bestAxis = a, bestPos = i;
						bestLMin = lBMin[i], bestRMin = rBMin[i], bestLMax = lBMax[i], bestRMax = rBMax[i];
					}
				}
			}
			float noSplitCost = (float)node.triCount * C_INT;
			if (splitCost >= noSplitCost) break; // not splitting is better.
			// in-place partition
			uint32_t j = node.leftFirst + node.triCount, src = node.leftFirst;
			const float rpd = rpd3.cell[bestAxis], nmin = nmin3.cell[bestAxis];
			for (uint32_t i = 0; i < node.triCount; i++)
			{
				const uint32_t fi = triIdx[src];
				int32_t bi = (uint32_t)(((fragment[fi].bmin[bestAxis] + fragment[fi].bmax[bestAxis]) * 0.5f - nmin) * rpd);
				bi = tinybvh_clamp( bi, 0, BVHBINS - 1 );
				if ((uint32_t)bi <= bestPos) src++; else tinybvh_swap( triIdx[src], triIdx[--j] );
			}
			// create child nodes
			uint32_t leftCount = src - node.leftFirst, rightCount = node.triCount - leftCount;
			if (leftCount == 0 || rightCount == 0) break; // should not happen.
			const int32_t lci = newNodePtr++, rci = newNodePtr++;
			bvhNode[lci].aabbMin = bestLMin, bvhNode[lci].aabbMax = bestLMax;
			bvhNode[lci].leftFirst = node.leftFirst, bvhNode[lci].triCount = leftCount;
			bvhNode[rci].aabbMin = bestRMin, bvhNode[rci].aabbMax = bestRMax;
			bvhNode[rci].leftFirst = j, bvhNode[rci].triCount = rightCount;
			node.leftFirst = lci, node.triCount = 0;
			// recurse
			task[taskCount++] = rci, nodeIdx = lci;
		}
		// fetch subdivision task from stack
		if (taskCount == 0) break; else nodeIdx = task[--taskCount];
	}
	// all done.
	refittable = true; // not using spatial splits: can refit this BVH
	frag_min_flipped = false; // did not use AVX for binning
	may_have_holes = false; // the reference builder produces a continuous list of nodes
	bvh_over_aabbs = (verts == 0); // bvh over aabbs is suitable as TLAS
	usedNodes = newNodePtr;
}

// SBVH builder.
// Besides the regular object splits used in the reference builder, the SBVH
// algorithm also considers spatial splits, where primitives may be cut in
// multiple parts. This increases primitive count but may reduce overlap of
// BVH nodes. The cost of each option is considered per split.
// For typical geometry, SBVH yields a tree that can be traversed 25% faster.
// This comes at greatly increased construction cost, making the SBVH
// primarily useful for static geometry.
void BVH::BuildHQ( const bvhvec4* vertices, const uint32_t primCount )
{
	BuildHQ( bvhvec4slice{ vertices, primCount * 3, sizeof( bvhvec4 ) } );
}
void BVH::BuildHQ( const bvhvec4slice& vertices )
{
	FATAL_ERROR_IF( vertices.count == 0, "BVH::BuildHQ( .. ), primCount == 0." );
	// allocate on first build
	const uint32_t primCount = vertices.count / 3;
	const uint32_t slack = primCount >> 2; // for split prims
	const uint32_t spaceNeeded = primCount * 3;
	if (allocatedNodes < spaceNeeded)
	{
		AlignedFree( bvhNode );
		AlignedFree( triIdx );
		AlignedFree( fragment );
		bvhNode = (BVHNode*)AlignedAlloc( spaceNeeded * sizeof( BVHNode ) );
		allocatedNodes = spaceNeeded;
		memset( &bvhNode[1], 0, 32 );	// node 1 remains unused, for cache line alignment.
		triIdx = (uint32_t*)AlignedAlloc( (primCount + slack) * sizeof( uint32_t ) );
		fragment = (Fragment*)AlignedAlloc( (primCount + slack) * sizeof( Fragment ) );
	}
	else FATAL_ERROR_IF( !rebuildable, "BVH::BuildHQ( .. ), bvh not rebuildable." );
	verts = vertices; // note: we're not copying this data; don't delete.
	idxCount = primCount + slack;
	triCount = primCount;
	uint32_t* triIdxA = triIdx, * triIdxB = new uint32_t[triCount + slack];
	memset( triIdxA, 0, (triCount + slack) * 4 );
	memset( triIdxB, 0, (triCount + slack) * 4 );
	// reset node pool
	uint32_t newNodePtr = 2, nextFrag = triCount;
	// assign all triangles to the root node
	BVHNode& root = bvhNode[0];
	root.leftFirst = 0, root.triCount = triCount, root.aabbMin = bvhvec3( BVH_FAR ), root.aabbMax = bvhvec3( -BVH_FAR );
	// initialize fragments and initialize root node bounds
	for (uint32_t i = 0; i < triCount; i++)
	{
		fragment[i].bmin = tinybvh_min( tinybvh_min( verts[i * 3], verts[i * 3 + 1] ), verts[i * 3 + 2] );
		fragment[i].bmax = tinybvh_max( tinybvh_max( verts[i * 3], verts[i * 3 + 1] ), verts[i * 3 + 2] );
		root.aabbMin = tinybvh_min( root.aabbMin, fragment[i].bmin );
		root.aabbMax = tinybvh_max( root.aabbMax, fragment[i].bmax ), triIdx[i] = i, fragment[i].primIdx = i;
	}
	const float rootArea = (root.aabbMax - root.aabbMin).halfArea();
	// subdivide recursively
	struct Task { uint32_t node, sliceStart, sliceEnd, dummy; };
	ALIGNED( 64 ) Task task[256];
	uint32_t taskCount = 0, nodeIdx = 0, sliceStart = 0, sliceEnd = triCount + slack;
	const bvhvec3 minDim = (root.aabbMax - root.aabbMin) * 1e-7f /* don't touch, carefully picked */;
	bvhvec3 bestLMin = 0, bestLMax = 0, bestRMin = 0, bestRMax = 0;
	while (1)
	{
		while (1)
		{
			BVHNode& node = bvhNode[nodeIdx];
			// find optimal object split
			bvhvec3 binMin[3][BVHBINS], binMax[3][BVHBINS];
			for (uint32_t a = 0; a < 3; a++) for (uint32_t i = 0; i < BVHBINS; i++) binMin[a][i] = BVH_FAR, binMax[a][i] = -BVH_FAR;
			uint32_t count[3][BVHBINS];
			memset( count, 0, BVHBINS * 3 * sizeof( uint32_t ) );
			const bvhvec3 rpd3 = bvhvec3( BVHBINS / (node.aabbMax - node.aabbMin) ), nmin3 = node.aabbMin;
			for (uint32_t i = 0; i < node.triCount; i++) // process all tris for x,y and z at once
			{
				const uint32_t fi = triIdx[node.leftFirst + i];
				bvhint3 bi = bvhint3( ((fragment[fi].bmin + fragment[fi].bmax) * 0.5f - nmin3) * rpd3 );
				bi.x = tinybvh_clamp( bi.x, 0, BVHBINS - 1 );
				bi.y = tinybvh_clamp( bi.y, 0, BVHBINS - 1 );
				bi.z = tinybvh_clamp( bi.z, 0, BVHBINS - 1 );
				binMin[0][bi.x] = tinybvh_min( binMin[0][bi.x], fragment[fi].bmin );
				binMax[0][bi.x] = tinybvh_max( binMax[0][bi.x], fragment[fi].bmax ), count[0][bi.x]++;
				binMin[1][bi.y] = tinybvh_min( binMin[1][bi.y], fragment[fi].bmin );
				binMax[1][bi.y] = tinybvh_max( binMax[1][bi.y], fragment[fi].bmax ), count[1][bi.y]++;
				binMin[2][bi.z] = tinybvh_min( binMin[2][bi.z], fragment[fi].bmin );
				binMax[2][bi.z] = tinybvh_max( binMax[2][bi.z], fragment[fi].bmax ), count[2][bi.z]++;
			}
			// calculate per-split totals
			float splitCost = BVH_FAR, rSAV = 1.0f / node.SurfaceArea();
			uint32_t bestAxis = 0, bestPos = 0;
			for (int32_t a = 0; a < 3; a++) if ((node.aabbMax[a] - node.aabbMin[a]) > minDim.cell[a])
			{
				bvhvec3 lBMin[BVHBINS - 1], rBMin[BVHBINS - 1], l1 = BVH_FAR, l2 = -BVH_FAR;
				bvhvec3 lBMax[BVHBINS - 1], rBMax[BVHBINS - 1], r1 = BVH_FAR, r2 = -BVH_FAR;
				float ANL[BVHBINS - 1], ANR[BVHBINS - 1];
				for (uint32_t lN = 0, rN = 0, i = 0; i < BVHBINS - 1; i++)
				{
					lBMin[i] = l1 = tinybvh_min( l1, binMin[a][i] );
					rBMin[BVHBINS - 2 - i] = r1 = tinybvh_min( r1, binMin[a][BVHBINS - 1 - i] );
					lBMax[i] = l2 = tinybvh_max( l2, binMax[a][i] );
					rBMax[BVHBINS - 2 - i] = r2 = tinybvh_max( r2, binMax[a][BVHBINS - 1 - i] );
					lN += count[a][i], rN += count[a][BVHBINS - 1 - i];
					ANL[i] = lN == 0 ? BVH_FAR : ((l2 - l1).halfArea() * (float)lN);
					ANR[BVHBINS - 2 - i] = rN == 0 ? BVH_FAR : ((r2 - r1).halfArea() * (float)rN);
				}
				// evaluate bin totals to find best position for object split
				for (uint32_t i = 0; i < BVHBINS - 1; i++)
				{
					const float C = C_TRAV + C_INT * rSAV * (ANL[i] + ANR[i]);
					if (C < splitCost)
					{
						splitCost = C, bestAxis = a, bestPos = i;
						bestLMin = lBMin[i], bestRMin = rBMin[i], bestLMax = lBMax[i], bestRMax = rBMax[i];
					}
				}
			}
			// consider a spatial split
			bool spatial = false;
			uint32_t NL[BVHBINS - 1], NR[BVHBINS - 1], budget = sliceEnd - sliceStart;
			bvhvec3 spatialUnion = bestLMax - bestRMin;
			float spatialOverlap = (spatialUnion.halfArea()) / rootArea;
			if (budget > node.triCount && splitCost < BVH_FAR && spatialOverlap > 1e-5f)
			{
				for (uint32_t a = 0; a < 3; a++) if ((node.aabbMax[a] - node.aabbMin[a]) > minDim.cell[a])
				{
					// setup bins
					bvhvec3 binMin[BVHBINS], binMax[BVHBINS];
					for (uint32_t i = 0; i < BVHBINS; i++) binMin[i] = BVH_FAR, binMax[i] = -BVH_FAR;
					uint32_t countIn[BVHBINS] = { 0 }, countOut[BVHBINS] = { 0 };
					// populate bins with clipped fragments
					const float planeDist = (node.aabbMax[a] - node.aabbMin[a]) / (BVHBINS * 0.9999f);
					const float rPlaneDist = 1.0f / planeDist, nodeMin = node.aabbMin[a];
					for (uint32_t i = 0; i < node.triCount; i++)
					{
						const uint32_t fragIdx = triIdxA[node.leftFirst + i];
						const int32_t bin1 = tinybvh_clamp( (int32_t)((fragment[fragIdx].bmin[a] - nodeMin) * rPlaneDist), 0, BVHBINS - 1 );
						const int32_t bin2 = tinybvh_clamp( (int32_t)((fragment[fragIdx].bmax[a] - nodeMin) * rPlaneDist), 0, BVHBINS - 1 );
						countIn[bin1]++, countOut[bin2]++;
						if (bin2 == bin1)
						{
							// fragment fits in a single bin
							binMin[bin1] = tinybvh_min( binMin[bin1], fragment[fragIdx].bmin );
							binMax[bin1] = tinybvh_max( binMax[bin1], fragment[fragIdx].bmax );
						}
						else for (int32_t j = bin1; j <= bin2; j++)
						{
							// clip fragment to each bin it overlaps
							bvhvec3 bmin = node.aabbMin, bmax = node.aabbMax;
							bmin[a] = nodeMin + planeDist * j;
							bmax[a] = j == 6 ? node.aabbMax[a] : (bmin[a] + planeDist);
							Fragment orig = fragment[fragIdx];
							Fragment tmpFrag;
							if (!ClipFrag( orig, tmpFrag, bmin, bmax, minDim )) continue;
							binMin[j] = tinybvh_min( binMin[j], tmpFrag.bmin );
							binMax[j] = tinybvh_max( binMax[j], tmpFrag.bmax );
						}
					}
					// evaluate split candidates
					bvhvec3 lBMin[BVHBINS - 1], rBMin[BVHBINS - 1], l1 = BVH_FAR, l2 = -BVH_FAR;
					bvhvec3 lBMax[BVHBINS - 1], rBMax[BVHBINS - 1], r1 = BVH_FAR, r2 = -BVH_FAR;
					float ANL[BVHBINS], ANR[BVHBINS];
					for (uint32_t lN = 0, rN = 0, i = 0; i < BVHBINS - 1; i++)
					{
						lBMin[i] = l1 = tinybvh_min( l1, binMin[i] ), rBMin[BVHBINS - 2 - i] = r1 = tinybvh_min( r1, binMin[BVHBINS - 1 - i] );
						lBMax[i] = l2 = tinybvh_max( l2, binMax[i] ), rBMax[BVHBINS - 2 - i] = r2 = tinybvh_max( r2, binMax[BVHBINS - 1 - i] );
						lN += countIn[i], rN += countOut[BVHBINS - 1 - i], NL[i] = lN, NR[BVHBINS - 2 - i] = rN;
						ANL[i] = lN == 0 ? BVH_FAR : ((l2 - l1).halfArea() * (float)lN);
						ANR[BVHBINS - 2 - i] = rN == 0 ? BVH_FAR : ((r2 - r1).halfArea() * (float)rN);
					}
					// find best position for spatial split
					for (uint32_t i = 0; i < BVHBINS - 1; i++)
					{
						const float Cspatial = C_TRAV + C_INT * rSAV * (ANL[i] + ANR[i]);
						if (Cspatial < splitCost && NL[i] + NR[i] < budget)
						{
							spatial = true, splitCost = Cspatial, bestAxis = a, bestPos = i;
							bestLMin = lBMin[i], bestLMax = lBMax[i], bestRMin = rBMin[i], bestRMax = rBMax[i];
							bestLMax[a] = bestRMin[a]; // accurate
						}
					}
				}
			}
			// terminate recursion
			float noSplitCost = (float)node.triCount * C_INT;
			if (splitCost >= noSplitCost) break; // not splitting is better.
			// double-buffered partition
			uint32_t A = sliceStart, B = sliceEnd, src = node.leftFirst;
			if (spatial)
			{
				const float planeDist = (node.aabbMax[bestAxis] - node.aabbMin[bestAxis]) / (BVHBINS * 0.9999f);
				const float rPlaneDist = 1.0f / planeDist, nodeMin = node.aabbMin[bestAxis];
				for (uint32_t i = 0; i < node.triCount; i++)
				{
					const uint32_t fragIdx = triIdxA[src++];
					const uint32_t bin1 = (uint32_t)((fragment[fragIdx].bmin[bestAxis] - nodeMin) * rPlaneDist);
					const uint32_t bin2 = (uint32_t)((fragment[fragIdx].bmax[bestAxis] - nodeMin) * rPlaneDist);
					if (bin2 <= bestPos) triIdxB[A++] = fragIdx; else if (bin1 > bestPos) triIdxB[--B] = fragIdx; else
					{
						// split straddler
						Fragment tmpFrag = fragment[fragIdx];
						Fragment newFrag;
						if (ClipFrag( tmpFrag, newFrag, tinybvh_max( bestRMin, node.aabbMin ), tinybvh_min( bestRMax, node.aabbMax ), minDim ))
							fragment[nextFrag] = newFrag, triIdxB[--B] = nextFrag++;
						if (ClipFrag( tmpFrag, fragment[fragIdx], tinybvh_max( bestLMin, node.aabbMin ), tinybvh_min( bestLMax, node.aabbMax ), minDim ))
							triIdxB[A++] = fragIdx;
					}
				}
			}
			else
			{
				// object partitioning
				const float rpd = rpd3.cell[bestAxis], nmin = nmin3.cell[bestAxis];
				for (uint32_t i = 0; i < node.triCount; i++)
				{
					const uint32_t fr = triIdx[src + i];
					int32_t bi = (int32_t)(((fragment[fr].bmin[bestAxis] + fragment[fr].bmax[bestAxis]) * 0.5f - nmin) * rpd);
					bi = tinybvh_clamp( bi, 0, BVHBINS - 1 );
					if (bi <= (int32_t)bestPos) triIdxB[A++] = fr; else triIdxB[--B] = fr;
				}
			}
			// copy back slice data
			memcpy( triIdxA + sliceStart, triIdxB + sliceStart, (sliceEnd - sliceStart) * 4 );
			// create child nodes
			uint32_t leftCount = A - sliceStart, rightCount = sliceEnd - B;
			if (leftCount == 0 || rightCount == 0) break;
			int32_t leftChildIdx = newNodePtr++, rightChildIdx = newNodePtr++;
			bvhNode[leftChildIdx].aabbMin = bestLMin, bvhNode[leftChildIdx].aabbMax = bestLMax;
			bvhNode[leftChildIdx].leftFirst = sliceStart, bvhNode[leftChildIdx].triCount = leftCount;
			bvhNode[rightChildIdx].aabbMin = bestRMin, bvhNode[rightChildIdx].aabbMax = bestRMax;
			bvhNode[rightChildIdx].leftFirst = B, bvhNode[rightChildIdx].triCount = rightCount;
			node.leftFirst = leftChildIdx, node.triCount = 0;
			// recurse
			task[taskCount].node = rightChildIdx;
			task[taskCount].sliceEnd = sliceEnd;
			task[taskCount++].sliceStart = sliceEnd = (A + B) >> 1;
			nodeIdx = leftChildIdx;
		}
		// fetch subdivision task from stack
		if (taskCount == 0) break; else
			nodeIdx = task[--taskCount].node,
			sliceStart = task[taskCount].sliceStart,
			sliceEnd = task[taskCount].sliceEnd;
	}
	// clean up
	for (uint32_t i = 0; i < triCount + slack; i++) triIdx[i] = fragment[triIdx[i]].primIdx;
	// Compact(); - TODO
	// all done.
	refittable = false; // can't refit an SBVH
	frag_min_flipped = false; // did not use AVX for binning
	may_have_holes = false; // there may be holes in the index list, but not in the node list
	usedNodes = newNodePtr;
}

// Refitting: For animated meshes, where the topology remains intact. This
// includes trees waving in the wind, or subsequent frames for skinned
// animations. Repeated refitting tends to lead to deteriorated BVHs and
// slower ray tracing. Rebuild when this happens.
void BVH::Refit( const uint32_t nodeIdx )
{
	FATAL_ERROR_IF( !refittable, "BVH::Refit( .. ), refitting an SBVH." );
	FATAL_ERROR_IF( bvhNode == 0, "BVH::Refit( WALD_32BYTE ), bvhNode == 0." );
	FATAL_ERROR_IF( may_have_holes, "BVH::Refit( WALD_32BYTE ), bvh may have holes." );
	for (int32_t i = usedNodes - 1; i >= 0; i--)
	{
		BVHNode& node = bvhNode[i];
		if (node.isLeaf()) // leaf: adjust to current triangle vertex positions
		{
			bvhvec4 aabbMin( BVH_FAR ), aabbMax( -BVH_FAR );
			for (uint32_t first = node.leftFirst, j = 0; j < node.triCount; j++)
			{
				const uint32_t vertIdx = triIdx[first + j] * 3;
				aabbMin = tinybvh_min( aabbMin, verts[vertIdx] ), aabbMax = tinybvh_max( aabbMax, verts[vertIdx] );
				aabbMin = tinybvh_min( aabbMin, verts[vertIdx + 1] ), aabbMax = tinybvh_max( aabbMax, verts[vertIdx + 1] );
				aabbMin = tinybvh_min( aabbMin, verts[vertIdx + 2] ), aabbMax = tinybvh_max( aabbMax, verts[vertIdx + 2] );
			}
			node.aabbMin = aabbMin, node.aabbMax = aabbMax;
			continue;
		}
		// interior node: adjust to child bounds
		const BVHNode& left = bvhNode[node.leftFirst], & right = bvhNode[node.leftFirst + 1];
		node.aabbMin = tinybvh_min( left.aabbMin, right.aabbMin );
		node.aabbMax = tinybvh_max( left.aabbMax, right.aabbMax );
	}
}

int32_t BVH::Intersect( Ray& ray ) const
{
	BVHNode* node = &bvhNode[0], * stack[64];
	uint32_t stackPtr = 0, steps = 0;
	while (1)
	{
		steps++;
		if (node->isLeaf())
		{
			for (uint32_t i = 0; i < node->triCount; i++) IntersectTri( ray, verts, triIdx[node->leftFirst + i] );
			if (stackPtr == 0) break; else node = stack[--stackPtr];
			continue;
		}
		BVHNode* child1 = &bvhNode[node->leftFirst];
		BVHNode* child2 = &bvhNode[node->leftFirst + 1];
		float dist1 = child1->Intersect( ray ), dist2 = child2->Intersect( ray );
		if (dist1 > dist2) { tinybvh_swap( dist1, dist2 ); tinybvh_swap( child1, child2 ); }
		if (dist1 == BVH_FAR /* missed both child nodes */)
		{
			if (stackPtr == 0) break; else node = stack[--stackPtr];
		}
		else /* hit at least one node */
		{
			node = child1; /* continue with the nearest */
			if (dist2 != BVH_FAR) stack[stackPtr++] = child2; /* push far child */
		}
	}
	return steps;
}

bool BVH::IsOccluded( const Ray& ray ) const
{
	BVHNode* node = &bvhNode[0], * stack[64];
	uint32_t stackPtr = 0;
	while (1)
	{
		if (node->isLeaf())
		{
			for (uint32_t i = 0; i < node->triCount; i++)
			{
				// Moeller-Trumbore ray/triangle intersection algorithm
				const uint32_t vertIdx = triIdx[node->leftFirst + i] * 3;
				const bvhvec3 edge1 = verts[vertIdx + 1] - verts[vertIdx];
				const bvhvec3 edge2 = verts[vertIdx + 2] - verts[vertIdx];
				const bvhvec3 h = cross( ray.D, edge2 );
				const float a = dot( edge1, h );
				if (fabs( a ) < 0.0000001f) continue; // ray parallel to triangle
				const float f = 1 / a;
				const bvhvec3 s = ray.O - bvhvec3( verts[vertIdx] );
				const float u = f * dot( s, h );
				if (u < 0 || u > 1) continue;
				const bvhvec3 q = cross( s, edge1 );
				const float v = f * dot( ray.D, q );
				if (v < 0 || u + v > 1) continue;
				const float t = f * dot( edge2, q );
				if (t > 0 && t < ray.hit.t) return true; // no need to look further
			}
			if (stackPtr == 0) break; else node = stack[--stackPtr];
			continue;
		}
		BVHNode* child1 = &bvhNode[node->leftFirst];
		BVHNode* child2 = &bvhNode[node->leftFirst + 1];
		float dist1 = child1->Intersect( ray ), dist2 = child2->Intersect( ray );
		if (dist1 > dist2) { tinybvh_swap( dist1, dist2 ); tinybvh_swap( child1, child2 ); }
		if (dist1 == BVH_FAR /* missed both child nodes */)
		{
			if (stackPtr == 0) break; else node = stack[--stackPtr];
		}
		else /* hit at least one node */
		{
			node = child1; /* continue with the nearest */
			if (dist2 != BVH_FAR) stack[stackPtr++] = child2; /* push far child */
		}
	}
	return false;
}

// Intersect a WALD_32BYTE BVH with a ray packet.
// The 256 rays travel together to better utilize the caches and to amortize the cost
// of memory transfers over the rays in the bundle.
// Note that this basic implementation assumes a specific layout of the rays. Provided
// as 'proof of concept', should not be used in production code.
// Based on Large Ray Packets for Real-time Whitted Ray Tracing, Overbeck et al., 2008,
// extended with sorted traversal and reduced stack traffic.
void BVH::Intersect256Rays( Ray* packet ) const
{
	// convenience macro
#define CALC_TMIN_TMAX_WITH_SLABTEST_ON_RAY( r ) const bvhvec3 rD = packet[r].rD, t1 = o1 * rD, t2 = o2 * rD; \
	const float tmin = tinybvh_max( tinybvh_max( tinybvh_min( t1.x, t2.x ), tinybvh_min( t1.y, t2.y ) ), tinybvh_min( t1.z, t2.z ) ); \
	const float tmax = tinybvh_min( tinybvh_min( tinybvh_max( t1.x, t2.x ), tinybvh_max( t1.y, t2.y ) ), tinybvh_max( t1.z, t2.z ) );
	// Corner rays are: 0, 51, 204 and 255
	// Construct the bounding planes, with normals pointing outwards
	const bvhvec3 O = packet[0].O; // same for all rays in this case
	const bvhvec3 p0 = packet[0].O + packet[0].D; // top-left
	const bvhvec3 p1 = packet[51].O + packet[51].D; // top-right
	const bvhvec3 p2 = packet[204].O + packet[204].D; // bottom-left
	const bvhvec3 p3 = packet[255].O + packet[255].D; // bottom-right
	const bvhvec3 plane0 = normalize( cross( p0 - O, p0 - p2 ) ); // left plane
	const bvhvec3 plane1 = normalize( cross( p3 - O, p3 - p1 ) ); // right plane
	const bvhvec3 plane2 = normalize( cross( p1 - O, p1 - p0 ) ); // top plane
	const bvhvec3 plane3 = normalize( cross( p2 - O, p2 - p3 ) ); // bottom plane
	const int32_t sign0x = plane0.x < 0 ? 4 : 0, sign0y = plane0.y < 0 ? 5 : 1, sign0z = plane0.z < 0 ? 6 : 2;
	const int32_t sign1x = plane1.x < 0 ? 4 : 0, sign1y = plane1.y < 0 ? 5 : 1, sign1z = plane1.z < 0 ? 6 : 2;
	const int32_t sign2x = plane2.x < 0 ? 4 : 0, sign2y = plane2.y < 0 ? 5 : 1, sign2z = plane2.z < 0 ? 6 : 2;
	const int32_t sign3x = plane3.x < 0 ? 4 : 0, sign3y = plane3.y < 0 ? 5 : 1, sign3z = plane3.z < 0 ? 6 : 2;
	const float d0 = dot( O, plane0 ), d1 = dot( O, plane1 );
	const float d2 = dot( O, plane2 ), d3 = dot( O, plane3 );
	// Traverse the tree with the packet
	int32_t first = 0, last = 255; // first and last active ray in the packet
	const BVHNode* node = &bvhNode[0];
	ALIGNED( 64 ) uint32_t stack[64], stackPtr = 0;
	while (1)
	{
		if (node->isLeaf())
		{
			// handle leaf node
			for (uint32_t j = 0; j < node->triCount; j++)
			{
				const uint32_t idx = triIdx[node->leftFirst + j], vid = idx * 3;
				const bvhvec3 edge1 = verts[vid + 1] - verts[vid], edge2 = verts[vid + 2] - verts[vid];
				const bvhvec3 s = O - bvhvec3( verts[vid] );
				for (int32_t i = first; i <= last; i++)
				{
					Ray& ray = packet[i];
					const bvhvec3 h = cross( ray.D, edge2 );
					const float a = dot( edge1, h );
					if (fabs( a ) < 0.0000001f) continue; // ray parallel to triangle
					const float f = 1 / a, u = f * dot( s, h );
					if (u < 0 || u > 1) continue;
					const bvhvec3 q = cross( s, edge1 );
					const float v = f * dot( ray.D, q );
					if (v < 0 || u + v > 1) continue;
					const float t = f * dot( edge2, q );
					if (t <= 0 || t >= ray.hit.t) continue;
					ray.hit.t = t, ray.hit.u = u, ray.hit.v = v, ray.hit.prim = idx;
				}
			}
			if (stackPtr == 0) break; else // pop
				last = stack[--stackPtr], node = bvhNode + stack[--stackPtr],
				first = last >> 8, last &= 255;
		}
		else
		{
			// fetch pointers to child nodes
			const BVHNode* left = bvhNode + node->leftFirst;
			const BVHNode* right = bvhNode + node->leftFirst + 1;
			bool visitLeft = true, visitRight = true;
			int32_t leftFirst = first, leftLast = last, rightFirst = first, rightLast = last;
			float distLeft, distRight;
			{
				// see if we want to intersect the left child
				const bvhvec3 o1( left->aabbMin.x - O.x, left->aabbMin.y - O.y, left->aabbMin.z - O.z );
				const bvhvec3 o2( left->aabbMax.x - O.x, left->aabbMax.y - O.y, left->aabbMax.z - O.z );
				// 1. Early-in test: if first ray hits the node, the packet visits the node
				CALC_TMIN_TMAX_WITH_SLABTEST_ON_RAY( first );
				const bool earlyHit = (tmax >= tmin && tmin < packet[first].hit.t && tmax >= 0);
				distLeft = tmin;
				if (!earlyHit) // 2. Early-out test: if the node aabb is outside the four planes, we skip the node
				{
					float* minmax = (float*)left;
					bvhvec3 p0( minmax[sign0x], minmax[sign0y], minmax[sign0z] );
					bvhvec3 p1( minmax[sign1x], minmax[sign1y], minmax[sign1z] );
					bvhvec3 p2( minmax[sign2x], minmax[sign2y], minmax[sign2z] );
					bvhvec3 p3( minmax[sign3x], minmax[sign3y], minmax[sign3z] );
					if (dot( p0, plane0 ) > d0 || dot( p1, plane1 ) > d1 || dot( p2, plane2 ) > d2 || dot( p3, plane3 ) > d3)
						visitLeft = false;
					else // 3. Last resort: update first and last, stay in node if first > last
					{
						for (; leftFirst <= leftLast; leftFirst++)
						{
							CALC_TMIN_TMAX_WITH_SLABTEST_ON_RAY( leftFirst );
							if (tmax >= tmin && tmin < packet[leftFirst].hit.t && tmax >= 0) { distLeft = tmin; break; }
						}
						for (; leftLast >= leftFirst; leftLast--)
						{
							CALC_TMIN_TMAX_WITH_SLABTEST_ON_RAY( leftLast );
							if (tmax >= tmin && tmin < packet[leftLast].hit.t && tmax >= 0) break;
						}
						visitLeft = leftLast >= leftFirst;
					}
				}
			}
			{
				// see if we want to intersect the right child
				const bvhvec3 o1( right->aabbMin.x - O.x, right->aabbMin.y - O.y, right->aabbMin.z - O.z );
				const bvhvec3 o2( right->aabbMax.x - O.x, right->aabbMax.y - O.y, right->aabbMax.z - O.z );
				// 1. Early-in test: if first ray hits the node, the packet visits the node
				CALC_TMIN_TMAX_WITH_SLABTEST_ON_RAY( first );
				const bool earlyHit = (tmax >= tmin && tmin < packet[first].hit.t && tmax >= 0);
				distRight = tmin;
				if (!earlyHit) // 2. Early-out test: if the node aabb is outside the four planes, we skip the node
				{
					float* minmax = (float*)right;
					bvhvec3 p0( minmax[sign0x], minmax[sign0y], minmax[sign0z] );
					bvhvec3 p1( minmax[sign1x], minmax[sign1y], minmax[sign1z] );
					bvhvec3 p2( minmax[sign2x], minmax[sign2y], minmax[sign2z] );
					bvhvec3 p3( minmax[sign3x], minmax[sign3y], minmax[sign3z] );
					if (dot( p0, plane0 ) > d0 || dot( p1, plane1 ) > d1 || dot( p2, plane2 ) > d2 || dot( p3, plane3 ) > d3)
						visitRight = false;
					else // 3. Last resort: update first and last, stay in node if first > last
					{
						for (; rightFirst <= rightLast; rightFirst++)
						{
							CALC_TMIN_TMAX_WITH_SLABTEST_ON_RAY( rightFirst );
							if (tmax >= tmin && tmin < packet[rightFirst].hit.t && tmax >= 0) { distRight = tmin; break; }
						}
						for (; rightLast >= first; rightLast--)
						{
							CALC_TMIN_TMAX_WITH_SLABTEST_ON_RAY( rightLast );
							if (tmax >= tmin && tmin < packet[rightLast].hit.t && tmax >= 0) break;
						}
						visitRight = rightLast >= rightFirst;
					}
				}
			}
			// process intersection result
			if (visitLeft && visitRight)
			{
				if (distLeft < distRight) // push right, continue with left
				{
					stack[stackPtr++] = node->leftFirst + 1;
					stack[stackPtr++] = (rightFirst << 8) + rightLast;
					node = left, first = leftFirst, last = leftLast;
				}
				else // push left, continue with right
				{
					stack[stackPtr++] = node->leftFirst;
					stack[stackPtr++] = (leftFirst << 8) + leftLast;
					node = right, first = rightFirst, last = rightLast;
				}
			}
			else if (visitLeft) // continue with left
				node = left, first = leftFirst, last = leftLast;
			else if (visitRight) // continue with right
				node = right, first = rightFirst, last = rightLast;
			else if (stackPtr == 0) break; else // pop
				last = stack[--stackPtr], node = bvhNode + stack[--stackPtr],
				first = last >> 8, last &= 255;
		}
	}
}

int32_t BVH::NodeCount() const
{
	// Determine the number of nodes in the tree. Typically the result should
	// be usedNodes - 1 (second node is always unused), but some builders may
	// have unused nodes besides node 1. TODO: Support more layouts.
	uint32_t retVal = 0, nodeIdx = 0, stack[64], stackPtr = 0;
	while (1)
	{
		const BVHNode& n = bvhNode[nodeIdx];
		retVal++;
		if (n.isLeaf()) { if (stackPtr == 0) break; else nodeIdx = stack[--stackPtr]; }
		else nodeIdx = n.leftFirst, stack[stackPtr++] = n.leftFirst + 1;
	}
	return retVal;
}

// Compact: Reduce the size of a BVH by removing any unsed nodes.
// This is useful after an SBVH build or multi-threaded build, but also after
// calling MergeLeafs. Some operations, such as Optimize, *require* a
// compacted tree to work correctly.
void BVH::Compact()
{
	FATAL_ERROR_IF( bvhNode == 0, "BVH::Compact( WALD_32BYTE ), bvhNode == 0." );
	BVHNode* tmp = (BVHNode*)AlignedAlloc( sizeof( BVHNode ) * usedNodes );
	memcpy( tmp, bvhNode, 2 * sizeof( BVHNode ) );
	uint32_t newNodePtr = 2, nodeIdx = 0, stack[64], stackPtr = 0;
	while (1)
	{
		BVHNode& node = tmp[nodeIdx];
		const BVHNode& left = bvhNode[node.leftFirst];
		const BVHNode& right = bvhNode[node.leftFirst + 1];
		tmp[newNodePtr] = left, tmp[newNodePtr + 1] = right;
		const uint32_t todo1 = newNodePtr, todo2 = newNodePtr + 1;
		node.leftFirst = newNodePtr, newNodePtr += 2;
		if (!left.isLeaf()) stack[stackPtr++] = todo1;
		if (!right.isLeaf()) stack[stackPtr++] = todo2;
		if (!stackPtr) break;
		nodeIdx = stack[--stackPtr];
	}
	usedNodes = newNodePtr;
	AlignedFree( bvhNode );
	bvhNode = tmp;
}

// BVH8 implementation
// ----------------------------------------------------------------------------

BVH8::~BVH8() 
{
	if (!ownBVH) bvh = BVH(); // clear out pointers we don't own.
	AlignedFree( bvh8Node );
}

void BVH8::Build( const bvhvec4* vertices, const uint32_t primCount ) 
{ 
	Build( bvhvec4slice( vertices, primCount * 3, sizeof( bvhvec4 ) ) ); 
}
void BVH8::Build( const bvhvec4slice& vertices ) 
{ 
	bvh.context = context; // properly propagate context to fix issue #66.
	bvh.BuildDefault( vertices );
	ConvertFrom( bvh );
}

void BVH8::ConvertFrom( const BVH& original )
{
	// get a copy of the original
	if (&original != &bvh) ownBVH = false; // bvh isn't ours; don't delete in destructor. 
	bvh = original; 
	// allocate space
	// Note: The safe upper bound here is usedNodes when converting an existing
	// BVH2, but we need triCount * 2 to be safe in later conversions, e.g. to
	// CWBVH, which may further split some leaf nodes.
	const uint32_t spaceNeeded = original.triCount * 2;
	if (allocatedNodes < spaceNeeded)
	{
		AlignedFree( bvh8Node );
		bvh8Node = (BVHNode*)AlignedAlloc( spaceNeeded * sizeof( BVHNode ) );
		allocatedNodes = spaceNeeded;
	}
	memset( bvh8Node, 0, sizeof( BVHNode ) * spaceNeeded );
	CopyBasePropertiesFrom( original );
	// create an mbvh node for each bvh2 node
	for (uint32_t i = 0; i < original.usedNodes; i++) if (i != 1)
	{
		BVH::BVHNode& orig = original.bvhNode[i];
		BVHNode& node8 = bvh8Node[i];
		node8.aabbMin = orig.aabbMin, node8.aabbMax = orig.aabbMax;
		if (orig.isLeaf()) node8.triCount = orig.triCount, node8.firstTri = orig.leftFirst;
		else node8.child[0] = orig.leftFirst, node8.child[1] = orig.leftFirst + 1, node8.childCount = 2;
	}
	// collapse
	uint32_t stack[128], stackPtr = 1, nodeIdx = stack[0] = 0; // i.e., root node
	while (1)
	{
		BVHNode& node = bvh8Node[nodeIdx];
		while (node.childCount < 8)
		{
			int32_t bestChild = -1;
			float bestChildSA = 0;
			for (uint32_t i = 0; i < node.childCount; i++)
			{
				// see if we can adopt child i
				const BVHNode& child = bvh8Node[node.child[i]];
				if ((!child.isLeaf()) && (node.childCount - 1 + child.childCount) <= 8)
				{
					const float childSA = SA( child.aabbMin, child.aabbMax );
					if (childSA > bestChildSA) bestChild = i, bestChildSA = childSA;
				}
			}
			if (bestChild == -1) break; // could not adopt
			const BVHNode& child = bvh8Node[node.child[bestChild]];
			node.child[bestChild] = child.child[0];
			for (uint32_t i = 1; i < child.childCount; i++)
				node.child[node.childCount++] = child.child[i];
		}
		// we're done with the node; proceed with the children
		for (uint32_t i = 0; i < node.childCount; i++)
		{
			const uint32_t childIdx = node.child[i];
			const BVHNode& child = bvh8Node[childIdx];
			if (!child.isLeaf()) stack[stackPtr++] = childIdx;
		}
		if (stackPtr == 0) break;
		nodeIdx = stack[--stackPtr];
	}
	usedNodes = original.usedNodes; // there will be gaps / unused nodes though.
}

// SplitBVH8Leaf: CWBVH requires that a leaf has no more than 3 primitives,
// but regular BVH construction does not guarantee this. So, here we split
// busy leafs recursively in multiple leaves, until the requirement is met.
void BVH8::SplitBVH8Leaf( const uint32_t nodeIdx, const uint32_t maxPrims )
{
	float fragMinFix = frag_min_flipped ? -1.0f : 1.0f;
	const uint32_t* triIdx = bvh.triIdx;
	const Fragment* fragment = bvh.fragment;
	BVHNode& node = bvh8Node[nodeIdx];
	if (node.triCount <= maxPrims) return; // also catches interior nodes
	// place all primitives in a new node and make this the first child of 'node'
	BVHNode& firstChild = bvh8Node[node.child[0] = usedNodes++];
	firstChild.triCount = node.triCount;
	firstChild.firstTri = node.firstTri;
	uint32_t nextChild = 1;
	// share with new sibling nodes
	while (firstChild.triCount > maxPrims && nextChild < 8)
	{
		BVHNode& child = bvh8Node[node.child[nextChild] = usedNodes++];
		firstChild.triCount -= maxPrims, child.triCount = maxPrims;
		child.firstTri = firstChild.firstTri + firstChild.triCount;
		nextChild++;
	}
	for (uint32_t i = 0; i < nextChild; i++)
	{
		BVHNode& child = bvh8Node[node.child[i]];
		if (!refittable) child.aabbMin = node.aabbMin, child.aabbMax = node.aabbMax; else
		{
			// TODO: why is this producing wrong aabbs for SBVH?
			child.aabbMin = bvhvec3( BVH_FAR ), child.aabbMax = bvhvec3( -BVH_FAR );
			for (uint32_t fi, j = 0; j < child.triCount; j++) fi = triIdx[child.firstTri + j],
				child.aabbMin = tinybvh_min( child.aabbMin, fragment[fi].bmin * fragMinFix ),
				child.aabbMax = tinybvh_max( child.aabbMax, fragment[fi].bmax );
		}
	}
	node.triCount = 0;
	// recurse; should be rare
	if (firstChild.triCount > maxPrims) SplitBVH8Leaf( node.child[0], maxPrims );
}

int32_t BVH8::Intersect( Ray& ray ) const
{
	BVHNode* node = &bvh8Node[0], * stack[512];
	const bvhvec4slice& verts = bvh.verts;
	const uint32_t* triIdx = bvh.triIdx;
	uint32_t stackPtr = 0, steps = 0;
	while (1)
	{
		steps++;
		if (node->isLeaf()) for (uint32_t i = 0; i < node->triCount; i++)
			IntersectTri( ray, verts, triIdx[node->firstTri + i] );
		else for (uint32_t i = 0; i < 8; i++) if (node->child[i])
		{
			BVHNode* child = bvh8Node + node->child[i];
			float dist = IntersectAABB( ray, child->aabbMin, child->aabbMax );
			if (dist < BVH_FAR) stack[stackPtr++] = child;
		}
		if (stackPtr == 0) break; else node = stack[--stackPtr];
	}
	return steps;
}

// BVH8_CWBVH implementation
// ----------------------------------------------------------------------------

BVH8_CWBVH::~BVH8_CWBVH() 
{
	if (!ownBVH8) bvh8 = BVH8(); // clear out pointers we don't own.
	AlignedFree( bvh8Data );
	AlignedFree( bvh8Tris );
}

void BVH8_CWBVH::Build( const bvhvec4* vertices, const uint32_t primCount ) 
{ 
	Build( bvhvec4slice( vertices, primCount * 3, sizeof( bvhvec4 ) ) ); 
}
void BVH8_CWBVH::Build( const bvhvec4slice& vertices ) 
{ 
	bvh8.context = context; // properly propagate context to fix issue #66.
	bvh8.Build( vertices );
	ConvertFrom( bvh8 );
}

void BVH8_CWBVH::ConvertFrom( BVH8& original )
{
	// get a copy of the original bvh8
	if (&original != &bvh8) ownBVH8 = false; // bvh isn't ours; don't delete in destructor. 
	bvh8 = original; 
	// Convert a BVH8 to the format specified in: "Efficient Incoherent Ray
	// Traversal on GPUs Through Compressed Wide BVHs", Ylitie et al. 2017.
	// Adapted from code by "AlanWBFT".
	FATAL_ERROR_IF( bvh8.bvh8Node[0].isLeaf(), "BVH8_CWBVH::ConvertFrom( .. ), converting a single-node bvh." );
	// allocate memory
	// Note: This can be far lower (specifically: usedNodes) if we know that
	// none of the BVH8 leafs has more than three primitives.
	// Without this guarantee, the only safe upper limit is triCount * 2, since
	// we will be splitting fat BVH8 leafs to as we go.
	uint32_t spaceNeeded = bvh8.triCount * 2 * 5; // CWBVH nodes use 80 bytes each.
	if (spaceNeeded > allocatedBlocks)
	{
		bvh8Data = (bvhvec4*)AlignedAlloc( spaceNeeded * 16 );
		bvh8Tris = (bvhvec4*)AlignedAlloc( bvh8.idxCount * 4 * 16 );
		allocatedBlocks = spaceNeeded;
	}
	memset( bvh8Data, 0, spaceNeeded * 16 );
	memset( bvh8Tris, 0, bvh8.idxCount * 3 * 16 );
	CopyBasePropertiesFrom( bvh8 );
	BVH8::BVHNode* stackNodePtr[256];
	uint32_t stackNodeAddr[256], stackPtr = 1, nodeDataPtr = 5, triDataPtr = 0;
	stackNodePtr[0] = &bvh8.bvh8Node[0], stackNodeAddr[0] = 0;
	// start conversion
	while (stackPtr > 0)
	{
		BVH8::BVHNode* orig = stackNodePtr[--stackPtr];
		const int32_t currentNodeAddr = stackNodeAddr[stackPtr];
		bvhvec3 nodeLo = orig->aabbMin, nodeHi = orig->aabbMax;
		// greedy child node ordering
		const bvhvec3 nodeCentroid = (nodeLo + nodeHi) * 0.5f;
		float cost[8][8];
		int32_t assignment[8];
		bool isSlotEmpty[8];
		for (int32_t s = 0; s < 8; s++)
		{
			isSlotEmpty[s] = true, assignment[s] = -1;
			bvhvec3 ds(
				(((s >> 2) & 1) == 1) ? -1.0f : 1.0f,
				(((s >> 1) & 1) == 1) ? -1.0f : 1.0f,
				(((s >> 0) & 1) == 1) ? -1.0f : 1.0f
			);
			for (int32_t i = 0; i < 8; i++) if (orig->child[i] == 0) cost[s][i] = BVH_FAR; else
			{
				BVH8::BVHNode* const child = &bvh8.bvh8Node[orig->child[i]];
				if (child->triCount > 3 /* must be leaf */) bvh8.SplitBVH8Leaf( orig->child[i], 3 );
				bvhvec3 childCentroid = (child->aabbMin + child->aabbMax) * 0.5f;
				cost[s][i] = dot( childCentroid - nodeCentroid, ds );
			}
		}
		while (1)
		{
			float minCost = BVH_FAR;
			int32_t minEntryx = -1, minEntryy = -1;
			for (int32_t s = 0; s < 8; s++) for (int32_t i = 0; i < 8; i++)
				if (assignment[i] == -1 && isSlotEmpty[s] && cost[s][i] < minCost)
					minCost = cost[s][i], minEntryx = s, minEntryy = i;
			if (minEntryx == -1 && minEntryy == -1) break;
			isSlotEmpty[minEntryx] = false, assignment[minEntryy] = minEntryx;
		}
		for (int32_t i = 0; i < 8; i++) if (assignment[i] == -1) for (int32_t s = 0; s < 8; s++) if (isSlotEmpty[s])
		{
			isSlotEmpty[s] = false, assignment[i] = s;
			break;
		}
		const BVH8::BVHNode oldNode = *orig;
		for (int32_t i = 0; i < 8; i++) orig->child[assignment[i]] = oldNode.child[i];
		// calculate quantization parameters for each axis
		const int32_t ex = (int32_t)((int8_t)ceilf( log2f( (nodeHi.x - nodeLo.x) / 255.0f ) ));
		const int32_t ey = (int32_t)((int8_t)ceilf( log2f( (nodeHi.y - nodeLo.y) / 255.0f ) ));
		const int32_t ez = (int32_t)((int8_t)ceilf( log2f( (nodeHi.z - nodeLo.z) / 255.0f ) ));
		// encode output
		int32_t internalChildCount = 0, leafChildTriCount = 0, childBaseIndex = 0, triangleBaseIndex = 0;
		uint8_t imask = 0;
		for (int32_t i = 0; i < 8; i++)
		{
			if (orig->child[i] == 0) continue;
			BVH8::BVHNode* const child = &bvh8.bvh8Node[orig->child[i]];
			const int32_t qlox = (int32_t)floorf( (child->aabbMin.x - nodeLo.x) / powf( 2, (float)ex ) );
			const int32_t qloy = (int32_t)floorf( (child->aabbMin.y - nodeLo.y) / powf( 2, (float)ey ) );
			const int32_t qloz = (int32_t)floorf( (child->aabbMin.z - nodeLo.z) / powf( 2, (float)ez ) );
			const int32_t qhix = (int32_t)ceilf( (child->aabbMax.x - nodeLo.x) / powf( 2, (float)ex ) );
			const int32_t qhiy = (int32_t)ceilf( (child->aabbMax.y - nodeLo.y) / powf( 2, (float)ey ) );
			const int32_t qhiz = (int32_t)ceilf( (child->aabbMax.z - nodeLo.z) / powf( 2, (float)ez ) );
			uint8_t* const baseAddr = (uint8_t*)&bvh8Data[currentNodeAddr + 2];
			baseAddr[i + 0] = (uint8_t)qlox, baseAddr[i + 24] = (uint8_t)qhix;
			baseAddr[i + 8] = (uint8_t)qloy, baseAddr[i + 32] = (uint8_t)qhiy;
			baseAddr[i + 16] = (uint8_t)qloz, baseAddr[i + 40] = (uint8_t)qhiz;
			if (!child->isLeaf())
			{
				// interior node, set params and push onto stack
				const int32_t childNodeAddr = nodeDataPtr;
				if (internalChildCount++ == 0) childBaseIndex = childNodeAddr / 5;
				nodeDataPtr += 5, imask |= 1 << i;
				// set the meta field - This calculation assumes children are stored contiguously.
				uint8_t* const childMetaField = ((uint8_t*)&bvh8Data[currentNodeAddr + 1]) + 8;
				childMetaField[i] = (1 << 5) | (24 + (uint8_t)i); // I don't see how this accounts for empty children?
				stackNodePtr[stackPtr] = child, stackNodeAddr[stackPtr++] = childNodeAddr; // counted in float4s
				internalChildCount++;
				continue;
			}
			// leaf node
			const uint32_t tcount = tinybvh_min( child->triCount, 3u ); // TODO: ensure that's the case; clamping for now.
			if (leafChildTriCount == 0) triangleBaseIndex = triDataPtr;
			int32_t unaryEncodedTriCount = tcount == 1 ? 0b001 : tcount == 2 ? 0b011 : 0b111;
			// set the meta field - This calculation assumes children are stored contiguously.
			uint8_t* const childMetaField = ((uint8_t*)&bvh8Data[currentNodeAddr + 1]) + 8;
			childMetaField[i] = (uint8_t)((unaryEncodedTriCount << 5) | leafChildTriCount);
			leafChildTriCount += tcount;
			for (uint32_t j = 0; j < tcount; j++)
			{
				int32_t primitiveIndex = bvh8.bvh.triIdx[child->firstTri + j];
			#ifdef CWBVH_COMPRESSED_TRIS
				PrecomputeTriangle( verts, +primitiveIndex * 3, (float*)&bvh8Tris[triDataPtr] );
				bvh8Tris[triDataPtr + 3] = bvhvec4( 0, 0, 0, *(float*)&primitiveIndex );
				triDataPtr += 4;
			#else
				bvhvec4 t = bvh8.bvh.verts[primitiveIndex * 3 + 0];
				t.w = *(float*)&primitiveIndex;
				bvh8Tris[triDataPtr++] = t;
				bvh8Tris[triDataPtr++] = bvh8.bvh.verts[primitiveIndex * 3 + 1];
				bvh8Tris[triDataPtr++] = bvh8.bvh.verts[primitiveIndex * 3 + 2];
			#endif
			}
		}
		uint8_t exyzAndimask[4] = { *(uint8_t*)&ex, *(uint8_t*)&ey, *(uint8_t*)&ez, imask };
		bvh8Data[currentNodeAddr + 0] = bvhvec4( nodeLo, *(float*)&exyzAndimask );
		bvh8Data[currentNodeAddr + 1].x = *(float*)&childBaseIndex;
		bvh8Data[currentNodeAddr + 1].y = *(float*)&triangleBaseIndex;
	}
	usedBlocks = nodeDataPtr;
}

// Intersect_CWBVH:
// Intersect a compressed 8-wide BVH with a ray. For debugging only, not efficient.
// Not technically limited to BVH_USEAVX, but __lzcnt and __popcnt will require
// exotic compiler flags (in combination with __builtin_ia32_lzcnt_u32), so... Since
// this is just here to test data before it goes to the GPU: MSVC-only for now.
static uint32_t __popc( uint32_t x )
{
#if defined(_MSC_VER) && !defined(__clang__)
	return __popcnt( x );
#elif defined(__GNUC__) || defined(__clang__)
	return __builtin_popcount( x );
#endif
}

static uint32_t as_uint( const float v ) { return *(uint32_t*)&v; }

#define STACK_POP() { ngroup = traversalStack[--stackPtr]; }
#define STACK_PUSH() { traversalStack[stackPtr++] = ngroup; }
static inline uint32_t extract_byte( const uint32_t i, const uint32_t n ) { return (i >> (n * 8)) & 0xFF; }
static inline uint32_t sign_extend_s8x4( const uint32_t i )
{
	// asm("prmt.b32 %0, %1, 0x0, 0x0000BA98;" : "=r"(v) : "r"(i)); // BA98: 1011`1010`1001`1000
	// with the given parameters, prmt will extend the sign to all bits in a byte.
	uint32_t b0 = (i & 0b10000000000000000000000000000000) ? 0xff000000 : 0;
	uint32_t b1 = (i & 0b00000000100000000000000000000000) ? 0x00ff0000 : 0;
	uint32_t b2 = (i & 0b00000000000000001000000000000000) ? 0x0000ff00 : 0;
	uint32_t b3 = (i & 0b00000000000000000000000010000000) ? 0x000000ff : 0;
	return b0 + b1 + b2 + b3; // probably can do better than this.
}
int32_t BVH8_CWBVH::Intersect( Ray& ray ) const
{
	bvhuint2 traversalStack[128];
	uint32_t hitAddr = 0, stackPtr = 0;
	bvhvec2 triangleuv( 0, 0 );
	const bvhvec4* blasNodes = bvh8Data;
	const bvhvec4* blasTris = bvh8Tris;
	float tmin = 0, tmax = ray.hit.t;
	const uint32_t octinv = (7 - ((ray.D.x < 0 ? 4 : 0) | (ray.D.y < 0 ? 2 : 0) | (ray.D.z < 0 ? 1 : 0))) * 0x1010101;
	bvhuint2 ngroup = bvhuint2( 0, 0b10000000000000000000000000000000 ), tgroup = bvhuint2( 0 );
	do
	{
		if (ngroup.y > 0x00FFFFFF)
		{
			const uint32_t hits = ngroup.y, imask = ngroup.y;
			const uint32_t child_bit_index = __bfind( hits );
			const uint32_t child_node_base_index = ngroup.x;
			ngroup.y &= ~(1 << child_bit_index);
			if (ngroup.y > 0x00FFFFFF) { STACK_PUSH( /* nodeGroup */ ); }
			{
				const uint32_t slot_index = (child_bit_index - 24) ^ (octinv & 255);
				const uint32_t relative_index = __popc( imask & ~(0xFFFFFFFF << slot_index) );
				const uint32_t child_node_index = child_node_base_index + relative_index;
				const bvhvec4 n0 = blasNodes[child_node_index * 5 + 0], n1 = blasNodes[child_node_index * 5 + 1];
				const bvhvec4 n2 = blasNodes[child_node_index * 5 + 2], n3 = blasNodes[child_node_index * 5 + 3];
				const bvhvec4 n4 = blasNodes[child_node_index * 5 + 4], p = n0;
				bvhint3 e;
				e.x = (int32_t) * ((int8_t*)&n0.w + 0), e.y = (int32_t) * ((int8_t*)&n0.w + 1), e.z = (int32_t) * ((int8_t*)&n0.w + 2);
				ngroup.x = as_uint( n1.x ), tgroup.x = as_uint( n1.y ), tgroup.y = 0;
				uint32_t hitmask = 0;
				const uint32_t vx = (e.x + 127) << 23u; const float adjusted_idirx = *(float*)&vx * ray.rD.x;
				const uint32_t vy = (e.y + 127) << 23u; const float adjusted_idiry = *(float*)&vy * ray.rD.y;
				const uint32_t vz = (e.z + 127) << 23u; const float adjusted_idirz = *(float*)&vz * ray.rD.z;
				const float origx = -(ray.O.x - p.x) * ray.rD.x;
				const float origy = -(ray.O.y - p.y) * ray.rD.y;
				const float origz = -(ray.O.z - p.z) * ray.rD.z;
				{	// First 4
					const uint32_t meta4 = *(uint32_t*)&n1.z, is_inner4 = (meta4 & (meta4 << 1)) & 0x10101010;
					const uint32_t inner_mask4 = sign_extend_s8x4( is_inner4 << 3 );
					const uint32_t bit_index4 = (meta4 ^ (octinv & inner_mask4)) & 0x1F1F1F1F;
					const uint32_t child_bits4 = (meta4 >> 5) & 0x07070707;
					uint32_t swizzledLox = (ray.rD.x < 0) ? *(uint32_t*)&n3.z : *(uint32_t*)&n2.x, swizzledHix = (ray.rD.x < 0) ? *(uint32_t*)&n2.x : *(uint32_t*)&n3.z;
					uint32_t swizzledLoy = (ray.rD.y < 0) ? *(uint32_t*)&n4.x : *(uint32_t*)&n2.z, swizzledHiy = (ray.rD.y < 0) ? *(uint32_t*)&n2.z : *(uint32_t*)&n4.x;
					uint32_t swizzledLoz = (ray.rD.z < 0) ? *(uint32_t*)&n4.z : *(uint32_t*)&n3.x, swizzledHiz = (ray.rD.z < 0) ? *(uint32_t*)&n3.x : *(uint32_t*)&n4.z;
					float tminx[4], tminy[4], tminz[4], tmaxx[4], tmaxy[4], tmaxz[4];
					tminx[0] = ((swizzledLox >> 0) & 0xFF) * adjusted_idirx + origx, tminx[1] = ((swizzledLox >> 8) & 0xFF) * adjusted_idirx + origx, tminx[2] = ((swizzledLox >> 16) & 0xFF) * adjusted_idirx + origx;
					tminx[3] = ((swizzledLox >> 24) & 0xFF) * adjusted_idirx + origx, tminy[0] = ((swizzledLoy >> 0) & 0xFF) * adjusted_idiry + origy, tminy[1] = ((swizzledLoy >> 8) & 0xFF) * adjusted_idiry + origy;
					tminy[2] = ((swizzledLoy >> 16) & 0xFF) * adjusted_idiry + origy, tminy[3] = ((swizzledLoy >> 24) & 0xFF) * adjusted_idiry + origy, tminz[0] = ((swizzledLoz >> 0) & 0xFF) * adjusted_idirz + origz;
					tminz[1] = ((swizzledLoz >> 8) & 0xFF) * adjusted_idirz + origz, tminz[2] = ((swizzledLoz >> 16) & 0xFF) * adjusted_idirz + origz, tminz[3] = ((swizzledLoz >> 24) & 0xFF) * adjusted_idirz + origz;
					tmaxx[0] = ((swizzledHix >> 0) & 0xFF) * adjusted_idirx + origx, tmaxx[1] = ((swizzledHix >> 8) & 0xFF) * adjusted_idirx + origx, tmaxx[2] = ((swizzledHix >> 16) & 0xFF) * adjusted_idirx + origx;
					tmaxx[3] = ((swizzledHix >> 24) & 0xFF) * adjusted_idirx + origx, tmaxy[0] = ((swizzledHiy >> 0) & 0xFF) * adjusted_idiry + origy, tmaxy[1] = ((swizzledHiy >> 8) & 0xFF) * adjusted_idiry + origy;
					tmaxy[2] = ((swizzledHiy >> 16) & 0xFF) * adjusted_idiry + origy, tmaxy[3] = ((swizzledHiy >> 24) & 0xFF) * adjusted_idiry + origy, tmaxz[0] = ((swizzledHiz >> 0) & 0xFF) * adjusted_idirz + origz;
					tmaxz[1] = ((swizzledHiz >> 8) & 0xFF) * adjusted_idirz + origz, tmaxz[2] = ((swizzledHiz >> 16) & 0xFF) * adjusted_idirz + origz, tmaxz[3] = ((swizzledHiz >> 24) & 0xFF) * adjusted_idirz + origz;
					for (int32_t i = 0; i < 4; i++)
					{
						// Use VMIN, VMAX to compute the slabs
						const float cmin = tinybvh_max( tinybvh_max( tinybvh_max( tminx[i], tminy[i] ), tminz[i] ), tmin );
						const float cmax = tinybvh_min( tinybvh_min( tinybvh_min( tmaxx[i], tmaxy[i] ), tmaxz[i] ), tmax );
						if (cmin <= cmax) hitmask |= extract_byte( child_bits4, i ) << extract_byte( bit_index4, i );
					}
				}
				{	// Second 4
					const uint32_t meta4 = *(uint32_t*)&n1.w, is_inner4 = (meta4 & (meta4 << 1)) & 0x10101010;
					const uint32_t inner_mask4 = sign_extend_s8x4( is_inner4 << 3 );
					const uint32_t bit_index4 = (meta4 ^ (octinv & inner_mask4)) & 0x1F1F1F1F;
					const uint32_t child_bits4 = (meta4 >> 5) & 0x07070707;
					uint32_t swizzledLox = (ray.rD.x < 0) ? *(uint32_t*)&n3.w : *(uint32_t*)&n2.y, swizzledHix = (ray.rD.x < 0) ? *(uint32_t*)&n2.y : *(uint32_t*)&n3.w;
					uint32_t swizzledLoy = (ray.rD.y < 0) ? *(uint32_t*)&n4.y : *(uint32_t*)&n2.w, swizzledHiy = (ray.rD.y < 0) ? *(uint32_t*)&n2.w : *(uint32_t*)&n4.y;
					uint32_t swizzledLoz = (ray.rD.z < 0) ? *(uint32_t*)&n4.w : *(uint32_t*)&n3.y, swizzledHiz = (ray.rD.z < 0) ? *(uint32_t*)&n3.y : *(uint32_t*)&n4.w;
					float tminx[4], tminy[4], tminz[4], tmaxx[4], tmaxy[4], tmaxz[4];
					tminx[0] = ((swizzledLox >> 0) & 0xFF) * adjusted_idirx + origx, tminx[1] = ((swizzledLox >> 8) & 0xFF) * adjusted_idirx + origx, tminx[2] = ((swizzledLox >> 16) & 0xFF) * adjusted_idirx + origx;
					tminx[3] = ((swizzledLox >> 24) & 0xFF) * adjusted_idirx + origx, tminy[0] = ((swizzledLoy >> 0) & 0xFF) * adjusted_idiry + origy, tminy[1] = ((swizzledLoy >> 8) & 0xFF) * adjusted_idiry + origy;
					tminy[2] = ((swizzledLoy >> 16) & 0xFF) * adjusted_idiry + origy, tminy[3] = ((swizzledLoy >> 24) & 0xFF) * adjusted_idiry + origy, tminz[0] = ((swizzledLoz >> 0) & 0xFF) * adjusted_idirz + origz;
					tminz[1] = ((swizzledLoz >> 8) & 0xFF) * adjusted_idirz + origz, tminz[2] = ((swizzledLoz >> 16) & 0xFF) * adjusted_idirz + origz, tminz[3] = ((swizzledLoz >> 24) & 0xFF) * adjusted_idirz + origz;
					tmaxx[0] = ((swizzledHix >> 0) & 0xFF) * adjusted_idirx + origx, tmaxx[1] = ((swizzledHix >> 8) & 0xFF) * adjusted_idirx + origx, tmaxx[2] = ((swizzledHix >> 16) & 0xFF) * adjusted_idirx + origx;
					tmaxx[3] = ((swizzledHix >> 24) & 0xFF) * adjusted_idirx + origx, tmaxy[0] = ((swizzledHiy >> 0) & 0xFF) * adjusted_idiry + origy, tmaxy[1] = ((swizzledHiy >> 8) & 0xFF) * adjusted_idiry + origy;
					tmaxy[2] = ((swizzledHiy >> 16) & 0xFF) * adjusted_idiry + origy, tmaxy[3] = ((swizzledHiy >> 24) & 0xFF) * adjusted_idiry + origy, tmaxz[0] = ((swizzledHiz >> 0) & 0xFF) * adjusted_idirz + origz;
					tmaxz[1] = ((swizzledHiz >> 8) & 0xFF) * adjusted_idirz + origz, tmaxz[2] = ((swizzledHiz >> 16) & 0xFF) * adjusted_idirz + origz, tmaxz[3] = ((swizzledHiz >> 24) & 0xFF) * adjusted_idirz + origz;
					for (int32_t i = 0; i < 4; i++)
					{
						const float cmin = tinybvh_max( tinybvh_max( tinybvh_max( tminx[i], tminy[i] ), tminz[i] ), tmin );
						const float cmax = tinybvh_min( tinybvh_min( tinybvh_min( tmaxx[i], tmaxy[i] ), tmaxz[i] ), tmax );
						if (cmin <= cmax) hitmask |= extract_byte( child_bits4, i ) << extract_byte( bit_index4, i );
					}
				}
				ngroup.y = (hitmask & 0xFF000000) | (as_uint( n0.w ) >> 24), tgroup.y = hitmask & 0x00FFFFFF;
			}
		}
		else tgroup = ngroup, ngroup = bvhuint2( 0 );
		while (tgroup.y != 0)
		{
			uint32_t triangleIndex = __bfind( tgroup.y );
		#ifdef CWBVH_COMPRESSED_TRIS
			const float* T = (float*)&blasTris[tgroup.x + triangleIndex * 4];
			const float transS = T[8] * ray.O.x + T[9] * ray.O.y + T[10] * ray.O.z + T[11];
			const float transD = T[8] * ray.D.x + T[9] * ray.D.y + T[10] * ray.D.z;
			const float ta = -transS / transD;
			if (ta > 0 && ta < ray.hit.t)
			{
				const bvhvec3 wr = ray.O + ta * ray.D;
				const float u = T[0] * wr.x + T[1] * wr.y + T[2] * wr.z + T[3];
				const float v = T[4] * wr.x + T[5] * wr.y + T[6] * wr.z + T[7];
				const bool hit = u >= 0 && v >= 0 && u + v < 1;
				if (hit) triangleuv = bvhvec2( u, v ), tmax = ta, hitAddr = *(uint32_t*)&T[15];
			}
		#else
			int32_t triAddr = tgroup.x + triangleIndex * 3;
			const bvhvec3 v0 = blasTris[triAddr];
			const bvhvec3 edge1 = bvhvec3( blasTris[triAddr + 1] ) - v0;
			const bvhvec3 edge2 = bvhvec3( blasTris[triAddr + 2] ) - v0;
			const bvhvec3 h = cross( ray.D, edge2 );
			const float a = dot( edge1, h );
			if (fabs( a ) > 0.0000001f)
			{
				const float f = 1 / a;
				const bvhvec3 s = ray.O - v0;
				const float u = f * dot( s, h );
				if (u >= 0 && u <= 1)
				{
					const bvhvec3 q = cross( s, edge1 );
					const float v = f * dot( ray.D, q );
					if (v >= 0 && u + v <= 1)
					{
						const float d = f * dot( edge2, q );
						if (d > 0.0f && d < tmax)
						{
							triangleuv = bvhvec2( u, v ), tmax = d;
							hitAddr = as_uint( blasTris[triAddr].w );
						}
					}
				}
			}
		#endif
			tgroup.y -= 1 << triangleIndex;
		}
		if (ngroup.y <= 0x00FFFFFF)
		{
			if (stackPtr > 0) { STACK_POP( /* nodeGroup */ ); }
			else
			{
				ray.hit.t = tmax;
				if (tmax < BVH_FAR)
					ray.hit.u = triangleuv.x, ray.hit.v = triangleuv.y;
				ray.hit.prim = hitAddr;
				break;
			}
		}
	} while (true);
	return 0;
}

// ============================================================================
//
//        H E L P E R S
//
// ============================================================================

// TransformPoint
bvhvec3 BLASInstance::TransformPoint( const bvhvec3& v ) const
{
	const bvhvec3 res(
		transform[0] * v.x + transform[1] * v.y + transform[2] * v.z + transform[3],
		transform[4] * v.x + transform[5] * v.y + transform[6] * v.z + transform[7],
		transform[8] * v.x + transform[9] * v.y + transform[10] * v.z + transform[11] );
	const float w = transform[12] * v.x + transform[13] * v.y + transform[14] * v.z + transform[15];
	if (w == 1) return res; else return res * (1.f / w);
}

// TransformVector - skips translation. Assumes orthonormal transform, for now.
bvhvec3 BLASInstance::TransformVector( const bvhvec3& v ) const
{
	return bvhvec3( transform[0] * v.x + transform[1] * v.y + transform[2] * v.z,
		transform[4] * v.x + transform[5] * v.y + transform[6] * v.z,
		transform[8] * v.x + transform[9] * v.y + transform[10] * v.z );
}

// SA
float BVHBase::SA( const bvhvec3& aabbMin, const bvhvec3& aabbMax )
{
	bvhvec3 e = aabbMax - aabbMin; // extent of the node
	return e.x * e.y + e.y * e.z + e.z * e.x;
}

// IntersectTri
void BVHBase::IntersectTri( Ray& ray, const bvhvec4slice& verts, const uint32_t idx ) const
{
	// Moeller-Trumbore ray/triangle intersection algorithm
	const uint32_t vertIdx = idx * 3;
	const bvhvec3 edge1 = verts[vertIdx + 1] - verts[vertIdx];
	const bvhvec3 edge2 = verts[vertIdx + 2] - verts[vertIdx];
	const bvhvec3 h = cross( ray.D, edge2 );
	const float a = dot( edge1, h );
	if (fabs( a ) < 0.0000001f) return; // ray parallel to triangle
	const float f = 1 / a;
	const bvhvec3 s = ray.O - bvhvec3( verts[vertIdx] );
	const float u = f * dot( s, h );
	if (u < 0 || u > 1) return;
	const bvhvec3 q = cross( s, edge1 );
	const float v = f * dot( ray.D, q );
	if (v < 0 || u + v > 1) return;
	const float t = f * dot( edge2, q );
	if (t > 0 && t < ray.hit.t)
	{
		// register a hit: ray is shortened to t
		ray.hit.t = t, ray.hit.u = u, ray.hit.v = v, ray.hit.prim = idx;
	}
}

// IntersectTri
bool BVHBase::TriOccludes( const Ray& ray, const bvhvec4slice& verts, const uint32_t idx ) const
{
	// Moeller-Trumbore ray/triangle intersection algorithm
	const uint32_t vertIdx = idx * 3;
	const bvhvec3 edge1 = verts[vertIdx + 1] - verts[vertIdx];
	const bvhvec3 edge2 = verts[vertIdx + 2] - verts[vertIdx];
	const bvhvec3 h = cross( ray.D, edge2 );
	const float a = dot( edge1, h );
	if (fabs( a ) < 0.0000001f) return false; // ray parallel to triangle
	const float f = 1 / a;
	const bvhvec3 s = ray.O - bvhvec3( verts[vertIdx] );
	const float u = f * dot( s, h );
	if (u < 0 || u > 1) return false;
	const bvhvec3 q = cross( s, edge1 );
	const float v = f * dot( ray.D, q );
	if (v < 0 || u + v > 1) return false;
	const float t = f * dot( edge2, q );
	return t > 0 && t < ray.hit.t;
}

// IntersectAABB
float BVHBase::IntersectAABB( const Ray& ray, const bvhvec3& aabbMin, const bvhvec3& aabbMax )
{
	// "slab test" ray/AABB intersection
	float tx1 = (aabbMin.x - ray.O.x) * ray.rD.x, tx2 = (aabbMax.x - ray.O.x) * ray.rD.x;
	float tmin = tinybvh_min( tx1, tx2 ), tmax = tinybvh_max( tx1, tx2 );
	float ty1 = (aabbMin.y - ray.O.y) * ray.rD.y, ty2 = (aabbMax.y - ray.O.y) * ray.rD.y;
	tmin = tinybvh_max( tmin, tinybvh_min( ty1, ty2 ) );
	tmax = tinybvh_min( tmax, tinybvh_max( ty1, ty2 ) );
	float tz1 = (aabbMin.z - ray.O.z) * ray.rD.z, tz2 = (aabbMax.z - ray.O.z) * ray.rD.z;
	tmin = tinybvh_max( tmin, tinybvh_min( tz1, tz2 ) );
	tmax = tinybvh_min( tmax, tinybvh_max( tz1, tz2 ) );
	if (tmax >= tmin && tmin < ray.hit.t && tmax >= 0) return tmin; else return BVH_FAR;
}

// PrecomputeTriangle (helper), transforms a triangle to the format used in:
// Fast Ray-Triangle Intersections by Coordinate Transformation. Baldwin & Weber, 2016.
void BVHBase::PrecomputeTriangle( const bvhvec4slice& vert, uint32_t triIndex, float* T )
{
	bvhvec3 v0 = vert[triIndex], v1 = vert[triIndex + 1], v2 = vert[triIndex + 2];
	bvhvec3 e1 = v1 - v0, e2 = v2 - v0, N = cross( e1, e2 );
	float x1, x2, n = dot( v0, N ), rN;
	if (fabs( N[0] ) > fabs( N[1] ) && fabs( N[0] ) > fabs( N[2] ))
	{
		x1 = v1.y * v0.z - v1.z * v0.y, x2 = v2.y * v0.z - v2.z * v0.y, rN = 1.0f / N.x;
		T[0] = 0, T[1] = e2.z * rN, T[2] = -e2.y * rN, T[3] = x2 * rN;
		T[4] = 0, T[5] = -e1.z * rN, T[6] = e1.y * rN, T[7] = -x1 * rN;
		T[8] = 1, T[9] = N.y * rN, T[10] = N.z * rN, T[11] = -n * rN;
	}
	else if (fabs( N.y ) > fabs( N.z ))
	{
		x1 = v1.z * v0.x - v1.x * v0.z, x2 = v2.z * v0.x - v2.x * v0.z, rN = 1.0f / N.y;
		T[0] = -e2.z * rN, T[1] = 0, T[2] = e2.x * rN, T[3] = x2 * rN;
		T[4] = e1.z * rN, T[5] = 0, T[6] = -e1.x * rN, T[7] = -x1 * rN;
		T[8] = N.x * rN, T[9] = 1, T[10] = N.z * rN, T[11] = -n * rN;
	}
	else if (fabs( N.z ) > 0)
	{
		x1 = v1.x * v0.y - v1.y * v0.x, x2 = v2.x * v0.y - v2.y * v0.x, rN = 1.0f / N.z;
		T[0] = e2.y * rN, T[1] = -e2.x * rN, T[2] = 0, T[3] = x2 * rN;
		T[4] = -e1.y * rN, T[5] = e1.x * rN, T[6] = 0, T[7] = -x1 * rN;
		T[8] = N.x * rN, T[9] = N.y * rN, T[10] = 1, T[11] = -n * rN;
	}
	else memset( T, 0, 12 * 4 ); // cerr << "degenerate source " << endl;
}

// ClipFrag (helper), clip a triangle against an AABB.
// Can probably be done a lot more efficiently. Used in SBVH construction.
bool BVH::ClipFrag( const Fragment& orig, Fragment& newFrag, bvhvec3 bmin, bvhvec3 bmax, bvhvec3 minDim )
{
	// find intersection of bmin/bmax and orig bmin/bmax
	bmin = tinybvh_max( bmin, orig.bmin );
	bmax = tinybvh_min( bmax, orig.bmax );
	const bvhvec3 extent = bmax - bmin;
	// Sutherland-Hodgeman against six bounding planes
	uint32_t Nin = 3, vidx = orig.primIdx * 3;
	bvhvec3 vin[10] = { verts[vidx], verts[vidx + 1], verts[vidx + 2] }, vout[10];
	for (uint32_t a = 0; a < 3; a++)
	{
		const float eps = minDim.cell[a];
		if (extent.cell[a] > eps)
		{
			uint32_t Nout = 0;
			const float l = bmin[a], r = bmax[a];
			for (uint32_t v = 0; v < Nin; v++)
			{
				bvhvec3 v0 = vin[v], v1 = vin[(v + 1) % Nin];
				const bool v0in = v0[a] >= l - eps, v1in = v1[a] >= l - eps;
				if (!(v0in || v1in)) continue; else if (v0in != v1in)
				{
					bvhvec3 C = v0 + (l - v0[a]) / (v1[a] - v0[a]) * (v1 - v0);
					C[a] = l /* accurate */, vout[Nout++] = C;
				}
				if (v1in) vout[Nout++] = v1;
			}
			Nin = 0;
			for (uint32_t v = 0; v < Nout; v++)
			{
				bvhvec3 v0 = vout[v], v1 = vout[(v + 1) % Nout];
				const bool v0in = v0[a] <= r + eps, v1in = v1[a] <= r + eps;
				if (!(v0in || v1in)) continue; else if (v0in != v1in)
				{
					bvhvec3 C = v0 + (r - v0[a]) / (v1[a] - v0[a]) * (v1 - v0);
					C[a] = r /* accurate */, vin[Nin++] = C;
				}
				if (v1in) vin[Nin++] = v1;
			}
		}
	}
	bvhvec3 mn( BVH_FAR ), mx( -BVH_FAR );
	for (uint32_t i = 0; i < Nin; i++) mn = tinybvh_min( mn, vin[i] ), mx = tinybvh_max( mx, vin[i] );
	newFrag.primIdx = orig.primIdx;
	newFrag.bmin = tinybvh_max( mn, bmin ), newFrag.bmax = tinybvh_min( mx, bmax );
	newFrag.clipped = 1;
	return Nin > 0;
}

} // namespace tinybvh

#ifdef __GNUC__
#pragma GCC diagnostic pop
#endif

#endif // TINYBVH_IMPLEMENTATION

#endif // TINY_BVH_H_
