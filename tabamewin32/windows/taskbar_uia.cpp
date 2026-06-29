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
#include <imm.h>
#include <iostream>
#include <objbase.h>
#include <oleacc.h>
#include <string>
#include <uiautomation.h>
#include <vector>
#include <windows.h>

#include "include/encoding.h"
// Link necessary libraries
#pragma comment(lib, "dwmapi.lib")
#pragma comment(lib, "Ole32.lib")
#pragma comment(lib, "OleAut32.lib")
#pragma comment(lib, "uiautomationcore.lib")
#pragma comment(lib, "imm32.lib")

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

// ------------------------------
// Layer 5: IME composition window
// ------------------------------
// Reports the position the active IME (or the system's own Win+. emoji
// panel) uses for the composition caret. Most useful exactly when the other
// layers are flaky: text fields mid-composition (CJK input, some browser
// omniboxes/search boxes) where UIA/MSAA caret patterns are absent or stale.
inline bool TryImeCompositionCaret(RECT &out) {
  GUITHREADINFO gti = {};
  gti.cbSize = sizeof(gti);

  if (!GetGUIThreadInfo(0, &gti))
    return false;

  HWND hTarget = gti.hwndFocus ? gti.hwndFocus : gti.hwndActive;
  if (!hTarget)
    return false;

  HIMC himc = ImmGetContext(hTarget);
  if (!himc)
    return false;

  COMPOSITIONFORM cf = {};
  BOOL ok = ImmGetCompositionWindow(himc, &cf);
  ImmReleaseContext(hTarget, himc);

  // dwStyle == 0 means the IME never set a composition position; the point
  // is meaningless in that case.
  if (!ok || cf.dwStyle == 0)
    return false;

  POINT pt = {cf.ptCurrentPos.x, cf.ptCurrentPos.y};
  ClientToScreen(hTarget, &pt);

  // The IME only reports a point, not an extent; synthesize a thin caret
  // rect around it so it behaves like the other layers downstream.
  out = {pt.x, pt.y, pt.x + 1, pt.y + 18};

  return IsValidRect(out);
}

// ------------------------------
// Layer 6: IME candidate window
// ------------------------------
// ImmGetCompositionWindow (above) and ImmGetCandidateWindow are two
// *separate* IMM32 channels: composition is "where typed-but-not-committed
// text appears", candidate is "where the IME's popup UI (candidate list,
// and by extension the system emoji/IME panel) should anchor". Apps that
// never go through real CJK composition - but still want Win+. / IME popups
// positioned correctly - set ONLY the candidate position via
// ImmSetCandidateWindow (this is exactly what cross-platform toolkits like
// winit's set_ime_cursor_area do under the hood on Windows, which GPUI-based
// editors such as Zed are built on). This is almost certainly why apps like
// Zed get a correctly-placed native emoji panel while exposing nothing to
// UIA/MSAA/IMM-composition: they only ever populate this channel.
inline bool TryImeCandidateCaret(RECT &out) {
  GUITHREADINFO gti = {};
  gti.cbSize = sizeof(gti);

  if (!GetGUIThreadInfo(0, &gti))
    return false;

  HWND hTarget = gti.hwndFocus ? gti.hwndFocus : gti.hwndActive;
  if (!hTarget)
    return false;

  HIMC himc = ImmGetContext(hTarget);
  if (!himc)
    return false;

  // Index 0 is the primary/default candidate window slot used for simple
  // single-position anchoring (as opposed to per-candidate-row slots 1-3).
  CANDIDATEFORM cf = {};
  BOOL ok = ImmGetCandidateWindow(himc, 0, &cf);
  ImmReleaseContext(hTarget, himc);

  if (!ok)
    return false;

  if (cf.dwStyle & CFS_CANDIDATEPOS) {
    POINT pt = {cf.ptCurrentPos.x, cf.ptCurrentPos.y};
    ClientToScreen(hTarget, &pt);
    out = {pt.x, pt.y, pt.x + 1, pt.y + 18};
  } else if (cf.dwStyle & CFS_EXCLUDE) {
    POINT tl = {cf.rcArea.left, cf.rcArea.top};
    POINT br = {cf.rcArea.right, cf.rcArea.bottom};
    ClientToScreen(hTarget, &tl);
    ClientToScreen(hTarget, &br);
    out = {tl.x, tl.y, br.x, br.y};
  } else {
    return false;
  }

  return IsValidRect(out);
}

