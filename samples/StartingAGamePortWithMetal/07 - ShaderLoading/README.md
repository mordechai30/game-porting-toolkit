# Loading your shaders

Load your Metal libraries into your game to perform computations and render beautiful graphics. 

## Overview

Starting in macOS 15 and iOS 18, Metal has unified libraries, allowing your apps to load libraries you compile for either platform, dramatically decreasing the time it takes to change the run target for your app by avoiding expensive shader recompilations.

## Port your shader loading code

You load shaders into your game to create *pipeline state* objects that you use to perform work on the GPU. All modern graphics APIs allow you to load shaders from a binary representation, either directly as GPU binary code, or as an intermediate representation (IR) that the video drivers then compile into machine code at runtime.

The Metal API supports both mechanisms, loading shader binary code from *Metal binary archives* or from *Metal intermediate representation* (*Metal IR*), respectively. For a comprehensive overview of both mechanisms, see [Bring your game to Mac, Part 2: Compile your shaders](https://developer.apple.com/videos/play/wwdc2023/10124) WWDC 2023 session.

This project converts its shaders into Metal IR by running the Metal shader converter, producing Metal libraries that the game loads at runtime.

### Load Metal library files

In other graphics APIs, you typically load the shader IR from a binary file and directly reference its bytes as the *shader modules* of a pipeline descriptor object. The process of loading Metal IR in Metal is very similar, except you first load the shader modules into `MTL::Library` instances, from which you query the entry points for your pipeline.

This project's `newPresentPipeline` and `newInstancedSpritePipeline` functions in the `ShaderPipelineBuilder.cpp` file load the Metal IR from the application bundle at runtime, create Metal library files, retrieve the shader entry points, and, by creating pipeline descriptor objects, instantiate the pipeline state objects that display the game on screen.

The process consists of the following steps:

1. Retrieve the file system path into bundle's `Resources/` directory.
2. Load the contents of each file as a vector of bytes.
3. Make a `dispatch_data_t` object containing these bytes.
4. Provide the `dispatch_data_t` object to the Metal device (`MTL::Device`) to load it as a Metal library (`MTL::Library`).
5. Build the pipeline objects from the Metal library.

### Retrieve the path into the bundle's resources

The app bundle packages its resources in a dedicated folder where Xcode copies the Metal libraries. You retrieve this path in a platform-independent way by querying the bundle for its resource path.

The `GameCoordinatorController.mm` file retrieves the path from Objective-C and passes it to the C++ codebase:

```objc
NSString* shaderPath = NSBundle.mainBundle.resourcePath;
```

The app then uses the `shaderPath.UTF8String` property to obtain a NULL-terminated string that it then uses to create a `std::string`.

> Note: The life cycle of the `shaderPath` string is not guaranteed to extend beyond the enclosing `@autoreleasepool` block. Make sure to allocate the `std::string` before the pool drains.

The `ShaderPipelineBuilder.cpp` file appends the name of the shader to the `shaderPath` and reads its bytes into a `std::vector<uint8_t>`.

### Make a dispatch data object from bytes

To load the Metal library into Metal, the app first converts its bytes into a `dispatch_data_t` object.

```cpp
dispatch_data_t data = dispatch_data_create(bytecode.data(),
                                            bytecode.size(),
                                            dispatch_get_main_queue(),
                                            DISPATCH_DATA_DESTRUCTOR_DEFAULT);
```

The queue parameter `dispatch_get_main_queue()` indicates that the destructor of the queue runs on the `main` thread, and the constant `DISPATCH_DATA_DESTRUCTOR_DEFAULT` specifies destruction uses its default mechanism.

When running in an *Automatic Reference Counting* (ARC) context (the default for `.m`, `.mm` files), the runtime releases the `data` object automatically when its retain count reaches *0*. In a *Manual Retain-Release* (MRR) context (typically `.cpp` files), you are responsible for releasing the `data` object when your app no longer needs it, by calling `CFRelease()`.

### Load the Metal library

In the `ShaderPipelineBuilder.cpp` file, the app uses the Metal device to load the Metal library bytes in a dispatch data object.

The following snippet loads the Metal library from the `data` object in both macOS and iOS:

```cpp
NS::Error* pError = nullptr;
MTL::Library* pLib = pDevice->newLibrary(data, &pError);
if (!pLib)
{
    printf("Error building Metal library: %s\n",
           pError->localizedDescription()->utf8String());
}
```

When you run the project in macOS 15 or iOS 18, Metal can load its libraries regardless of their specified target platform, removing the need to recompile them when you switch the run destination.

### Make the pipeline state object instances

The app uses Metal to retrieve the shader functions from the library instances, build *pipeline descriptor* objects, and compile its *pipeline state* objects.

The `ShaderPipelineBuilder.cpp` file creates the pipeline state objects by first retrieving the vertex and fragment functions:

```cpp
auto pVFn = NS::TransferPtr(pVtxLib->newFunction(MTLSTR("MainVS")));
auto pFFn = NS::TransferPtr(pFragLib->newFunction(MTLSTR("MainFS")));
```

Next, the app creates the *vertex descriptor*, describing the format of the vertex buffer:

```cpp
auto pVtxDesc = NS::TransferPtr(MTL::VertexDescriptor::alloc()->init());

// ... configure vertex descriptor ...
```

Finally, the app creates the descriptor and builds the pipeline:

```cpp
auto pPsoDesc = NS::TransferPtr(MTL::RenderPipelineDescriptor::alloc()->init());
pPsoDesc->setVertexDescriptor(pVtxDesc.get());
pPsoDesc->setVertexFunction(pVFn.get());
pPsoDesc->setFragmentFunction(pFFn.get());

// ... 

NS::Error* pMtlError = nullptr;
MTL::RenderPipelineState* pPso =
    pDevice->newRenderPipelineState(pPsoDesc.get(), &pMtlError);

assert(pPso);
```

The app then saves this pipeline state object (sending a `retain()` message to it to ensure its life cycle), and uses it at rendering time.

## See also

* [Bring your game to Mac, Part 2: Compile your shaders](https://developer.apple.com/videos/play/wwdc2023/10124) WWDC 2023 session

## Test your knowledge

1. Modify the `newInstancedSpritePipeline` function in `ShaderPipelineBuilder.cpp` to disable alpha blending and rerun the game. Notice the effect that lack of alpha blending has on the visuals.
2. Add a new function to `ShaderPipelineBuilder.cpp` to load and create a pipeline state object consisting of the custom shaders from the shader conversion chapter.
