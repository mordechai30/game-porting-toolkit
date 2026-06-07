# Adding cross-device cloud saves to your game using CloudKit
Replicate your game saves on iCloud to make your game seamlessly playable across Apple devices.

## Overview
> Note: This sample code project is associated with WWDC24 session 9200: [Bring your advanced games to Apple platforms](https://developer.apple.com/wwdc24/9200/).

## Prerequisites
An Apple Developer Program membership is needed to create a CloudKit container.

## Configure the sample code project
Before you run the sample code project in Xcode:
* In Game Cloud Save > Targets > SampleGame > Signing & Capabilities, select your team and create a bundle identifier.
* In the iCloud section, create an iCloud container.
* To run tests, repeat the same process for `CloudSaveTestsTarget`.
* In Config.swift, set the `containerIdentifier` to your newly created iCloud container. Note: you may want to use a different container identifier when you run the unit tests, and separate its cloud data from the sample game app.

## Play the sample game
The sample game launches into a simple game menu view, where you can start and later resume a game from one of five (configurable in Config.swift) save locations. 
The game takes an astronomical theme and has five chapters. You can tap on the furthest unlocked chapter to simulate a save action and progress the game.
It's helpful to follow the log, and understand how the game triggers a save action, writes the relevant save file to disk, and starts a sync with the cloud. The log also reveals important state changes in the file operations and sync operations.
