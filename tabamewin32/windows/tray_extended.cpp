// tray_extended.cpp
//
// Extended system tray enumeration + UIA-based click automation.
//
// Click strategy (why not PostMessage):
//   - PostMessage(WM_LBUTTONDOWN) works for Win32 apps but is ignored by
//     Qt, Electron, and Appx/UWP tray icons.
//   - UIA InvokePattern::Invoke() goes through the accessibility bus and
//     works for all framework types including Qt and packaged apps.
//   - Right/middle clicks have no UIA pattern; we resolve the element's
//     screen rect via UIA and deliver a real SendInput event to that point.
//
// Exported surface:
//   struct ExtTrayIcon { toolTip, processId, appHwnd, uID, uCallbackMsg,
//                        hIcon, isVisible, isOverflow }
//   std::vector<ExtTrayIcon> EnumAllTrayIcons()
//   bool ClickTrayIconUia(toolTip, isOverflow, clickType)
//       clickType: 0=left, 1=right, 2=middle, 3=double-left

#pragma once
#ifndef UNICODE
#define UNICODE
#endif

#include <windows.h>
#include <commctrl.h>
#include <psapi.h>
#include <uiautomation.h>
#pragma comment(lib, "uiautomationcore.lib")
#pragma comment(lib, "comctl32.lib")

#include <string>
#include <vector>

#include "include/encoding.h"

// ─── Data type ────────────────────────────────────────────────────────────────

struct ExtTrayIcon
{
    std::wstring toolTip;
    int          processId   = 0;
    HWND         appHwnd     = nullptr;
    UINT         uID         = 0;
    UINT         uCallbackMsg = 0;
    HICON        hIcon       = nullptr; // GDI handle — pass int to getIconPng() on Dart side
    bool         isVisible   = false;
    bool         isOverflow  = false;
};

// ─── Tray toolbar reader ──────────────────────────────────────────────────────

static void ReadTrayToolbar(HWND toolbarWnd, bool isOverflow,
                            std::vector<ExtTrayIcon>& out)
{
    if (!toolbarWnd) return;

    DWORD dwPid = 0;
    GetWindowThreadProcessId(toolbarWnd, &dwPid);
    if (!dwPid) return;

    HANDLE hProc = OpenProcess(PROCESS_VM_READ | PROCESS_VM_OPERATION |
                               PROCESS_QUERY_INFORMATION, FALSE, dwPid);
    if (!hProc) return;

    int count = static_cast<int>(SendMessage(toolbarWnd, TB_BUTTONCOUNT, 0, 0));
    if (count <= 0) { CloseHandle(hProc); return; }

    LPVOID pRemote = VirtualAllocEx(hProc, nullptr, sizeof(TBBUTTON),
                                    MEM_COMMIT, PAGE_READWRITE);
    if (!pRemote) { CloseHandle(hProc); return; }

    // Mirror of the internal TRAYDATA structure used by Explorer.
    struct TRAYDATA_LOCAL {
        HWND hwnd;
        UINT uID;
        UINT uCallbackMessage;
        DWORD Reserved[2];
        HICON hIcon;
    };

    for (int i = 0; i < count; ++i)
    {
        SendMessage(toolbarWnd, TB_GETBUTTON, i, reinterpret_cast<LPARAM>(pRemote));

        TBBUTTON tbb{};
        if (!ReadProcessMemory(hProc, pRemote, &tbb, sizeof(tbb), nullptr))
            continue;

        TRAYDATA_LOCAL td{};
        if (!ReadProcessMemory(hProc, reinterpret_cast<LPCVOID>(tbb.dwData),
                               &td, sizeof(td), nullptr))
            continue;

        ExtTrayIcon icon;
        icon.isOverflow = isOverflow;
        icon.isVisible  = !(tbb.fsState & TBSTATE_HIDDEN);

        // Tooltip — read for ALL icons (visible and hidden)
        {
            wchar_t tip[1024]{};
            wchar_t* pTip = reinterpret_cast<wchar_t*>(tbb.iString);
            for (int x = 0; x < 1023; ++x)
            {
                wchar_t ch{};
                if (!ReadProcessMemory(hProc, pTip + x, &ch, sizeof(wchar_t), nullptr))
                    break;
                if (!ch) break;
                tip[x] = ch;
            }
            icon.toolTip = tip;
        }

        icon.appHwnd      = td.hwnd;
        icon.uID          = td.uID;
        icon.uCallbackMsg = td.uCallbackMessage;
        icon.hIcon        = td.hIcon; // GDI handles are kernel-global — valid cross-process

        DWORD appPid = 0;
        if (td.hwnd) GetWindowThreadProcessId(td.hwnd, &appPid);
        icon.processId = static_cast<int>(appPid);

        out.push_back(std::move(icon));
    }

    VirtualFreeEx(hProc, pRemote, 0, MEM_RELEASE);
    CloseHandle(hProc);
}

