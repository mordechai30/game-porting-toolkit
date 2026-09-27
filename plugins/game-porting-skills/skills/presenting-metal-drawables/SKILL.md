---
name: presenting-metal-drawables
description: ALWAYS use when implementing or debugging the Metal drawable presentation contract — `CAMetalLayer` configuration, drawable lifecycle (`nextDrawable`, `waitForDrawable`, `signalDrawable`, `present`), vsync (`displaySyncEnabled`), `CAMetalDisplayLink`, HDR/EDR layer setup, direct-to-display vs composited, or drawable-residency-set rules. Trigger for CAMetalLayer, CAMetalDrawable, nextDrawable, signalDrawable, waitForDrawable, displaySyncEnabled, presentAfterMinimumDuration, drawableSize, framebufferOnly, wantsExtendedDynamicRangeContent, EDR headroom, ProMotion, swap chain port, "blank window", "vsync not working". Do NOT trigger for render-thread / run-loop / resize / fullscreen integration on macOS — use `setting-up-macos-window`. General `MTLResidencySet` semantics — use `managing-metal4-resources`. Cross-API translation tables for non-presentation APIs — use `translating-to-metal4-api`. For dual-frame presentation via a present thread — use `using-metalfx-frame-interpolation`.
---

# Metal 4 Presentation & Frame Pacing

## Overview

Metal 4 splits the cmd-buffer-level `[cmd presentDrawable:]` into a queue-level sequence: `[queue waitForDrawable:]` before commit, `[queue signalDrawable:]` after commit, and `[drawable present]`. The conceptual flow — acquire drawable, encode, present, submit — is unchanged; only the API surface is more explicit. `MTL4CommandBuffer` does not expose `presentDrawable:`, so any code path using `MTL4CommandQueue` must use the queue-level form. Code paths still using the Metal 3 `MTLCommandQueue` keep `[cmd presentDrawable:]` and remain correct in a Metal 4 app.

## Ownership

**Owns:**
- Drawable lifecycle (`nextDrawable`, `waitForDrawable`, `signalDrawable`, `present`)
- `CAMetalLayer` configuration and properties
- Vsync semantics (`displaySyncEnabled`, `presentAfterMinimumDuration:`)
- `CAMetalDisplayLink` API basics; variable refresh rate detection
- HDR/EDR layer configuration; pixel format ↔ colorspace pairing
- Direct-to-display vs composited presentation rules
- Drawable residency set (the layer-owned read-only `residencySet`)
- Apply-after-present rule

**Doesn't own:**
- Render-thread / run-loop / fullscreen / resize integration → `setting-up-macos-window`
- General `MTLResidencySet` semantics → `managing-metal4-resources`
- Cross-API translation tables for non-presentation APIs → `translating-to-metal4-api`
- Engine-internal frame pacing on a dedicated render thread → `setting-up-macos-window`
- MetalFX-driven dual-frame presentation → `using-metalfx-frame-interpolation`

## References

**Read the relevant framework header before writing presentation code** — the headers are the source of truth for property names, types, and method signatures.

