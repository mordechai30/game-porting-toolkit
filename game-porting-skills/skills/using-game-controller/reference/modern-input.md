# Modern Physical Input

This document discusses the design and use of the modern APIs for accessing and monitoring game controller physical input.


## Overview

The GameController framework introduced a modernized set of physical input APIs in macOS 14, iOS 17, tvOS 17, and visionOS 1.  These APIs replace the older profile-based physical input APIs: `GCExtendedGamepad`, `GCGamepad`, `GCMicroGamepad`, `GCXboxGamepad`, `GCDualShockGamepad`, `GCDualSenseGamepad`, and `GCPhysicalInputProfile`.

The following classes and protocols comprise the modern physical input APIs.

```
# Top-level types
<GCDevicePhysicalInputState>
<GCDevicePhysicalInput>
GCControllerInputState
GCControllerLiveInput
# Element Types
<GCPhysicalInputElement>
<GCButtonElement>
<GCAxisElement>
<GCSwitchElement>
<GCDirectionPadElement>
# Input Types
<GCLinearInput>
<GCAxisInput>
<GCAxis2DInput>
<GCRelativeInput>
<GCPressedStateInput>
<GCTouchedStateInput>
<GCSwitchPositionInput>
# Utility Types
<GCDevicePhysicalInputStateDiff>
<GCPhysicalInputElementCollection>
<GCPhysicalInputSource>
<GCPhysicalInputExtents>
```

Prefer to use the modern physical input APIs when writing code that targets the above Apple OS versions or later.  You can also determine at runtime whether it is safe to use the modern physical input APIs.

```objc
    if (@available(macOS 14, iOS 17, tvOS 17, *)) {
        // Ok to use modern physical input APIs
    } else {
        // Use older profile-based physical input APIs
    }
```


## Key Concepts

### Input hierarchy

Inputs are grouped under elements.

An **element** is a named control on a device that the user interacts with.  The 'A' button is an element.  The 'B' button is a (separate) element.  The left thumbstick is an element.  The direction pad (dpad) is an element.  And so on.

An **input** is the representation of a specific model of interaction the element is capable of measuring.  A button element contains a contact machanism capable of detecting boolean press state.  But on some devices a button element may also include a capacitive sensor capable of detecting contact of the user's finger before the button is physically pressed.  These are two distinct 'inputs' of the button element.

Four top-level element types are defined.  Each type is represented by a protocol conforming to `GCPhysicalInputElement`.  

| Protocol | Interaction model | Example |
|---|---|---|
| `GCButtonElement` | An element that asserts only while pressed. | A button or momentary contact switch. |
| `GCAxisElement` | An element that the user rotates or repositions along an axis. | A steering wheel. |
| `GCSwitchElement` | An element that can be set to one of several fixed positions and maintains that position until further interaction. | A rotary or toggle selector switch. |
| `GCDirectionPadElement` | An element that can be tilted in different directions along two axes. | A direction pad; a thumbstick. |

An element may conform to multiple types.  The object that represents a clickable thumbstick element conforms to both the `GCButtonElement` and `GCDirectionPadElement` protocols because the element satisfies the interaction model of both types.

The full element hierarchy is shown below, as well as the inputs suported on each element type.

```
<GCPhysicalInputElement>
    <GCButtonElement>
       /// The pressed state (and press amount for analog buttons).
       (property) .pressedInput: <GCLinearInput & GCPressedStateInput>
       /// The touch/contact state, if the button includes a capacitive sensor.
       (property) .touchedInput: <GCTouchedStateInput>?
    <GCSwitchElement>
        /// The position of the switch.
        (property) .positionInput: <GCSwitchPositionInput>
    <GCAxisElement>
        /// The value along the measured axis as the position between a lower and upper bound.  Not all axis elements measure a bounded value.
        (property) .absoluteInput: <GCAxisInput>?
        /// The value along the measured axis as the change (delta) since the prior input state.
        (property) .relativeInput: <GCRelativeInput>
    <GCDirectionPadElement>
        /// The combined XY position input.
        (property) .xyAxes: <GCAxis2DInput>
        /// The horizontal component of the position input.
        (property) .xAxis: <GCAxisInput>
        /// The vertical component of the position input.
        (property) .yAxis: <GCAxisInput>
        /// The positive vertical component of the position input.
        (property) .up: <GCLinearInput, GCPressedStateInput> 
        /// The negative vertical component of the position input.
        (property) .down: <GCLinearInput, GCPressedStateInput> 
        /// The negative horizontal component of the position input.
        (property) .left: <GCLinearInput, GCPressedStateInput> 
        /// The positive horizontal component of the position input.
        (property) .right: <GCLinearInput, GCPressedStateInput> 
```

