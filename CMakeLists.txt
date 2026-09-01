# CMakeLists.txt - RapidOCRViewer
# Dual-mode build:
#   Windows (existing):  msbuild vs2026/RapidOCRViewer.sln  (không dùng CMake)
#   macOS native (mới):  cmake -B build/macos -GXcode  hoặc  -G Ninja
#                        cmake --build build/macos --config Release
#   Yêu cầu Apple Clang:  clang --version  (Xcode CLT)
#   Deps: brew install tesseract leptonica libpng jpeg-turbo giflib webp
#
# Trên macOS:
#   cmake -B build/macos -DCMAKE_BUILD_TYPE=Release
#   cmake --build build/macos -j$(sysctl -n hw.ncpu)
#   open build/macos/RapidOCRViewer.app
#
# Trên macOS cross MinGW vẫn giữ nguyên: ./build_macos.sh --cross

cmake_minimum_required(VERSION 3.20)

# --- version từ src/version.h ---
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/src/version.h" _ver_h)
string(REGEX MATCH "#define VERSION_MAJOR[ \t]+([0-9]+)" _ ${_ver_h})
set(VERSION_MAJOR ${CMAKE_MATCH_1})
string(REGEX MATCH "#define VERSION_MINOR[ \t]+([0-9]+)" _ ${_ver_h})
set(VERSION_MINOR ${CMAKE_MATCH_1})
string(REGEX MATCH "#define VERSION_REVISION[ \t]+([0-9]+)" _ ${_ver_h})
set(VERSION_REVISION ${CMAKE_MATCH_1})
set(PROJECT_VERSION "${VERSION_MAJOR}.${VERSION_MINOR}.${VERSION_REVISION}")
message(STATUS "RapidOCRViewer version ${PROJECT_VERSION}")

project(RapidOCRViewer
    VERSION ${PROJECT_VERSION}
    DESCRIPTION "RapidOCRViewer - macOS native (Apple Clang + AppKit)"
    LANGUAGES C CXX OBJCXX
)

# Chỉ hỗ trợ macOS native khi chạy trên Darwin với AppleClang
if(NOT APPLE)
    message(FATAL_ERROR
        "CMakeLists này chỉ dành cho macOS native (Apple Clang + AppKit).\n"
        "Trên Windows hãy dùng vs2026/RapidOCRViewer.sln\n"
        "Trên Linux/macOS cross Windows: ./build_macos.sh --cross / ./build_linux.sh"
    )
endif()

if(NOT CMAKE_CXX_COMPILER_ID MATCHES "AppleClang|Clang")
    message(WARNING "Khuyến nghị AppleClang. Hiện tại: ${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION}")
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_OBJCXX_STANDARD 17)
set(CMAKE_C_STANDARD 11)
set(CMAKE_OSX_DEPLOYMENT_TARGET "11.0" CACHE STRING "min macOS (UTType/Vision cần 11+)")
# Universal2: chạy cả Intel lẫn Apple Silicon khi build với Xcode
# cmake -B build -DCMAKE_OSX_ARCHITECTURES="x86_64;arm64"
if(NOT CMAKE_OSX_ARCHITECTURES)
    # mặc định theo máy build
endif()

# --- options ---
option(WITH_TESSERACT "Enable Tesseract OCR (brew tesseract)" ON)
option(WITH_WEBP "Enable bundled libwebp" ON)

# --- dependencies via brew / pkg-config ---
find_package(PkgConfig QUIET)

