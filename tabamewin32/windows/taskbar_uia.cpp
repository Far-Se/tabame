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
#include <iostream>
#include <vector>
#include <string>

// Link necessary libraries
#pragma comment(lib, "dwmapi.lib")
#pragma comment(lib, "Ole32.lib")
#pragma comment(lib, "OleAut32.lib")
#pragma comment(lib, "uiautomationcore.lib")

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