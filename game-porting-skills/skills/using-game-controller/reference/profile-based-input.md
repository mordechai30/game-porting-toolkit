# Profile-based Physical Input

This document discusses the design and use of the profile-based APIs for accessing and monitoring game controller physical input.


## Overview

The GameController framework originated on iOS, which initially only supported game controllers designed to Apple's specification (MFi).  Apple defined the "gamepad" profile, and later the "extended gamepad" profile based on the requirements imposed on MFi game controllers.  Additional profiles were defined for the AppleTV remotes in tvOS 8.0, and eventually for PlayStation and Xbox controllers when support was added in iOS 13.

Each profile is represented by a class inheriting from `GCPhysicalInputProfile` - the base profile.  The following classes and protocols comprise the profile-based physical input APIs.

```
# Profiles
GCPhysicalInputProfile
GCMicroGamepad
GCDirectionalGamepad
GCGamepad
GCExtendedGamepad
GCXboxGamepad
GCDualShockGamepad
GCDualSenseGamepad
# Elements
GCControllerElement (aliased to GCDeviceElement)
GCControllerButtonInput (aliased to GCDeviceButtonInput)
GCControllerAxisInput (aliased to GCDeviceAxisInput)
GCControllerDirectionPad (aliased to GCDeviceDirectionPad)
GCControllerTouchpad (aliased to GCDeviceTouchpad)
GCDualSenseAdaptiveTrigger
```

## Profiles

A profile provides a guarantee that the controls you expect to find on a specific controller exist. A device can support multiple profiles, ensuring all controls each profile defines are present on the physical controller.

The following profiles are defined.  All profiles are superset of the *base profile*.  Most profiles are superset of one or more other profiles.

```
+ Base (GCPhysicalInputProfile)
    + Micro (GCMicroGamepad)
        + Directional (GCDirectionalGamepad)
        + Gamepad (GCGamepad)
            + Extended (GCExtendedGamepad)
                + Xbox (GCXboxGamepad)
                + DualShock (GCDualShockGamepad)
                + DualSense (GCDualSenseGamepad)
```

### Base

The base profile does not guarantee the existence of any controls.  You can check for the existance of controls by querying the `elements` collection, or the `buttons`, `axes`, `dpads`, and `touchpads` collections of `GCPhysicalInputProfile`.

```swift
    // Check if controller has an 'A' button, 'B' button, and a D-Pad
    
    if let aButton = controller.physicalInputProfile.buttons[GCInputButtonA],
       let bButton = controller.physicalInputProfile.buttons[GCInputButtonB],
       let dpad = controller.physicalInputProfile.dpads[GCInputDirectionPad]
    {
        
    }
```


### Micro

The micro profile guarantees:

* One direction pad (`GCInputDirectionPad`)
* Two digital face buttons - 'A' (`GCInputButtonA`) and 'X' (`GCInputButtonX`)
* A menu button (`GCInputButtonMenu`)

```swift
    // Check if controller supports the Micro gamepad profile
    
    if let microGamepad: GCMicroGamepad = controller.microGamepad {
        let aButton = microGamepad.buttonA
        let xButton = microGamepad.buttonX
        let dpad = microGamepad.dpad
        let menu = microGamepad.buttonMenu
    }
```

### Gamepad

The gamepad profile guarantees:

* One direction pad (`GCInputDirectionPad`)
* Four face buttons (arranged in a diamond pattern) - 'A' (`GCInputButtonA`), 'B' (`GCInputButtonB`), 'X' (`GCInputButtonX`), 'Y' (`GCInputButtonY`)
* Two shoulder buttons - left shoulder (`GCInputLeftShoulder`), and right shoulder (`GCInputRightShoulder`)
* A menu button (`GCInputButtonMenu`)

```swift
    // Check if controller supports the Gamepad profile
    
    if let gamepad: GCGamepad = controller.gamepad {
        let aButton = gamepad.buttonA
        let bButton = gamepad.buttonB
        let xButton = gamepad.buttonX
        let yButton = gamepad.buttonY
        let leftShoulder = gamepad.leftShoulder
        let rightShoulder = gamepad.rightShoulder
        let dpad = gamepad.dpad
        let menu = gamepad.buttons[GCInputButtonMenu]!
    }
```

### Extended

