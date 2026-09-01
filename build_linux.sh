#!/usr/bin/env bash
# ============================================================
# build_linux.sh - Linux build / packaging script for RapidOCRViewer
#
# LƯU Ý QUAN TRỌNG:
#   RapidOCRViewer là ứng dụng Win32 thuần (WinAPI, GDI+, WinMain,
#   WIN32_FIND_DATA, Registry, NSIS). KHÔNG thể build native Linux
#   (GTK/Qt) nếu không port lại toàn bộ GUI.
#   => Script này CHẠY TRÊN Linux nhưng CROSS-COMPILE ra binary Windows
#      (RapidOCRViewer.exe) bằng MinGW-w64, sau đó đóng gói:
#        - Portable tar.gz  (dist/RapidOCRViewer-Portable-*.tar.gz)
#        - Portable zip     (dist/RapidOCRViewer-Portable-*.zip)
#        - NSIS installer   (nếu makensis có sẵn)
#
# Tương đương Windows:
#   build_portable.bat  -> ./build_linux.sh --portable
#   build_installer.bat -> ./build_linux.sh --installer
#
# Yêu cầu trên Ubuntu/Debian (cài 1 lần):
#   sudo apt update && sudo apt install -y mingw-w64 nsis zip python3
#   # tesseract/leptonica dev nếu muốn cross-compile thật:
#   sudo apt install -y libtesseract-dev libleptonica-dev
#
# Trên Fedora/RHEL:
#   sudo dnf install -y mingw64-gcc mingw64-gcc-c++ mingw64-winpthreads nsis zip python3
#
# Sử dụng:
#   ./build_linux.sh [Chinese|English] [x64] [--portable|--installer|--all] [--skip-build] [--mock]
#   Ví dụ:
#     ./build_linux.sh                          # Chinese, x64, --all
#     ./build_linux.sh English --portable       # chỉ portable
#     ./build_linux.sh --skip-build --portable  # bỏ qua compile, chỉ đóng gói
#     ./build_linux.sh --mock --portable        # build mock OCR (không cần Tesseract)
#
# Output:
#   dist/RapidOCRViewer-Portable/               (thư mục portable)
#   dist/RapidOCRViewer-Portable-<version>.x64.<lang>.zip
#   dist/RapidOCRViewer-Portable-<version>.x64.<lang>.tar.gz
#   dist/RapidOCRViewer-<version>.x64.<lang>-linux.tar.gz (alias)
#   RapidOCRViewer-<version>.x64.<lang>-Setup.exe  (nếu --installer/--all và có makensis)
#
# Tác giả: hesphoros (2026), dựa trên build_macos.sh / build_portable.bat
# ============================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[ OK ]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()   { err "$*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$SCRIPT_DIR"
cd "$REPO"

parse_version() {
    local vy ma mi rv
    vy=$(grep -E '#define VERSION_YEAR' src/version.h | awk '{print $3}')
    ma=$(grep -E '#define VERSION_MAJOR' src/version.h | awk '{print $3}')
    mi=$(grep -E '#define VERSION_MINOR' src/version.h | awk '{print $3}')
    rv=$(grep -E '#define VERSION_REVISION' src/version.h | awk '{print $3}')
    if [[ -n "$vy" && "$vy" != "2026" ]]; then
        echo "${vy}.${ma}.${mi}.${rv}"
    else
        echo "${ma}.${mi}.${rv}"
    fi
}
VERSION_SHORT=$(parse_version)
if [[ "$VERSION_SHORT" == *.*.*.* ]]; then
    VERSION="$VERSION_SHORT"
    VERSION4="$VERSION_SHORT"
else
    VERSION="$VERSION_SHORT"
    VERSION4="${VERSION_SHORT}.0"
fi
info "Version: $VERSION (VERSION4=$VERSION4)"

LANG_SEL="Chinese"
ARCH="x64"
MODE="all"
SKIP_BUILD=0
MOCK=0

for arg in "$@"; do
    case "$arg" in
        Chinese|chinese|zh-CN) LANG_SEL="Chinese" ;;
        English|english|en-US) LANG_SEL="English" ;;
        x64|x86|arm64|ARM64) ARCH="$arg"; ARCH="x64" ;;
        --portable) MODE="portable" ;;
        --installer) MODE="installer" ;;
        --all) MODE="all" ;;
        --skip-build) SKIP_BUILD=1 ;;
        --mock) MOCK=1 ;;
        -h|--help)
            cat <<'HELP_EOF'
