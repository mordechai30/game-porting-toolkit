---
name: setting-up-macos-window
description: Setting up the macOS window layer when porting a Windows game to Metal. Covers AppDelegate + NSWindow programmatic setup, a CAMetalLayer-backed GameView with CAMetalDisplayLink, GameViewController lifecycle, AppKit notifications routed into the engine via `Engine*` callbacks, keyboard/mouse input replacing WndProc, fullscreen transitions, cursor visibility and mouse-look confinement, sleep prevention, and per-frame screen state for sizes and EDR. Use whenever the question touches porting a Windows game window to macOS — AppDelegate / GameView / GameViewController setup, replacing WndProc, fullscreen, cursor handling, window resize, or AppKit notification routing.
---

# Game Window Port

A guided workflow for wiring up the macOS window layer when porting a Windows game to Metal.

## Scope and Companion Skills

This skill covers windowing concerns: the AppKit surface, the view that owns the `CAMetalLayer` and the render-tick source, lifecycle, notifications, and input.
The boundary with the engine is the `Engine*` callback API described in Phase 6.
Past that boundary, presentation and rendering live in companion skills:

| Question is about | Skill |
|---|---|
| Drawable acquisition, presentation flow (`waitForDrawable`, `signalDrawable`, `present`), layer property semantics (`pixelFormat`, `colorspace`, `drawableSize`, `maximumDrawableCount`, `displaySyncEnabled`, EDR opt-in), Metal 3 vs Metal 4 | `presenting-metal-drawables` |
| D3D12/Vulkan API mapping to Metal 4 (device, queue, command buffer, encoder, PSO, shader compile, swap chain) | `translating-to-metal4-api` |

## Reference Routing

| Question is about | Read |
|---|---|
| Working implementations of `GameView`, `GameRenderer`, `GameViewController`, `AppDelegate` | `references/window-implementation.md` |
| `Engine*` callbacks, `ScreenParameters`, shutdown, Windows message mapping cheat sheet | `references/engine-and-messages.md` |
| AppKit notification handlers, fullscreen, display migration, resize | `references/window-notifications.md` |
| Keyboard input, modifier keys | `references/keyboard-events.md` |
| Mouse input, `NSTrackingArea`, cursor visibility, cursor confinement / mouse-look, focus loss | `references/mouse-and-cursor.md` |
| Display sleep, three-mode `presentationOptions` | `references/presentation-and-sleep.md` |

**Reading `Engine*` calls.** Each placeholder is documented in `references/engine-and-messages.md`: when called, what data, what to look for in the engine.

**Response length.** Provide the architectural pattern and key code blocks inline.
For full implementations, point to the appropriate reference file.
A focused 200 to 400 line response that explains the *why* and shows the critical *what* is ideal.

**UIKit/AppKit APIs.** Some UIKit/AppKit APIs use different names for the same function. Overriding an UIKit method in AppKit causes silent no-op bugs. ALWAYS use AppKit API names to generate and debug code. For example: UIKit uses `+layerClass` and AppKit uses `-makeBackingLayer` to make the view's backing layer.

---

## Phase 1: Assess the Codebase

Before writing code, inspect the engine codebase to answer these; if unclear, ask the user:

1. **Engine render entry point.** Find where the engine expects a Metal device and drawable. The platform hands the device and `CAMetalLayer` off via `EngineInitializeApp(device, layer)` (Phase 6); per-tick drawable handling is the engine's design choice (Phase 4).
2. **Engine main loop.** Spawn a dedicated game thread for frame orchestration and signal it from the render-loop callback — engine work (physics, AI, world updates) must not run on the main thread, as delays block AppKit events and notifications.
3. **Platform guard prefix.** Look at existing platform-specific code and infer the convention (e.g., `MINIENGINE_`, `RE_`, `UE_`). Use it consistently for Apple-specific guards.
4. **`LSApplicationCategoryType` in `Info.plist`.** Set to `public.app-category.games` or a subcategory. Game Mode turns on with both this key and the app being in fullscreen and gives the foreground game higher-priority GPU and CPU scheduling and reduced audio and input latency.
5. **`com.apple.developer.sustained-execution` entitlement.** Add this together with `LSApplicationCategoryType` to activate sustained execution, which allows the system to maintain a consistent performance state over your app's lifecycle on applicable devices.
6. **Minimum deployment target.** Metal 4 requires macOS 26+; `CAMetalDisplayLink` requires macOS 14+.

