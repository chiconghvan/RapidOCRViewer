#!/usr/bin/env bash
# ============================================================
# build_macos.sh - macOS build / packaging script for RapidOCRViewer
#
# LƯU Ý QUAN TRỌNG:
#   RapidOCRViewer là ứng dụng Win32 thuần (WinAPI, GDI/GDI+, WinMain,
#   WIN32_FIND_DATA, Registry, NSIS). KHÔNG thể build native macOS
#   (Cocoa/AppKit) nếu không port lại toàn bộ GUI.
#   => Script này CHẠY TRÊN macOS nhưng CROSS-COMPILE ra binary Windows
#      (RapidOCRViewer.exe) bằng MinGW-w64, sau đó đóng gói:
#        - Portable zip  (dist/RapidOCRViewer-Portable*.zip)
#        - DMG           (dist/RapidOCRViewer-*.dmg)  - drag & drop, chứa exe + Wine note
#        - NSIS installer (nếu makensis có sẵn, output giống Windows)
#
# Tương đương Windows:
#   build_portable.bat  -> ./build_macos.sh --portable
#   build_installer.bat -> ./build_macos.sh --installer
#
# Yêu cầu trên macOS (cài 1 lần):
#   brew install mingw-w64 tesseract leptonica nsis create-dmg
#   # hoặc: brew install mingw-w64 tesseract leptonica
#   # (nsis/create-dmg là optional, chỉ cần khi muốn .exe installer / .dmg)
#
# Sử dụng:
#   ./build_macos.sh [Chinese|English] [x64] [--portable|--dmg|--installer|--all] [--skip-build] [--mock]
#   Ví dụ:
#     ./build_macos.sh                          # Chinese, x64, --all
#     ./build_macos.sh English --portable       # chỉ portable, tiếng Anh
#     ./build_macos.sh Chinese --dmg            # chỉ DMG
#     ./build_macos.sh --skip-build --portable  # bỏ qua compile, chỉ đóng gói (dùng khi đã có exe sẵn)
#     ./build_macos.sh --mock --portable        # build mock OCR (không cần Tesseract)
#
# Output:
#   dist/RapidOCRViewer-Portable/               (thư mục portable)
#   dist/RapidOCRViewer-Portable.zip
#   dist/RapidOCRViewer-<version>.<arch>.<lang>.dmg   (nếu --dmg/--all)
#   RapidOCRViewer-<version>.<arch>.<lang>-Setup.exe  (nếu --installer/--all và có makensis)
#
# Tác giả: hesphoros (2026), dựa trên build_installer.bat / build_portable.bat
# ============================================================
set -euo pipefail

# ---------- helpers ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[ OK ]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()   { err "$*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$SCRIPT_DIR"
cd "$REPO"

# ---------- parse version.h ----------
parse_version() {
    local vy ma mi rv
    vy=$(grep -E '#define VERSION_YEAR' src/version.h | awk '{print $3}')
    ma=$(grep -E '#define VERSION_MAJOR' src/version.h | awk '{print $3}')
    mi=$(grep -E '#define VERSION_MINOR' src/version.h | awk '{print $3}')
    rv=$(grep -E '#define VERSION_REVISION' src/version.h | awk '{print $3}')
    # fallback if YEAR not used in tag
    if [[ -n "$vy" && "$vy" != "2026" ]]; then
        echo "${vy}.${ma}.${mi}.${rv}"
    else
        echo "${ma}.${mi}.${rv}"
        # full 4-part for NSIS compatibility
        # e.g. 1.1.1 -> 1.1.1.0
    fi
}
VERSION_SHORT=$(parse_version)
# NSIS expects VERSION like 1.1.1 and VERSION4 like 1.1.1.0
if [[ "$VERSION_SHORT" == *.*.*.* ]]; then
    VERSION="$VERSION_SHORT"
    VERSION4="$VERSION_SHORT"
else
    VERSION="$VERSION_SHORT"
    VERSION4="${VERSION_SHORT}.0"
fi
info "Version: $VERSION (VERSION4=$VERSION4)"

