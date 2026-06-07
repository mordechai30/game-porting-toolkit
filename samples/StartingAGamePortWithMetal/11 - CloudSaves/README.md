# Adding cross-device cloud saves to your game using CloudKit

Use the CloudKit framework to keep the highest score a player achieves in the game from chapter 10 in sync across multiple Apple devices.

## Overview

`GameApplication.m` files in the `macOS/` and `iOS/` folders receive system events, such as when the game starts or ends. Instances of this class use the `GameCoordinatorController` to conditionally retrieve and upload the highest score of the game using a `CloudSaveManager` object.

## Synchronize game save data

Because of its dependency on an internet connection, the sample code project gates uploads and downloads of the high score on the compile-time macro `GP_SUPPORT_CLOUDSAVES`. The project defines this macro when you select the "GameProject+CloudSaves" scheme in the Xcode run bar.

Additionally, using CloudKit requires specific configuration in your Xcode scheme, including signing into Xcode using a professional developer account, code signing your game, and logging into iCloud on all test devices. Use the regular "GameProject" scheme to keep cloud saves disabled and avoid these requirements. See the section "Enabling CloudKit in your project configuration" below for more details.

Once you're set up for building and signing the project, the `CloudSaveManager.m` and `CloudSaveManager.h` files provide a turn-key solution to sync game files to an iCloud container using CloudKit. These files don't have any dependencies to the rest of the project, allowing you to take them as is and use them in your games.

To sync, the `initWithMetalLayer:` function in the sample's `GameCoordinatorController.m` file creates an instance of the `CloudSaveManager` class with an iCloud identifier and a target directory to sync. This directory hosts a save data file that contains the highest-recorded score of the game.

You specify your cloud identifier and the save directory URL by passing them to the `CloudSaveManager` constructor:

```objc
// The name of the container is your app’s bundle identifier prefixed with "iCloud."
NSString* identifier = [NSString stringWithFormat:@"iCloud.%@", NSBundle.mainBundle.bundleIdentifier];

NSURL* saveURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];

cloudSaveManager = [[CloudSaveManager alloc] initWithCloudIdentifier:identifier
                                                     saveDirectoryURL:saveURL];
```

Next, as the system calls `application:didFinishLaunchingWithOptions:` in iOS and `applicationDidFinishLaunching` in macOS to set up the game, these functions call `downloadCloudSavesBlocking:` of the `GameCoordinatorController.m` file, which downloads the latest save file from iCloud using the `syncWithCompletionHandler:` function of the `CloudSaveManager`.

```objc
[cloudSaveManager syncWithCompletionHandler:^(BOOL conflictDetected, NSError *error) {
    // Handle sync errors or merge conflicts.
}];
```

The `syncWithCompletionHandler:` function takes a block as a parameter, which the sample uses to parse the data it downloads, and set the highest score game-wide. The sample doesn't block as it waits for the sync to continue, allowing the game to start as soon as possible without waiting for network activity. Upon completing the sync and parsing any previous high score, the game sample shows it to the player as a UI banner.

While this sample doesn't resolve synchronization conflicts that may arise from save files modified on multiple devices, your game can do so directly from within this block. In case of a conflict, `resolveConflictWithLocality:` provides a convenient mechanism to resolve conflicts to the local or remote version of the file.

Because synchronization is network-based, your game needs to be prepared for it to fail. When the `CloudSaveManager` detects a network error, the sync function returns an error code. This sample discards remote data when it encounters an error; however, your game may choose to retry or offer the player an option to disable cloud saves.

The function `uploadWithCompletionHandler:` of the `CloudSaveManager` allows the game to upload changes to the server:

```objc
[cloudSaveManager uploadWithCompletionHandler:^(BOOL conflictDetected, NSError *error) {
    // Handle upload errors or merge conflicts.
}];
```

Uploading save data to the server may generate merge conflicts. Use the completion handler to determine how best to handle this situation. For example, you may choose not to handle a conflict right away and defer the resolution to a later time. This could be the best approach if the game intends to save its data later on during gameplay.

