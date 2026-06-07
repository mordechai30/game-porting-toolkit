# Handling your game's input

Handle game controller, keyboard, mouse, and multi-touch input through a unified API across macOS and iOS.

## Overview

Common to macOS and iOS, your game can support game controllers and the mouse and keyboard to sense and respond to a player's actions. Additionally, iOS devices recognize up to ten finger touches onscreen simultaneously, creating an even more personal experience where your players directly tap objects and menus onscreen to interact with them.

## Port from other input systems

All gaming platforms offer mechanisms to sense input from your players as they use game controllers, keyboards, and mice. A typical approach is to poll the state of the hardware every game frame, and process that input to update the state of the game simulation.

On Apple devices, the Game Controller framework enables you to both poll and register callbacks to respond to player actions.

If your game logic relies on polling, the Game Controller framework offers a simple-to-use interface with direct access to the connected input devices and the current state of each button, key, and thumbstick. This makes it trivial to port input code.

For example, the following code snippet demonstrates how your game may be polling the state of the first connected game controller and sensing whether the player is pressing button 'A' on another platform:

```objc
XINPUT_STATE state;
ZeroMemory( &state, sizeof(XINPUT_STATE) );

DWORD firstController = 0;
DWORD result = XInputGetState( firstController, &state );
if (result == ERROR_SUCCESS)
{
    if ((state.Gamepad.wButtons & XINPUT_GAMEPAD_A) != 0)
    {
        // Player is pressing button 'A'.
    }
}
```

The Game Controller framework offers a similar, and more syntactically elegant, polling mechanism.

```objc
GCController* controller = GCController.controllers[0];
if (controller.extendedGamepad.buttonA.pressed)
{
    // Player is pressing button 'A'.
}
```

By repeating this logic to all other buttons, you can easily port your input code to Apple devices using the Game Controller framework.

> Note: In Objective-C it is valid to use properties on `nil` objects, so when there's no controller, this if-condition gracefully evaluates to `false`, making the check for success in the original code snippet unnecessary.

The Game Controller framework provides you the same functionality in macOS and iOS, allowing you to easily bring your input to iOS devices.

### Register event callbacks

In addition to polling, the Game Controller framework allows you to register block callbacks for input events. When taking this approach, you set up the callback once at game controller connection time.

```objc
GCController* controller = GCController.controllers[0];
controller.extendedGamepad.buttonA.valueChangedHandler =
    ^(GCControllerButtonInput* button, float value, BOOL pressed) {
        // Handle button 'A' press and release events.
    };
```

This project’s `Controller.mm` file demonstrates how to register to receive notifications each time your player connects and disconnects a physical game controller, and how to set up event callbacks.

## Handle input on touch-first devices

If your game relies on game controller input, you need to consider the situation where your players don’t have a physical controller to use with their iOS device. Unlike with macOS, iOS games can’t fall back to mouse and keyboard input.

For these situations, the Game Controller framework provides you a built-in onscreen virtual game controller you can use. This is a direct simple-to-configure virtual device that allows you to specify what buttons to display and virtually *connect* to the iOS device.

The virtual game controller receives screen tap events from your players and injects them into the same callbacks your game uses for physical game controllers. You don’t need any additional logic to handle its input.

The `iOS/GameApplication.m` file configures a virtual game controller when it determines there are no other physical game controllers connected.

```objc
// Create a configuration object for the virtual game controller
GCVirtualControllerConfiguration* virtualGCConfig = [[GCVirtualControllerConfiguration alloc] init];

// Set its virtual buttons and create it:
virtualGCConfig.elements = [NSSet setWithObjects:GCInputLeftThumbstick, GCInputButtonA, nil];
GCVirtualController* virtualController = [[GCVirtualController alloc] initWithConfiguration:virtualGCConfig];

// Connect the virtual game controller:
[virtualController connectWithReplyHandler:nil];
```

Although you can always summon the virtual game controller, on iOS devices, your players likely still expect to interact with in-game menus and other UI using tap gestures rather than through the onscreen controller.

This is partly for ergonomic reasons, as directly tapping UI elements is more natural than aiming a virtual cursor and pressing a virtual key, but also because the virtual game controller may partially obscure onscreen elements.

In either situation, strive to quickly dismiss the onscreen controller to declutter the view when your player connects a physical game controller.

In this project, the `iOS/GameApplication.m` file presents a virtual game controller when the device has no physical controllers available, and registers callbacks for when the player connects and disconnects game controllers to summon and dismiss the onscreen controls on demand.

