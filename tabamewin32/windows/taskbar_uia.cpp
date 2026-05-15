#pragma once

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif

#include <windows.h>
#include <uiautomation.h>
#include <dwmapi.h>
#include <objbase.h>
#include <oleacc.h>
#include <comdef.h>
#include <iostream>
#include <vector>
#include <string>

// Link necessary libraries
#pragma comment(lib, "dwmapi.lib")
#pragma comment(lib, "Ole32.lib")
#pragma comment(lib, "OleAut32.lib")
#pragma comment(lib, "uiautomationcore.lib")

#pragma comment(lib, "oleacc.lib")

// Structure to hold our extracted window data
struct WindowData {
    std::wstring uiaName;
    std::wstring helpText;
};

static IUIAutomation* g_pAutomation = nullptr;

static void ReleaseUiaCache()
{
    if (g_pAutomation) {
        g_pAutomation->Release();
        g_pAutomation = nullptr;
    }
}

void ShutdownTaskbarUia()
{
    ReleaseUiaCache();
}
// Find the taskbar and walk its UIA tree to get button names/tooltips
static std::vector<WindowData> GetTaskbarWindowsUIA() {
    std::vector<WindowData> results;

    if (!g_pAutomation) {
        HRESULT hr = CoCreateInstance(__uuidof(CUIAutomation), NULL,
            CLSCTX_INPROC_SERVER, __uuidof(IUIAutomation),
            (void**)&g_pAutomation);
        if (FAILED(hr) || !g_pAutomation) return results;
    }

    // 1. Find the taskbar HWND
    HWND hTaskbar = FindWindowW(L"Shell_TrayWnd", nullptr);
    if (!hTaskbar) return results;

    // The actual task button area is inside "MSTaskListWClass"
    HWND hTaskList = FindWindowExW(nullptr, nullptr, L"MSTaskListWClass", nullptr);
    if (!hTaskList) {
        // Fallback: walk into Shell_TrayWnd children
        hTaskList = FindWindowExW(hTaskbar, nullptr, L"ReBarWindow32", nullptr);
        hTaskList = FindWindowExW(hTaskList, nullptr, L"MSTaskSwWClass", nullptr);
        hTaskList = FindWindowExW(hTaskList, nullptr, L"MSTaskListWClass", nullptr);
    }
    if (!hTaskList) return results;

    // 2. Get UIA element for the task list
    IUIAutomationElement* pTaskList = nullptr;
    if (FAILED(g_pAutomation->ElementFromHandle(hTaskList, &pTaskList)) || !pTaskList)
        return results;

    // 3. Create a condition to find all Button children
    IUIAutomationCondition* pButtonCond = nullptr;
    VARIANT varType;
    varType.vt = VT_I4;
    varType.lVal = UIA_ButtonControlTypeId;
    g_pAutomation->CreatePropertyCondition(UIA_ControlTypePropertyId, varType, &pButtonCond);

    IUIAutomationElementArray* pButtons = nullptr;
    pTaskList->FindAll(TreeScope_Descendants, pButtonCond, &pButtons);

    if (pButtons) {
        int count = 0;
        pButtons->get_Length(&count);

        for (int i = 0; i < count; i++) {
            IUIAutomationElement* pBtn = nullptr;
            pButtons->GetElement(i, &pBtn);
            if (!pBtn) continue;

            BSTR bstrName = nullptr;
            BSTR bstrHelp = nullptr;
            pBtn->get_CurrentName(&bstrName);
            pBtn->get_CurrentHelpText(&bstrHelp);

            // Get the native window handle this button represents
            VARIANT varHwnd;
            pBtn->GetCurrentPropertyValue(UIA_NativeWindowHandlePropertyId, &varHwnd);

            WindowData data;
            if (bstrName)     { data.uiaName   = bstrName;    SysFreeString(bstrName); }
            if (bstrHelp)     { data.helpText  = bstrHelp;    SysFreeString(bstrHelp); }

            VariantClear(&varHwnd);
            results.push_back(data);
            pBtn->Release();
        }
        pButtons->Release();
    }

    if (pButtonCond) pButtonCond->Release();
    pTaskList->Release();
    return results;
}

