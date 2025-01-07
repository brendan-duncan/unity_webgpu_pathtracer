using System;
using System.Runtime.InteropServices;

// Access to the TinyBVH plugin.
public class TinyBVH
{
#if UNITY_EDITOR
    const string libraryName = "unity-webgpu-pathtracer-plugin";
#elif PLATFORM_WEBGL
    const string libraryName = "__Internal";
#else
    const string libraryName = "unity-webgpu-pathtracer-plugin";
#endif

    [DllImport(libraryName)]
    public static extern int BuildBVH(IntPtr verticesPtr, int count);

    [DllImport(libraryName)]
    public static extern void DestroyBVH(int index);

    [DllImport(libraryName)]
    public static extern bool IsBVHReady(int index);

    [DllImport(libraryName)]
    public static extern int GetCWBVHNodesSize(int index);
    
    [DllImport(libraryName)]
    public static extern int GetCWBVHTrisSize(int index);

    [DllImport(libraryName)]
    public static extern bool GetCWBVHData(int index, out IntPtr bvhNodes, out IntPtr bvhTris);


    [DllImport(libraryName)]
    public static extern int BuildTLAS(IntPtr aabbs, int instanceCount);

    [DllImport(libraryName)]
    public static extern void DestroyTLAS(int index);

    [DllImport(libraryName)]
    public static extern bool IsTLASReady(int index);

    [DllImport(libraryName)]
    public static extern int GetTLASNodesSize(int index);

    [DllImport(libraryName)]
    public static extern bool GetTLASData(int index, out IntPtr bvhNodes);
}
