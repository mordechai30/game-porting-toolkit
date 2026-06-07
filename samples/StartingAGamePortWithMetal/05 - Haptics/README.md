# Implementing tactile feedback through haptics

Use haptics to add a whole new level of immersion to your game.

## Overview

Core Haptics provides the fundamentals you need to implement your haptics and play them back in response to in-game events. You use this framework to play events both on iOS devices that support a haptic engine and on physical game controllers.

## Port game controller rumble to Apple devices

Games coming from other platforms typically implement a game controller rumble effect by setting the intensity of the actuators directly during their game loop as game events occur. The Core Haptics framework enables you to easily port this behavior to Apple devices using `long-running` haptic events.

### Set up Core Haptics

The Core Haptics framework is comprehensive, allowing you to play your haptic content on the Taptic Engine in iOS devices as well as on game controllers. This allows you to convey a deeper gaming experience, even when your players don’t have a game controller handy.

To help you bring your rumble code over to Apple devices, this project focuses on haptic content for game controllers. As such, the sample starts the process of playing haptics by first creating an instance of a haptic engine when the player connects a game controller.

The `Controller.mm` file does this by adding an observer to the `GCControllerDidConnectNotification` notification. Its callback block creates an instance of a haptic engine that references the actuators in the game controller's handles — where your player feels the rumble effect.

```objc
CHHapticEngine* hapticEngine =
    [controller.haptics createEngineWithLocality:GCHapticsLocalityHandles];
```

The callback block continues by then creating an instance of the `LongRunningHaptics` class from the `Haptics.m` file. This class wraps the engine, and starts it. The engine plays `haptic patterns` that consist of `haptic events`, each one controlling the tactile sensations to convey to the player.

Under certain conditions, the system may stop the haptic engine — for example, if your player sends the game to the background. Attempting to use a stopped engine triggers an exception. You can register a callback block to the `stoppedHandler` property of the haptic engine instance to keep track of stop events and resume it accordingly.

### Create haptic patterns

You can prebuild haptic patterns to play in your game ahead of time and store them in [AHAP](https://developer.apple.com/documentation/corehaptics/representing_haptic_patterns_in_ahap_files?language=objc) files bundled with your app, or you can create them programmatically at runtime. This project creates the haptic patterns at runtime to demonstrate how to port rumble code from other platforms using a long-running event with a `CHHapticDynamicParameter` instance.

Make sure to review the [Core Haptics Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/playing-haptics) for more details about designing your players' haptic experience.

### Play haptic patterns

The Core Haptics framework allows you to play your haptic patterns using haptic pattern player instances. These allow your game to play its haptic patterns on any supported game controller, regardless of vendor, as well as on iOS devices.

To play haptic patterns, after you `start()` an instance of `CHHapticEngine`, you create instances of `CHHapticPatternPlayer`, providing your haptic patterns, and call `startAtTime` on them.

> Note: The Core Haptics framework guarantees that the `CHHapticPatternPlayer` instance remains alive and active during playback. You don't need to hold a strong reference to it, enabling your program to "fire and forget" the play action.

To demonstrate how you can port engine rumble code that expects to directly drive intensity to actuators, the `LongRunningHaptics` class creates a long-running haptic event of type `CHHapticEventTypeHapticContinuous`, with a duration of `GCHapticDurationInfinite`, an intensity of `1.0`, and a dynamic parameter representing the intensity of each motor your game engine expects to operate — on a normalized scale from 0 to 1.

During the game's update loop, when a significant event occurs — such as the player destroying a rock — `Game.cpp` sends (through an instance of the `GameController` class) a message to the `LongRunningHaptics` instance to adjust the intensity.

As it takes over, the `LongRunningHaptics` instance checks whether the haptic engine is stopped (resulting from system calls to `stoppedHandler`) and restarts it on demand before any requests to play a haptic event.

Next, this class creates `CHHapticDynamicParameter` instances for each motor intensity to adjust and sends it to the haptic player by calling `sendParameters`.

The Core Haptics framework then multiplies *the last parameter you send* with the continuous event's initial intensity, allowing you to dial up and down the motor intensity. As long as your updates are fast enough, your player feels a continuous change in haptic intensity.

For more details, see the [Introducing Core Haptics](https://developer.apple.com/videos/play/wwdc2019/520) and [Advancements in Game Controllers](https://developer.apple.com/videos/play/wwdc2020/10614/) WWDC sessions.

## See also

* [Introducing Core Haptics](https://developer.apple.com/videos/play/wwdc2019/520) WWDC 2019 session
* [Advancements in Game Controllers](https://developer.apple.com/videos/play/wwdc2020/10614/) WWDC 2020 session

## Test your knowledge

1. Modify `Game.cpp` to play a game controller rumble effect when the player performs an attack action.
2. Expand `Haptics.m` to introduce a new, distinct haptic pattern to play when the player performs an attack.
