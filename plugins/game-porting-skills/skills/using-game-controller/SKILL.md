---
name: using-game-controller
description: ALWAYS use when the user has any question about game controller input on Apple platforms — whether writing new code, porting from Windows, or modernizing an existing implementation. Trigger when working with the GCController API or GameController framework (controller lifecycle, connect/disconnect, current controller, player index, profile-based input, modern input API, polling, callbacks, haptics, rumble, adaptive triggers, motion/IMU, or on-screen controls), or when porting Windows controller code such as XInput, DirectInput, GameInput, RawInput, joystickapi.h, IOKit HID, IOHIDManager, or HidP_* APIs. Do NOT trigger for keyboard or mouse input.
---

## Overview

A comprehensive guide to Apple's GameController framework - covering Swift/ObjC APIs, platform considerations, and porting from Windows.

Use the GameController framework when writing code for Apple platforms that interacts with game controllers.  The `GCController` API presents a common abstraction over gamepad and joystick input devices.  The GameController framework supports popular game controllers including the Sony DualSHOCK 4, Sony DualSense, Nintendo Switch Pro, and Microsoft Xbox controllers.  Advanced features available on these controllers - IMU, Rumble, and Adaptive Triggers (force feedback) - are supported.  

When porting Windows code that calls RawInput (e.g, `RegisterRawInputDevices`) or HID (`HidP_*`) APIs to interfce with Sony, Nintendo, and other non-Xbox controllers, AVOID writing equivalent code that uses IOKit and `IOHIDManager` APIs.  PREFER to re-write the code to use the abstractions provided by the `GCController` API instead.


---

## Framework Concepts

* **Device-centric model** - Each `GCController` represents a connected gamepad or joystick device.  You obtain the currently connected devices from `GCController.controllers`, listen for new connections (`GCControllerDidConnectNotification`) and disconnections (`GCControllerDidDisconnectNotification`), and monitor for input from the one(s) you are interested in.
* **Component architecture** - Game controller device features are exposed from sub-objects retrieved from the `GCController` object.
    - Physical input from control surfaces (buttons, thumbsticks) is accessed through the `GCControllerLiveInput` object returned from the `GCController.input` property (modern API), or through the `GCPhysicalInputProfile` (or subclass thereof) object returned from `GCController.physicalInputProfile` (older profile based API).
    - Motion input from an integrated IMU is accessed through the `GCMotion` object returned from the `GCController.motion` property.  If this property returns `nil`, the controller does not feature an integrated IMU and does not produce motion input.
    - Haptic and rumble commands are sent to a `CHHapticEngine` created from the `GCDeviceHaptics` object returned from `GCController.haptics` property.  If this property returns `nil`, the controller does not feature integrated haptic or rumble actuators.
* **Physical Input Hierachy** - Input from buttons, thumbsticks, dpad, etc are nested in a two-level hierarchy.  The first level is the element that produces the input (the specific button, thumbstick, or dpad).  The second level is the input source.  A button typically reports a boolean press state, but may also report a scalar displacement value (e.g, for a trigger).  A thumbstick reports X and Y scalar components, and may also report a boolean press state if the thumbstick is clickable.  Each is represented as a distinct input nested under the element.
* **Named Input Elements** - Buttons, thumbsticks, dpad, and other physical input elements are looked up by semantic (string) name from `GCControllerLiveInput` or `GCPhysicalInputProfile`.  A `GCController` may represent a device with elements beyond those found on an Xbox controller.


---

## Topics

| Topic | Description | See |
| Getting Started | Discovering controllers; controller lifecycle. | This file, "Controller Lifecycle" |
| Inspecting the Controller Device | Checking device compatibility, and representing the device in your UI. | `reference/inspect-the-device.md` |
| Element names | How elements (buttons, stick, triggers) are identified on a controller. | `reference/input-element-names.md` |
| Modern input | Receiving input (buttons, stick, triggers) via callbacks, or reading input from a polling loop.  Supporting input from any controller. | `reference/modern-input.md` |
| Profile-based input | Receiving input from controllers that support one of several Apple-defined profiles. | `reference/profile-based-input.md` |
| Haptics / rumble | Play haptic patterns and rumble effects to a controller. | `reference/haptics.md` |
| Platform notes | Platform best practices and quirks (macOS vs iOS vs tvOS vs visionOS) | `reference/platform-notes.md` |

The following is a list of important APIs in the GameController framework, and where you can learn more about them.

