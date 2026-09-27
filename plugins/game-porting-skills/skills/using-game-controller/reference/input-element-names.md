# Locating Physical Input Elements

This document discusses how physical input elements (buttons, thumbsticks, dpads) on a game controller are identified in the GameController framework.


## Overview

Physical input elements on a game controller device are identified by a *semantic name* - a string identifier.  These identifiers are often the label on the element or related to the type and location of the element.

**NOTE** that face button elements are named by manufacturer label, not by position.  `GCInputButtonA` corresponds to the 'A' button on an Xbox controller, the 'A' button on a Nintendo controller, and the 'Cross' button on a PlayStation controller.  Other platform's input APIs commonly treat the 'A' button as always being the bottom button in the ABXY diamond, but this is not the case in GameController framework.


## Standard Identifiers

The GameController framework defines constants for all element identifiers.  Prefer to use these constants rather than hardcoding the underlying string value in your code.

The type of the constant indicates which kind of element it identifiers - a button, switch, axis, or direction pad (which includes thumbstick).  Use the matching collection property on `GCControllerLiveInput` or `GCPhysicalInputProfile` to lookup the corresponding element.

```swift
// Lookup the 'A' button element in GCControllerLiveInput
let buttonA = controller.input.buttons[.a]
// Lookup the 'A' button element in GCPhysicalInputProfile
let buttonA = controller.physicalInputProfile.buttons[GCInputButtonA]

// Lookup the left thumbstick element in GCControllerLiveInput
let leftThumbstick = controller.input.dpads[.leftThumbstick]
// Lookup the 'A' button element in GCPhysicalInputProfile
let leftThumbstick = controller.physicalInputProfile.dpads[GCInputLeftThumbstick]
```

```objc
// Lookup the 'A' button element in GCControllerLiveInput
__auto_type buttonA = controller.input.buttons[GCInputButtonA]
// Lookup the 'A' button element in GCPhysicalInputProfile
__auto_type buttonA = controller.physicalInputProfile.buttons[GCInputButtonA]

// Lookup the left thumbstick element in GCControllerLiveInput
__auto_type leftThumbstick = controller.input.dpads[GCInputLeftThumbstick]
// Lookup the left thumbstick element in GCPhysicalInputProfile
__auto_type leftThumbstick = controller.physicalInputProfile.dpads[GCInputLeftThumbstick]
```

#### Face Button Element Identifiers

| String Value | Constant (ObjC) | Swift Static Member |
|---|---|---|
| `"Button A"` | `GCInputButtonA` | `GCButtonElementName.a` |
| `"Button B"` | `GCInputButtonB` | `GCButtonElementName.b` |
| `"Button X"` | `GCInputButtonX` | `GCButtonElementName.x` |
| `"Button Y"` | `GCInputButtonY` | `GCButtonElementName.y` |

```objc
/**
 *  Identifies the face button element with label "A" on a controller.
 *
 *  Standard gamepads differ on where they position the "A" button among the
 *  face buttons.  Xbox and MFi gamepads place the "A" button at the bottom.
 *  Other controllers place it on the left.
 *
 *  \c GCInputButtonA always identifies the button with label "A", regardless
 *  of where that button is positioned on the controller face.  For PlayStation
 *  gamepads, \c GCInputButtonA identifies the "cross" button.
 *
 *  If the controller does not have a face button with label "A", then
 *  \c GCInputButtonA identifies the primary face button (the button most
 *  ergonomic for quick or spammy actions).
 */
GAMECONTROLLER_EXPORT GCInputButtonName GCInputButtonA API_AVAILABLE(macos(11.0), ios(14.0), tvos(14.0));

/**
 *  Identifies the face button element with label "B" on a controller.
 *
 *  Standard gamepads differ on where they position the "B" button among the
 *  face buttons.  Xbox and MFi gamepads place the "B" button on the left.
 *  Other controllers place it on the bottom.
 *
 *  \c GCInputButtonB always identifies the button with label "B", regardless
 *  of where that button is positioned on the controller face.  For PlayStation
 *  gamepads, \c GCInputButtonB identifies the "circle" button.
 */
GAMECONTROLLER_EXPORT GCInputButtonName GCInputButtonB API_AVAILABLE(macos(11.0), ios(14.0), tvos(14.0));

/**
 *  Identifies the face button element with label "X" on a controller.
 *
 *  Standard gamepads differ on where they position the "X" button among the
 *  face buttons.  Xbox and MFi gamepads place the "X" button on the right.
 *  Other controllers place it at the top.
 *
 *  \c GCInputButtonX always identifies the button with label "X", regardless
 *  of where that button is positioned on the controller face.  For PlayStation
 *  gamepads, \c GCInputButtonX identifies the "square" button.
 */
GAMECONTROLLER_EXPORT GCInputButtonName GCInputButtonX API_AVAILABLE(macos(11.0), ios(14.0), tvos(14.0));

/**
 *  Identifies the face button element with label "Y" on a controller.
 *
 *  Standard gamepads differ on where they position the "Y" button among the
 *  face buttons.  Xbox and MFi gamepads place the "Y" button at the top.
 *  Other controllers place it on the left.
 *
 *  \c GCInputButtonY always identifies the button with label "Y", regardless
 *  of where that button is positioned on the controller face.  For PlayStation
 *  gamepads, \c GCInputButtonY identifies the "triangle" button.
 */
GAMECONTROLLER_EXPORT GCInputButtonName GCInputButtonY API_AVAILABLE(macos(11.0), ios(14.0), tvos(14.0));
```