The extended profile guarantees:

* One analog direction pad (`GCInputDirectionPad`)
* Two thumbsticks - left (`GCInputLeftThumbstick`), and right (`GCInputRightThumbstick`).
* Four face buttons (arranged in a diamond pattern) - 'A' (`GCInputButtonA`), 'B' (`GCInputButtonB`), 'X' (`GCInputButtonX`), 'Y' (`GCInputButtonY`)
* Two shoulder buttons - left shoulder (`GCInputLeftShoulder`), and right shoulder (`GCInputRightShoulder`)
* Two trigger buttons - left trigger (`GCInputLeftTrigger`), and right trigger (`GCInputRightTrigger`)
* A menu button (`GCInputButtonMenu`)

Devices supporting the extended profile typically include (but are not required to include):

* Thumbstick buttons (clickable thumbsticks) - left (`GCInputLeftThumbstickButton`), and right (`GCInputRightThumbstickButton`)
* Home button (`GCInputButtonHome`)
* Options button (`GCInputButtonOptions`)

Devices supporting the extended profile sometimes include:

* Bumper buttons adjacent to the shoulder buttons - left (`GCInputLeftBumper`), and right (`GCInputRightBumper`)
* Back buttons or paddle buttons - up to two on the left back-side (`GCInputBackLeftButton(0-1)`), and up to two on the right back-side (`GCInputBackRightButton(0-1)`)

```swift
    // Check if the controller supports the Extended profile
    
    if let extendedGamepad: GCExtendedGamepad = controller.extendedGamepad {
        let aButton = extendedGamepad.buttonA
        let bButton = extendedGamepad.buttonB
        let xButton = extendedGamepad.buttonX
        let yButton = extendedGamepad.buttonY
        let leftShoulder = extendedGamepad.leftShoulder
        let rightShoulder = extendedGamepad.rightShoulder
        let leftTrigger = extendedGamepad.leftTrigger
        let rightTrigger = extendedGamepad.rightTrigger
        let leftThumbstick = extendedGamepad.leftThumbstick
        let rightThumbstick = extendedGamepad.rightThumbstick
        let dpad = extendedGamepad.dpad
        let menu = extendedGamepad.buttonMenu
        
        if let leftThumbstickButton = extendedGamepad.leftThumbstickButton {
            // Device has clickable left thumbstick
        }
        
        if let rightThumbstickButton = extendedGamepad.rightThumbstickButton {
            // Device has clickable right thumbstick
        }
        
        if let options = extendedGamepad.buttonOptions {
            // Device has options button
        }
        
        if let home = extendedGamepad.buttonHome {
            // Device has Home button
            //
            // Remember to set `preferredSystemGestureState` to
            // `GCSystemGestureStateDisabled` if you intend to use
            // this button in your app or game.
            home.preferredSystemGestureState = .disabled
        }
        
        // In Objective-C, this would be written:
        //    __auto_type leftBumper = extendedGamepad.buttons[GCInputLeftBumper];
        if let leftBumper = extendedGamepad.buttons[__GCInputButtonName.leftBumper.rawValue] {
            // Device has left bumper button
            // This button is more commonly called 'L4'
        }
        
        // In Objective-C, this would be written:
        //    __auto_type leftBumper = extendedGamepad.buttons[GCInputRightBumper];
        if let rightBumper = extendedGamepad.buttons[__GCInputButtonName.rightBumper.rawValue] {
            // Device has right bumper button
            // This button is more commonly called 'R4'
        }
        
        // In Objective-C, this would be written:
        //    __auto_type leftPrimaryBackButton = extendedGamepad.buttons[GCInputBackLeftButton(0)];
        if let leftPrimaryBackButton = extendedGamepad.buttons[__GCInputBackLeftButton(0).rawValue] {
            // Device has a button or paddle on the left underside.
            // This buttons is sometimes called 'M2', 'P2', or 'PL'.
        }
        
        // In Objective-C, this would be written:
        //    __auto_type rightPrimaryBackButton = extendedGamepad.buttons[GCInputBackRightButton(0)];
        if let rightPrimaryBackButton = extendedGamepad.buttons[__GCInputBackRightButton(0).rawValue] {
            // Device has a button or paddle on the right underside.
            // This buttons is sometimes called 'M1', 'P1', or 'PR'.
        }
    }
```

