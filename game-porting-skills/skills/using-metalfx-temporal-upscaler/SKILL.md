---
name: using-metalfx-temporal-upscaler
description: ALWAYS use when the user wants to add MetalFX temporal upscaling, super-resolution, or upscaling to a Metal app — whether they say "add MetalFX", "add temporal upscaling", "render at lower resolution and upscale", "add DLSS-like upscaling", "add FSR-like upscaling", TAA, motion vectors, jitter pattern, or mention MTLFXTemporalScaler (Metal 3) or MTL4FXTemporalScaler (Metal 4) directly.
---

# Adding MetalFX Temporal Upscaling to a Metal App

This skill walks through integrating `MTLFXTemporalScaler` into an existing Metal rendering application. The scaler renders at a lower resolution and uses motion vectors, depth, and temporal jitter to produce a high-quality upscaled output.

## Prerequisites

- macOS 13.0+ / iOS 16.0+
- Apple Silicon recommended
- `@import MetalFX;` (auto-links with `CLANG_ENABLE_MODULES = YES`)
- The app must already render a 3D scene with a projection matrix and model-view-projection transforms

## Overview of Changes

The integration touches 3 areas:
1. **Shaders** — Add motion vector output (MRT) and subpixel jitter to the vertex shader
2. **Renderer** — Create offscreen render targets, the temporal scaler, and a new 3-pass render flow
3. **Shared types** — Add previous-frame MVP and jitter offset to the per-frame data struct

Read `references/integration-guide.md` for the complete technical reference including API details, texture formats, jitter sequences, motion vector conventions, and troubleshooting.

## Abstraction Strategy

Before starting integration, check if the engine already has a high-level abstraction for temporal upscaling (e.g., from DLSS, FSR, XeSS). If it does, integrate MetalFX through the existing abstraction — follow the same execution paths wherever the APIs are compatible. This makes debugging easier and minimizes the chance for bugs. Only diverge from the existing patterns where MetalFX API differences require it.

If no existing upscaling abstraction exists, ask the developer: introduce a minimal abstraction layer (Recommended — cleaner, easier to maintain and debug), or implement MetalFX directly in the source without abstractions (faster, but harder to extend later)?

## Integration Steps

### Step 1: Understand the existing renderer

