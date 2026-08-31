// ocr_panel.c - Right-side OCR panel implementation
#include "viv.h"
#include "ocr_panel.h"
#include "string.h"

static HWND g_panel_hwnd = NULL;
static HWND g_edit_hwnd = NULL;
static HWND g_copy_hwnd = NULL;
static HWND g_clear_hwnd = NULL;
static HWND g_label_hwnd = NULL;
static const int PANEL_W = OCR_PANEL_WIDTH;
static const int MARGIN = 8;
static const int BTN_H = 24;
static const int LABEL_H = 20;

static LRESULT CALLBACK panel_proc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam);

void ocr_panel_create(HWND parent) {
    if (g_panel_hwnd) return;

    // Create panel container as child of main window
    g_panel_hwnd = CreateWindowExW(0, L"STATIC", L"", WS_CHILD | WS_CLIPSIBLINGS | WS_CLIPCHILDREN,
        0,0,PANEL_W,100, parent, (HMENU)40050, os_hinstance, NULL);
    // Use a custom proc for background
    SetWindowLongPtr(g_panel_hwnd, GWLP_WNDPROC, (LONG_PTR)panel_proc);
    // Store old proc? We'll just handle WM_CTLCOLOR via parent or panel_proc

    // Label "OCR Result"
    wchar_t labelText[64];
    string_copy_utf8_string(labelText, localization_get_string(LOCALIZATION_ID_OCR_RESULT));
    g_label_hwnd = CreateWindowExW(0, L"STATIC", labelText, WS_CHILD | WS_VISIBLE | SS_LEFT,
        MARGIN, MARGIN, PANEL_W - MARGIN*2, LABEL_H, g_panel_hwnd, NULL, os_hinstance, NULL);
    HFONT hFont = (HFONT)GetStockObject(DEFAULT_GUI_FONT);
    SendMessage(g_label_hwnd, WM_SETFONT, (WPARAM)hFont, TRUE);

    // Edit multiline
    g_edit_hwnd = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"", WS_CHILD | WS_VISIBLE | WS_VSCROLL | ES_MULTILINE | ES_AUTOVSCROLL | ES_WANTRETURN,
        MARGIN, MARGIN + LABEL_H + 4, PANEL_W - MARGIN*2, 100, g_panel_hwnd, (HMENU)40051, os_hinstance, NULL);
    SendMessage(g_edit_hwnd, WM_SETFONT, (WPARAM)hFont, TRUE);
    // Allow unicode

    // Copy button
    wchar_t copyText[32];
    string_copy_utf8_string(copyText, localization_get_string(LOCALIZATION_ID_OCR_COPY));
    g_copy_hwnd = CreateWindowExW(0, L"BUTTON", copyText, WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
        MARGIN, 0, (PANEL_W - MARGIN*3)/2, BTN_H, g_panel_hwnd, (HMENU)VIV_ID_OCR_COPY, os_hinstance, NULL);
    SendMessage(g_copy_hwnd, WM_SETFONT, (WPARAM)hFont, TRUE);

    // Clear button
    wchar_t clearText[32];
    string_copy_utf8_string(clearText, localization_get_string(LOCALIZATION_ID_OCR_CLEAR));
    // Fallback if not localized
    if (clearText[0]==0) wcscpy_s(clearText, 32, L"Clear");
    g_clear_hwnd = CreateWindowExW(0, L"BUTTON", clearText, WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
        MARGIN + (PANEL_W - MARGIN*3)/2 + MARGIN, 0, (PANEL_W - MARGIN*3)/2, BTN_H, g_panel_hwnd, (HMENU)VIV_ID_OCR_CLEAR, os_hinstance, NULL);
    SendMessage(g_clear_hwnd, WM_SETFONT, (WPARAM)hFont, TRUE);

    // Initially hidden
    ShowWindow(g_panel_hwnd, SW_HIDE);
}

void ocr_panel_destroy(void) {
    if (g_panel_hwnd) DestroyWindow(g_panel_hwnd);
    g_panel_hwnd = NULL;
    g_edit_hwnd = NULL;
    g_copy_hwnd = NULL;
    g_clear_hwnd = NULL;
    g_label_hwnd = NULL;
}