RECT GetFocusedElementRect() {
    IUIAutomation* pAutomation = nullptr;
    IUIAutomationElement* pFocusedElement = nullptr;
    RECT rect = {};

    CoInitialize(nullptr);
    CoCreateInstance(
        CLSID_CUIAutomation, nullptr,
        CLSCTX_INPROC_SERVER,
        IID_IUIAutomation,
        (void**)&pAutomation
    );

    if (pAutomation) {
        pAutomation->GetFocusedElement(&pFocusedElement);

        if (pFocusedElement) {
            RECT bounds;
            pFocusedElement->get_CurrentBoundingRectangle(&bounds);
            rect = bounds;
            pFocusedElement->Release();
        }
        pAutomation->Release();
    }

    CoUninitialize();
    return rect;
}



namespace detail {
 
// Extract the first RECT from a SAFEARRAY of doubles (left,top,width,height).
// If the range is degenerate the rect may be zero-width; we still return it so
// the caller can use at least the top-left as the caret origin.
inline bool RectFromSafeArray(SAFEARRAY* pSA, RECT& out)
{
    if (!pSA) return false;
 
    double* data = nullptr;
    if (FAILED(SafeArrayAccessData(pSA, reinterpret_cast<void**>(&data))))
        return false;
 
    long lb = 0, ub = 0;
    SafeArrayGetLBound(pSA, 1, &lb);
    SafeArrayGetUBound(pSA, 1, &ub);
    long count = ub - lb + 1;
 
    bool ok = false;
    if (count >= 4)
    {
        out.left   = static_cast<LONG>(data[0]);
        out.top    = static_cast<LONG>(data[1]);
        out.right  = static_cast<LONG>(data[0] + data[2]);
        out.bottom = static_cast<LONG>(data[1] + data[3]);
        // Accept even a zero-width rect — the position is still valid.
        ok = (out.left != 0 || out.top != 0);
    }
 
    SafeArrayUnaccessData(pSA);
    return ok;
}
 
// Expand a text range by one character unit so GetBoundingRectangles returns a
// non-empty rect for a degenerate (collapsed) caret range.
// Tries forward first; if already at end-of-document tries backward.
inline SAFEARRAY* BoundingRectsFromCaretRange(IUIAutomationTextRange* pRange)
{
    if (!pRange) return nullptr;
 
    IUIAutomationTextRange* pExp = nullptr;
    pRange->Clone(&pExp);
    if (!pExp) return nullptr;
 
    INT moved = 0;
    pExp->MoveEndpointByUnit(TextPatternRangeEndpoint_End,
                              TextUnit_Character, 1, &moved);
    if (moved == 0)
    {
        // At end of document — expand backward instead.
        pExp->MoveEndpointByUnit(TextPatternRangeEndpoint_Start,
                                  TextUnit_Character, -1, &moved);
    }
 
    SAFEARRAY* pSA = nullptr;
    pExp->GetBoundingRectangles(&pSA);
    pExp->Release();
    return pSA;
}
 
// ---------------------------------------------------------------------------
// Layer 1 — Win32 GUITHREADINFO caret
// ---------------------------------------------------------------------------
inline bool TryWin32Caret(RECT& out)
{
    GUITHREADINFO gti = {};
    gti.cbSize = sizeof(gti);
 
    // Pass threadId = 0 → foreground thread.
    if (!GetGUIThreadInfo(0, &gti) || !gti.hwndCaret)
        return false;
 
    // rcCaret is in client coordinates of hwndCaret.
    RECT rc = gti.rcCaret;
    POINT tl = { rc.left, rc.top };
    POINT br = { rc.right, rc.bottom };
    ClientToScreen(gti.hwndCaret, &tl);
    ClientToScreen(gti.hwndCaret, &br);
 
    out = { tl.x, tl.y, br.x, br.y };
 
    // A zero-size rect still has a valid position — accept it.
    return true;
}
 
// ---------------------------------------------------------------------------
// Layer 2 — UIA TextPattern2::GetCaretRange
// ---------------------------------------------------------------------------
inline bool TryUIACaretRange(IUIAutomationElement* pElem, RECT& out)
{
    IUIAutomationTextPattern2* pTP2 = nullptr;
    HRESULT hr = pElem->GetCurrentPattern(
        UIA_TextPattern2Id,
        reinterpret_cast<IUnknown**>(&pTP2));
    if (FAILED(hr) || !pTP2) return false;
 
    BOOL isActive = FALSE;
    IUIAutomationTextRange* pRange = nullptr;
    hr = pTP2->GetCaretRange(&isActive, &pRange);
    pTP2->Release();
 
    if (FAILED(hr) || !pRange) return false;
 
    SAFEARRAY* pSA = BoundingRectsFromCaretRange(pRange);
    pRange->Release();
 
    bool ok = RectFromSafeArray(pSA, out);
    if (pSA) SafeArrayDestroy(pSA);
    return ok;
}
 
// ---------------------------------------------------------------------------
// Layer 3 — UIA TextPattern::GetSelection (collapsed = caret)
// ---------------------------------------------------------------------------
inline bool TryUIASelection(IUIAutomationElement* pElem, RECT& out)
{
    IUIAutomationTextPattern* pTP = nullptr;
    HRESULT hr = pElem->GetCurrentPattern(
        UIA_TextPatternId,
        reinterpret_cast<IUnknown**>(&pTP));
    if (FAILED(hr) || !pTP) return false;
 
    IUIAutomationTextRangeArray* pSel = nullptr;
    hr = pTP->GetSelection(&pSel);
    pTP->Release();
    if (FAILED(hr) || !pSel) return false;
 
    int count = 0;
    pSel->get_Length(&count);
 
    bool ok = false;
    if (count > 0)
    {
        IUIAutomationTextRange* pRange = nullptr;
        pSel->GetElement(0, &pRange);
        if (pRange)
        {
            SAFEARRAY* pSA = BoundingRectsFromCaretRange(pRange);
            pRange->Release();
            ok = RectFromSafeArray(pSA, out);
            if (pSA) SafeArrayDestroy(pSA);
        }
    }
 
    pSel->Release();
    return ok;
}
 
// ---------------------------------------------------------------------------
// Layer 4 — IAccessible OBJID_CARET
// ---------------------------------------------------------------------------
inline bool TryAccessibleCaret(RECT& out)
{
    HWND hwnd = GetForegroundWindow();
    if (!hwnd) return false;
 
    IAccessible* pAcc = nullptr;
    VARIANT varChild  = {};
    HRESULT hr = AccessibleObjectFromWindow(
        hwnd, 
        static_cast<DWORD>(OBJID_CARET), // Cast to DWORD to resolve C4245
        IID_IAccessible,
        reinterpret_cast<void**>(&pAcc));
    if (FAILED(hr) || !pAcc) return false;
 
    VARIANT self;
    self.vt   = VT_I4;
    self.lVal = CHILDID_SELF;
 
    LONG x = 0, y = 0, w = 0, h = 0;
    hr = pAcc->accLocation(&x, &y, &w, &h, self);
    pAcc->Release();
 
    if (FAILED(hr)) return false;
 
    out = { x, y, x + w, y + h };
    return (x != 0 || y != 0);
}
 
} // namespace detail
 
// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------
 
/// Returns the screen-space bounding rect of the current text caret.
/// Falls back through multiple strategies; returns an empty RECT on total failure.
inline RECT GetFocusedElementCaretRect()
{
    RECT result = {};
 
    // --- Layer 1: Win32 caret (fastest, most reliable for classic apps) -------
    if (detail::TryWin32Caret(result))
        return result;
 
    // --- Layers 2–3 need a UIA element; initialise COM once -------------------
    IUIAutomation*        pAuto = nullptr;
    IUIAutomationElement* pElem = nullptr;
 
    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
 
    HRESULT hr = CoCreateInstance(
        CLSID_CUIAutomation, nullptr,
        CLSCTX_INPROC_SERVER,
        IID_IUIAutomation,
        reinterpret_cast<void**>(&pAuto));
 
    if (SUCCEEDED(hr) && pAuto)
        pAuto->GetFocusedElement(&pElem);
 
    if (pElem)
    {
        // --- Layer 2: UIA TextPattern2::GetCaretRange -------------------------
        if (detail::TryUIACaretRange(pElem, result))
            goto done;
 
        // --- Layer 3: UIA TextPattern::GetSelection ---------------------------
        if (detail::TryUIASelection(pElem, result))
            goto done;
 
        // --- Layer 5 (last resort): focused element bounding rect -------------
        // (done after layer 4 so IAccessible gets a chance first)
    }
 
    // --- Layer 4: IAccessible OBJID_CARET ------------------------------------
    if (detail::TryAccessibleCaret(result))
        goto done;
 
    // --- Layer 5: focused element bounding rect (whole control) --------------
    if (pElem)
        pElem->get_CurrentBoundingRectangle(&result);
 
done:
    if (pElem)  pElem->Release();
    if (pAuto)  pAuto->Release();
    CoUninitialize();
    return result;
}
 

