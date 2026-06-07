/*
<samplecode>
  <abstract>
  Declares the iOS application delegate that creates the Metal-backed view and
  instantiates the game coordinator at launch.
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

// Provides the ApplicationDelegate, which the main() function references.
// It implements method `application:didFinishLaunchingWithOptions:`, which
// is the entry point for the game on iOS.
@interface GameApplication : UIResponder <UIApplicationDelegate>
@end

