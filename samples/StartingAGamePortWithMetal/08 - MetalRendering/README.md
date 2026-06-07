# Rendering beautiful graphics with Metal

Use Metal for hardware-accelerated rendering across Apple silicon Mac, iPad, and iPhone with a low-overhead API and integrated compute.

## Overview

[Metal](https://developer.apple.com/metal) powers hardware-accelerated graphics on Apple devices by providing a low-overhead API, rich shading language, tight integration between graphics and compute, and an unparalleled suite of GPU profiling and debugging tools. Your games and pro apps that use Metal can take full advantage of the incredible performance and efficiency of Apple silicon across Mac, iPad, and iPhone.

Use the Metal API to bring your graphics code over to Apple devices. Metal gives you low-level access to the graphics and compute capabilities of Apple GPUs, while providing you with an easy-to-use API available across all Apple devices.

## Port your renderer using Metal

### Choose the programming language

C++ and HLSL are two popular programming languages in game development.

This project comes preconfigured with [Metal-cpp](https://developer.apple.com/metal/cpp), allowing you to use your team’s existing expertise in C++ to develop a high-performance Metal renderer tailored to Apple’s GPUs. Metal-cpp exposes all the Metal APIs and has no measurable overhead compared to using the Objective-C interface to the Metal API.

Metal-cpp gives you (and requires) fine-grained control over memory management via reference counting. This capability provides you opportunities to avoid any runtime overhead that could be inadvertently introduced by automatic reference counting; however, proper use requires becoming familiar with the manual retain-release memory model of Apple’s platforms.

If your team is familiar with Objective-C, or prefers to use automatic reference counting, you can easily remove Metal-cpp from this project and compile your C++ source code as “mixed Objective-C++” code. This compilation mode allows you to mix both programming languages in a single file, enabling calling into the Metal framework using Objective-C syntax while keeping the rest of your game’s logic in C++.

Finally, the renderer uses the Metal shader converter's runtime library, `metal_irconverter_runtime.h`, and an example *bump allocator* to operate pipeline state objects that the app creates from shaders the [Metal shader converter](https://developer.apple.com/metal/shader-converter) compiles from `DXIL`. Your project can freely mix and match pipeline state objects consisting of shaders written in both HLSL and Metal Shading Language.

Method `Game::draw()` in `GameRendering.cpp` demonstrates how to use Metal to efficiently render a 2D game consisting of a player sprite, enemy rocks, and special effects.

### Port resource layouts

As you bring over your rendering logic, you need to determine your strategy for binding graphics resources, such as buffers, textures, and samplers, to your pipeline state objects.

[Metal shader converter](https://developer.apple.com/metal/shader-converter) offers you two mechanisms to port your resource layout from other graphics APIs to Metal: automatic layout and explicit layout:

* **Automatic layout** — This mechanism maps each global shader resource as an entry in a buffer. The memory layout of each entry corresponds to structure `IRDescriptorTableEntry` in header file `metal_irconverter_runtime.h`.
* **Explicit layout** — This mechanism allows you to provide a *root signature* object from other graphics APIs to control the layout of the resources into buffers. Using this mechanism, you define a hierarchy of resources, where the root level corresponds to a buffer of `uint64_t` GPU addresses to other resources, including other buffers representing descriptor tables.

You may find the automatic layout the easiest to use; however, in some situations, it's desirable to explicitly establish the layout of resources via a root signature to avoid the need to reflect binding offsets. Additionally, using an explicit layout enables you to bind unbounded arrays to your pipelines, simplifying porting a bindless renderer from other graphics APIs.

This sample uses embedded root signatures for the entry points in files `present.hlsl` and `sprite_instanced.hlsl` to establish the resource locations where the renderer in `Game.cpp` binds its data through its *top-level argument buffer*.

For more details about the Metal shader converter binding models and helper functions, including other mechanisms to specify your root signature programmatically, and through JSON files, see the [Metal shader converter documentation](https://developer.apple.com/metal/shader-converter).

### Understand the Metal resource residency model

When you convert your shaders from other platforms to Metal libraries and use the pipelines you build from them, you bind your resources indirectly through *argument buffers*. Metal requires you to explicitly mark the residency of all resources your shaders access through these buffers, otherwise these may not be present at runtime, causing a command buffer failure.

Metal provides you three mechanisms to mark your resources resident:

* By explicitly calling `useResource()` and `useResources()`
* By using Metal *Heap* objects (`MTL::Heap`) and marking them resident via `useHeap()`
* By using Metal *Residency Sets* (`MTL::ResidencySet`), starting in macOS 15, and iOS 18

`useResource()` and `useResources()` allow you to mark resident a resource or an array of resources for the current render or compute pass you are encoding. Metal aggregates all resources you specify through these calls and makes sure that when the pass executes, these resources are available to the GPU.

Metal heap instances are a large resource from where you can suballocate resources. Because Metal heap instances are a single allocation to Metal, you mark the entire heap object (including all suballocations) resident in a single call to `useHeap()`.

Adopting Metal heaps requires that you plan ahead of time how you organize your resources, rather than allocating them on-the-fly; however, calls to `useHeap()` typically result in lower CPU usage compared to performing multiple calls to `useResource()`.

> Note: Allocating read and write resources from the same Metal heap instance may result in *false sharing* when using Metal's automatic resource tracking, potentially increasing the CPU wall clock time execution of your frame. Consider using Metal heaps for read-only resources and using discrete allocations for writable resources.

When using the `useResource()` and `useHeap()` APIs, you specify resource residency on a per-pass granularity level. Your render and compute passes need to mark residency for all resources they access indirectly when using these methods.

For more details about Metal's residency model and resource synchronization primitives, see [Go Bindless with Metal 3](https://developer.apple.com/videos/play/wwdc2022/10101) WWDC session.

Finally, Metal residency sets are a new residency management model in macOS 15 and iOS 18. Residency Sets provide the low CPU overhead of Metal heaps while keeping the flexibility of the `useResource()` APIs. They do this while simultaneously making it easier to track resource residency at a coarser granularity level than per pass.

Residency Sets behave like *virtual* Metal heaps. As you create discrete resources from a `MTL::Device` instance, you add them once to Residency Sets. When a Residency Set becomes resident, it automatically makes all its resources resident, fully removing the need to mark resources resident on a per-pass basis. You can also add Metal heap instances to residency sets, making the entire instance, along with all its suballocations resident when the residency set becomes resident.

Furthermore, when you create a Metal Residency Set, you specify the granularity level at which it controls residency. For example, when you establish that a Residency Set provides *command queue-level* residency, then Metal automatically marks all resources it contains resident for all work your game submits to that command queue.

Metal Residency Sets dramatically simplify the Metal residency model and can yield significant CPU savings compared to individually marking the residency of discrete resources through the `useResource()` API. Using Residency Sets, not only do you save the cost of calling `useResource()` multiple times during your frame, but also, subject to your system’s capacity, Metal attempts to keep your resources resident for as long as possible — even across frames — avoiding the cost of wiring and unwiring memory repeatedly.

Keep in mind, however, that when you use residency sets, you need to convey to Metal your resource dependencies through Metal's synchronization primitives such as `MTL::Fence`.

In macOS 15 and iOS 18, this sample uses Metal residency sets to keep indirect resources resident for as long as possible. Function `initializeResidencySet()` in `Game.cpp` creates a Metal residency set instance, collects all indirect resources into it, associates it to the command queue, and commits it.

```cpp
_renderData.residencySet =
    NS::TransferPtr(pDevice->newResidencySet(pResidencySetDesc.get(), &pError));

if(_renderData.residencySet)
{
     _renderData.residencySet->requestResidency();
     pCommandQueue->addResidencySet(_renderData.residencySet.get());
     
     // ... add resources into the residency set ...
     
      _renderData.residencySet->commit();
 }
```

After committing the Residency Set, all subsequent work the sample submits to this command queue can automatically assume these resources are resident.

On operating systems before macOS 15 and iOS 18, the sample falls back to using a combination of `useResources()` and `useHeap()`, in `GameRendering.cpp`, preserving backwards compatibility.

### Increase the priority of your render thread

Your render thread is by definition in the critical path for rendering, as it encodes the work your game submits to the GPU. Priority decay is the behavior by which, over time, the macOS and iOS scheduler decrease the priority of long-running threads to fairly share the CPU across all threads.

When you spawn a separate thread for rendering, you can convey to the system that this thread needs to opt out of priority decay and that it’s high priority. These settings make the scheduler treat the way it schedules your render thread, so it’s important to restrict this configuration to as few threads as possible to avoid congestion that could negatively impact all threads.

This sample’s `GameCoordinatorController` (`GameCoordinatorController.m`) uses the `pthread` API to create a high-priority “detached thread” with a round-robin scheduling policy for the vsync callback.

```objc
// Create a high-priority thread that sets up the CAMetalDisplayLink callback and renders the game

int res = 0;

pthread_attr_t attr;
pthread_attr_init( &attr );

// Opt out of priority decay:  
pthread_attr_setschedpolicy( &attr, SCHED_RR );

// Increase priority of render thread:
struct sched_param param = { .sched_priority = 45 };
pthread_attr_setschedparam( &attr, &param );

// Enable the system to automatically clean up upon thread exit:
pthread_attr_setdetachstate( &attr, PTHREAD_CREATE_DETACHED );

// Create thread:
pthread_t tid;
pthread_create( &tid, &attr, renderWorker, (__bridge void *)_metalDisplayLink );

// Clean up transient objects:
pthread_attr_destroy( &attr );
```

`pthread_create` passes in `renderWorker`, a function pointer to the entry point of the thread. The sample implements it in the same file:

```objc
static void* renderWorker( void* _Nullable obj )
{
    pthread_setname_np("RenderThread");
    CAMetalDisplayLink* metalDisplayLink = (__bridge CAMetalDisplayLink *)obj;
    [metalDisplayLink addToRunLoop:[NSRunLoop currentRunLoop]
                           forMode:NSDefaultRunLoopMode];
    [[NSRunLoop currentRunLoop] run];
    return nil;
}
```

The `renderWorker` function, running in the elevated-priority thread, adds the Metal display link instance to the current run loop and starts it. Under this setup, callbacks from the Metal display link instance occur on this elevated-priority thread.

### Organize your renderer into render passes

One key characteristic of Apple silicon devices is their unified memory, shared between the CPU and GPU.

The GPU contains a small on-chip memory, called tile memory, into which your pipelines write render attachment data for each render pass. The GPU only copies this data back out into shared system memory when the render pass ends. Working directly on tile memory is key to the power efficiency and performance of Apple GPUs.

The Metal API is a perfect fit for Apple's [TBDR GPU architecture](https://developer.apple.com/documentation/metal/tailor_your_apps_for_apple_gpus_and_tile-based_deferred_rendering?language=objc), giving you fine-grained control over whether the driver copies data from system memory to tile memory and back from tile memory to system memory, and when.

You control the granularity at which the driver copies data by aggregating your work into *render passes*. When a render pass starts, the driver determines what data it needs to copy into tile memory by inspecting the `MTLLoadAction` actions you specify for each render attachment. Similarly, the driver determines what data it needs to copy back to system memory by inspecting the `MTLStoreAction` you specify for each render attachment.

Copying data between the two memories consumes memory bandwidth, which costs power, and additionally causes heat dissipation, which in excess is undesirable for passively cooled devices such as iOS devices and fanless MacBook models.

As you bring your renderer over to Metal, you should strive to organize your rendering to consolidate work into as few render passes as possible, ideally performing all work that impacts the same render targets together. Key to this goal is to avoid breaking up render passes to perform compute work or data copies between resources (such as image or buffer blits).

Consider reorganizing your workload to batch data copies together at the beginning of your frame, avoiding copy operations later, and grouping commands of the same type together by avoiding interleaving render and compute work. If your renderer doesn't allow for easily batching compute and render work separately, you can create separate command buffer instances for the compute and render work and encode your work into these two command buffers. This additionally enables you to perform your encoding in parallel.

Finally, it's typical in other render APIs without the concept of render passes to have dedicated operations to clear render targets. Because Metal aggregates all render work into render passes, you can efficiently use the `MTLLoadActionClear` to clear the attachment in tile memory just in time before use, completely avoiding the memory bandwidth cost of copying the attachment data into tile memory just to clear it and then storing it back.

### Port indirect drawing logic to Metal

Elaborate game engines rely on indirect drawing (*execute indirect*) to implement GPU-driven pipelines where a compute shader determines the render work to perform in a subsequent render pass.

In this process, the compute shader takes an input, performs an algorithm, such as determining potential object visibility, and writes its results into a buffer specifying how many objects to render. The graphics API then encodes a render operation that references the parameters in this buffer instead of directly encoding them. This removes the CPU from the equation, giving the GPU a larger say on what the renderer displays to your players.

Metal fully supports indirect drawing through its own *execute indirect* functionality and through the concept of *indirect command buffers*.

For Metal render pipeline state objects you create from shaders converted with Metal shader converter, functions `IRRuntimeDrawPrimitives` and `IRRuntimeDrawIndexedPrimitives` take a Metal buffer containing the structures `MTLDrawPrimitivesIndirectArguments` and `MTLDrawIndexedPrimitivesIndirectArguments`, respectively, which indirectly specify the parameters of the draw call to Metal.

[Metal indirect command buffers](https://developer.apple.com/documentation/metal/indirect_command_encoding?language=objc), instances of `MTL::IndirectCommandBuffer`, provide a more flexible mechanism for executing indirect drawing work. For example, indirect command buffers allow you to change the render pipeline state within the indirect draw call, enabling the GPU to express complex rendering logic with vastly different visual results.

Indirect command buffers provide you with a mechanism to port *multidraw indirect* draw calls from other graphics APIs to Metal. After your compute shader writes the multidraw indirect buffer, dispatch a custom compute shader that re-encodes the multidraw indirect buffer into a Metal indirect command buffer. You can then replace your renderer's multidraw indirect call with `executeCommandsInBuffer()` to encode execution of the indirect command buffer to your render pass.

> Note: Because HLSL doesn't have the concept of indirect command buffers, use the Metal Shading Language (MSL) to implement the multidraw indirect translation compute shader.

If your renderer already includes a compute-based multidraw indirect compaction dispatch, you can save the cost of an additional compute dispatch by rewriting your compaction shader to directly encode its results into the indirect command buffer.

For more details on porting indirect rendering logic to Metal, see [Bring your game to Mac, Part 3: Render with Metal](https://developer.apple.com/videos/play/wwdc2023/10125/) WWDC 2023 session.

### Port ray tracing pipelines

Metal shader converter fully supports ray-tracing pipelines and ray query, allowing you to easily bring your unmodified ray-tracing shaders to the Metal API. For details on how to bring your ray-tracing shaders to Metal, see the [Metal shader converter documentation](https://developer.apple.com/metal/shader-converter).

The Metal shader converter macOS installer comes with two code samples `RayQueryExample` and `RayTracingPipelinesExample` that it copies to `/opt/metal-shaderconverter/samples/` on your system. These samples demonstrate how to compile, configure, and run ray-tracing pipelines and ray query shaders on Metal.

### Port mesh shader pipelines

Metal shader converter fully supports mesh shader pipelines, allowing you to easily bring your unmodified mesh shaders to the Metal API. For details on how to bring your mesh shaders to Metal, see the [Metal shader converter documentation](https://developer.apple.com/metal/shader-converter).

### Port geometry and tessellation shaders to Metal

Metal shader converter fully supports bringing legacy shader stages, such as geometry shaders and tessellation shaders, to Metal. For details on how to bring your legacy shaders to Metal, see the [Metal shader converter documentation](https://developer.apple.com/metal/shader-converter) and the [Bring your game to Metal, Part 2: Compile your shaders](https://developer.apple.com/videos/play/wwdc2023/10124/) WWDC 2023 session.

The Metal shader converter macOS installer comes with the MetalShaderConverterDylibExample sample project, which demonstrates how to compile, configure, and run geometry and tessellation shaders on Metal. You can find that sample under `/opt/metal-shaderconverter/samples/` on your system after installing Metal shader converter.

### Upscale with MetalFX

The [MetalFX](https://developer.apple.com/documentation/metalfx?language=objc) framework provides your game with an out-of-the-box solution for saving GPU time by targeting a lower resolution and efficiently upscaling it to the device's screen.

MetalFX is available on both macOS and iOS, making it easy to target both platforms from the same codebase, and offers two mechanisms to upscale your content:

* Spatial scaling, via `MTLFX::SpatialScaler`
* Temporal scaling, via `MTLFX::TemporalScaler`

The spatial scaler is easier to set up; however, the temporal scaler produces better results by using temporal information across different frames. This sample uses the spatial scaler because it renders a simple 2D game with no depth information. In your advanced games, you should use the temporal scaler.

When adopting upscaling, make sure you don't apply it to your game's UI, otherwise it may not appear as crisp as your players expect. Separate your in-game content rendering from your UI rendering and apply MetalFX upscaling in between these two stages.

When using Metal shader converter pipelines, your textures need to be of type `TextureArray` to provide cross-platform-compatible behavior; however, MetalFX expects non-`TextureArray` inputs. This sample’s `buildRenderTextures()` in `GameCoordinator.cpp` creates texture views to use as `TextureArray` to `Texture` adapters, allowing it to take advantage of the power of MetalFX upscalers for converted shaders.

For more details on adopting efficient upscaling in your Metal game, see [Boost performance with MetalFX Upscaling](https://developer.apple.com/videos/play/wwdc2022/10103/) and [Bring your game to Mac, Part 3: Render with Metal](https://developer.apple.com/videos/play/wwdc2023/10125/) WWDC sessions.

### Efficiently wait for GPU completion

Metal applications typically work on multiple frames simultaneously. As the GPU executes work corresponding to a frame, the CPU encodes subsequent work for the next frame in parallel.

Overwriting the contents of Metal resources from the CPU while the GPU accesses them concurrently leads to race conditions between the two devices, and could cause visual corruption and GPU hangs.

To synchronize access to writeable resources, the sample creates three copies of each writable Metal buffer. This allows the GPU to work on one copy of the data as the CPU prepares the next. In addition, the sample suspends the CPU render thread to ensure the GPU work completes before cycling through these three sets of resources.

Both macOS and iOS offer several synchronization primitives that you can use to coordinate access to resources between the CPU and GPU. The best primitive you can use to coordinate this access is Metal shared events, which allow the GPU to signal the CPU as work reaches any specific point of your choosing in a command buffer.

This project’s `draw()` function in `GameCoordinator.cpp` uses Metal shared events to pause the CPU render thread until the GPU signals that it completed work on prior buffers.

```cpp
// _pacingTimeStampIndex is a uint64, kMaxFramesInFlight is 3.

if (_pacingTimeStampIndex > kMaxFramesInFlight)
{
    uint64_t const timeStampToWait = _pacingTimeStampIndex - kMaxFramesInFlight;
    _pPacingEvent->waitUntilSignaledValue(timeStampToWait, DISPATCH_TIME_FOREVER);
}

 MTL::CommandBuffer* pCmd = _pCommandQueue->commandBuffer();

// ... encode GPU work ...

 pCmd->presentDrawable(pDrawable);
pCmd->encodeSignalEvent(_pPacingEvent.get(), _pacingTimeStampIndex);
pCmd->commit();
```

In this snippet, the project liberally encodes the first three frames, always encoding signaling events for timestamps.

Starting with the fourth frame, the CPU thread blocks, waiting for the GPU to signal a prior timestamp. This ensures that if the CPU gets too far ahead of the GPU, the system makes it wait until the GPU catches up.

Unlike other synchronization primitives, such as `dispatch_semaphores`, Metal shared events have the advantage that when the GPU signals a value, the operating system’s scheduler understands the dependency and directly wakes up any blocked threads, allowing your game’s render thread to efficiently resume its work.

## Make the most of Apple displays

Macs and iOS devices possess beautiful screens of different shapes, capable of displaying vibrant colors. Take advantage of this hardware to deliver an experience to your players like never seen before.

### Make the most of Apple’s displays with EDR

Macs and iOS devices support displaying content beautifully through extended display range (EDR). EDR allows you to present content to your players beyond the standard display range (SDR), enabling your game to convey beautiful colors that just pop out the screen.

The process of adding EDR to your game in both macOS and iOS is straightforward:

1. Opt into EDR support via your Metal layer.
2. Select an extended-range colorspace for your Metal layer.
3. Use a pixel representation for your render target that can encode values beyond SDR.
4. Display your game content beyond the 0.0 — 1.0 range.

To opt into EDR support, this code sample sets `wantsExtendedDynamicRangeContent = YES` and selects a *P3* colorspace when it creates the `CAMetalLayer` instance in file `MetalView.m`.


```objc
- (CALayer *)makeBackingLayer
{
    CAMetalLayer* layer = [CAMetalLayer layer];
    layer.wantsExtendedDynamicRangeContent = YES;
    layer.colorspace = CGColorSpaceCreateWithName(kCGColorSpaceExtendedLinearDisplayP3);
    return layer;
}
```


Finally, the sample uses pixel format `MTLPixelFormatRGBA16Float` for the Metal layer and render attachments, which allows it to store pixels beyond the 0.0 — 1.0 range.

The EDR headroom, corresponding to the maximum intensity that your display can represent, depends on several factors, including the current brightness level of your player's display. Thus, the EDR headroom is a dynamic value. You can query the `maximumExtendedDynamicRangeColorComponentValue` property of the `NSScreen` and `UIScreen` objects on macOS and iOS, respectively, to determine the headroom available at any given time.

In macOS, you can additionally register a callback to a headroom change notification using key: `NSApplicationDidChangeScreenParametersNotification`.

> Note: This code sample uses a simple tone mapper that stretches the SDR range to cover the headroom available. In your game, keep the SDR content within the 0.0 — 1.0 range and only go beyond these values for true EDR content.

For more details on adopting EDR in your macOS and iOS games, see [Explore HDR rendering with EDR](https://developer.apple.com/videos/play/wwdc2021/10161) and [Explore EDR on iOS](https://developer.apple.com/videos/play/wwdc2022/10113/).

### Handle full screen

While iOS games typically run full screen, macOS games may also support a non-full-screen windowed mode. In both situations, your game needs to adapt to the geometry of the window into which it renders its content.

On macOS, the window can be of different sizes, or it can enter and exit full-screen mode at your player’s request. In iOS, different devices, such as iPad and iPhone 15 Pro, offer different aspect ratios that your game needs to adapt to dynamically.

As you bring up your game, determine what resolution settings your Metal renderer supports for your target frame rate and which aspect ratios your game exposes. High-fidelity games typically target a resolution lower than the device’s retina resolution, opting to devote most processing power to producing beautiful pixels that the game then scales up using super-scaling frameworks such as MetalFX.

This project sets the internal render resolution to 1920x1080, and uses Core Animation to letterbox the Metal view and preserve this aspect ratio regardless of your player's device screen or window's geometry.

In files `iOS/GameApplication.m` and `macOS/GameApplication.m`, function `createView()` sets this configuration.

```objc
   // Set layer size and make it opaque:
    _metalLayer.drawableSize = CGSizeMake(1920, 1080);
    _metalLayer.opaque = YES;
    _metalLayer.framebufferOnly = YES;
    
    // Configure CoreAnimation letterboxing:
    _metalLayer.contentsGravity = kCAGravityResizeAspect;
    _metalLayer.backgroundColor = CGColorGetConstantColor(kCGColorBlack);
```

After it retrieves the Metal layer, the code snippet sets its size to 1920x1080, makes it an opaque render destination, enabling extra optimizations at composition time, and sets its `contentsGravity` to `kCAGravityResizeAspect`. This last property delegates letterboxing to Core Animation.

The final property, `backgroundColor`, determines the color of the letterbox bars that Core Animation draws.

### Provide in-game settings

Players typically expect a settings menu that allows them to tweak their experience. Some players prefer to play in a high-fidelity mode, where your game draws fewer frames per second, but these are at maximum quality. Other players prefer to reach high frame rates and minimum latency.

Further, players expect game menus to express a custom theme that matches your game’s narrative and art style. Use the Metal framework to render custom UI and allow your players to tweak how they experience your game. Typical settings your players expect include the rendering resolution, aspect ratio, super-scaling quality mode, and so on.

Unlike in other platforms, macOS provides a great full-screen experience to your players right out of the box via the green full-screen control at the top-left corner of your window. Use this control to implement your full-screen experience, instead of exposing a programmatic way to trigger it. Using this control does not prevent macOS from directly compositing your game onscreen.

## Deliver a great display experience

* Determine what resolution settings your game supports for your target frame rate and at which aspect ratios. High-fidelity games typically target a resolution lower than the device’s retina resolution.
* Players expect a settings menu that allows them to tweak their experience.
* Expose UI to configure settings such as the resolution, frame rate, and potentially offer a battery-saver mode.
* Adapt to the window’s geometry.
    * Your game renders at a predetermined resolution, but the app’s window size adapts to your player’s configuration.
    * When your content can't adjust to the window's geometry, use Core Animation to implement letterboxing, which adjusts your Metal view while preserving your game’s proportions.
    * Use upscale algorithms such as MetalFX to increase your render target’s resolution and provide smoother graphics to your players without drastic compromises in performance.
    * These principles help you deliver a great full-screen experience as well.
* Use EDR where available to show vibrant colors that pop out of the screen.
* In macOS, use the full-screen button to go full screen. There's no need to provide an option in the game’s settings.
* Adopt direct to display.

## See also

Consult the [Designing for games on Apple platforms guidelines](https://developer.apple.com/design/human-interface-guidelines/designing-for-games) on the following topics for more details on how to deliver a great display experience:

* [Window management](https://developer.apple.com/design/human-interface-guidelines/windows) — Design a consistent layout that adapts gracefully to context changes.
* [Going full screen](https://developer.apple.com/design/human-interface-guidelines/going-full-screen) — Players appreciate full-screen mode for situations where they want to feel immersed or focused on task.
* [Game menus](https://developer.apple.com/design/human-interface-guidelines/menus) — When you use menus consistently in your app or game, it can help make your experience feel familiar and easy to learn.
* [Typography](https://developer.apple.com/design/human-interface-guidelines/typography) — In addition to ensuring legible text, your typographic choices can help you clarify an information hierarchy, communicate important content, and express your brand or art style.
* [Metal developer workflows](https://developer.apple.com/documentation/xcode/metal-developer-workflows) documentation for more details.
* [Bring your game to Mac, Part 3: Render with Metal](https://developer.apple.com/videos/play/wwdc2023/10125/) WWDC 2023 session.
* [Metal shader converter documentation](https://developer.apple.com/metal/shader-converter).
* [Go Bindless with Metal 3](https://developer.apple.com/videos/play/wwdc2022/10101) for more details about Metal's residency model and resource synchronization primitives.
* [Explore HDR rendering with EDR](https://developer.apple.com/videos/play/wwdc2021/10161).
* [Explore EDR on iOS](https://developer.apple.com/videos/play/wwdc2022/10113/).

## Test your knowledge

1. Extend the GPU-based collision detection from *Chapter 04 – Physics* to indirectly draw the enemy rocks without involving the CPU, moving the game to a GPU-driven renderer.
2. Modify the `sprite_instanced.hlsl` fragment shader to apply a variety of colors to the enemy rocks. Hint: use the *SV_InstanceID* shader semantic to distinguish between instances and calculate the color.
