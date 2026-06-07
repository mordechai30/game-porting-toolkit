# Managing your app's life cycle

Control your app's life cycle, and target macOS and iOS from a single codebase.

## Overview

Although it's possible to build terminal-based games that use characters and text to represent the game's visuals, today's games typically rely on creating a window containing a *canvas* where they display 2D or 3D graphics.

Similar to other platforms, Apple SDKs contain all the frameworks you need to create your game's window and respond to player input. Unlike other platforms, however, where you programmatically define window classes, display them to your players, and manually receive, translate, and dispatch system events, Apple frameworks offer you a more simplified experience.

Instead of defining window classes programmatically, you can use Xcode to visually design your window in *Storyboard* files. When you build your Storyboard file, Xcode serializes it into an efficient binary format that your app loads at runtime, restoring the layout of your UI elements.

When handling events, instead of manually peeking an event queue, translating, and dispatching messages, on Apple devices you defer this boilerplate task to a [*RunLoop*](https://developer.apple.com/documentation/foundation/nsrunloop) object.

Calling function `UIApplicationMain()` in iOS and `NSApplicationMain()` in macOS from your main thread yields control to the [RunLoop](https://developer.apple.com/documentation/foundation/nsrunloop) object, which then takes care of forwarding significant events to your app components.

This makes handling player events on Apple devices very simple. For games, use the Game Controller framework to either subscribe to events or poll the state of any keyboards, mice, or game controllers connected to the device. Because this framework is unified across macOS and iOS, your event-handling code works on all Apple devices automatically.

Similarly, the [`CAMetalDisplayLink`](https://developer.apple.com/documentation/quartzcore/cametaldisplaylink?language=objc) class allows you to register a callback for screen vertical sync (*vsync*) events, giving you a convenient place from where you can drive your game rendering.

As in any other platform, your program needs an entry point to register itself with these objects.
This sample uses the `applicationDidFinishLaunching:` method in the file `GameApplication.m` for each platform to instantiate a `GameCoordinatorController` instance. Among other things, this object creates a  `CAMetalDisplayLink` and configures a regular callback tied to the display’s vsync, laying the foundation for an interactive game.

## Port from other programming languages

Traditionally, windowed applications use the C programming language because it provides access to the entire platform's programmable surface. Unfortunately, C has two main drawbacks for implementing windowed applications tied to an operating system's API:

* Because C is a statically typed language, runtime discovery of platform classes across different operating system versions becomes difficult. Apps need a way to query what interfaces are available and need an indirect way to initialize them into objects.
* C requires manual memory management, which can become challenging in visual apps where objects are long-lived and tied to user interaction.

Other platforms address these shortcomings by relying on complex interfaces that allow performing global queries using universally unique identifiers (*UUID*s) and passing pointers to helper creator functions. To help with memory management, these platforms rely on C++ template metaprogramming to wrap memory objects into reference-counted constructs. In some extreme cases, platforms even extend their C/C++ compilers with proprietary extensions that bolt on a new dialect on top of the language in an attempt to manage the complexity.

Apple SDKs take an elegant approach to this problem with purposely defined programming languages that provide the runtime dynamism the app needs, and that build reference counting right into the language. The platform accomplishes this while still giving you direct access to C (and C++) for your game logic. These languages are Swift and Objective-C.

This project uses Objective-C to interface with platform-specific SDKs while simultaneously demonstrating how to effectively mix this language with C and C++ to trivially interface with a C++ game core. If you are new to the platform, Objective-C syntax should be familiar to you, as it's another C-based language.

## Understand the app life cycle in this project

This project provides you with the foundational aspects to begin an app, using AppKit in macOS and UIKit in iOS to create a view that is suitable for the game to render Metal content, and run a render loop.

This section of the sample contains two subfolders: **macOS/** and **iOS/**. Each contains the files necessary for handling aspects of the game that set up a window with a view suitable for rendering Metal content, receiving and handling system events, and running the game's update and render loops.

The **Common/** folder contains files that provide logic common to both platforms. It's a convenient place to share logic and avoid unnecessary code duplication.

### Respond to game update and draw events

Games produce the illusion of animation by updating the state of the world and displaying it to players several times every second. The most efficient way to implement these updates is by tying them to the display's refresh rate.

At runtime, the instance of the `GameCoordinatorController` creates a `CAMetalDisplayLink` instance, which provides a unified point where the system calls a delegate you register at a rate corresponding to the display's vertical sync (*vsync*).

As the system prepares to display the next frame, typically 30, 60, or 120 times per second, the instance of `CAMetalDisplayLink` calls its delegate's `metalDisplayLink:(CAMetalDisplayLink *)link needsUpdate:(CAMetalDisplayLinkUpdate* )update` method to signal it is time to update the game and display it.

> Note: Always favor using `CAMetalDisplayLink` instead of `CVDisplayLink` in macOS and `CADisplayLink` in iOS, as it provides you additional control over the target game latency.

### Implement the update and render loops

This project implements its game logic in C++, but some of the platform-specific code uses Objective-C or Objective-C++ to call into the SDK.

This project's instance of `GameCoordinatorController` creates and delegates the responsibility of updating the game state and rendering it to the `GameCoordinator`. This is a pure C++ class in `GameCoordinator.hpp`. Among its responsibilities, it creates and maintains the `Game` instance, starting each frame, asking the game to draw itself, and testing the end-of-game conditions.

### Target macOS and iOS

The sample contains a multiplatform target that allows you to run the game in macOS and iOS in one step by changing the run destination in the run bar.

As Xcode builds your project for the target, it selects the appropriate SDK and determines the files it uses to build the application bundle from either the `macOS/` or the `iOS/` folder.

Each folder provides the implementation of the window creation logic for both iOS and macOS, allowing you to build an app that feels native on each platform. The rest of the sample files use frameworks available on both platforms, targeting both macOS and iOS from the same files and using the same APIs.

Starting in **macOS 15** and **iOS 18**, Metal unifies its shaders, allowing your game to load its Metal libraries without requiring shader recompilation.

Similarly, assets in other formats common to macOS and iOS don't need to be repackaged to run in iOS. For example, iPhone 15 Pro supports *BCn* texture compression, providing you a common texture format across both platforms and avoiding the need for texture recompression.

> Note: When running in iOS, Xcode signs application bundles, including all embedded resources, before running on iOS devices. Consider implementing a mechanism to load your asset packages from outside the application bundle to reduce build-run iteration times during development.

### Specify entitlements and capabilities

Entitlements allow your game to request specific behaviors from the system that may be necessary to support your game.

For iOS devices, this project includes (commented out) the **Increased memory limit** key in the `Game.entitlements` file, which indicates that the game requires as much memory as possible. Use this entitlement when providing an experience that doesn't fit within the standard memory limits, but avoid using it if your game doesn't need it as it may force other apps in the background to unload.

Additionally, the project's `iOSInfo.plist` file conveys to the platform that the game allows targeting 120 Hz on iOS devices, requests Game Mode, and indicates to the App Store that this game supports game controllers. When the App Store encounters the latter, it displays a game controller icon on your game's page.

Entitlements and capabilities also apply to macOS. This project's `macOSInfo.plist` file specifies to the platform that this app belongs to the *Games* app category, making the game trigger macOS Game Mode when in full screen.
