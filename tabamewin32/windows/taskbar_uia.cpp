#pragma once

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif

#include <comdef.h>
#include <dwmapi.h>
#include <fstream>
#include <iostream>
#include <objbase.h>
#include <oleacc.h>
#include <string>
#include <uiautomation.h>
#include <vector>
#include <windows.h>
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

static IUIAutomation *g_pAutomation = nullptr;

static void ReleaseUiaCache() {
  if (g_pAutomation) {
    g_pAutomation->Release();
    g_pAutomation = nullptr;
  }
}

void ShutdownTaskbarUia() { ReleaseUiaCache(); }
// Find the taskbar and walk its UIA tree to get button names/tooltips
static std::vector<WindowData> GetTaskbarWindowsUIA() {
  std::vector<WindowData> results;

  if (!g_pAutomation) {
    HRESULT hr =
        CoCreateInstance(__uuidof(CUIAutomation), NULL, CLSCTX_INPROC_SERVER,
                         __uuidof(IUIAutomation), (void **)&g_pAutomation);
    if (FAILED(hr) || !g_pAutomation)
      return results;
  }

  // 1. Find the taskbar HWND
  HWND hTaskbar = FindWindowW(L"Shell_TrayWnd", nullptr);
  if (!hTaskbar)
    return results;

  // The actual task button area is inside "MSTaskListWClass"
  HWND hTaskList =
      FindWindowExW(nullptr, nullptr, L"MSTaskListWClass", nullptr);
  if (!hTaskList) {
    // Fallback: walk into Shell_TrayWnd children
    hTaskList = FindWindowExW(hTaskbar, nullptr, L"ReBarWindow32", nullptr);
    hTaskList = FindWindowExW(hTaskList, nullptr, L"MSTaskSwWClass", nullptr);
    hTaskList = FindWindowExW(hTaskList, nullptr, L"MSTaskListWClass", nullptr);
  }
  if (!hTaskList)
    return results;

  // 2. Get UIA element for the task list
  IUIAutomationElement *pTaskList = nullptr;
  if (FAILED(g_pAutomation->ElementFromHandle(hTaskList, &pTaskList)) ||
      !pTaskList)
    return results;

  // 3. Create a condition to find all Button children
  IUIAutomationCondition *pButtonCond = nullptr;
  VARIANT varType;
  varType.vt = VT_I4;
  varType.lVal = UIA_ButtonControlTypeId;
  g_pAutomation->CreatePropertyCondition(UIA_ControlTypePropertyId, varType,
                                         &pButtonCond);

  IUIAutomationElementArray *pButtons = nullptr;
  pTaskList->FindAll(TreeScope_Descendants, pButtonCond, &pButtons);

  if (pButtons) {
    int count = 0;
    pButtons->get_Length(&count);

    for (int i = 0; i < count; i++) {
      IUIAutomationElement *pBtn = nullptr;
      pButtons->GetElement(i, &pBtn);
      if (!pBtn)
        continue;

      BSTR bstrName = nullptr;
      BSTR bstrHelp = nullptr;
      pBtn->get_CurrentName(&bstrName);
      pBtn->get_CurrentHelpText(&bstrHelp);

      // Get the native window handle this button represents
      VARIANT varHwnd;
      pBtn->GetCurrentPropertyValue(UIA_NativeWindowHandlePropertyId, &varHwnd);

      WindowData data;
      if (bstrName) {
        data.uiaName = bstrName;
        SysFreeString(bstrName);
      }
      if (bstrHelp) {
        data.helpText = bstrHelp;
        SysFreeString(bstrHelp);
      }

      VariantClear(&varHwnd);
      results.push_back(data);
      pBtn->Release();
    }
    pButtons->Release();
  }

  if (pButtonCond)
    pButtonCond->Release();
  pTaskList->Release();
  return results;
}

