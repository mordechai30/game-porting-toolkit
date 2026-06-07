# Mouse and Cursor

Mouse event routing, cursor visibility, and cursor confinement for mouse-look.
All methods live on `GameViewController` and route through the responder chain.
For the high-level mapping from Windows messages to Apple equivalents, see `references/engine-and-messages.md`.

## Mouse Motion

Consider `GCMouse` and `GCKeyboard` from the Game Controller framework as the preferred input API for games — `GCMouse` provides raw, unaccelerated relative mouse movement without cursor association, which is the right foundation for mouse-look.
Games typically want absolute position for UI and menus, and relative delta for mouse-look gameplay.

For NSEvent-based input, note these coordinate conversion considerations before wiring.
AppKit uses a bottom-left origin (positive Y = up); flip the Y axis to match the top-left space most engines expect.
`event.locationInWindow` returns logical points, not backing pixels; multiply by `self.view.window.backingScaleFactor` to get the drawable pixel position the engine expects.
If the window aspect ratio differs from `drawableSize`, `kCAGravityResizeAspect` letterboxes the layer; apply a scale and offset to map from window pixel space into drawable coordinate space.

**Absolute position** (for UI and menus).

```objc
- (void)mouseMoved:(NSEvent*)event {
    CGFloat scale = self.view.window.backingScaleFactor;
    CGPoint pos = [event locationInWindow];
    pos.x *= scale;
    pos.y = (self.view.bounds.size.height - pos.y) * scale;
    EngineHandleMouseMotion((float)pos.x, (float)pos.y);
}
```

**Relative delta** (for mouse-look; replaces RAWINPUT / WM_INPUT).

In `viewDidAppear`, after setup, wire any already-connected mice and observe for new ones:

```objc
for (GCMouse* mouse in GCMouse.mice)
    mouse.mouseInput.mouseMovedHandler = ^(GCMouseInput* input, float deltaX, float deltaY) {
        EngineHandleMouseDelta(deltaX, deltaY);
    };
[[NSNotificationCenter defaultCenter] addObserver:self
    selector:@selector(mouseConnected:)
    name:GCMouseDidConnectNotification object:nil];
```

```objc
- (void)mouseConnected:(NSNotification*)note {
    GCMouse* mouse = (GCMouse*)note.object;
    mouse.mouseInput.mouseMovedHandler = ^(GCMouseInput* input, float deltaX, float deltaY) {
        EngineHandleMouseDelta(deltaX, deltaY);
    };
}
```

If using NSEvent for mouse delta instead:

```objc
- (void)mouseMoved:(NSEvent*)event {
    EngineHandleMouseDelta((float)event.deltaX, (float)event.deltaY);
}
```


## Mouse Buttons

```objc
- (void)mouseDown:(NSEvent*)event       { EngineHandleMouseButton(0, true, event); }   // Left
- (void)mouseUp:(NSEvent*)event         { EngineHandleMouseButton(0, false, event); }
- (void)rightMouseDown:(NSEvent*)event  { EngineHandleMouseButton(1, true, event); }   // Right
- (void)rightMouseUp:(NSEvent*)event    { EngineHandleMouseButton(1, false, event); }

- (void)otherMouseDown:(NSEvent*)event {
    if (event.buttonNumber >= 0 && event.buttonNumber < 5)
        EngineHandleMouseButton((int)event.buttonNumber, true, event);
}
- (void)otherMouseUp:(NSEvent*)event {
    if (event.buttonNumber >= 0 && event.buttonNumber < 5)
        EngineHandleMouseButton((int)event.buttonNumber, false, event);
}
```

`event.buttonNumber` for `otherMouse*`: 2 = middle, 3 = back (XButton1), 4 = forward (XButton2).

## Mouse Dragging

Route the drag methods through `mouseMoved:` because AppKit suppresses `mouseMoved:` while a button is held.

```objc
- (void)mouseDragged:(NSEvent*)event       { [self mouseMoved:event]; }
- (void)rightMouseDragged:(NSEvent*)event  { [self mouseMoved:event]; }
- (void)otherMouseDragged:(NSEvent*)event  { [self mouseMoved:event]; }
```

## Scroll Wheel

Trackpads send precise scrolling deltas roughly 10× larger than mouse-wheel notch deltas; multiply precise deltas by 0.1.

```objc
- (void)scrollWheel:(NSEvent*)event {
    float dy = (float)event.scrollingDeltaY;
    float dx = (float)event.scrollingDeltaX;   // horizontal or wheel-tilt
    if (event.hasPreciseScrollingDeltas) {
        dy *= 0.1f;
        dx *= 0.1f;
    }
    EngineHandleScroll(dy, dx);
}
```

