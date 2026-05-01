#ifndef TABAMEWIN32_SHELL_UTILS
#define TABAMEWIN32_SHELL_UTILS

#include <windows.h>
#include <shlobj.h>
#include <ShellAPI.h>
#include <tlhelp32.h>
#include <atlbase.h>
#include <atlcom.h>
#include <exdisp.h>
#include <shldisp.h>
#include <string>
#include <vector>

#include "include/encoding.h"

#pragma comment(lib, "advapi32")

// ---------------------------------------------------------------------------
// Desktop shell automation (launch as explorer)
// ---------------------------------------------------------------------------
#include <windows.h>
#include <atlbase.h>
#include <atlcom.h>
#include <shldisp.h>
#include <shlobj.h>
#include <tlhelp32.h>
#include <set>
#include <string>
#include <vector>
#include <thread>

// ─────────────────────────────────────────────────────────────────────────────
// Your original helpers (unchanged)
// ─────────────────────────────────────────────────────────────────────────────

namespace
{
    void FindDesktopFolderView(REFIID riid, void **ppv)
    {
        CComPtr<IShellWindows> spShellWindows;
        spShellWindows.CoCreateInstance(CLSID_ShellWindows);

        CComVariant vtLoc(CSIDL_DESKTOP);
        CComVariant vtEmpty;
        long lhwnd;
        CComPtr<IDispatch> spdisp;
        spShellWindows->FindWindowSW(&vtLoc, &vtEmpty, SWC_DESKTOP, &lhwnd,
                                     SWFO_NEEDDISPATCH, &spdisp);

        CComPtr<IShellBrowser> spBrowser;
        CComQIPtr<IServiceProvider>(spdisp)->QueryService(SID_STopLevelBrowser,
                                                          IID_PPV_ARGS(&spBrowser));

        CComPtr<IShellView> spView;
        spBrowser->QueryActiveShellView(&spView);
        spView->QueryInterface(riid, ppv);
    }

    void GetDesktopAutomationObject(REFIID riid, void **ppv)
    {
        CComPtr<IShellView> spsv;
        FindDesktopFolderView(IID_PPV_ARGS(&spsv));
        CComPtr<IDispatch> spdispView;
        spsv->GetItemObject(SVGIO_BACKGROUND, IID_PPV_ARGS(&spdispView));
        spdispView->QueryInterface(riid, ppv);
    }

    DWORD GetExplorerPid()
    {
        HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
        if (snapshot == INVALID_HANDLE_VALUE)
            return 0;

        PROCESSENTRY32W entry = {};
        entry.dwSize = sizeof(entry);
        DWORD pid = 0;

        if (Process32FirstW(snapshot, &entry))
        {
            do
            {
                if (_wcsicmp(entry.szExeFile, L"explorer.exe") == 0)
                {
                    pid = entry.th32ProcessID;
                    break;
                }
            } while (Process32NextW(snapshot, &entry));
        }

        CloseHandle(snapshot);
        return pid;
    }
} // anonymous namespace

// ─────────────────────────────────────────────────────────────────────────────
// Window focusing (runs on a background thread)
// ─────────────────────────────────────────────────────────────────────────────

namespace
{
    struct FindWindowData
    {
        DWORD pid;
        HWND  hwnd;
    };

    BOOL CALLBACK FindMainWindow(HWND wnd, LPARAM lParam)
    {
        auto* data = reinterpret_cast<FindWindowData*>(lParam);
        DWORD wndPid = 0;
        GetWindowThreadProcessId(wnd, &wndPid);

        if (wndPid == data->pid
            && IsWindowVisible(wnd)
            && GetWindow(wnd, GW_OWNER) == nullptr)
        {
            data->hwnd = wnd;
            return FALSE;
        }
        return TRUE;
    }

    HWND WaitForProcessWindow(DWORD pid, DWORD timeoutMs = 5000)
    {
        FindWindowData data{ pid, nullptr };
        DWORD elapsed = 0;

        while (elapsed < timeoutMs)
        {
            EnumWindows(FindMainWindow, reinterpret_cast<LPARAM>(&data));
            if (data.hwnd)
                return data.hwnd;
            Sleep(100);
            elapsed += 100;
        }
        return nullptr;
    }