RECT GetFocusedElementRect() {
  IUIAutomation *pAutomation = nullptr;
  IUIAutomationElement *pFocusedElement = nullptr;
  RECT rect = {};

  CoInitialize(nullptr);
  CoCreateInstance(CLSID_CUIAutomation, nullptr, CLSCTX_INPROC_SERVER,
                   IID_IUIAutomation, (void **)&pAutomation);

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

// ------------------------------
// RECT validation (IMPORTANT FIX)
// ------------------------------
inline bool IsValidRect(const RECT &r) {
  if (r.right <= r.left)
    return false;
  if (r.bottom <= r.top)
    return false;

  // Reject only true empty rects, NOT (0,0) positions
  if (r.left == 0 && r.top == 0 && r.right == 0 && r.bottom == 0)
    return false;

  return true;
}

// ------------------------------
// SAFEARRAY -> RECT conversion (FIXED)
// ------------------------------
inline bool RectFromSafeArray(SAFEARRAY *pSA, RECT &out) {
  if (!pSA)
    return false;

  double *data = nullptr;
  if (FAILED(SafeArrayAccessData(pSA, reinterpret_cast<void **>(&data))))
    return false;

  long lb = 0, ub = 0;
  SafeArrayGetLBound(pSA, 1, &lb);
  SafeArrayGetUBound(pSA, 1, &ub);

  bool ok = false;

  if ((ub - lb + 1) >= 4) {
    // SAFEARRAY may not start at 0 → FIXED indexing
    // const long base = lb;

    double x = data[0];
    double y = data[1];
    double w = data[2];
    double h = data[3];

    out.left = static_cast<LONG>(x);
    out.top = static_cast<LONG>(y);
    out.right = static_cast<LONG>(x + w);
    out.bottom = static_cast<LONG>(y + h);

    ok = IsValidRect(out);
  }

  SafeArrayUnaccessData(pSA);
  return ok;
}
// ------------------------------
// Expand caret range safely
// ------------------------------
inline SAFEARRAY *BoundingRectsFromCaretRange(IUIAutomationTextRange *pRange) {
  if (!pRange)
    return nullptr;

  IUIAutomationTextRange *pExp = nullptr;
  if (FAILED(pRange->Clone(&pExp)) || !pExp)
    return nullptr;

  INT moved = 0;

  // Try expand forward
  pExp->MoveEndpointByUnit(TextPatternRangeEndpoint_End, TextUnit_Character, 1,
                           &moved);

  // If no movement, try backward
  if (moved == 0) {
    pExp->MoveEndpointByUnit(TextPatternRangeEndpoint_Start, TextUnit_Character,
                             -1, &moved);
  }

  SAFEARRAY *pSA = nullptr;
  HRESULT hr = pExp->GetBoundingRectangles(&pSA);

  pExp->Release();

  if (FAILED(hr))
    return nullptr;

  return pSA;
}

// ------------------------------
// Layer 1: Win32 caret
// ------------------------------
inline bool TryWin32Caret(RECT &out) {
  GUITHREADINFO gti = {};
  gti.cbSize = sizeof(gti);

  if (!GetGUIThreadInfo(0, &gti) || !gti.hwndCaret)
    return false;

  RECT rc = gti.rcCaret;

  POINT tl = {rc.left, rc.top};
  POINT br = {rc.right, rc.bottom};

  ClientToScreen(gti.hwndCaret, &tl);
  ClientToScreen(gti.hwndCaret, &br);

  out = {tl.x, tl.y, br.x, br.y};

  return IsValidRect(out);
}

// ------------------------------
// Layer 2: UIA CaretRange
// ------------------------------
inline bool TryUIACaretRange(IUIAutomationElement *pElem, RECT &out) {
  IUIAutomationTextPattern2 *pTP2 = nullptr;

  if (FAILED(pElem->GetCurrentPattern(UIA_TextPattern2Id,
                                      reinterpret_cast<IUnknown **>(&pTP2))) ||
      !pTP2)
    return false;

  BOOL isActive = FALSE;
  IUIAutomationTextRange *pRange = nullptr;

  HRESULT hr = pTP2->GetCaretRange(&isActive, &pRange);
  pTP2->Release();

  if (FAILED(hr) || !pRange)
    return false;

  SAFEARRAY *pSA = BoundingRectsFromCaretRange(pRange);
  pRange->Release();

  if (!pSA)
    return false;

  bool ok = RectFromSafeArray(pSA, out);
  SafeArrayDestroy(pSA);

  return ok;
}

// ------------------------------
// Layer 3: UIA Selection
// ------------------------------
inline bool TryUIASelection(IUIAutomationElement *pElem, RECT &out) {
  IUIAutomationTextPattern *pTP = nullptr;

  if (FAILED(pElem->GetCurrentPattern(UIA_TextPatternId,
                                      reinterpret_cast<IUnknown **>(&pTP))) ||
      !pTP)
    return false;

  IUIAutomationTextRangeArray *pSel = nullptr;
  HRESULT hr = pTP->GetSelection(&pSel);
  pTP->Release();

  if (FAILED(hr) || !pSel)
    return false;

  int count = 0;
  pSel->get_Length(&count);

  bool ok = false;

  if (count > 0) {
    IUIAutomationTextRange *pRange = nullptr;
    pSel->GetElement(0, &pRange);

    if (pRange) {
      SAFEARRAY *pSA = BoundingRectsFromCaretRange(pRange);
      pRange->Release();

      if (pSA) {
        ok = RectFromSafeArray(pSA, out);
        SafeArrayDestroy(pSA);
      }
    }
  }

  pSel->Release();
  return ok;
}

// ------------------------------
// Layer 4: IAccessible caret
// ------------------------------
inline bool TryAccessibleCaret(RECT &out) {
  HWND hwnd = GetForegroundWindow();
  if (!hwnd)
    return false;

  IAccessible *pAcc = nullptr;

  HRESULT hr = AccessibleObjectFromWindow(hwnd, static_cast<DWORD>(OBJID_CARET),
                                          IID_IAccessible,
                                          reinterpret_cast<void **>(&pAcc));

  if (FAILED(hr) || !pAcc)
    return false;

  VARIANT self;
  self.vt = VT_I4;
  self.lVal = CHILDID_SELF;

  LONG x = 0, y = 0, w = 0, h = 0;

  hr = pAcc->accLocation(&x, &y, &w, &h, self);
  pAcc->Release();

  if (FAILED(hr))
    return false;

  out = {x, y, x + w, y + h};

  return IsValidRect(out);
}

} // namespace detail