Consult the Human Interface Guidelines on [adding touch controls to games](https://developer.apple.com/documentation/gamecontroller/adding_touch_controls_to_games_that_support_game_controllers_in_ios) and [keyboard](https://developer.apple.com/design/human-interface-guidelines/keyboards) for best practices in delivering a great input experience for your players.

## Advertise game controller support on the App Store

This project is preconfigured to advertise support for game controllers in the App Store. This capability, which you can control from the game project’s Signing & Capabilities tab in Xcode, instructs the App Store to display a game controller badge on your app's page. This is a great way to convey to your players that they may enjoy your game with a physical game controller.

## Implement best practices for great input

Best practices for great input include the following:

* Always favor direct touch for menus.
* Show the virtual game controller when no other input methods are available in-game.
* Subscribe to input device connect/disconnect notifications and respond accordingly by showing and hiding the virtual controller as needed.
* When designing touch controls:
    * Expose *semantic* meaning in each button, instead of a generic glyph.
    * Only expose actions relevant to the game’s current context.
    * Avoid obstructing your game’s view when rendering the touch controls.
* Consult the [Designing for games](https://developer.apple.com/design/human-interface-guidelines/designing-for-games) for input best practices.

## Offer legacy input from other platforms

The Game Controller framework is powerful and versatile. If your game heavily relies on other abstractions, the framework makes it easy to adapt between interfaces. Avoid this approach when possible. Favor using the Game Controller interfaces to obtain access to its full capabilities.

When designing a compatibility shim, first make a structure compatible with the other platform's input model.

```cpp
struct GamepadInput
{
    enum Button {
        DPadUp          = 0x0001,
        DPadDown        = 0x0002,
        DPadLeft        = 0x0004,
        DPadRight       = 0x0008,
        Start           = 0x0010,
        Back            = 0x0020,
        LeftThumbstick  = 0x0040,
        RightThumbstick = 0x0080,
        LeftShoulder    = 0x0100,
        RightShoulder   = 0x0200,
        A               = 0x1000,
        B               = 0x2000,
        X               = 0x4000,
        Y               = 0x8000,
    };
    
    uint32_t buttons;
    float leftTriggerPressure;  // normalized to [0,1]
    float rightTriggerPressure; // normalized to [0,1]
    float leftThumbstickX;
    float leftThumbstickY;
    float rightThumbstickX;
    float rightThumbstickY;
};
```

Using Objective-C blocks, it's easy to connect Game Controller events to it by registering a block to handle game controller connect events.

```objc
[NSNotificationCenter.defaultCenter 
    addObserverForName:GCControllerDidConnectNotification
                object: nil
                    queue: nil
            usingBlock:^(NSNotification*  notification) {
                // ... map inputs to structure ...
            }
```

The following code snippet shows how to map the thumbstick values:

```objc
    GCController* controller = (GCController *)(notification.object);
    GCExtendedGamepad* gamepad = controller.extendedGamepad;
    
    gamepad.leftThumbstick.valueChangedHandler = ^(GCControllerDirectionPad * _Nonnull dpad, float xValue, float yValue) {
        _thumbstickXSpeed = xValue;
        gamepadInput.leftThumbstickX = xValue;
        gamepadInput.leftThumbstickY = yValue;
    };

    gamepad.rightThumbstick.valueChangedHandler = ^(GCControllerDirectionPad * _Nonnull dpad, float xValue, float yValue) {
        gamepadInput.rightThumbstickX = xValue;
        gamepadInput.rightThumbstickY = yValue;
    };
    
    gamepad.leftTrigger.valueChangedHandler = ^(GCControllerButtonInput * _Nonnull button, float value, BOOL pressed) {
        gamepadInput.leftTriggerPressure = value;
    };
    
    gamepad.rightTrigger.valueChangedHandler = ^(GCControllerButtonInput * _Nonnull button, float value, BOOL pressed) {
        gamepadInput.rightTriggerPressure = value;
    };
```

Mapping the buttons is similarly easy, and you can simplify the process with a macro.

```objc
#define MAP_GC_INPUT(SRC, DST) \
SRC.valueChangedHandler = ^(GCControllerButtonInput * _Nonnull button, float value, BOOL pressed) { \
gamepadInput.buttons = pressed ? (gamepadInput.buttons | GamepadInput::DST) : (gamepadInput.buttons & ~GamepadInput::DST); }

    MAP_GC_INPUT(gamepad.dpad.up, DPadUp);
    MAP_GC_INPUT(gamepad.dpad.down, DPadDown);
    MAP_GC_INPUT(gamepad.dpad.left, DPadLeft);
    MAP_GC_INPUT(gamepad.dpad.right, DPadRight);
    
    MAP_GC_INPUT(gamepad.buttonMenu, Start);
    MAP_GC_INPUT(gamepad.buttonHome, Back);
    
    MAP_GC_INPUT(gamepad.leftShoulder, LeftShoulder);
    MAP_GC_INPUT(gamepad.rightShoulder, RightShoulder);
    MAP_GC_INPUT(gamepad.leftThumbstickButton, LeftThumbstick);
    MAP_GC_INPUT(gamepad.rightThumbstickButton, RightThumbstick);
    
    MAP_GC_INPUT(gamepad.buttonA, A);
    MAP_GC_INPUT(gamepad.buttonB, B);
    MAP_GC_INPUT(gamepad.buttonX, X);
    MAP_GC_INPUT(gamepad.buttonY, Y);
        
#undef MAP_GC_INPUT
    }];
```

## See also

For best practices in delivering a great input experience to your players, consult the Human Interface Guidelines on the following:

* [Game Controllers](https://developer.apple.com/design/human-interface-guidelines/game-controllers)
* [Touch controls](https://developer.apple.com/design/human-interface-guidelines/keyboards)
* [Keyboard](https://developer.apple.com/design/human-interface-guidelines/keyboards) 

## Test your knowledge

1. Modify the game controller input in `Controller.mm` to detect when the player presses button 'X'.
2. Save this event in the game controller state and use it to implement a "double-shot" action in `Game.cpp`.