---

## Phase 2: Application Entry Point

### File: `main.mm`

Implement main() for the app and give the engine its command-line arguments before starting AppKit / NSApplicationMain.

---

## Phase 3: App Delegate

### File: `AppDelegate.h/.mm`

Start from `references/window-implementation.md` → `## AppDelegate`.
- Implement a `setupMenu` method to build the menu programmatically. Call in `applicationDidFinishLaunching:` after the window is shown. It needs to make:
  - App menu with About and Quit (`terminate:` with Cmd+`q` key equivalent). Substitute the app's actual name into the About and Quit titles (e.g., "About MyGame", "Quit MyGame").
  - Window menu with Toggle Full Screen (`toggleFullScreen:` with Ctrl+Cmd+F key equivalent).
- `applicationWillTerminate:` - See `references/engine-and-messages.md` → Shutdown.

---

## Phase 4: GameView and GameRenderer

### File: `GameView.h/.mm`

Start from `references/window-implementation.md` → `## GameView`.
Do not use `MTKView` — it owns the render loop and drawable lifecycle, which prevents `CAMetalDisplayLink` integration.
`configureWithDevice:` is called once from `GameViewController` (Phase 5); the engine reconfigures layer properties via the layer reference before each tick.

### File: `GameRenderer.h/.mm`

Start from `references/window-implementation.md` → `## GameRenderer`.
- `metalDisplayLink:needsUpdate:` — replace the color-clear animation with a call into the engine's per-tick rendering hook. The drawable comes from `update.drawable`.

---

## Phase 5: GameViewController

### File: `GameViewController.h/.mm`

Start from `references/window-implementation.md` → `## GameViewController`.

**`viewDidAppear` — replace with this engine-wired sequence. Do not reorder; steps 1–9 wire the engine before step 10 starts it.**

1. `[self configureForWindowedMode]` then `[window center]`.
2. Create device: `id<MTLDevice> device = MTLCreateSystemDefaultDevice()`.
3. `[_gameView configureWithDevice:device]`.
4. `EngineInitializeApp(device, _gameView.metalLayer)`.
5. If the engine needs a `CAMetalDisplayLink` setup, use `GameRenderer` from `references/window-implementation.md` as a starting point and wire the engine's tick into `metalDisplayLink:needsUpdate:` per Phase 4. If the engine drives its own render loop, skip `GameRenderer` — the layer is already passed to the engine in step 4.
6. `[window makeFirstResponder:self]`.
7. `[self installTrackingArea]` — see `references/mouse-and-cursor.md`.
8. `[self registerNotifications]` — see `references/window-notifications.md`.
9. `EngineWindowDidResize` with the backing-pixel size of `_gameView.bounds`.
10. `EngineStart()`.

Use `viewDidAppear` not `viewWillAppear` — `view.window` is nil in `viewWillAppear` on macOS.
Guard with `_initialized` — `viewDidAppear` can fire more than once.

**`configureForWindowedMode`:**

The window keeps all standard decorations — close, minimize, and zoom buttons — and is resizable.
`NSWindowStyleMaskFullSizeContentView` extends the content view under the titlebar so the game renders edge-to-edge; `titleVisibility = NSWindowTitleHidden` removes only the title text, leaving the traffic-light controls visible.

```objc
- (void)configureForWindowedMode {
    if ([self isFullScreen]) return;
    NSWindow* w = self.view.window;
    w.styleMask = NSWindowStyleMaskTitled
                | NSWindowStyleMaskClosable
                | NSWindowStyleMaskMiniaturizable
                | NSWindowStyleMaskResizable
                | NSWindowStyleMaskFullSizeContentView;
    w.titlebarAppearsTransparent = YES;
    w.titleVisibility = NSWindowTitleHidden;
    w.backgroundColor = [NSColor blackColor];   // letterbox bars during live resize
    w.minSize = NSMakeSize(640, 360);
    w.contentAspectRatio = NSMakeSize(16, 9);   // set to the game's native aspect ratio
    [self applyPresentationOptions];   // see references/presentation-and-sleep.md
}
```

