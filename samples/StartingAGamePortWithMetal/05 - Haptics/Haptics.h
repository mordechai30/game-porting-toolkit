/*
<samplecode>
  <abstract>
  Declares the long-running haptics player that wraps a `CHHapticEngine` and
  exposes a single intensity-knob interface for game-controller rumble.
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

#import <CoreHaptics/CoreHaptics.h>

@interface LongRunningHaptics : NSObject
- (instancetype)initWithEngine:(CHHapticEngine *)hapticsEngine;
- (void)setIntensity:(float)intensity;
@end
