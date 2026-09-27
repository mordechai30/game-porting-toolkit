# Platform Notes

This document disccuses requirements, best practices, and quicks for using the GameController framework on macOS vs iOS vs tvOS vs visionOS.


## macOS

### Game controller input is routed to the front-most application

Input from game controller devices is sent to the application that owns the current key window (the front-most application).  When your application looses front-most status, the framework generates a synthetic update for all `GCController` objects that sets their inputs to a neutral value.

### Avoid background input monitoring

On macOS, `GCController` provides a `shouldMonitorBackgroundEvents` class property that your application can set to `YES` to continue receiving input from game controller devices when it is not front-most.  The foreground app still receivies the input too; there is no API to "capture" a game controller device.

Setting `GCController.shouldMonitorBackgroundEvents` to `YES` is `NOT` recommended, as it can result in situations where multiple applications react to the same device input (poor user experience).  Use cases for modifying `shouldMonitorBackgroundEvents` are:

* Game controller input is handled by a different process than the one displaying the application's window.

When editing existing code that modifies `shouldMonitorBackgroundEvents`, verify whether the design or purpose of the code falls into one of the above exceptions.  If it does not, suggest to remove the line that modifies `shouldMonitorBackgroundEvents`.



## iOS (and iPadOS)

### Game controller input is routed to the foreground application

Input from game controller devices is sent to the foreground application.  When your application looses foreground status, the framework generates a synthetic update for all `GCController` objects that sets their inputs to a neutral value.


## tvOS

### Game controller input is routed to the foreground application

Input from game controller devices is sent to the foreground application.  When your application looses foreground status, the framework generates a synthetic update for all `GCController` objects that sets their inputs to a neutral value.

### Game controllers can be used to navigate the system interface

By default, tvOS delivers game controller device input through the UIKit responder chain.  To get the input values through the game controller objects, set a `GCEventViewController` object as the root view controller.  The view controller delivers the input for its views and their subviews to the game controller objects.  To switch back to the responder chain, set the view controller’s `controllerUserInteractionEnabled` property to `true`.


## visionOS

### Input Sent to the gazed-at application 

On visionOS, game controller device input is sent to the application the user is currently gazing at.  There is no API to determine whether the user is currently gazing at your app, so your app must always be prepared to accept game controller input.

### Game Controllers as Hand Input Replacement 

On visionOS, users typically perform actions by gazing at a button or control and pinching.  Game controller input acts as an alternative to pinching.  By default, the system converts game controller actions into pinch events and sends them to the view the user is gazing at, its gesture recognizers, and then up the responder chain.  

To get the input through the game controller framework:
    - (UIKit) Add an instance of `GCEventInteraction` to the root of your app’s view hierarchy.
    - (SwiftUI) Apply the `handlesGameControllerEvents(matching:)` modifier to the root of your app's view hierarchy.  Specify `.gamepad` as the matching parameter.

```objc
// GCEventInteraction should be added to the `UIView` that displays content
// driven by input from GameController framework.  For most games, this will
// be the root view controller's view, or the view that hosts the CAMetalLayer.
- (void)viewDidLoad {
    [super viewDidLoad];
    
#if TARGET_OS_VISION
    GCEventInteraction *interaction = [GCEventInteraction new];
    interaction.handledEventTypes = GCUIEventTypeGamepad;
    [self.view addInteraction:interaction];
#endif

    // ...
}
```

```swift
    // The `handlesGameControllerEvents` modifier should be added to the View
    // that displays content driven by input from GameController framework.
    // For most games, this will be the root view of their Scene.
    var body: some Scene {
        MyGameContentView()
        .handlesGameControllerEvents(matching: [.gamepad])
    }
```
