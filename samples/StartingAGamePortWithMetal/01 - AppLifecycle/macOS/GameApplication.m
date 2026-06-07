/*
<samplecode>
  <abstract>
  macOS application delegate. Creates a window with a Metal-backed `NSView`,
  instantiates the game coordinator, and forwards EDR-headroom changes.
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

#import "GameCoordinatorController.h"
#import "GameApplication.h"

#include <Metal/Metal.h>
#include <QuartzCore/CAMetalLayer.h>


@interface GameWindow : NSWindow
@end

@implementation GameWindow
// Override this method to prevent the system click sound when the user presses Escape to exit fullscreen.
- (void)keyDown:(NSEvent *)event
{
}
@end

@implementation GameApplication
{
    GameWindow*                _window;
    NSView*                    _view;
    CAMetalLayer*              _metalLayer;
    GameCoordinatorController* _gameCoordinator;
}

- (BOOL) applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    return YES;
}

- (void)createWindow
{
    NSWindowStyleMask mask = NSWindowStyleMaskClosable | NSWindowStyleMaskTitled | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
    NSScreen * screen = [NSScreen mainScreen];

    NSRect contentRect = NSMakeRect(0, 0, 1280, 720);

    // Center the window on the screen.
    contentRect.origin.x = (screen.frame.size.width / 2) - (contentRect.size.width / 2);
    contentRect.origin.y = (screen.frame.size.height / 2) - (contentRect.size.height / 2);

    _window = [[GameWindow alloc] initWithContentRect:contentRect
                                            styleMask:mask
                                              backing:NSBackingStoreBuffered
                                                defer:NO
                                               screen:screen];

    _window.releasedWhenClosed = NO;
    _window.minSize = NSMakeSize(640, 360);
    _window.delegate = self;

    [self updateWindowTitle:_window];
}

- (void)showWindow
{
    [_window setIsVisible:YES];
    [_window makeMainWindow];
    [_window makeKeyAndOrderFront:_window];
}

// Create the view and Metal layer backing it that renders the game
- (void)createView
{
    NSAssert(_window, @"You need to create the window before the view");
    
    _metalLayer = [[CAMetalLayer alloc] init];
    _metalLayer.device = MTLCreateSystemDefaultDevice();
    
    // Set layer size and make it opaque:
    _metalLayer.drawableSize = NSMakeSize(1920 , 1080);
    _metalLayer.opaque = YES;
    _metalLayer.framebufferOnly = YES;
    
    // Configure CoreAnimation letterboxing:
    _metalLayer.contentsGravity = kCAGravityResizeAspect;
    _metalLayer.backgroundColor = CGColorGetConstantColor(kCGColorBlack);
    
    // Prepare the layer for EDR rendering:
    _metalLayer.pixelFormat = MTLPixelFormatRGBA16Float;
    _metalLayer.wantsExtendedDynamicRangeContent = YES;
    _metalLayer.colorspace = CGColorSpaceCreateWithName(kCGColorSpaceExtendedLinearDisplayP3);

    // Create a view and customize its layer to a MetalLayer where
    // the game can render Metal content:
    _view = [[NSView alloc] initWithFrame:_window.contentLayoutRect];
    _view.layer = _metalLayer;

    _window.contentView = _view;
}

- (void)createGame
{
    NSAssert(_metalLayer, @"You need to create the MetalLayer before creating the game");
    
    // The canvas size represents a relative amount of screen real estate for UI elements.
    // Since the UI elements are fixed size, on macOS set a canvas larger than on iOS to
    // produce a stylized UI with smaller elements.
    NSUInteger gameUICanvasSize = 30;
    _gameCoordinator = [[GameCoordinatorController alloc] initWithMetalLayer:_metalLayer
                                                                  gameUICanvasSize:gameUICanvasSize];
}

- (void)evaluateCommandLine
{
    NSArray<NSString *>* args = [[NSProcessInfo processInfo] arguments];
    BOOL exitAfterOneFrame = [args containsObject:@"--auto-close"];

    if (exitAfterOneFrame)
    {
        NSLog(@"Automatically terminating in 5 seconds...");
        [[NSApplication sharedApplication] performSelector:@selector(terminate:) withObject:self afterDelay:5];
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    [self createWindow];
    [self createView];
    [self createGame];
    [self showWindow];
    [self evaluateCommandLine];
    [self updateMaxEDRValue];

    [NSNotificationCenter.defaultCenter addObserver:self 
                                           selector:@selector(maxEDRValueDidChange:)
                                               name:NSApplicationDidChangeScreenParametersNotification
                                             object:nil];
    
    [_gameCoordinator loadLastHighScoreAfterSync:@NO];
    
#if GP_SUPPORT_CLOUDSAVES
    // Sync high score from cloud
    NSLog(@"Sync\'ing down");
    [_gameCoordinator downloadCloudSavesBlocking:NO];
#endif // GP_SUPPORT_CLOUDSAVES
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    [_gameCoordinator saveHighScore];
    
#if GP_SUPPORT_CLOUDSAVES
    // Sync high score from cloud
    NSLog(@"Sync'ing up");
    [_gameCoordinator uploadCloudSavesBlocking:YES];
#endif // GP_SUPPORT_CLOUDSAVES
    self->_gameCoordinator = nil;
}

- (void)updateMaxEDRValue
{
    float maxEDRValue = _window.screen.maximumExtendedDynamicRangeColorComponentValue;
    [_gameCoordinator maxEDRValueDidChangeTo:maxEDRValue];
    [self updateWindowTitle:_window];
}

- (void)maxEDRValueDidChange:(NSNotification *)notification
{
    [self updateMaxEDRValue];
}

- (void)updateWindowTitle:(nonnull NSWindow *) window
{
    NSScreen* screen = window.screen;

    NSString* title = [NSString stringWithFormat:@"Game Project (%@ @ %ldHz, EDR max: %.2f)",
                       screen.localizedName,
                       (long)screen.maximumFramesPerSecond,
                       screen.maximumExtendedDynamicRangeColorComponentValue
    ];

    window.title = title;
}

- (void)windowDidChangeScreen:(NSNotification *)notification
{
    [self updateMaxEDRValue];
}

- (void)setBrightness:(id)sender
{
    NSSlider* slider = (NSSlider *)sender;
    float brightness = slider.floatValue * 100;
    
    NSAssert(_gameCoordinator, @"Game coordinator needs to be initialized to set brightness");
    [_gameCoordinator setBrightness:brightness];
}

- (void)setEDRBias:(id)sender
{
    NSSlider* slider = (NSSlider *)sender;
    float edrBias = slider.floatValue;
    
    NSAssert(_gameCoordinator, @"Game coordinator needs to be initialized to set EDR bias");
    [_gameCoordinator setEDRBias:edrBias];
}

@end
