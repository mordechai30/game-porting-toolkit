# Codebase Analysis Checklists

Reference document for `porting-discover`. Covers platform readiness, graphics backend analysis, feature coverage, platform gaps, practical advice, risks, and dependencies.

## Platform Readiness

### Build System
- Can the project build for macOS? Check for Xcode projects/workspaces, CMake with macOS support, or other build configurations targeting Apple platforms.
- What is the deployment target? Metal 4 requires macOS 26+ / iOS 26+.
- Can the build system be extended for Apple targets without diverging from the main branch?
- Some engines have a Windows-based dev environment — Mac Remote Developer Tools for Windows allows building CMake projects from Visual Studio with a Mac as remote target: https://developer.apple.com/documentation/TechnologyOverviews/building-your-macos-game-remotely-from-your-pc
- **Answer:** Does it build for macOS? What build system? Deployment target?

### Platform Layer (Windowing, Input, OS)
- Does the engine have a macOS platform layer? Search for `NSWindow`, `NSView`, `NSApplication`, `UIWindow`, `CAMetalLayer`.
- Is there an iOS/tvOS platform layer?
- **Answer:** macOS platform layer exists? iOS? If missing, this becomes a foundation milestone.

### Content Pipeline
- Are assets pre-cooked for Apple platforms, or is a cooking/conversion step needed?
- Are shaders pre-compiled to metallibs, or does the build system handle shader compilation?
- **Answer:** Content pipeline ready for Apple? Shader pipeline produces Metal output?

### Required Libraries
- Check for metal-cpp if the engine uses C++ (look for `MTL::`, `MTL4::`, metal-cpp headers)
- Check for Metal shader converter if HLSL shaders are used
- **Answer:** metal-cpp present? Metal shader converter present? Any missing dependencies?

### Third-Party Dependencies & Middleware
- Catalog all third-party libraries the engine uses. For each one, determine Apple platform availability:
  - **Available on Apple** — has a macOS/iOS build or is cross-platform (e.g., zlib, stb, SDL)
  - **Has Apple SDK** — vendor provides an Apple platform version (e.g., FMOD, Wwise, Havok)
  - **No Apple version** — must be replaced, wrapped, or stubbed (e.g., XAudio2, DirectInput, platform-specific DRM)
- Catalog middleware: audio, video, networking, physics, anti-cheat, DRM — portability of each.
- For dependencies with no Apple version: can they be stubbed for initial milestones without breaking the main loop? Or are they init-order dependencies that block startup?
- **Answer:** Full dependency list with Apple platform status. Which can be stubbed? Which are blockers?

## Graphics Backend Analysis (12-Point)

### 1. Existing Backend Implementations
- Identify all existing graphics backends (D3D12, Vulkan, Metal 3, OpenGL, console-specific)
- How is the backend selected? (build-time, runtime, plugin system?)
- Where do backend implementations live in the codebase?
- **Answer:** Which backends exist? How are they organized?

### 2. Graphics API Abstraction
- How does the engine abstract the graphics API? (virtual interface class, free-function namespace, template-based, thin wrapper?)
- Identify key abstraction types: device, command buffer/list, pipeline state, buffer, texture, sampler, descriptor set, render pass, swap chain, fence/semaphore
- **If no abstraction exists** (single-API codebase with raw API calls throughout): flag as a **key decision** for goal planning. The porting strategy (abstraction layer, thin shim, direct replacement) significantly affects milestone structure.
- **Answer:** What abstraction pattern? What are the key types? If none, note "No abstraction — single-API codebase."

### 3. Shader Source Language
- Search for `.hlsl`, `.glsl`, `.metal` files
- Check for custom shading language or shader DSL
- **Answer:** HLSL / GLSL / MSL / Custom DSL / Mixed?

### 4. Shader Compilation Pipeline
- Search for DXC, SPIRV-Cross, Metal shader converter, `metallib` references
- Pre-compiled or runtime compilation?
- **Answer:** What produces Metal-consumable shader output?