    void FocusWindowAsync(DWORD pid)
    {
        // Detached thread — waits for the window without blocking the caller
        std::thread([pid]()
        {
            HWND hwnd = WaitForProcessWindow(pid, 5000);
            if (!hwnd)
                return;

            if (IsIconic(hwnd))
                ShowWindow(hwnd, SW_RESTORE);
            else
                ShowWindow(hwnd, SW_SHOW);

            SetForegroundWindow(hwnd);
        }).detach();
    }

    // For ShellExecute path: we don't have a PID, so diff the process list
    void FocusNewProcessAsync(std::set<DWORD> pidsBefore)
    {
        std::thread([pidsBefore = std::move(pidsBefore)]()
        {
            // Give the shell a moment to spawn
            Sleep(500);

            HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
            if (snap == INVALID_HANDLE_VALUE)
                return;

            PROCESSENTRY32W pe{ sizeof(pe) };
            DWORD newPid = 0;

            if (Process32FirstW(snap, &pe))
            {
                do {
                    if (pidsBefore.find(pe.th32ProcessID) == pidsBefore.end())
                    {
                        newPid = pe.th32ProcessID;
                        break;
                    }
                } while (Process32NextW(snap, &pe));
            }
            CloseHandle(snap);

            if (!newPid)
                return;

            HWND hwnd = WaitForProcessWindow(newPid, 5000);
            if (!hwnd)
                return;

            if (IsIconic(hwnd))
                ShowWindow(hwnd, SW_RESTORE);
            else
                ShowWindow(hwnd, SW_SHOW);

            SetForegroundWindow(hwnd);
        }).detach();
    }
} // anonymous namespace

// ─────────────────────────────────────────────────────────────────────────────
// Core launch functions
// ─────────────────────────────────────────────────────────────────────────────

static bool ShellExecuteFromExplorer(
    PCWSTR pszFile,
    PCWSTR pszParameters = nullptr,
    PCWSTR pszDirectory  = nullptr,
    PCWSTR pszOperation  = nullptr,
    int    nShowCmd      = SW_SHOWNORMAL)
{
    CComPtr<IShellFolderViewDual> spFolderView;
    GetDesktopAutomationObject(IID_PPV_ARGS(&spFolderView));
    if (!spFolderView)
        return false;

    CComPtr<IDispatch> spdispShell;
    HRESULT hr = spFolderView->get_Application(&spdispShell);
    if (FAILED(hr) || !spdispShell)
        return false;

    CComQIPtr<IShellDispatch2> shell(spdispShell);
    if (!shell)
        return false;

    // Snapshot PIDs before launch so FocusNewProcessAsync can diff them
    std::set<DWORD> pidsBefore;
    {
        HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
        if (snap != INVALID_HANDLE_VALUE)
        {
            PROCESSENTRY32W pe{ sizeof(pe) };
            if (Process32FirstW(snap, &pe))
                do { pidsBefore.insert(pe.th32ProcessID); }
                while (Process32NextW(snap, &pe));
            CloseHandle(snap);
        }
    }

    AllowSetForegroundWindow(ASFW_ANY);

    hr = shell->ShellExecute(
        CComBSTR(pszFile),
        CComVariant(pszParameters ? pszParameters : L""),
        CComVariant(pszDirectory  ? pszDirectory  : L""),
        CComVariant(pszOperation  ? pszOperation  : L""),
        CComVariant(nShowCmd));

    if (FAILED(hr))
        return false;

    // Focus happens in the background — caller returns immediately
    FocusNewProcessAsync(std::move(pidsBefore));
    return true;
}

