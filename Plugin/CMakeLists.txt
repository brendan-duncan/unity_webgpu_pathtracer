cmake_minimum_required(VERSION 3.10)

set(PLUGIN_NAME unity-webgpu-pathtracer-plugin)

project(unity-webgpu-pathtracer-plugin)

set(CMAKE_CXX_STANDARD 17)

add_library(unity-webgpu-pathtracer-plugin SHARED
    ../Assets/Plugins/Web/src/plugin.cpp
)

if(WIN32)
    install(TARGETS unity-webgpu-pathtracer-plugin DESTINATION ${CMAKE_SOURCE_DIR}/../Assets/Plugins/Windows)
endif()

if(APPLE)
    set_target_properties(unity-webgpu-pathtracer-plugin PROPERTIES SUFFIX ".bundle")
    install(TARGETS unity-webgpu-pathtracer-plugin DESTINATION ${CMAKE_SOURCE_DIR}/../Assets/Plugins/OSX)
endif()    

if(UNIX AND NOT APPLE)
    install(TARGETS unity-webgpu-pathtracer-plugin DESTINATION ${CMAKE_SOURCE_DIR}/../Assets/Plugins/Linux)
endif()
