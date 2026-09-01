// ocr_engine.cpp - Tesseract 5 + Leptonica integration
// Conditional compilation: if HAVE_TESSERACT is defined, use real engine.
// Otherwise provide mock implementation so project builds without vcpkg.
#include "ocr_engine.h"
#include <windows.h>
#include <string>

static char g_last_error[512] = {0};
static int g_inited = 0;
static int g_available = 0;

const char* ocr_get_last_error(void) { return g_last_error; }
int ocr_is_available(void) { return g_available; }

#ifdef HAVE_TESSERACT

// Real implementation
#include <tesseract/baseapi.h>
#include <leptonica/allheaders.h>
#include <mutex>

// Free a text buffer returned by Tesseract using the DLL's own CRT.
// GetUTF8Text() allocates its result inside tesseract55.dll (release CRT);
// freeing it with the app's CRT (e.g. debug MTd msvcp140d.dll) crashes with
// "debug_heap.cpp: is_block_type_valid" heap assertion. TessDeleteText runs
// inside the DLL so the matching CRT is used.
extern "C" void TessDeleteText(const char* text);
// Same rationale for the ResultIterator and its line buffers: both are
// allocated inside tesseract55.dll, so they must be freed by DLL-side
// functions (TessResultIteratorDelete / TessDeleteText) to keep the
// matching CRT heap (see comment above).
extern "C" void TessResultIteratorDelete(tesseract::ResultIterator* handle);

static tesseract::TessBaseAPI *g_api = nullptr;
static std::mutex g_api_mutex;
static wchar_t g_tessdata_dir[MAX_PATH] = {0};

int ocr_init(const wchar_t *tessdataDir) {
    std::lock_guard<std::mutex> lock(g_api_mutex);
    if (g_inited) return 1;
    if (!tessdataDir || !*tessdataDir) {
        snprintf(g_last_error, sizeof(g_last_error), "tessdataDir empty");
        return 0;
    }
    wcsncpy_s(g_tessdata_dir, tessdataDir, MAX_PATH-1);
    // Convert wide to utf8 for Tesseract
    char utf8Dir[MAX_PATH*3];
    WideCharToMultiByte(CP_UTF8, 0, tessdataDir, -1, utf8Dir, sizeof(utf8Dir), NULL, NULL);

    g_api = new tesseract::TessBaseAPI();
    // OEM_LSTM_ONLY = 1, PSM_AUTO = 3 - good for Vietnamese
    if (g_api->Init(utf8Dir, "vie", tesseract::OEM_LSTM_ONLY) != 0) {
        snprintf(g_last_error, sizeof(g_last_error), "Tess Init failed for vie in %s", utf8Dir);
        delete g_api; g_api = nullptr;
        return 0;
    }
    // Optimize for speed/accuracy: single language vie, keep defaults
    g_api->SetVariable("tessedit_do_invert", "0");
    g_inited = 1;
    g_available = 1;
    return 1;
}

void ocr_shutdown(void) {
    std::lock_guard<std::mutex> lock(g_api_mutex);
    if (g_api) {
        g_api->End();
        delete g_api;
        g_api = nullptr;
    }
    g_inited = 0;
}

