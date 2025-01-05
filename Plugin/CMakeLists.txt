cmake_minimum_required(VERSION 3.10)

set(PLUGIN_NAME unity-webgpu-pathtracer-plugin)

project(unity-webgpu-pathtracer-plugin)

set(CMAKE_CXX_STANDARD 17)

add_library(unity-webgpu-pathtracer-plugin SHARED
    ../Assets/Plugins/Web/src/plugin.cpp
)

if(WINDOWS)
    install(TARGETS unity-webgpu-pathtracer-plugin DESTINATION ../Assets/Plugins/Windows)
elif(APPLE)
    set_target_properties(unity-webgpu-pathtracer-plugin PROPERTIES SUFFIX ".bundle")
    install(TARGETS unity-webgpu-pathtracer-plugin DESTINATION ../Assets/Plugins/OSX)
elif(UNIX)
    install(TARGETS unity-webgpu-pathtracer-plugin DESTINATION ../Assets/Plugins/Linux)
endif()