Before writing code, identify:
- **Where the projection matrix is built** (need to know FOV, near/far, aspect ratio)
- **Where the model-view-projection matrix is computed** (need to track previous frame's MVP)
- **The render pass structure** (currently renders to drawable? To an offscreen target?)
- **The drawable/color format** (typically BGRA8Unorm_sRGB)
- **Matrix order** When bridging a row-vector matrix library (DirectXMath for example) to Metal's column-vector simd::float4x4, the matrix must be transposed

### Step 2: Add previous MVP and jitter to per-frame data

Add to the shared frame data struct (the struct used by both CPU and shaders):
```c
matrix_float4x4 prevModelViewProjectionMatrix;  // For motion vectors
vector_float2 jitterOffset;                       // Clip-space subpixel jitter
```

### Step 3: Modify shaders for motion vectors

**Vertex shader changes:**
- Compute unjittered clip position: `clipPos = MVP * worldPos`
- Compute previous clip position: `prevClipPos = prevMVP * worldPos`
- Apply jitter: `position = clipPos; position.xy += jitterOffset * clipPos.w`
- Pass both `currentClipPos` and `prevClipPos` to fragment shader

**Fragment shader changes:**
- Change return type to a struct with two outputs: `[[color(0)]]` for color (RGBA16Float) and `[[color(1)]]` for motion (RG16Float)
- Compute motion vector: `prevNDC - currentNDC` (perspective divide both, then subtract)
- The `motionVectorScale` on the scaler converts this NDC delta to pixel displacement
- Apply negative mip bias to all material texture samples — see `references/integration-guide.md` for the formula. Without this, textures appear blurry at the lower render resolution

**Add a fullscreen blit shader** for copying the upscaled output to the drawable:
```metal
vertex FullscreenOut fullscreenVertex(uint vid [[vertex_id]]) {
    FullscreenOut out;
    out.texCoord = float2((vid << 1) & 2, vid & 2);
    out.position = float4(out.texCoord * float2(2, -2) + float2(-1, 1), 0, 1);
    return out;
}
fragment float4 fullscreenFragment(FullscreenOut in [[stage_in]], texture2d<float> tex [[texture(0)]]) {
    constexpr sampler s(min_filter::linear, mag_filter::linear);
    return tex.sample(s, in.texCoord);
}
```

### Step 4: Create offscreen render targets

Render at `displaySize / scaleFactor` (e.g., 2x means half width and half height):

| Texture | Format | Resolution | Usage Flags |
|---------|--------|------------|-------------|
| Color target | RGBA16Float (HDR default; substitute your engine's format if supported) | Render | RenderTarget \| ShaderRead |
| Depth target | Depth32Float | Render | RenderTarget \| ShaderRead |
| Motion target | RG16Float | Render | RenderTarget \| ShaderRead |
| Upscaled output | RGBA16Float (HDR default; substitute your engine's format if supported) | Display | **RenderTarget \| ShaderRead \| ShaderWrite** |

**Critical:** The output texture MUST have `ShaderWrite` because MetalFX writes via internal compute shaders, not as a render target. Missing this causes silent black output with no error.

### Step 5: Create the temporal scaler

```objc
MTLFXTemporalScalerDescriptor *desc = [[MTLFXTemporalScalerDescriptor alloc] init];
desc.inputWidth  = renderWidth;   desc.inputHeight = renderHeight;
desc.outputWidth = displayWidth;  desc.outputHeight = displayHeight;
desc.colorTextureFormat  = MTLPixelFormatRGBA16Float;
desc.depthTextureFormat  = MTLPixelFormatDepth32Float;
desc.motionTextureFormat = MTLPixelFormatRG16Float;
desc.outputTextureFormat = MTLPixelFormatRGBA16Float;
// colorTextureFormat / outputTextureFormat must match your render-target formats; verify with [MTLFXTemporalScalerDescriptor supportsDevice:]

// Metal 3: id<MTLFXTemporalScaler> scaler = [desc newTemporalScalerWithDevice:device];
// Metal 4 (macOS/iOS 26.0+): pass an MTL4Compiler for pipeline state compilation
id<MTL4FXTemporalScaler> scaler = [desc newTemporalScalerWithDevice:device compiler:compiler];
scaler.motionVectorScaleX = renderWidth  * 0.5f;  // NDC→pixel conversion
scaler.motionVectorScaleY = renderHeight * 0.5f;
scaler.inputContentWidth  = renderWidth;
scaler.inputContentHeight = renderHeight;
```

### Step 6: Update the render pipeline descriptor

The scene pipeline must match the offscreen MRT layout:
```objc
pipelineDesc.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA16Float;  // color
pipelineDesc.colorAttachments[1].pixelFormat = MTLPixelFormatRG16Float;    // motion
pipelineDesc.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
pipelineDesc.stencilAttachmentPixelFormat = MTLPixelFormatInvalid;
```

Also create a separate blit pipeline targeting the view's `colorPixelFormat` (typically BGRA8Unorm_sRGB).

### Step 7: Implement the 3-pass render flow

**Per frame:**
1. **Pass 1 — Scene render** to offscreen targets (color + motion + depth) at render resolution
2. **Pass 2 — MetalFX upscale**: set textures, jitter, reset flag, encode to command buffer
3. **Pass 3 — Blit** upscaled output to drawable via fullscreen triangle

**Pass 2 encode call** — the command buffer protocol differs between Metal 3 and Metal 4:
```objc
// Metal 3: [scaler encodeToCommandBuffer:cmdBuf]; // cmdBuf is id<MTLCommandBuffer>
// Metal 4 (macOS/iOS 26.0+): cmdBuf is id<MTL4CommandBuffer>
[scaler encodeToCommandBuffer:cmdBuf];
```
The selector is the same, but the argument type changed from `id<MTLCommandBuffer>` to `id<MTL4CommandBuffer>`. All per-frame properties (textures, `jitterOffsetX/Y`, `motionVectorScaleX/Y`, `inputContentWidth/Height`, `reset`) are identical across both APIs — they live on the shared `MTLFXTemporalScalerBase` protocol.

The jitter must match between what the shader applies and what MetalFX receives:
- Shader gets clip-space jitter: `2*jitterX/renderWidth`, `-2*jitterY/renderHeight`
- MetalFX gets pixel-space jitter: raw Halton values (-0.5 to +0.5)

### Step 8: Implement Halton jitter sequence

```c
static float halton(int index, int base) {
    float result = 0.0f, f = 1.0f / base;
    int i = index;
    while (i > 0) { result += f * (i % base); i /= base; f /= base; }
    return result;
}
// Per frame: jitterX = halton(index+1, 2) - 0.5; jitterY = halton(index+1, 3) - 0.5;
```

Phase count by scale factor: 1.5x→18, 2x→32, 3x→72. Formula: `ceil(8 * scale²)`.

### Step 9: Track previous-frame matrices

Each frame, before computing new matrices:
1. Save current view-projection and model matrices as "previous"
2. Compute `prevModelViewProjectionMatrix = prevVP * prevModel` and store in frame data
3. The shader uses this to compute where each vertex was last frame

### Step 10: Handle resize

When the view size changes, recreate all offscreen textures and the temporal scaler at the new dimensions. Update the projection matrix using render resolution aspect ratio.

## Common Pitfalls

See `references/integration-guide.md` for the full troubleshooting guide. The top issues:

1. **Black output** — Output texture missing `ShaderWrite` usage flag
2. **Screen shaking** — Jitter Y sign wrong (negate for Metal's clip-space Y-up)
3. **Ghosting** — Motion vectors include jitter (they shouldn't) or wrong scale sign
4. **Blurry** — Too few jitter phases for the scale factor, or missing mip bias
5. **Scaler returns nil** — Check `[MTLFXTemporalScalerDescriptor supportsDevice:]`

## If artifacts persist

1. **Consult Apple's reference.** [Applying Temporal Antialiasing and Upscaling Using MetalFX](https://developer.apple.com/documentation/metalfx/applying-temporal-antialiasing-and-upscaling-using-metalfx) — `AAPLRenderer.swift` and `Shaders.metal` for jitter signs, `motionVectorScaleX/Y` signs, and the `prevUV - currentUV` convention. Deviate once you understand why your engine differs.

2. **Build a hotkey-triggered diagnostic dump.** Each dump should include:
   - Render/display dimensions and scale ratio
   - Scaler state: `jitterOffsetX/Y`, `motionVectorScaleX/Y`, `inputContentWidth/Height`, `depthReversed`
   - Camera (current + previous): eye, FOV, `camera.jitter` in both clip and pixel units
   - View / projection / VP matrices for both frames (confirms previous-frame snapshot timing)
   - Last 32–64 frames of `halton - 0.5` alongside the values fed to `camera.jitter` and `scaler.jitterOffset`
   - 5×5(or denser) velocity grid in both UV and pixel units

   Trigger it in the failing situation — static camera (isolates jitter), pure rotation (uniform motion), pure translation (depth-dependent parallax). For interactive cases, ask the developer to trigger the dump while reproducing the artifact. Comparing the three dumps isolates most sign and scale errors directly.

## Verification

Confirm the integration from debug logs:
- **Jitter sequence** — correct values cycling through the expected phase count
- **MetalFX-relevant transformations** — motion vectors and scaler properties are set as expected

The developer must confirm the debug log verification before the integration is considered complete.

If the scene can be rendered with a static camera, capture a GPU frame and inspect the motion vector texture — it should be uniform zero (solid black). Per-geometry color variation indicates non-zero motion vectors, typically from incorrect `prevMVP` or jitter leaking into the motion vector computation.

### Visual Verification

After building and launching the app, verify rendering is working by capturing a screenshot of the app window. This is useful both for self-checking your work and for showing the user what the result looks like.

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
- No obvious artifacts like screen-door patterns (jitter sign wrong) or heavy ghosting (motion vector issue)
- The scene looks sharp despite rendering at lower resolution (MetalFX upscaling is working)
