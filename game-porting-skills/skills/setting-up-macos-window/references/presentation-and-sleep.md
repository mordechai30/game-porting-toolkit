# Presentation Options and Display Sleep

Platform-side polish for full-screen gameplay.
Covers `presentationOptions` (menu bar, dock, cursor behavior by window mode) and display sleep prevention.
Both live as methods on `GameViewController` so they share state with the cursor visibility flag and fullscreen mode.
Cursor visibility itself lives in `references/mouse-and-cursor.md`.

## `presentationOptions`

The behavior of the menu bar, dock, and cursor depends on whether the app is windowed, fullscreen with cursor visible (in a menu), or fullscreen with cursor hidden (in gameplay).
Apply via `NSApplication.sharedApplication.presentationOptions`.

```objc
// Declare in GameViewController's @implementation { } block:
//   BOOL _cursorVisible;

- (void)applyPresentationOptions {
    NSApplicationPresentationOptions opts;
    if ([self isFullScreen] && !_cursorVisible) {
        // Fullscreen gameplay
        opts = NSApplicationPresentationHideMenuBar
             | NSApplicationPresentationHideDock
             | NSApplicationPresentationDisableCursorLocationAssistance;
    } else if ([self isFullScreen] && _cursorVisible) {
        // Fullscreen menu
        opts = NSApplicationPresentationAutoHideMenuBar
             | NSApplicationPresentationHideDock
             | NSApplicationPresentationDisableCursorLocationAssistance;
    } else {
        // Windowed
        opts = NSApplicationPresentationDefault
             | NSApplicationPresentationDisableCursorLocationAssistance;
    }
    NSApplication.sharedApplication.presentationOptions = opts;
}
```

All three branches set `NSApplicationPresentationDisableCursorLocationAssistance`.
macOS otherwise warps the cursor when the user shakes the mouse, disrupting mouse-look mid-frame.

## Display Sleep Prevention

Use `IOPMAssertion` to prevent the display from sleeping during gameplay.

```objc
#import <IOKit/pwr_mgt/IOPMLib.h>

// Declare in GameViewController's @implementation { } block:
//   IOPMAssertionID _sleepAssertion;   // zero-inits to kIOPMNullAssertionID

- (void)setDisplaySleepDisabled:(BOOL)disabled {
    if (disabled && _sleepAssertion == kIOPMNullAssertionID) {
        IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep,
                                    kIOPMAssertionLevelOn,
                                    CFSTR("Game in progress"),
                                    &_sleepAssertion);
    } else if (!disabled && _sleepAssertion != kIOPMNullAssertionID) {
        IOPMAssertionRelease(_sleepAssertion);
        _sleepAssertion = kIOPMNullAssertionID;
    }
}
```

Call `[self setDisplaySleepDisabled:YES]` during gameplay (cursor hidden).
Call `[self setDisplaySleepDisabled:NO]` in menus (cursor visible), on focus loss, and at shutdown.