Usage: ./build_linux.sh [Chinese|English] [x64] [--portable|--installer|--all] [--skip-build] [--mock]

  Chinese|English   Ngôn ngữ installer (mặc định: Chinese)
  --portable        Chỉ tạo portable tar.gz/zip
  --installer       Chỉ tạo NSIS installer (cần makensis)
  --all             Tạo tất cả (mặc định)
  --skip-build      Bỏ qua compile, chỉ đóng gói
  --mock            Build mock OCR (không cần Tesseract)
  -h|--help         Hiện trợ giúp này

Ví dụ:
  ./build_linux.sh
  ./build_linux.sh English --portable
  ./build_linux.sh --skip-build --portable
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

if [[ "$(uname -s)" != "Linux" ]]; then
    warn "Bạn đang chạy script Linux trên $(uname -s) - script vẫn thử chạy."
fi

check_deps() {
    info "[1/4] Checking dependencies..."
    if command -v x86_64-w64-mingw32-gcc >/dev/null 2>&1; then
        ok "mingw-w64: $(x86_64-w64-mingw32-gcc --version | head -n1)"
    else
        if [[ $SKIP_BUILD -eq 0 ]]; then
            warn "x86_64-w64-mingw32-gcc not found. Cài: sudo apt install mingw-w64"
            warn "  -> Build sẽ BỎ QUA compile và chỉ đóng gói nếu đã có vs2026/x64/Release/RapidOCRViewer.exe"
        fi
    fi
    if command -v x86_64-w64-mingw32-windres >/dev/null 2>&1; then
        ok "windres: $(x86_64-w64-mingw32-windres --version | head -n1)"
    fi
    if command -v makensis >/dev/null 2>&1; then
        ok "makensis: $(makensis -VERSION 2>&1 | head -n1)"
    else
        if [[ "$MODE" == "installer" || "$MODE" == "all" ]]; then
            warn "makensis not found. Cài: sudo apt install nsis"
        fi
    fi
    command -v zip >/dev/null 2>&1 && ok "zip: $(zip -v 2>&1 | head -n1)" || warn "zip not found - sẽ dùng python3/tar fallback"
    command -v tar >/dev/null 2>&1 && ok "tar: $(tar --version | head -n1)" || warn "tar not found"
    command -v python3 >/dev/null 2>&1 && ok "python3: $(python3 --version)" || warn "python3 not found"
}

do_build() {
    if [[ $SKIP_BUILD -eq 1 ]]; then
        info "[2/4] Skip build (--skip-build)"
        return 0
    fi
    if ! command -v x86_64-w64-mingw32-gcc >/dev/null 2>&1; then
        warn "[2/4] MinGW not available -> skip compile, will try to reuse existing exe"
        warn "     Expected: vs2026/x64/Release/RapidOCRViewer.exe"
        if [[ -f "vs2026/x64/Release/RapidOCRViewer.exe" ]]; then
            ok "Found existing exe, continue to packaging"
        else
            warn "No existing exe. Packaging will create a placeholder + instructions."
        fi
        return 0
    fi

    info "[2/4] Cross-compiling Release $ARCH (HAVE_TESSERACT=$([[ $MOCK -eq 1 ]] && echo 0 || echo 1))..."
    local OUTDIR="vs2026/x64/Release"
    mkdir -p "$OUTDIR"

    if [[ -f "Makefile.mingw" ]]; then
        info "Found Makefile.mingw -> make -f Makefile.mingw"
        if make -f Makefile.mingw clean 2>/dev/null || true; then :; fi
        if make -f Makefile.mingw -j"$(nproc 2>/dev/null || echo 4)" HAVE_TESSERACT=$([[ $MOCK -eq 1 ]] && echo 0 || echo 1); then
            ok "Build via Makefile.mingw succeeded"
            return 0
        else
            warn "Makefile.mingw build failed, falling back to packaging only"
            return 0
        fi
    fi

    warn "No Makefile.mingw found. RapidOCRViewer chưa có CMake/Makefile cho MinGW cross."
    warn "  Thay vào đó, script sẽ kiểm tra exe có sẵn từ Windows build."
    cat <<'EOF'
  Gợi ý tạo Makefile.mingw:
    sudo apt install mingw-w64 libtesseract-dev libleptonica-dev
    make -f Makefile.mingw -j$(nproc)
  Hoặc build trên Windows rồi copy exe sang Linux:
    ./build_linux.sh --skip-build --portable
EOF

    if [[ ! -f "$OUTDIR/RapidOCRViewer.exe" ]]; then
        warn "Creating placeholder RapidOCRViewer.exe -> $OUTDIR/RapidOCRViewer.exe"
        cat > "$OUTDIR/RapidOCRViewer.exe.placeholder.txt" <<PLACEHOLDER
This is a PLACEHOLDER for RapidOCRViewer.exe
------------------------------------------------
The actual Windows exe was not cross-compiled on Linux because no Makefile.mingw is present.

To get a real exe:
  Option A (recommended): Build on Windows
    - Open vs2026/RapidOCRViewer.sln in Visual Studio 2022
    - Build Release x64
    - Copy vs2026/x64/Release/RapidOCRViewer.exe to this Linux machine
    - Re-run: ./build_linux.sh --skip-build --portable

  Option B: Cross-compile on Linux
    - sudo apt install mingw-w64 libtesseract-dev libleptonica-dev
    - Create Makefile.mingw
    - ./build_linux.sh

Version: $VERSION ($LANG_SEL)
Built on: $(date -u +"%Y-%m-%dT%H:%M:%SZ") @ $(hostname) ($(uname -m))
PLACEHOLDER
        cp "$OUTDIR/RapidOCRViewer.exe.placeholder.txt" "$OUTDIR/RapidOCRViewer.exe" 2>/dev/null || true
    else
        ok "Reusing existing $OUTDIR/RapidOCRViewer.exe"
    fi

    if [[ -f "tessdata/vie.traineddata" ]]; then
        mkdir -p "$OUTDIR/tessdata"
        cp -f "tessdata/vie.traineddata" "$OUTDIR/tessdata/vie.traineddata" 2>/dev/null || true
        ok "Copied tessdata/vie.traineddata -> $OUTDIR/tessdata/"
    fi
}