// ─── Public API — enumeration ─────────────────────────────────────────────────

std::vector<ExtTrayIcon> EnumAllTrayIcons()
{
    std::vector<ExtTrayIcon> result;

    // 1. Main tray
    HWND mainTray = FindWindowW(L"Shell_TrayWnd", nullptr);
    if (mainTray)
    {
        HWND notify  = FindWindowExW(mainTray, nullptr, L"TrayNotifyWnd",   nullptr);
        HWND pager   = FindWindowExW(notify,   nullptr, L"SysPager",        nullptr);
        HWND toolbar = FindWindowExW(pager,    nullptr, L"ToolbarWindow32", nullptr);
        ReadTrayToolbar(toolbar, false, result);
    }

    // 2. Overflow / hidden-icons tray
    HWND overflowWnd = FindWindowW(L"NotifyIconOverflowWindow", nullptr);
    if (overflowWnd)
    {
        HWND toolbar = FindWindowExW(overflowWnd, nullptr, L"ToolbarWindow32", nullptr);
        ReadTrayToolbar(toolbar, true, result);
    }

    return result;
}

// ─── UIA helpers ─────────────────────────────────────────────────────────────

// Find the tray toolbar ToolbarWindow32 HWND for the given tray type.
static HWND GetTrayToolbarHwnd(bool overflow)
{
    if (overflow)
    {
        HWND ow = FindWindowW(L"NotifyIconOverflowWindow", nullptr);
        return ow ? FindWindowExW(ow, nullptr, L"ToolbarWindow32", nullptr) : nullptr;
    }
    HWND main   = FindWindowW(L"Shell_TrayWnd", nullptr);
    HWND notify = main ? FindWindowExW(main,   nullptr, L"TrayNotifyWnd",   nullptr) : nullptr;
    HWND pager  = notify ? FindWindowExW(notify, nullptr, L"SysPager",      nullptr) : nullptr;
    return pager ? FindWindowExW(pager, nullptr, L"ToolbarWindow32", nullptr) : nullptr;
}

// Find the UIA button element whose Name matches tipName inside toolbarHwnd.
// Caller owns the returned element (must Release()).
static IUIAutomationElement* FindTrayButtonByName(
    IUIAutomation* pAuto, HWND toolbarHwnd, const std::wstring& tipName)
{
    if (!toolbarHwnd || !pAuto) return nullptr;

    IUIAutomationElement* pToolbar = nullptr;
    if (FAILED(pAuto->ElementFromHandle(toolbarHwnd, &pToolbar)) || !pToolbar)
        return nullptr;

    // Build a condition: ControlType==Button AND Name==tipName
    VARIANT vtType;
    VariantInit(&vtType);
    vtType.vt   = VT_I4;
    vtType.lVal = UIA_ButtonControlTypeId;
    IUIAutomationCondition* pTypeCond = nullptr;
    pAuto->CreatePropertyCondition(UIA_ControlTypePropertyId, vtType, &pTypeCond);
    VariantClear(&vtType);

    VARIANT vtName;
    VariantInit(&vtName);
    vtName.vt      = VT_BSTR;
    vtName.bstrVal = SysAllocString(tipName.c_str());
    IUIAutomationCondition* pNameCond = nullptr;
    pAuto->CreatePropertyCondition(UIA_NamePropertyId, vtName, &pNameCond);
    VariantClear(&vtName);

    IUIAutomationCondition* pAnd = nullptr;
    pAuto->CreateAndCondition(pTypeCond, pNameCond, &pAnd);
    if (pTypeCond) pTypeCond->Release();
    if (pNameCond) pNameCond->Release();

    IUIAutomationElement* pBtn = nullptr;
    if (pAnd)
    {
        pToolbar->FindFirst(TreeScope_Children, pAnd, &pBtn);
        pAnd->Release();
    }

    pToolbar->Release();
    return pBtn;
}

// ─── Public API — UIA click ───────────────────────────────────────────────────

