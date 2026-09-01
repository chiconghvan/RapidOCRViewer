#import "OCRPanel.h"

@implementation OCRPanel

- (instancetype)initWithFrame:(NSRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.wantsLayer = YES;
        self.layer.backgroundColor = [NSColor controlBackgroundColor].CGColor;
        self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

        // Title
        NSTextField *title = [NSTextField labelWithString:@"Fast OCR (vie) – Kéo vùng trên ảnh để nhận dạng"];
        title.font = [NSFont boldSystemFontOfSize:11];
        title.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:title];

        // TextView trong ScrollView
        NSScrollView *scroll = [[NSScrollView alloc] init];
        scroll.translatesAutoresizingMaskIntoConstraints = NO;
        scroll.hasVerticalScroller = YES;
        scroll.borderType = NSBezelBorder;
        _textView = [[NSTextView alloc] init];
        _textView.editable = YES;
        _textView.richText = NO;
        _textView.font = [NSFont systemFontOfSize:12];
        _textView.string = @"";
        scroll.documentView = _textView;
        [self addSubview:scroll];

        _copyButton = [NSButton buttonWithTitle:@"Copy" target:self action:@selector(onCopy:)];
        _copyButton.bezelStyle = NSBezelStyleRounded;
        _copyButton.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_copyButton];

        _clearButton = [NSButton buttonWithTitle:@"Clear" target:self action:@selector(onClear:)];
        _clearButton.bezelStyle = NSBezelStyleRounded;
        _clearButton.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_clearButton];

        _paragraphButton = [NSButton checkboxWithTitle:@"Merge paragraphs" target:nil action:nil];
        _paragraphButton.state = NSControlStateValueOn;
        _paragraphButton.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_paragraphButton];

        [NSLayoutConstraint activateConstraints:@[
            [title.topAnchor constraintEqualToAnchor:self.topAnchor constant:8],
            [title.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8],
            [title.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],

            [scroll.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:8],
            [scroll.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8],
            [scroll.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
            [scroll.bottomAnchor constraintEqualToAnchor:_copyButton.topAnchor constant:-8],

            [_copyButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8],
            [_copyButton.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-8],
            [_copyButton.widthAnchor constraintEqualToConstant:80],

            [_clearButton.leadingAnchor constraintEqualToAnchor:_copyButton.trailingAnchor constant:8],
            [_clearButton.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-8],
            [_clearButton.widthAnchor constraintEqualToConstant:80],

            [_paragraphButton.leadingAnchor constraintEqualToAnchor:_clearButton.trailingAnchor constant:12],
            [_paragraphButton.centerYAnchor constraintEqualToAnchor:_copyButton.centerYAnchor],
        ]];

        // Placeholder
        _textView.string = @"Sẵn sàng. Kéo một vùng chữ trên ảnh để OCR.";
    }
    return self;
}

- (void)setText:(NSString *)text busy:(BOOL)busy {
    (void)busy;
    _textView.string = text ?: @"";
    if (busy) {
        _textView.string = @"Recognizing…";
    }
}

- (void)setBusy:(BOOL)busy {
    if (busy) _textView.string = @"Recognizing…";
    _copyButton.enabled = !busy;
}

- (void)onCopy:(id)sender {
    (void)sender;
    NSString *s = _textView.string;
    if (!s.length) return;
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:s forType:NSPasteboardTypeString];
}

- (void)onClear:(id)sender {
    (void)sender;
    _textView.string = @"";
}

@end