```
# Devices (This file, "Controller Lifecycle")
<GCDevice>                              https://developer.apple.com/documentation/gamecontroller/gcdevice
GCController                            https://developer.apple.com/documentation/gamecontroller/gccontroller

# Modern Physical Input (`reference/modern-input.md`)
<GCDevicePhysicalInputState>            https://developer.apple.com/documentation/gamecontroller/gcdevicephysicalinputstate
<GCDevicePhysicalInput>                 https://developer.apple.com/documentation/gamecontroller/gcdevicephysicalinput
<GCDevicePhysicalInputStateDiff>        https://developer.apple.com/documentation/gamecontroller/gcdevicephysicalinputstatediff
<GCPhysicalInputSource>                 https://developer.apple.com/documentation/gamecontroller/gcphysicalinputsource
<GCPhysicalInputExtents>                https://developer.apple.com/documentation/gamecontroller/gcphysicalinputextents
<GCPhysicalInputElementCollection>      https://developer.apple.com/documentation/gamecontroller/gcphysicalinputelementcollection-c.class?language=objc
<GCPhysicalInputElement>                https://developer.apple.com/documentation/gamecontroller/gcphysicalinputelement
<GCButtonElement>                       https://developer.apple.com/documentation/gamecontroller/gcbuttonelement
<GCAxisElement>                         https://developer.apple.com/documentation/gamecontroller/gcaxiselement
<GCSwitchElement>                       https://developer.apple.com/documentation/gamecontroller/gcswitchelement
<GCDirectionPadElement>                 https://developer.apple.com/documentation/gamecontroller/gcdirectionpadelement
<GCLinearInput>                         https://developer.apple.com/documentation/gamecontroller/gclinearinput
<GCAxisInput>                           https://developer.apple.com/documentation/gamecontroller/gcaxisinput
<GCAxis2DInput>                         https://developer.apple.com/documentation/gamecontroller/gcaxis2dinput
<GCRelativeInput>                       https://developer.apple.com/documentation/gamecontroller/gcrelativeinput
<GCPressedStateInput>                   https://developer.apple.com/documentation/gamecontroller/gcpressedstateinput
<GCTouchedStateInput>                   https://developer.apple.com/documentation/gamecontroller/gctouchedstateinput
<GCSwitchPositionInput>                 https://developer.apple.com/documentation/gamecontroller/gcswitchpositioninput
GCControllerInputState                  https://developer.apple.com/documentation/gamecontroller/gccontrollerinputstate
GCControllerLiveInput                   https://developer.apple.com/documentation/gamecontroller/gccontrollerliveinput

# Profile-based Physical Input (`reference/profile-based-input.md`)
GCPhysicalInputProfile                  https://developer.apple.com/documentation/gamecontroller/gcphysicalinputprofile
GCMicroGamepad                          https://developer.apple.com/documentation/gamecontroller/gcmicrogamepad
GCDirectionalGamepad                    https://developer.apple.com/documentation/gamecontroller/gcdirectionalgamepad
GCGamepad                               https://developer.apple.com/documentation/gamecontroller/gcgamepad
GCExtendedGamepad                       https://developer.apple.com/documentation/gamecontroller/gcextendedgamepad
GCXboxGamepad                           https://developer.apple.com/documentation/gamecontroller/gcxboxgamepad
GCDualShockGamepad                      https://developer.apple.com/documentation/gamecontroller/gcdualshockgamepad
GCDualSenseGamepad                      https://developer.apple.com/documentation/gamecontroller/gcdualsensegamepad
GCControllerElement (aliased to GCDeviceElement)            https://developer.apple.com/documentation/gamecontroller/gccontrollerelement
GCControllerButtonInput (aliased to GCDeviceButtonInput)    https://developer.apple.com/documentation/gamecontroller/gccontrollerbuttoninput
GCControllerAxisInput (aliased to GCDeviceAxisInput)        https://developer.apple.com/documentation/gamecontroller/gccontrolleraxisinput
GCControllerDirectionPad (aliased to GCDeviceDirectionPad)  https://developer.apple.com/documentation/gamecontroller/gccontrollerdirectionpad
GCControllerTouchpad (aliased to GCDeviceTouchpad)          https://developer.apple.com/documentation/gamecontroller/gccontrollertouchpad
GCDualSenseAdaptiveTrigger              https://developer.apple.com/documentation/gamecontroller/gcdualsenseadaptivetrigger
```


