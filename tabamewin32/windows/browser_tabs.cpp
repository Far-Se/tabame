#pragma once

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif

#include <algorithm>
#include <string>
#include <uiautomation.h>
#include <unordered_map>
#include <vector>
#include <windows.h>

#pragma comment(lib, "uiautomationcore.lib")

// ---------------------------------------------------------------------------
// Browser tab enumeration / activation via UI Automation.
//
// Chromium based browsers (Chrome, Edge, Brave, Opera, ...) expose their tab
// strip through UIA as a `Tab` control whose children are `TabItem` controls,
// each named with the page title. The tab strip is part of the browser chrome,
// so it is exposed even when full document accessibility is disabled — which
// keeps this enumeration cheap (we never walk the page content tree).
// ---------------------------------------------------------------------------

struct BrowserTab {
  std::wstring browser; // Friendly browser name (e.g. "Chrome").
  int hwnd;             // Top-level browser window handle.
  int index;            // Position of the TabItem within the strip.
  std::wstring title;   // Tab/page title.
};

// Map a process executable basename (lowercased) to a Chromium browser name.
static std::wstring ChromiumBrowserNameFromExe(const std::wstring &exeLower) {
  static const std::unordered_map<std::wstring, std::wstring> kBrowsers = {
      {L"chrome.exe", L"Chrome"},   {L"msedge.exe", L"Edge"},
      {L"brave.exe", L"Brave"},     {L"opera.exe", L"Opera"},
      {L"opera_gx.exe", L"Opera GX"}, {L"vivaldi.exe", L"Vivaldi"},
  };
  auto it = kBrowsers.find(exeLower);
  return it == kBrowsers.end() ? std::wstring() : it->second;
}

static std::wstring GetProcessExeBasenameLower(DWORD pid) {
  std::wstring result;
  HANDLE h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (!h)
    return result;
  wchar_t path[MAX_PATH];
  DWORD size = MAX_PATH;
  if (QueryFullProcessImageNameW(h, 0, path, &size)) {
    std::wstring full(path, size);
    size_t pos = full.find_last_of(L"\\/");
    result = (pos == std::wstring::npos) ? full : full.substr(pos + 1);
    std::transform(result.begin(), result.end(), result.begin(), ::towlower);
  }
  CloseHandle(h);
  return result;
}

struct BrowserWindowRef {
  HWND hwnd;
  std::wstring browser;
};

static BOOL CALLBACK CollectBrowserWindowsProc(HWND hwnd, LPARAM lParam) {
  auto *out = reinterpret_cast<std::vector<BrowserWindowRef> *>(lParam);
  if (!IsWindowVisible(hwnd))
    return TRUE;
  if (GetWindow(hwnd, GW_OWNER) != nullptr)
    return TRUE; // Skip owned popups/dialogs.
  LONG exStyle = GetWindowLongW(hwnd, GWL_EXSTYLE);
  if (exStyle & WS_EX_TOOLWINDOW)
    return TRUE;
  if (GetWindowTextLengthW(hwnd) == 0)
    return TRUE;

  DWORD pid = 0;
  GetWindowThreadProcessId(hwnd, &pid);
  if (!pid)
    return TRUE;

  std::wstring browser = ChromiumBrowserNameFromExe(GetProcessExeBasenameLower(pid));
  if (browser.empty())
    return TRUE;

  out->push_back({hwnd, browser});
  return TRUE;
}

// Locate the tab strip (`Tab` control) inside a browser window so that the
// subsequent TabItem search stays scoped and fast. Returns the window root as a
// fallback when the strip cannot be isolated. Caller owns the returned scope
// reference only when *scopeOut is set.
static IUIAutomationElement *
ScopeToTabStrip(IUIAutomation *automation, IUIAutomationElement *root,
                IUIAutomationElement **scopeOut) {
  *scopeOut = nullptr;
  VARIANT vTab;
  vTab.vt = VT_I4;
  vTab.lVal = UIA_TabControlTypeId;
  IUIAutomationCondition *tabCond = nullptr;
  if (SUCCEEDED(automation->CreatePropertyCondition(UIA_ControlTypePropertyId,
                                                    vTab, &tabCond)) &&
      tabCond) {
    root->FindFirst(TreeScope_Descendants, tabCond, scopeOut);
    tabCond->Release();
  }
  return *scopeOut ? *scopeOut : root;
}

static IUIAutomationElementArray *FindTabItems(IUIAutomation *automation,
                                               IUIAutomationElement *searchRoot) {
  VARIANT vTabItem;
  vTabItem.vt = VT_I4;
  vTabItem.lVal = UIA_TabItemControlTypeId;
  IUIAutomationCondition *cond = nullptr;
  IUIAutomationElementArray *items = nullptr;
  if (SUCCEEDED(automation->CreatePropertyCondition(UIA_ControlTypePropertyId,
                                                    vTabItem, &cond)) &&
      cond) {
    searchRoot->FindAll(TreeScope_Descendants, cond, &items);
    cond->Release();
  }
  return items;
}

