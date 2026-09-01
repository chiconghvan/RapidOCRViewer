# macOS native (Apple Clang + AppKit)

Đây là port **native macOS** của RapidOCRViewer, build bằng **Apple Clang** (Xcode CLT) ra `.app` thật sự, không phải cross MinGW + Wine.

## Kiến trúc
- `src/` gốc là Win32 thuần (`windows.h`, GDI+, `WinMain`, `WIN32_FIND_DATA`). Không thể `clang` trực tiếp trên macOS.
- `macos/` là lớp GUI mới viết bằng **Objective-C++ (ARC) + AppKit**, tái sử dụng logic OCR:
  - `ViewerView.mm` — hiển thị ảnh (aspect fit) + kéo chọn vùng OCR (tương đương `viv.c` `_viv_ocr_*`)
  - `ViewerWindow.mm` — `NSWindow` + `NSSplitView` (ảnh trái, OCR panel phải 320px như bản Windows)
  - `OCRPanel.mm` — panel phải với `NSTextView` + Copy/Clear (như `ocr_panel.c`)
  - `OCRBridge.mm` — chuyển `NSImage` -> `Pix` (Leptonica) -> `TessBaseAPI` (Tesseract 5, `vie`), chạy async như `viv.c` `_viv_ocr_thread_proc`
  - `AppDelegate.mm` — `NSApplicationDelegate`, handle open file, drag & drop, command line
- `libwebp` — dùng luôn submodule kèm repo, build static bằng Apple Clang qua CMake.
- `tesseract`/`leptonica` — lấy từ `brew` (`/opt/homebrew` hoặc `/usr/local`), link dynamic.

## Yêu cầu
```bash
xcode-select --install
brew install cmake tesseract leptonica pkg-config
# optional:
brew install create-dmg
```

## Build
```bash
# Native (khuyến nghị)
./build_macos.sh --native
# hoặc trực tiếp cmake:
cmake -B build/macos -DCMAKE_BUILD_TYPE=Release
cmake --build build/macos -j$(sysctl -n hw.ncpu)
open build/macos/RapidOCRViewer.app  # hoặc build/macos/Release/RapidOCRViewer.app (Xcode generator)

# Mock OCR (không cần tesseract)
./build_macos.sh --native --mock
cmake -B build/macos -DWITH_TESSERACT=OFF

# Chọn arch
./build_macos.sh --native --arch arm64        # Apple Silicon
./build_macos.sh --native --arch x86_64       # Intel
./build_macos.sh --native --arch universal    # universal2

# Cross Windows exe (cũ, MinGW)
./build_macos.sh --cross
```

## Output
- `build/macos/RapidOCRViewer.app` — app native
- `dist/RapidOCRViewer-<ver>-macOS.zip` — zip app (ditto)
- `dist/RapidOCRViewer-<ver>-macOS.dmg` — DMG kéo thả

## Chạy
- Mở ảnh: `⌘O`, kéo thả file vào window, hoặc `open RapidOCRViewer.app --args /path/to/image.jpg`
- OCR: kéo vùng chữ trên ảnh → thả → panel phải hiện `Recognizing…` → kết quả (vie). `Copy` để copy, `Clear` để xóa.
- Đổi ảnh → panel tự xóa (như bản Windows).

## So sánh với bản Windows
- Bản Windows: `viv.c` 15k dòng, GDI/GDI+, Win32 message loop, registry, NSIS installer.
- Bản macOS: AppKit, ARC, không có registry, không cần NSIS. Tính năng viewer/OCR tương đương, thiếu một số dialog Options/registry associations đặc thù Windows.

## Troubleshooting
- `tessdata not found` → kiểm tra `build/macos/RapidOCRViewer.app/Contents/Resources/tessdata/vie.traineddata` hoặc `tessdata/vie.traineddata` cạnh repo.
- `Tesseract not compiled` → `brew install tesseract leptonica` rồi rebuild.
- `clang not found` → `xcode-select --install`
