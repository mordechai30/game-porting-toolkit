# Engine Callbacks and Windows Message Mapping

This file documents how the platform code (macOS windowing) connects to the engine: what events the platform fires in, what data is provided, and what to look for in the engine codebase.
Each `Engine*` name is a placeholder for a function the engine already has.
Find the engine's actual handler for each integration point and wire the platform event to it.
Don't define new functions; map to what's there.

The Windows Message Mapping table below is the porter's audit aid for replacing the Windows message pump with Apple equivalents.
The Engine Callbacks table that follows details what each `Engine*` placeholder maps to in the engine.
The `ScreenParameters` section covers the per-frame snapshot the engine pulls from the platform.
The Pause and Resume section covers what drives engine-side pause/resume and the display-link expectation.
The Shutdown section covers the two-phase shutdown flow.
Input handlers (key, mouse, scroll, tracking) live at their call sites in `references/keyboard-events.md` and `references/mouse-and-cursor.md`.

## Windows Message Mapping

Audit the Windows message pump before removing it.
Map every `WM_` case to its Apple equivalent.
Per-handler details live in `references/keyboard-events.md`, `references/mouse-and-cursor.md`, and `references/window-notifications.md`.

| Windows | Apple equivalent |
|---|---|
| `WM_KEYDOWN/UP` | `keyDown:` / `keyUp:` to `EngineHandleKeyEvent`. See `references/keyboard-events.md`. |
| `WM_CHAR` | `event.characters` in `keyDown:`. Use `insertText:` for IME / dead-key text entry. |
| `WM_MOUSEMOVE` | `mouseMoved:` to `EngineHandleMouseMotion`. See `references/mouse-and-cursor.md`. |
| `WM_LBUTTONDOWN/UP` | `mouseDown:` / `mouseUp:` to `EngineHandleMouseButton(0, ...)` |
| `WM_RBUTTONDOWN/UP` | `rightMouseDown:` / `rightMouseUp:` to `EngineHandleMouseButton(1, ...)` |
| `WM_MBUTTONDOWN/UP` | `otherMouseDown:` / `otherMouseUp:` (`buttonNumber == 2`) to `EngineHandleMouseButton(2, ...)` |
| `WM_XBUTTONDOWN/UP` | `otherMouseDown:` / `otherMouseUp:` (`buttonNumber 3` or `4`) to `EngineHandleMouseButton(3 or 4, ...)` |
| `WM_MOUSEWHEEL` | `scrollWheel:` to `EngineHandleScroll` |
| `WM_SETCURSOR` | `CGDisplayHideCursor` / `CGDisplayShowCursor`. See `references/mouse-and-cursor.md`. |
| `WM_KILLFOCUS` | `NSApplicationWillResignActiveNotification` to `EngineResetInputStateOnLostFocus` |
| `WM_INPUT` (RAWINPUT) | `event.deltaX` / `event.deltaY` in `mouseMoved:`. See `references/mouse-and-cursor.md` (Model B). |
| `WM_SYSKEYDOWN` (Alt+Enter) | Fullscreen handled by the window layer (Ctrl+Cmd+F). |
| `WM_SIZE` | `NSWindowDidResizeNotification` to `EngineWindowDidResize`. See `references/window-notifications.md`. |
| `WM_ACTIVATE` | `NSApplicationWillResignActive` / `DidBecomeActive` to `EngineWindowDidChangeFocus` |
| `WM_CLOSE` / `WM_DESTROY` | `NSWindowWillCloseNotification` to `EngineWindowWillClose`. See `references/window-notifications.md`. |
| `WM_PAINT` | Replaced by the render loop. |
| `WM_SYSCOMMAND` (`SC_SCREENSAVE`, `SC_MONITORPOWER`) | Suppressed via `IOPMLib` power assertion. See `references/presentation-and-sleep.md`. |

## Engine Callbacks

This table covers lifecycle and window/display events.
Each row: the placeholder name, when the platform invokes it, what data is provided, and what to look for in the engine codebase.

| `Engine*` placeholder | When the platform invokes it | Data the platform provides | What to look for in the engine |
|---|---|---|---|
| `EngineProcessCommandLine` | `main()` before `NSApplicationMain` (Phase 2) | `argc`, `argv` | Command-line consumer. Must copy or consume `argv` before `NSApplicationMain` takes over; after that, `argv` won't be accessible. |
| `EngineInitializeApp` | `viewDidAppear` step 2 (Phase 5) | `id<MTLDevice>`, `CAMetalLayer*` | Renderer init: sets up shaders, PSOs, static resources, and configures layer properties (`pixelFormat`, `colorspace`, `drawableSize`, `displaySyncEnabled`, `maximumDrawableCount`, `wantsExtendedDynamicRangeContent`). Must **not** start the game loop or render here. |
| `EngineStart` | `viewDidAppear` step 6 (Phase 5), after init + notifications + initial size | (none) | "Start the game loop" function. Allocates anything that needed full startup; begins rendering. |
| `EnginePrepareAppForShutdown` | Called internally by `EngineWindowWillClose` / `EngineAppWillTerminate` — not by the platform directly | (none) | Centralized cleanup helper. Idempotent. Consolidates save flushing, resource release, and thread shutdown. |
| `EngineWindowDidResize` | `windowDidResize:` (filtered for live-resize end) | pixel width, pixel height (ints) | Window-resize handler. Updates render targets (offscreen textures, depth buffers, MSAA) to match new pixel dimensions. |
| `EngineWindowDidMinimize` | `windowDidMiniaturize:` | (none) | Minimize handler. Typically pauses or slows the game loop and skips rendering. |
| `EngineWindowDidDeminiaturize` | `windowDidDeminiaturize:` (the platform also re-fires `EngineWindowDidResize` after this) | (none) | Restore handler. Typically resumes the game loop. |
| `EngineWindowDidChangeFocus` | `windowDidBecomeKey:` / `windowDidResignKey:` / `appDidBecomeActive:` / `appWillResignActive:` | `bool focused` | Focus-change handler. Pauses on focus loss; resumes on gain. Avoid stuck keys/buttons and reset key/mouse state. |
| `EngineDisplayDidChange` | Any of 4 display-change notifications via `displayDidChange:` | (none) | Display-change handler. Re-evaluates EDR, refresh rate, and any cached display-dependent state. |
| `EngineResetInputStateOnLostFocus` | `appWillResignActive:` | (none) | Input-state clear. Clears held keys, mouse buttons, modifier flags so nothing stays pressed when the user Cmd-Tabs away. |
| `EngineWindowWillClose` | `windowWillClose:` (filtered to main window) | (none) | Shutdown handler. Performs synchronous cleanup (flush saves, release resources, signal threads), typically via `EnginePrepareAppForShutdown`. |
| `EngineAppWillTerminate` | `applicationWillTerminate:` | (none) | Last hook for logging or telemetry. |