#### Shoulder and Trigger Button Element Identifiers

| String Value | Constant (ObjC) | Swift Static Member |
|---|---|---|
| `"Left Shoulder"` | `GCInputLeftShoulder` | `GCButtonElementName.leftShoulder` |
| `"Right Shoulder"` | `GCInputRightShoulder` | `GCButtonElementName.rightShoulder` |
| `"Left Bumper"` | `GCInputLeftBumper` | `GCButtonElementName.leftBumper` |
| `"Right Bumper"` | `GCInputRightBumper` | `GCButtonElementName.rightBumper` |
| `"Left Trigger"` | `GCInputLeftTrigger` | `GCButtonElementName.leftTrigger` |
| `"Right Trigger"` | `GCInputRightTrigger` | `GCButtonElementName.rightTrigger` |

```objc
/**
 *  Identifies the button element located at the front-left edge of a gamepad.
 *
 *  A user typically manipulates a left shoulder button - sometimes called
 *  left bumper button - using the first (index) or second (middle) finger of
 *  their left hand.
 *
 *  This button is often referred to as the "L Button", "Left Bumper", or "L1".
 */
GAMECONTROLLER_EXPORT GCInputButtonName GCInputLeftShoulder API_AVAILABLE(macos(11.0), ios(14.0), tvos(14.0));

/**
 *  Identifies the button element located at the front-right edge of a gamepad.
 *
 *  A user typically manipulates a right shoulder button - sometimes called
 *  right bumper button - using the first (index) or second (middle) finger of
 *  their right hand.
 *
 *  This button is often referred to as the "R Button", "Right Bumper", or "R1".
 */
GAMECONTROLLER_EXPORT GCInputButtonName GCInputRightShoulder API_AVAILABLE(macos(11.0), ios(14.0), tvos(14.0));

/**
 *  Identifies the button element located at the front-left of a gamepad,
 *  between the left shoulder button and the gamepad's horizontal center.
 */
GAMECONTROLLER_EXPORT GCInputButtonName GCInputLeftBumper API_AVAILABLE(macos(14.4), ios(17.4), tvos(17.4), visionos(1.1));

/**
 *  Identifies the button element located at the front-right of a gamepad,
 *  between the right shoulder button and the horizontal center.
 */
GAMECONTROLLER_EXPORT GCInputButtonName GCInputRightBumper API_AVAILABLE(macos(14.4), ios(17.4), tvos(17.4), visionos(1.1));

/**
 *  Identifies the trigger element located at the front-left edge of a gamepad.
 *
 *  A trigger button is located below any shoulder button.
 */
GAMECONTROLLER_EXPORT GCInputButtonName GCInputLeftTrigger API_AVAILABLE(macos(11.0), ios(14.0), tvos(14.0));

/**
 *  Identifies the trigger element located at the front-right edge of a gamepad.
 *
 *  A trigger button is located below any shoulder button.
 */
GAMECONTROLLER_EXPORT GCInputButtonName GCInputRightTrigger API_AVAILABLE(macos(11.0), ios(14.0), tvos(14.0));
```

#### Direction Pad (Dpad) and Thumbstick Identifiers

Thumbsticks and direction pads are represented by the same types in GameController framework.