---

## Setup

The GameController framework is part of the macOS, iOS, tvOS, and visionOS SDKs.

### Objective-C

```objc
#import <GameController/GameController.h>
or
@import GameController
```

### Swift

```swift
import GameController
```


---

## Best Practices

### Things to DO

When writing new code or modernizing existing code, follow these current best practices.

#### Add Info.plist keys

Ensure the following key is present in the application's Information Property List (`Info.plist`):

```
<key>GCSupportsControllerUserInteraction</key>
<true/>
```

This key with a `true` value tells the system that the application supports game controller input.


### Things to AVOID

When writing new code or modernizing existing code, look for these anti-patterns and suggest a resolution.

#### Do NOT assume controller inputs or features are available based on the product category

The product category returned from `GCController.productCategory` is intended to help your application display appropriate artwork for the controller only.
* Do NOT write code that assumes (or asserts) that `nullable` (optional) properties return a `non-nil` value, based on a prior product category check.
* Do NOT write code that assumes the object returned by a property or method is a specific sub-class, based on a prior product category check.

```swift
    if controller.productCategory == GCProductCategoryDualSense {
        // WRONG: Do NOT assume controller supports the DualSense profile
        //        because productCategory is GCProductCategoryDualSense.
        let dualSenseGamepad = controller.extendedGamepad as! GCDualSenseGamepad
        let adaptiveLeftTrigger: GCDualSenseAdaptiveTrigger = dualSenseGamepad.leftTrigger
        
        // WRONG: Do NOT assume controller has adaptive trigger because the
        //        productCategory is GCProductCategoryDualSense.
        let adaptiveRightTrigger = controller.physicalInputProfile.buttons[GCInputRightTrigger] as! GCDualSenseAdaptiveTrigger
    }
    
    if controller.productCategory == GCProductCategoryDualShock4 || controller.productCategory == GCProductCategoryDualSense {
        // WRONG: Do NOT assume controller supports motion input because the
        //        productCategory identifies a PlayStation controller
        let motion = controller.motion!
        motion.sensorsActive = true
        
        // WRONG: Do NOT assume controller supports haptics because the
        //        productCategory identifies a PlayStation controller
        let haptics = controller.haptics!
        // WRONG: Do NOT assume a haptics locality is available because the
        //        productCategory identifies a PlayStation controller.
        let hapticsEngine = haptics.createEngine(withLocality: .leftHandle)!
    }
```

Instead, check for controller features and inputs individually.

```swift
    // CORRECT: Check if `controller.extendedGamepad` is a `GCDualSenseGamepad`.
    if let dualSenseGamepad = controller.extendedGamepad as? GCDualSenseGamepad {
        let adaptiveLeftTrigger: GCDualSenseAdaptiveTrigger = dualSenseGamepad.leftTrigger
    }
    else if let extendedGamepad = controller.extendedGamepad {
        // Handle non-DualSense extended gamepad
        let leftTrigger: GCControllerButtonInput = extendedGamepad.leftTrigger
    }
    else {
        // Notify the player their controller is not compatible with the game.
    }
    
    // CORRECT: Check if controller supports motion input (has an IMU)
    if let motion = controller.motion {
        motion.sensorsActive = true
    }
    
    // CORRECT: Check if controller supports haptics
    if let haptics = controller.haptics {
        // CORRECT: Handle failure if `GCHapticsLocalityLeftHandle` is not
        //          available.
        if let hapticsEngine = haptics.createEngine(withLocality: .leftHandle) {
            
        }
        // Fallback to defaut locality.
        else if let hapticsEngine = haptics.createEngine(withLocality: .default) {
            
        }
        else {
            // GCHapticsLocalityDefault is guaranteed to be supported, but
            // errors can occur creating the haptics engine.
        }
    }
```

#### Avoid in-app control remapping features

Apple operating systems allow users to remap game controllers controls in system settings.  You should NOT offer a UI for remapping controls in your application.



---

## Controller Lifecycle

The framework posts a `GCControllerDidConnectNotification` when a controller becomes available to your application (typically when the device connects to the host), and a `GCControllerDidDisconnectNotification` when a controller becomes unavailable (device disconnects from the host).  The `GCController.controllers` array reflects the currently avaiable controllers.  Do not make assumptions about the ordering of this array.

