# Adopting Game Center to track player achievements

Adopt the Game Center framework into your game to easily implement achievements.

## Overview

You create achievements through the App Store Connect portal and associate them with your game. Each achievement has a unique identifier that your game uses to report your players' progress toward it.

Your game may have a maximum of 100 achievements, with each individual achievement providing a maximum of 100 points. Keep these limits in mind to budget correctly if you plan on adding more achievements in the future as part of a game expansion or DLC.

After you define your achievements, as the player progresses through the game, you report achievement progress and completion through the Game Center framework.

> Note: Reporting achievement progress requires authenticating your player, and some players might prefer not to authenticate to enjoy your game. Consider making achievements optional, not requiring in-game authentication, so your players can still enjoy your game without achievements.

## Configure achievements

In App Store Connect, go to the *Features* tab of your game's page. You can find achievements under the Game Center section. Click "Add achievement" to bring up the achievement creation page.

The achievement creation page allows you to specify the achievement ID, which you later use to refer to the achievement, and its attributes, including its localized descriptions.

## Update achievements

The following Objective-C snippet demonstrates the process of reporting 50% progress toward an achievement:

```objc
#import <GameKit/GameKit.h>

// ... //

NSString* identifier = @"...";

GKAchievement* achievement = [[GKAchievement alloc] initWithIdentifier:identifier];
achievement.percentComplete = 50.0;

[GKAchievement reportAchievements:@[achievement]
            withCompletionHandler:^(NSError * _Nullable error) {
    if (error)
    {
        // Handle any errors reporting the achievement progress
    }
}];
```

The code snippet shows that you report achievement progress by creating instances of the `GKAchievement` class, using the achievement identifier to indicate which achievement you intend to update.

Your app then sets the achievement completion percentage via its `percentComplete` property, and finally uses the static method `reportAchievements:withCompletionHandler:` of the `GKAchievement` class to submit the progress update.

## Display achievements to your players

You can conveniently display all achievements to your players by creating instances of the `GKGameCenterViewController` class and presenting it from your game's iOS view controller.

When you use instances of this class, iOS displays a preconfigured view with all your achievements and your players' progress toward each one. Achievements at 100% completion also display their associated imagery.

If you prefer to display achievements in your custom in-game interface, you can query the Game Center framework for the `GKAchievementDescription` instances corresponding to each identifier. The description includes the achievement title, its achieved and unachieved description, and complete, incomplete, and placeholder imagery.

## See also

For more details on achievements, leaderboards, and multiplayer support in the Game Center framework, see [Tap into Game Center: Leaderboards, Achievements, and Multiplayer](https://developer.apple.com/videos/play/wwdc2020/10619/) WWDC 2020 session.