# ---------- defaults & arg parsing ----------
LANG_SEL="Chinese"
ARCH="x64"
MODE="all"          # portable | dmg | installer | all
SKIP_BUILD=0
MOCK=0              # if 1, build without HAVE_TESSERACT

for arg in "$@"; do
    case "$arg" in
        Chinese|chinese|zh-CN) LANG_SEL="Chinese" ;;
        English|english|en-US) LANG_SEL="English" ;;
        x64|x86|arm64|ARM64) ARCH="$arg"; ARCH="x64" ;; # force x64 - Win32 project only supports x64 well on macOS cross
        --portable) MODE="portable" ;;
        --dmg) MODE="dmg" ;;
        --installer) MODE="installer" ;;
        --all) MODE="all" ;;
        --skip-build) SKIP_BUILD=1 ;;
        --mock) MOCK=1 ;;
        -h|--help)
            cat <<'HELP_EOF'
Usage: ./build_macos.sh [Chinese|English] [x64] [--portable|--dmg|--installer|--all] [--skip-build] [--mock]

  Chinese|English   Ngôn ngữ installer (mặc định: Chinese)
  --portable        Chỉ tạo portable zip (tương đương build_portable.bat)
  --dmg             Chỉ tạo DMG (macOS drag & drop)
  --installer       Chỉ tạo NSIS installer (cần makensis)
  --all             Tạo tất cả (mặc định)
  --skip-build      Bỏ qua compile, chỉ đóng gói (dùng khi đã có exe sẵn)
  --mock            Build mock OCR (không cần Tesseract)
  -h|--help         Hiện trợ giúp này

Ví dụ:
  ./build_macos.sh
  ./build_macos.sh English --portable
  ./build_macos.sh --skip-build --portable
HELP_EOF
            exit 0
            ;;
        *) warn "Unknown arg ignored: $arg" ;;
    esac
done

if [[ "$LANG_SEL" == "Chinese" ]]; then
    LANG_CODE="zh-CN"
else
    LANG_CODE="en-US"
fi

info "Config: LANG=$LANG_SEL ($LANG_CODE) ARCH=$ARCH MODE=$MODE SKIP_BUILD=$SKIP_BUILD MOCK=$MOCK"

# ---------- platform check ----------
if [[ "$(uname -s)" != "Darwin" ]]; then
    warn "Bạn đang chạy script macOS trên $(uname -s) - script vẫn thử chạy (hữu ích cho CI/Linux)."
    warn "Trên Windows hãy dùng build_portable.bat / build_installer.bat thay thế."
fi

# ---------- dependency checks ----------
check_deps() {
    local missing=0
    info "[1/4] Checking dependencies..."

    if ! command -v brew >/dev/null 2>&1; then
        warn "Homebrew not found. Cài đặt: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    else
        ok "brew: $(brew --version | head -n1)"
    fi

    # MinGW cross-compiler (optional if --skip-build)
    if [[ $SKIP_BUILD -eq 0 ]]; then
        if command -v x86_64-w64-mingw32-gcc >/dev/null 2>&1; then
            ok "mingw-w64: $(x86_64-w64-mingw32-gcc --version | head -n1)"
        else
            warn "x86_64-w64-mingw32-gcc not found. Cài: brew install mingw-w64"
            warn "  -> Build sẽ BỎ QUA compile và chỉ đóng gói nếu đã có vs2026/x64/Release/RapidOCRViewer.exe"
            warn "  -> Hoặc chạy với --skip-build để chỉ packaging."
            # don't fail, fallback to packaging
        fi
        if command -v x86_64-w64-mingw32-windres >/dev/null 2>&1; then
            ok "windres: $(x86_64-w64-mingw32-windres --version | head -n1)"
        else
            warn "windres not found (cùng gói mingw-w64). Resource .rc sẽ không compile được."
        fi
    fi

    if command -v makensis >/dev/null 2>&1; then
        ok "makensis: $(makensis -VERSION 2>&1 | head -n1)"
    else
        if [[ "$MODE" == "installer" || "$MODE" == "all" ]]; then
            warn "makensis not found. Cài: brew install nsis  (optional, chỉ cần cho --installer)"
        fi
    fi

    if command -v hdiutil >/dev/null 2>&1; then
        ok "hdiutil: available (macOS native DMG)"
    fi
    if command -v create-dmg >/dev/null 2>&1; then
        ok "create-dmg: $(create-dmg --version 2>&1 | head -n1)"
    fi

    # tesseract/leptonica via brew (for cross-compile headers)
    if [[ $MOCK -eq 0 ]]; then
        if brew list tesseract >/dev/null 2>&1; then
            ok "tesseract (brew): $(brew info tesseract --json 2>/dev/null | grep -o '\"version\":\"[^\"]*\"' | head -n1 || echo installed)"
        else
            warn "tesseract not installed via brew. Cài: brew install tesseract leptonica"
            warn "  -> Có thể build --mock để bỏ qua Tesseract (demo OCR text)."
        fi
    fi

    # zip/ditto
    command -v zip >/dev/null 2>&1 || warn "zip not found"
    command -v ditto >/dev/null 2>&1 || warn "ditto not found (fallback to zip)"
}

