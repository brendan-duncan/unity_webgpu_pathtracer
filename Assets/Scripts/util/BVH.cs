using System;
using System.Runtime.InteropServices;
using UnityEngine;

namespace tinybvh
{
    public class BVH
    {
#if UNITY_EDITOR
        const string libraryName = "unity-webgpu-pathtracer-plugin";
#elif PLATFORM_WEBGL
        const string libraryName = "__Internal";
#else
        const string libraryName = "unity-webgpu-pathtracer-plugin";
#endif
            
        [DllImport(libraryName)]
        private static extern int BuildBVH(IntPtr verticesPtr, int count);

        [DllImport(libraryName)]
        private static extern void DestroyBVH(int index);

        [DllImport(libraryName)]
        private static extern bool IsBVHReady(int index);

        [DllImport(libraryName)]
        private static extern int GetCWBVHNodesSize(int index);
        
        [DllImport(libraryName)]
        private static extern int GetCWBVHTrisSize(int index);

        [DllImport(libraryName)]
        private static extern bool GetCWBVHData(int index, out IntPtr bvhNodes, out IntPtr bvhTris);

        // Index of the BVH internal to the plugin.
        private int index = -1;

        // Construct a new BVH from the given vertices.
        // Set buildCWBVH to true if this is intended for GPU traversal.
        public void Build(IntPtr verticesPtr, int count)
        {
            Debug.Log("!!!! " + libraryName);
            if (index >= 0)
                Destroy();

            index = BuildBVH(verticesPtr, count);
        }

        // Frees the memory of the BVH in the plugin.
        public void Destroy()
        {
            if (index < 0)
                return;
            DestroyBVH(index);
            index = -1;
        }

        // Returns true if the BVH has finished building and can be read or intersected with.
        public bool IsReady()
        {
            if (index < 0)
                return false;
            return IsBVHReady(index);
        }

        // Retrieve the size of the CWBVH nodes array in bytes.
        public int GetCWBVHNodesSize()
        {
            if (index < 0)
                return 0;
            return GetCWBVHNodesSize(index);
        }

        // Retrieve the size of the CWBVH triangles array in bytes.
        public int GetCWBVHTrisSize()
        {
            if (index < 0)
                return 0;
            return GetCWBVHTrisSize(index);
        }

        // Retrieve the CWBVH data for GPU upload.
        public bool GetCWBVHData(out IntPtr bvhNodes, out IntPtr bvhTris)
        {
            if (index < 0)
            {
                bvhNodes = IntPtr.Zero;
                bvhTris = IntPtr.Zero;
                return false;
            }

            return GetCWBVHData(index, out bvhNodes, out bvhTris);
        }
    }
}
