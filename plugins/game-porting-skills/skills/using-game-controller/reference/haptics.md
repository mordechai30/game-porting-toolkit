# Playing Haptics

This document discusses using the GameController and CoreHaptics frameworks to play haptic and rumble effects on game controller devices.


## Overview

Check if a game controller device supports haptics by accessing the `GCController.haptics` property.  This property returns a `GCDeviceHaptics` object, or `nil` if the game controller does not support haptics or rumble effect playback.

You use the `GCDeviceHaptics` object to create a `CHHapticsEngine` that will play haptic patterns on one or more of the game controller's actuators.  A game controller may include multiple actuators.  You determine which actuators a `CHHapticEngine` will target by specifying a `GCHapticsLocality` at creation time.  You can also inspect the available localities on a game controller.

```objc
API_AVAILABLE(macos(11.0), ios(14.0), tvos(14.0))
@interface GCDeviceHaptics : NSObject

/**
 The set of supported haptic localities for this device - representing the 
 locations of its haptic actuators.
*/
@property (nonatomic, strong, readonly) NSSet<GCHapticsLocality> *supportedLocalities;

/**
 Creates and returns a new instance of CHHapticEngine with a given GCHapticsLocality. Any patterns you send to this engine will play on
 all specified actuators.
 */
- (CHHapticEngine * _Nullable)createEngineWithLocality:(GCHapticsLocality)locality;

@end
```

The following localities are defined.

```objc
typedef NSString* GCHapticsLocality NS_TYPED_ENUM;
/** A default locality will give users an expected haptic experience.  ALWAYS AVAILABLE. */
GCHapticsLocality const GCHapticsLocalityDefault;
/** A locality that targets all actuators.  ALWAYS AVAILABLE. */
GCHapticsLocality const GCHapticsLocalityAll;
/** A locality that targets both the left and right handle actuators. */
GCHapticsLocality const GCHapticsLocalityHandles;
GCHapticsLocality const GCHapticsLocalityLeftHandle;
GCHapticsLocality const GCHapticsLocalityRightHandle;
/** A locality that targets both the left and right trigger actuators. */
GCHapticsLocality const GCHapticsLocalityTriggers;
GCHapticsLocality const GCHapticsLocalityLeftTrigger;
GCHapticsLocality const GCHapticsLocalityRightTrigger;
```

You may create multiple `CHHapticEngine` objects targeting the same locality.  The system mixes the patterns playing on each engine to produce the final haptic output.


## Best Practices

### Always fallback to the default locality

 If you want to play different experiences on different actuators (for example, using the left handle actuator as a woofer and the right actuator as a tweeter), you can create multiple engines -- one with a `GCHapticsLocalityLeftHandle` locality and another with a `GCHapticsLocalityRightHandle` locality.  However, you should always fall back to the default locality (`GCHapticsLocalityDefault`) if more specific localities are not available.
 
### Always use `GCDeviceHaptics` to create haptic engines when a controller is connected
 
"Attached" or "Attachable" (sometimes called "form-fitting") game controllers - such as the Backbone and Razer Kishi - clamp around the iPhone or iPad.  Beginning in iOS 27, when an attached controller is connected, iOS may route haptic output through the iPhone's built-in haptic actuator on behalf of an attached game controller device, when the game controller device lacks an actuator.  Because these devices physically connect to the iPhone, haptic waveforms propogate through the game controller into the user's hands, offering a comparable experience to waveforms produced by an actuator built into a game controller.

While a game controller is connected your application SHOULD ONLY play haptic effects through a `CHHapticEngine` created by calling `-[GCDeviceHaptics createEngineWithLocality:]`.  DO NOT create a `CHHapticEngine` using a direct initializer such as `-[CHHapticEngine initAndReturnError:]` while a game controller is connected.

For an attached controller that lacks an actuator, `GCController.haptics` still returns a `GCDeviceHaptics` object.  Calling `-[GCDeviceHaptics createEngineWithLocality:GCHapticsLocalityDefault]` on this object will return a `CHHapticEngine` targeting the iPhone or iPad's internal actuaotr, or `nil` if the user has disabled haptics in game controller settings.

