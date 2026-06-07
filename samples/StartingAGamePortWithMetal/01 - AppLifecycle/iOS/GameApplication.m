/*
<samplecode>
  <abstract>
  iOS application delegate. Creates the window, the Metal view, and the
  virtual game controller, then hands off to the shared
  `GameCoordinatorController`.
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

#import <GameController/GameController.h>

#import "GameCoordinatorController.h"
#import "GameView.h"

#import "GameApplication.h"

@implementation GameApplication {
    UIWindow*                  _window;
    CAMetalLayer*              _metalLayer;
    GameView*                  _view;
    GameViewController*        _viewController;
    GameCoordinatorController* _gameCoordinator;
    GCVirtualController*       _virtualController;
}

// Entry point for the game on iOS.
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    // Prevent the iOS device from going to sleep when playing the game:
    UIApplication.sharedApplication.idleTimerDisabled = YES;
    
    [self createWindow];
    [self createView];
    [self createGame];
    [self initVirtualController];
    
    [_gameCoordinator loadLastHighScoreAfterSync:@NO];
    
#if GP_SUPPORT_CLOUDSAVES
    // Sync high score from cloud
    NSLog(@"Sync\'ing down");
    [_gameCoordinator downloadCloudSavesBlocking:NO];
#endif // GP_SUPPORT_CLOUDSAVES
    
    return YES;
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    [_gameCoordinator saveHighScore];

#if GP_SUPPORT_CLOUDSAVES
    // Sync high score from cloud
    NSLog(@"Sync'ing up");
    [_gameCoordinator uploadCloudSavesBlocking:YES];
#endif // GP_SUPPORT_CLOUDSAVES
    
    self->_gameCoordinator = nil;
}

- (void)createWindow
{
    UIScreen* screen = [UIScreen mainScreen];
    _window = [[UIWindow alloc] initWithFrame:screen.bounds];

    [_window makeKeyAndVisible];
}

- (void)createView
{
    NSAssert(_window, @"You need to create the window before the view");
    
    // Set up the view controller, its view, and install them into the window:
    _view = [[GameView alloc] initWithFrame:_window.screen.bounds];
    _viewController = [[GameViewController alloc] init];
    _viewController.view = _view;
    _window.rootViewController = _viewController;
    
    // Set layer size and make it opaque:
    _metalLayer = (CAMetalLayer*)_view.layer;
    _metalLayer.drawableSize = CGSizeMake(1920 , 1080);
    _metalLayer.opaque = YES;
    _metalLayer.framebufferOnly = YES;
    
    // Configure CoreAnimation letterboxing:
    _metalLayer.contentsGravity = kCAGravityResizeAspect;
    _metalLayer.backgroundColor = CGColorGetConstantColor(kCGColorBlack);
    
    // Prepare the layer for EDR rendering:
    _metalLayer.pixelFormat = MTLPixelFormatRGBA16Float;
    _metalLayer.wantsExtendedDynamicRangeContent = YES;
    _metalLayer.colorspace = CGColorSpaceCreateWithName(kCGColorSpaceExtendedLinearDisplayP3);
}

- (void)createGame
{
    NSAssert(_metalLayer, @"You need to create the MetalLayer before creating the game");
    
    
    // The canvas size represents a relative amount of screen real estate for UI elements.
    // Since the UI elements are fixed size, on iOS set a canvas smaller than on macOS to
    // produce a UI with larger elements that are easier to read on smaller screens.
    NSUInteger gameUICanvasSize = 20;
    _gameCoordinator = [[GameCoordinatorController alloc] initWithMetalLayer:_metalLayer
                                                            gameUICanvasSize:gameUICanvasSize];
}

- (void)initVirtualController
{
    [self updateVirtualControllerVisibility];

    NSNotificationCenter* notif = NSNotificationCenter.defaultCenter;
    NSOperationQueue* mainQueue = NSOperationQueue.mainQueue;
    [notif addObserverForName:GCControllerDidConnectNotification object:nil queue:mainQueue usingBlock:^(NSNotification * _Nonnull notification) {
        [self onControllerConnected:notification];
    }];

    [notif addObserverForName:GCControllerDidDisconnectNotification object:nil queue:mainQueue usingBlock:^(NSNotification * _Nonnull notification) {
        [self onControllerDisconnected:notification];
    }];
    
    [NSNotificationCenter.defaultCenter addObserverForName:GCKeyboardDidConnectNotification
                                                    object:nil
                                                     queue:nil
                                                usingBlock:^(NSNotification * _Nonnull notification) {
        [self updateVirtualControllerVisibility];
    }];
    
    [NSNotificationCenter.defaultCenter addObserverForName:GCKeyboardDidDisconnectNotification
                                                    object:nil
                                                     queue:nil
                                                usingBlock:^(NSNotification * _Nonnull notification) {
        [self updateVirtualControllerVisibility];
    }];
}

- (void)updateVirtualControllerVisibility
{
    // Create a virtual game controller with a left thumbstick and an action button "A".
    // In your game, consider conveying the semantics of each action by customizing the
    // action button's glyph.

    if (GCController.controllers.count == 0 && GCKeyboard.coalescedKeyboard.keyboardInput == nil)
    {
        // Create a configuration object for the Virtual Game Controller:
        GCVirtualControllerConfiguration* virtualGCConfig = [[GCVirtualControllerConfiguration alloc] init];

        // Set its virtual buttons and create it:
        virtualGCConfig.elements = [NSSet setWithObjects:GCInputLeftThumbstick, GCInputButtonA, nil];
        _virtualController = [[GCVirtualController alloc] initWithConfiguration:virtualGCConfig];

        // Connect the Virtual Game Controller:
        [_virtualController connectWithReplyHandler:nil];

        _viewController.physicalGameControllerInUse = NO;
    }
    else
    {
        _viewController.physicalGameControllerInUse = YES;
        [_virtualController disconnect];
    }
}

- (void)onControllerDisconnected:(NSNotification*)notification
{
    if (_virtualController == nil && GCController.controllers.count == 0)
    {
        // Last physical controller disconnected and there is no virtual one,
        // connect a virtual GC.

        // Create a configuration object for the Virtual Game Controller:
        GCVirtualControllerConfiguration* virtualGCConfig = [[GCVirtualControllerConfiguration alloc] init];

        // Set its virtual buttons and create it:
        virtualGCConfig.elements = [NSSet setWithObjects:GCInputLeftThumbstick, GCInputButtonA, nil];
        _virtualController = [[GCVirtualController alloc] initWithConfiguration:virtualGCConfig];

        // Connect the Virtual Game Controller:
        [_virtualController connectWithReplyHandler:nil];
    }
}

- (void)onControllerConnected:(NSNotification *)notification
{
    if (GCController.controllers.count > 1 && _virtualController != nil)
    {
        // Connected a physical controller, disconnect the virtual one:
        [_virtualController disconnect];
        _virtualController = nil;
    }
}

@end
