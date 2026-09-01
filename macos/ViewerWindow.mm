#import "ViewerWindow.h"
#import "ViewerView.h"
#import "OCRPanel.h"
#import "OCRBridge.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface ViewerWindow () <NSWindowDelegate>
@property (strong) NSSplitView *split;
@property (strong) NSImage *currentImage;
@property (strong) NSURL *currentURL;
@end

@implementation ViewerWindow

- (instancetype)initWithContentRect:(NSRect)contentRect styleMask:(NSWindowStyleMask)style backing:(NSBackingStoreType)backingStoreType defer:(BOOL)flag {
    if (self = [super initWithContentRect:contentRect styleMask:style backing:backingStoreType defer:flag]) {
        self.title = @"RapidOCRViewer – macOS native (Apple Clang)";
        self.delegate = self;
        self.releasedWhenClosed = NO;
        self.minSize = NSMakeSize(700, 400);

        // Menu (minimal)
        [self buildMenu];

        _split = [[NSSplitView alloc] initWithFrame:self.contentView.bounds];
        _split.vertical = YES;
        _split.dividerStyle = NSSplitViewDividerStyleThin;
        _split.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [self.contentView addSubview:_split];

        _viewerView = [[ViewerView alloc] initWithFrame:NSMakeRect(0,0,700,600)];
        [_viewerView setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];

        // OCR panel bên phải 320px như bản Windows
        _ocrPanel = [[OCRPanel alloc] initWithFrame:NSMakeRect(0,0,320,600)];

        [_split addSubview:_viewerView];
        [_split addSubview:_ocrPanel];
        // Giữ panel 320px
        [_split setHoldingPriority:NSLayoutPriorityDefaultHigh forSubviewAtIndex:1];

        // OCR callback
        __weak typeof(self) weak = self;
        _viewerView.onSelectionFinished = ^(NSRect selInView){
            [weak runOCRWithSelection:selInView];
        };

        // Drag & drop
        [self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];

        // Tessdata path: .app/Resources/tessdata  hoặc  ./tessdata  (dev)
        NSString *resTess = [[NSBundle mainBundle] pathForResource:@"vie" ofType:@"traineddata" inDirectory:@"tessdata"];
        NSString *tessDir = resTess ? [resTess stringByDeletingLastPathComponent] : nil;
        if (!tessDir) {
            // dev fallback: repo/tessdata
            NSString *dev = [[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent];
            // build/macos/RapidOCRViewer.app/Contents/MacOS -> repo
            for (int i=0;i<4;i++) {
                NSString *cand = [dev stringByAppendingPathComponent:@"tessdata"];
                if ([[NSFileManager defaultManager] fileExistsAtPath:[cand stringByAppendingPathComponent:@"vie.traineddata"]]) {
                    tessDir = cand; break;
                }
                dev = [dev stringByDeletingLastPathComponent];
            }
            if (!tessDir) {
                // CWD
                if ([[NSFileManager defaultManager] fileExistsAtPath:@"tessdata/vie.traineddata"]) tessDir = @"tessdata";
            }
        }
        if (tessDir) {
            [[OCRBridge shared] setupWithTessdataPath:tessDir];
            NSLog(@"[OCR] tessdata: %@", tessDir);
        } else {
            NSLog(@"[OCR] tessdata not found, mock mode");
            [[OCRBridge shared] setupWithTessdataPath:@""];
        }

        // Layout
        [self.contentView setNeedsLayout:YES];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self adjustSplit];
        });
    }
    return self;
}

- (void)adjustSplit {
    CGFloat w = self.contentView.bounds.size.width;
    CGFloat left = MAX(400, w - 320);
    [_split setPosition:left ofDividerAtIndex:0];
}

- (void)windowDidResize:(NSNotification *)notification {
    (void)notification;
    // giữ panel 320px khi resize như _viv_on_size
}