**TIP:** When your code needs to interpret a d-pad as four buttons, read the press state from the `up, down, left, right` inputs instead of interpreting the value from the `xAixs, yAxis, or xyAxes` inputs.  Some game controllers feature direction pads that support pressing the left+right or up+down directions simultaneously.  The press states of the `up, down, left, right` inputs will reflect correctly in this case.  The `xAixs, yAxis` inputs will sum the positive and negative direction values to a reported value of `0`.

Seven input types are defined.  These types do NOT indicate the specific model of interaction; that is established by the documentation associated with the property on the element type from which the input is accessed.  Input types define either a) the kind of data the input produces, or b) the state the input represents.  Each input type is represented by a protocol.

| Protocol | Data produced |
|---|---|
| `GCLinearInput` | Normalized values in the unit interval - between `[0, 1]` |
| `GCAxisInput` | Normalized values - between `[-1, 1]` - along an axis with a fixed origin. |
| `GCAxis2DInput` | Pair of normalized values - between `[-1, 1]` - along two axes with fixed origin. |
| `GCRelativeInput` | Normalized relative value (delta) |
| `GCPressedStateInput` | A boolean press state. |
| `GCTouchedStateInput` | A boolean touch state. |
| `GCSwitchPositionInput` | An inteneger value for the position of a switch. |


### Input as a sequence of states

Snapshots are first class objects in the modern physical input API.  When an update (e.g, HID input report) from the device arrives, the `GCController` creates a copy of the current input state, applies the update to it, and publishes it as the latest (i.e, current) state in an internal ring buffer.

An instance of `GCControllerInputState` (which conforms to `<GCDevicePhysicalInputState>`) represents the complete state of a device's physical inputs at a moment in time.  A `GCControllerInputState` object, and the element and input objects obtained from it, are immutable.  Propeties on these obejcts may be read by multiple threads concurrently without data races.

The `GCControllerLiveInput` class (which conforms to `<GCDevicePhysicalInput>`) subclasses `GCControllerInputState` and represents the "live" (latest) state of the device's physical inputs.  When you access elements and their inputs directly through the `GCControllerLiveInput` object, the data is being read from the latest state in the ring buffer.  Each access is atomic and multiple threads may concurrently access `GCControllerLiveInput` without data races.  Beware however that the latest device state can change between each atomic access.

```
let aButtonPressed = controller.input.buttons[.a]?.pressedInput.pressed // 'A' button press read from latest state
// -> Update arrives, latest device state replaced with new/updated state
let bButtonPressed = controller.input.buttons[.b]?.pressedInput.pressed // 'B' button press read from new latest state
```

You can avoid this by calling `-capture` on the `GCControllerLiveInput` to obtain a `GCControllerInputState` object containing a snapshot of the current state, then reading element and input values from the snapshot.  Calling `-capture` is a fast operation.

#### Input Timestamps

The `<GCDevicePhysicalInputState>` object provides a `lastEventTimestamp` property that returns the timestamp of the device update that produced the input state.  This timestamp typically corresponds to when the device update was received by the host's kernel.  The time domain of this timestamp is host time (`mach_absolute_time`) converted into seconds.

Each input object conforming to `<GC*Input>` also provides a `lastValueTimestamp` property that returns the timestamp of the device update that last modified the input's value.  This timestamp may be less than the `lastEventTimestamp` of the containing `<GCDevicePhysicalInputState>` if the input's value is unchanged in later updates received from the device.


## Working with Element Representations

Each physical input element on a device is represented by an object that conforms to `<GCPhysicalInputElement>`, and one or more of its specialization protocols (e.g, `<GCButtonElement>`).  You access these objects via collections on objects conforming to `<GCDevicePhysicalInputState>`:

```objc
/**
 The following properties allow for runtime lookup of any input element when provided with a valid alias.

 @example input.elements[GCInputButtonA]
 @example input.dpads[GCInputLeftThumbstick]
 @example input.dpads[GCInputButtonB] // fails, "Button B" is not a DirectionPad
 */
@property (readonly) GCPhysicalInputElementCollection<GCInputElementName, id<GCPhysicalInputElement>> *elements NS_REFINED_FOR_SWIFT;
@property (readonly) GCPhysicalInputElementCollection<GCInputButtonName, id<GCButtonElement>> *buttons NS_REFINED_FOR_SWIFT;
@property (readonly) GCPhysicalInputElementCollection<GCInputAxisName, id<GCAxisElement>> *axes NS_REFINED_FOR_SWIFT;
@property (readonly) GCPhysicalInputElementCollection<GCInputSwitchName, id<GCSwitchElement>> *switches NS_REFINED_FOR_SWIFT;
@property (readonly) GCPhysicalInputElementCollection<GCInputDirectionPadName, id<GCDirectionPadElement>> *dpads NS_REFINED_FOR_SWIFT;
```

