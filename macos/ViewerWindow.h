#pragma once
#import <Cocoa/Cocoa.h>

@class ViewerView;
@class OCRPanel;

@interface ViewerWindow : NSWindow
@property (strong) ViewerView *viewerView;
@property (strong) OCRPanel *ocrPanel;
- (void)openImageAtURL:(NSURL *)url;
- (IBAction)performOpenPanel:(id)sender;
@end
