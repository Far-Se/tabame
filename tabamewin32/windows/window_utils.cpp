#ifndef TABAMEWIN32_WINDOW_UTILS
#define TABAMEWIN32_WINDOW_UTILS

#include <windows.h>
#include <TlHelp32.h>
#include <shobjidl.h>
#include <shlobj.h>
#include <string>
#include <utility>

#include "include/encoding.h"

// ---------------------------------------------------------------------------
// Get process executable name from HWND
// ---------------------------------------------------------------------------
std::wstring getHwndName(HWND hWnd)
{
    std::wstring processName;
    DWORD pid = 0;
    GetWindowThreadProcessId(hWnd, &pid);

    HANDLE hSnap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (hSnap != INVALID_HANDLE_VALUE)
    {
        PROCESSENTRY32 pe;
        pe.dwSize = sizeof(PROCESSENTRY32);
        if (Process32First(hSnap, &pe))
        {
            do
            {
                if (pe.th32ProcessID == pid)
                {
                    processName = pe.szExeFile;
                    break;
                }
            } while (Process32Next(hSnap, &pe));
        }
        CloseHandle(hSnap);
    }

    if (processName.empty())
        processName = L"-";

    return processName;
}

// ---------------------------------------------------------------------------
// Find the top-level window for a given process ID
// ---------------------------------------------------------------------------
HWND FindTopWindow(DWORD pid)
{
    std::pair<HWND, DWORD> params = {nullptr, pid};

    EnumWindows(
        [](HWND hwnd, LPARAM lParam) -> BOOL
        {
            auto *pParams = reinterpret_cast<std::pair<HWND, DWORD> *>(lParam);
            DWORD processId = 0;
            if (GetWindowThreadProcessId(hwnd, &processId) && processId == pParams->second)
            {
                SetLastError(static_cast<DWORD>(-1));
                pParams->first = hwnd;
                return FALSE;
            }
            return TRUE;
        },
        reinterpret_cast<LPARAM>(&params));

    if (GetLastError() == static_cast<DWORD>(-1) && params.first)
        return params.first;

    return nullptr;
}

// ---------------------------------------------------------------------------
// Skip/show window in taskbar
// Bug fix: check SUCCEEDED(res) instead of truthy res for HrInit
// ---------------------------------------------------------------------------
namespace
{
    ITaskbarList3 *g_taskbar = nullptr;
    bool g_taskbarInitialized = false;
} // anonymous namespace

void SetHwndSkipTaskbar(HWND hWnd, bool skip)
{
    if (!g_taskbarInitialized)
    {
        HRESULT res = CoCreateInstance(CLSID_TaskbarList, nullptr, CLSCTX_INPROC_SERVER,
                                      IID_PPV_ARGS(&g_taskbar));
        g_taskbarInitialized = true;
        if (SUCCEEDED(res) && g_taskbar)
            g_taskbar->HrInit();
    }

    if (!g_taskbar)
        return;

    if (skip)
        g_taskbar->DeleteTab(hWnd);
    else
        g_taskbar->AddTab(hWnd);
}

// ---------------------------------------------------------------------------
// Resolve .lnk shortcut to target path
// Bug fix: proper Release() on all error paths
// ---------------------------------------------------------------------------
int LinkToPath(LPCTSTR path, LPTSTR lpszPath, int iPathBufferSize)
{
    IShellLink *pShellLink = nullptr;
    HRESULT rc = CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                                 IID_IShellLink, reinterpret_cast<void **>(&pShellLink));
    if (FAILED(rc))
        return 0;

    IPersistFile *pPersistFile = nullptr;
    rc = pShellLink->QueryInterface(IID_IPersistFile, reinterpret_cast<void **>(&pPersistFile));
    if (FAILED(rc))
    {
        pShellLink->Release();
        return 0;
    }

    rc = pPersistFile->Load(path, STGM_READ);
    if (FAILED(rc))
    {
        pPersistFile->Release();
        pShellLink->Release();
        return 0;
    }

    rc = pShellLink->Resolve(nullptr, 0);
    if (FAILED(rc))
    {
        pPersistFile->Release();
        pShellLink->Release();
        return 0;
    }

    rc = pShellLink->GetPath(lpszPath, iPathBufferSize, nullptr, SLGP_SHORTPATH);

    pPersistFile->Release();
    pShellLink->Release();
    return SUCCEEDED(rc) ? 1 : 0;
}

#endif // TABAMEWIN32_WINDOW_UTILS