```swift
public extension GCDevicePhysicalInputState {
    var elements: GCPhysicalInputElementCollection<GCPhysicalInputElement>
    var buttons: GCPhysicalInputElementCollection<GCButtonElement>
    var axes: GCPhysicalInputElementCollection<GCAxisElement>
    var switches: GCPhysicalInputElementCollection<GCSwitchElement>
    var dpads: GCPhysicalInputElementCollection<GCDirectionPadElement>
}
```

The `elements` collection is a superset of the other collections.  The keys for these collections are element *semantic names*.  The same element may be identified by multiple names.  See `./input-element-names.md` for a list of semantic names and which element each name identfies on a device.

```objc
// On a controller with clickable left thumbtick, these expressions return the same object.  The object conforms to both <GCDirectionPadElement> and <GCButtonElement>.
input.elements[GCInputLeftThumbstick]
input.elements[GCInputLeftThumbstickButton]
input.dpads[GCInputLeftThumbstick]
input.buttons[GCInputLeftThumbstickButton]
```

### Element Attributes

Each element can return a localized name (string) and a glyph to show in UI.  These names and glyphs accurately reflect the underlying controller device - PlayStation glyphs and names are returned for PlayStation controllers, Xbox glyphs and names are returned for Xbox controllers.

```swift
    if let aButton = controller.input.buttons[.a] {
        if let displayName: String = aButton.localizedName {
            // Show the value of displayName in intstructional UI that
            // refers to the 'A' button element.
            //
            //    "Press \(displayName) to jump!"
            //
        }
        if let symbolName = aButton.sfSymbolsName {
            let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: aButton.localizedName)
            // Show the symbol image in instructional UI that refers to the
            // 'A' button element.
        }
    }
```

If the user remaps controls in the system settings, the names and glyphs update accordingly.  In the above example, if the user had remapped the 'B' button to the 'A' button, `aButton.localizedName` would return `"Button B"` because that is the button the user would press to jump.


## Receiving Input

The modern physical input APIs can be used in any of four different modes: **Callback**, **Callback Polling**, **Live Polling**, or **Buffered Polling**.

* Use **Callback** mode when:
    - Your application is event driven.
    - Your code responds to each input individually.  You do not need to handle simulatenous press of 'A' + 'B' button as a distinct action.
* Use **Callback Polling** mode when:
    - Your application is event driven.
    - Your code needs to examine each input state change received from the device as a whole.  For example, to look for a simulatenous press of 'A' + 'B' buttons.
* Use **Live Polling** mode when:
    - Your application or engine already has a constantly running loop that is used for simulation, rendering, etc.
    - You only care about the latest state of the game controller's inputs.
* Use **Buffered Polling** mode when:
    - Your application or engine already has a constantly running loop that is used for simulation, rendering, etc.
    - Your code needs to track every input state change received from the device since the previous iteration of your loop.

Live Polling and Buffered Polling yield the lowest possible input latency for code already designed around a fixed "game loop" (not a run loop like `CFRunLoop`).

**IMPORTANT:**: The GameController framework applies deadzone and saturation to device input before delivering it to your application.  Do NOT apply your own deadzone or satuation to input obtained through the GameController framework.


### Callback

Your application registers blocks that are scheduled on a dispatch queue when the values of inputs change.  There are two places your application can register these blocks:

* On the `elementValueDidChangeHandler` of the `<GCDevicePhysicalInput>` object.  When an update from the device is received and a new input state produced, the block is scheduled once for every element with changed input between the previous and new input states.
* On the `<GC*Input>` objects representing specific inputs.  For example, `controller.input.buttons[.a]?.pressedDidChangeHandler`.  When an update from the device is received and a new input state produced, the block is only scheduled if the value of the input changed between the previous and new states.

The queue that registered blocks are scheduled on is the `GCDevicePhysicalInput.queue`, which defaults to the `GCController.handlerQueue`, which defaults to the main queue.

Example of registering callbacks when a controller connects.