| String Value | Constant (ObjC) | Swift Static Member |
|---|---|---|
| `"Direction Pad"` | `GCInputDirectionPad` | `GCDirectionPadElementName.directionPad` |
| `"Left Thumbstick"` | `GCInputLeftThumbstick` | `GCDirectionPadElementName.leftThumbstick` |
| `"Right Thumbstick"` | `GCInputRightThumbstick` | `GCDirectionPadElementName.rightThumbstick` |
| `"Left Thumbstick Button"` | `GCInputLeftThumbstickButton` | `GCButtonElementName.leftThumbstickButton` |
| `"Right Thumbstick Button"` | `GCInputRightThumbstickButton` | `GCButtonElementName.rightThumbstickButton` |

```objc
GAMECONTROLLER_EXPORT GCInputDirectionPadName GCInputDirectionPad API_AVAILABLE(macos(11.0), ios(14.0), tvos(14.0));

/**
 *  Identifies an analog stick element that a user typically manipulates using
 *  their left thumb.
 */
GAMECONTROLLER_EXPORT GCInputDirectionPadName GCInputLeftThumbstick API_AVAILABLE(macos(11.0), ios(14.0), tvos(14.0));

/**
 *  Identifies an analog stick element that a user typically manipulates using
 *  their right thumb.
 */
GAMECONTROLLER_EXPORT GCInputDirectionPadName GCInputRightThumbstick API_AVAILABLE(macos(11.0), ios(14.0), tvos(14.0));

/**
 *  Identifies the clickable element of an analog stick element that a user
 *  typically manipulates using their left thumb.
 */
GAMECONTROLLER_EXPORT GCInputButtonName GCInputLeftThumbstickButton API_AVAILABLE(macos(11.0), ios(14.0), tvos(14.0));

/**
 *  Identifies the clickable element of an analog stick element that a user
 *  typically manipulates using their right thumb.
 */
GAMECONTROLLER_EXPORT GCInputButtonName GCInputRightThumbstickButton API_AVAILABLE(macos(11.0), ios(14.0), tvos(14.0));
```

#### Back Button Element Identifiers

| String Value | Constant (ObjC) | Swift Static Member |
|---|---|---|
| `"Back Left Button 0"` | `GCInputBackLeftButton(0)` | `GCButtonElementName.backLeftButton(0)` |
| `"Back Left Button 1"` | `GCInputBackLeftButton(1)` | `GCButtonElementName.backLeftButton(1)` |
| `"Back Right Button 0"` | `GCInputBackRightButton(1)` | `GCButtonElementName.backRightButton(0)` |
| `"Back Right Button 1"` | `GCInputBackRightButton(1)` | `GCButtonElementName.backRightButton(1)` |

```objc
/*
 * Back Buttons
 *
 * Some gamepads include additional buttons or triggers on their underside.
 * Because the number and layout of bottom buttons can vary by controller, the
 * Game Controller framework identifies them by their ease of operation.  The
 * back left and right buttons at the first position are located nearest the
 * natural rest position of the user's fingers and are suitable for actions
 * requiring repeated inputs.  The buttons at the 'second' position may require
 * the user to move their fingers to press and should be used for less frequent
 * actions.
 *
 * Example view looking at the underside of a gamepad with four back buttons
 * arranged horizontally:
 *
 *     +---------------------------------------------------------------+
 *     |                       Controller top                          |
 *     +---------------------------------------------------------------+
 *     |                                                               |
 *   R | [(R) 0]  [(R) 1]                             [(L) 1]  [(L) 0] | L
 *     |                                                               |
 *     +---------------------------------------------------------------|
 *     |             Controller bottom (nearest the user)              |
 *     +---------------------------------------------------------------+
 */

/* Note: The `position` argument begins at index 0. */
GAMECONTROLLER_EXPORT GCInputButtonName GCInputBackLeftButton(NSInteger position) NS_REFINED_FOR_SWIFT API_AVAILABLE(macos(14.4), ios(17.4), tvos(17.4), visionos(1.1));
GAMECONTROLLER_EXPORT GCInputButtonName GCInputBackRightButton(NSInteger position) NS_REFINED_FOR_SWIFT API_AVAILABLE(macos(14.4), ios(17.4), tvos(17.4), visionos(1.1));
```

#### Function Button Element Identifiers

| String Value | Constant (ObjC) | Swift Static Member |
|---|---|---|
| `"Button Home"` | `GCInputButtonHome` | `GCButtonElementName.home` |
| `"Button Menu"` | `GCInputButtonMenu` | `GCButtonElementName.menu` |
| `"Button Options"` | `GCInputButtonOptions` | `GCButtonElementName.options` |
| `"Button Share"` | `GCInputButtonShare` | `GCButtonElementName.share` |

