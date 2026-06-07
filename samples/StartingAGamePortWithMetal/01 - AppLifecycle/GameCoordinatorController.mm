/*
<samplecode>
  <abstract>
  Creates the high-priority render thread, drives the `CAMetalDisplayLink`
  callback, and forwards display-link updates and EDR notifications to the
  C++ `GameCoordinator`.
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

#include "GameCoordinatorController.h"
#include "GameCoordinator.hpp"

#if TARGET_OS_IOS
#import <UIKit/UIKit.h>
#endif
#import <QuartzCore/QuartzCore.h>

#import "CloudSaveManager.h"

#include <memory>

static void* renderWorker( void* _Nullable obj )
{
    pthread_setname_np("RenderThread");
    CAMetalDisplayLink* metalDisplayLink = (__bridge CAMetalDisplayLink *)obj;
    [metalDisplayLink addToRunLoop:[NSRunLoop currentRunLoop]
                           forMode:NSDefaultRunLoopMode];
    [[NSRunLoop currentRunLoop] run];
    return nil;
}

@implementation GameCoordinatorController
{
    std::unique_ptr< GameCoordinator > _pGameCoordinator;
    CAMetalLayer*                      _metalLayer;
    CAMetalDisplayLink*                _metalDisplayLink;
    CloudSaveManager*                  _cloudSaveManager;
    dispatch_semaphore_t               _cloudSemaphore;
}

- (nonnull instancetype)initWithMetalLayer:(nonnull CAMetalLayer *)metalLayer gameUICanvasSize:(NSUInteger)gameUICanvasSize
{
    self = [super init];
    if(self)
    {
        _metalLayer = metalLayer;
        
        NSString* shaderPath = NSBundle.mainBundle.resourcePath;
        
        _pGameCoordinator = std::make_unique< GameCoordinator >((__bridge MTL::Device *)_metalLayer.device,
                                                                (MTL::PixelFormat)_metalLayer.pixelFormat,
                                                                _metalLayer.drawableSize.width,
                                                                _metalLayer.drawableSize.height,
                                                                gameUICanvasSize,
                                                                shaderPath.UTF8String);

        _metalDisplayLink = [[CAMetalDisplayLink alloc] initWithMetalLayer:_metalLayer];
        _metalDisplayLink.delegate = self;
        _metalDisplayLink.preferredFrameRateRange = CAFrameRateRangeMake(30, 120, 120);

#if GP_SUPPORT_CLOUDSAVES
        
        // The name of the container is your app’s bundle identifier prefixed with "iCloud."
        NSString* identifier = [NSString stringWithFormat:@"iCloud.%@", NSBundle.mainBundle.bundleIdentifier];
        NSURL* saveURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
        _cloudSaveManager = [[CloudSaveManager alloc] initWithCloudIdentifier:identifier
                                                             saveDirectoryURL:saveURL];
        
        _cloudSemaphore = dispatch_semaphore_create(0);
#endif // GP_SUPPORT_CLOUDSAVES
        
        // Create a high-priority thread that sets up the CAMetalDisplayLink callback and renders the game.
        
        int res = 0;
        // Configure the render thread to opt out of priority decay (SCHED_RR) and run at
        // elevated priority (sched_priority = 45). This priority class matches what
        // CAMetalDisplayLink expects for its vsync callbacks. The exact value is
        // empirically tuned for the display-link callback path; restrict this
        // configuration to as few threads as possible to avoid scheduler congestion.
        // See: pthread(3), sched(3).
        pthread_attr_t attr;
        res = pthread_attr_init( &attr );
        NSAssert( res == 0, @"Unable to initialize thread attributes." );

        res = pthread_attr_setschedpolicy( &attr, SCHED_RR );
        NSAssert( res == 0, @"Unable to set thread attribute scheduler policy." );

        struct sched_param param = { .sched_priority = 45 };
        res = pthread_attr_setschedparam( &attr, &param );
        NSAssert( res == 0, @"Unable to set thread attribute priority." );
        
        // Enable the system to automatically clean up upon thread exit:
        res = pthread_attr_setdetachstate( &attr, PTHREAD_CREATE_DETACHED );
        NSAssert( res == 0, @"Unable to set thread attribute to run detached." );
        
        // Create thread:
        pthread_t tid;
        res = pthread_create( &tid, &attr, renderWorker, (__bridge void *)_metalDisplayLink );
        NSAssert( res == 0, @"Unable to create render thread" );
        
        // Clean up transient objects:
        pthread_attr_destroy( &attr );
    }

    return self;
}

- (void)dealloc
{
    self->_metalDisplayLink = nil;
    _pGameCoordinator.reset();
}

- (void)renderThreadLoop
{
    [_metalDisplayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [[NSRunLoop currentRunLoop] run];
}

- (void)metalDisplayLink:(nonnull CAMetalDisplayLink *)link needsUpdate:(nonnull CAMetalDisplayLinkUpdate *)update
{
#if TARGET_OS_IOS
    // iOS does not post EDR headroom notifications. This sample queries the headroom
    // and adjusts it before rendering each frame.
    float maxEDRValue = UIScreen.mainScreen.potentialEDRHeadroom;
    _pGameCoordinator->setMaxEDRValue(maxEDRValue);
#endif // TARGET_OS_IOS
    
    id<CAMetalDrawable> drawable = update.drawable;
    _pGameCoordinator->draw((__bridge CA::MetalDrawable *)drawable, CACurrentMediaTime());
}

- (void)maxEDRValueDidChangeTo:(float)value
{
    _pGameCoordinator->setMaxEDRValue(value);
}

- (void)setBrightness:(float)brightness
{
    _pGameCoordinator->setBrightness(brightness);
}

- (void)setEDRBias:(float)edrBias
{
    _pGameCoordinator->setEDRBias(edrBias);
}

#pragma mark - High score persistence

- (void)loadLastHighScoreAfterSync:(nonnull NSNumber *)hasSyncd
{
    NSError* __autoreleasing fileError = nil;
    NSString* saveFilePath = [NSTemporaryDirectory() stringByAppendingString:@"/hiscore.txt"];
    NSString* hiScoreTxt = [NSString stringWithContentsOfURL:[NSURL fileURLWithPath:saveFilePath]
                                                    encoding:NSUTF8StringEncoding
                                                       error:&fileError];
    
    int highscore = 0;
    if (!hiScoreTxt)
    {
        NSLog(@"Error parsing save file (%@), initializing score to 0", fileError.localizedDescription);
    }
    else
    {
        NSLog(@"Restoring high score of: %@", hiScoreTxt);
        highscore = hiScoreTxt.intValue;
    }
    
    _pGameCoordinator->setHighScore(highscore, hasSyncd.boolValue ? GameCoordinator::HighScoreSource::Cloud
                                                                  : GameCoordinator::HighScoreSource::Local);
}

- (void)saveHighScore
{
    // Store new high score
    NSString* saveFilePath = [NSTemporaryDirectory() stringByAppendingString:@"/hiscore.txt"];
    NSString* hiScoreTxt = [NSString stringWithFormat:@"%d", _pGameCoordinator->highScore()];
    
    NSError* __autoreleasing fileError = nil;
    bool success = [hiScoreTxt writeToURL:[NSURL fileURLWithPath:saveFilePath]
                               atomically:NO
                                 encoding:NSUTF8StringEncoding
                                    error:&fileError];
    if (!success)
    {
        NSLog(@"Error writing temporary hi-score file: %@", fileError.localizedDescription);
        assert(false);
    }
    
    NSLog(@"Saved high score of: %@", hiScoreTxt);
}

#pragma mark - Cloud Saves demo

- (void)downloadCloudSavesBlocking:(BOOL)blocking
{
#if GP_SUPPORT_CLOUDSAVES
    __weak GameCoordinatorController* weakSelf = self;
    [_cloudSaveManager syncWithCompletionHandler:^(BOOL conflictDetected, NSError * _Nullable error) {
        GameCoordinatorController* strongSelf = weakSelf;
        
        if (blocking)
        {
            dispatch_semaphore_signal(strongSelf->_cloudSemaphore);
        }
        
        if (conflictDetected)
        {
            NSLog(@"Cloud high score conflict detected, favoring local changes");
        }
        else if (error)
        {
            NSLog(@"Error retrieving cloud high score, using local data. Error: (%@)", error.localizedDescription);
        }
        
        // Load previous high score from cloud save file.
        // There is no guarantee about the thread on which this block runs, so
        // the sample requests to the ObjC runtime that it calls "loadLastHighScoreAfterSync:"
        // on the main thread, since updating the in-game UI is not thread-safe.
        [strongSelf performSelectorOnMainThread:@selector(loadLastHighScoreAfterSync:)
                                     withObject:@YES
                                  waitUntilDone:NO];

    }];
    
    if (blocking)
    {
        dispatch_semaphore_wait(_cloudSemaphore, DISPATCH_TIME_FOREVER);
    }
#endif // #if GP_SUPPORT_CLOUDSAVES
}

- (void)uploadCloudSavesBlocking:(BOOL)blocking
{
#if GP_SUPPORT_CLOUDSAVES
    
    // Sync entire folder to cloud:
    __weak GameCoordinatorController* weakSelf = self;
    [_cloudSaveManager uploadWithCompletionHandler:^(BOOL conflictDetected, NSError * _Nullable error) {
        GameCoordinatorController* strongSelf = weakSelf;
        if (blocking)
        {
            dispatch_semaphore_signal(strongSelf->_cloudSemaphore);
        }
        
        if (conflictDetected || error)
        {
            NSLog(@"Error: %s", conflictDetected ? "Save conflict" : error.localizedDescription.UTF8String);
            assert(false);
        }
    }];
    
    if (blocking)
    {
        dispatch_semaphore_wait(_cloudSemaphore, DISPATCH_TIME_FOREVER);
    }
    
    NSLog(@"Sync complete");
#endif // #if GP_SUPPORT_CLOUDSAVES
}

@end
