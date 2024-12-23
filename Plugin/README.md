# unity-tinybvh-plugin
A simple wrapper for tinybvh which provides an interface for Unity.

# Compiling for Windows
 - Run `GenerateProjectFiles.bat`
 - Open generated Visual Studio project
 - Build
 - Copy compiled DLL into Unity project under `Assets/Plugins/Windows`

# Compiling for OSX
 - Run `GenerateProjectFiles.command`
 - Open generated XCode project
 - Configure for the current architecture you're compiling for
 - Build
 - Rename generated .dylib to .bundle
 - Copy the bundle into Unity project under `Assets/Plugins/OSX`

# Compiling for Linux
 - Run `GenerateProjectFiles.sh`
 - Run `make`
 - Copy compiled .so into Unity project under `Assets/Plugins/Linux`