## `ScreenParameters` Snapshot

The engine pulls a fresh snapshot once per frame.
It captures everything the engine needs to know about the window and display in one struct.

```cpp
struct ScreenParameters {
    CGSize  screenSizeInPoints;
    CGSize  screenSizeInPixels;
    CGSize  windowSizeInPoints;
    CGSize  windowSizeInPixels;
    CGFloat insetSizeInPoints;     // safe-area top inset (height in pts of the camera notch)
    CGFloat contentScale;          // backingScaleFactor
    CGFloat currentEDRHeadroom;    // 1.0 = SDR only, >1.0 = HDR available
    CGFloat potentialEDRHeadroom;  // maximum the display can achieve
    int     maximumFramesPerSecond;

    bool valid()        const { return windowSizeInPixels.width > 0 && windowSizeInPixels.height > 0; }
    bool supportsEDR()  const { return potentialEDRHeadroom > 1.0; }

    // Compare against a previous snapshot
    bool windowSizeChangedSince         (const ScreenParameters& p) const;
    bool currentEDRHeadroomChangedSince (const ScreenParameters& p) const;
    bool supportsEDRChangedSince        (const ScreenParameters& p) const;
};

ScreenParameters GetScreenParameters(NSWindow* window);
```

```cpp
ScreenParameters GetScreenParameters(NSWindow* window) {
    __block ScreenParameters p = {};
    dispatch_block_t fill = ^{
        NSScreen* screen = window.screen;
        CGFloat   scale  = screen.backingScaleFactor;
        CGSize    winPts = window.contentView.bounds.size;
        CGSize    scrPts = screen.frame.size;
        p.contentScale            = scale;
        p.screenSizeInPoints      = scrPts;
        p.screenSizeInPixels      = CGSizeMake(scrPts.width * scale, scrPts.height * scale);
        p.windowSizeInPoints      = winPts;
        p.windowSizeInPixels      = CGSizeMake(winPts.width * scale, winPts.height * scale);
        p.insetSizeInPoints       = screen.safeAreaInsets.top;
        p.currentEDRHeadroom      = screen.maximumExtendedDynamicRangeColorComponentValue;
        p.potentialEDRHeadroom    = screen.maximumPotentialExtendedDynamicRangeColorComponentValue;
        p.maximumFramesPerSecond  = (int)screen.maximumFramesPerSecond;
    };
    if ([NSThread isMainThread]) fill();
    else dispatch_sync(dispatch_get_main_queue(), fill);
    return p;
}
```

Each call costs one `dispatch_sync` to the main thread (microseconds).
Calling once per frame from the render path is the default; the engine can cache if it has a reason to.

`maximumFramesPerSecond` is a ceiling, not a guarantee — on HDMI-connected or mirrored displays the system may run lower.
Use it to set `preferredFrameRateRange` on `CAMetalDisplayLink`.
Do not rely on it as a precise timing source.

## Pause and Resume

The engine handles pausing and unpausing the game so don't add pause logic to the NSView/NSViewController.
Wire the visibility and focus callbacks (`EngineWindowDidMinimize`, `EngineWindowDidDeminiaturize`, `EngineWindowDidChangeFocus`) for the engine to handle this task.
Let the engine decide when to render instead of stopping or invalidating the display link.
Avoid polling `NSApp.isHidden` or `self.window.isMiniaturized` — update the engine state from the notification handlers.

## Shutdown

The platform routes two shutdown moments into the engine: `EngineWindowWillClose` and `EngineAppWillTerminate`.
AppKit posts `windowWillClose:` when the game window is being closed.
Always check the notification object against the main window in `windowWillClose:` because macOS posts the notification for transient windows during some transitions (e.g., green-button fullscreen exit).
Wire the engine's shutdown helper into `EngineWindowWillClose` and do cleanup synchronously — the termination callback is time-constrained, so save critical game state first (save files, user settings) before waiting for the renderer to stop.

AppKit posts `applicationWillTerminate:` once all windows have closed (close button, Cmd+Q) or on OS-driven termination.
`EngineAppWillTerminate` is for last logging or telemetry only.