# Tesseract + Leptonica (brew install tesseract leptonica)
if(WITH_TESSERACT)
    if(PKG_CONFIG_FOUND)
        pkg_check_modules(TESSERACT QUIET tesseract)
        pkg_check_modules(LEPTONICA QUIET lept)
    endif()
    # fallback manual brew prefix
    if(NOT TESSERACT_FOUND)
        foreach(_pfx /opt/homebrew /usr/local /opt/local)
            if(EXISTS "${_pfx}/include/tesseract/baseapi.h")
                set(TESSERACT_INCLUDE_DIRS "${_pfx}/include")
                file(GLOB _tess_lib "${_pfx}/lib/libtesseract.*")
                if(_tess_lib)
                    list(GET _tess_lib 0 TESSERACT_LIBRARIES)
                    set(TESSERACT_FOUND TRUE)
                    message(STATUS "Found tesseract (brew fallback): ${_pfx}")
                    break()
                endif()
            endif()
        endforeach()
    endif()
    if(NOT LEPTONICA_FOUND)
        foreach(_pfx /opt/homebrew /usr/local /opt/local)
            if(EXISTS "${_pfx}/include/leptonica/allheaders.h")
                set(LEPTONICA_INCLUDE_DIRS "${_pfx}/include")
                file(GLOB _lept_lib "${_pfx}/lib/liblept.*")
                if(_lept_lib)
                    list(GET _lept_lib 0 LEPTONICA_LIBRARIES)
                    set(LEPTONICA_FOUND TRUE)
                    message(STATUS "Found leptonica (brew fallback): ${_pfx}")
                    break()
                endif()
            endif()
        endforeach()
    endif()
    if(TESSERACT_FOUND AND LEPTONICA_FOUND)
        message(STATUS "Tesseract: ${TESSERACT_INCLUDE_DIRS} -> ${TESSERACT_LIBRARIES}")
        message(STATUS "Leptonica: ${LEPTONICA_INCLUDE_DIRS} -> ${LEPTONICA_LIBRARIES}")
        add_definitions(-DHAVE_TESSERACT=1)
    else()
        message(WARNING "tesseract/leptonica not found -> build mock OCR. Cài: brew install tesseract leptonica\n"
                        "  Hoặc: cmake -DWITH_TESSERACT=OFF")
        set(WITH_TESSERACT OFF)
    endif()
endif()

# --- libwebp (bundled) ---
if(WITH_WEBP)
    # Dùng libwebp kèm repo, build static với AppleClang
    # Chỉ build core decoder/encoder cần cho viewer, tắt tool thừa
    set(WEBP_BUILD_CWEBP OFF CACHE BOOL "" FORCE)
    set(WEBP_BUILD_DWEBP OFF CACHE BOOL "" FORCE)
    set(WEBP_BUILD_GIF2WEBP OFF CACHE BOOL "" FORCE)
    set(WEBP_BUILD_IMG2WEBP OFF CACHE BOOL "" FORCE)
    set(WEBP_BUILD_VWEBP OFF CACHE BOOL "" FORCE)
    set(WEBP_BUILD_WEBPINFO OFF CACHE BOOL "" FORCE)
    set(WEBP_BUILD_EXTRAS OFF CACHE BOOL "" FORCE)
    set(WEBP_BUILD_WEBPMUX OFF CACHE BOOL "" FORCE)
    # libwebp CMake tự handle Apple Silicon
    add_subdirectory(libwebp EXCLUDE_FROM_ALL)
    # alias để link dễ
    # libwebp tạo target: webp, webpdemux, sharpyuv
endif()

# --- macOS sources ---
set(MACOS_SOURCES
    macos/main.mm
    macos/AppDelegate.mm
    macos/ViewerWindow.mm
    macos/ViewerView.mm
    macos/OCRBridge.mm
    macos/OCRPanel.mm
)

set(MACOS_HEADERS
    macos/AppDelegate.h
    macos/ViewerWindow.h
    macos/ViewerView.h
    macos/OCRBridge.h
    macos/OCRPanel.h
)

# Icon (dùng lại icon Windows nếu có, hoặc tạo placeholder)
set(MACOS_ICON "${CMAKE_CURRENT_SOURCE_DIR}/res/RapidOCRViewer.icns")
if(NOT EXISTS "${MACOS_ICON}")
    # fallback: dùng icon png -> iconset nếu cần, tạm để trống
    set(MACOS_ICON "")
endif()

# --- target .app ---
add_executable(RapidOCRViewer MACOSX_BUNDLE
    ${MACOS_SOURCES}
    ${MACOS_HEADERS}
    # Tài nguyên
    macos/Info.plist.in
)

# Info.plist
set_target_properties(RapidOCRViewer PROPERTIES
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/macos/Info.plist.in"
    MACOSX_BUNDLE_BUNDLE_NAME "RapidOCRViewer"
    MACOSX_BUNDLE_GUI_IDENTIFIER "com.voidtools.rapidocrviewer"
    MACOSX_BUNDLE_BUNDLE_VERSION "${PROJECT_VERSION}"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "${PROJECT_VERSION}"
    MACOSX_BUNDLE_COPYRIGHT "© 2025 voidtools / hesphoros"
    # Icon
    MACOSX_BUNDLE_ICON_FILE "RapidOCRViewer"
    XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "com.voidtools.rapidocrviewer"
    XCODE_ATTRIBUTE_CLANG_ENABLE_OBJC_ARC YES
    XCODE_ATTRIBUTE_CLANG_ENABLE_OBJC_WEAK YES
    # Hardened runtime, sandbox off (cần đọc file bất kỳ)
    XCODE_ATTRIBUTE_ENABLE_HARDENED_RUNTIME YES
)