### Xbox

The Xbox profile guarantees the device has all of the controls found on an Xbox One controller.  The `GCXboxGamepad` class subclasses `GCExtendedGamepad`.  All controls guaranteed by the Extended profile are guaranteed by the Xbox profile.  The following optional controls in the Extended profile are guaranteed by the Xbox profile:

* Thumbstick buttons (clickable thumbsticks) - left (`GCInputLeftThumbstickButton`), and right (`GCInputRightThumbstickButton`).  Xbox One and later Xbox controllers have clickable thumbsticks.
* Home button (`GCInputButtonHome`).  Xbox controllers include an 'Xbox' button that is the MFi Home button equivalent.
* Options button (`GCInputButtonOptions`).  Xbox controllers include a 'View' button that is the MFi Options button equivalent.

```swift
    // Check if the controller supports the Xbox profile
    
    if let xboxGamepad: GCXboxGamepad = controller.extendedGamepad as? GCXboxGamepad {
        let aButton = xboxGamepad.buttonA
        let bButton = xboxGamepad.buttonB
        let xButton = xboxGamepad.buttonX
        let yButton = xboxGamepad.buttonY
        let leftShoulder = xboxGamepad.leftShoulder
        let rightShoulder = xboxGamepad.rightShoulder
        let leftTrigger = xboxGamepad.leftTrigger
        let rightTrigger = xboxGamepad.rightTrigger
        let leftThumbstick = xboxGamepad.leftThumbstick
        let rightThumbstick = xboxGamepad.rightThumbstick
        let dpad = xboxGamepad.dpad
        let menu = xboxGamepad.buttonMenu
        
        // Xbox profile guarantees clickable thumbsticks
        let leftThumbstickButton = xboxGamepad.leftThumbstickButton!
        let rightThumbstickButton = xboxGamepad.rightThumbstickButton!
        
        // Xbox profile guarantees options ('View') button is present.
        let view = xboxGamepad.buttonOptions!
        
        // Xbox profile guarantees home ('Xbox' logo) button is present.
        let xbox = xboxGamepad.buttonHome!
        // Remember to set `preferredSystemGestureState` to
        // `GCSystemGestureStateDisabled` if you intend to use
        // the Home button in your app or game.
        xbox.preferredSystemGestureState = .disabled
        
        // Xbox Elite series controllers have four paddle buttons
        // on the back of the controller.
        if let p1 = xboxGamepad.paddleButton1 {
            
        }
        if let p2 = xboxGamepad.paddleButton2 {
            
        }
        if let p3 = xboxGamepad.paddleButton3 {
            
        }
        if let p4 = xboxGamepad.paddleButton4 {
            
        }
    }
```

### DualShock

The DualShock profile guarantees the device has all of the controls found on a DualShock 4 controller.  The `GCDualShockGamepad` class subclasses `GCExtendedGamepad`.  All controls guaranteed by the Extended profile are guaranteed by the DualShock profile.  The following optional controls in the Extended profile are guaranteed by the DualShock profile:

* Thumbstick buttons (clickable thumbsticks) - left (`GCInputLeftThumbstickButton`), and right (`GCInputRightThumbstickButton`).  DualShock controllers have clickable thumbsticks.
* Home button (`GCInputButtonHome`).  DualShock controllers include an 'PS' button that is the MFi Home button equivalent.
* Options button (`GCInputButtonOptions`).  DualShock controllers include a 'Share' button that is the MFi Options button equivalent.

