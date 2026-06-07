/*
<samplecode>
  <abstract>
  Standard iOS entry point that hands control to `UIApplicationMain` with
  `GameApplication` as the delegate.
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

#import <UIKit/UIKit.h>
#import "GameApplication.h"

int main(int argc, char * argv[])
{
    // Yield the game loop to the `UIApplication`, which instantiates class `iOS/GameApplication`
    // and calls its application:didFinishLaunchingWithOptions:, where this sample then sets
    // up the window, view, and game.
    return UIApplicationMain(argc, argv, nil, NSStringFromClass([GameApplication class]));
}