```swift
// WRONG example
func createHapticEngine(controller: GCController, preferredLocality: GCHapticsLocality) -> CHHapticEngine? {
    // Check if the controller supports haptics
    if let controllerHaptics = controller.haptics {
        if let hapticEngine = controllerHaptics.createEngine(withLocality: preferredLocality) {
            return hapticEngine
        }
        // Fallback to the default locality
        else {
            return controllerHaptics.createEngine(withLocality: .default)
        }
    }
    // WRONG: Do NOT fallback to creating a `CHHapticEngine` that targets the
    //        internal actuator because the controller is attached (form-fitting).
    else if controller.isAttachedToDevice {
        // WRONG: This will return an engine that targets the internal actuator,
        // without respecting the user's preference to disable haptics
        // when using a game controller.
        return try? CHHapticEngine()
    }
    else {
        // No haptics experience possible for this game controller.
        return nil
    }
}
```

### Always handle a `nil` result from `-[GCDeviceHaptics createEngineWithLocality:]`

Users can disable game controller haptics in the system game controller settings.  When haptics are disabled, `-[GCDeviceHaptics createEngineWithLocality:]` returns `nil` even if the requested locality is present in `supportedLocalities`.  Your application SHOULD gracefully handle this case.


```swift
import GameController
import CoreHaptics

// CORRECT example
func createHapticEngine(controller: GCController, preferredLocality: GCHapticsLocality) -> CHHapticEngine? {
    // Check if the controller supports haptics
    if let controllerHaptics = controller.haptics {
        if let hapticEngine = controllerHaptics.createEngine(withLocality: preferredLocality) {
            return hapticEngine
        }
        // Fallback to the default locality
        else {
            return controllerHaptics.createEngine(withLocality: .default)
        }
    }
    else {
        // No haptics experience possible for this game controller.
        return nil
    }
}
```

### Create CHHapticEngine objects at setup time

Creating a `CHHapticEngine` object is an expensive operation.  Create all needed `CHHapticEngine` objects for a controller during setup (e.g, after discovering the controller) and re-use those objects for the lifetime of the game controller connection.  Avoid creating a new `CHHapticEngine` just to play a single haptic pattern, then discarding the engine.


## Examples

### Simple Rumble

Demonstrates how to create an haptic engine, prepare it for playback, and play fixed length rumble patterns.

```swift
/// A type commonly found in a real application or engine that manages a
/// specific game controller input source (i.e, a game controller device).
class GameControllerInputSource {
    let controller: GCController
    
    /// An engine for playing haptic effects on the controller.  Your
    /// application must hold a strong reference to the `CHHapticEngine` for the
    /// entire time you anticipate needing to play haptics.
    let hapticsEngine: CHHapticEngine?
    
    init(controller: GCController) {
        self.controller = controller
        
        self.hapticsEngine = createHapticEngine(controller: controller, preferredLocality: .default)
        self.resumeHaptics()
    }
    
    deinit {
        self.suspendHaptics()
    }
    
    /// Asynchronously start the haptic engine.
    ///
    /// You would typically call this method shortly before you anticipate
    /// needing to play haptic patterns.  If your app or engine are structured
    /// such that they lack tracking of when haptics *are* and *are not*
    /// needed, the engine can be started after receiving the controller
    /// connection notification, or immediately before playing a haptic pattern.
    func resumeHaptics() {
        guard let hapticsEngine = self.hapticsEngine else {
            return
        }
        
        Task { @MainActor in
            do {
                try await hapticsEngine.start()
            } catch {
                print("Haptic error: \(error)")
            }
        }
    }
    
    /// At a point where the application knows it will not need to play further
    /// haptic patterns in the immediate future, it can call this method to
    /// stop the haptic engine.  When haptics are needed again, the engine can
    /// be restarted.
    func suspendHaptics() {
        guard let hapticsEngine = self.hapticsEngine else {
            return
        }
        
        hapticsEngine.stop()
    }
    
    /// Play a rumble effect with a fixed intensity for a fixed duration.
    func playFixedRumble(intensity: Float, duration: TimeInterval) {
        guard let engine = self.hapticsEngine else {
            return
        }
        
        // Engines may stop on its own in auto-shutdown mode, or may not have
        // been started.  Ensure it is started (synchronously).  This is a no-op
        // if the engine is already running.
        do {
            try engine.start()
        } catch {
            print("Haptic engine start error: \(error)")
            return
        }
        
        let event = CHHapticEvent(eventType: .hapticContinuous,
                                  parameters: [
                                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                                  ],
                                  relativeTime: .zero,
                                  duration: duration)
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            print("Haptic playback error: \(error)")
        }
    }
}
```
