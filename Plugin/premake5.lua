local ROOT_DIR = "./"

solution "unity-webgpu-pathtracer-plugin"
    startproject "unity-webgpu-pathtracer-plugin"

    configurations { "Release", "Debug" }
    platforms { "x86_64" }

    filter "platforms:x86_64"
        architecture "x86_64"

    filter "configurations:Release*"
        defines { "NDEBUG" }
        optimize "Speed"
        symbols "On"

    filter "configurations:Debug*"
        defines { "_DEBUG" }
        optimize "Debug"
        symbols "On"

    filter {}
        
project "unity-webgpu-pathtracer-plugin"
    kind "SharedLib"
    language "C++"
    cppdialect "C++17"
    exceptionhandling "Off"
    rtti "Off"
    warnings "Default"
    characterset "ASCII"
    vectorextensions "AVX"
    location ("build/" .. _ACTION)

    defines {
        "_CRT_SECURE_NO_WARNINGS",
        "_CRT_NONSTDC_NO_DEPRECATE",
        "_USE_MATH_DEFINES",
    }

    includedirs {
        path.join(ROOT_DIR, "../Assets/PlugIns/Web/src/"),
    }

    files { 
        path.join(ROOT_DIR, "../Assets/PlugIns/Web/src/**.cpp"),
        path.join(ROOT_DIR, "../Assets/PlugIns/Web/src/**.c"),
        path.join(ROOT_DIR, "../Assets/PlugIns/Web/src/**.h"),
    }

    filter {}