**`isFullScreen` and `toggleFullscreen`:**

```objc
- (BOOL)isFullScreen {
    return (self.view.window.styleMask & NSWindowStyleMaskFullScreen) != 0;
}

- (void)toggleFullscreen {
    [self.view.window toggleFullScreen:nil];
    // windowDidEnterFullScreen / windowDidExitFullScreen handle the engine-side work.
}
```

**Pause and shutdown:**

Wire visibility and focus `Engine*` callbacks via notifications — see Pause and Resume in `references/engine-and-messages.md`.
Shutdown: `windowWillClose:` and `applicationWillTerminate:` — see `references/window-notifications.md` and `references/engine-and-messages.md` → Shutdown.

---

## Phase 6: Engine Callbacks

The platform fires `Engine*` callbacks; the engine pulls a per-frame `ScreenParameters` snapshot.
See **`references/engine-and-messages.md`** for the full callback list, struct definition, shutdown, and the Windows message mapping cheat sheet.

---

## Phase 7: Notifications

Register AppKit notifications in `registerNotifications` and route each into its `Engine*` callback. See **`references/window-notifications.md`**.

---

## Phase 8: Input

Implement the keyboard and mouse responder-chain methods on `GameViewController` and install the `NSTrackingArea`. See **`references/keyboard-events.md`** and **`references/mouse-and-cursor.md`**.

---

## Phase 9: Sleep and Presentation Options

Implement display sleep prevention and the three-mode `presentationOptions` per **`references/presentation-and-sleep.md`**.

---

## Verification Checklist

Before claiming the macOS window layer is done, confirm:

**Window and lifecycle:**
- [ ] Window opens. AppDelegate creates it programmatically. Menus build correctly.
- [ ] `EngineInitializeApp` receives a non-nil device and layer.
- [ ] Initial `EngineWindowDidResize` fires once at startup with non-zero dimensions.
- [ ] `EngineStart` fires last in `viewDidAppear`, after notifications and the initial size event.
- [ ] `[window center]` runs once at startup, not on fullscreen exit.
- [ ] Render loop starts and the `metalDisplayLink:needsUpdate:` delegate fires once per display tick.

**Notifications:**
- [ ] Window resize fires `EngineWindowDidResize` once on release of the live-resize drag, not on every intermediate size.
- [ ] Fullscreen toggle works (Ctrl+Cmd+F) and re-fires `EngineWindowDidResize` at the final dimensions.
- [ ] Closing the window (red close button, Cmd+Q, green-zoom while in fullscreen) does not crash mid-fullscreen-exit. `windowWillClose:` ignores notifications whose `object` is not the game's window.
- [ ] All four display-change notifications fire `EngineDisplayDidChange`. Test by moving the window between displays of different scale or refresh rate, and by changing the display profile.
- [ ] Minimize and restore fire `EngineWindowDidMinimize` and `EngineWindowDidDeminiaturize`. Restore re-fires `EngineWindowDidResize`.
- [ ] App resign/become active fires `EngineWindowDidChangeFocus`.

**Input:**
- [ ] Keyboard reaches the engine. Test multiple keys including modifiers via `flagsChanged:`.
- [ ] Mouse move, click (left, right, middle, side), drag, and scroll all register.
- [ ] Cursor tracks the mouse in the engine's expected coordinate space — verify coordinates are in drawable pixel space, not AppKit logical points.
- [ ] Mouse delta coordinates are sent with the correct Y-flip to match the engine's expected inputs.
- [ ] Trackpad scroll feels comparable to mouse-wheel scroll. Precise deltas are normalized.
- [ ] No stuck keys after Cmd-Tab. Focus loss clears input state.
- [ ] Cursor confinement works for mouse-look if the game needs it.

**HDR / EDR:**
- [ ] `GetScreenParameters().currentEDRHeadroom` reports `>1.0` on an HDR-capable display, `1.0` otherwise.

**Shutdown:**
- [ ] `EngineWindowWillClose` fires when the user closes the window (close button, Cmd+Q, green-zoom while in fullscreen). The engine performs cleanup synchronously and returns.
- [ ] `EngineAppWillTerminate` fires after the window closes.
- [ ] No destructor-order crashes in the console on either shutdown path.