void ocr_panel_show(BOOL show) {
    if (!g_panel_hwnd) return;
    ShowWindow(g_panel_hwnd, show ? SW_SHOW : SW_HIDE);
    // Parent will re-layout via WM_SIZE
    if (GetParent(g_panel_hwnd)) {
        RECT rc; GetClientRect(GetParent(g_panel_hwnd), &rc);
        // Trigger parent's on_size by sending WM_SIZE
        SendMessage(GetParent(g_panel_hwnd), WM_SIZE, 0, MAKELPARAM(rc.right, rc.bottom));
    }
}

BOOL ocr_panel_is_visible(void) {
    return g_panel_hwnd && IsWindowVisible(g_panel_hwnd);
}

HWND ocr_panel_get_hwnd(void) { return g_panel_hwnd; }

void ocr_panel_set_text(const wchar_t *text) {
    if (!g_edit_hwnd) return;
    SetWindowTextW(g_edit_hwnd, text ? text : L"");
    // Move caret to start
    SendMessage(g_edit_hwnd, EM_SETSEL, 0, 0);
}

void ocr_panel_set_status(const wchar_t *status) {
    ocr_panel_set_text(status);
}

void ocr_panel_clear(void) {
    ocr_panel_set_text(L"");
}

void ocr_panel_on_size(RECT clientRect) {
    if (!g_panel_hwnd) return;
    int totalW = clientRect.right - clientRect.left;
    int totalH = clientRect.bottom - clientRect.top;
    // Panel is on right, fixed width
    int panelX = totalW - PANEL_W;
    if (panelX < 0) panelX = 0;
    int panelW = PANEL_W;
    if (totalW < PANEL_W) panelW = totalW;

    SetWindowPos(g_panel_hwnd, NULL, panelX, 0, panelW, totalH, SWP_NOZORDER | SWP_NOACTIVATE);

    // Layout inside panel
    int innerW = panelW - MARGIN*2;
    int labelY = MARGIN;
    SetWindowPos(g_label_hwnd, NULL, MARGIN, labelY, innerW, LABEL_H, SWP_NOZORDER);
    int editY = labelY + LABEL_H + 4;
    int btnY = totalH - BTN_H - MARGIN;
    int editH = btnY - editY - MARGIN;
    if (editH < 40) editH = 40;
    SetWindowPos(g_edit_hwnd, NULL, MARGIN, editY, innerW, editH, SWP_NOZORDER);
    int btnW = (innerW - MARGIN)/2;
    SetWindowPos(g_copy_hwnd, NULL, MARGIN, btnY, btnW, BTN_H, SWP_NOZORDER);
    SetWindowPos(g_clear_hwnd, NULL, MARGIN + btnW + MARGIN, btnY, btnW, BTN_H, SWP_NOZORDER);
}

static LRESULT CALLBACK panel_proc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch(msg) {
        case WM_CTLCOLORSTATIC: {
            HDC hdc = (HDC)wParam;
            SetBkColor(hdc, GetSysColor(COLOR_BTNFACE));
            SetTextColor(hdc, GetSysColor(COLOR_BTNTEXT));
            static HBRUSH br = NULL;
            if (!br) br = GetSysColorBrush(COLOR_BTNFACE);
            return (LRESULT)br;
        }
        case WM_ERASEBKGND: {
            HDC hdc = (HDC)wParam;
            RECT rc; GetClientRect(hwnd, &rc);
            FillRect(hdc, &rc, GetSysColorBrush(COLOR_BTNFACE));
            // Draw left border
            HPEN pen = CreatePen(PS_SOLID, 1, GetSysColor(COLOR_3DSHADOW));
            HPEN old = SelectObject(hdc, pen);
            MoveToEx(hdc, 0, 0, NULL);
            LineTo(hdc, 0, rc.bottom);
            SelectObject(hdc, old);
            DeleteObject(pen);
            return 1;
        }
        case WM_COMMAND: {
            WORD id = LOWORD(wParam);
            if (id == VIV_ID_OCR_COPY || id == VIV_ID_OCR_CLEAR) {
                // Forward to parent
                SendMessage(GetParent(hwnd), WM_COMMAND, wParam, lParam);
                return 0;
            }
            break;
        }
    }
    return DefWindowProcW(hwnd, msg, wParam, lParam);
}
