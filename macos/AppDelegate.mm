#import "AppDelegate.h"
#import "ViewerWindow.h"

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    NSRect frame = NSMakeRect(100, 100, 1100, 700);
    self.window = [[ViewerWindow alloc] initWithContentRect:frame
                                                  styleMask:(NSWindowStyleMaskTitled |
                                                             NSWindowStyleMaskClosable |
                                                             NSWindowStyleMaskResizable |
                                                             NSWindowStyleMaskMiniaturizable)
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

    // Mở file từ command line: open RapidOCRViewer.app --args /path/to/image.jpg
    NSArray *args = [[NSProcessInfo processInfo] arguments];
    for (NSString *arg in args) {
        if ([arg hasPrefix:@"/"] || [arg hasPrefix:@"./"]) {
            NSURL *url = [NSURL fileURLWithPath:arg];
            if ([[NSFileManager defaultManager] fileExistsAtPath:arg]) {
                [self.window openImageAtURL:url];
                break;
            }
        }
    }
}

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender {
    (void)sender;
    return NO;
}

- (BOOL)applicationOpenUntitledFile:(NSApplication *)sender {
    (void)sender;
    [self.window performOpenPanel:nil];
    return YES;
}

- (void)application:(NSApplication *)sender openFiles:(NSArray<NSString *> *)filenames {
    (void)sender;
    for (NSString *path in filenames) {
        NSURL *url = [NSURL fileURLWithPath:path];
        [self.window openImageAtURL:url];
        break; // chỉ mở file đầu tiên (playlist sẽ bổ sung sau)
    }
    [sender replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    (void)sender;
    return YES;
}

@end