### 5. Existing Metal Backend
- Search for `MTL::`, `id<MTL`, `@import Metal`, `#import <Metal/Metal.h>`
- Metal 3 vs Metal 4 usage (`MTL4::` or `MTL4` protocols)
- **Answer:** Metal 3 exists? Metal 4 started? No Metal backend?

### 6. Resource Binding Model
- How are resources bound to shaders? (per-draw, argument buffers, bindless, descriptor heaps/sets?)
- Binding index conventions or partitions? If not discoverable, note as something to ask the user.
- **Answer:** Binding model? Index partitioning conventions?

### 7. Render Graph / Frame Graph
- Search for "render graph", "frame graph", "pass dependency", "render pass builder"
- How are passes ordered and dependencies tracked?
- Does it handle resource transitions/barriers?
- **Answer:** Has render graph? How are dependencies and barriers expressed?

### 8. Synchronization Model
- Explicit state transitions (D3D12-style), pipeline barriers (Vulkan-style), or implicit tracking?
- Where are barriers issued? (render graph, command recording, abstracted?)
- **Answer:** Explicit or implicit? Where are barriers managed?

### 9. Threading Model
- Single render thread? Parallel command encoding? Worker threads for resource loading?
- **Answer:** How are command buffers created and submitted? Parallel encoding?

### 10. Memory Management
- Custom allocators, pool allocators, ring buffers, frame-delayed destruction?
- Are renderer structs allocated with C allocators or C++ `new`?
- **Answer:** Custom allocators? Deferred destruction? How are GPU struct lifetimes managed?

### 11. Language Conventions & Engine Libraries
- What language(s)? (C, C++, ObjC, ObjC++, mixed)
- Custom containers vs STL? Custom strings? Custom IO? Custom threading primitives? Custom allocators? Custom assert macros? Custom logging?
- **Answer:** What standard library usage exists? What custom implementations must the agent follow? The agent must match the engine's conventions — do not introduce STL types or foreign patterns.

### 12. ObjC / ARC Usage (if Metal backend exists)
- ARC enabled or manual retain/release? (check `-fobjc-arc` / `-fno-objc-arc`)
- `@autoreleasepool`, `NS::AutoreleasePool`, `NS::TransferPtr`, `NS::RetainPtr` usage?
- **Answer:** ARC or manual? metal-cpp RAII used?

## Feature Coverage Matrix

Catalog the full backend API surface to understand scope.

### Backend Function Inventory
Using an existing backend (preferably D3D12 or Vulkan), catalog all functions/methods the backend implements. Group by feature domain: device/init, resource creation (buffers, textures, samplers, render targets), command encoding (draw, dispatch, copy), pipeline state, descriptor binding, synchronization, queries, presentation, debug markers, compute, raytracing.

### Feature Domain Summary
Produce a summary table with function counts per domain. Note which domains are essential vs optional for initial goals.

## Platform Gap Analysis

Source → Apple platform mapping. Point to domain skills where they exist; provide inline guidance for domains without skills.

