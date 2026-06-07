# Playing audio to further immerse your players

Bring audio to your game with popular middleware or Apple frameworks for music, sound effects, and rich spatial sound.

## Overview

Audio is a crucial component of your game. Popular audio middleware supports macOS and iOS, allowing you to bring this aspect of your game to the Apple platform. You can also incorporate Apple audio frameworks to deliver rich spatial sound to your players.

Games typically use third-party middleware for implementing audio. The game logic integrates with the middleware SDK to play music and sound effects.

## Port your audio

Two examples of popular audio middleware are:

* [Audiokinetic Wwise](https://www.audiokinetic.com/en/products/wwise/)
* [FMOD](https://www.fmod.com/)

Because both middleware solutions are readily available in macOS and iOS, you can continue to use these frameworks as you bring your game to Apple devices, allowing you to deliver audio experiences from your existing codebase.

You can integrate these middleware solutions into your project as a library or framework, making it easy to port your audio code to the Apple platform. Check your middleware's manual and make sure to use the latest version for broader support.

> Note: Starting with version 2021.1.4, Wwise is available for both Apple silicon and iOS devices. Audio banks, however, are platform-specific. When running your game in iOS, be sure to rebuild them for each target platform.

## Use Apple frameworks for audio

In addition to third-party middleware, Apple SDKs provide a comprehensive set of audio technologies that enable you to create rich game audio experiences. Use them to immerse your players in multichannel audio with spatial rendering, and process sound in real time using AVAudioEngine.

[PHASE](https://developer.apple.com/documentation/phase?language=objc) (Physical Audio Spatialization Engine) allows you to provide complex, dynamic audio experiences in your games. With PHASE, you can control sound layers and adjust audio parameters in real time. As you develop your app, dynamic integration with your app's visual scene enables audio to react to logic and visual changes automatically. The framework supports various audio hardware, which enables your app to provide a consistent spatial audio experience across platforms and output devices like headphones and speakers.

For more details, see the [Working with audio](https://developer.apple.com/audio/) guide and the [PHASE](https://developer.apple.com/documentation/phase?language=objc) documentation on the Apple developer site.

### Learn about audio in this project

This project uses the Apple PHASE framework to play sound effects whenever the player's ray collides with an enemy spaceship.

At build time, the **Copy Phase** of the project's build configuration copies the mp3 sound files to the application bundle, making them available to the game at runtime.

The `PhaseAudio.mm` file is responsible for loading the sound effects from the application bundle and registering them as `sound asset` instances with the PHASE engine it creates. As the sample registers the sound assets, it assigns them an `identifier`.

Because PHASE is a graph-based sound system, the sample then creates `PHASESoundEventNodeAsset` event nodes that references the audio files by their identifiers. The sample also assigns each event its own identifier.

Finally, when the game requests playing sound effects, the `PhaseAudio::playSoundEvent()` function instantiates a new `PHASESoundEvent` and calls `startWithCompletion:` on it, reproducing the sound effect to the player.

> Note: Although this sample demonstrates how to play simple stereo sound, PHASE is a powerful framework that allows you to render 3D audio that takes into consideration occluder geometry. Be sure to review its documentation to learn more about the capabilities it can bring to your game.

## See also

* The [Working with audio](https://developer.apple.com/audio/) guide.
* [PHASE](https://developer.apple.com/documentation/phase?language=objc) documentation on the Apple developer site.
* The [Discover geometry-aware audio with the Physical Audio Spatialization Engine (PHASE)](https://developer.apple.com/videos/play/wwdc2021/10079/) WWDC 2021 session.

## Test your knowledge

1. Add a second sound effect to `PhaseAudio.mm` by registering a new sound asset and its event node.
2. Modify `Game.mm` to play this sound effect when the player performs its "shoot" action.