```swift
    // Check if the controller supports the DualShock profile
    
    if let dualShockGamepad: GCDualShockGamepad = controller.extendedGamepad as? GCDualShockGamepad {
        let aButton = dualShockGamepad.buttonA // Cross Button
        let bButton = dualShockGamepad.buttonB // Circle Button
        let xButton = dualShockGamepad.buttonX // Square Button
        let yButton = dualShockGamepad.buttonY // Triangle Button
        let leftShoulder = dualShockGamepad.leftShoulder // L1
        let rightShoulder = dualShockGamepad.rightShoulder // R1
        let leftTrigger = dualShockGamepad.leftTrigger // L2
        let rightTrigger = dualShockGamepad.rightTrigger // R2
        let leftThumbstick = dualShockGamepad.leftThumbstick
        let rightThumbstick = dualShockGamepad.rightThumbstick
        let dpad = dualShockGamepad.dpad
        let menu = dualShockGamepad.buttonMenu // 'Option' button on DualShock controller
        
        // DualShock profile guarantees clickable thumbsticks
        let leftThumbstickButton = dualShockGamepad.leftThumbstickButton! // L3
        let rightThumbstickButton = dualShockGamepad.rightThumbstickButton! // R3
        
        // DualShock profile guarantees options ('Share') button is present.
        let options = dualShockGamepad.buttonOptions!
        
        // DualShock profile guarantees home ('PS' logo) button is present.
        let ps = dualShockGamepad.buttonHome!
        // Remember to set `preferredSystemGestureState` to
        // `GCSystemGestureStateDisabled` if you intend to use
        // the Home button in your app or game.
        ps.preferredSystemGestureState = .disabled
        
        // DualShock controller features a clickable touchpad
        
        let touchpadButton = dualShockGamepad.touchpadButton
        
        let primaryTouch: GCControllerDirectionPad = dualShockGamepad.touchpadPrimary
        let secondaryTouch: GCControllerDirectionPad = dualShockGamepad.touchpadSecondary
    }
```

### DualSense

The DualSense profile guarantees the device has all of the controls found on a DualSense controller.  The `GCDualSenseGamepad` class subclasses `GCExtendedGamepad`.  All controls guaranteed by the Extended profile are guaranteed by the DualSense profile.  The following optional controls in the Extended profile are guaranteed by the DualSense profile:

* Thumbstick buttons (clickable thumbsticks) - left (`GCInputLeftThumbstickButton`), and right (`GCInputRightThumbstickButton`).  DualSense controllers have clickable thumbsticks.
* Home button (`GCInputButtonHome`).  DualSense controllers include an 'PS' button that is the MFi Home button equivalent.
* Options button (`GCInputButtonOptions`).  DualSense controllers include a 'Create' button that is the MFi Options button equivalent.

```swift
    // Check if the controller supports the DualSense profile
    
    if let dualSenseGamepad: GCDualSenseGamepad = controller.extendedGamepad as? GCDualSenseGamepad {
        let aButton = dualSenseGamepad.buttonA // Cross Button
        let bButton = dualSenseGamepad.buttonB // Circle Button
        let xButton = dualSenseGamepad.buttonX // Square Button
        let yButton = dualSenseGamepad.buttonY // Triangle Button
        let leftShoulder = dualSenseGamepad.leftShoulder // L1
        let rightShoulder = dualSenseGamepad.rightShoulder // R1
        let leftThumbstick = dualSenseGamepad.leftThumbstick
        let rightThumbstick = dualSenseGamepad.rightThumbstick
        let dpad = dualSenseGamepad.dpad
        let menu = dualSenseGamepad.buttonMenu // 'Option' button on DualShock controller
        
        // The DualSense has adaptive triggers
        let leftTrigger: GCDualSenseAdaptiveTrigger = dualSenseGamepad.leftTrigger // L2
        let rightTrigger: GCDualSenseAdaptiveTrigger = dualSenseGamepad.rightTrigger // R2
        
        // DualSense profile guarantees clickable thumbsticks
        let leftThumbstickButton = dualSenseGamepad.leftThumbstickButton! // L3
        let rightThumbstickButton = dualSenseGamepad.rightThumbstickButton! // R3
        
        // DualSense profile guarantees options ('Create') button is present.
        let options = dualSenseGamepad.buttonOptions!
        
        // DualSense profile guarantees home ('PS' logo) button is present.
        let ps = dualSenseGamepad.buttonHome!
        // Remember to set `preferredSystemGestureState` to
        // `GCSystemGestureStateDisabled` if you intend to use
        // the Home button in your app or game.
        ps.preferredSystemGestureState = .disabled
        
        // DualSense controller features a clickable touchpad
        
        let touchpadButton = dualSenseGamepad.touchpadButton
        
        let primaryTouch: GCControllerDirectionPad = dualSenseGamepad.touchpadPrimary
        let secondaryTouch: GCControllerDirectionPad = dualSenseGamepad.touchpadSecondary
    }
```