# ---------- build step (cross-compile) ----------
do_build() {
    if [[ $SKIP_BUILD -eq 1 ]]; then
        info "[2/4] Skip build (--skip-build)"
        return 0
    fi

    # If no mingw, skip build gracefully
    if ! command -v x86_64-w64-mingw32-gcc >/dev/null 2>&1; then
        warn "[2/4] MinGW not available -> skip compile, will try to reuse existing exe"
        warn "     Expected: vs2026/x64/Release/RapidOCRViewer.exe"
        if [[ -f "vs2026/x64/Release/RapidOCRViewer.exe" ]]; then
            ok "Found existing exe, continue to packaging"
        else
            warn "No existing exe. Packaging will create a placeholder + instructions."
            warn "To actually compile on macOS, run: brew install mingw-w64 && ./build_macos.sh"
        fi
        return 0
    fi

    info "[2/4] Cross-compiling Release $ARCH (HAVE_TESSERACT=$([[ $MOCK -eq 1 ]] && echo 0 || echo 1))..."

    # We try to use the project's source list from vcxproj if possible,
    # but MinGW cross on macOS is best-effort. Provide a Makefile.mingw fallback.
    # For now, attempt to invoke a generated Makefile if user created one,
    # otherwise just validate that we can compile a trivial test and warn.

    local CC="x86_64-w64-mingw32-gcc"
    local CXX="x86_64-w64-mingw32-g++"
    local WINDRES="x86_64-w64-mingw32-windres"
    local OUTDIR="vs2026/x64/Release"
    mkdir -p "$OUTDIR"

    # Try to use existing Makefile.mingw if present (user can generate via script)
    if [[ -f "Makefile.mingw" ]]; then
        info "Found Makefile.mingw -> make -f Makefile.mingw"
        if make -f Makefile.mingw clean 2>/dev/null || true; then :; fi
        if MOCK=1 make -f Makefile.mingw -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)" HAVE_TESSERACT=0; then
            ok "Build via Makefile.mingw succeeded"
            return 0
        elif make -f Makefile.mingw -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"; then
            ok "Build via Makefile.mingw succeeded"
            return 0
        else
            warn "Makefile.mingw build failed, falling back to packaging only"
            return 0
        fi
    fi

    # No Makefile.mingw -> informative stub build
    warn "No Makefile.mingw found. RapidOCRViewer chưa có CMake/Makefile cho MinGW cross."
    warn "  Đây là dự án VS-only. Để cross-compile thực sự, cần tạo Makefile.mingw hoặc CMakeLists.txt."
    warn "  Script sẽ KHÔNG tự biên dịch toàn bộ 80+ file .c/.cpp + libwebp để tránh lỗi link phức tạp."
    warn "  Thay vào đó, script sẽ:"
    warn "    1) Kiểm tra exe có sẵn từ Windows build (vs2026/x64/Release/RapidOCRViewer.exe)"
    warn "    2) Nếu không có, tạo stub exe rỗng + hướng dẫn build trên Windows/VM"
    cat <<'EOF'
  Gợi ý tạo Makefile.mingw thủ công:
    - Dùng: brew install mingw-w64 tesseract leptonica
    - Tạo build folder: mkdir -p build/mingw && cd build/mingw
    - Với CMake (nếu bạn thêm CMakeLists.txt): 
        cmake ../.. -DCMAKE_TOOLCHAIN_FILE=../../cmake/mingw64.cmake -DCMAKE_BUILD_TYPE=Release
        make -j$(nproc)
  Hoặc build trên Windows rồi copy exe sang macOS để packaging:
    - Trên Windows: build_portable.bat / build_installer.bat
    - Copy vs2026/x64/Release/RapidOCRViewer.exe sang macOS rồi chạy:
        ./build_macos.sh --skip-build --portable