// Helper: create PIX from HBITMAP cropped rect
static Pix* pix_from_hbitmap_rect(HBITMAP hbitmap, RECT rc) {
    BITMAP bm;
    if (!GetObject(hbitmap, sizeof(BITMAP), &bm)) return nullptr;
    int srcW = bm.bmWidth;
    int srcH = bm.bmHeight;
    int w = rc.right - rc.left;
    int h = rc.bottom - rc.top;
    if (w <= 0 || h <= 0) return nullptr;
    if (rc.left < 0) rc.left = 0;
    if (rc.top < 0) rc.top = 0;
    if (rc.right > srcW) rc.right = srcW;
    if (rc.bottom > srcH) rc.bottom = srcH;
    w = rc.right - rc.left;
    h = rc.bottom - rc.top;
    if (w <= 0 || h <= 0) return nullptr;

    HDC hdcScreen = GetDC(NULL);
    HDC hdcSrc = CreateCompatibleDC(hdcScreen);
    HDC hdcDst = CreateCompatibleDC(hdcScreen);
    HBITMAP hCrop = CreateCompatibleBitmap(hdcScreen, w, h);
    if (!hCrop) { DeleteDC(hdcSrc); DeleteDC(hdcDst); ReleaseDC(NULL,hdcScreen); return nullptr; }

    HGDIOBJ oldSrc = SelectObject(hdcSrc, hbitmap);
    HGDIOBJ oldDst = SelectObject(hdcDst, hCrop);
    BitBlt(hdcDst, 0,0,w,h, hdcSrc, rc.left, rc.top, SRCCOPY);
    SelectObject(hdcSrc, oldSrc);
    SelectObject(hdcDst, oldDst);
    DeleteDC(hdcSrc);
    DeleteDC(hdcDst);
    ReleaseDC(NULL,hdcScreen);

    // Extract bits via GetDIBits
    BITMAPINFO bmi = {0};
    bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bmi.bmiHeader.biWidth = w;
    bmi.bmiHeader.biHeight = -h; // top-down
    bmi.bmiHeader.biPlanes = 1;
    bmi.bmiHeader.biBitCount = 32;
    bmi.bmiHeader.biCompression = BI_RGB;

    int stride = w * 4;
    unsigned char *bits = (unsigned char*)malloc(stride * h);
    if (!bits) { DeleteObject(hCrop); return nullptr; }

    HDC hdc = GetDC(NULL);
    int lines = GetDIBits(hdc, hCrop, 0, h, bits, &bmi, DIB_RGB_COLORS);
    ReleaseDC(NULL,hdc);
    DeleteObject(hCrop);
    if (lines != h) { free(bits); return nullptr; }

    // Create PIX (32 bpp)
    Pix *pix = pixCreate(w, h, 32);
    if (!pix) { free(bits); return nullptr; }
    for (int y=0; y<h; y++) {
        l_uint32 *line = pixGetData(pix) + y * pixGetWpl(pix);
        unsigned char *src = bits + y * stride;
        for (int x=0; x<w; x++) {
            // bits is BGRA
            unsigned char b = src[x*4+0];
            unsigned char g = src[x*4+1];
            unsigned char r = src[x*4+2];
            // PIX is RGBA: 0xRRGGBBAA? leptonica uses big-endian: compose with r<<24|g<<16|b<<8
            // Actually pixSetPixel with 32bpp expects 0xRRGGBB
            // Use helper: composeRGBPixel
            l_uint32 val;
            composeRGBPixel(r,g,b,&val);
            line[x] = val;
        }
    }
    free(bits);
    // Set resolution 300 dpi for better OCR
    pixSetXRes(pix, 300);
    pixSetYRes(pix, 300);
    return pix;
}

// Helper: shared SetImage + Recognize, returns Pix* to use (caller must pixDestroy)
static Pix* _ocr_set_image(HBITMAP hbitmap, RECT srcRect) {
    Pix *pix = pix_from_hbitmap_rect(hbitmap, srcRect);
    if (!pix) {
        snprintf(g_last_error, sizeof(g_last_error), "pix create failed");
        return nullptr;
    }
    int w = pixGetWidth(pix);
    int h = pixGetHeight(pix);
    Pix *pixToUse = pix;
    if (w < 200 || h < 50) {
        Pix *scaled = pixScale(pix, 2.0, 2.0);
        if (scaled) { pixDestroy(&pix); pixToUse = scaled; }
    }
    g_api->SetImage(pixToUse);
    g_api->SetPageSegMode(tesseract::PSM_AUTO);
    g_api->Recognize(0);
    return pixToUse;
}

// Normalize bare LF to CRLF for Windows EDIT control.
static wchar_t* _ocr_normalize_crlf(wchar_t *wstr, int wlen) {
    size_t n = 0;
    for (size_t i = 0; wstr && wstr[i] != 0; i++) {
        if (wstr[i] == L'\n' && (i == 0 || wstr[i-1] != L'\r')) n++;
    }
    if (n > 0 && wstr) {
        size_t newlen = (size_t)wlen + n;
        wchar_t *nw = (wchar_t*)malloc(newlen * sizeof(wchar_t));
        if (nw) {
            size_t j = 0;
            for (size_t i = 0; wstr[i] != 0; i++) {
                if (wstr[i] == L'\n' && (i == 0 || wstr[i-1] != L'\r')) nw[j++] = L'\r';
                nw[j++] = wstr[i];
            }
            nw[j] = 0;
            free(wstr);
            wstr = nw;
        }
    }
    return wstr;
}

