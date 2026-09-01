#import "ViewerView.h"

@implementation ViewerView

- (instancetype)initWithFrame:(NSRect)frameRect {
    if (self = [super initWithFrame:frameRect]) {
        self.wantsLayer = YES;
        self.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;
        _selecting = NO;
        _selectionRect = NSZeroRect;
    }
    return self;
}

- (void)setImage:(NSImage *)image {
    _image = image;
    _selectionRect = NSZeroRect;
    _selecting = NO;
    self.needsDisplay = YES;
}

- (BOOL)isFlipped { return NO; }

- (NSRect)imageDrawRect {
    if (!_image) return NSZeroRect;
    NSSize imgSize = _image.size;
    if (imgSize.width <= 0 || imgSize.height <= 0) return NSZeroRect;
    NSRect bounds = self.bounds;
    // Aspect fit
    CGFloat scale = MIN(bounds.size.width / imgSize.width,
                        bounds.size.height / imgSize.height);
    scale = MIN(scale, 1.0 * 4.0); // cho phép phóng tới 400% nếu ảnh nhỏ, giống viv.c zoom
    NSSize drawSize = NSMakeSize(imgSize.width * scale, imgSize.height * scale);
    NSRect r;
    r.size = drawSize;
    r.origin.x = NSMidX(bounds) - drawSize.width * 0.5;
    r.origin.y = NSMidY(bounds) - drawSize.height * 0.5;
    return NSIntegralRect(r);
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [[NSColor windowBackgroundColor] setFill];
    NSRectFill(self.bounds);

    if (_image) {
        NSRect dst = [self imageDrawRect];
        [_image drawInRect:dst
                  fromRect:NSMakeRect(0, 0, _image.size.width, _image.size.height)
                 operation:NSCompositingOperationSourceOver
                  fraction:1.0
            respectFlipped:YES
                     hints:@{NSImageHintInterpolation: @(NSImageInterpolationHigh)}];
    } else {
        // Placeholder
        NSString *msg = @"Kéo thả ảnh vào đây hoặc ⌘O để mở\nKéo vùng trên ảnh để OCR (Tesseract vie)";
        NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
        ps.alignment = NSTextAlignmentCenter;
        NSDictionary *attrs = @{
            NSFontAttributeName: [NSFont systemFontOfSize:13],
            NSForegroundColorAttributeName: [NSColor secondaryLabelColor],
            NSParagraphStyleAttributeName: ps
        };
        NSSize sz = [msg sizeWithAttributes:attrs];
        NSRect r = NSMakeRect(NSMidX(self.bounds)-sz.width/2, NSMidY(self.bounds)-sz.height/2, sz.width, sz.height);
        [msg drawInRect:r withAttributes:attrs];
    }

    // Vẽ selection
    if (_selecting || !NSEqualRects(_selectionRect, NSZeroRect)) {
        NSRect sel = _selectionRect;
        // chuẩn hóa
        sel = NSMakeRect(MIN(sel.origin.x, NSMaxX(sel)), MIN(sel.origin.y, NSMaxY(sel)),
                         fabs(sel.size.width), fabs(sel.size.height));
        // đường đứt nét như viv.c DrawFocusRect
        [[NSColor systemBlueColor] setStroke];
        NSBezierPath *path = [NSBezierPath bezierPathWithRect:sel];
        path.lineWidth = 1.0;
        CGFloat dash[2] = {4, 4};
        [path setLineDash:dash count:2 phase:0];
        [path stroke];
        // overlay mờ
        [[[NSColor systemBlueColor] colorWithAlphaComponent:0.15] setFill];
        NSRectFillUsingOperation(sel, NSCompositingOperationSourceOver);
    }
}

#pragma mark - Mouse (OCR selection, giống _viv_ocr_start/update/finish)

- (void)mouseDown:(NSEvent *)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    NSRect imgRect = [self imageDrawRect];
    if (!_image || !NSPointInRect(p, imgRect)) {
        [super mouseDown:event];
        return;
    }
    _selecting = YES;
    _selectionRect.origin = p;
    _selectionRect.size = NSZeroSize;
    self.needsDisplay = YES;
}

- (void)mouseDragged:(NSEvent *)event {
    if (!_selecting) { [super mouseDragged:event]; return; }
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    NSRect imgRect = [self imageDrawRect];
    // clamp vào image rect
    p.x = MAX(NSMinX(imgRect), MIN(NSMaxX(imgRect), p.x));
    p.y = MAX(NSMinY(imgRect), MIN(NSMaxY(imgRect), p.y));
    NSPoint origin = _selectionRect.origin;
    // origin giữ nguyên từ mouseDown
    _selectionRect = NSMakeRect(origin.x, origin.y, p.x - origin.x, p.y - origin.y);
    self.needsDisplay = YES;
}

- (void)mouseUp:(NSEvent *)event {
    if (!_selecting) { [super mouseUp:event]; return; }
    _selecting = NO;
    NSRect sel = _selectionRect;
    sel.size.width = fabs(sel.size.width);
    sel.size.height = fabs(sel.size.height);
    sel.origin.x = MIN(_selectionRect.origin.x, _selectionRect.origin.x + _selectionRect.size.width);
    sel.origin.y = MIN(_selectionRect.origin.y, _selectionRect.origin.y + _selectionRect.size.height);
    // Nếu chọn quá nhỏ -> bỏ
    if (sel.size.width < 8 || sel.size.height < 8) {
        _selectionRect = NSZeroRect;
        self.needsDisplay = YES;
        return;
    }
    _selectionRect = sel;
    self.needsDisplay = YES;
    if (self.onSelectionFinished) {
        self.onSelectionFinished(sel);
    }
}

- (NSRect)selectionInImagePixels:(NSRect)selInView {
    NSRect imgRect = [self imageDrawRect];
    if (NSEqualRects(imgRect, NSZeroRect) || !_image) return NSZeroRect;
    // map view rect -> image pixel rect
    CGFloat sx = _image.size.width / imgRect.size.width;
    CGFloat sy = _image.size.height / imgRect.size.height;
    // view coord origin bottom-left; need flip Y vì image origin top-left?
    // NSView isFlipped NO, imageDrawRect origin bottom-left.
    NSRect r;
    r.origin.x = (selInView.origin.x - imgRect.origin.x) * sx;
    r.origin.y = (selInView.origin.y - imgRect.origin.y) * sy;
    r.size.width = selInView.size.width * sx;
    r.size.height = selInView.size.height * sy;
    // clamp
    r.origin.x = MAX(0, r.origin.x);
    r.origin.y = MAX(0, r.origin.y);
    r.size.width = MIN(_image.size.width - r.origin.x, r.size.width);
    r.size.height = MIN(_image.size.height - r.origin.y, r.size.height);
    // Chú ý: CGImage origin top-left, cần flip Y
    r.origin.y = _image.size.height - r.origin.y - r.size.height;
    return NSIntegralRect(r);
}

@end