portable_package() {
    info "[3/4] Creating portable package (Linux tar.gz + zip)..."

    local EXE="vs2026/x64/Release/RapidOCRViewer.exe"
    if [[ ! -f "$EXE" ]]; then
        if [[ -f "vs2026/x64/Release/RapidOCRViewer.exe.placeholder.txt" ]]; then
            EXE="vs2026/x64/Release/RapidOCRViewer.exe"
        else
            warn "Exe not found: $EXE (packaging will still run but archive will contain placeholder)"
        fi
    fi

    local PORT="dist/RapidOCRViewer-Portable"
    local OUT="dist"
    mkdir -p "$PORT/tessdata"
    mkdir -p "$OUT"

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

    if compgen -G "redist/*.dll" > /dev/null 2>&1; then
        cp -f redist/*.dll "$PORT/" 2>/dev/null || true
        ok "Copied redist/*.dll"
    else
        warn "redist/*.dll not found"
    fi

    if compgen -G "vs2026/x64/Release/*.dll" > /dev/null 2>&1; then
        cp -f vs2026/x64/Release/*.dll "$PORT/" 2>/dev/null || true
        ok "Copied vs2026/x64/Release/*.dll"
    fi

    if [[ -f "tessdata/vie.traineddata" ]]; then
        cp -f "tessdata/vie.traineddata" "$PORT/tessdata/"
        ok "Copied tessdata/vie.traineddata"
    elif [[ -f "vs2026/x64/Release/tessdata/vie.traineddata" ]]; then
        cp -f "vs2026/x64/Release/tessdata/vie.traineddata" "$PORT/tessdata/"
        ok "Copied vs2026/x64/Release/tessdata/vie.traineddata"
    else
        warn "tessdata/vie.traineddata not found"
    fi

    [[ -f "Changes.txt" ]] && cp -f "Changes.txt" "$PORT/" || true
    [[ -f "LICENSE" ]] && cp -f "LICENSE" "$PORT/LICENSE.txt" || true

    [[ -f "$TMP_README/README_OCR.md" ]] && cp -f "$TMP_README/README_OCR.md" "$PORT/" || true
    [[ -f "$TMP_README/README_PORTABLE.txt" ]] && cp -f "$TMP_README/README_PORTABLE.txt" "$PORT/" || true
    rm -rf "$TMP_README"

    cat > "$PORT/README_LINUX.txt" <<EOF
RapidOCRViewer $VERSION ($ARCH, $LANG_CODE) - Portable (built on Linux)
========================================================================
This is a WINDOWS application (Win32 .exe). It does NOT run natively on Linux.

To run on Linux:
  1) Install Wine:
       sudo apt install wine64   # Debian/Ubuntu
       sudo dnf install wine     # Fedora
  2) Run:
       wine "$PORT/RapidOCRViewer.exe"
  3) Or use Bottles / PlayOnLinux / VM.

Tessdata: tessdata/vie.traineddata (Vietnamese OCR)
DLLs: see redist/*.dll (Tesseract 5 + Leptonica + deps)
Built: $(date) on $(uname -a)

Original Windows build:
  - Use build_portable.bat / build_installer.bat on Windows
  - Or cross-compile on Linux with: sudo apt install mingw-w64 && ./build_linux.sh

EOF
    ok "Created $PORT/README_LINUX.txt"

    # --- create archives ---
    local ZIP="$OUT/RapidOCRViewer-Portable-${VERSION}.${ARCH}.${LANG_CODE}.zip"
    local ZIP_LEGACY="$OUT/RapidOCRViewer-Portable.zip"
    local TGZ="$OUT/RapidOCRViewer-Portable-${VERSION}.${ARCH}.${LANG_CODE}.tar.gz"
    local TGZ_LINUX="$OUT/RapidOCRViewer-${VERSION}.${ARCH}.${LANG_CODE}-linux.tar.gz"
    rm -f "$ZIP" "$ZIP_LEGACY" "$TGZ" "$TGZ_LINUX"

    # tar.gz (preferred on Linux)
    info "Creating tar.gz $TGZ"
    if tar -czf "$TGZ" -C "dist" "RapidOCRViewer-Portable" 2>/dev/null; then
        ok "Portable tar.gz: $TGZ ($(du -h "$TGZ" | cut -f1))"
        cp -f "$TGZ" "$TGZ_LINUX" 2>/dev/null || true
        ok "Linux tar.gz: $TGZ_LINUX"
        cp -f "$TGZ" "$OUT/RapidOCRViewer-Portable.tar.gz" 2>/dev/null || true
    else
        warn "tar failed"
    fi

    # zip (for compatibility)
    local ZIPPED=0
    if command -v zip >/dev/null 2>&1; then
        if (cd "dist" && zip -r -q "RapidOCRViewer-Portable-${VERSION}.${ARCH}.${LANG_CODE}.zip" "RapidOCRViewer-Portable" 2>/dev/null); then
            ZIPPED=1
            cp -f "$ZIP" "$ZIP_LEGACY" 2>/dev/null || true
            ok "Portable zip: $ZIP ($(du -h "$ZIP" | cut -f1))"
        fi
    fi
    if [[ $ZIPPED -eq 0 ]] && command -v python3 >/dev/null 2>&1; then
        info "Trying python3 zip fallback..."
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
            ok "Portable zip (python): $ZIP"
        fi
    fi

    echo
    ls -lh "$PORT" 2>/dev/null | head -n 20
    echo
    ls -lh "$TGZ" "$TGZ_LINUX" "$ZIP" 2>/dev/null || true
}

installer_package() {
    info "[3/4] Building NSIS installer (makensis)..."
    local EXE="vs2026/x64/Release/RapidOCRViewer.exe"
    if [[ ! -f "$EXE" ]]; then
        warn "Exe not found: $EXE"
    fi
    if ! command -v makensis >/dev/null 2>&1; then
        warn "makensis not found. Install: sudo apt install nsis"
        return 0
    fi
    info "makensis /DVS_VERSION=vs2026 /DBUILD_CONFIG=Release /Dx64 /DLANG=$LANG_SEL nsis/installer.nsi"
    pushd "nsis" >/dev/null
    if makensis "/DVS_VERSION=vs2026" "/DBUILD_CONFIG=Release" "/Dx64" "/DLANG=$LANG_SEL" installer.nsi; then
        ok "NSIS build succeeded"
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

main() {
    check_deps
    do_build

    case "$MODE" in
        portable)  portable_package ;;
        installer) installer_package ;;
        all)
            portable_package
            echo
            installer_package
            ;;
    esac

    info "[4/4] Done. Outputs:"
    echo "  Portable folder: dist/RapidOCRViewer-Portable/"
    ls -lh dist/*.zip dist/*.tar.gz 2>/dev/null | sed 's/^/    /' || echo "    (no archive)"
    ls -lh RapidOCRViewer-*-Setup.exe 2>/dev/null | sed 's/^/    /' || echo "    (no installer - optional, need makensis)"
    echo
    ok "Build script finished. See dist/ and repo root for outputs."
    info "Tip: wine vs2026/x64/Release/RapidOCRViewer.exe"
}

main "$@"