```swift
    func handleConnection(_ controller: GCController) {
        let input: GCControllerLiveInput = controller.input
        
        input.buttons[.a]?.pressedInput.pressedDidChangeHandler = { (element: GCPhysicalInputElement, input: GCPressedStateInput, pressed: Bool) in
            // Scheduled when the 'A' button is pressed or released.
        }
        input.buttons[.b]?.pressedInput.pressedDidChangeHandler = { (element: GCPhysicalInputElement, input: GCPressedStateInput, pressed: Bool) in
            // Scheduled when the 'B' button is pressed or released.
        }
        input.dpads[.leftThumbstick]?.xyAxes.valueDidChangeHandler = { (element: GCPhysicalInputElement, input: GCAxis2DInput, value: GCPoint2) in
            // Scheduled when left thumbstick direction changes.
        }
        
        // ALTERNATIVELY, register a single `elementValueDidChangeHandler`
        
        input.elementValueDidChangeHandler = { (physicalInput: GCDevicePhysicalInput, element: GCPhysicalInputElement) in
            // Scheduled when an input of any element changes.
            if element === physicalInput.buttons[.a] {
                let aButtonPressed: Bool = (element as! GCButtonElement).pressedInput.isPressed
                // ...
            }
            else if element === physicalInput.buttons[.a] {
                let bButtonPressed: Bool = (element as! GCButtonElement).pressedInput.isPressed
                // ...
            }
            else if element === physicalInput.dpads[.leftThumbstick] {
                let thumbstickValue: GCPoint2 = (element as! GCDirectionPadElement).xyAxes.value
                // ...
            }
        }
    }
    
    @objc func controllerDidConnect(_ notification: Notification) {
        if let controller = notification.object as? GCController {
            self.handleConnection(controller)
        }
    }
```

Prefer to register individual callbacks on `<GC*Input>` objects.  With a `elementValueDidChangeHandler` callback, you do not receive the specific input that changed or the value of the input at the time the block was scheduled.  This forces your code to read the current value from the `<GCDevicePhysicalInput>`, which may have changed since the handler was scheduled.

```
-> 'A' button pressed; device update received; new input state created.  `elementValueDidChangeHandler` is scheduled for `A` button element.
-> 'A' button released; device update received; new input state created.  `elementValueDidChangeHandler` is scheduled for `A` button element.
-> `elementValueDidChangeHandler` called on queue.  Reads `(element as! GCButtonElement).pressedInput.isPressed == false`.
-> `elementValueDidChangeHandler` called on queue.  Reads `(element as! GCButtonElement).pressedInput.isPressed == false`.
```

The `elementValueDidChangeHandler` may be used as a "finalization step" by your code, since invocations of `elementValueDidChangeHandler` for an input state are scheduled *after* invocations of individual callbacks on `<GC*Input>` objects.


### Live Polling

Your code reads the latest values of all inputs that it is interested in during each iteration of your "game loop".  It is recommended to call `-capture` on the `<GCDevicePhysicalInput>` and read the input values from the returned snapshot.

```swift
    // Assume this function is called during each iteration ("tick") of your
    // game loop.
    func handleInput(for controller: GCController) {
        let input = controller.input
        // Capture a snapshot of the current controller input state.  Even
        // if updated input from the device arrives before this method
        // returns, the contents of the snapshot will not change.
        //
        // Capturing and reading from a snapshot is free from data races.
        let currentInputState = input.capture()
        
        let aButtonPressed = currentInputState.buttons[.a]?.pressedInput.isPressed
        let bButtonPressed = currentInputState.buttons[.b]?.pressedInput.isPressed
        let leftThumbstickDirection = currentInputState.dpads[.leftThumbstick]?.xyAxes.value
        
        // Act on the input...
    }
```


### Buffered Polling

Buffered polling uses the internal ring buffer maintained by the `GCDevicePhysicalInput` as a queue.  When an update from the device arrives, the GameController framework creates a new input state and appends it to the queue.  During each iteration of your "game loop", you drain the queue and handle each input state sequentially.  This enables your code to handle actions, such as pressing snd releasing a button, that occur between iterations of your loop.

Buffered polling requires setup when the controller connects.  Your code configures the `inputStateQueueDepth` of the `<GCDevicePhysicalInput>` to specify the maximum number of input states to buffer.  If the application does not drain the pending input states in the queue before this limit is reached, older input states will be discarded - resulting in "missing" input state changes.  Game controllers typically send input to the host every 4ms, 7.5ms, 8ms, or 15ms.  For a "game loop" that polls for input every frame (typically 16.6ms or 31.25ms), a buffer value of `8` is sufficient.  However a larger value of `20` is recommended, to leave margin in case your loop stalls and can not process input for a period of time.

During each iteration of your loop, call `-nextInputState` on the `<GCDevicePhysicalInput>` to pop the oldest input state from the queue.  The returned object conforms to `<GCDevicePhysicalInputState & GCDevicePhysicalInputStateDiff>`.  Once all pending input states are drained from the queue, `-nextInputState` returns `nil`.

