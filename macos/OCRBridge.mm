#import "OCRBridge.h"

#ifdef HAVE_TESSERACT
#include <tesseract/baseapi.h>
#include <leptonica/allheaders.h>
#include <mutex>
static tesseract::TessBaseAPI *g_api = nullptr;
static std::mutex g_mutex;
static BOOL g_inited = NO;
static NSString *g_lastError = nil;
#endif

@implementation OCRBridge

+ (instancetype)shared {
    static OCRBridge *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[OCRBridge alloc] init]; });
    return s;
}

- (BOOL)setupWithTessdataPath:(NSString *)path {
#ifdef HAVE_TESSERACT
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_inited) return YES;
    if (!path.length) {
        g_lastError = @"tessdata path empty";
        return NO;
    }
    const char *utf8 = path.UTF8String;
    g_api = new tesseract::TessBaseAPI();
    if (g_api->Init(utf8, "vie", tesseract::OEM_LSTM_ONLY) != 0) {
        g_lastError = [NSString stringWithFormat:@"Tess Init failed for vie in %s", utf8];
        delete g_api; g_api = nullptr;
        return NO;
    }
    g_api->SetVariable("tessedit_do_invert", "0");
    g_inited = YES;
    g_lastError = nil;
    return YES;
#else
    (void)path;
    g_lastError = @"Tesseract not compiled (HAVE_TESSERACT=0). Cài brew install tesseract leptonica và rebuild.";
    return YES; // mock vẫn cho chạy
#endif
}

- (BOOL)isAvailable {
#ifdef HAVE_TESSERACT
    return g_inited && g_api != nullptr;
#else
    return NO;
#endif
}

- (NSString *)lastError {
#ifdef HAVE_TESSERACT
    return g_lastError;
#else
    return g_lastError ?: @"Mock OCR";
#endif
}

static Pix *PixFromNSImageCrop(NSImage *image, NSRect crop) {
#ifdef HAVE_TESSERACT
    if (!image || crop.size.width <= 1 || crop.size.height <= 1) return nullptr;
    // NSImage -> CGImage -> bitmap BGRA
    NSRect rect = NSMakeRect(0, 0, image.size.width, image.size.height);
    CGImageRef cg = [image CGImageForProposedRect:&rect context:nil hints:nil];
    if (!cg) return nullptr;
    size_t w = CGImageGetWidth(cg);
    size_t h = CGImageGetHeight(cg);
    // crop đã là pixel rect top-left
    int cx = (int)crop.origin.x;
    int cy = (int)crop.origin.y;
    int cw = (int)crop.size.width;
    int ch = (int)crop.size.height;
    cx = MAX(0, MIN((int)w - 1, cx));
    cy = MAX(0, MIN((int)h - 1, cy));
    cw = MIN(cw, (int)w - cx);
    ch = MIN(ch, (int)h - cy);
    if (cw <= 0 || ch <= 0) return nullptr;

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    // 8-bit BGRA
    NSMutableData *data = [NSMutableData dataWithLength:w * h * 4];
    CGContextRef ctx = CGBitmapContextCreate(data.mutableBytes, w, h, 8, w*4, cs,
                                            kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs);
    if (!ctx) return nullptr;
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), cg);
    CGContextRelease(ctx);

    // crop + convert to Pix
    Pix *pix = pixCreate(cw, ch, 32);
    if (!pix) return nullptr;
    uint8_t *bytes = (uint8_t *)data.bytes;
    for (int y = 0; y < ch; y++) {
        l_uint32 *line = pixGetData(pix) + y * pixGetWpl(pix);
        int srcY = cy + y;
        uint8_t *src = bytes + srcY * w * 4;
        for (int x = 0; x < cw; x++) {
            int srcX = cx + x;
            uint8_t r = src[srcX*4+0];
            uint8_t g = src[srcX*4+1];
            uint8_t b = src[srcX*4+2];
            l_uint32 v;
            composeRGBPixel(r, g, b, &v);
            line[x] = v;
        }
    }
    pixSetXRes(pix, 300);
    pixSetYRes(pix, 300);
    return pix;
#else
    (void)image; (void)crop;
    return nullptr;
#endif
}

- (void)recognizeImage:(NSImage *)image cropRect:(NSRect)cropInPixels completion:(void(^)(NSString *text, NSString *error))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
#ifdef HAVE_TESSERACT
        std::lock_guard<std::mutex> lock(g_mutex);
        if (!g_inited || !g_api) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, @"OCR not inited"); });
            return;
        }
        Pix *pix = PixFromNSImageCrop(image, cropInPixels);
        if (!pix) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, @"Pix create failed"); });
            return;
        }
        int pw = pixGetWidth(pix), ph = pixGetHeight(pix);
        Pix *toUse = pix;
        if (pw < 200 || ph < 50) {
            Pix *scaled = pixScale(pix, 2.0, 2.0);
            if (scaled) { pixDestroy(&pix); toUse = scaled; }
        }
        g_api->SetImage(toUse);
        g_api->SetPageSegMode(tesseract::PSM_AUTO);
        char *utf8 = g_api->GetUTF8Text();
        pixDestroy(&toUse);
        if (!utf8) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, @"GetUTF8Text null"); });
            return;
        }
        NSString *text = [NSString stringWithUTF8String:utf8];
        // Free bên trong DLL: dùng delete[] nếu build static, hoặc tess delete
        // Khi link brew dylib thì free bằng delete[]
        delete[] utf8; // tesseract 5 brew trả về new char[]
        // Trim
        text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!text.length) text = @"(không nhận dạng được chữ)";
        dispatch_async(dispatch_get_main_queue(), ^{ completion(text, nil); });
#else
        (void)image;
        NSString *mock = [NSString stringWithFormat:
            @"[Demo OCR] Vùng: %.0f,%.0f %.0fx%.0f\n\nTesseract chưa biên dịch (HAVE_TESSERACT=0).\nCài: brew install tesseract leptonica\nRồi rebuild: cmake --build build/macos\n\nVí dụ tiếng Việt: Xin chào, Hà Nội – Đà Nẵng – TP. Hồ Chí Minh.",
            cropInPixels.origin.x, cropInPixels.origin.y, cropInPixels.size.width, cropInPixels.size.height];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(mock, nil); });
#endif
    });
}

@end