wchar_t* ocr_recognize_hbitmap(HBITMAP hbitmap, RECT srcRect) {
    if (!g_inited || !g_api) {
        snprintf(g_last_error, sizeof(g_last_error), "OCR not inited");
        return nullptr;
    }
    if (!hbitmap) {
        snprintf(g_last_error, sizeof(g_last_error), "null hbitmap");
        return nullptr;
    }
    std::lock_guard<std::mutex> lock(g_api_mutex);

    Pix *pix = pix_from_hbitmap_rect(hbitmap, srcRect);
    if (!pix) {
        snprintf(g_last_error, sizeof(g_last_error), "pix create failed");
        return nullptr;
    }
    // Optional: upscale small images for speed/accuracy tradeoff
    int w = pixGetWidth(pix);
    int h = pixGetHeight(pix);
    Pix *pixToUse = pix;
    // If very small, scale 2x
    if (w < 200 || h < 50) {
        Pix *scaled = pixScale(pix, 2.0, 2.0);
        if (scaled) {
            pixDestroy(&pix);
            pixToUse = scaled;
        }
    }

    g_api->SetImage(pixToUse);
    // PSM 3 = Auto page segmentation (detects lines and paragraphs, inserts newlines)
    // PSM 6 = SINGLE_BLOCK concatenates all lines without newlines
    g_api->SetPageSegMode(tesseract::PSM_AUTO);

    char *utf8 = g_api->GetUTF8Text();
    if (pixToUse != pix) pixDestroy(&pixToUse);
    else pixDestroy(&pix);

    if (!utf8) {
        snprintf(g_last_error, sizeof(g_last_error), "GetUTF8Text null");
        return nullptr;
    }
    // Convert utf8 to wide
    int wlen = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, NULL, 0);
    wchar_t *wstr = (wchar_t*)malloc(wlen * sizeof(wchar_t));
    if (wstr) MultiByteToWideChar(CP_UTF8, 0, utf8, -1, wstr, wlen);
    TessDeleteText(utf8); // free inside tesseract55.dll (matching CRT)

    // Normalize line breaks: Tesseract emits '\n' (LF), but the Windows
    // multiline EDIT control only renders line breaks for '\r\n' (CRLF).
    // A lone LF shows up as no line break (or a garbage glyph), so the OCR
    // result appears "stuck together". Convert bare '\n' to '\r\n'.
    {
        size_t n = 0;
        for (size_t i = 0; wstr && wstr[i] != 0; i++) {
            if (wstr[i] == L'\n' && (i == 0 || wstr[i-1] != L'\r')) n++;
        }
        if (n > 0 && wstr) {
            size_t newlen = (size_t)wlen + n;
            wchar_t *nw = (wchar_t*)malloc(newlen * sizeof(wchar_t));
            if (nw) {
                size_t j = 0;
                for (size_t i = 0; wstr[i] != 0; i++) {
                    if (wstr[i] == L'\n' && (i == 0 || wstr[i-1] != L'\r')) {
                        nw[j++] = L'\r';
                    }
                    nw[j++] = wstr[i];
                }
                nw[j] = 0;
                free(wstr);
                wstr = nw;
            }
        }
    }
    return wstr;
}