```swift
/// Assume this object manages game controller input sources within your
/// application or engine.
class GameControllerInputManager: NSObject
{
    override init() {
        super.init()
        
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(controllerDidConnect(_:)), name: .GCControllerDidConnect, object: nil)
        notificationCenter.addObserver(self, selector: #selector(controllerDidDisconnect(_:)), name: .GCControllerDidDisconnect, object: nil)
        
        // Handle controllers that are already connected when app launches.
        for controller in GCController.controllers() {
            handleConnection(controller)
        }
    }
    
    deinit {
        let notificationCenter = NotificationCenter.default
        notificationCenter.removeObserver(self, name: .GCControllerDidConnect, object: nil)
        notificationCenter.removeObserver(self, name: .GCControllerDidDisconnect, object: nil)
    }
    
    // Controller connected
    @objc func controllerDidConnect(_ notification: Notification) {
        if let controller = notification.object as? GCController {
            self.handleConnection(controller)
        }
    }
    
    // Controller disconnected
    @objc func controllerDidDisconnect(_ notification: Notification) {
        if let controller = notification.object as? GCController {
            self.handleDisconnection(controller)
        }
    }
}
```

Calls to `+[GCController startWirelessControllerDiscoveryWithCompletionHandler:]` are not necessary and should be removed.  Users pair wireless game controllers in the system Bluetooth settings.


### Current Controller

The framework keeps track of the "current controller".  This is the device that most recently connected, or that input was most recently received from.  Single-player games should use the current controller as their input source.

```swift
/// Assume this object manages game controller input sources within your
/// application or engine.
class GameControllerInputManager: NSObject
{
    // OPTION 1: Listen for notifications when the current controller changes.
    //           Implement this option, if your application prefers to register
    //           callbacks on the `GCController` to receive input.

    override init() {
        super.init()
        
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(controllerDidBecomeCurrent(_:)), name: .GCControllerDidBecomeCurrent, object: nil)
        notificationCenter.addObserver(self, selector: #selector(controllerDidStopBeingCurrent(_:)), name: .GCControllerDidStopBeingCurrent, object: nil)
    }
    
    deinit {
        let notificationCenter = NotificationCenter.default
        notificationCenter.removeObserver(self, name: .GCControllerDidBecomeCurrent, object: nil)
        notificationCenter.removeObserver(self, name: .GCControllerDidStopBeingCurrent, object: nil)
    }
    
    @objc func controllerDidBecomeCurrent(_ notification: Notification) {
        if let controller = notification.object as? GCController {
            self.becomeCurrent(controller)
        }
    }

    @objc func controllerDidStopBeingCurrent(_ notification: Notification) {
        if let controller = notification.object as? GCController {
            self.resignCurrent(controller)
        }
    }
    
    func becomeCurrent(_ controller: GCController) {
        // Register callbacks on the new current controller.
    }
    
    func resignCurrent(_ controller: GCController) {
        // Unregister callbacks on the previous current controller
    }
    
    // OPTION 2: When polling controller input during your game loop, read
    //           from the current controller.  Implement this option if your
    //           application prefers to poll for input.
    
    // Assume this function is called during each iteration ("tick") of your
    // game loop.
    func handleInput() {
        // NOTE: Accessing the current controller is an atomic operation.
        if let currentController = GCController.current {
            // Read input from the current controller
            
            let aButtonPressed = currentController.physicalInputProfile.buttons[GCInputButtonA]?.isPressed ?? false
            let leftTriggerPressed = currentController.physicalInputProfile.buttons[GCInputLeftTrigger]?.isPressed ?? false
            let leftTriggerValue: Float = currentController.physicalInputProfile.buttons[GCInputLeftTrigger]?.value ?? .zero
            let leftThumbstickX = currentController.physicalInputProfile.dpads[GCInputLeftThumbstick]?.xAxis.value ?? .zero
            let leftThumbstickY = currentController.physicalInputProfile.dpads[GCInputLeftThumbstick]?.yAxis.value ?? .zero
            
            // Handle input...
        }
    }
```

### Player Index Assignment

For multiplayer games, set `controller.playerIndex` to map each controller to a player slot.  This also controls the player indicator LEDs on supported controllers (e.g, DualSense, Xbox Wireless):

