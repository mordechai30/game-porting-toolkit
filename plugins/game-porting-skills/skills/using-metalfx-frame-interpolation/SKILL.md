---
name: using-metalfx-frame-interpolation
description: ALWAYS use to add MetalFX frame interpolation with a dedicated PresentThread for precise dual-frame presentation to a Metal app. Use this skill when the user wants to add frame interpolation, frame generation, double the framerate, or mentions MTLFXFrameInterpolator (Metal 3) or MTL4FXFrameInterpolator (Metal 4). This skill assumes temporal upscaling is already integrated (use using-metalfx-temporal-upscaler first if not). Also trigger when the user says "add frame gen", "120fps", "interpolate frames", or wants smoother motion.
---

# Adding MetalFX Frame Interpolation to a Metal App

This skill adds MetalFX frame interpolation to a Metal app that already has a MetalFX temporal scaler integrated. The interpolator generates intermediate frames between real rendered frames, effectively doubling the display framerate (e.g., 60fps render → 120fps display).

Two API variants exist:
- **Metal 3** — `MTLFXFrameInterpolator` (macOS 15.0+ / iOS 18.0+)
- **Metal 4** — `MTL4FXFrameInterpolator` (macOS 26.0+ / iOS 26.0+), which inherits from the shared `MTLFXFrameInterpolatorBase` protocol

All per-frame properties are identical across both APIs (they live on `MTLFXFrameInterpolatorBase`). The differences are the creation call, the command buffer type used for encoding, and the support check — see the notes below.

**Prerequisite:** The app must already have MetalFX temporal upscaling working. If not, use the `using-metalfx-temporal-upscaler` skill first.

## Abstraction Strategy

Before starting integration, check if the engine already has a high-level abstraction for frame interpolation (e.g., from DLSS Frame Generation, FSR Frame Gen). If it does, integrate MetalFX through the existing abstraction — follow the same execution paths wherever the APIs are compatible. This makes debugging easier and minimizes the chance for bugs. Only diverge from the existing patterns where MetalFX API differences require it.

If no existing frame interpolation abstraction exists, ask the developer: introduce a minimal abstraction layer (Recommended — cleaner, easier to maintain and debug), or implement MetalFX directly in the source without abstractions (faster, but harder to extend later)?

**Important:** When bridging a row-vector matrix library (DirectXMath for example) to Metal's column-vector simd::float4x4, the matrix must be transposed

## Architecture

Frame interpolation uses a dedicated present thread with precise pacing for smooth output:

```
Render thread (MTKView, 60fps)           PresentThread
  │                                        │
  ├─ Scene render → offscreen              │
  ├─ Temporal upscale → back buffer        │
  ├─ Commit command buffer                 │
  ├─ Present(interpolator, queue) ────────►│
  │                                        ├─ Encode frame interpolation
  │   (blocked until consumed)             ├─ Acquire drawable → blit interpolated → present
  │                                        ├─ Wait ~48% frame time (kevent64 timer)
  │◄───────────────────────────────────────├─ Acquire drawable → blit real → present
  │                                        │
```

The PresentThread class from `references/present-thread.md` provides the complete C++ implementation with ObjC wrapper.

## What You Need to Create

### 1. New files
- `AAPLPresentThread.h` — ObjC interface wrapping the C++ PresentThread
- `AAPLPresentThread.mm` — C++ PresentThread class + ObjC wrapper (Objective-C++ file)

### 2. Modified files
- **Renderer** — Add frame interpolator, integrate PresentThread, change render flow
- **Xcode project** — Add new .h/.mm files to all targets

## Integration Steps

### Step 1: Create the PresentThread

Read `references/present-thread.md` for the complete implementation. The class provides:

- **Triple-buffered back buffers** — the temporal scaler writes upscaled output here
- **Encoding thread** — acquires drawables, copies interpolated+real frames, presents
- **Pacing thread** — kevent64 absolute timer for sub-ms precision half-frame timing
- **MTLEvent synchronization** — coordinates GPU work between render and present threads

