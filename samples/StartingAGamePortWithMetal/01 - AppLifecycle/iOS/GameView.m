/*
<samplecode>
  <abstract>
  A `UIView` whose backing layer is a `CAMetalLayer` configured for EDR
  rendering.
  </abstract>
</samplecode>
*/

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
//
// Copyright 2026 Apple Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
//-------------------------------------------------------------------------------------------------------------------------------------------------------------

#import "GameView.h"
#import <UIKit/UIKit.h>
#import <GameController/GameController.h>

@implementation GameView

// Override the static layerClass method to customize the class of the layer to CAMetalLayer,
// making this view suitable to render Metal content.
+ (Class)layerClass
{
    return [CAMetalLayer class];
}

@end

@implementation GameViewController

- (instancetype)init
{
    if(self = [super init])
    {
        self.physicalGameControllerInUse = NO;
    }

    return self;
}

- (BOOL)prefersStatusBarHidden
{
    return YES;
}

// When using a virtual game controller or touch controls, gray out the home indicator
// by returning `UIRectEdgeNone` to avoid unintentional system interactions.
- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures
{
    return self.physicalGameControllerInUse ? UIRectEdgeNone : UIRectEdgeAll;
}

// When a using a physical game controller, hide the home indicator to avoid
// unintentional interactions.
- (BOOL)prefersHomeIndicatorAutoHidden
{
    return self.physicalGameControllerInUse;
}

@end