if(MACOS_ICON AND EXISTS "${MACOS_ICON}")
    target_sources(RapidOCRViewer PRIVATE "${MACOS_ICON}")
    set_source_files_properties("${MACOS_ICON}" PROPERTIES MACOSX_PACKAGE_LOCATION "Resources")
endif()

# tessdata: copy vie.traineddata vào .app/Resources
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/tessdata/vie.traineddata")
    add_custom_command(TARGET RapidOCRViewer POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_BUNDLE_CONTENT_DIR:RapidOCRViewer>/Resources/tessdata"
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CMAKE_CURRENT_SOURCE_DIR}/tessdata/vie.traineddata"
            "$<TARGET_BUNDLE_CONTENT_DIR:RapidOCRViewer>/Resources/tessdata/vie.traineddata"
        COMMENT "Copy tessdata/vie.traineddata -> .app/Resources"
    )
    # cũng install cho `cmake --install`
    install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/tessdata/vie.traineddata"
        DESTINATION "RapidOCRViewer.app/Contents/Resources/tessdata")
endif()

# Includes - chỉ macos + libwebp (không include src/ Win32 để tránh utf8_t/BOOL/SIZE_T lỗi trên macOS)
target_include_directories(RapidOCRViewer PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/macos"
    "${CMAKE_CURRENT_SOURCE_DIR}/libwebp/src"
)

# Link frameworks macOS
target_link_libraries(RapidOCRViewer PRIVATE
    "-framework Cocoa"
    "-framework QuartzCore"
    "-framework UniformTypeIdentifiers"
    "-framework Vision"  # optional, để dự phòng Vision OCR
)

if(WITH_WEBP)
    target_link_libraries(RapidOCRViewer PRIVATE webp webpdemux sharpyuv)
    target_include_directories(RapidOCRViewer PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/libwebp"
        "${CMAKE_BINARY_DIR}/libwebp/src/webp"
    )
endif()

if(WITH_TESSERACT)
    target_include_directories(RapidOCRViewer PRIVATE ${TESSERACT_INCLUDE_DIRS} ${LEPTONICA_INCLUDE_DIRS})
    target_link_libraries(RapidOCRViewer PRIVATE ${TESSERACT_LIBRARIES} ${LEPTONICA_LIBRARIES})
    # brew tesseract kéo theo libpng, jpeg, tiff, etc. PkgConfig đã link đủ
    if(TESSERACT_LDFLAGS)
        target_link_options(RapidOCRViewer PRIVATE ${TESSERACT_LDFLAGS})
    endif()
endif()

# Compiler flags Apple Clang
target_compile_options(RapidOCRViewer PRIVATE
    -Wall -Wextra -Wno-deprecated-declarations
    $<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>
    $<$<COMPILE_LANGUAGE:CXX>:-fobjc-arc>
)

# Rpath cho brew dylib khi chạy không cần install
set_target_properties(RapidOCRViewer PROPERTIES
    INSTALL_RPATH_USE_LINK_PATH TRUE
    BUILD_WITH_INSTALL_RPATH TRUE
)

# --- install + DMG ---
install(TARGETS RapidOCRViewer
    BUNDLE DESTINATION .
)

# DMG via cpack (tùy chọn)
set(CPACK_GENERATOR "DragNDrop")
set(CPACK_DMG_VOLUME_NAME "RapidOCRViewer ${PROJECT_VERSION}")
set(CPACK_PACKAGE_FILE_NAME "RapidOCRViewer-${PROJECT_VERSION}-macOS")
include(CPack)

message(STATUS "AppleClang: ${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION}")
message(STATUS "OSX architectures: ${CMAKE_OSX_ARCHITECTURES} (trống = native)")
message(STATUS "Build type: ${CMAKE_BUILD_TYPE}")
message(STATUS "WITH_TESSERACT=${WITH_TESSERACT}  WITH_WEBP=${WITH_WEBP}")