static bool LaunchWithExplorerToken(
    const std::wstring& file,
    const std::wstring& arguments        = L"",
    const std::wstring& workingDirectory = L"")
{
    DWORD explorerPid = GetExplorerPid();
    if (explorerPid == 0)
        return false;

    HANDLE explorerProcess = OpenProcess(PROCESS_QUERY_INFORMATION, FALSE, explorerPid);
    if (!explorerProcess)
        return false;

    HANDLE explorerToken   = nullptr;
    HANDLE duplicatedToken = nullptr;
    bool   launched        = false;

    do
    {
        if (!OpenProcessToken(explorerProcess,
                              TOKEN_DUPLICATE | TOKEN_ASSIGN_PRIMARY | TOKEN_QUERY,
                              &explorerToken))
            break;

        if (!DuplicateTokenEx(explorerToken,
                              TOKEN_ALL_ACCESS,
                              nullptr,
                              SecurityImpersonation,
                              TokenPrimary,
                              &duplicatedToken))
            break;

        STARTUPINFOW si = {};
        si.cb           = sizeof(si);
        si.dwFlags      = STARTF_USESHOWWINDOW;
        si.wShowWindow  = SW_SHOWNORMAL;

        PROCESS_INFORMATION pi = {};

        std::wstring commandLine = L"\"" + file + L"\"";
        if (!arguments.empty())
            commandLine += L" " + arguments;

        std::vector<wchar_t> buf(commandLine.begin(), commandLine.end());
        buf.push_back(L'\0');

        AllowSetForegroundWindow(ASFW_ANY);

        launched = CreateProcessWithTokenW(
            duplicatedToken,
            LOGON_WITH_PROFILE,
            nullptr,
            buf.data(),
            CREATE_NEW_CONSOLE,
            nullptr,
            workingDirectory.empty() ? nullptr : workingDirectory.c_str(),
            &si,
            &pi) != FALSE;

        if (launched)
        {
            // Focus on background thread — no blocking here
            FocusWindowAsync(pi.dwProcessId);

            CloseHandle(pi.hProcess);
            CloseHandle(pi.hThread);
        }
    }
    while (false);

    if (explorerToken)   CloseHandle(explorerToken);
    if (duplicatedToken) CloseHandle(duplicatedToken);
    CloseHandle(explorerProcess);

    return launched;
}

// ─────────────────────────────────────────────────────────────────────────────
// Public entry point
// ─────────────────────────────────────────────────────────────────────────────

bool LaunchWithExplorer(
    const std::wstring& file,
    const std::wstring& arguments        = L"",
    const std::wstring& workingDirectory = L"")
{
    if (LaunchWithExplorerToken(file, arguments, workingDirectory))
        return true;

    return ShellExecuteFromExplorer(
        file.c_str(),
        arguments.empty()        ? nullptr : arguments.c_str(),
        workingDirectory.empty() ? nullptr : workingDirectory.c_str(),
        nullptr,
        SW_SHOWNORMAL);
}

// ---------------------------------------------------------------------------
// Browse for folder dialog
// ---------------------------------------------------------------------------
static int CALLBACK BrowseCallbackProc(HWND /*hwnd*/, UINT /*uMsg*/, LPARAM /*lParam*/, LPARAM /*lpData*/)
{
    return 0;
}

std::string BrowseFolder()
{
    BROWSEINFO bi = {0};
    bi.lpszTitle = _T("Browse for folder...");
    bi.ulFlags = BIF_RETURNONLYFSDIRS | BIF_NEWDIALOGSTYLE;
    bi.lpfn = BrowseCallbackProc;

    LPITEMIDLIST pidl = SHBrowseForFolder(&bi);
    if (pidl != nullptr)
    {
        TCHAR path[MAX_PATH];
        SHGetPathFromIDList(pidl, path);

        IMalloc *imalloc = nullptr;
        if (SUCCEEDED(SHGetMalloc(&imalloc)))
        {
            imalloc->Free(pidl);
            imalloc->Release();
        }
        return Encoding::WideToUtf8(path);
    }
    return "";
}

