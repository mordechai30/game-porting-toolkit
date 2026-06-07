/*
<samplecode>
  <abstract>
  Declares the `UIView` whose backing layer is a `CAMetalLayer` configured
  for EDR rendering.
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

#include <UIKit/UIKit.h>

// On iOS, you create a view suitable for Metal content by defining a custom UIView subclass that
// overrides the static "layerClass" method to return the "CAMetalLayer" class.
@interface GameView : UIView
@end

// GameViewController requests hiding the home indicator to favor in-game gestures (instead of system gestures)
// when using touch controls.
@interface GameViewController : UIViewController
@property BOOL physicalGameControllerInUse;
@end