**Mapping the touchpad click to a game button:** Games that use the touchpad click as a functional button (map, inventory, select) should map `touchpadButton.pressed` into the game's existing button constants. The touchpad click typically fills the same role as Xbox Back/View — map it to the same bit so existing gameplay logic works unchanged:

```objc
    // Map the touchpad click to the game's Back/View button equivalent.
    BOOL touchpadPressed = NO;
    if ([controller.extendedGamepad isKindOfClass:[GCDualSenseGamepad class]]) {
        touchpadPressed = ((GCDualSenseGamepad*)controller.extendedGamepad).touchpadButton.pressed;
    }
    else if ([controller.extendedGamepad isKindOfClass:[GCDualShockGamepad class]]) {
        touchpadPressed = ((GCDualShockGamepad*)controller.extendedGamepad).touchpadButton.pressed;
    }
    // Feed touchpadPressed into the game's input system as the Back/View/Select action.
```

This captures only the click — touch/swipe coordinates are available via `touchpadPrimary`/`touchpadSecondary` but most ported games only need the button press. The modern input APIs do not support touchpad elements, so this requires the profile-based path.


## Key Concepts

### Input hierarchy

Inputs are properties of elements.

An **element** is a named control on a device that the user interacts with.  The 'A' button is an element.  The 'B' button is a (separate) element.  The left thumbstick is an element.  The direction pad (dpad) is an element.  And so on.

An **input** is the representation of a specific model of interaction the element is capable of measuring.  A button element contains a contact machanism capable of detecting boolean press state.  Some buttons feature potentiaometers that can detect displacement or "press amount".

Four top-level element types are defined.  Each type is represented by a subclass of `GCControllerElement`. 

| Protocol | Interaction model | Example |
|---|---|---|
| `GCControllerButtonInput` | An element that asserts only while pressed. | A button or momentary contact switch. |
| `GCControllerAxisInput` | An element that the user rotates or measures position along an axis. | One axis of a thumbstick. |
| `GCControllerDirectionPad` | A common grouping of 2 axis inputs. | A direction pad; a thumbstick. |
| `GCControllerTouchpad` | A touch-based two axis input with a notion of "touch state" | (Not used). |

Elements can be nested under other elements.  A `GCControllerDirectionPad` exposes an X and Y `GCControllerAxisInput`.  The full element hierarchy is shown below, as well as the inputs supported on each element type.

```
GCControllerElement
    /// Read this property to determine whether the element reports more than 
    /// just digital values, such as decimal ranges between 0 and 1.
    (property) analog: Bool
    GCControllerButtonInput
        /// A normalized value for the input, between [0, 1]. 
        (property) .value: Float
        /// The binary press state of the button.
        (property) .pressed: Bool
    GCControllerAxisInput
        /// A normalized value for the input, between [-1, 1].
        (property) .value: Float
    GCControllerDirectionPad
        /// The child element for the measured value along the horizontal axis.
        (property) .xAxis: GCControllerAxisInput
        /// The child element for the measured value along the vertical axis.
        (property) .yAxis: GCControllerAxisInput
        /// The child element for the measured positive component along the vertical axis.
        (property) .up: GCControllerButtonInput
        /// The child element for the measured negative component along the vertical axis.
        (property) .down: GCControllerButtonInput
        /// The child element for the measured negative component along the horizontal axis.
        (property) .left: GCControllerButtonInput
        /// The child element for the measured positive component along the horizontal axis.
        (property) .right: GCControllerButtonInput
```

**TIP:** When your code needs to interpret a d-pad as four buttons, read the press state from the child `up, down, left, right` elements instead of interpreting the value from the `xAixs, yAxis` child elements.  Some game controllers feature direction pads that support pressing the left+right or up+down directions simultaneously.  The press states of the `up, down, left, right` inputs will reflect correctly in this case.  The `xAixs, yAxis` inputs will sum the positive and negative direction values to a reported value of `0`.


## Working with Element Representations

Each physical input elements on a device is represented by an object that is subclass of to `GCControllerElement`.  You access these objects using the properties on the profile classes - `GCExtendedGamepad`, `GCGamepad`, `GCMicroGamepad`, etc - or via collections on `GCPhysicalInputProfile`:

```objc
/**
 The following properties allow for runtime lookup of any input element on a profile, when provided with a valid alias.

 @example extendedGamepad.elements["Button A"] == extendedGamepad.buttonA // YES
 @example extendedGamepad.dpads["Left Thumbstick"] == extendedGamepad.leftThumbstick // YES
 @example extendedGamepad.dpads["Button B"] // returns nil, "Button B" is not a GCControllerDirectionPad
*/
@property (nonatomic, readonly, strong) NSDictionary<NSString *, GCDeviceElement *> *elements API_AVAILABLE(macos(11.0), ios(14.0), tvos(14.0));
@property (nonatomic, readonly, strong) NSDictionary<NSString *, GCDeviceButtonInput *> *buttons API_AVAILABLE(macos(11.0), ios(14.0), tvos(14.0));
@property (nonatomic, readonly, strong) NSDictionary<NSString *, GCDeviceAxisInput *> *axes API_AVAILABLE(macos(11.0), ios(14.0), tvos(14.0));
@property (nonatomic, readonly, strong) NSDictionary<NSString *, GCDeviceDirectionPad *> *dpads API_AVAILABLE(macos(11.0), ios(14.0), tvos(14.0));
@property (nonatomic, readonly, strong) NSDictionary<NSString *, GCDeviceTouchpad *> *touchpads API_AVAILABLE(macos(11.0), ios(14.0), tvos(14.0));
```

The `elements` collection is a superset of the other collections.  The keys for these collections are element *semantic names*.  The same element may be identified by multiple names.  See `./input-element-names.md` for a list of semantic names and which element each name identfies on a device.

```objc
// On a controller supportng the Extended profile, these expressions return the same object.
controller.physicalInputProfile.elements[GCInputLeftThumbstick]
controller.physicalInputProfile.dpads[GCInputLeftThumbstick]
controller.extendedGamepad.leftThumbstick
```

### Element Attributes

Each element can be queried for a localized name (string) and a glyph to show in UI.  These names and glyphs accurately reflect the underlying controller device - PlayStation glyphs and names are returned for PlayStation controllers, Xbox glyphs and names are returned for Xbox controllers.

```swift
    let aButton: GCControllerButtonInput = ... 
    
    if let displayName: String = aButton.localizedName {
        // Show the value of displayName in intstructional UI that
        // refers to the 'A' button element.
        //
        //    "Press \(displayName) to jump!"
        //
    }
    if let symbolName: String = aButton.sfSymbolsName {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: aButton.localizedName)
        // Show the symbol image in instructional UI that refers to the
        // 'A' button element.
    }
```

If the user remaps controls in the system settings, the names and glyphs update accordingly.  In the above example, if the user had remapped the 'B' button to the 'A' button, `aButton.localizedName` would return `"Button B"` because that is the button the user would press to jump.

### Digital vs Analog Input

Check the `.analog` property on a `GCControllerElement` object to determine whether the represented element can produce more than just digital values, such as decimal ranges between 0 and 1.

```swift
let extendedGamepad: GCExtendedGamepad = ...

// Not all triggers can produce analog values (e.g, Nintendo controllers do not 
// include potentiometers in the triggers).
let leftTriggerIsAnalog = extendedGamepad.leftTrigger.isAnalog

// A very small number of game controller include direction pads in lieu of 
// thumbsticks.  These controllers are still eligible to support the 'Extended'
// profile as long as there are three direction pads (a direction pad + two
// direction pads to replace the two thumbsticks).
let leftThumbstickIsAnalog = extendedGamepad.leftThumbstick.isAnalog
```


## Receiving Input

The profile-based physical input APIs can be used in one of two different modes: **Callback** and **Live Polling**.

**IMPORTANT:**: The GameController framework applies deadzone and saturation to device input before delivering it to your application.  Do NOT apply your own deadzone or satuation to input obtained through the GameController framework.

### Callback

Your application registers blocks that are scheduled on a dispatch queue when values of elements change.

The queue that registered blocks are scheduled on is the `GCController.handlerQueue`, which defaults to the main queue.

