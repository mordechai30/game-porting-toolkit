# Converting your shaders

This project demonstrates how to bring your shaders from DXIL to Metal using Metal shader converter.

## Overview

Shaders are small programs that execute on the GPU to *shade* surfaces and perform computations. Game developers typically use the HLSL shading language to implement their shaders. Using the [Metal shader converter](https://developer.apple.com/metal/shader-converter), you can convert your shaders to Metal libraries.

## Port shaders to Metal

This project contains two example shader files, `present.hlsl` and `sprite_instanced.hlsl`, that it uses to draw the game to the player.

These files each contain two *vertex* shaders and two *fragment* shaders, which the app first compiles to an intermediate representation (*DXIL*) and then converts to Metal libraries, producing four *.metallib* files.

Because Metal Shader Converter consumes HLSL, the project doesn't include any `.metal` (Metal Shading Language) source files. This chapter focuses specifically on the *conversion* path; for samples authored directly in MSL, see the [Metal](https://developer.apple.com/metal/) developer site.

Metal shader converter is easy to integrate into your asset pipeline. In addition to its command-line interface, Metal shader converter offers a dynamic library (available for macOS and Microsoft Windows) that you can use for more elaborate shader conversions from a custom shader conversion program.

For example, you can use the Metal shader converter dynamic library to make a program that programmatically customizes the root signature of each shader, renames entry points, obtains offline reflection data, packages the Metal libraries into custom *PAK* files, and more.

Review the [Metal shader converter](https://developer.apple.com/metal/shader-converter) documentation for more details and examples, including how to convert legacy shader stages such as geometry and tessellation shaders, as well as modern mesh shading, ray tracing, and ray query shaders.

The [Metal developer tools](https://developer.apple.com/metal/tools/) in Xcode 16 on macOS 15 and iOS 18 fully support [debugging](https://developer.apple.com/documentation/xcode/debugging-the-shaders-within-a-draw-command-or-compute-dispatch), [profiling](https://developer.apple.com/documentation/xcode/optimizing-gpu-performance#Optimize-shaders-with-per-line-shader-profiling-statistics), and performing Metal shader validation of shaders that Metal shader converter compiles.

You can download Metal shader converter from [https://developer.apple.com/downloads?q=Shader%20Converter](https://developer.apple.com/downloads).

## Understand shader conversion in this project

This project demonstrates how to convert shaders at compilation time by extending the Xcode build system and adding three new custom build steps.

Click `GameProject` at the top of the Project Navigator, select the `GameProject` target, and then select "Build Phases". The project devotes two new steps (or *phases*) to shader compilation and conversion. Each phase lists its inputs and outputs, defining the shaders it converts:

1. **Compile HLSL shaders to DXIL**. The script tests for the DXC compiler under `/usr/local/bin/dxc-3.7` and uses this program to convert the entry points in the HLSL shader files to DXIL, placing it in the `Cache/` folder. If the compiler is not present, the project uses precached DXIL files.
2. **Convert DXIL to metallibs**. The script uses the Metal shader converter command-line tool to convert the DXIL shaders into Metal libraries.

In the last phase, the invocation instructs Metal shader converter to write its output Metal libraries into the `PrecompiledAssets/` folder. Because Xcode's project navigator references these files, Xcode automatically adds them to the "Copy Bundle Resources" phase of the build process, copying the Metal libraries to the app bundle.

Altogether, this process makes it easy to compile, convert, and package shaders, making them available to both macOS and iOS apps, ready for loading at runtime.

## See also

* [Get started with Metal shader converter](https://developer.apple.com/metal/shader-converter)
* [Metal shader converter download page](https://developer.apple.com/downloads?q=Shader%20Converter)
* [Metal developer tools](https://developer.apple.com/metal/tools/)
* [Metal developer workflows](https://developer.apple.com/documentation/xcode/metal-developer-workflows/)
* [Debugging the shaders within a draw command or compute dispatch](https://developer.apple.com/documentation/xcode/debugging-the-shaders-within-a-draw-command-or-compute-dispatch)
* [Optimize shaders with per-line shader profiling statistics](https://developer.apple.com/documentation/xcode/optimizing-gpu-performance#Optimize-shaders-with-per-line-shader-profiling-statistics)
* [Discover new Metal profiling tools for M3 and A17 Pro](https://developer.apple.com/videos/play/tech-talks/111374/) Tech Talk
* [Bring your game to Mac, Part 2: Compile your shaders](https://developer.apple.com/videos/play/wwdc2023/10124) WWDC 2023

## Test your knowledge

1. Modify the `sprite_instanced.hlsl` file to apply a color effect, such as an outline, to the enemy rocks. Note: this requires making an HLSL compiler available under `/usr/local/bin/`.
2. Extend the custom build phases in this project to add a new vertex and fragment shader pair to this project and compile them to a Metal library that Xcode copies into the application bundle at build time.