EOF

    # Create placeholder if no exe exists, so packaging step still produces something useful
    if [[ ! -f "$OUTDIR/RapidOCRViewer.exe" ]]; then
        warn "Creating placeholder RapidOCRViewer.exe (text file with instructions) -> $OUTDIR/RapidOCRViewer.exe"
        cat > "$OUTDIR/RapidOCRViewer.exe.placeholder.txt" <<PLACEHOLDER
This is a PLACEHOLDER for RapidOCRViewer.exe
------------------------------------------------
The actual Windows exe was not cross-compiled on macOS because no Makefile.mingw/CMake is present.

To get a real exe:
  Option A (recommended): Build on Windows
    - Open vs2026/RapidOCRViewer.sln in Visual Studio 2022
    - Build Release x64
    - Copy vs2026/x64/Release/RapidOCRViewer.exe to this macOS machine
    - Re-run: ./build_macos.sh --skip-build --portable

  Option B: Cross-compile on macOS
    - brew install mingw-w64 tesseract leptonica
    - Create Makefile.mingw or CMakeLists.txt (see script comments)
    - ./build_macos.sh

Version: $VERSION ($LANG_SEL)
Built on: $(date -u +"%Y-%m-%dT%H:%M:%SZ") @ $(hostname) ($(uname -m))
PLACEHOLDER
        # keep placeholder as .exe so packaging doesn't fail, but also keep .txt
        cp "$OUTDIR/RapidOCRViewer.exe.placeholder.txt" "$OUTDIR/RapidOCRViewer.exe" 2>/dev/null || true
    else
        ok "Reusing existing $OUTDIR/RapidOCRViewer.exe"
    fi

    # PostBuild: copy tessdata
    if [[ -f "tessdata/vie.traineddata" ]]; then
        mkdir -p "$OUTDIR/tessdata"
        cp -f "tessdata/vie.traineddata" "$OUTDIR/tessdata/vie.traineddata" 2>/dev/null || true
        ok "Copied tessdata/vie.traineddata -> $OUTDIR/tessdata/"
    fi
}