```objc
GAMECONTROLLER_EXPORT GCInputButtonName GCInputButtonHome API_AVAILABLE(macos(11.0), ios(14.0), tvos(14.0));
GAMECONTROLLER_EXPORT GCInputButtonName GCInputButtonMenu API_AVAILABLE(macos(11.0), ios(14.0), tvos(14.0));
GAMECONTROLLER_EXPORT GCInputButtonName GCInputButtonOptions API_AVAILABLE(macos(11.0), ios(14.0), tvos(14.0));
GAMECONTROLLER_EXPORT GCInputButtonName GCInputButtonShare API_AVAILABLE(macos(12.0), ios(15.0), tvos(15.0));
```

#### PlayStation Controller Elements

These identifiers name elements found on PlayStation controllers.

| String Value | Constant (ObjC) |
|---|---|---|
| `"Touchpad 1"` | `GCInputDualShockTouchpadOne` |
| `"Touchpad 2"` | `GCInputDualShockTouchpadTwo` |
| `"Touchpad Button"` | `GCInputDualShockTouchpadButton` |

```objc
GAMECONTROLLER_EXPORT GCInputDirectionPadName GCInputDualShockTouchpadOne API_AVAILABLE(macos(11.0), ios(14.0), tvos(14.0));
GAMECONTROLLER_EXPORT GCInputDirectionPadName GCInputDualShockTouchpadTwo API_AVAILABLE(macos(11.0), ios(14.0), tvos(14.0));
GAMECONTROLLER_EXPORT GCInputButtonName GCInputDualShockTouchpadButton API_AVAILABLE(macos(11.0), ios(14.0), tvos(14.0));
```

#### Xbox Elite Controller Elements

These identifiers name the paddle elements found on Xbox Elite series controllers.

| String Value | Constant (ObjC) |
|---|---|---|
| `"Paddle 1"` | `GCInputXboxPaddleOne` |
| `"Paddle 2"` | `GCInputXboxPaddleTwo` |
| `"Paddle 3"` | `GCInputXboxPaddleThree` |
| `"Paddle 4"` | `GCInputXboxPaddleFour` |

```objc
GAMECONTROLLER_EXPORT GCInputButtonName GCInputXboxPaddleOne API_AVAILABLE(macos(11.0), ios(14.0), tvos(14.0));
GAMECONTROLLER_EXPORT GCInputButtonName GCInputXboxPaddleTwo API_AVAILABLE(macos(11.0), ios(14.0), tvos(14.0));
GAMECONTROLLER_EXPORT GCInputButtonName GCInputXboxPaddleThree API_AVAILABLE(macos(11.0), ios(14.0), tvos(14.0));
GAMECONTROLLER_EXPORT GCInputButtonName GCInputXboxPaddleFour API_AVAILABLE(macos(11.0), ios(14.0), tvos(14.0));
```


## Game Controller Reference Mapping Table

This table shows how elements on Xbox, PlayStation, and Nintendo controllers are identified in the GameController framework.  

**IMPORTANT**: This table is for reference only, to be used when porting existing code that may be dealing with Xbox/PlayStation/Nintendo controllers specifically.  The GameController framework supports more than Xbox, PlayStation, and Nintendo controllers.  Avoid trying to discern or special case specific controllers when writing code for Apple platforms.  Instead, program to the abstractions provided by the GameController framework.

| Identifier | Xbox | PlayStation | Nintendo |
| `GCInputButtonA` | A | Cross | A |
| `GCInputButtonB` | B | Circle | B |
| `GCInputButtonX` | X | Square | X |
| `GCInputButtonY` | Y | Triangle | Y |
| `GCInputLeftShoulder` | LB | L1 | L |
| `GCInputRightShoulder` | RB | R1 | R |
| `GCInputLeftTrigger` | LT | L2 | ZL |
| `GCInputRightTrigger` | RT | R2 | ZR |
| `GCInputDirectionPad` | Directional pad (D-Pad) | Directional Buttons | +Control Pad |
| `GCInputLeftThumbstick` / `GCInputLeftThumbstickButton` | Left stick | Left stick | Left Stick |
| `GCInputRightThumbstick` / `GCInputRightThumbstickButton` | Right stick | Right stick | Right Stick |
| `GCInputButtonHome` | Xbox button | PS button | HOME button |
| `GCInputButtonMenu` | Menu button | options button | + Button |
| `GCInputButtonOptions` | View button | create button | - Button |
| `GCInputButtonShare` | Share button (Series X|S and later) | N/A | Capture Button |