- (void)buildMenu {
    NSMenu *main = [[NSMenu alloc] init];
    // App
    NSMenuItem *appItem = [[NSMenuItem alloc] init];
    NSMenu *appMenu = [[NSMenu alloc] init];
    [appMenu addItemWithTitle:@"About RapidOCRViewer" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = appMenu;
    [main addItem:appItem];
    // File
    NSMenuItem *fileItem = [[NSMenuItem alloc] init];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    [fileMenu addItemWithTitle:@"Open…" action:@selector(performOpenPanel:) keyEquivalent:@"o"];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"Close" action:@selector(performClose:) keyEquivalent:@"w"];
    fileItem.submenu = fileMenu;
    [main addItem:fileItem];
    // View
    NSMenuItem *viewItem = [[NSMenuItem alloc] init];
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    [viewMenu addItemWithTitle:@"Toggle OCR Panel" action:@selector(toggleOCRPanel:) keyEquivalent:@""];
    viewItem.submenu = viewMenu;
    [main addItem:viewItem];
    [NSApp setMainMenu:main];
}

- (IBAction)performOpenPanel:(id)sender {
    (void)sender;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowsMultipleSelection = NO;
    panel.canChooseDirectories = NO;
    panel.allowedContentTypes = @[UTTypeImage, UTTypeBMP, UTTypeGIF, UTTypePNG, UTTypeJPEG, UTTypeTIFF, UTTypeWebP];
    // fallback cho macOS <11
    if (!panel.allowedContentTypes) {
        panel.allowedFileTypes = @[@"bmp",@"gif",@"ico",@"jpg",@"jpeg",@"png",@"tif",@"tiff",@"webp"];
    }
    if ([panel runModal] == NSModalResponseOK) {
        [self openImageAtURL:panel.URL];
    }
}

- (void)openImageAtURL:(NSURL *)url {
    if (!url) return;
    NSImage *img = [[NSImage alloc] initWithContentsOfURL:url];
    if (!img) {
        NSAlert *a = [[NSAlert alloc] init];
        a.messageText = @"Không mở được ảnh";
        a.informativeText = url.path;
        [a runModal];
        return;
    }
    self.currentImage = img;
    self.currentURL = url;
    self.viewerView.image = img;
    self.title = [NSString stringWithFormat:@"%@ — RapidOCRViewer", url.lastPathComponent];
    // clear OCR như _viv_ocr_clear_panel_on_image_change
    [self.ocrPanel setText:@"" busy:NO];
    self.viewerView.selectionRect = NSZeroRect;
    [self.viewerView setNeedsDisplay:YES];
}

- (void)runOCRWithSelection:(NSRect)selInView {
    if (!self.currentImage) return;
    NSRect crop = [self.viewerView selectionInImagePixels:selInView];
    if (crop.size.width < 4 || crop.size.height < 4) return;
    [self.ocrPanel setBusy:YES];
    [[OCRBridge shared] recognizeImage:self.currentImage cropRect:crop completion:^(NSString *text, NSString *error){
        if (error) {
            [self.ocrPanel setText:[NSString stringWithFormat:@"Lỗi OCR: %@\n%@", error, [[OCRBridge shared] lastError] ?: @""] busy:NO];
        } else {
            [self.ocrPanel setText:text busy:NO];
        }
    }];
}

- (IBAction)toggleOCRPanel:(id)sender {
    (void)sender;
    BOOL collapsed = [_split isSubviewCollapsed:_ocrPanel];
    [_split setPosition:collapsed ? (self.contentView.bounds.size.width - 320) : self.contentView.bounds.size.width
       ofDividerAtIndex:0];
}

#pragma mark - Drag & drop

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    NSPasteboard *pb = sender.draggingPasteboard;
    if ([pb canReadObjectForClasses:@[[NSURL class]] options:@{NSPasteboardURLReadingFileURLsOnlyKey:@YES}]) {
        return NSDragOperationCopy;
    }
    return NSDragOperationNone;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSArray *urls = [sender.draggingPasteboard readObjectsForClasses:@[[NSURL class]] options:@{NSPasteboardURLReadingFileURLsOnlyKey:@YES}];
    for (NSURL *url in urls) {
        [self openImageAtURL:url];
        break;
    }
    return YES;
}

@end
