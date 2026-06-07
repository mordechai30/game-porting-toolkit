/*
<samplecode>
  <abstract>
  Creates a long-running `CHHapticEvent` of infinite duration and updates its
  `CHHapticDynamicParameter` whenever the game adjusts rumble intensity,
  restarting the engine if the system stopped it.
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

#import "Haptics.h"
#import <GameController/GameController.h>

@interface LongRunningHaptics() {
    CHHapticEngine* _engine;
    BOOL _isEngineStopped;
    id<CHHapticPatternPlayer> _longRunningPatternPlayer;
    
}
- (void)_registerEngineStopHandler;
- (BOOL)_startEngine;
- (void)_startLongRunningEvent;
@end

@implementation LongRunningHaptics

- (instancetype)initWithEngine:(CHHapticEngine *)hapticsEngine
{
    if ( self = [super init] )
    {
        _engine = hapticsEngine;
        _isEngineStopped = YES;
        [self _startEngine];
        [self _startLongRunningEvent];
    }
    return self;
}

- (void)_registerEngineStopHandler
{
    __weak LongRunningHaptics* weakSelf = self;
    _engine.stoppedHandler = ^(CHHapticEngineStoppedReason stoppedReason) {
        // The engine reports an unexpected stop, for example, after an audio-session interruption.
        // Reset state so the next playback attempt restarts the engine.
        NSLog(@"Haptic engine stopped: %d", (int)stoppedReason);
        LongRunningHaptics* strongSelf = weakSelf;
        if (strongSelf)
        {
            strongSelf->_isEngineStopped = YES;
        }
    };
}

- (BOOL)_startEngine
{
    if (_isEngineStopped)
    {
        NSError* __autoreleasing error = nil;
        if (![_engine startAndReturnError:&error])
        {
            NSLog(@"Failed to start haptic engine, reason: %@", error.localizedDescription);
            return NO;
        }
        _isEngineStopped = NO;
    }
    return YES;
}

- (void)_startLongRunningEvent
{
    CHHapticEventParameter* hapticEventParam =
        [[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticIntensity
                                                      value:1.0];
    
    CHHapticEvent* continuousEvent =
        [[CHHapticEvent alloc] initWithEventType:CHHapticEventTypeHapticContinuous
                                      parameters:@[hapticEventParam]
                                    relativeTime:0
                                        duration:GCHapticDurationInfinite];
    
    NSError* __autoreleasing error = nil;
    
    CHHapticPattern* pattern =
        [[CHHapticPattern alloc] initWithEvents:@[continuousEvent]
                                     parameters:@[]
                                          error:&error];
    
    if (!pattern)
    {
        NSLog(@"Error creating haptic pattern: %@", error.localizedDescription);
        assert(pattern);
    }
    
    // If the player has a game controller with a haptic engine:
    
    assert (_engine);
    
    _longRunningPatternPlayer = [_engine createPlayerWithPattern:pattern error:&error];
    if (!_longRunningPatternPlayer)
    {
        NSLog(@"Error creating long-running pattern player: %@", error.localizedDescription);
        assert(_longRunningPatternPlayer);
    }
    
    if (![_longRunningPatternPlayer startAtTime:CHHapticTimeImmediate error:&error])
    {
        NSLog(@"Error starting long-running pattern player: %@", error.localizedDescription);
        assert(false);
    }
    
    // Mute intensity until overwritten:
    [self setIntensity:0.0f];
}

- (void)setIntensity:(float)intensity
{
    if (_isEngineStopped)
    {
        [self _startEngine];
    }
    
    if (!_isEngineStopped)
    {
        CHHapticDynamicParameter* hapticParameter =
        [[CHHapticDynamicParameter alloc] initWithParameterID:CHHapticDynamicParameterIDHapticIntensityControl
                                                        value:intensity
                                                 relativeTime:0];
        
        NSError* __autoreleasing error = nil;
        
        // Multiply pattern's initial intensity by the new parameter:
        if (![_longRunningPatternPlayer sendParameters:@[hapticParameter]
                                                atTime:CHHapticTimeImmediate
                                                 error:&error])
        {
            NSLog(@"Error updating motor intensity: %@", error.localizedDescription);
        }
    }
}

@end
