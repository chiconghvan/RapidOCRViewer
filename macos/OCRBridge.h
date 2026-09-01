#pragma once
#import <Cocoa/Cocoa.h>

// Bridge Tesseract: nhận NSImage + rect pixel -> string
// Dùng AppleClang + brew tesseract khi có, fallback mock string khi không.

@interface OCRBridge : NSObject
+ (instancetype)shared;
- (BOOL)setupWithTessdataPath:(NSString *)path; // trả về YES nếu init thành công
- (BOOL)isAvailable;
- (NSString *)lastError;
- (void)recognizeImage:(NSImage *)image
              cropRect:(NSRect)cropInPixels // origin top-left, pixel coords
            completion:(void(^)(NSString *text, NSString *error))completion;
@end