/// Clicks a tray icon via UIAutomation — no mouse movement required.
///
/// clickType: 0=left, 1=right, 2=middle, 3=double-left
///
/// Left / double: IUIAutomationInvokePattern::Invoke() — works for all
///   framework types (Win32, Qt, Electron, Appx/UWP).
///
/// Right / middle: element's bounding rect is resolved via UIA, then
///   SendInput delivers a real mouse event to that screen point.  This
///   requires the element to have valid screen coordinates (i.e. the tray
///   area must be accessible — the overflow window is a real window even
///   if the taskbar is auto-hidden, so overflow icons can always be reached
///   this way; main-tray icons may require the taskbar to be visible).
bool ClickTrayIconUia(const std::wstring& tipName, bool preferOverflow, int clickType)
{
    IUIAutomation* pAuto = nullptr;
    HRESULT hr = CoCreateInstance(__uuidof(CUIAutomation8), nullptr, CLSCTX_INPROC_SERVER,
                                  __uuidof(IUIAutomation), reinterpret_cast<void**>(&pAuto));
    if (FAILED(hr) || !pAuto)
    {
        hr = CoCreateInstance(__uuidof(CUIAutomation), nullptr, CLSCTX_INPROC_SERVER,
                              __uuidof(IUIAutomation), reinterpret_cast<void**>(&pAuto));
    }
    if (FAILED(hr) || !pAuto) return false;

    // Search preferred tray first, then fall back to the other one.
    IUIAutomationElement* pBtn = nullptr;
    {
        HWND h1 = GetTrayToolbarHwnd(preferOverflow);
        pBtn = FindTrayButtonByName(pAuto, h1, tipName);

        if (!pBtn)
        {
            HWND h2 = GetTrayToolbarHwnd(!preferOverflow);
            pBtn = FindTrayButtonByName(pAuto, h2, tipName);
        }
    }

    if (!pBtn) { pAuto->Release(); return false; }

    bool ok = false;

    if (clickType == 0 || clickType == 3) // left / double — use InvokePattern
    {
        IUnknown* pRaw = nullptr;
        pBtn->GetCurrentPattern(UIA_InvokePatternId, &pRaw);
        if (pRaw)
        {
            IUIAutomationInvokePattern* pInvoke = nullptr;
            if (SUCCEEDED(pRaw->QueryInterface(__uuidof(IUIAutomationInvokePattern),
                                                reinterpret_cast<void**>(&pInvoke))) && pInvoke)
            {
                pInvoke->Invoke();
                if (clickType == 3) { Sleep(80); pInvoke->Invoke(); } // double-click
                pInvoke->Release();
                ok = true;
            }
            pRaw->Release();
        }

        // Fallback: LegacyIAccessiblePattern DoDefaultAction
        if (!ok)
        {
            IUnknown* pAcc = nullptr;
            pBtn->GetCurrentPattern(UIA_LegacyIAccessiblePatternId, &pAcc);
            if (pAcc)
            {
                IUIAutomationLegacyIAccessiblePattern* pLeg = nullptr;
                if (SUCCEEDED(pAcc->QueryInterface(__uuidof(IUIAutomationLegacyIAccessiblePattern),
                                                    reinterpret_cast<void**>(&pLeg))) && pLeg)
                {
                    pLeg->DoDefaultAction();
                    pLeg->Release();
                    ok = true;
                }
                pAcc->Release();
            }
        }
    }
    else // right (1) or middle (2) — resolve screen rect and SendInput
    {
        RECT rect{};
        pBtn->get_CurrentBoundingRectangle(&rect);

        if (rect.right > rect.left && rect.bottom > rect.top)
        {
            int cx = (rect.left + rect.right) / 2;
            int cy = (rect.top  + rect.bottom) / 2;

            // Absolute normalised coordinates for SendInput
            int vsX = GetSystemMetrics(SM_XVIRTUALSCREEN);
            int vsY = GetSystemMetrics(SM_YVIRTUALSCREEN);
            int vsW = GetSystemMetrics(SM_CXVIRTUALSCREEN);
            int vsH = GetSystemMetrics(SM_CYVIRTUALSCREEN);

            DWORD downFlag = (clickType == 1) ? MOUSEEVENTF_RIGHTDOWN : MOUSEEVENTF_MIDDLEDOWN;
            DWORD upFlag   = (clickType == 1) ? MOUSEEVENTF_RIGHTUP   : MOUSEEVENTF_MIDDLEUP;

            INPUT inputs[3]{};
            // 1. Move
            inputs[0].type        = INPUT_MOUSE;
            inputs[0].mi.dx       = MulDiv(cx - vsX, 65535, vsW - 1);
            inputs[0].mi.dy       = MulDiv(cy - vsY, 65535, vsH - 1);
            inputs[0].mi.dwFlags  = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK;
            // 2. Down
            inputs[1].type        = INPUT_MOUSE;
            inputs[1].mi.dwFlags  = downFlag;
            // 3. Up
            inputs[2].type        = INPUT_MOUSE;
            inputs[2].mi.dwFlags  = upFlag;

            SendInput(3, inputs, sizeof(INPUT));
            ok = true;
        }
    }

    pBtn->Release();
    pAuto->Release();
    return ok;
}
