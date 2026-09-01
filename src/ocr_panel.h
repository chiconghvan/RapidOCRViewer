// ocr_panel.h - Right-side OCR panel (fixed 320px)
#pragma once
#include <windows.h>
#ifdef __cplusplus
extern "C" {
#endif

#define OCR_PANEL_WIDTH 320
#define WM_OCR_DONE     (WM_USER + 100)
#define WM_OCR_ERROR    (WM_USER + 101)

void ocr_panel_create(HWND parent);
void ocr_panel_destroy(void);
void ocr_panel_show(BOOL show);
BOOL ocr_panel_is_visible(void);
void ocr_panel_set_text(const wchar_t *text);
void ocr_panel_set_status(const wchar_t *status);
void ocr_panel_on_size(RECT clientRect);
HWND ocr_panel_get_hwnd(void);
void ocr_panel_clear(void);
BOOL ocr_panel_get_paragraph(void);
void ocr_panel_set_paragraph(BOOL on);

#ifdef __cplusplus
}
#endif