// ------------------------------
// Heuristic: is this "bounding rect" actually just the whole window?
// ------------------------------
// Apps that implement no accessibility API at all (custom-rendered editors
// like Zed/GPUI, many games, some Electron/GPU canvases) still get a
// generic UIA "Pane" element for their top-level HWND for free, courtesy of
// UIAutomationCore's default window provider. Its bounding rect is just the
// window's rect - not a caret position. Treating that as a real result is
// worse than having no result, since the caller (e.g. the emoji picker) can
// fall back to the mouse cursor position instead, which is far closer.
inline bool LooksLikeWholeWindowFallback(const RECT &candidate) {
  HWND hwnd = GetForegroundWindow();
  if (!hwnd)
    return false;

  RECT wndRect = {};
  if (!GetWindowRect(hwnd, &wndRect))
    return false;

  const long wndW = wndRect.right - wndRect.left;
  const long wndH = wndRect.bottom - wndRect.top;
  if (wndW <= 0 || wndH <= 0)
    return false;

  const long candW = candidate.right - candidate.left;
  const long candH = candidate.bottom - candidate.top;

  // A real caret/small-control rect is a tiny fraction of the window; a
  // generic passthrough rect covers most/all of it.
  return candW >= wndW / 2 && candH >= wndH / 2;
}

// ------------------------------
// Best-effort human name for a UIA control type id, for diagnostics only.
// ------------------------------
inline std::string ControlTypeIdToName(long id) {
  switch (id) {
  case UIA_ButtonControlTypeId:
    return "Button";
  case UIA_EditControlTypeId:
    return "Edit";
  case UIA_DocumentControlTypeId:
    return "Document";
  case UIA_TextControlTypeId:
    return "Text";
  case UIA_PaneControlTypeId:
    return "Pane";
  case UIA_WindowControlTypeId:
    return "Window";
  case UIA_CustomControlTypeId:
    return "Custom";
  case UIA_GroupControlTypeId:
    return "Group";
  case UIA_ComboBoxControlTypeId:
    return "ComboBox";
  default:
    return "Unknown(" + std::to_string(id) + ")";
  }
}

} // namespace detail

// --------------------------------------------------
// Diagnostics: per-layer breakdown
// --------------------------------------------------
// One result per detection strategy, so callers (e.g. a debug overlay) can
// see exactly which layer fired and with what numbers, instead of only the
// first/best rect. Useful when an app's caret position comes out wrong or
// jumps around: you can tell at a glance which layer is lying.
struct CaretLayerResult {
  bool found = false;
  RECT rect = {};
};

struct CaretDebugResult {
  CaretLayerResult win32Caret;       // GetGUIThreadInfo().rcCaret
  CaretLayerResult accessibleCaret;  // IAccessible OBJID_CARET
  CaretLayerResult uiaCaretRange;    // UIA TextPattern2.GetCaretRange
  CaretLayerResult uiaSelection;     // UIA TextPattern.GetSelection
  CaretLayerResult imeCandidate;     // IMM ImmGetCandidateWindow (CFS_CANDIDATEPOS/CFS_EXCLUDE)
  CaretLayerResult imeComposition;   // IMM ImmGetCompositionWindow
  CaretLayerResult uiaBoundingRect;  // UIA focused element bounding rect (fallback)

  std::string chosenLayer; // name of the layer that supplied `best`, or "" if none
  RECT best = {};
  bool found = false;

  // Diagnostics about whatever UIA's GetFocusedElement() actually returned,
  // regardless of whether any caret layer fired. When every layer above
  // reports "not found", this tells you *why*: e.g. an app with no
  // accessibility support shows up as a bare Pane/Window with none of the
  // patterns set, which is the generic passthrough every HWND gets for free.
  bool hasFocusedElement = false;
  std::string elementName;
  std::string elementClassName;
  std::string elementControlType; // human-readable, e.g. "Pane", "Edit"
  bool supportsTextPattern = false;
  bool supportsTextPattern2 = false;
  bool supportsValuePattern = false;
  bool supportsLegacyIAccessible = false;
};