std::vector<BrowserTab> EnumerateBrowserTabs() {
  std::vector<BrowserTab> tabs;

  std::vector<BrowserWindowRef> windows;
  EnumWindows(CollectBrowserWindowsProc, reinterpret_cast<LPARAM>(&windows));
  if (windows.empty())
    return tabs;

  IUIAutomation *automation = nullptr;
  if (FAILED(CoCreateInstance(CLSID_CUIAutomation, nullptr,
                              CLSCTX_INPROC_SERVER, IID_IUIAutomation,
                              reinterpret_cast<void **>(&automation))) ||
      !automation)
    return tabs;

  for (const auto &bw : windows) {
    IUIAutomationElement *root = nullptr;
    if (FAILED(automation->ElementFromHandle(bw.hwnd, &root)) || !root)
      continue;

    IUIAutomationElement *scope = nullptr;
    IUIAutomationElement *searchRoot = ScopeToTabStrip(automation, root, &scope);

    IUIAutomationElementArray *items = FindTabItems(automation, searchRoot);
    if (items) {
      int count = 0;
      items->get_Length(&count);
      for (int i = 0; i < count; i++) {
        IUIAutomationElement *item = nullptr;
        items->GetElement(i, &item);
        if (!item)
          continue;
        BSTR name = nullptr;
        item->get_CurrentName(&name);
        std::wstring title = name ? name : L"";
        if (name)
          SysFreeString(name);
        item->Release();
        // The trailing "+" / new-tab affordance can surface as a nameless
        // TabItem — skip empties, but keep the real array index `i` so that
        // activation re-selects the correct element.
        if (!title.empty())
          tabs.push_back({bw.browser,
                          static_cast<int>(reinterpret_cast<LONG_PTR>(bw.hwnd)),
                          i, title});
      }
      items->Release();
    }

    if (scope)
      scope->Release();
    root->Release();
  }

  automation->Release();
  return tabs;
}

static bool SelectTabItem(IUIAutomationElement *item) {
  if (!item)
    return false;

  IUIAutomationSelectionItemPattern *sel = nullptr;
  if (SUCCEEDED(item->GetCurrentPatternAs(UIA_SelectionItemPatternId,
                                          IID_PPV_ARGS(&sel))) &&
      sel) {
    HRESULT hr = sel->Select();
    sel->Release();
    if (SUCCEEDED(hr))
      return true;
  }

  IUIAutomationLegacyIAccessiblePattern *legacy = nullptr;
  if (SUCCEEDED(item->GetCurrentPatternAs(UIA_LegacyIAccessiblePatternId,
                                          IID_PPV_ARGS(&legacy))) &&
      legacy) {
    HRESULT hr = legacy->DoDefaultAction();
    legacy->Release();
    if (SUCCEEDED(hr))
      return true;
  }

  IUIAutomationInvokePattern *invoke = nullptr;
  if (SUCCEEDED(item->GetCurrentPatternAs(UIA_InvokePatternId,
                                          IID_PPV_ARGS(&invoke))) &&
      invoke) {
    HRESULT hr = invoke->Invoke();
    invoke->Release();
    if (SUCCEEDED(hr))
      return true;
  }

  return false;
}

static std::wstring TabItemName(IUIAutomationElement *item) {
  BSTR name = nullptr;
  item->get_CurrentName(&name);
  std::wstring out = name ? name : L"";
  if (name)
    SysFreeString(name);
  return out;
}

// Bring the browser window forward and switch to the requested tab. The tab is
// resolved by index first (verified against the title to survive minor tab-bar
// changes) and falls back to a title match, then to the bare index.
bool FocusBrowserTab(int hwndValue, int index, const std::wstring &title) {
  HWND hwnd = reinterpret_cast<HWND>(static_cast<LONG_PTR>(hwndValue));
  if (!IsWindow(hwnd))
    return false;

  if (IsIconic(hwnd))
    ShowWindow(hwnd, SW_RESTORE);
  SetForegroundWindow(hwnd);

  IUIAutomation *automation = nullptr;
  if (FAILED(CoCreateInstance(CLSID_CUIAutomation, nullptr,
                              CLSCTX_INPROC_SERVER, IID_IUIAutomation,
                              reinterpret_cast<void **>(&automation))) ||
      !automation)
    return false;

  bool ok = false;
  IUIAutomationElement *root = nullptr;
  if (SUCCEEDED(automation->ElementFromHandle(hwnd, &root)) && root) {
    IUIAutomationElement *scope = nullptr;
    IUIAutomationElement *searchRoot = ScopeToTabStrip(automation, root, &scope);
    IUIAutomationElementArray *items = FindTabItems(automation, searchRoot);

    if (items) {
      int count = 0;
      items->get_Length(&count);
      IUIAutomationElement *target = nullptr;

      // Preferred: exact index, confirmed by title when one was supplied.
      if (index >= 0 && index < count) {
        IUIAutomationElement *cand = nullptr;
        items->GetElement(index, &cand);
        if (cand) {
          if (title.empty() || TabItemName(cand) == title)
            target = cand;
          else
            cand->Release();
        }
      }

      // Fallback: first tab whose title matches.
      if (!target && !title.empty()) {
        for (int i = 0; i < count; i++) {
          IUIAutomationElement *cand = nullptr;
          items->GetElement(i, &cand);
          if (!cand)
            continue;
          if (TabItemName(cand) == title) {
            target = cand;
            break;
          }
          cand->Release();
        }
      }

      // Last resort: the index even if the title drifted.
      if (!target && index >= 0 && index < count)
        items->GetElement(index, &target);

      if (target) {
        ok = SelectTabItem(target);
        target->Release();
      }
      items->Release();
    }

    if (scope)
      scope->Release();
    root->Release();
  }

  automation->Release();
  return ok;
}