## NSTrackingArea

Install an `NSTrackingArea` on the game view to receive `mouseMoved:` and `mouseExited:` events.
The following method, called in `viewDidAppear`, installs one with the view controller as the owner:

```objc
- (void)installTrackingArea {
    for (NSTrackingArea* area in self.view.trackingAreas)
        [self.view removeTrackingArea:area];
    NSTrackingAreaOptions opts = NSTrackingMouseMoved
                               | NSTrackingMouseEnteredAndExited
                               | NSTrackingActiveInKeyWindow
                               | NSTrackingInVisibleRect;
    NSTrackingArea* area = [[NSTrackingArea alloc] initWithRect:self.view.bounds
                                                        options:opts
                                                          owner:self
                                                       userInfo:nil];
    [self.view addTrackingArea:area];
}
```

`NSTrackingInVisibleRect` auto-tracks the view's bounds, so the area survives resize without reinstall.

The tracking area also delivers `mouseExited:`.
Use it to clear engine-side hover state.

```objc
- (void)mouseExited:(NSEvent*)event { EngineHandleMouseLeave(); }
```

## Cursor Visibility

The engine calls `setCursorVisible:` to switch between menu (cursor visible) and gameplay (cursor hidden).

```objc
// Declare in GameViewController's @implementation { } block:
//   BOOL _cursorVisible;

- (void)setCursorVisible:(BOOL)visible {
    if (visible == _cursorVisible) return;
    _cursorVisible = visible;
    if (visible) CGDisplayShowCursor(kCGDirectMainDisplay);
    else         CGDisplayHideCursor(kCGDirectMainDisplay);
    [self applyPresentationOptions];
}
```

The `kCGDirectMainDisplay` argument is required by the API but has no effect.
`CGDisplayShowCursor` and `CGDisplayHideCursor` are reference-counted, so the early-return on equal state keeps counts balanced.

`applyPresentationOptions` lives in `references/presentation-and-sleep.md`; it reads `_cursorVisible` to pick the correct menu bar and dock behavior for the current mode.

## Cursor Confinement (Mouse-Look)

The engine calls `[self enterMouseLook]` when entering mouse-look mode and `[self exitMouseLook]` when exiting.
Decouple the visible cursor from mouse movement on entry; restore on exit.

```objc
// Declare in GameViewController's @implementation { } block:
//   BOOL    _mouseLookActive;
//   CGPoint _savedCursorPosition;

- (void)enterMouseLook {
    if (_mouseLookActive) return;
    _mouseLookActive = YES;

    NSWindow* window = self.view.window;

    // Save cursor position. NSEvent uses bottom-left; CGWarp uses top-left.
    NSPoint nsPos = [NSEvent mouseLocation];
    CGFloat h = NSScreen.mainScreen.frame.size.height;
    _savedCursorPosition = CGPointMake(nsPos.x, h - nsPos.y);

    CGAssociateMouseAndMouseCursorPosition(false);
    CGDisplayHideCursor(kCGDirectMainDisplay);

    // Warp to window center so the hidden cursor cannot hover other windows.
    CGFloat cx = window.frame.origin.x + window.frame.size.width  * 0.5;
    CGFloat cy = window.frame.origin.y + window.frame.size.height * 0.5;
    CGWarpMouseCursorPosition(CGPointMake(cx, h - cy));
}

- (void)exitMouseLook {
    if (!_mouseLookActive) return;
    _mouseLookActive = NO;
    CGAssociateMouseAndMouseCursorPosition(true);
    CGWarpMouseCursorPosition(_savedCursorPosition);
    CGDisplayShowCursor(kCGDirectMainDisplay);
}
```

Release confinement whenever the cursor should be visible: menus, pause screens, focus loss (see Focus Loss below).
If display geometry changes during mouse-look (fullscreen transition, display migration), call `[self exitMouseLook]` then `[self enterMouseLook]` to re-save and re-center.

`CGDisplayHideCursor` and `CGDisplayShowCursor` are reference-counted per display, so keep call counts balanced.

## Focus Loss

When the app resigns active, perform two platform-side actions:

* Call `EngineResetInputStateOnLostFocus` so the engine clears its input state.
* Call `[self exitMouseLook]` if cursor confinement is active.

The `appWillResignActive:` handler in `GameViewController` does both. See `references/window-notifications.md` for the registration.