// ---------------------------------------------------------------------------
// Shortcut creation
// ---------------------------------------------------------------------------
void CreateShortcut(bool create, const std::wstring &exePath, const std::wstring &destPath,
                    int ShowCmd, const std::string &args, const std::wstring &destExe = L"")
{
    std::wstring wExe = exePath.substr(exePath.find_last_of(L"\\") + 1);
    wExe.replace(wExe.find(L".exe"), sizeof(L".exe") - 1, L".lnk");

    std::wstring wStartMenuPath = destPath + L"\\";
    if (!destExe.empty())
        wStartMenuPath.append(destExe);
    else
        wStartMenuPath.append(wExe);

    if (!create)
    {
        std::string path = Encoding::WideToUtf8(wStartMenuPath.c_str());
        std::remove(path.c_str());
        return;
    }

    CoInitialize(nullptr);
    IShellLink *psl = nullptr;
    HRESULT hres = CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                                   IID_IShellLink, reinterpret_cast<void **>(&psl));
    if (SUCCEEDED(hres))
    {
        // Use a mutable copy for PathRemoveFileSpec
        std::vector<wchar_t> pathBuf(exePath.begin(), exePath.end());
        pathBuf.push_back(L'\0');

        psl->SetPath(exePath.c_str());
        PathRemoveFileSpec(pathBuf.data());
        psl->SetWorkingDirectory(pathBuf.data());
        psl->SetShowCmd(ShowCmd);

        if (!args.empty())
        {
            std::wstring wArgs = Encoding::Utf8ToWide(args);
            psl->SetArguments(wArgs.c_str());
        }

        IPersistFile *ppf = nullptr;
        hres = psl->QueryInterface(IID_IPersistFile, reinterpret_cast<void **>(&ppf));
        if (SUCCEEDED(hres))
        {
            ppf->Save(wStartMenuPath.c_str(), TRUE);
            ppf->Release();
        }
        psl->Release();
    }
    CoUninitialize();
}

// ---------------------------------------------------------------------------
// Set start on system startup (as admin shortcut flag)
// ---------------------------------------------------------------------------
int SetStartOnStartupAsAdmin(bool enabled, const std::string &exePath)
{
    HRESULT result = CoInitialize(nullptr);
    if (FAILED(result))
        return -1;

    IShellLink *link = nullptr;
    result = CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                              IID_IShellLink, reinterpret_cast<void **>(&link));
    if (FAILED(result))
    {
        CoUninitialize();
        return -1;
    }

    IPersistFile *file = nullptr;
    result = link->QueryInterface(IID_IPersistFile, reinterpret_cast<void **>(&file));
    if (FAILED(result))
    {
        link->Release();
        CoUninitialize();
        return -2;
    }

    // Build shortcut path
    WCHAR startMenuPath[MAX_PATH];
    SHGetFolderPathW(nullptr, CSIDL_STARTUP, nullptr, 0, startMenuPath);
    std::string exe = exePath.substr(exePath.find_last_of("\\") + 1);
    std::wstring wExe = Encoding::Utf8ToWide(exe);
    wExe.replace(wExe.find(L".exe"), sizeof(L".exe") - 1, L".lnk");
    std::wstring wPath = std::wstring(startMenuPath) + L"\\" + wExe;

    result = file->Load(wPath.c_str(), STGM_READ);
    if (FAILED(result))
    {
        file->Release();
        link->Release();
        CoUninitialize();
        return -3;
    }

    IShellLinkDataList *pdl = nullptr;
    result = link->QueryInterface(IID_IShellLinkDataList, reinterpret_cast<void **>(&pdl));
    if (FAILED(result))
    {
        file->Release();
        link->Release();
        CoUninitialize();
        return -4;
    }

    DWORD dwFlags = 0;
    result = pdl->GetFlags(&dwFlags);
    if (FAILED(result))
    {
        pdl->Release();
        file->Release();
        link->Release();
        CoUninitialize();
        return -5;
    }

    bool hasRunAs = (SLDF_RUNAS_USER & dwFlags) == SLDF_RUNAS_USER;
    if (!hasRunAs && enabled)
    {
        result = pdl->SetFlags(SLDF_RUNAS_USER | dwFlags);
    }
    else if (hasRunAs && !enabled)
    {
        result = pdl->SetFlags(dwFlags & ~SLDF_RUNAS_USER);
    }
    else
    {
        pdl->Release();
        file->Release();
        link->Release();
        CoUninitialize();
        return 0; // Already in desired state
    }

    if (FAILED(result))
    {
        pdl->Release();
        file->Release();
        link->Release();
        CoUninitialize();
        return -6;
    }

    result = file->Save(nullptr, true);
    if (FAILED(result))
    {
        pdl->Release();
        file->Release();
        link->Release();
        CoUninitialize();
        return -8;
    }
    file->SaveCompleted(nullptr);

    pdl->Release();
    file->Release();
    link->Release();
    CoUninitialize();
    return ERROR_SUCCESS;
}

#endif // TABAMEWIN32_SHELL_UTILS