Create an ObjC wrapper (since the main renderer is .m, not .mm) with this interface:
```objc
@interface AAPLPresentThread : NSObject
- (instancetype)initWithMinDuration:(float)minDuration
                         metalLayer:(CAMetalLayer *)layer
                            library:(id<MTLLibrary>)library;
- (void)startFrame:(id<MTLCommandBuffer>)commandBuffer;
- (id<MTLTexture>)getBackBuffer;
- (void)present:(id<MTLFXFrameInterpolator>)interpolator queue:(id<MTLCommandQueue>)queue;
// Metal 4 equivalent: - (void)present:(id<MTL4FXFrameInterpolator>)interpolator queue:(id<MTL4CommandQueue>)queue;
- (void)resize:(uint32_t)width height:(uint32_t)height pixelFormat:(MTLPixelFormat)format;
- (void)drainPendingPresents;
@end
```

**Important:** The header must use `#import <Metal/Metal.h>` etc., NOT `@import MetalFX;` — the latter fails when included from C++ compilation units.

### Step 2: Create the frame interpolator

```objc
MTLFXFrameInterpolatorDescriptor *desc = [[MTLFXFrameInterpolatorDescriptor alloc] init];
desc.inputWidth  = renderWidth;   desc.inputHeight = renderHeight;
desc.outputWidth = displayWidth;  desc.outputHeight = displayHeight;
desc.colorTextureFormat  = MTLPixelFormatRGBA16Float;
desc.depthTextureFormat  = MTLPixelFormatDepth32Float;
desc.motionTextureFormat = MTLPixelFormatRG16Float;
desc.outputTextureFormat = MTLPixelFormatRGBA16Float;

// Metal 3: id<MTLFXFrameInterpolator> interpolator = [desc newFrameInterpolatorWithDevice:device];
// Metal 4 (macOS/iOS 26.0+): pass an MTL4Compiler for pipeline state compilation
id<MTL4FXFrameInterpolator> interpolator = [desc newFrameInterpolatorWithDevice:device compiler:compiler];
```

Set these properties once (not per-frame):
```objc
interpolator.fieldOfView = fovDegrees;   // e.g., 65.0
interpolator.nearPlane = nearZ;           // e.g., 1.0
interpolator.farPlane = farZ;             // e.g., 5000.0
interpolator.aspectRatio = aspect;        // render width / render height
```

Set these per-frame before `Present()`:
```objc
interpolator.depthTexture = depthTarget;
interpolator.motionTexture = motionTarget;
// Before assigning jitterOffsetX/Y, consult with the rest of the pipeline
// (temporal upscaling if present) whether this is necessary and in which
// space the jitter needs to be defined at that stage.
interpolator.jitterOffsetX = jitterX;
interpolator.jitterOffsetY = jitterY;
interpolator.motionVectorScaleX = renderWidth * 0.5f;
interpolator.motionVectorScaleY = renderHeight * 0.5f;
```

Note: `MTLFXFrameInterpolator` does NOT have a `reset` property. History management is internal.

### Step 3: Modify the render flow

**Old flow (temporal upscaling only):**
1. Render scene to offscreen
2. Temporal upscale → `_upscaledOutput`
3. Blit `_upscaledOutput` to drawable
4. Present drawable

**New flow (with frame interpolation):**
1. `[_presentThread startFrame:commandBuffer]` — sync with present thread
2. Render scene to offscreen (unchanged)
3. Temporal upscale → `[_presentThread getBackBuffer]` (NOT your own output texture)
4. Commit the command buffer (PresentThread needs the GPU work done)
5. Set per-frame interpolator properties (depth, motion, jitter, MV scale)
6. `[_presentThread present:_frameInterpolator queue:_commandQueue]` — this encodes interpolation + handles dual presentation
7. **Remove** all `presentDrawable:` and blit-to-drawable code — PresentThread handles it

Key changes:
- Temporal scaler `outputTexture` = `_presentThread.getBackBuffer` (PresentThread manages its own triple-buffered textures)
- You no longer need `_upscaledOutput` or `_blitPipelineState` — PresentThread has its own copy pipeline
- You no longer call `[commandBuffer presentDrawable:]` — PresentThread acquires drawables and presents

### Step 4: Initialize PresentThread