- QuartzCore framework headers - `$(xcrun --show-sdk-path)/System/Library/Frameworks/QuartzCore.framework/Headers/CAMetalLayer.h` — declares both `CAMetalLayer` and the `CAMetalDrawable` protocol
- Apple documentation - [CAMetalLayer](https://developer.apple.com/documentation/quartzcore/cametallayer)
- Apple documentation - [Managing your game window for Metal in macOS](https://developer.apple.com/documentation/metal/managing-your-game-window-for-metal-in-macos)
- Apple documentation - [Metal Performance HUD](https://developer.apple.com/documentation/xcode/monitoring-your-metal-apps-graphics-performance)

## Design Patterns

### macOS Rendering Stack

```
NSWindow
  └── NSView (engine's view subclass)
        └── CAMetalLayer (backing layer)
              └── CAMetalDrawable (per-frame drawable texture)
```

The engine typically owns the window and view. The Metal backend configures the `CAMetalLayer` and acquires drawables from it each frame.

### CAMetalLayer Configuration

```objc
// ObjC
CAMetalLayer* metalLayer = (CAMetalLayer*)view.layer;
metalLayer.device = device;
metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;  // must match pipeline output; affects direct vs composited presentation
metalLayer.drawableSize = CGSizeMake(width, height);
metalLayer.maximumDrawableCount = 2;                 // or 3 for triple buffering
metalLayer.framebufferOnly = YES;                    // enables GPU compression, no readback
metalLayer.opaque = YES;

// macOS only
metalLayer.displaySyncEnabled = enableVsync;         // sole vsync control

```

**Key properties:**
- `pixelFormat` — must match render pipeline color attachment format
- `drawableSize` — update when window resizes
- `maximumDrawableCount` — 2 (double buffering) or 3 (triple buffering). Controls pipeline depth.
- `framebufferOnly` — set YES unless you need to read back the drawable texture. Enables GPU compression.
- `displaySyncEnabled` — the sole vsync control. YES = cap to display refresh rate. NO = uncapped.

### Presentation flow (Metal 4 queue-level)

The per-frame presentation sequence:

```objc
// ObjC — Metal 4 queue-level presentation

// 1. Acquire drawable (CPU-side block until a drawable is available)
id<CAMetalDrawable> drawable = [metalLayer nextDrawable];

// 2. Encode render commands into MTL4CommandBuffer(s)
//    ... encode render commands ...

// 3. GPU-side wait for drawable's backing texture to be released by display
//    (must be before commit, but encoding can happen before the wait)
[queue waitForDrawable:drawable];

// 4. Submit GPU work
[queue commit:cmds count:count];

// 5. Signal that GPU work targeting this drawable is complete
[queue signalDrawable:drawable];

// 6. Present — the layer handles timing based on displaySyncEnabled
[drawable present];
```

**Acquiring the drawable** — choose one of two schemes:

*Scheme A — minimum latency:* acquire the drawable at frame start, present at frame end. Simplest; the GPU may idle waiting for previous-frame work to drain before this frame's drawable becomes available.

```objc
// Frame start
id<CAMetalDrawable> drawable = [metalLayer nextDrawable];
[queue waitForDrawable:drawable];
// Encode all GPU work targeting the drawable
[queue commit:cmds count:count];
[queue signalDrawable:drawable];
[drawable present];
```

*Scheme B — early GPU submission:* commit work that doesn't depend on the drawable before calling `nextDrawable`/`waitForDrawable`. The GPU stays busy on independent work while the drawable becomes available.

```objc
// Encode + commit work that does NOT depend on the drawable (shadow maps, GPU culling, etc.)
[queue commit:earlyCmds count:earlyCount];
// Now acquire the drawable — the GPU is already working
id<CAMetalDrawable> drawable = [metalLayer nextDrawable];
[queue waitForDrawable:drawable];
// Encode + commit drawable-dependent work
[queue commit:lateCmds count:lateCount];
[queue signalDrawable:drawable];
[drawable present];
```

**Key points:**
- `nextDrawable` is a **CPU-side block** — it waits until a drawable is available from the pool.
- `waitForDrawable` is a **GPU-side wait** — ensures the drawable's backing texture is released by the display before the GPU writes to it. Place before `commit`, but encoding can happen before the wait.
- `signalDrawable` + `present` is the Metal 4 queue-level form of `[cmd presentDrawable:]`. The conceptual sequence is identical; the API surface differs.
- Always use plain `[drawable present]` — the layer's `displaySyncEnabled` controls timing.
- **Do not hold strong references to drawables longer than necessary.** Release drawables as soon as possible — holding them prevents the system from recycling them, which can starve the drawable pool.

### Converting from Metal 3 cmd-buffer form

The Metal 3 cmd-buffer pattern (`nextDrawable` → encode → `[cmd presentDrawable:]` → `[cmd commit]`) translates mechanically to the queue-level form:

| Metal 3 (`MTLCommandBuffer`) | Metal 4 (`MTL4CommandQueue`) |
|---|---|
| `[cmd presentDrawable:drawable]` then `[cmd commit]` | `[queue waitForDrawable:drawable]` before commit → `[queue commit:cmds]` → `[queue signalDrawable:drawable]` → `[drawable present]` |
| `[cmd presentDrawable:drawable afterMinimumDuration:d]` | `[queue signalDrawable:drawable]` → `[drawable presentAfterMinimumDuration:d]` |

Both `present` and `presentAfterMinimumDuration:` are declared on `MTLDrawable`, which `CAMetalDrawable` conforms to. `waitForDrawable:` is part of the queue-level scheme only — do not call it alongside `[cmd presentDrawable:]`.

### Vsync Control

`displaySyncEnabled` on `CAMetalLayer` is the **sole vsync control**:

```objc
// Enable vsync — frame rate caps to display refresh rate
metalLayer.displaySyncEnabled = YES;

// Disable vsync — frame rate uncapped (limited by drawable pool size)
metalLayer.displaySyncEnabled = NO;
```

**Toggling at runtime:**
```objc
// Toggle vsync at runtime
vsyncEnabled = !vsyncEnabled;
metalLayer.displaySyncEnabled = vsyncEnabled;
```

### Custom Frame Pacing

For capping frame rate to a specific target (e.g., 30 FPS on a 60Hz display):

```objc
// Present after a minimum duration (frame rate cap)
NSTimeInterval frameDuration = 1.0 / targetFPS;
[drawable presentAfterMinimumDuration:frameDuration];
```

This is for **custom frame rate caps**, not for vsync. Vsync is controlled by `displaySyncEnabled`.

### Variable Refresh Rate Displays and CAMetalDisplayLink

Modern Apple displays support variable refresh rates — Adaptive-Sync on Mac (40–120Hz) and ProMotion on Mac and iPad (24–120Hz). `CAMetalDisplayLink` is the modern way to drive the render loop on macOS, providing display-synced callbacks with presentation timestamps.

Key rules:

- Do not hardcode display refresh rates — query at runtime; the available rate can change with Low Power Mode, thermal throttling, or accessibility settings.
- Use `update.targetPresentationTimestamp` (or `link.targetTimestamp` on `CADisplayLink`) for animation timing — not `timestamp`. `targetTimestamp` stays consistent across frame-rate transitions; `timestamp` causes hitches.
- Present at the highest rate the app can sustain evenly; stay above the display minimum (~40Hz) so the display doesn't fall out of adaptive sync.
- `CAMetalDisplayLink` pre-acquires the drawable and delivers it to the delegate — do not call `[metalLayer nextDrawable]` on this path.

For full setup code (delegate wiring, `preferredFrameLatency`, run-loop integration), variable-refresh-rate detection on macOS and iOS, and frame-rate transition smoothness: see `references/frame-pacing.md`.

For engine integration on a dedicated render thread (run-loop ownership, frame semaphore, switching between vsync-on and vsync-off at runtime): see the `setting-up-macos-window` skill.

### Cross-API Swap Chain Equivalents

| Concept | D3D12 | Vulkan | Metal 4 |
|---|---|---|---|
| Swap chain | `IDXGISwapChain` | `VkSwapchainKHR` | `CAMetalLayer` |
| Back buffer | `ID3D12Resource` (from swap chain) | `VkImage` (from swapchain) | `drawable.texture` |
| Acquire image | Implicit (Present returns next) | `vkAcquireNextImageKHR` | `[layer nextDrawable]` |
| Present | `IDXGISwapChain::Present` | `vkQueuePresentKHR` | `[queue signalDrawable:]` + `[drawable present]` |
| Vsync | `Present(1, 0)` vs `Present(0, 0)` | `VK_PRESENT_MODE_FIFO` vs `MAILBOX`/`IMMEDIATE` | `displaySyncEnabled` on layer |
| Image count | `BufferCount` in desc | `minImageCount` in create info | `maximumDrawableCount` on layer |
| Resize | `ResizeBuffers` | Recreate swapchain | Update `drawableSize` |

### Direct-to-Display vs Composited Presentation

macOS can present Metal content in two modes:
- **Direct-to-display:** The hardware composites the drawable directly to the display with very low overhead, with high-quality upscaling/downscaling. Lowest latency, best performance.
- **Composited:** The window server composites the drawable alongside other UI elements. Higher latency, additional memory bandwidth.

Direct-to-display is preferred for rendering. The Metal HUD (`MTL_HUD_ENABLED=1`) and Instruments can verify which mode is active.

**Requirements for direct-to-display (per Apple documentation):**
- Full-screen mode (use `[window toggleFullScreen:nil]`)
- Opaque `CAMetalLayer` (`metalLayer.opaque = YES`)
- RGB content (all RGB formats supported by Metal layers are capable of direct-to-display)
- There may be additional edge case conditions depending on hardware and system software

```objc
// Minimum setup for direct-to-display eligibility
metalLayer.opaque = YES;
metalLayer.framebufferOnly = YES;  // no readback, enables GPU compression
[window toggleFullScreen:nil];     // enter full-screen mode
```

**Pixel format considerations:**
All RGB formats supported by `CAMetalLayer` are capable of direct-to-display when the above conditions are met. However, HDR formats may have additional constraints in practice — some HDR formats (e.g., extended sRGB, HDR10) may require vsync enabled to qualify for direct presentation. Verify with Metal HUD during development.

```objc
// Standard SDR — directly presentable
metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;

// HDR formats — directly presentable in full-screen, but verify with Metal HUD
metalLayer.pixelFormat = MTLPixelFormatRGBA16Float;       // extended sRGB
metalLayer.pixelFormat = MTLPixelFormatBGR10_XR;          // HDR10
metalLayer.pixelFormat = MTLPixelFormatBGR10_XR_sRGB;     // HDR10 sRGB
```

**Window resize handling:** keep `drawableSize` in sync with the view's backing size, but do not mutate `drawableSize` from `windowDidResize:` if the render thread is separate from the UI thread — a frame that began at the old size can finish against a resized layer, producing glitches or (with `framebufferOnly = YES`) validation failures. The correct pattern is: capture the new backing size on the UI thread, queue it, and apply it on the render thread between frames after in-flight work has drained. For the full render-thread / live-resize / fullscreen-transition implementation, see `setting-up-macos-window`.

**Drawable size does not need to match display size.** The macOS compositor efficiently sends the drawable directly to the display even if the drawable size doesn't match the monitor size — it applies high-quality scaling automatically.

### HDR and Color Space Configuration

The pixel format and `colorspace` on `CAMetalLayer` must be paired correctly, and `wantsExtendedDynamicRangeContent = YES` must be set to enable HDR output. Without it, the OS compositor silently clips values above 1.0 to SDR.

| Output | Pixel format | Colorspace | Transfer function applied by |
|---|---|---|---|
| SDR | `MTLPixelFormatBGRA8Unorm_sRGB` | `kCGColorSpaceSRGB` | hardware (sRGB on write) |
| HDR 10-bit PQ | `MTLPixelFormatBGR10A2Unorm` | `kCGColorSpaceDisplayP3_PQ` | engine shader |
| HDR 16-bit linear | `MTLPixelFormatRGBA16Float` | `kCGColorSpaceExtendedLinearSRGB` | OS compositor |

If the colorspace name contains `_PQ`, the engine shader must write PQ-encoded values. With extended-linear colorspaces, the shader writes linear values and the OS applies the transfer.

For the full pixel-format table (P3 / Rec. 2100 / 16-bit PQ variants), per-platform EDR-headroom queries (macOS `maximumExtendedDynamicRangeColorComponentValue` and iOS `currentEDRHeadroom`), and display-profile-change handling: see `references/hdr-colorspace.md`.

### Render Loop Modes: VSync-On vs VSync-Off

Use different render loop mechanisms depending on whether vsync is enabled:

**VSync-On — use `CAMetalDisplayLink`:**
- The display link pre-acquires a drawable before calling your delegate, so do NOT call `nextDrawable` directly.
- The drawable reflects the layer properties from the *previous* frame — update `drawableSize`/`pixelFormat`/`colorspace` after presenting, not before (apply-after-present rule).
- Set `displaySyncEnabled = YES` on the layer.

**VSync-Off — use a semaphore-based dispatch queue loop:**
- Set `displaySyncEnabled = NO` on the layer.
- Use a serial dispatch queue with a `dispatch_semaphore` (count 2 or 3) to limit in-flight frames.
- Call `nextDrawable` explicitly each frame.
- Use `[drawable presentAfterMinimumDuration:]` to cap frame rate, or `[drawable present]` for uncapped.

For the apply-after-present rule with a code example: see `references/frame-pacing.md`. For a complete dual-path implementation that switches between modes at runtime on a dedicated render thread (`updateFramePacing`, frame semaphore drain, run-loop wiring): see the `setting-up-macos-window` skill.

### Drawable Residency

The `MTLTexture`s backing drawables must be resident before the GPU can render to them. `CAMetalLayer` provides a read-only `residencySet` property that automatically tracks the drawable textures.

```objc
// Queue-level — attach once, covers all command buffers on this queue
[commandQueue addResidencySet:metalLayer.residencySet];

// Or command-buffer-level — attach per frame
[commandBuffer useResidencySet:metalLayer.residencySet];
```

**Key points:**
- The layer's residency set is **read-only** — do not add or remove allocations from it. The layer manages it automatically.
- The set automatically tracks the latest drawable resources.
- For most engines, attaching at the queue level is simplest — it ensures all drawables are always resident.

For general `MTLResidencySet` semantics (creating sets, `addAllocation`/`removeAllocation`, `requestResidency`, the kernel-side `commit()` cost, the per-queue and per-command-buffer 32-set cap, frame-delayed destruction): see `managing-metal4-resources`. The layer's `residencySet` is a specialization of those rules — read-only and auto-managed.

## Anti-Patterns / Common Mistakes

1. **Using `presentAtTime:0` for vsync-off.** This conflicts with `signalDrawable` and breaks frame pacing. Use `displaySyncEnabled = NO` on the layer instead. For standard presentation, plain `[drawable present]` is correct. Use `presentAfterMinimumDuration:` only for custom frame rate caps.

2. **Skipping `waitForDrawable`.** `nextDrawable` blocks on the CPU until a drawable is available, but `waitForDrawable` is a GPU-side wait ensuring the drawable's backing texture is released by the display. Both are needed — removing `waitForDrawable` can cause rendering to a texture still being displayed.

3. **Holding drawable references too long.** Keeping a strong reference to the drawable beyond the present call prevents the display system from recycling it. This starves the drawable pool and can cause stuttering or `nextDrawable` to block indefinitely.

4. **Forgetting to update `drawableSize` on resize.** If the window resizes but `drawableSize` is not updated, rendering will be at the wrong resolution (stretched or cropped).

5. **Not setting `framebufferOnly = YES`.** Unless the engine needs to read back the drawable texture (rare), this should be YES. It enables GPU compression and is a free performance win.

6. **Not making drawable textures resident.** The drawable's backing `MTLTexture`s must be in a residency set before GPU use. Attach `metalLayer.residencySet` to the queue or command buffer — without it, rendering to the drawable can cause GPU faults.

## Debugging Strategies

- **Blank window:** Check drawable count, `waitForDrawable` presence, and whether `signalDrawable` + `present` are both called. White screen often indicates the drawable is never presented or is presented before rendering completes.
- **Frame rate not matching vsync:** Verify `displaySyncEnabled` is being set on the correct `CAMetalLayer` instance. Use Metal HUD (`MTL_HUD_ENABLED=1`) to see actual frame rate. If the difference between vsync on and off is unclear, ask the user to set their display to a lower refresh rate (e.g., 60Hz) where the gap is obvious — the agent cannot change display settings.
- **Stuttering:** Check for frame pacing issues. Use Metal HUD to observe frame time consistency. Verify drawable pool isn't starved (are drawables held too long?). Check if the render loop is display-synced or timer-based.
- **Metal HUD:** `MTL_HUD_ENABLED=1` provides immediate visual feedback on frame rate, GPU time, memory, and present mode (direct vs composited). Add `MTL_HUD_LOG_ENABLED=1` to log per-frame statistics to the console — the agent can parse this output to diagnose frame pacing issues without user interaction. Add `MTL_HUD_ENCODER_TIMING_ENABLED=1` for per-encoder GPU time breakdown.

## Good Practices

- **Always use `[drawable present]`** — let the layer handle timing via `displaySyncEnabled`. Only use `presentAfterMinimumDuration:` for explicit frame rate caps.
- **Keep drawable lifetime short** — acquire at frame start or late in the frame, present at frame end, release immediately after present.
- **Use `@autoreleasepool`** around drawable acquisition and presentation to ensure timely cleanup of temporary ObjC objects.
- **Test vsync at a low refresh rate** (e.g., 60Hz) where the difference between capped and uncapped is obvious. At high refresh rates (144Hz+), the uncapped rate may be close to the refresh rate, making it hard to tell if vsync is working.
- **Use Metal HUD during development** — `MTL_HUD_ENABLED=1` gives immediate visual feedback without adding logging code.
- **Choose drawable count for the workload, not by default.** 2 drawables (double-buffer) caps vsync-off frame rate but minimizes latency; 3 drawables enable deeper pipelining at one extra frame of latency per added drawable. Test against the engine's specific workload before settling.