```swift
    // Assume this function is called during each iteration ("tick") of your
    // game loop.
    func handleInput(for controller: GCController) {
        let input = controller.input
        
        while let oldestInputState = input.nextInputState() {
            let aButtonPressed: Bool
            
            if let aButton = oldestInputState.buttons[.a] {
                aButtonPressed = aButton.pressedInput.isPressed
                let aButtonChange = oldestInputState.change(for: aButton)
                if aButtonChange == .unknownChange {
                    // This is either the very first input state, or the previous input state was purged from the buffer before we dequeued it.
                }
            } else {
                aButtonPressed = false
            }
            
            // Act on this input state...
        }
    }
    
    func handleConnection(_ controller: GCController) {
        let input: GCControllerLiveInput = controller.input
        
        // When setting up the newly connected controller, expand the input queue depth to 20.
        // Up to 20 input states will be buffered.
        input.inputStateQueueDepth = 20
        
        ...
    }
    
    @objc func controllerDidConnect(_ notification: Notification) {
        if let controller = notification.object as? GCController {
            self.handleConnection(controller)
        }
    }
```

#### Callback Polling

Callback polling works similarly to live polling or buffered polling, except that instead of reading input during each tick of a "game loop" your code registers a block with the `inputStateAvailableHandler` of `<GCDevicePhysicalInput>`.  This block is scheduled when a new input state becomes available.  Once scheduled, the block is not eligable to be scheduled again until all pending input states have been dequeued, by calling `-capture` until it returns `nil`. 

```objc
    input.inputStateQueueDepth = 20;
    input.inputStateAvailableHandler = ^(__kindof id<GCDevicePhysicalInput> physicalInput) {
        id<GCDevicePhysicalInputState, GCDevicePhysicalInputStateDiff> nextInputState;
        while ((nextInputState = [physicalInput nextInputState])) {
            // You can grab the individual states of all elements that your app
            // is interested in.
            id<GCButtonElement> buttonA = nextInputState.buttons[GCInputButtonA];
            BOOL buttonAPressed = buttonA.pressedInput.pressed;
            if (buttonAPressed) {
                // Handle button A pressed
            }
 
            // Your code can first query whether an element's input value changed
            // from the prior input state.
            GCDevicePhysicalInputElementChange buttonAChange = [nextInputState changeForElement:buttonA];
            if (buttonAChange == GCDevicePhysicalInputElementChanged) {
                // Handle button A input changed
            }
 
            // Or, your code can request an enumerator of elements with input
            // values that changed from the prior input state
            for (id<GCPhysicalInputElement> changedElement in nextInputState.changedElements) {
 
            }
        }
    };
```


## Known issues and limitations of the modern physical input APIs

The modern physical input APIs have the following known limitations.  If these apply to your code, continue to use the older profile-based input APIs.

### Not supported with the AppleTV remote

The connected AppleTV remote is represented by a `GCController` object.  However the `GCControllerLiveInput` retrieved from the `GCController.input` property for this device reports zero button and dpad elements.  Check if the `GCController.productCategory` is `GCProductCategorySiriRemote1stGen`, `GCProductCategorySiriRemote2ndGen`, `GCProductCategoryControlCenterRemote` or `GCProductCategoryUniversalElectronicsRemote` to determine if a `GCController` represents an AppleTV remote.  Use `GCController.microGamepad` to access physical input from these devices.

### Not supported with `GCVirtualController` or `TCTouchController`

When calling `-connect` on an instance of `GCVirtualController` or `TCTouchController`, a `GCController` object is created and reported as connected.  However the `GCControllerLiveInput` retrieved from the `GCController.input` property for this device reports zero button and dpad elements.  Check if the `GCController.productCategory` is `"Touch Controller"`.  Use `GCController.extendedGamepad` or `GCController.physicalInputProfile` to access input from these virtual controllers.

### DualShock and DualSense touchpad element not available

The modern input APIs do not currently define a representation for a touchpad element type.  You will need to use the profile-based input APIs to read input from the touchpad on DualShock and DualSense controllers.

### DualSense adaptive trigger force feedback functions not available

Control of the adaptive triggers on DualSense controllers are accessed through the `GCDualSenseAdaptiveTrigger` subclass of `GCControllerButtonInput`, which is part of the profile-based input APIs.  You can read DualSense trigger input using the modern physical input APIs.  But you will need to access the `GCDualSenseAdaptiveTrigger` through the profile-based input APIs to configure force feedback effects.
