cmake_minimum_required(VERSION 3.10)

project(unity-webgpu-pathtracer-plugin)

set(CMAKE_CXX_STANDARD 17)

add_library(unity-webgpu-pathtracer-plugin SHARED
    "../Assets/Plugins/Web/src/plugin.cpp"
)

if(APPLE)
    set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ../Assets/Plugins/OSX)
endif()