```swift
/// Assume this object manages game controller input sources within your
/// application or engine.
class GameControllerInputManager: NSObject
{
    var playerControllers: InlineArray<4, GCController?>
    
    func nextAvailablePlayerIndex() -> Int? {
        for i in playerControllers.indices {
            if playerControllers[i] == nil {
                return i
            }
        }
        return nil
    }
    
    func handleConnection(_ controller: GCController) {
        if let playerIndex = nextAvailablePlayerIndex() {
            self.playerControllers[playerIndex] = controller
            // NOTE: In C/C++/Objective-C, check if playerIndex is less than
            // (<) GCControllerPlayerIndex4
            if let gcPlayerIndex = GCControllerPlayerIndex(rawValue: playerIndex) {
                controller.playerIndex = gcPlayerIndex
            }
        }
        
        ...
    }
    
    func handleDisconnection(_ controller: GCController) {
        controller.playerIndex = .indexUnset
        // Remove controller from the playerControllers array
        ...
    }
}
```

For single player games, avoid modifying the `playerIndex`.

**IMPORTANT:** AVOID using the `playerIndex` value as an index into an array, or key into a collection.  The `playerIndex` is *shared state* - it can be modified by other clients, and therefore may change unexpectedly.  If you need to associate app-specific data to a `GCController` object, use the Objective-C runtime's *associated objects* feature.

### Lifecycle Implementation Details

A `GCController` instance represents the lifetime of a single device connection.  When the same device disconnects and later reconnects, a new `GCController` instance is created.

When a device connects, the framework takes the following actions on the main thread (main dispatch queue):

* Adds the new `GCController` to the `GCController.controllers` array.
* Posts the `GCControllerDidStopBeingCurrentNotification` notification with the current `GCController` (skipped if there is no current controller).
* Assigns the new `GCController` to the `GCController.current` property.
* Posts the `GCControllerDidBecomeCurrentNotification` with the new `GCController`.
* Posts the `GCControllerDidConnectNotification` with the new `GCController`.

When a device disconnects, the framework takes the following actions on the main thread (main dispatch queue):

* Removes the `GCController` from the `GCController.controllers` array.
* If the disconnected device is the current controller:
    - Posts the `GCControllerDidStopBeingCurrentNotification` notification with the disconnected `GCController`.
    - Assigns the previous current controller to the `GCController.current` property.
    - Posts the `GCControllerDidBecomeCurrentNotification` with the new current `GCController`.
* Posts the `GCControllerDidDisconnectNotification` with the disconnected `GCController`.

When input is received from a device, the framework makes the device the current `GCController`:

* Posts the `GCControllerDidStopBeingCurrentNotification` notification with the previous current `GCController` (skipped if there is no current controller).
* Assigns the new current `GCController` to the `GCController.current` property.
* Posts the `GCControllerDidBecomeCurrentNotification` with the new current `GCController`.


---

## Next Steps

### Platform setup

tvOS and visionOS require additional setup to receive game controller input using the GameController framework; discussed in `reference/platform-notes.md`.


### Input handling

The GameController framework has offered profile-based APIs for accessing and monitoring game controller physical input since its inception.  Recent OS versions added modern physical input APIs, supporting fast snapshots and atomic polling.

Prefer to use the modern physical input APIs (`reference/modern-input.md`) unless:
- Your application uses `GCVirtualController` or `TCTouchController` to display on-screen touch controls on iOS.
- Your application uses GameController framework to handle input from the AppleTV remote on tvOS.
- Your application supports PlayStation controller-specific features: TouchPad or Adaptive Triggers.
- Your application supports macOS 13, iOS 16, tvOS 16, or earlier.

Otherwise, use the profile-based physical input APIs (`reference/profile-based-input.md`).


---

## Modernizing Existing Code

If you are updating a codebase that is already using the GameController framework to interface with game controllers, look for usages of these outdated APIs or patterns and suggest to modernize them.


#### Modernize input snapshots

Look for existing code using the following deprecated APIs:

```
GCMicroGamepadSnapshotDataFromNSData
NSDataFromGCMicroGamepadSnapshotData
GCMicroGamepadSnapShotDataV100FromNSData
NSDataFromGCMicroGamepadSnapShotDataV100
GCGamepadSnapShotDataV100FromNSData
NSDataFromGCGamepadSnapShotDataV100
GCExtendedGamepadSnapshotDataFromNSData
NSDataFromGCExtendedGamepadSnapshotData
GCExtendedGamepadSnapShotDataV100FromNSData
NSDataFromGCExtendedGamepadSnapShotDataV100
```

Update to use snapshot techniques discussed in `reference/modern-input.md` or `reference/profile-based-input.md`.