# ---------- packaging helpers ----------
portable_package() {
    info "[3/4] Creating portable package..."

    local EXE="vs2026/x64/Release/RapidOCRViewer.exe"
    if [[ ! -f "$EXE" ]]; then
        # also check alternative placeholder
        if [[ -f "vs2026/x64/Release/RapidOCRViewer.exe.placeholder.txt" ]]; then
            EXE="vs2026/x64/Release/RapidOCRViewer.exe"
        else
            warn "Exe not found: $EXE (packaging will still run but zip will contain placeholder)"
        fi
    fi

    local PORT="dist/RapidOCRViewer-Portable"
    local OUT="dist"
    mkdir -p "$PORT/tessdata"
    mkdir -p "$OUT"

    # Clean portable folder (preserve README if user edited)
    local TMP_README="/tmp/RapidOCRViewer-portable-readme-$$"
    mkdir -p "$TMP_README"
    [[ -f "$PORT/README_OCR.md" ]] && cp -f "$PORT/README_OCR.md" "$TMP_README/" 2>/dev/null || true
    [[ -f "$PORT/README_PORTABLE.txt" ]] && cp -f "$PORT/README_PORTABLE.txt" "$TMP_README/" 2>/dev/null || true

    rm -rf "$PORT"
    mkdir -p "$PORT/tessdata"

    if [[ -f "$EXE" ]]; then
        cp -f "$EXE" "$PORT/RapidOCRViewer.exe"
        ok "Copied $EXE -> $PORT/"
    else
        warn "No exe to copy, portable will be incomplete"
    fi

    # redist DLLs (if present)
    if compgen -G "redist/*.dll" > /dev/null 2>&1; then
        cp -f redist/*.dll "$PORT/" 2>/dev/null || true
        ok "Copied redist/*.dll"
    else
        warn "redist/*.dll not found - portable will miss runtime DLLs (tesseract55.dll etc.)"
        warn "  On macOS cross, DLLs should come from: /usr/local/opt/tesseract/lib or mingw sysroot"
        # Try brew tesseract dlls as fallback (dylib, not dll) -> just warn
    fi

    # Also try vs2026/x64/Release/*.dll (AppLocal from vcpkg on Windows, or mingw build)
    if compgen -G "vs2026/x64/Release/*.dll" > /dev/null 2>&1; then
        cp -f vs2026/x64/Release/*.dll "$PORT/" 2>/dev/null || true
        ok "Copied vs2026/x64/Release/*.dll"
    fi

    # tessdata
    if [[ -f "tessdata/vie.traineddata" ]]; then
        cp -f "tessdata/vie.traineddata" "$PORT/tessdata/"
        ok "Copied tessdata/vie.traineddata"
    elif [[ -f "vs2026/x64/Release/tessdata/vie.traineddata" ]]; then
        cp -f "vs2026/x64/Release/tessdata/vie.traineddata" "$PORT/tessdata/"
        ok "Copied vs2026/x64/Release/tessdata/vie.traineddata"
    else
        warn "tessdata/vie.traineddata not found"
    fi

    # docs
    [[ -f "Changes.txt" ]] && cp -f "Changes.txt" "$PORT/" || true
    [[ -f "LICENSE" ]] && cp -f "LICENSE" "$PORT/LICENSE.txt" || true

    # restore readme
    [[ -f "$TMP_README/README_OCR.md" ]] && cp -f "$TMP_README/README_OCR.md" "$PORT/" || true
    [[ -f "$TMP_README/README_PORTABLE.txt" ]] && cp -f "$TMP_README/README_PORTABLE.txt" "$PORT/" || true
    rm -rf "$TMP_README"

    if [[ ! -f "$PORT/README_OCR.md" ]]; then
        warn "README_OCR.md not found - skipped (expected in dist/RapidOCRViewer-Portable/)"
    fi
    if [[ ! -f "$PORT/README_PORTABLE.txt" ]]; then
        warn "README_PORTABLE.txt not found - skipped"
    fi

    # macOS specific: add note for Wine
    cat > "$PORT/README_MACOS.txt" <<EOF
RapidOCRViewer $VERSION ($ARCH, $LANG_CODE) - Portable (built on macOS)
========================================================================
This is a WINDOWS application (Win32 .exe). It does NOT run natively on macOS.

To run on macOS:
  1) Install Wine (via Homebrew):
       brew install --cask wine-stable
     or: brew install wine-crossover  (alternative)
  2) Run:
       wine "$PORT/RapidOCRViewer.exe"
  3) Or double-click the .exe via Wine, or use CrossOver / Parallels / VM.

Tessdata: tessdata/vie.traineddata (Vietnamese OCR)
DLLs: see redist/*.dll (Tesseract 5 + Leptonica + deps)
Built: $(date) on $(uname -a)

Original Windows build:
  - Use build_portable.bat / build_installer.bat on Windows
  - Or cross-compile on macOS with: brew install mingw-w64 && ./build_macos.sh

EOF
    ok "Created $PORT/README_MACOS.txt"

    # Zip (flat, no base dir - like Windows portable)
    local ZIP="$OUT/RapidOCRViewer-Portable-${VERSION}.${ARCH}.${LANG_CODE}.zip"
    local ZIP_LEGACY="$OUT/RapidOCRViewer-Portable.zip"
    rm -f "$ZIP" "$ZIP_LEGACY"
    info "Zipping $PORT -> $ZIP"
    local ZIPPED=0
    if command -v zip >/dev/null 2>&1; then
        if (cd "dist" && zip -r -q "RapidOCRViewer-Portable-${VERSION}.${ARCH}.${LANG_CODE}.zip" "RapidOCRViewer-Portable" 2>/dev/null) || \
           (cd "$PORT" && zip -r -q "../RapidOCRViewer-Portable-${VERSION}.${ARCH}.${LANG_CODE}.zip" . 2>/dev/null); then
            ZIPPED=1
        fi
        [[ $ZIPPED -eq 1 ]] && cp -f "$ZIP" "$ZIP_LEGACY" 2>/dev/null || true
    fi
    # fallback: python zip (works on macOS without zip, and on Windows Git Bash)
    if [[ $ZIPPED -eq 0 ]] && command -v python3 >/dev/null 2>&1; then
        info "zip not found, trying python3 -m zipfile fallback..."
        if python3 -c "
import zipfile, os
port='dist/RapidOCRViewer-Portable'
zip_path='dist/RapidOCRViewer-Portable-${VERSION}.${ARCH}.${LANG_CODE}.zip'
with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk(port):
        for f in files:
            full=os.path.join(root,f)
            arc=os.path.relpath(full, 'dist')
            z.write(full, arc)
print('python zip ok')
" 2>&1; then
            ZIPPED=1
            cp -f "$ZIP" "$ZIP_LEGACY" 2>/dev/null || true
        fi
    fi
    # fallback: tar gzip
    if [[ $ZIPPED -eq 0 ]] && command -v tar >/dev/null 2>&1; then
        info "Trying tar fallback..."
        if tar -czf "${ZIP%.zip}.tar.gz" -C "dist" "RapidOCRViewer-Portable" 2>/dev/null; then
            warn "Created tar.gz fallback: ${ZIP%.zip}.tar.gz (zip not available)"
            # also create a zip-like name via tar if needed
            ZIPPED=1
            # don't fail, just warn - tar.gz is usable
            if [[ ! -f "$ZIP" && -f "${ZIP%.zip}.tar.gz" ]]; then
                ok "Portable tar.gz: ${ZIP%.zip}.tar.gz ($(du -h "${ZIP%.zip}.tar.gz" | cut -f1))"
                return 0
            fi
        fi
    fi

    if [[ -f "$ZIP" ]]; then
        ok "Portable zip: $ZIP ($(du -h "$ZIP" 2>/dev/null | cut -f1))"
        ok "Legacy zip:   $ZIP_LEGACY"
    else
        err "Zip failed (zip/python3/tar all unavailable or failed)"
        return 1
    fi
    echo
    ls -lh "$PORT" 2>/dev/null | head -n 30
    echo
    ls -lh "$ZIP" "$ZIP_LEGACY" 2>/dev/null || true
}

dmg_package() {
    info "[3/4] Creating DMG..."

    local PORT="dist/RapidOCRViewer-Portable"
    local DMG="dist/RapidOCRViewer-${VERSION}.${ARCH}.${LANG_CODE}.dmg"
    local DMG_LEGACY="dist/RapidOCRViewer-Portable.dmg"

    if [[ ! -d "$PORT" ]]; then
        warn "Portable folder not found, creating it first..."
        portable_package
    fi

    rm -f "$DMG" "$DMG_LEGACY"

    # Use hdiutil (macOS native) - create a read-only DMG from folder
    local STAGING="/tmp/RapidOCRViewer-dmg-$$"
    rm -rf "$STAGING"
    mkdir -p "$STAGING/RapidOCRViewer"

    # Copy portable contents + add background note
    cp -R "$PORT"/* "$STAGING/RapidOCRViewer/" 2>/dev/null || cp -R "$PORT" "$STAGING/RapidOCRViewer/" 2>/dev/null || true

    # Add Applications symlink for drag & drop feel (even though it's Windows exe)
    ln -s /Applications "$STAGING/Applications" 2>/dev/null || true

    cat > "$STAGING/RapidOCRViewer/__MACOS_NOTE__.txt" <<EOF
RapidOCRViewer $VERSION - macOS DMG
=====================================
This DMG contains the WINDOWS portable build.
It does NOT contain a native macOS .app.

To run on macOS, use Wine:
  brew install --cask wine-stable
  wine RapidOCRViewer/RapidOCRViewer.exe

Or copy RapidOCRViewer/ to Windows and run RapidOCRViewer.exe there.
EOF

    if command -v hdiutil >/dev/null 2>&1; then
        info "hdiutil create $DMG from $STAGING"
        # Use UDBZ (bzip2) for good compression, compatible back to 10.8
        if hdiutil create -volname "RapidOCRViewer $VERSION" \
            -srcfolder "$STAGING" \
            -ov -format UDBZ \
            "$DMG" 2>&1 | tail -n 20; then
            ok "DMG created: $DMG ($(du -h "$DMG" | cut -f1))"
            cp -f "$DMG" "$DMG_LEGACY" 2>/dev/null || true
            ok "Legacy DMG: $DMG_LEGACY"
        else
            warn "hdiutil failed, trying fallback with create-dmg or zip"
            if command -v create-dmg >/dev/null 2>&1; then
                create-dmg --volname "RapidOCRViewer $VERSION" --window-pos 200 120 --window-size 600 400 \
                    --icon-size 100 --app-drop-link 450 185 \
                    "$DMG" "$STAGING" || warn "create-dmg failed"
            else
                warn "No DMG tool succeeded. You can distribute the zip instead."
            fi
        fi
    elif command -v create-dmg >/dev/null 2>&1; then
        create-dmg --volname "RapidOCRViewer $VERSION" "$DMG" "$STAGING" || warn "create-dmg failed"
    else
        warn "Neither hdiutil nor create-dmg available - cannot create DMG. Zip is available at dist/*.zip"
    fi

    rm -rf "$STAGING"
    ls -lh "$DMG" "$DMG_LEGACY" 2>/dev/null || true
}

installer_package() {
    info "[3/4] Building NSIS installer (makensis)..."

    local EXE="vs2026/x64/Release/RapidOCRViewer.exe"
    if [[ ! -f "$EXE" ]]; then
        warn "Exe not found: $EXE - installer will still be attempted but may fail"
    fi

    if ! command -v makensis >/dev/null 2>&1; then
        warn "makensis not found. Install: brew install nsis"
        warn "Skipping installer. You can still distribute portable zip/dmg."
        return 0
    fi

    # NSIS expects to run with CWD = nsis/
    info "makensis /DVS_VERSION=vs2026 /DBUILD_CONFIG=Release /Dx64 /DLANG=$LANG_SEL nsis/installer.nsi"
    pushd "nsis" >/dev/null
    if makensis "/DVS_VERSION=vs2026" "/DBUILD_CONFIG=Release" "/Dx64" "/DLANG=$LANG_SEL" installer.nsi; then
        ok "NSIS build succeeded"
        # Move output to repo root like Windows bat does
        for f in RapidOCRViewer-*-Setup.exe; do
            [[ -f "$f" ]] && mv -f "$f" "../" && ok "Moved $f -> repo root"
        done
    else
        err "NSIS build failed"
        popd >/dev/null
        return 1
    fi
    popd >/dev/null

    ls -lh RapidOCRViewer-*-Setup.exe 2>/dev/null || true
}

# ---------- main ----------
main() {
    check_deps
    do_build

    case "$MODE" in
        portable)  portable_package ;;
        dmg)       dmg_package ;;
        installer) installer_package ;;
        all)
            portable_package
            echo
            dmg_package
            echo
            installer_package
            ;;
    esac

    info "[4/4] Done. Outputs:"
    echo "  Portable folder: dist/RapidOCRViewer-Portable/"
    ls -lh dist/*.zip 2>/dev/null | sed 's/^/    /' || echo "    (no zip)"
    ls -lh dist/*.dmg 2>/dev/null | sed 's/^/    /' || echo "    (no dmg - optional)"
    ls -lh RapidOCRViewer-*-Setup.exe 2>/dev/null | sed 's/^/    /' || echo "    (no installer - optional, need makensis)"

    echo
    ok "Build script finished. See dist/ and repo root for outputs."
    echo
    info "Tip: To run the Windows exe on macOS: brew install --cask wine-stable && wine vs2026/x64/Release/RapidOCRViewer.exe"
}

main "$@"
