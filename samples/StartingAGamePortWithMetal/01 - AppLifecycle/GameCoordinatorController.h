/*
<samplecode>
  <abstract>
  Declares the controller that bridges platform-specific app entry points
  (macOS / iOS) into the shared C++ `GameCoordinator`, and owns the
  `CAMetalDisplayLink` render thread.
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

#import <QuartzCore/QuartzCore.h>

@interface GameCoordinatorController : NSObject <CAMetalDisplayLinkDelegate>

- (nonnull instancetype)initWithMetalLayer:(nonnull CAMetalLayer *)metalLayer gameUICanvasSize:(NSUInteger)gameUICanvasSize;

- (void)metalDisplayLink:(nonnull CAMetalDisplayLink *)link needsUpdate:(nonnull CAMetalDisplayLinkUpdate *)update;

- (void)maxEDRValueDidChangeTo:(float)value;

- (void)setBrightness:(float)brightness;

- (void)setEDRBias:(float)edrBias;

- (void)loadLastHighScoreAfterSync:(nonnull NSNumber *)hasSyncd;

- (void)saveHighScore;

- (void)downloadCloudSavesBlocking:(BOOL)blocking;

- (void)uploadCloudSavesBlocking:(BOOL)blocking;

@end
