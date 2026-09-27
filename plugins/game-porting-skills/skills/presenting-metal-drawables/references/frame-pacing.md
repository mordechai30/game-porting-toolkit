# Frame Pacing

Detail on `CAMetalDisplayLink`, variable refresh rate displays, and the two render-loop modes (vsync-on / vsync-off). The SKILL.md body covers the basics; load this file when wiring a render loop or debugging frame-rate issues.

## CAMetalDisplayLink

`CAMetalDisplayLink` is the modern way to drive the render loop on macOS. It provides display-synced callbacks with presentation timestamps, replacing `CVDisplayLink` and manual timers.

```objc
// ObjC
CAMetalDisplayLink* displayLink = [[CAMetalDisplayLink alloc] initWithMetalLayer:metalLayer];
displayLink.preferredFrameLatency = 2;  // default; tailor to engine's latency/throughput needs
displayLink.paused = NO;
displayLink.delegate = self;

// Start on run loop
[displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];

// Delegate callback — called at display refresh rate
- (void)metalDisplayLink:(CAMetalDisplayLink*)link
             needsUpdate:(CAMetalDisplayLinkUpdate*)update {
    CFTimeInterval deltaTime = update.targetPresentationTimestamp - previousTimestamp;
    previousTimestamp = update.targetPresentationTimestamp;
    [self renderFrame:deltaTime];
}
```

Benefits over `CVDisplayLink` or manual timers:

- Automatically syncs to display refresh rate
- Provides target presentation timestamps for frame pacing
- Integrates with `NSRunLoop` modes (handles UI events during resize/drag)
- `preferredFrameLatency` controls frames of render latency

Not all engines use `CAMetalDisplayLink`. Many have their own render loop (timer-based, run loop-based, or dedicated thread). Integrate with whatever the engine provides rather than replacing it. For full engine integration on a dedicated render thread (run-loop wiring, frame semaphore, resize plumbing), see the `setting-up-macos-window` skill.

## Variable Refresh Rate Displays

Modern Apple displays support variable refresh rates — Adaptive-Sync on Mac (40–120Hz) and ProMotion on Mac and iPad (24–120Hz). The frame pacing strategy should adapt to these.

### Detecting variable refresh rate support

```objc
// macOS — Adaptive-Sync detection
- (BOOL)isAdaptiveSyncSupported:(NSScreen*)screen {
    NSTimeInterval minInterval = screen.minimumRefreshInterval;
    NSTimeInterval maxInterval = screen.maximumRefreshInterval;
    return minInterval != maxInterval;  // different = variable rate
}

// Adaptive-Sync requires full-screen mode
- (BOOL)isAdaptiveSyncActive:(NSWindow*)window {
    NSScreen* screen = [window screen];
    BOOL isFullscreen = ([window styleMask] & NSFullScreenWindowMask) == NSFullScreenWindowMask;
    return isFullscreen && [self isAdaptiveSyncSupported:screen];
}

// iOS/iPadOS — ProMotion max rate
NSInteger maxRate = [[UIScreen mainScreen] maximumFramesPerSecond];
```

Do not hardcode display refresh rates. Always query at runtime — the available rate can change due to Low Power Mode, thermal throttling, or accessibility settings.

**Strategy for variable refresh rate displays:** present frames at the highest rate the app can sustain evenly. Stay above the display's minimum rate (typically 40Hz) to avoid the display falling out of adaptive sync.

### Frame rate transition smoothness

When using `CADisplayLink` (iOS) or `CAMetalDisplayLink` (macOS), use `targetTimestamp` for animation timing — not `timestamp`:

```objc
// WRONG — causes hitches at frame rate transitions
progress += link.timestamp - previousTimestamp;

// CORRECT — smooth transitions between frame rates
progress += link.targetTimestamp - previousTargetTimestamp;
previousTargetTimestamp = link.targetTimestamp;
```

`targetTimestamp` represents when the frame will be composited, providing consistent timing even when the display transitions between refresh rates.

## Render Loop Modes: VSync-On vs VSync-Off

The recommended approach is to use different render loop mechanisms depending on whether vsync is enabled.

### VSync-On — use `CAMetalDisplayLink`

- The display link pre-acquires a drawable before calling your delegate, so do NOT call `nextDrawable` directly.
- The drawable reflects the layer properties from the *previous* frame — update `drawableSize`/`pixelFormat`/`colorspace` after presenting, not before (see "Apply-after-present rule" below).
- Set `displaySyncEnabled = YES` on the layer.

### VSync-Off — use a semaphore-based dispatch queue loop

- Set `displaySyncEnabled = NO` on the layer.
- Use a serial dispatch queue with a `dispatch_semaphore` (count 2 or 3) to limit in-flight frames.
- Call `nextDrawable` explicitly each frame.
- Use `[drawable presentAfterMinimumDuration:]` to cap frame rate, or `[drawable present]` for uncapped.

### Switching between modes at runtime

- VSync-On → VSync-Off: invalidate the display link, then start the semaphore loop.
- VSync-Off → VSync-On: stop the render loop, wait for in-flight frames to drain, then create a new display link.

For a complete dual-path implementation that switches at runtime on a dedicated render thread (with `updateFramePacing`, `_frameSemaphore`, and run-loop wiring), see `render-loop-detail.md`.

## Apply-after-present rule

Once a drawable is acquired, its properties are fixed — the drawable itself cannot be changed. Layer property changes (`drawableSize`, `pixelFormat`, `colorspace`) only affect the *next* drawable acquired. Apply them after presenting, never before acquiring the next drawable.

This is especially important with `CAMetalDisplayLink`, which provides the drawable to the delegate rather than letting the app call `nextDrawable` directly — there is no opportunity to change layer properties before the drawable arrives.

```objc
// Render with the current frame's parameters
[self encodeFrame:drawable params:_currentParams];
[queue commit:cmds count:count];
[queue signalDrawable:drawable];
[drawable present];

// Then update layer properties for the *next* frame
DrawableParameters next = [self buildDrawableParameters];
if (next != _currentParams) {
    _metalLayer.drawableSize = next.targetSize;
    _metalLayer.pixelFormat  = next.pixelFormat;
    _metalLayer.colorspace   = next.colorspace;
    _currentParams = next;
}
```