> Note: Your game doesn't need to call `syncWithCompletionHandler:` before calling `uploadWithCompletionHandler:`, allowing you to easily implement autosaving of game progress.

## Enable CloudKit in your project configuration

To test cloud saves in this project, follow the steps below to modify the "GameProject+CloudSaves" scheme. For more details on using CloudKit in your games, see [Enable CloudKit in your app](https://developer.apple.com/documentation/cloudkit/enabling_cloudkit_in_your_app).

### Configure your account

To use iCloud to save data in containers, you need to have a professional developer account in Xcode. For Enterprise accounts, your account may need the App Manager permission to register containers. Personal development teams don't support the iCloud and Push Notifications capabilities.

Additionally, be sure that your developer account manager has accepted the latest terms of the Apple Developer Program License Agreement. You may not be able to create iCloud containers until the agreement is in effect.

> Note: You may need to restart Xcode after you make changes to your developer account's permission level.

### Configure the sample code project from the client side

Before you run the sample code project in Xcode:

1. Click Game Project in the Project navigator. Click the "GameProject+CloudSaves" target. Click Signing & Capabilities.
2. Select your development team and enter a bundle identifier. By default, the same identifier propagates to macOS and iOS.
3. For macOS, make sure your project isn't configured as Signed to run locally.
4. Scroll down to the iCloud capability section. Create an iCloud container by clicking the Add button (+).
5. Set the `initWithCloudIdentifier` to your newly created iCloud container in `initWithMetalLayer:` in the `GameCoordinatorController.mm` file.
6. If the container is displayed in red, use the Refresh button to synchronize its status.

### Configure the sample code project from the iCloud side

Instead of using Xcode, you can also create your container via the web portal with the following steps:

1. Go to the [developer dashboard](https://icloud.developer.apple.com/dashboard/).
2. On the top-right section of the page, select your development team — this can't be your personal development team.
3. Click CloudKit Database.
4. On the top-left section of the page, next to Development click the drop-down list and select "Create New Container."
5. Provide a description and give your container an identifier matching the one you use in the client side.
6. Click Continue.

Return to Xcode and click the refresh icon in the iCloud containers section. The icon then turns from red to black.

### Log into iCloud to test file synchronization

To test iCloud, you need an iCloud account to save records to a container. Note that your iCloud account is distinct from your Apple Developer account.

If you don’t have an iCloud account, create one for use during development. In macOS, launch System Preferences and click Sign In. Click Create Apple ID under the Apple ID text field and follow the instructions.

If you already have an iCloud account, enter your credentials on an iOS or iPadOS device:

1. Launch the Settings app and click "Sign in to your iPhone/iPad."
2. Enter your Apple ID and password.
3. Click Next. Wait until the system verifies your iCloud account.
4. To enable iCloud Drive, choose iCloud and then click the iCloud Drive switch. If the switch doesn’t appear, iCloud Drive is already enabled.

> Note: When you run the game on a device that isn't logged into iCloud, the standard output shows a message stating: "This request requires an authenticated account."

> Note: If you get the error "Failed to modify some record zones" when you run the game, iCloud may not have completed the container creation request yet.

## Understand the CloudSaveManager internals

Internally, the `CloudSaveManager` uses CloudKit to handle synchronization with iCloud.

Each save file corresponds to a `CKRecord` of type `SaveFile`, which contains a `CKAsset` with the file, its last modification date, and last device that modified it.

The `CloudSaveManager` instance saves these records into a state file. There is also one `RootRecord` that holds general information to help resolve synchronization conflicts.

During sync, the `CloudSaveManager` instance first checks if the game added or modified any files by comparing them with a known state. If it finds any changed files, it marks them for update.

It then sends files marked for modifications using a `CKModifyRecordsOperation`. If the operation fails with `CKErrorServerRecordChanged`, the function reports the conflict to the completion handler.

If there are no errors or conflicts, the function uses `CKFetchRecordZoneChangesOperation` to fetch new changes from the server and merge them with the game's local records.