// Paragraph-aware OCR: use ResultIterator to iterate text lines, join lines
// inside each paragraph into a single flowing line, and separate paragraphs
// with a blank line (CRLF CRLF). This avoids the OCR result being broken into
// lines that mirror the image layout.
wchar_t* ocr_recognize_hbitmap_paragraphs(HBITMAP hbitmap, RECT srcRect) {
    if (!g_inited || !g_api) {
        snprintf(g_last_error, sizeof(g_last_error), "OCR not inited");
        return nullptr;
    }
    if (!hbitmap) {
        snprintf(g_last_error, sizeof(g_last_error), "null hbitmap");
        return nullptr;
    }
    std::lock_guard<std::mutex> lock(g_api_mutex);

    Pix *pixToUse = _ocr_set_image(hbitmap, srcRect);
    if (!pixToUse) return nullptr;

    std::string result;
    tesseract::ResultIterator *it = g_api->GetIterator();
    if (!it) {
        snprintf(g_last_error, sizeof(g_last_error), "GetIterator null");
        pixDestroy(&pixToUse);
        return nullptr;
    }
    it->Begin();
    bool para_open = false;    // we are inside a paragraph that produced text
    do {
        if (it->Empty(tesseract::RIL_TEXTLINE)) continue;
        char *line = it->GetUTF8Text(tesseract::RIL_TEXTLINE);
        std::string ls = line ? line : "";
        if (line) TessDeleteText(line);
        // Strip trailing line breaks
        while (!ls.empty() && (ls.back() == '\n' || ls.back() == '\r')) ls.pop_back();
        // Trim surrounding whitespace
        size_t b = ls.find_first_not_of(" \t");
        size_t e = ls.find_last_not_of(" \t");
        if (b != std::string::npos) {
            ls = ls.substr(b, e - b + 1);
            // Within a paragraph join lines with a single space.
            if (para_open) result.append(" ");
            result.append(ls);
            para_open = true;
        }
        // End of a paragraph: insert a blank line separator.
        if (it->IsAtFinalElement(tesseract::RIL_PARA, tesseract::RIL_TEXTLINE)) {
            if (para_open) { result.append("\r\n\r\n"); para_open = false; }
        }
    } while (it->Next(tesseract::RIL_TEXTLINE));
    TessResultIteratorDelete(it);
    pixDestroy(&pixToUse);

    // Trim trailing blank lines
    while (result.size() >= 4 && result.compare(result.size() - 4, 4, "\r\n\r\n") == 0)
        result.resize(result.size() - 4);
    if (result.empty()) {
        snprintf(g_last_error, sizeof(g_last_error), "no text");
        return nullptr;
    }
    int wlen = MultiByteToWideChar(CP_UTF8, 0, result.c_str(), -1, NULL, 0);
    wchar_t *wstr = (wchar_t*)malloc(wlen * sizeof(wchar_t));
    if (wstr) MultiByteToWideChar(CP_UTF8, 0, result.c_str(), -1, wstr, wlen);
    return wstr;
}

void ocr_free_result(wchar_t *p) { if (p) free(p); }

#else
// Mock implementation - builds without tesseract
#include <stdio.h>
int ocr_init(const wchar_t *tessdataDir) {
    (void)tessdataDir;
    // Check if vie.traineddata exists to report more accurate error
    g_inited = 1;
    g_available = 0;
    snprintf(g_last_error, sizeof(g_last_error), "Tesseract not compiled (HAVE_TESSERACT=0). Install vcpkg tesseract+leptonica and rebuild with /DHAVE_TESSERACT");
    // Still return 1 so UI works in demo mode
    return 1;
}
void ocr_shutdown(void) { g_inited = 0; }
wchar_t* ocr_recognize_hbitmap(HBITMAP hbitmap, RECT srcRect) {
    (void)hbitmap;
    // Mock: return demo Vietnamese text with rect info
    wchar_t *buf = (wchar_t*)malloc(512*sizeof(wchar_t));
    if (!buf) return nullptr;
    // Provide helpful demo text
    swprintf_s(buf, 512, L"[Demo OCR] Vùng chọn: %ld,%ld %ldx%ld\n\nTesseract chưa được biên dịch.\nHãy cài vcpkg tesseract + leptonica và build với HAVE_TESSERACT.\n\nĐể kiểm thử, panel này đã hoạt động và nút Copy sẽ sao chép văn bản.\n\nVí dụ tiếng Việt: Xin chào, đây là kết quả OCR mẫu với dấu tiếng Việt: Hà Nội, Đà Nẵng, TP. Hồ Chí Minh.",
        srcRect.left, srcRect.top, srcRect.right - srcRect.left, srcRect.bottom - srcRect.top);
    return buf;
}
wchar_t* ocr_recognize_hbitmap_paragraphs(HBITMAP hbitmap, RECT srcRect) {
    // Mock: same demo text (paragraph mode)
    return ocr_recognize_hbitmap(hbitmap, srcRect);
}
void ocr_free_result(wchar_t *p) { if(p) free(p); }
#endif
