# Inspecting the Controller Device

This document discusses what attributes of the device the GameController framework makes available to your application, and how those attributes are intended to be used.

## Overview

The `GCController` class presents common abstraction over gamepad and joystick devices from different manufacturers.  The API **intentionally** provides limited insight into the make and model of the underlying device - THIS IS BY DESIGN.

The attributes that `GCController` does make available are intended to help your application or game properly represent the controller in its user interface.

#### Vendor Name

The `GCController.vendorName` returns a display name (string) for the controller, suitable for showing in your user interface.

Use the value from the `vendorName` property when your application needs to refer to the device in your user interface.  

**IMPORTANT:** Do not compare this string against known values.  Users are able to rename their game controller devices in system settings, and these custom names will be returned by `GCController.vendorName`.

#### Product Category

The `GCController.productCategory` returns a string value identifying the broad product category the device belongs to.  This string may be compared against the following constants:

```
    func handleConnection(_ controller: GCController) {
        let productCategory = controller.productCategory
        
        if productCategory == GCProductCategoryDualShock4 {
            // Consider showing DualSHOCK4 artwork in your UI when referring to
            // this controller.
            //
            // IMPORTANT: Do NOT assume that `controller.extendedGamepad` is a
            //            `GCDualShockGamepad`.
        }
        else if productCategory == GCProductCategoryDualSense {
            // Consider showing DualSense artwork in your UI when referring to
            // this controller.
            //
            // IMPORTANT: Do NOT assume that `controller.extendedGamepad` is a
            //            `GCDualSenseGamepad`.
        }
        else if productCategory == GCProductCategoryXboxOne {
            // Consider showing Xbox artwork in your UI when referring to
            // this controller.
            //
            // IMPORTANT: Do NOT assume that `controller.extendedGamepad` is a
            //            `GCXboxGamepad`.
        }
        else if productCategory == GCProductCategoryMFi {
            // This controller is an MFi-licensed controller.
            //
            // Show generic (Xbox-like) artwork in your UI when referring to
            // this controller.
        }
        else if productCategory == GCProductCategoryHID {
            // This controller is some other HID-compatible game controller.
            //
            // Inspect the available physical input elements on this
            // controller and show appropriate artwork.
        }
        else if productCategory == GCProductCategoryArcadeStick {
            // This controller is an Arcade Stick (Fight Stick) form factor.
        }
        else {
            // Always handle unknown product categories.
            //
            // Inspect the available physical input elements on this
            // controller and show appropriate artwork.
        }
    }
```

Use the value from the `productCategory` property to select appropriate artwork for the device to show in your user interface.  For example, a help screen in your application may show a wireframe of the device with labels indicating the in-game action performed by each button.  Your designer will likely have prepared variations of this UI for PlayStation, Xbox, and generic game controllers.  You would use the `productCategory` to select which of these assets to display.

**IMPORTANT**: Do NOT make assumptions about controller features based on `productCategory`.  Do NOT assume that `GCProductCategoryDualShock4` implies the controller supports motion input, or has a touchpad.  Do NOT assume that `GCProductCategoryDualSense` implies support for haptics and adaptive triggers.  Fix all code that currently makes such assumptions.


## Check controller compatibility

If your application requires a minimum set of available inputs, check whether they are present when the controller connects.  Not all controllers have triggers and thumbsticks.  Try to offer a fallback experience for these controllers - for example, a simplified control scheme for the player character.