inline std::string GetModuleDirectoryFile(const char *filename) {
  char path[MAX_PATH];
  GetModuleFileNameA(nullptr, path, MAX_PATH);

  std::string s = path;

  size_t pos = s.find_last_of("\\/");
  if (pos != std::string::npos)
    s.resize(pos + 1);

  s += filename;
  return s;
}
// --------------------------------------------------
// FINAL PUBLIC API (FIXED LOGIC FLOW)
// --------------------------------------------------
inline RECT GetFocusedElementCaretRect() {
  RECT best = {};
  bool found = false;

  auto LogRect = [](const char *type, const RECT &r) {
    return;
    // std::ofstream f(GetModuleDirectoryFile("caret_debug.txt"),
    // std::ios::app); if (!f)
    //   return;

    // f << "[" << type << "] "
    //   << "[Rect l=" << r.left << " t=" << r.top << " r=" << r.right
    //   << " b=" << r.bottom << " w=" << (r.right - r.left)
    //   << " h=" << (r.bottom - r.top) << "]\n";
  };

  auto LogMiss = [](const char *type) {
    return;
    // std::ofstream f(GetModuleDirectoryFile("caret_debug.txt"),
    // std::ios::app); if (!f)
    //   return;

    // f << "[" << type << "] [Rect invalid]\n";
  };

  IUIAutomation *pAuto = nullptr;
  IUIAutomationElement *pElem = nullptr;

  CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  HRESULT hr =
      CoCreateInstance(CLSID_CUIAutomation, nullptr, CLSCTX_INPROC_SERVER,
                       IID_IUIAutomation, reinterpret_cast<void **>(&pAuto));

  if (SUCCEEDED(hr) && pAuto)
    pAuto->GetFocusedElement(&pElem);

  // -------------------------
  // PRIORITY 1: Win32 caret
  // -------------------------
  {
    RECT tmp{};
    if (detail::TryWin32Caret(tmp) && detail::IsValidRect(tmp)) {
      LogRect("Win32Caret", tmp);

      if (!found) {
        best = tmp;
        found = true;
      }
    } else {
      LogMiss("Win32Caret");
    }
  }

  {
    RECT tmp{};
    if (detail::TryAccessibleCaret(tmp) && detail::IsValidRect(tmp)) {
      LogRect("AccessibleCaret", tmp);

      if (!found) {
        best = tmp;
        found = true;
      }
    } else {
      LogMiss("AccessibleCaret");
    }
  }
  // -------------------------
  // PRIORITY 2: UIA caret range
  // -------------------------
  if (pElem) {
    RECT tmp{};
    if (detail::TryUIACaretRange(pElem, tmp) && detail::IsValidRect(tmp)) {
      LogRect("UIACaretRange", tmp);

      if (!found) {
        best = tmp;
        found = true;
      }
    } else {
      LogMiss("UIACaretRange");
    }
  }

  // -------------------------
  // PRIORITY 3: UIA selection
  // -------------------------
  if (pElem) {
    RECT tmp{};
    if (detail::TryUIASelection(pElem, tmp) && detail::IsValidRect(tmp)) {
      LogRect("UIASelection", tmp);

      if (!found) {
        best = tmp;
        found = true;
      }
    } else {
      LogMiss("UIASelection");
    }
  }

  // -------------------------
  // PRIORITY 4: IAccessible
  // -------------------------

  // -------------------------
  // PRIORITY 5: UIA bounding rect
  // -------------------------
  if (pElem) {
    RECT tmp{};
    if (SUCCEEDED(pElem->get_CurrentBoundingRectangle(&tmp)) &&
        detail::IsValidRect(tmp)) {
      LogRect("UIABoundingRect", tmp);

      if (!found) {
        best = tmp;
        found = true;
      }
    } else {
      LogMiss("UIABoundingRect");
    }
  }

  if (pElem)
    pElem->Release();

  if (pAuto)
    pAuto->Release();

  CoUninitialize();

  return found ? best : RECT{0, 0, 0, 0};
}