```swift
    let extendedGamepad: GCExtendedGamepad = ...
    
    // OPTION 1: Register callbacks on individual elements
    
    extendedGamepad.buttonA.pressedChangedHandler = { (button: GCControllerButtonInput, value: Float, pressed: Bool) in
        // Scheduled when 'A' button pressed state changes
    }
    
    extendedGamepad.leftTrigger.pressedChangedHandler = { (button: GCControllerButtonInput, value: Float, pressed: Bool) in
        // Scheduled when left trigger pressed state changes
    }
    extendedGamepad.leftTrigger.valueChangedHandler = { (button: GCControllerButtonInput, value: Float, pressed: Bool) in
        // Scheduled when left trigger value changes.
        //
        // For digital buttons, value only changes between 'pressed' and
        // 'not pressed' states.
        // For analog buttons (e.g, triggers), value changes as the user
        // displaces the button (pulls the trigger).
    }
    
    extendedGamepad.leftThumbstick.valueChangedHandler = { (dpad: GCControllerDirectionPad, xAxis: Float, yAxis: Float) in
        // Scheduled when left thumbstick position changes.
        // xAxis and yAxis contain normalized values between [0, 1]
        //   -1 is left or down
        //    1 is right or up
        //    0 is neutral
    }
    
    // OPTION 2: Register callback with the profile
    
    extendedGamepad.valueChangedHandler = { (extendedGamepad: GCExtendedGamepad, element: GCControllerElement) in
        // Scheduled when any element changes
        // 'element' is the modified element
        if element === extendedGamepad.buttonA {
            let aButtonPressed = extendedGamepad.buttonA.isPressed
            // ...
        }
        else if element === extendedGamepad.leftTrigger {
            let leftTriggerPressed = extendedGamepad.leftTrigger.isPressed
            let leftTriggerValue: Float = extendedGamepad.leftTrigger.value
            // ...
        }
        else if element === extendedGamepad.leftThumbstick {
            let leftThumbstickX = extendedGamepad.leftThumbstick.xAxis.value
            let leftThumbstickY = extendedGamepad.leftThumbstick.yAxis.value
            // ...
        }
    }
    
    // `GCPhysicalInputProfile` also exposes a `valueDidChangeHandler`.
    // Because `GCExtendedGamepad` subclasses `GCPhysicalInputProfile`,
    // either handler (or both) may be configured.
    extendedGamepad.valueDidChangeHandler = { (profile: GCPhysicalInputProfile, element: GCControllerElement) in
        
    }
```

Prefer to register callbacks on the individual element objects.  With the profile's `valueChangedHandler` callback, you do not receive the value of the element at the time the block was scheduled.  This forces your code to read the *current* value from the element, which may have changed since the handler was scheduled.


### Live Polling

Your code reads the latest values of all inputs that it is interested in during each iteration of your "game loop".

```swift
    // Assume this function is called during each iteration ("tick") of your
    // game loop.
    func handleInput(for controller: GCController) {
        let input = controller.input
        
        // Elements on a profile are modified on the controller's handler
        // queue.  The modification is *not* atomic.  Accessing the profile
        // or its elements off-queue is subject to data races.
        dispatchPrecondition(condition: .onQueue(controller.handlerQueue))
        
        // Assume we previously checked that `controller` supports the
        // Extended profile.
        let extendedGamepad = controller.extendedGamepad!
        
        // OPTION 1: Read and handle input on the queue.
        
        let aButtonPressed = extendedGamepad.buttonA.isPressed
        let leftTriggerPressed = extendedGamepad.leftTrigger.isPressed
        let leftTriggerValue: Float = extendedGamepad.leftTrigger.value
        let leftThumbstickX = extendedGamepad.leftThumbstick.xAxis.value
        let leftThumbstickY = extendedGamepad.leftThumbstick.yAxis.value
        // ...
        
        // OPTION 2: Capture a snapshot of current input state.
        // You can transfer the snapshot to a different queue or thread
        // to read and handle the input.  Snapshots are immutable and can be
        // accessed from any thread without risk of data races.
        
        let snapshot = extendedGamepad.capture()
        
        // These reads can happen on another thread.
        let aButtonPressed = snapshot.buttonA.isPressed
        let leftTriggerPressed = snapshot.leftTrigger.isPressed
        let leftTriggerValue: Float = snapshot.leftTrigger.value
        let leftThumbstickX = snapshot.leftThumbstick.xAxis.value
        let leftThumbstickY = snapshot.leftThumbstick.yAxis.value
    }
```
