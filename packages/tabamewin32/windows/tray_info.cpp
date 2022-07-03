#include <Windows.h>
#include <CommCtrl.h>
#include <tchar.h>
#include <cassert>

#include <crtdbg.h>

#include <atlbase.h>
#include <iostream>
#include <sstream>
//#include "icon.h"
#include <Psapi.h>
#include <winuser.h>
#include <string>
#include <filesystem>

using namespace std;

struct TRAYDATA
{
    HWND hwnd;
    UINT uID;
    UINT uCallbackMessage;
    DWORD Reserved[2];
    HICON hIcon;
};

struct TrayIconData
{
    wstring toolTip;
    bool isVisible;
    int processID;
    TRAYDATA data;
};

std::vector<TrayIconData> EnumSystemTray()
{
    std::vector<TrayIconData> output;

    bool bFound = false;

    // find system tray window
    HWND trayWnd = FindWindow(_T("Shell_TrayWnd"), NULL);
    if (trayWnd)
    {
        trayWnd = FindWindowEx(trayWnd, NULL, _T("TrayNotifyWnd"), NULL);
        if (trayWnd)
        {
            trayWnd = FindWindowEx(trayWnd, NULL, _T("SysPager"), NULL);
            if (trayWnd)
            {
                trayWnd = FindWindowEx(trayWnd, NULL, _T("ToolbarWindow32"), NULL);
                bFound = true;
            }
        }
    }

    assert(bFound);

    DWORD dwTrayPid;
    GetWindowThreadProcessId(trayWnd, &dwTrayPid);

    int count = (int)SendMessage(trayWnd, TB_BUTTONCOUNT, 0, 0);

    HANDLE hProcess = OpenProcess(PROCESS_ALL_ACCESS, FALSE, dwTrayPid);
    if (!hProcess)
    {
        return std::vector<TrayIconData>{};
    }

    SIZE_T dwSize = sizeof(TBBUTTON);
    // cout << "Size: " << dwSize << endl;
    LPVOID lpData = VirtualAllocEx(hProcess, NULL, dwSize, MEM_COMMIT, PAGE_READWRITE);
    if (!lpData)
    {
        return std::vector<TrayIconData>{};
    }

    for (int i = 0; i < count; i++)
    {
        HWND hwnd32;
        TBBUTTON buttonInfo;

        SendMessage(trayWnd, TB_GETBUTTON, i, (LPARAM)lpData);

        TBBUTTON tbb{};
        if (!ReadProcessMemory(hProcess, lpData, (LPVOID)&tbb, sizeof(TBBUTTON), NULL))
        {
            continue;
        }
        TRAYDATA trayInfo;
        if (!ReadProcessMemory(hProcess, (LPCVOID)tbb.dwData, (LPVOID)&trayInfo, sizeof(TRAYDATA), NULL))
        {
            continue;
        }
        hwnd32 = (HWND)trayInfo.hwnd;
        buttonInfo = tbb;
        wchar_t TipChar{};
        wchar_t sTip[1024] = {0};
        wchar_t *pTip = (wchar_t *)tbb.iString;

        if (!(tbb.fsState & TBSTATE_HIDDEN))
        {
            int x = 0;
            do
            {
                if (x == 1023)
                {
                    wcscpy_s(sTip, L"");
                    break;
                }
                ReadProcessMemory(hProcess, (LPCVOID)pTip++, &TipChar, sizeof(wchar_t), NULL);
                sTip[x++] = TipChar;
            } while (true);
            // } while (sTip[x++] = TipChar); // !HERE
            // wcout << sTip << endl;
        }

        DWORD dwProcessId = 0;
        GetWindowThreadProcessId(hwnd32, &dwProcessId);

        TrayIconData iconInfo;
        iconInfo.toolTip = W2T(sTip);
        iconInfo.data = trayInfo;
        iconInfo.processID = (int)dwProcessId;
        iconInfo.isVisible = !(tbb.fsState & TBSTATE_HIDDEN);
        output.push_back(iconInfo);
        // TRIGGER EVENT
        // PostMessage(trayInfo.hwnd, trayInfo.uCallbackMessage, trayInfo.uID, WM_LBUTTONDBLCLK);
    }
    VirtualFreeEx(hProcess, lpData, NULL, MEM_RELEASE);
    return output;
}