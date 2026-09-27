# Keyboard Events

Keyboard input flows through `keyDown:`, `keyUp:`, and `flagsChanged:` on `GameViewController`.
For the high-level mapping from Windows messages to Apple equivalents, see `references/engine-and-messages.md`.

## Keyboard

```objc
- (void)keyDown:(NSEvent*)event {
    wchar_t ch = (event.characters.length > 0) ? [event.characters characterAtIndex:0] : 0;
    EngineHandleKeyEvent(event.keyCode, true, ch, event.modifierFlags, event.isARepeat);
}

- (void)keyUp:(NSEvent*)event {
    EngineHandleKeyEvent(event.keyCode, false, 0, event.modifierFlags, false);
}
```

Do not call `[super keyDown:event]`.
The default passes unhandled keys up the responder chain and triggers the system alert beep on every keypress.

`event.keyCode` is a 16-bit HID usage code, not a character.
Values are stable across keyboard layouts.
If the engine needs a UTF-8 text representation of the key, use `event.characters.UTF8String`.

Override `acceptsFirstResponder` on `GameViewController` to return `YES` (Phase 5).
Without it, `keyDown:` and `keyUp:` never fire.

## Modifier Keys

AppKit sends `flagsChanged:` for shift, ctrl, alt, cmd, and caps-lock instead of `keyDown:` / `keyUp:`.
Fan out to one synthesized key event per modifier bit using canonical HID codes.

```objc
- (void)flagsChanged:(NSEvent*)event {
    NSEventModifierFlags flags = event.modifierFlags;
    EngineHandleKeyEvent(0x37, (flags & NSEventModifierFlagCommand)   != 0, 0, flags, false); // Cmd
    EngineHandleKeyEvent(0x38, (flags & NSEventModifierFlagShift)     != 0, 0, flags, false); // Shift
    EngineHandleKeyEvent(0x39, (flags & NSEventModifierFlagCapsLock)  != 0, 0, flags, false); // CapsLock
    EngineHandleKeyEvent(0x3A, (flags & NSEventModifierFlagOption)    != 0, 0, flags, false); // Alt/Option
    EngineHandleKeyEvent(0x3B, (flags & NSEventModifierFlagControl)   != 0, 0, flags, false); // Ctrl
}
```

If the engine tracks modifier flags as a separate bitmask, expose `EngineHandleModifierFlags(flags)` and call that instead.
