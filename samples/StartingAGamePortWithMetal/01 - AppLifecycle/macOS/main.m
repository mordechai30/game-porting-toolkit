/*
<samplecode>
  <abstract>
  Standard macOS entry point that builds the menu bar and hands control to
  `NSApplicationMain`.
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

#import <Cocoa/Cocoa.h>
#import "GameApplication.h"

static void makeSliderSubmenu(NSMenu* parentMenu, NSString* title, SEL action, double minValue, double maxValue, double defaultValue, NSInteger tickmarks)
{
    NSMenu* submenu = [[NSMenu alloc] initWithTitle:title];
    
    NSMenuItem* sliderHostItem = [parentMenu addItemWithTitle:title action:nil keyEquivalent:@""];
    sliderHostItem.submenu = submenu;
    
    NSSlider* slider = [NSSlider sliderWithTarget:nil action:action];
    slider.frame = NSMakeRect(0, 0, 160, 16);
    NSMenuItem* sliderItem = [submenu addItemWithTitle:@"" action:nil keyEquivalent:@""];
    sliderItem.view = slider;
    slider.numberOfTickMarks = tickmarks;
    slider.minValue = minValue;
    slider.maxValue = maxValue;
    slider.intValue = defaultValue;
    slider.allowsTickMarkValuesOnly = tickmarks ? YES : NO;
    slider.autoresizingMask = NSViewMinXMargin|NSViewWidthSizable|NSViewMaxXMargin|NSViewMinYMargin|NSViewMaxYMargin|NSViewHeightSizable;
    [slider sizeToFit];
}

// Create system menu and set default shortcuts typically expected by macOS users.
static void createApplicationMenu(NSApplication* app)
{
    app.mainMenu = [[NSMenu alloc] init];

    NSString* bundleName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];

    // Create about menu
    
    NSMenu* appMenu = [[NSMenu alloc] initWithTitle:@""];
    NSMenuItem* appMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];

    [appMenu addItemWithTitle:[@"About " stringByAppendingString:bundleName]
                        action:@selector(orderFrontStandardAboutPanel:)
                 keyEquivalent:@""];

    [appMenu addItem:[NSMenuItem separatorItem]];

    [appMenu addItemWithTitle:[@"Hide " stringByAppendingString:bundleName]
                         action:@selector(hide:)
                  keyEquivalent:@"h"];

    NSMenuItem* hide_other_item = [appMenu addItemWithTitle:@"Hide Others"
                                                       action:@selector(hideOtherApplications:)
                                                keyEquivalent:@"h"];
    hide_other_item.keyEquivalentModifierMask = NSEventModifierFlagOption | NSEventModifierFlagCommand;

    [appMenu addItemWithTitle:@"Show All" action:@selector(unhideAllApplications:) keyEquivalent:@""];

    [appMenu addItem:[NSMenuItem separatorItem]];

    [appMenu addItemWithTitle:[@"Quit " stringByAppendingString:bundleName]
                        action:@selector(terminate:)
                 keyEquivalent:@"q"];

    appMenuItem.submenu = appMenu;

    [app.mainMenu addItem:appMenuItem];

    // Create graphics menu
    NSMenu* graphicsMenu = [[NSMenu alloc] initWithTitle:@"Graphics"];
    NSMenuItem* graphicsMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    graphicsMenuItem.submenu = graphicsMenu;
    
    makeSliderSubmenu(graphicsMenu, @"Brightness", @selector(setBrightness:), /* min */ 1, /* max */ 10, /* current */ 5, /* tickmarks */ 9);
    makeSliderSubmenu(graphicsMenu, @"EDR Demo",   @selector(setEDRBias:)   , /* min */ 0, /* max */ 1,  /* current */ 0, /* tickmarks */ 0);
    
    [app.mainMenu addItem:graphicsMenuItem];
    
    // Create window menu
    NSMenu* windowsMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    NSMenuItem* windowsMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];

    [windowsMenu addItemWithTitle:NSLocalizedString(@"Minimize", @"")
                            action:@selector(performMiniaturize:)
                     keyEquivalent:@"m"];
    windowsMenuItem.submenu = windowsMenu;
    [app.mainMenu addItem:windowsMenuItem];
    
    app.windowsMenu = windowsMenu;
}


int main(int argc, const char * argv[])
{
    NSApplication* application = [NSApplication sharedApplication];
    createApplicationMenu(application);
    
    // Set up the application and window delegate:
    GameApplication* gameApplication = [[GameApplication alloc] init];
    application.delegate             = gameApplication;
    
    // Yield the game loop to the `NSApplication`, which calls
    // application:didFinishLaunchingWithOptions: from the application delegate
    // (an instance of `macOS/GameApplication`), where this sample then sets
    // up view, and game.
    return NSApplicationMain(argc, argv);
}
