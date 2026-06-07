# Render Loop Implementation Detail

Engine-side render-loop wiring — dual render paths, frame pacing, in-flight frame limiting, and the apply-after-present mechanism. The drawable contract and `CAMetalDisplayLink` API surface are covered in this skill's SKILL.md.

## Table of Contents

- [Dual Render Loop Paths](#dual-render-loop-paths)
- [Updating Frame Pacing at Runtime](#updating-frame-pacing-at-runtime)
- [startRenderLoop / stopRenderLoop](#startrenderloop--stoprenderloop)
- [shutdownRenderThread](#shutdownrenderthread)
- [renderWithDrawable: — The Shared Render Helper](#renderwithdrawable--the-shared-render-helper)
- [renderFrame (Timer Path)](#renderframe-timer-path)
- [In-Flight Frame Limiting](#in-flight-frame-limiting)
- [Apply-After-Present Rule](#apply-after-present-rule)
- [buildDrawableParameters](#builddrawableparameters)
- [applyDrawableParameters:](#applydrawableparameters)
- [Pixel Format / Colorspace Reference](#pixel-format--colorspace-reference)
- [Development Tips](#development-tips)

---

## Dual Render Loop Paths

Implement both, switchable at runtime. The following blocks show each path individually for clarity. In practice, both live inside `updateFramePacing` (shown below), which tears down the current path and rebuilds the correct one. Do not implement these as standalone setup code — `startRenderLoop` calls `updateFramePacing`, which handles all initial setup.

The drawable contract, vsync semantics, the apply-after-present rule, and `CAMetalDisplayLink` API basics live in this skill's SKILL.md. This reference covers only the engine-side wiring (run-loop, frame semaphore, render thread, runtime mode switching).

### VSync on (CAMetalDisplayLink)

```objc
_displayLink = [[CAMetalDisplayLink alloc] initWithMetalLayer:_metalLayer];
_displayLink.delegate = self;
int maxFPS = GetScreenParams().maximumFramesPerSecond;
_displayLink.preferredFrameRateRange = CAFrameRateRangeMake(maxFPS, maxFPS, maxFPS);
// min=preferred=max locks to the display rate. A lower min (e.g. 30) tells the OS it
// may drop to that rate on ProMotion to save power — causing judder even when GPU keeps up.
[_displayLink addToRunLoop:_renderRunLoop forMode:NSRunLoopCommonModes];
```

`CAMetalDisplayLink` delivers the drawable *to* the delegate — do not call `[metalLayer nextDrawable]` in this path. The `update` object also provides `targetTimestamp` and `targetPresentationTimestamp` for frame pacing.

```objc
// CAMetalDisplayLinkDelegate — fires on the render thread
- (void)metalDisplayLink:(CAMetalDisplayLink*)link needsUpdate:(CAMetalDisplayLinkUpdate*)update {
    if (!_renderLoopRunning) return;
    dispatch_semaphore_wait(_frameSemaphore, DISPATCH_TIME_FOREVER);
    id<CAMetalDrawable> drawable = update.drawable;
    if (!drawable) { dispatch_semaphore_signal(_frameSemaphore); return; }
    [self renderWithDrawable:drawable];
}
```

### VSync off (run loop timer)

```objc
#if TARGET_OS_OSX
_metalLayer.displaySyncEnabled = NO;  // without this, layer throttles to refresh rate
#endif
int cap = settings.frameRateCap;
CFTimeInterval interval = (cap > 0) ? 1.0 / (CFTimeInterval)cap : 0.001;
_renderTimer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault,
    CFAbsoluteTimeGetCurrent(), interval, 0, 0,
    ^(CFRunLoopTimerRef timer) { [self renderFrame]; });
CFRunLoopAddTimer([_renderRunLoop getCFRunLoop], _renderTimer, kCFRunLoopCommonModes);
```

`displaySyncEnabled` (macOS only, default `YES`) controls vsync at the layer level. If left enabled, the layer throttles presentation to the display refresh rate even though the timer fires faster, defeating uncapped rendering. `updateFramePacing` handles toggling this property.

The timer interval sets an upper bound on frame rate — the in-flight semaphore in `renderFrame` is the actual throttle. For uncapped rendering (`frameRateCap = 0`), use a small interval (e.g., `0.001` = 1000 Hz ceiling); the semaphore blocks when all 3 frames are queued on the GPU, so real frame rate is determined by GPU completion speed, not timer precision. For capped rendering, set the interval to `1.0 / frameRateCap`. Because the timer interval is baked at creation time, changing `RenderSettings.frameRateCap` requires calling `updateFramePacing` to rebuild the timer — it will not take effect automatically.

---

## displayDidChange

Called on the main thread when the window moves to a different display (`windowDidChangeScreen:`) or the screen's EDR/colorspace capabilities change (`NSScreenColorSpaceDidChangeNotification`). Refreshes the cached EDR headroom and rebuilds frame pacing for the new display's refresh rate.

```objc
- (void)displayDidChange {
    // Called on the main thread — safe to read screen properties directly.
    _cachedEDRHeadroom.store(GetCurrentEDRHeadroom(self.window.screen),
                             std::memory_order_relaxed);
    // Rebuild display link with the new display's maximumFramesPerSecond.
    // Must run on the render thread — dispatch asynchronously.
    [self performSelector:@selector(updateFramePacing)
                 onThread:_renderThread
               withObject:nil
            waitUntilDone:NO];
}
```

The `GameViewController` calls `[_gameView displayDidChange]` from both `windowDidChangeScreen:` and the `NSScreenColorSpaceDidChangeNotification` handler. Do not call `updateFramePacing` directly from the main thread — it must run on the render thread so teardown and new display-link creation are serialized with frame callbacks.

---

## Updating Frame Pacing at Runtime

Call `updateFramePacing` whenever `RenderSettings` changes — vsync toggle, frame rate cap, or preferred frame rate range. It reads the current settings, tears down the active path, and rebuilds the correct one with current values. This eliminates stale parameters (e.g., a `targetFPS` baked into the timer at creation time that no longer matches the user's setting):

```objc
- (void)updateFramePacing {
    RenderSettings& settings = EngineGetRenderSettings();

    // 1. Tear down the current render path
    if (_displayLink) {
        [_displayLink invalidate];
        _displayLink = nil;
    }
    if (_renderTimer) {
        CFRunLoopTimerInvalidate(_renderTimer);
        CFRelease(_renderTimer);
        _renderTimer = NULL;
    }

    // 2. Rebuild the correct path from current settings
    if (settings.vsyncEnabled) {
#if TARGET_OS_OSX
        _metalLayer.displaySyncEnabled = YES;
#endif
        _displayLink = [[CAMetalDisplayLink alloc] initWithMetalLayer:_metalLayer];
        _displayLink.delegate = self;
        int maxFPS = GetScreenParams().maximumFramesPerSecond;
        _displayLink.preferredFrameRateRange = CAFrameRateRangeMake(maxFPS, maxFPS, maxFPS);
        [_displayLink addToRunLoop:_renderRunLoop forMode:NSRunLoopCommonModes];
    } else {
#if TARGET_OS_OSX
        _metalLayer.displaySyncEnabled = NO;
#endif
        int cap = settings.frameRateCap;
        CFTimeInterval interval = (cap > 0) ? 1.0 / (CFTimeInterval)cap : 0.001;
        _renderTimer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault,
            CFAbsoluteTimeGetCurrent(), interval, 0, 0,
            ^(CFRunLoopTimerRef timer) { [self renderFrame]; });
        CFRunLoopAddTimer([_renderRunLoop getCFRunLoop], _renderTimer, kCFRunLoopCommonModes);
    }
}
```

Stop the old path before starting the new one — never let both run simultaneously. `[CAMetalDisplayLink invalidate]` and `CFRunLoopTimerInvalidate` both prevent future callbacks from firing, but they do not block if a callback is currently executing on another thread. To avoid a race between teardown and an in-flight delegate callback, call `updateFramePacing` on the render thread — use `[self performSelector:@selector(updateFramePacing) onThread:_renderThread withObject:nil waitUntilDone:NO]` from the settings UI. When both teardown and callbacks run on the same thread, no concurrent access is possible and the transition is safe. In-flight frames from the old path complete normally; their completion handlers signal the shared semaphore, so the new path's first frame waits naturally if all slots are taken. The render thread's run loop wakes automatically when a new source is added. The game's settings UI should call `updateFramePacing` (dispatched to the render thread) after writing any frame pacing change to `RenderSettings`.

---

## startRenderLoop / stopRenderLoop

`startRenderLoop` reads current `RenderSettings` and kicks off the appropriate path:
```objc
- (void)startRenderLoop {
    _currentDrawableParams = [self buildDrawableParameters];
    _renderLoopRunning = YES;
    [self updateFramePacing];
}
```

`stopRenderLoop` tears down the active path and drains in-flight frames so GPU resources can be safely deallocated afterward:
```objc
- (void)stopRenderLoop {
    if (!_renderLoopRunning) return;  // safe to call twice — viewWillDisappear + dealloc
    _renderLoopRunning = NO;
    if (_displayLink) { [_displayLink invalidate]; _displayLink = nil; }
    if (_renderTimer) {
        CFRunLoopTimerInvalidate(_renderTimer);
        CFRelease(_renderTimer);
        _renderTimer = NULL;
    }

    // Drain in-flight frames — wait for every slot so all GPU work completes.
    // Without this, deallocating the renderer while command buffers are still
    // in flight causes Metal validation errors or hard crashes.
    for (int i = 0; i < MaxBuffersInFlight; i++)
        dispatch_semaphore_wait(_frameSemaphore, DISPATCH_TIME_FOREVER);
    for (int i = 0; i < MaxBuffersInFlight; i++)
        dispatch_semaphore_signal(_frameSemaphore);  // restore count for potential restart
}
```

The `_renderLoopRunning` flag is checked at the top of both `renderFrame` and the `CAMetalDisplayLink` delegate before the semaphore wait. The early return at the top of `stopRenderLoop` makes it safe to call twice — `viewWillDisappear` and `dealloc` both call it, and without the guard the second call deadlocks (the drain loop waits for GPU signals that will never arrive because rendering already stopped). The drain loop acquires all semaphore slots, blocking until every in-flight command buffer has completed and signaled. The restore loop returns the semaphore to its initial count so `startRenderLoop` can be called again without deadlocking. Always call `stopRenderLoop` before `EngineShutdownRenderer()` in the shutdown sequence.

---

## shutdownRenderThread

`stopRenderLoop` stops rendering but leaves the thread alive for potential restart. `shutdownRenderThread` tears down the thread itself — call it only during final dealloc:
```objc
- (void)shutdownRenderThread {
    _shouldStopRenderThread = YES;
    CFRunLoopStop([_renderRunLoop getCFRunLoop]);
    while (![_renderThread isFinished])
        [NSThread sleepForTimeInterval:0.001];
    _renderThread = nil;
    _renderRunLoop = nil;
}
```
`CFRunLoopStop` wakes the thread from `runMode:beforeDate:`, the while loop exits because `_shouldStopRenderThread` is true, and the thread block returns. The brief spin-wait is safe — the thread exits within microseconds of the flag being set.

Both `CAMetalDisplayLink` and the run loop timer fire on the same dedicated render thread — the engine always sees the same thread regardless of vsync mode, so thread assertions and thread-local state work correctly across switches.

---

## renderWithDrawable: — The Shared Render Helper

Both the delegate (vsync-on) and `renderFrame` (vsync-off) call this after acquiring a drawable and waiting on the semaphore. This is the single method that drives all rendering.

### Default pattern — platform owns queue and present

Uses `EngineRenderFrame` declared in Phase 5:

```objc
- (void)renderWithDrawable:(id<CAMetalDrawable>)drawable {
    // Apply pending resize on the render thread where we own GPU resources
    if (_resizePending.exchange(false)) {
        GetScreenParams().pixelSize = CGSizeMake(_pendingWidth, _pendingHeight);
        float scale = GetScreenParams().contentScale;
        GetScreenParams().pointSize = CGSizeMake(_pendingWidth / scale,
                                                  _pendingHeight / scale);
        // Placeholder — engine rebuilds depth buffers, MSAA targets, and other resolution-dependent GPU resources.
        EngineOnResize(_pendingWidth, _pendingHeight);
    }

    DrawableParameters params = _currentDrawableParams;

    // Engine returns the final command buffer without committing it
    id<MTLCommandBuffer> finalCommandBuffer = EngineRenderFrame(_commandQueue, drawable, params);
    if (!finalCommandBuffer) { dispatch_semaphore_signal(_frameSemaphore); return; }

    // Signal semaphore when GPU finishes — must be added before commit
    dispatch_semaphore_t sema = _frameSemaphore;
    [finalCommandBuffer addCompletedHandler:^(id<MTLCommandBuffer> cb) {
        dispatch_semaphore_signal(sema);
    }];
    [finalCommandBuffer presentDrawable:drawable];
    [finalCommandBuffer commit];

    // Update layer properties for next frame (after present, never before acquire)
    DrawableParameters desired = [self buildDrawableParameters];
    if (params != desired) {
        [self applyDrawableParameters:desired];
        _currentDrawableParams = desired;
    }
}
```

> **Implementation note:** Choose one of these two `renderWithDrawable:` patterns and delete the other. They are mutually exclusive — both implement the same method. The default pattern is simpler; use the alternative only if the engine manages its own `MTLCommandQueue`.

### Alternative — engine owns its own command queue and presentation

Some engines manage their own `MTLCommandQueue` and call `presentDrawable:` + `commit` internally. In this case, the platform layer passes the drawable and a completion callback instead. The alternative `EngineRenderFrame` overload takes `(drawable, params, onComplete)` — declare it alongside the default overload in Phase 5.

```objc
- (void)renderWithDrawable:(id<CAMetalDrawable>)drawable {
    if (_resizePending.exchange(false)) {
        GetScreenParams().pixelSize = CGSizeMake(_pendingWidth, _pendingHeight);
        float scale = GetScreenParams().contentScale;
        GetScreenParams().pointSize = CGSizeMake(_pendingWidth / scale,
                                                  _pendingHeight / scale);
        EngineOnResize(_pendingWidth, _pendingHeight);
    }

    DrawableParameters params = _currentDrawableParams;
    dispatch_semaphore_t sema = _frameSemaphore;
    EngineRenderFrame(drawable, params, ^{
        dispatch_semaphore_signal(sema);
    });

    DrawableParameters desired = [self buildDrawableParameters];
    if (params != desired) {
        [self applyDrawableParameters:desired];
        _currentDrawableParams = desired;
    }
}
```

Choose one pattern based on how much control the engine needs. The default pattern is simpler — the platform layer handles present/commit and the semaphore completion handler in one place. The alternative gives the engine full control over command queue management and presentation timing.

---

## renderFrame (Timer Path)

```objc
- (void)renderFrame {
    if (!_renderLoopRunning) return;
    dispatch_semaphore_wait(_frameSemaphore, DISPATCH_TIME_FOREVER);
    id<CAMetalDrawable> drawable = [_metalLayer nextDrawable];
    if (!drawable) { dispatch_semaphore_signal(_frameSemaphore); return; }
    [self renderWithDrawable:drawable];
}
```

The only difference from the delegate path is how the drawable is acquired — `[_metalLayer nextDrawable]` here vs `update.drawable` above. Everything else flows through `renderWithDrawable:`. `nextDrawable` blocks until a drawable is available (up to ~1 second). If all drawables are in-flight — the GPU is behind — it returns nil. The nil check signals the semaphore and skips the frame; the next frame will usually succeed.

---

## In-Flight Frame Limiting

`_frameSemaphore` (created with `MaxBuffersInFlight = 3`) prevents the CPU from racing ahead of the GPU. The semaphore wait in `renderFrame` and the delegate blocks the render thread if 3 frames are already queued, and the completion handler in `renderWithDrawable:` signals when the GPU finishes each frame. This is what prevents `nextDrawable` from blocking or returning nil — the nil check is a safety net.

---

## Apply-After-Present Rule

`buildDrawableParameters` and `applyDrawableParameters:` run *after* presenting. Layer property changes (`pixelFormat`, `colorspace`, `drawableSize`) only affect the next drawable acquired — applying them before acquiring the next drawable produces undefined results.

For the rule's full explanation and a minimal code example, see `presenting-metal-drawables/references/frame-pacing.md` ("Apply-after-present rule"). The functions below show the engine-side `RenderSettings` plumbing for this skill.

---

## buildDrawableParameters

Combines current `RenderSettings` and `ScreenParameters` into the layer configuration for the next frame:

```objc
- (DrawableParameters)buildDrawableParameters {
    RenderSettings& settings = EngineGetRenderSettings();
    ScreenParameters& screen = GetScreenParams();

    // EDR headroom is maintained by displayDidChange (called from windowDidChangeScreen:
    // and NSScreenColorSpaceDidChangeNotification on the main thread) — read atomically
    // here without any cross-thread dispatch. One-frame staleness is fine; EDR headroom
    // changes on a seconds-to-minutes timescale.
    float edrHeadroom = _cachedEDRHeadroom.load(std::memory_order_relaxed);

    DrawableParameters params;
    params.targetSize = screen.pixelSize;

    if (settings.hdrEnabled && edrHeadroom > 1.0f) {
        params.pixelFormat = MTLPixelFormatBGR10A2Unorm;
        params.hdrHeadroom = edrHeadroom;
    } else {
        params.pixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
        params.hdrHeadroom = 1.0f;
    }

    params.vsyncEnabled = settings.vsyncEnabled;
    return params;
}
```

---

## applyDrawableParameters:

Updates the layer to match the desired configuration:

```objc
// Apply new layer properties when drawable parameters change.
// Called only when buildDrawableParameters returns values different from the current state.
// Do not call this every frame — CGColorSpaceCreateWithName and layer property writes are not free.
- (void)applyDrawableParameters:(DrawableParameters)params {
    _metalLayer.pixelFormat  = params.pixelFormat;
    _metalLayer.drawableSize = params.targetSize;

    RenderSettings& settings = EngineGetRenderSettings();
    CFStringRef csName;
    if (params.hdrHeadroom > 1.0f) {
        csName = (settings.colorGamut == ColorGamut::Rec2020)
            ? kCGColorSpaceITUR_2100_PQ
            : kCGColorSpaceDisplayP3_PQ;
    } else {
        csName = (settings.colorGamut == ColorGamut::DisplayP3)
            ? kCGColorSpaceDisplayP3
            : kCGColorSpaceSRGB;
    }
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(csName);
    _metalLayer.colorspace = cs;
    CGColorSpaceRelease(cs);
}
```

`CGColorSpaceCreateWithName` returns a +1 retained object. `CAMetalLayer.colorspace` is a retained property — it retains the new value and releases the old one on assignment. `CGColorSpaceRelease(cs)` balances the +1 from `Create`. Without it, every settings change leaks a `CGColorSpaceRef`. This runs only when settings actually change, not every frame.

The colorspace is derived from two inputs: `DrawableParameters.hdrHeadroom` tells the platform layer whether the display is HDR-capable, and `RenderSettings.colorGamut` tells it what gamut the engine's shaders are outputting. The engine reads `DrawableParameters` at the top of each frame and configures its tonemapping pipeline accordingly — if the platform downgraded to SDR (headroom == 1.0), the engine sees that and skips PQ encoding.

---

## Pixel Format / Colorspace Reference

For the canonical pixel-format ↔ colorspace pairing table (SDR / HDR P3 PQ / Rec. 2100 PQ / 10-bit vs 16-bit) and the rule of who applies the transfer function, see `presenting-metal-drawables/references/hdr-colorspace.md`. Prefer 10-bit (`MTLPixelFormatBGR10A2Unorm`) over 16-bit (`MTLPixelFormatRGBA16Float`) when available — lower memory bandwidth, sufficient for most game content. EDR headroom (from `ScreenParameters.edrHeadroom`) determines whether HDR is actually available on the current display — `1.0` means SDR only.

---

## Development Tips

> **Development tip:** Use Metal HUD (`MTL_HUD_ENABLED=1` environment variable, or Xcode scheme -> Run -> Options -> Metal HUD) for GPU frame time, FPS, and memory — no code required.

> **Development tip:** Enable Metal Validation (`MTL_DEBUG_LAYER=1` environment variable, or Xcode scheme -> Run -> Diagnostics -> GPU -> Metal Validation) to catch API misuse, resource hazards, and encoding errors — the Metal equivalent of D3D's debug layer. Use it during development; disable for profiling and shipping.