```
    func handleConnection(_ controller: GCController) {
    
        // Check available input elements.
        //
        // Assume our game requires a direction pad and six action buttons
        // for minimal control experience.
        
        // OPTION 1: Using modern input APIs (recommended)
        
        let modernInput = controller.input
        
        let aButton = modernInput.buttons[.a]
        let bButton = modernInput.buttons[.b]
        let xButton = modernInput.buttons[.x]
        let yButton = modernInput.buttons[.y]
        let leftShoulder = modernInput.buttons[.leftShoulder]
        let rightShoulder = modernInput.buttons[.rightShoulder]
        let leftTrigger = modernInput.buttons[.leftTrigger]
        let rightTrigger = modernInput.buttons[.rightTrigger]
        let leftThumbstick = modernInput.dpads[.leftThumbstick]
        let rightThumbstick = modernInput.dpads[.rightThumbstick]
        let directionPad = modernInput.dpads[.directionPad]
        // Button for pausing/accessing game menu.
        let menuButton = modernInput.buttons[.menu]
        // Back buttons are located on the underside of more advanced
        // controllers (e.g, paddle buttons on the Xbox Elite controller).
        let leftBackButton = modernInput.buttons[.backLeftButton(position: 0)]
        let rightBackButton = modernInput.buttons[.backRightButton(position: 0)]
        
        // Check if the controller satisfies minimum requirements
        if directionPad != nil && aButton != nil && bButton != nil && xButton != nil && yButton != nil && menuButton != nil && leftShoulder != nil && rightShoulder != nil {
            // Check if the controller has enough inputs for more advanced player
            // control.
            if leftTrigger != nil && rightTrigger != nil && leftThumbstick != nil && rightThumbstick != nil {
                // Check if the controller has back buttons.
                if leftBackButton != nil && rightBackButton != nil {
                    // Consider binding these buttons to convienience features
                    // in the game.
                }
                // Use advanced controls
            }
            else {
                // Use basic controls
            }
        }
        else {
            // This controller is not usable for the game.
            // You should indicate in your UI that the controller is detected,
            // but is not usable.
        }
        
        
        // OPTION 2: Using the profile-based input APIs
        
        let physicalInputProfile = controller.physicalInputProfile
        
        // The "extended gamepad" profile guarantees:
        //  - A/B/X/Y buttons
        //  - Shoulder buttons
        //  - Trigger buttons
        //  - Direction pad
        //  - Left and right thumbstick
        //  - Menu button
        if let extendedGamepad = physicalInputProfile as? GCExtendedGamepad {
            // Use advanced controls
            
        }
        // The "gamepad" profile guarantees:
        //  - A/B/X/Y buttons
        //  - Shoulder buttons
        //  - Direction pad
        //  - Menu button
        else if let gamepad = physicalInputProfile as? GCGamepad {
            // Use basic controls
        }
        else {
            // This controller is not usable for the game.
            // You should indicate in your UI that the controller is detected,
            // but is not usable.
        }
        
    }
```

Check for advanced controller features when the controller connects.

```
        // Check for a touchpad element (found on the DualSHOCK 4, DualSense,
        // and some third-party PlayStation controllers)
        
        let physicalInputProfile = controller.physicalInputProfile
        
        // OPTION 2: Check for touchpad elements individually. (Recommended)
        
        if let touchpadPrimaryTouch = physicalInputProfile.dpads[GCInputDualShockTouchpadOne],
           let touchpadSecondaryTouch = physicalInputProfile.dpads[GCInputDualShockTouchpadTwo],
           let touchpadButton = physicalInputProfile.buttons[GCInputDualShockTouchpadButton]
        {
            
        }
        
        // OPTION 2: Check for `GCDualShockGamepad`.
        
        // A `physicalInputProfile` that is a `GCDualShockGamepad` (or subclass)
        // implies the device features all of the input elements found on a
        // DualShock 4 controller.
        if let dsGamepad = physicalInputProfile as? GCDualShockGamepad {
            // The position of the first finger on the touchpad
            let touchpadPrimaryTouch = dsGamepad.touchpadPrimary
            // The position of the second finger on the touchpad
            let touchpadecondaryTouch = dsGamepad.touchpadSecondary
            // The entire touchpad also serves as a clickable button.
            let touchpadButton = dsGamepad.touchpadButton
        }
        
        
        // Check if the device features motion input (has an IMU)
        if let motionInput: GCMotion = controller.motion {
            
        }
        
        // Check if the device features haptic/rumble actuators.
        if let haptics: GCDeviceHaptics = controller.haptics {
            
        }
```