inline CaretDebugResult GetFocusedElementCaretRectDetailed() {
  CaretDebugResult dbg;

  auto consider = [&dbg](const char *name, CaretLayerResult &layer) {
    if (layer.found && !dbg.found) {
      dbg.best = layer.rect;
      dbg.found = true;
      dbg.chosenLayer = name;
    }
  };

  IUIAutomation *pAuto = nullptr;
  IUIAutomationElement *pElem = nullptr;

  CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  HRESULT hr =
      CoCreateInstance(CLSID_CUIAutomation, nullptr, CLSCTX_INPROC_SERVER,
                       IID_IUIAutomation, reinterpret_cast<void **>(&pAuto));

  if (SUCCEEDED(hr) && pAuto)
    pAuto->GetFocusedElement(&pElem);

  if (pElem) {
    dbg.hasFocusedElement = true;

    BSTR bstrName = nullptr;
    if (SUCCEEDED(pElem->get_CurrentName(&bstrName)) && bstrName) {
      dbg.elementName = Encoding::WideToUtf8(std::wstring(bstrName, SysStringLen(bstrName)));
      SysFreeString(bstrName);
    }

    BSTR bstrClass = nullptr;
    if (SUCCEEDED(pElem->get_CurrentClassName(&bstrClass)) && bstrClass) {
      dbg.elementClassName = Encoding::WideToUtf8(std::wstring(bstrClass, SysStringLen(bstrClass)));
      SysFreeString(bstrClass);
    }

    CONTROLTYPEID controlTypeId = 0;
    if (SUCCEEDED(pElem->get_CurrentControlType(&controlTypeId)))
      dbg.elementControlType = detail::ControlTypeIdToName(controlTypeId);

    IUnknown *pPattern = nullptr;
    if (SUCCEEDED(pElem->GetCurrentPattern(UIA_TextPatternId, &pPattern)) && pPattern) {
      dbg.supportsTextPattern = true;
      pPattern->Release();
      pPattern = nullptr;
    }
    if (SUCCEEDED(pElem->GetCurrentPattern(UIA_TextPattern2Id, &pPattern)) && pPattern) {
      dbg.supportsTextPattern2 = true;
      pPattern->Release();
      pPattern = nullptr;
    }
    if (SUCCEEDED(pElem->GetCurrentPattern(UIA_ValuePatternId, &pPattern)) && pPattern) {
      dbg.supportsValuePattern = true;
      pPattern->Release();
      pPattern = nullptr;
    }
    if (SUCCEEDED(pElem->GetCurrentPattern(UIA_LegacyIAccessiblePatternId, &pPattern)) && pPattern) {
      dbg.supportsLegacyIAccessible = true;
      pPattern->Release();
      pPattern = nullptr;
    }
  }

  // PRIORITY 1: Win32 caret
  dbg.win32Caret.found =
      detail::TryWin32Caret(dbg.win32Caret.rect) && detail::IsValidRect(dbg.win32Caret.rect);
  consider("Win32Caret", dbg.win32Caret);

  // PRIORITY 2: IAccessible caret
  dbg.accessibleCaret.found = detail::TryAccessibleCaret(dbg.accessibleCaret.rect) &&
                              detail::IsValidRect(dbg.accessibleCaret.rect);
  consider("AccessibleCaret", dbg.accessibleCaret);

  // PRIORITY 3: UIA caret range
  if (pElem) {
    dbg.uiaCaretRange.found = detail::TryUIACaretRange(pElem, dbg.uiaCaretRange.rect) &&
                              detail::IsValidRect(dbg.uiaCaretRange.rect);
    consider("UIACaretRange", dbg.uiaCaretRange);
  }

  // PRIORITY 4: UIA selection
  if (pElem) {
    dbg.uiaSelection.found = detail::TryUIASelection(pElem, dbg.uiaSelection.rect) &&
                             detail::IsValidRect(dbg.uiaSelection.rect);
    consider("UIASelection", dbg.uiaSelection);
  }

  // PRIORITY 5: IME candidate window (popup-anchor channel; see TryImeCandidateCaret)
  dbg.imeCandidate.found = detail::TryImeCandidateCaret(dbg.imeCandidate.rect) &&
                           detail::IsValidRect(dbg.imeCandidate.rect);
  consider("ImeCandidate", dbg.imeCandidate);

  // PRIORITY 6: IME composition window
  dbg.imeComposition.found = detail::TryImeCompositionCaret(dbg.imeComposition.rect) &&
                             detail::IsValidRect(dbg.imeComposition.rect);
  consider("ImeComposition", dbg.imeComposition);

  // PRIORITY 7: UIA bounding rect (whole-element fallback, least precise)
  if (pElem) {
    dbg.uiaBoundingRect.found =
        SUCCEEDED(pElem->get_CurrentBoundingRectangle(&dbg.uiaBoundingRect.rect)) &&
        detail::IsValidRect(dbg.uiaBoundingRect.rect);

    // Report the real numbers either way (for diagnostics), but don't let
    // it win "best" if it's just the generic whole-window passthrough -
    // see LooksLikeWholeWindowFallback for why.
    if (dbg.uiaBoundingRect.found &&
        !detail::LooksLikeWholeWindowFallback(dbg.uiaBoundingRect.rect)) {
      consider("UIABoundingRect", dbg.uiaBoundingRect);
    }
  }

  if (pElem)
    pElem->Release();
  if (pAuto)
    pAuto->Release();

  CoUninitialize();

  return dbg;
}

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
  const CaretDebugResult dbg = GetFocusedElementCaretRectDetailed();
  return dbg.found ? dbg.best : RECT{0, 0, 0, 0};
}