In `loadMetal:`:
```objc
CAMetalLayer *metalLayer = (CAMetalLayer *)view.layer;
metalLayer.maximumDrawableCount = 3;  // Required for dual presentation
id<MTLLibrary> library = [_device newDefaultLibrary];
_presentThread = [[AAPLPresentThread alloc] initWithMinDuration:1.0f/120.0f
                                                     metalLayer:metalLayer
                                                        library:library];
```

On resize, call `[_presentThread resize:width height:height pixelFormat:format]`.

### Step 5: Handle the Resize guard

The PresentThread's `Resize()` must guard against zero dimensions (the metal layer may report 0x0 before the first layout pass):
```cpp
void Resize(uint32_t width, uint32_t height, MTLPixelFormat pixelFormat) {
    if (width == 0 || height == 0) return;  // Guard against pre-layout calls
    // ... create textures ...
}
```

## PresentThread Internals

The PresentThread uses a sophisticated dual-thread model for precise frame pacing:

**PresentThreadFunction** (encoding thread):
- Waits for work from `Present()`
- Acquires drawable, copies interpolated frame from `m_interpolationOutputs`, presents
- Acquires second drawable, copies real frame from `m_backBuffers`, presents
- Uses MTLEvent to ensure GPU work ordering

**PacingThreadFunction** (pacing thread):
- Uses `kqueue` + `kevent64` with `NOTE_MACHTIME | NOTE_ABSOLUTE` for sub-ms timer precision
- Calculates timestamp at ~48% of frame interval: `time + (delta * 31) >> 6`
- Signals `MTLSharedEvent` to gate the second present

**Present()** (called from render thread):
- Configures interpolator's `colorTexture` (current back buffer) and `prevColorTexture` (previous back buffer)
- Encodes interpolation to command buffer
- Manages frame-in-flight count (max 2)
- Advances triple buffer index

## Texture Usage Flags

All PresentThread textures:
- Back buffers: `ShaderRead | ShaderWrite | RenderTarget`
- Interpolation outputs: `ShaderRead | RenderTarget`
- Interpolation inputs: `ShaderRead | RenderTarget`
- All use `MTLPixelFormatRGBA16Float` and `StorageModePrivate`

## Troubleshooting

- **Crash on launch (zero-size textures)**: Add zero-dimension guard in `Resize()`
- **Deadlock**: Ensure `Present()` is called from the render thread, not the present thread
- **Black frames**: Verify temporal scaler output goes to `getBackBuffer()`, not a separate texture
- **Frame interpolator returns nil**: Check OS version and device support. Metal 3: `+[MTLFXFrameInterpolatorDescriptor supportsDevice:]` (macOS 15.0+ / iOS 18.0+). Metal 4: `+[MTLFXFrameInterpolatorDescriptor supportsMetal4FX:]` (macOS/iOS 26.0+) — a distinct class method that checks Metal 4 compatibility.
- **`@import` errors in .mm file**: Use `#import <Metal/Metal.h>` etc. in the header, not `@import`

## Verification

Confirm the integration from debug logs:
- **Frame interpolation** — debug logs confirm interpolation is happening each frame

The developer must confirm the debug log verification before the integration is considered complete.

### Visual Verification

After building and launching the app, verify rendering is working by capturing a screenshot of the app window. If possible closest match vs non-upscaled. This is useful both for self-checking your work and for showing the user what the result looks like.

**Capture the app window** (not the full screen — just the window):

```bash
# Find the main content window by app name, filtering for the largest window
APP_NAME="MyApp"  # Replace with the actual app/process name
WID=$(python3 -c "
import Quartz
for w in Quartz.CGWindowListCopyWindowInfo(Quartz.kCGWindowListOptionAll, Quartz.kCGNullWindowID):
    if '$APP_NAME' in w.get('kCGWindowOwnerName', ''):
        b = w.get('kCGWindowBounds', {})
        if b.get('Height', 0) > 100:
            print(w['kCGWindowNumber']); break
")
screencapture -x -o -l "$WID" /tmp/mfx_screenshot.png
```

Then view the screenshot at `/tmp/mfx_screenshot.png`. Look for:
- The 3D scene is visible (not black, not a blank window)
- Motion looks smooth — with frame interpolation, camera pans and object movement should appear fluid
- No obvious artifacts like ghosting on moving objects or tearing between interpolated and real frames
