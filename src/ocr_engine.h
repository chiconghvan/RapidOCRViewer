// ocr_engine.h - Tesseract 5 C++ API wrapper for RapidOCRViewer
// Provides C interface for viv.c (which is compiled as C)
#pragma once
#ifdef __cplusplus
extern "C" {
#endif

#include <windows.h>

// Initialize Tesseract. tessdataDir: folder containing vie.traineddata/tessdata
// Returns 1 on success, 0 on failure.
// Thread-safe init once; call from UI thread before first OCR.
int ocr_init(const wchar_t *tessdataDir);
void ocr_shutdown(void);

// Recognize from HBITMAP cropped region.
// srcRect in source image pixel coords (already mapped from selection)
// hbitmap: source HBITMAP (DIB, 32bpp)
// Returns allocated wchar_t* (must be freed with ocr_free_result) or NULL on fail.
// Caller must free with ocr_free_result.
wchar_t* ocr_recognize_hbitmap(HBITMAP hbitmap, RECT srcRect);

// Paragraph-aware version: uses ResultIterator to merge lines within each
// paragraph into flowing text, separated by blank lines between paragraphs.
// Otherwise same contract as ocr_recognize_hbitmap.
wchar_t* ocr_recognize_hbitmap_paragraphs(HBITMAP hbitmap, RECT srcRect);

// Free result from ocr_recognize_hbitmap
void ocr_free_result(wchar_t *p);

// Last error string (static, utf8)
const char* ocr_get_last_error(void);

// Check if real tesseract is available
int ocr_is_available(void);

#ifdef __cplusplus
}
#endif