/* 
RECT GetFocusedElementCaretRect() {
    RECT caretRect = {};
    IUIAutomation*        pAuto = nullptr;
    IUIAutomationElement* pElem = nullptr;
    IUIAutomationTextPattern* pTextPattern = nullptr;
    IUIAutomationTextRangeArray* pSelection = nullptr;
    IUIAutomationTextRange* pRange = nullptr;

    CoInitialize(nullptr);

    HRESULT hr = CoCreateInstance(
        CLSID_CUIAutomation, nullptr,
        CLSCTX_INPROC_SERVER,
        IID_IUIAutomation,
        reinterpret_cast<void**>(&pAuto)
    );
    if (FAILED(hr) || !pAuto) goto cleanup;

    // Get focused element
    if (FAILED(pAuto->GetFocusedElement(&pElem)) || !pElem) goto cleanup;

    // Try to get TextPattern from the focused element
    hr = pElem->GetCurrentPattern(UIA_TextPatternId,
                                  reinterpret_cast<IUnknown**>(&pTextPattern));
    if (FAILED(hr) || !pTextPattern) {
        // Fallback: element has no text pattern (e.g. a button),
        // just use the control bounding rect
        pElem->get_CurrentBoundingRectangle(&caretRect);
        goto cleanup;
    }

    // GetSelection returns the caret range when no text is selected
    // (a degenerate/collapsed range at cursor position)
    if (FAILED(pTextPattern->GetSelection(&pSelection)) || !pSelection) goto cleanup;

    {
        int count = 0;
        pSelection->get_Length(&count);
        if (count == 0) goto cleanup;

        // Take the first (or only) selection range
        pSelection->GetElement(0, &pRange);
        if (!pRange) goto cleanup;

        // Get bounding rectangles of the caret range
        SAFEARRAY* pRects = nullptr;
        pRange->GetBoundingRectangles(&pRects);

        if (pRects) {
            // Each rect = 4 doubles: left, top, width, height
            double* data = nullptr;
            SafeArrayAccessData(pRects, reinterpret_cast<void**>(&data));

            long lBound, uBound;
            SafeArrayGetLBound(pRects, 1, &lBound);
            SafeArrayGetUBound(pRects, 1, &uBound);
            long elemCount = uBound - lBound + 1;

            if (elemCount >= 4) {
                caretRect.left   = static_cast<LONG>(data[0]);
                caretRect.top    = static_cast<LONG>(data[1]);
                caretRect.right  = static_cast<LONG>(data[0] + data[2]); // left + width
                caretRect.bottom = static_cast<LONG>(data[1] + data[3]); // top + height
            }

            SafeArrayUnaccessData(pRects);
            SafeArrayDestroy(pRects);
        }
    }

cleanup:
    if (pRange)        pRange->Release();
    if (pSelection)    pSelection->Release();
    if (pTextPattern)  pTextPattern->Release();
    if (pElem)         pElem->Release();
    if (pAuto)         pAuto->Release();
    CoUninitialize();

    return caretRect;
} */