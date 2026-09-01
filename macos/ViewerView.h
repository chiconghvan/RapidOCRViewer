#pragma once
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

// View hiển thị ảnh + cho phép kéo chọn vùng OCR
@interface ViewerView : NSView
@property (strong) NSImage *image;
@property (assign) NSRect selectionRect; // trong coord của view
@property (assign) BOOL selecting;
@property (copy) void (^onSelectionFinished)(NSRect selInView); // callback khi thả chuột
- (void)setImage:(NSImage *)image;
- (NSRect)imageDrawRect; // rect thực tế ảnh đang vẽ (aspect fit)
- (NSRect)selectionInImagePixels:(NSRect)selInView;
@end
