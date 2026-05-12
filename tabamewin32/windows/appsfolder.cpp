#include <windows.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <shlwapi.h>
#include <propkey.h>
#include <propvarutil.h>
#include <wrl/client.h>

#include <string>
#include <vector>
#include <iostream>

#pragma comment(lib, "Ole32.lib")
#pragma comment(lib, "Shell32.lib")
#pragma comment(lib, "Shlwapi.lib")

using Microsoft::WRL::ComPtr;

struct AppInfo
{
    std::wstring name;
    std::wstring exePathOrAppId;
    HICON hIcon = nullptr;
};

//------------------------------------------------------------
// RAII COM helper
//------------------------------------------------------------
class ScopedCOM
{
public:
    ScopedCOM()
    {
        hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    }

    ~ScopedCOM()
    {
        if (SUCCEEDED(hr))
            CoUninitialize();
    }

    bool IsValid() const
    {
        return SUCCEEDED(hr) || hr == RPC_E_CHANGED_MODE;
    }

private:
    HRESULT hr{};
};

//------------------------------------------------------------
// Safe string property helper
//------------------------------------------------------------
static std::wstring GetStringProperty(
    IShellItem2* item,
    REFPROPERTYKEY key)
{
    if (!item)
        return L"";

    PWSTR value = nullptr;

    HRESULT hr = item->GetString(key, &value);

    if (FAILED(hr) || !value)
        return L"";

    std::wstring result(value);
    CoTaskMemFree(value);

    return result;
}

//------------------------------------------------------------
// Canonical icon extraction from PIDL
//------------------------------------------------------------
HICON GetIconFromPIDL(LPCITEMIDLIST pidl)
{
    if (!pidl)
        return nullptr;

    SHFILEINFOW sfi{};

    if (!SHGetFileInfoW(
            reinterpret_cast<LPCWSTR>(pidl),
            0,
            &sfi,
            sizeof(sfi),
            SHGFI_PIDL | SHGFI_ICON | SHGFI_LARGEICON))
    {
        return nullptr;
    }

    return sfi.hIcon;
}

//------------------------------------------------------------
// Create canonical absolute PIDL from shell object
//------------------------------------------------------------
static PIDLIST_ABSOLUTE GetAbsolutePIDL(IUnknown* object)
{
    PIDLIST_ABSOLUTE pidl = nullptr;

    if (!object)
        return nullptr;

    if (FAILED(SHGetIDListFromObject(object, &pidl)))
        return nullptr;

    return pidl;
}

//------------------------------------------------------------
// Enumerate AppsFolder
//------------------------------------------------------------
std::vector<AppInfo> GetAllAppsFolder()
{
    std::vector<AppInfo> apps;

    ScopedCOM com;

    if (!com.IsValid())
        return apps;

    //--------------------------------------------------------
    // Open shell:AppsFolder
    //--------------------------------------------------------
    ComPtr<IShellItem> appsFolderItem;

    HRESULT hr = SHCreateItemFromParsingName(
        L"shell:AppsFolder",
        nullptr,
        IID_PPV_ARGS(&appsFolderItem));

    if (FAILED(hr))
        return apps;

    //--------------------------------------------------------
    // Get IShellFolder
    //--------------------------------------------------------
    ComPtr<IShellFolder> shellFolder;

    hr = appsFolderItem->BindToHandler(
        nullptr,
        BHID_SFObject,
        IID_PPV_ARGS(&shellFolder));

    if (FAILED(hr))
        return apps;

    //--------------------------------------------------------
    // Enumerate entries
    //--------------------------------------------------------
    ComPtr<IEnumIDList> enumList;

    hr = shellFolder->EnumObjects(
        nullptr,
        SHCONTF_NONFOLDERS,
        &enumList);

    if (FAILED(hr))
        return apps;

    LPITEMIDLIST childPidl = nullptr;

    while (enumList->Next(1, &childPidl, nullptr) == S_OK)
    {
        AppInfo app;

        //----------------------------------------------------
        // Create shell item
        //----------------------------------------------------
        ComPtr<IShellItem2> shellItem2;

        hr = SHCreateItemWithParent(
            nullptr,
            shellFolder.Get(),
            childPidl,
            IID_PPV_ARGS(&shellItem2));

        if (FAILED(hr))
        {
            CoTaskMemFree(childPidl);
            continue;
        }

        //----------------------------------------------------
        // Display name
        //----------------------------------------------------
        app.name = GetStringProperty(
            shellItem2.Get(),
            PKEY_ItemNameDisplay);

        //----------------------------------------------------
        // Win32 executable path
        //----------------------------------------------------
        app.exePathOrAppId = GetStringProperty(
            shellItem2.Get(),
            PKEY_Link_TargetParsingPath);

        //----------------------------------------------------
        // UWP fallback
        //----------------------------------------------------
        if (app.exePathOrAppId.empty())
        {
            app.exePathOrAppId = GetStringProperty(
                shellItem2.Get(),
                PKEY_AppUserModel_ID);
        }

        //----------------------------------------------------
        // Canonical absolute PIDL
        //----------------------------------------------------
        PIDLIST_ABSOLUTE absolutePidl =
            GetAbsolutePIDL(shellItem2.Get());

        if (absolutePidl)
        {
            app.hIcon = GetIconFromPIDL(absolutePidl);
            CoTaskMemFree(absolutePidl);
        }

        apps.emplace_back(std::move(app));

        CoTaskMemFree(childPidl);
    }

    return apps;
}