- **Windowing**: Win32/HWND → NSWindow/UIWindow — see `setting-up-macos-window` skill
  - [Managing your game window for Metal in macOS](https://developer.apple.com/documentation/metal/managing-your-game-window-for-metal-in-macos?language=objc)
- **Graphics**: DirectX/Vulkan/OpenGL → Metal 4 — see Metal 4 domain skills
- **Shaders**: (HLSL → DXIL) → Metal IR via Metal shader converter
  - [Metal shader converter](https://developer.apple.com/metal/shader-converter/)
- **Input**: XInput/DirectInput/Raw Input → GCController/GCMouse/GCKeyboard — see `using-game-controller` skill
- **Audio**: XAudio2/FMOD/Wwise → AVAudioEngine or platform-specific middleware build
  - FMOD and Wwise have Apple platform SDKs — check version compatibility
  - XAudio2 has no Apple equivalent; replace with AVAudioEngine: https://developer.apple.com/documentation/avfaudio/avaudioengine?language=swift
- **Threading**: Win32 threads → pthreads / GCD
  - Use QoS classes for thread prioritization, `os_unfair_lock` or `pthread_mutex_t` for mutual exclusion
  - Scale thread count via `sysctl` (`hw.perflevel0.logicalcpu` / `hw.perflevel1.logicalcpu`)
  - Every thread touching Metal/ObjC must have `@autoreleasepool`
  - [Tune CPU job scheduling for Apple silicon games](https://developer.apple.com/videos/play/tech-talks/110147/)
- **File system**: backslashes → forward slashes, drive letters → relative/bundle paths, case sensitivity (macOS default case-insensitive, iOS case-sensitive)
- **Dynamic libraries**: DLL → dylib/framework. `LoadLibrary`/`GetProcAddress` → `dlopen`/`dlsym`
- **Entry point**: WinMain → main (or `NSApplicationMain` / `UIApplicationMain`)

## Practical Porting Advice

Patterns proven across multiple ports. Only include items relevant to the specific codebase in the discovery report.

### Stubbing strategy
Stub subsystems behind preprocessor defines so they can be re-enabled individually:
```c
#define STUB_AUDIO      1
#define STUB_NETWORK    1
#define STUB_VIDEO      1
#define STUB_RENDERER   1
```
Stub: audio, networking, video playback, unavailable middleware, and the renderer (replace with clear). **Do not stub input** — plan for at least one input method.

### Build system mergeability
Port the build system so it stays mergeable with the main branch and all existing platform targets. Add Apple support alongside, don't replace.

### Code signing
Ad-hoc codesign for development: `codesign -s - --force --deep <executable>`

### Display resolution
Start with fixed 1920x1080 (macOS) or a fixed resolution the game already supports (iOS). No dynamic scaling early on.

### CPU memory simplification
If the engine has complex custom allocators, consider routing through `malloc` initially — it works well on Apple platforms for all sizes. Revisit after milestones.

### Threading simplification
For initial milestones, evaluate constraining gameplay and rendering to a single thread to avoid race conditions. Multi-threaded rendering re-enabled after first milestones.

### ObjC/C++ boundary
ObjC code cannot be included in `.cpp` files — must be in `.mm` files. Bridge via `extern "C"` or opaque pointers.

**BOOL typedef conflict:** On arm64 macOS, ObjC defines `BOOL` as `bool`. If platform stubs define `typedef int BOOL`, this causes redefinition errors. Use `typedef bool BOOL` with an `#ifndef` guard.

## Risk Assessment

Flag what will be hard or could block progress:

- **Middleware with no Apple platform version** — can be a showstopper
- **Shader complexity** — number and complexity of shaders, HLSL → Metal IR scope
- **Inline assembly** — needs manual rewrite
- **Platform-specific SIMD intrinsics** — SSE typically maps cleanly via `sse2neon`; AVX and hot paths need review
- **Custom memory allocators tied to Win32 APIs** — VirtualAlloc, HeapCreate, etc.
- **Threading model assumptions** — fibers, custom thread pools, Win32-specific threading
- **File I/O assumptions** — case-insensitive paths, backslashes, drive letters
- **Anti-cheat / DRM** — usually a blocker, needs platform-specific solution or removal

## Dependency Graph

Map what blocks what for this specific game:

- Minimum set of subsystems needed for the main loop to run?
- Which subsystems can be stubbed independently?
- What depends on the renderer vs what is independent?
- Init-order dependencies that will cause problems?
- Does the asset pipeline need to work before the main loop can load?

## Scope Estimation

- How many source files touch platform APIs directly?
- How many third-party libs need replacement vs recompile?
- How much code is behind a platform abstraction vs raw API calls?
- How large is the asset pipeline and what does it depend on?
