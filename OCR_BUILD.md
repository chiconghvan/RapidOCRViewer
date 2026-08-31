# Fast OCR Integration – Build & Packaging Guide

## Tổng quan
- **Chế độ Fast OCR** được tích hợp trực tiếp vào viewer (không gọi `tesseract.exe`).
- Kích hoạt: `View → Fast OCR` hoặc `Ctrl+Shift+O` (check mark).
- Khi bật: con trỏ `crosshair`, kéo vẽ bounding box trên vùng ảnh → crop từ `HBITMAP` đã decode → chạy Tesseract 5 (vie) bất đồng bộ → tự động hiện **panel phải 320px** với `Edit` đa dòng + nút **Copy/Clear**.
- Đổi ảnh (Next/Prev/Home) sẽ **tự xóa** panel để vẽ lại liên tục (theo yêu cầu).
- `ESC` thoát Fast OCR hoặc hủy thao tác vẽ.

## Kiến trúc
- `src/ocr_engine.h/.cpp` – wrapper `TessBaseAPI` + Leptonica `PIX`. Nếu không có `HAVE_TESSERACT`, build mock (demo text) để vẫn kiểm thử UI/Copy.
- `src/ocr_panel.h/.c` – child window `STATIC` chứa `EDIT` + 2 `BUTTON`, layout trong `_viv_on_size`, vẽ nền `COLOR_BTNFACE`.
- `src/viv.c` – thêm state `_viv_ocr_mode/_viv_doing_OCR_SELECT`, helpers `_viv_ocr_get_image_area`, `client_to_src_rect`, overlay `DrawFocusRect`, thread `CreateThread(_viv_ocr_thread_proc)`.
- Tọa độ: `rx/ry/rw/rh` từ `_viv_get_render_size` (đã trừ panel width) → map `clientPt → srcPt` bằng `fx = imageW/rw`.
- Clipboard: `OpenClipboard/CF_UNICODETEXT`.
- Async: `PostMessage(WM_OCR_DONE/WM_OCR_ERROR)` về UI thread, hiển thị ngay “Recognizing…”.

## Build Windows 10/11 x64

### 1. Yêu cầu
- Visual Studio 2022 Build Tools 18+ (`MSBuild 18.8`, `MSVC 14.51`)
- Windows 10 SDK 10.0

### 2. Build với Tesseract thật (mặc định hiện tại, `HAVE_TESSERACT` đã bật sẵn trong vcxproj `Release|x64`)
Cài vcpkg:
```bat
git clone https://github.com/microsoft/vcpkg C:\vcpkg
C:\vcpkg\bootstrap-vcpkg.bat
C:\vcpkg\vcpkg integrate install
set VCPKG_ROOT=C:\vcpkg
C:\vcpkg\vcpkg install tesseract leptonica --triplet x64-windows
```
Build (không cần truyền thêm define — `HAVE_TESSERACT` đã nằm trong `vs2026\voidImageViewer.vcxproj`):
```bat
msbuild vs2026\voidImageViewer.vcxproj /p:Configuration=Release /p:Platform=x64
```
vcpkg tự link `tesseract55.lib` + `leptonica-1.87.0.lib` và dùng **AppLocal** copy toàn bộ DLL runtime cần thiết vào `$(OutDir)`.

Nếu muốn build mock OCR (demo text, không cần Tesseract), xóa `HAVE_TESSERACT` khỏi `PreprocessorDefinitions` trong vcxproj rồi build lại.

### 3. Runtime DLLs (`redist\`)
- Sau khi build với Tesseract thật, exe import `tesseract55.dll` + `leptonica-1.87.0.dll` (+ 18 DLL phụ thuộc).
- Các DLL đã được thu thập vào **`redist\`** trong repo (20 file: `tesseract55.dll`, `leptonica-1.87.0.dll`, `archive`, `bz2`, `gif`, `jpeg62`, `libcurl`, `liblzma`, `libpng16`, `libsharpyuv`, `libwebp`, `libwebpmux`, `lz4`, `msvcp140`, `openjp2`, `tiff`, `vcruntime140`, `vcruntime140_1`, `z`, `zstd`).
- Cập nhật lại nếu đổi version vcpkg: copy từ `C:\vcpkg\installed\x64-windows\bin\*.dll` (+ `vcruntime140*.dll`, `msvcp140.dll` từ `VC\Redist\MSVC\*\x64\Microsoft.VC*.CRT\`).

### 4. tessdata
- File `tessdata\vie.traineddata` (~7.7 MB, tessdata chuẩn) đã được đặt sẵn trong repo.
- PostBuild `xcopy` sẽ copy vào `$(OutDir)tessdata\vie.traineddata`.
- Runtime `ocr_init` thử `exeDir\tessdata` rồi `exeDir` fallback.

### 5. Portable (onedir)
- Copy vào `dist\RapidOCRViewer-Portable\`:
  - `vs2026\x64\Release\voidImageViewer.exe` → đổi tên `RapidOCRViewer.exe`
  - `redist\*.dll` (cùng thư mục exe)
  - `tessdata\vie.traineddata`, `Changes.txt`, `LICENSE.txt`, `README_OCR.md`, `README_PORTABLE.txt`
- Zip toàn bộ thành `RapidOCRViewer-Portable.zip`.

### 6. Installer (NSIS)
```bat
makensis /DVS_VERSION=vs2026 /DBUILD_CONFIG=Release /Dx64 nsis\installer.nsi
```
Sẽ đóng gói `voidImageViewer.exe` + `tessdata\vie.traineddata` + toàn bộ `redist\*.dll`. Khi cài, app tự copy DLL vào `$INSTDIR`; Uninstall xóa cả DLL và tessdata qua `_viv_process_install_command_line_options`.

## Kiểm thử nhanh
1. Mở ảnh JPG/PNG chứa tiếng Việt.
2. `Ctrl+Shift+O` → panel hiện (nếu đã có kết quả cũ thì hiển thị placeholder).
3. Kéo vẽ vùng chữ → thả → panel hiện “Recognizing…” → kết quả sau ~0.3-1s (mock: demo text, real: text Việt).
4. Edit text trong panel, bấm **Copy** → paste vào Notepad kiểm tra clipboard Unicode.
5. Bấm `Next`/`Prev` → panel tự xóa.
6. `ESC` thoát Fast OCR.

## Lưu ý hiệu năng
- Crop trực tiếp từ `HBITMAP` qua `GetDIBits` → `Pix`, không ghi file tạm.
- `TessBaseAPI` khởi tạo một lần, giữ sống suốt session (~30 MB).
- `PSM_SINGLE_BLOCK` cho vùng crop → nhanh hơn `PSM_AUTO`.
- Thread riêng, UI không block.

## Troubleshooting
- `Tess Init failed` → kiểm tra `tessdata\vie.traineddata` cạnh exe.
- Build error `STL1003` → `ocr_engine.cpp` phải compile as C++ (`CompileAsCpp`), đã fix trong `vs2026\voidImageViewer.vcxproj: <CompileAs>CompileAsCpp</CompileAs>`.
- Resource `IDC_...` missing → đã bổ sung trong `res\resource.h`.
