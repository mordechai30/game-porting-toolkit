
# Configuring your project

Set up your game project to target macOS, and then easily target iOS later.

## Overview

The first step to bring your game to Apple devices is to bootstrap it in macOS.

By starting with a port to the Mac, you target the same software APIs, unified memory architecture, advanced hardware, and GPU capabilities shared between Apple silicon and iOS devices, such as iPhone 15 Pro.

During the initial stages of work, you can rapidly iterate on Mac using Xcode and Instruments, with additional memory and the resources of powerful desktop Macs. The extra storage and memory for debugging and test scaffolding is super useful during development.

And you can easily test with command-line automation and with keyboard, mouse, and controller input right at your desk.

When running on the Mac, the unified architecture of Apple silicon and the resources and capabilities of iPhone 15 Pro and iPhone 15 Pro Max make bringing the Mac port over to iPhone easy.

## Target macOS and iOS from a single project

Starting with Xcode 14, it's simple for a single app target to support all Apple devices uniformly, such as Mac, iPad, and iPhone, while still allowing for customization when needed. This is great for games, as they typically use a common codebase and share most of its project settings across all its destinations.

To set up an Objective-C/C++ multiplatform project, start by creating a macOS app project from a template, then click the project's name in the **Project navigator**, click **General**, and click the **+** button in **Supported Destinations** to add iOS as a target platform.

Note that this is different from creating an iOS project, which includes the Mac (Designed for iPad) target by default. Although using the Mac (Designed for iPad) target is a great way to start porting an existing iOS game to macOS, the configuration this sample code uses allows you to take your macOS build to the next level by using the full macOS SDK.

When you add another platform to your project, Xcode warns you that it needs to make changes to your configuration, updating your target to only include dependencies available on the new platform. It's important to note Xcode doesn't make changes to the code, so if your code uses API that isn't available on all platforms, you need to resolve those issues manually.


> Note: It's valid to have more than one macOS destination when developing in Xcode. This is especially useful when transitioning from the Mac Catalyst or the Mac (Designed for iPad) target to a full macOS app.

When your Xcode project supports multiplatform targets, many app target settings include a mechanism to condition its values for each platform. You can configure the game's display name, version, bundle identifier, and other settings, based on which SDK (macOS or iOS) Xcode uses at compile time.

If your project lets Xcode automatically manage code signing, you don't need to make any special adjustments to build and sign your game for each platform.

And when both your macOS and iOS products use the same bundle identifier, when you publish them to the App Store, they automatically support universal purchase, so players who buy your iOS game also get your macOS game automatically.

Finally, if your game makes use of capabilities like push notifications, any capabilities you use for the iOS build that are applicable to the macOS build are included with no extra work. Xcode even combines them into a single entitlements file.

## Resolve platform differences

It's not unusual to run into issues building an app for a new destination, especially as you add a new SDK to your project. Although most Apple frameworks you use for game development support both macOS and iOS, some specific frameworks may not be available.

It's important not to import or link frameworks when they are unavailable to the platform's SDK. You are responsible for modifying your codebase, as you add a new platform to your game, to disable any code unavailable in an SDK.

> Note: As you share code between your platforms, Xcode checks API availability against your currently selected run destination. As you work, make sure to toggle the run destination to the platform for which you're adjusting your code to get useful insights from Xcode's code analysis.

To tailor your code for each platform, you can use conditional compilation, selectively replacing parts of your code based on the active SDK when the changes are not too extensive.

In other cases, for example if you have an entire file that does not support any given platform, Xcode multiplatform projects offer extended options for several project configuration aspects under the project configuration's **Build Phases**.

The **Compile Sources** build phase allows you to specify that particular source files compile only for a certain platform, instead of both. Likewise, the **Copy Files** build phase lets you filter which files Xcode copies over to the application bundle as it builds the app.

Use these options to create source and files that target both platforms, where applicable, and elegantly distinguish between them when necessary.

Following this advanced Xcode configuration makes it easy for you to target macOS and iOS devices in one step.

You can find more details about how to target both macOS and iOS from a single project scheme in the [Use Xcode to develop a multiplatform app](https://developer.apple.com/videos/play/wwdc2022/110371/) and [Explore advanced project configuration in Xcode](https://developer.apple.com/videos/play/wwdc2021/10210) WWDC sessions.


## Benefit from cross-platform Metal enhancements

The majority of Apple frameworks you use for game development target both macOS and iOS, making the experience of developing for both platforms simultaneously straightforward.

In addition, **macOS 15** and **iOS 18** include several enhancements that bring macOS and iOS closer together, simplifying the process of targeting both platforms from a single codebase.

Some of these enhancements include:

* [Unified Metal shaders](https://developer.apple.com/metal): Target both platforms without needing to recompile your Metal libraries.
* [Unified device initialization](https://developer.apple.com/documentation/metal/1433367-mtlcopyalldevices?language=objc): Use the same Metal device initialization API on both platforms. 
* [Device certification API](https://developer.apple.com/documentation/foundation/nsprocessinfo/4354193-isdevicecertifiedfor): Gracefully scale up and down your performance by querying devices for their performance profiles.

## See also

* [Use Xcode to develop a multiplatform app](https://developer.apple.com/videos/play/wwdc2022/110371/) WWDC 2022 session.
* [Explore advanced project configuration in Xcode](https://developer.apple.com/videos/play/wwdc2021/10210) WWDC 2021 session.

## Test your knowledge

1. Build and run this project on your Mac.
2. Change the run destination in Xcode's run bar to your iOS device.
3. Set up device provisioning and code signing, and then run the game in iOS.
