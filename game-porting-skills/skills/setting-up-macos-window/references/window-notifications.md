# Window Notification Handlers

The `GameViewController`'s `registerNotifications` method should register these Window, Display, and App notification handlers.
The handlers ideally live as methods in `GameViewController` and route AppKit notifications into the `Engine*` callbacks.

## Map `NSNotification` Handlers to the Engine Callbacks

Most notification handlers should forward the message to the corresponding `Engine*` callback.
Handle macOS-specific behavior in the platform layer when appropriate.
Confirm that the engine will receive the input values it expects to preserve its intended behavior like using pixels instead of points.
The notes column below provides extra detail.
If blank, then forward into the engine's event handling system.

| AppKit notification | Handler | Engine callback | Notes |
|---|---|---|---|
| `NSWindowDidResizeNotification` | `windowDidResize:` | `EngineWindowDidResize(pixelW, pixelH);` | Filter via `inLiveResize`. See [Special Cases](#special-cases). |
| `NSViewFrameDidChangeNotification` | `windowDidResize:` | (same) | |
| `NSWindowDidMiniaturizeNotification` | `windowDidMiniaturize:` | `EngineWindowDidMinimize();` | |
| `NSWindowDidDeminiaturizeNotification` | `windowDidDeminiaturize:` | `EngineWindowDidDeminiaturize(); [self windowDidResize:note];` | |
| `NSWindowDidEnterFullScreenNotification` | `windowDidEnterFullScreen:` | `[self windowDidResize:note];` | Clears `_fullscreenTransitioning`. See [Special Cases](#fullscreen-transitions). |
| `NSWindowDidExitFullScreenNotification` | `windowDidExitFullScreen:` | `[self windowDidResize:note];` | Clears `_fullscreenTransitioning`. See [Special Cases](#fullscreen-transitions). |
| `NSWindowWillEnterFullScreenNotification` | `windowWillEnterFullScreen:` | (sets `_fullscreenTransitioning = YES`) | See [Special Cases](#fullscreen-transitions). |
| `NSWindowWillExitFullScreenNotification` | `windowWillExitFullScreen:` | (sets `_fullscreenTransitioning = YES`) | See [Special Cases](#fullscreen-transitions). |
| `NSWindowDidFailToEnterFullScreenNotification` | `windowDidFailToEnterFullScreen:` | (clears `_fullscreenTransitioning`) | Required so the flag does not stick on failure. |
| `NSWindowDidFailToExitFullScreenNotification` | `windowDidFailToExitFullScreen:` | (clears `_fullscreenTransitioning`) | Required so the flag does not stick on failure. |
| `NSWindowDidChangeScreenNotification` | `displayDidChange:` | `EngineDisplayDidChange();` | See [Special Cases](#special-cases). |
| `NSWindowDidChangeScreenProfileNotification` | `displayDidChange:` | `EngineDisplayDidChange();` | |
| `NSWindowDidChangeBackingPropertiesNotification` | `displayDidChange:` | `EngineDisplayDidChange();` | Also re-fires resize. See [Special Cases](#special-cases). |
| `NSApplicationDidChangeScreenParametersNotification` | `displayDidChange:` | `EngineDisplayDidChange();` | |
| `NSWindowDidBecomeKeyNotification` | `windowDidBecomeKey:` | `EngineWindowDidChangeFocus(true);` | |
| `NSWindowDidResignKeyNotification` | `windowDidResignKey:` | `EngineWindowDidChangeFocus(false);` | |
| `NSApplicationDidBecomeActiveNotification` | `appDidBecomeActive:` | `EngineWindowDidChangeFocus(true);` | |
| `NSApplicationWillResignActiveNotification` | `appWillResignActive:` | `EngineWindowDidChangeFocus(false); EngineResetInputStateOnLostFocus();` | |
| `NSWindowWillCloseNotification` | `windowWillClose:` | See [Special Cases](#special-cases). | |

## Special Cases

### `windowDidResize:`

Ignore intermediate sizes during a live drag or fullscreen transition.
Forward only the settled call (where `view.inLiveResize == NO` and `_fullscreenTransitioning == NO`) and pass pixel dimensions to the engine.

```objc
// Declare in GameViewController's @implementation { } block:
//   BOOL _fullscreenTransitioning;

- (void)windowDidResize:(NSNotification*)note {
    if (self.view.inLiveResize || _fullscreenTransitioning) return;
    NSWindow* window = self.view.window;
    if (!window) return;
    CGSize px = [window convertSizeToBacking:self.view.bounds.size];
    if (px.width > 0 && px.height > 0)
        EngineWindowDidResize((int)px.width, (int)px.height);
}
```

The `_fullscreenTransitioning` flag is set and cleared by the fullscreen handlers; see [Fullscreen Transitions](#fullscreen-transitions).

### `displayDidChange:`

Route all four display-change notifications through this handler.
Re-fire the resize on `NSWindowDidChangeBackingPropertiesNotification` because pixel size changed even though the point size did not.

```objc
- (void)displayDidChange:(NSNotification*)note {
    EngineDisplayDidChange();
    if ([note.name isEqualToString:NSWindowDidChangeBackingPropertiesNotification]) {
        [self windowDidResize:note];
    }
}
```

### `windowWillClose:`

Verify that the `notification.object` is the game's main window before starting shutdown.
macOS posts `NSWindowWillCloseNotification` for transient windows during some transitions (notably the green-button fullscreen exit).
Route the message to the engine so it can handle clean up tasks, finish game saves, etc.

```objc
- (void)windowWillClose:(NSNotification*)note {
    NSWindow* closingWindow = (NSWindow*)note.object;
    if (closingWindow != self.view.window) return;
    EngineWindowWillClose();
}
```

### Fullscreen Transitions

`toggleFullScreen:` runs an animation that fires intermediate resize and frame-change notifications.
Forwarding those to the engine causes flicker, mis-sized render targets, and wasted work as the engine reallocates between intermediate sizes.

The pattern parallels `inLiveResize` filtering: set a flag for the duration of the animation, suppress resize events while it is set, and fire one settled resize at the end.

```objc
// Declare in GameViewController's @implementation { } block:
//   BOOL _fullscreenTransitioning;

- (void)windowWillEnterFullScreen:(NSNotification*)note { _fullscreenTransitioning = YES; }
- (void)windowWillExitFullScreen:(NSNotification*)note  { _fullscreenTransitioning = YES; }

- (void)windowDidEnterFullScreen:(NSNotification*)note {
    _fullscreenTransitioning = NO;
    [self windowDidResize:note];
}
- (void)windowDidExitFullScreen:(NSNotification*)note {
    _fullscreenTransitioning = NO;
    [self windowDidResize:note];
}

- (void)windowDidFailToEnterFullScreen:(NSNotification*)note { _fullscreenTransitioning = NO; }
- (void)windowDidFailToExitFullScreen:(NSNotification*)note  { _fullscreenTransitioning = NO; }
```

Failures happen — typically during display hotplug or when another fullscreen-capable app is on the destination display.
Without the fail handlers, a single failure leaves `_fullscreenTransitioning` stuck at `YES` and silently breaks every subsequent resize event.
