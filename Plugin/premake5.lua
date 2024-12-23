local ROOT_DIR = "./"

solution "unity-tinybvh-plugin"
    startproject "unity-tinybvh-plugin"

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
        
project "unity-tinybvh-plugin"
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
        path.join(ROOT_DIR, "../Assets/PlugIns/WebGL/src/"),
        --path.join(ROOT_DIR, "include/"),
    }

    files { 
        path.join(ROOT_DIR, "../Assets/PlugIns/WebGL/src/**.cpp"),
        path.join(ROOT_DIR, "../Assets/PlugIns/WebGL/src/**.c"),
        path.join(ROOT_DIR, "../Assets/PlugIns/WebGL/src/**.h"),
        --path.join(ROOT_DIR, "include/**.h")
    }

    filter {}