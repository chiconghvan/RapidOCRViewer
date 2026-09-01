#pragma once
#import <Cocoa/Cocoa.h>

@class ViewerWindow;

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (strong) ViewerWindow *window;
@end