//------------------------------------------------------------
// Get icon directly by app name
//------------------------------------------------------------
HICON GetAppIcon(const std::wstring& appName)
{
    ScopedCOM com;

    if (!com.IsValid())
        return nullptr;

    ComPtr<IShellItem> appsFolderItem;

    HRESULT hr = SHCreateItemFromParsingName(
        L"shell:AppsFolder",
        nullptr,
        IID_PPV_ARGS(&appsFolderItem));

    if (FAILED(hr))
        return nullptr;

    ComPtr<IShellFolder> shellFolder;

    hr = appsFolderItem->BindToHandler(
        nullptr,
        BHID_SFObject,
        IID_PPV_ARGS(&shellFolder));

    if (FAILED(hr))
        return nullptr;

    ComPtr<IEnumIDList> enumList;

    hr = shellFolder->EnumObjects(
        nullptr,
        SHCONTF_NONFOLDERS,
        &enumList);

    if (FAILED(hr))
        return nullptr;

    LPITEMIDLIST childPidl = nullptr;

    while (enumList->Next(1, &childPidl, nullptr) == S_OK)
    {
        ComPtr<IShellItem2> shellItem2;

        hr = SHCreateItemWithParent(
            nullptr,
            shellFolder.Get(),
            childPidl,
            IID_PPV_ARGS(&shellItem2));

        if (FAILED(hr))
        {
            CoTaskMemFree(childPidl);
            continue;
        }

        std::wstring currentName = GetStringProperty(
            shellItem2.Get(),
            PKEY_ItemNameDisplay);

        if (_wcsicmp(currentName.c_str(), appName.c_str()) == 0)
        {
            PIDLIST_ABSOLUTE absolutePidl =
                GetAbsolutePIDL(shellItem2.Get());

            HICON hIcon = nullptr;

            if (absolutePidl)
            {
                hIcon = GetIconFromPIDL(absolutePidl);
                CoTaskMemFree(absolutePidl);
            }

            CoTaskMemFree(childPidl);
            return hIcon;
        }

        CoTaskMemFree(childPidl);
    }

    return nullptr;
}

//------------------------------------------------------------
// Example usage
//------------------------------------------------------------
/* int wmain()
{
    auto apps = GetAllAppsFolder();

    for (const auto& app : apps)
    {
        std::wcout
            << L"Name: " << app.name << std::endl
            << L"Target: " << app.exePathOrAppId << std::endl
            << L"HICON: " << app.hIcon << std::endl
            << L"------------------------------------"
            << std::endl;
    }

    HICON hChrome = GetAppIcon(L"Google Chrome");

    if (hChrome)
    {
        std::wcout << L"Chrome icon loaded successfully." << std::endl;

        //----------------------------------------------------
        // IMPORTANT:
        // Destroy HICON when finished.
        //----------------------------------------------------
        DestroyIcon(hChrome);
    }

    return 0;
} */