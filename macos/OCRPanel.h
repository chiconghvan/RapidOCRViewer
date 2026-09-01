#pragma once
#import <Cocoa/Cocoa.h>

@interface OCRPanel : NSView
@property (strong) NSTextView *textView;
@property (strong) NSButton *copyButton;
@property (strong) NSButton *clearButton;
@property (strong) NSButton *paragraphButton;
- (void)setText:(NSString *)text busy:(BOOL)busy;
- (void)setBusy:(BOOL)busy;
@end
