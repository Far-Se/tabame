#include <windows.h>
#include <propkey.h>
#include <propvarutil.h>
#include <shellapi.h>
#include <shlguid.h>
#include <shlobj.h>
#include <shlwapi.h>
#include <shobjidl.h>
#include <wrl/client.h>

#include <cstdint>
#include <future>
#include <string>
#include <vector>

#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "propsys.lib")

using Microsoft::WRL::ComPtr;

struct AppInfo {
    std::wstring name;
    std::wstring executable;
    std::wstring arguments;
    std::wstring appUserModelId;
    std::wstring parsingName;
};

struct AppBitmap {
    std::vector<uint8_t> pixels; // BGRA, premultiplied alpha already un-done
    int width  = 0;
    int height = 0;
};

// ---------------------------------------------------------------------------
// Property key for the executable path stored in the shell item's property
// store (works for Win32 shortcuts AND packaged apps).
// PKEY_Link_TargetParsingPath = {B9B4B3FC-2B51-4A42-B5D8-324146AFCF25}, 2
// ---------------------------------------------------------------------------
// static const PROPERTYKEY PKEY_Link_TargetParsingPath = {
//     {0xB9B4B3FC, 0x2B51, 0x4A42, {0xB5, 0xD8, 0x32, 0x41, 0x46, 0xAF, 0xCF, 0x25}}, 2
// };
// PKEY_Link_Arguments = {436F2667-14E2-4FEB-B30A-146C53B5B674}, 100
static const PROPERTYKEY PKEY_Link_Arguments_Custom = {
    {0x436F2667, 0x14E2, 0x4FEB, {0xB3, 0x0A, 0x14, 0x6C, 0x53, 0xB5, 0xB6, 0x74}}, 100
};

namespace detail {

// ---------------------------------------------------------------------------
// FIX #2: Read alpha from the DIB section bits directly.
//
// IShellItemImageFactory returns a 32-bpp premultiplied-ARGB DIB section.
// GetDIBits with BI_RGB zeroes the alpha byte on every pixel, making the
// result appear corrupt / invisible when displayed.
// The correct approach: lock the DIB section memory and copy the raw
// premultiplied pixels, then un-premultiply so callers get straight BGRA.
// ---------------------------------------------------------------------------
inline AppBitmap HBitmapToAppBitmap(HBITMAP hbmp) {
    AppBitmap result;
    if (!hbmp) return result;

    DIBSECTION ds{};
    if (GetObject(hbmp, sizeof(ds), &ds) != sizeof(ds)) {
        // Not a DIB section — fall back to GetDIBits (icons from .exe files)
        BITMAP bm{};
        if (!GetObject(hbmp, sizeof(bm), &bm)) return result;

        BITMAPINFOHEADER bi{};
        bi.biSize        = sizeof(bi);
        bi.biWidth       = bm.bmWidth;
        bi.biHeight      = -bm.bmHeight;
        bi.biPlanes      = 1;
        bi.biBitCount    = 32;
        bi.biCompression = BI_RGB;

        const size_t bytes = static_cast<size_t>(bm.bmWidth * 4) * bm.bmHeight;
        result.pixels.resize(bytes);
        result.width  = bm.bmWidth;
        result.height = bm.bmHeight;

        HDC hdc = GetDC(nullptr);
        GetDIBits(hdc, hbmp, 0, bm.bmHeight, result.pixels.data(),
                  reinterpret_cast<BITMAPINFO*>(&bi), DIB_RGB_COLORS);
        ReleaseDC(nullptr, hdc);

        // Force alpha to 255 for plain HBITMAP (no real alpha channel)
        for (size_t i = 3; i < bytes; i += 4)
            result.pixels[i] = 255;

        return result;
    }

    // DIB section: ds.dsBm.bmBits points directly at the pixel data.
    const int w = ds.dsBm.bmWidth;
    const int h = ds.dsBm.bmHeight;
    if (w <= 0 || h == 0 || !ds.dsBm.bmBits) return result;

    const int absH   = (h < 0) ? -h : h;
    const size_t bytes = static_cast<size_t>(w * 4) * absH;

    result.pixels.resize(bytes);
    result.width  = w;
    result.height = absH;

    // The DIB section is top-down when biHeight < 0, bottom-up when > 0.
    // bmBits always starts at the first row as stored.
    const uint8_t* src = static_cast<const uint8_t*>(ds.dsBm.bmBits);

    if (h < 0) {
        // Top-down: copy directly
        std::memcpy(result.pixels.data(), src, bytes);
    } else {
        // Bottom-up: flip rows
        const size_t stride = static_cast<size_t>(w * 4);
        for (int row = 0; row < absH; ++row) {
            std::memcpy(result.pixels.data() + row * stride,
                        src + (absH - 1 - row) * stride,
                        stride);
        }
    }

    // Un-premultiply alpha so Dart/Flutter sees straight BGRA.
    // Premultiplied: stored_B = real_B * alpha/255
    // Straight:      real_B   = stored_B * 255 / alpha
    uint8_t* px = result.pixels.data();
    for (int i = 0; i < w * absH; ++i, px += 4) {
        const uint8_t a = px[3];
        if (a == 0) {
            px[0] = px[1] = px[2] = 0;
        } else if (a < 255) {
            px[0] = static_cast<uint8_t>((px[0] * 255u) / a);
            px[1] = static_cast<uint8_t>((px[1] * 255u) / a);
            px[2] = static_cast<uint8_t>((px[2] * 255u) / a);
        }
    }

    return result;
}

// ---------------------------------------------------------------------------
// FIX #1: Icon extraction for UWP / packaged apps.
//
// SHCreateItemFromParsingName fails for AUMIDs (they are not file-system
// paths).  The item we already have from enumerating the AppsFolder *does*
// support IShellItemImageFactory — so we pass the live IShellItem* here.
// For GetAppBitmap (called by AUMID/parsingName string) we re-enumerate
// the folder to find the matching item.
// ---------------------------------------------------------------------------
inline HBITMAP ExtractIconBitmapFromItem(IShellItem* item, int desiredSize = 256) {
    ComPtr<IShellItemImageFactory> factory;
    if (FAILED(item->QueryInterface(IID_PPV_ARGS(&factory))))
        return nullptr;

    // SIIGBF_RESIZETOFIT | SIIGBF_ICONONLY avoids slow thumbnail generation
    // for document-type apps and always returns the app icon.
    SIZE sz{desiredSize, desiredSize};
    HBITMAP bitmap = nullptr;
    HRESULT hr = factory->GetImage(sz, SIIGBF_RESIZETOFIT | SIIGBF_ICONONLY, &bitmap);
    if (FAILED(hr) || !bitmap) {
        sz = {48, 48};
        hr = factory->GetImage(sz, SIIGBF_RESIZETOFIT | SIIGBF_ICONONLY, &bitmap);
    }
    return SUCCEEDED(hr) ? bitmap : nullptr;
}

inline std::wstring ReadStringProp(IPropertyStore* store, const PROPERTYKEY& key) {
    PROPVARIANT pv;
    PropVariantInit(&pv);
    std::wstring result;
    if (SUCCEEDED(store->GetValue(key, &pv))) {
        PWSTR text = nullptr;
        if (SUCCEEDED(PropVariantToStringAlloc(pv, &text)) && text) {
            result = text;
            CoTaskMemFree(text);
        }
    }
    PropVariantClear(&pv);
    return result;
}

// ---------------------------------------------------------------------------
// FIX #3: Resolve executable & arguments.
//
// BHID_SFUIObject → IShellLink does NOT work for items in the virtual
// AppsFolder; that handler is simply not implemented for those items.
//
// Strategy:
//  a) If the parsingName ends in .exe  →  that IS the executable.
//  b) Try IShellItem2 → PKEY_Link_TargetParsingPath (works for .lnk that
//     the shell exposes as app entries, e.g. classic Win32 shortcuts).
//  c) For packaged (UWP/MSIX) apps, PKEY_AppUserModel_PackageInstallPath
//     + PKEY_AppUserModel_RelativeApplicationID give us the host exe.
//     We compose the full path from those two.
// ---------------------------------------------------------------------------

// {9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3}, 5  — package install path
static const PROPERTYKEY PKEY_AppUserModel_PackageInstallPath = {
    {0x9F4C2855, 0x9F79, 0x4B39, {0xA8, 0xD0, 0xE1, 0xD4, 0x2D, 0xE1, 0xD5, 0xF3}}, 5
};
// // {9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3}, 8  — relative exe inside package
// static const PROPERTYKEY PKEY_AppUserModel_HostEnvironment = {
//     {0x9F4C2855, 0x9F79, 0x4B39, {0xA8, 0xD0, 0xE1, 0xD4, 0x2D, 0xE1, 0xD5, 0xF3}}, 8
// };

inline void ResolveExecutableAndArgs(IShellItem* item,
                                     const std::wstring& parsingName,
                                     std::wstring& outExe,
                                     std::wstring& outArgs)
{
    outExe.clear();
    outArgs.clear();

    // ── (a) Plain .exe in AppsFolder ────────────────────────────────────────
    if (parsingName.size() > 4) {
        auto ext = parsingName.substr(parsingName.size() - 4);
        // lowercase compare
        for (auto& c : ext) c = static_cast<wchar_t>(towlower(c));
        if (ext == L".exe") {
            outExe = parsingName;
            return;
        }
    }

    // ── (b) Shell link (classic Win32 shortcut exposed as app entry) ─────────
    // Use IShellItem2 property store with the link target key.
    ComPtr<IShellItem2> item2;
    if (SUCCEEDED(item->QueryInterface(IID_PPV_ARGS(&item2)))) {
        PWSTR target = nullptr;
        if (SUCCEEDED(item2->GetString(PKEY_Link_TargetParsingPath, &target))
            && target && target[0]) {
            outExe = target;
            CoTaskMemFree(target);

            // Arguments from the same property store
            PWSTR args = nullptr;
            if (SUCCEEDED(item2->GetString(PKEY_Link_Arguments_Custom, &args))
                && args) {
                outArgs = args;
                CoTaskMemFree(args);
            }
            return;
        }
        if (target) CoTaskMemFree(target);
    }

    // ── (c) Packaged (UWP/MSIX) app ─────────────────────────────────────────
    // Read install path from property store; the actual host exe is
    // usually not directly walkable without package identity, so we just
    // return the install root so the caller knows where the app lives.
    ComPtr<IPropertyStore> store;
    if (SUCCEEDED(item->BindToHandler(nullptr, BHID_PropertyStore,
                                      IID_PPV_ARGS(&store)))) {
        std::wstring installPath =
            ReadStringProp(store.Get(), PKEY_AppUserModel_PackageInstallPath);
        if (!installPath.empty()) {
            outExe = installPath; // root of the package (closest we can get)
        }
        // outArgs stays empty — packaged apps are launched via AUMID
    }
}

} // namespace detail

// ---------------------------------------------------------------------------
// GetAllApps — enumerate shell:AppsFolder
// ---------------------------------------------------------------------------
inline std::vector<AppInfo> GetAllApps() {
    std::vector<AppInfo> apps;

    HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    const bool weInitCom = SUCCEEDED(hr);

    ComPtr<IShellItem> appsFolder;
    hr = SHGetKnownFolderItem(FOLDERID_AppsFolder, KF_FLAG_DEFAULT, nullptr,
                              IID_PPV_ARGS(&appsFolder));
    if (FAILED(hr)) { if (weInitCom) CoUninitialize(); return apps; }

    ComPtr<IEnumShellItems> enumerator;
    hr = appsFolder->BindToHandler(nullptr, BHID_EnumItems,
                                   IID_PPV_ARGS(&enumerator));
    if (FAILED(hr)) { if (weInitCom) CoUninitialize(); return apps; }

    ComPtr<IShellItem> item;
    ULONG fetched = 0;

    while (enumerator->Next(1, &item, &fetched) == S_OK && fetched) {
        AppInfo info;

        PWSTR name = nullptr;
        if (SUCCEEDED(item->GetDisplayName(SIGDN_NORMALDISPLAY, &name)) && name) {
            info.name = name;
            CoTaskMemFree(name);
        }

        PWSTR parsing = nullptr;
        if (SUCCEEDED(item->GetDisplayName(SIGDN_DESKTOPABSOLUTEPARSING, &parsing))
            && parsing) {
            info.parsingName = parsing;
            CoTaskMemFree(parsing);
        }

        ComPtr<IPropertyStore> store;
        if (SUCCEEDED(item->BindToHandler(nullptr, BHID_PropertyStore,
                                          IID_PPV_ARGS(&store)))) {
            info.appUserModelId =
                detail::ReadStringProp(store.Get(), PKEY_AppUserModel_ID);
        }

        detail::ResolveExecutableAndArgs(item.Get(), info.parsingName,
                                         info.executable, info.arguments);

        if (!info.name.empty() &&
            (!info.parsingName.empty() || !info.appUserModelId.empty())) {
            apps.push_back(std::move(info));
        }

        item.Reset();
        fetched = 0;
    }

    if (weInitCom) CoUninitialize();
    return apps;
}

inline std::future<std::vector<AppInfo>> GetAllAppsAsync() {
    return std::async(std::launch::async,
                      []() -> std::vector<AppInfo> { return GetAllApps(); });
}

// ---------------------------------------------------------------------------
// GetAppBitmap — fetch icon by parsingName or AUMID.
//
// FIX #1 continued: for UWP/packaged apps the parsingName is an AUMID like
// "Microsoft.WindowsStore_8wekyb3d8bbwe!App", not a file-system path.
// SHCreateItemFromParsingName works only for file-system items.
// We must resolve the item through the AppsFolder namespace instead.
// ---------------------------------------------------------------------------
namespace detail {

inline ComPtr<IShellItem> FindItemInAppsFolder(const std::wstring& parsingName) {
    ComPtr<IShellItem> appsFolder;
    if (FAILED(SHGetKnownFolderItem(FOLDERID_AppsFolder, KF_FLAG_DEFAULT,
                                    nullptr, IID_PPV_ARGS(&appsFolder))))
        return nullptr;

    ComPtr<IEnumShellItems> enumerator;
    if (FAILED(appsFolder->BindToHandler(nullptr, BHID_EnumItems,
                                         IID_PPV_ARGS(&enumerator))))
        return nullptr;

    ComPtr<IShellItem> item;
    ULONG fetched = 0;

    while (enumerator->Next(1, &item, &fetched) == S_OK && fetched) {
        PWSTR parsing = nullptr;
        if (SUCCEEDED(item->GetDisplayName(SIGDN_DESKTOPABSOLUTEPARSING, &parsing))
            && parsing) {
            bool match = (_wcsicmp(parsing, parsingName.c_str()) == 0);
            CoTaskMemFree(parsing);
            if (match) return item;
        }

        // Also match by AUMID (for callers who pass the AUMID string directly)
        ComPtr<IPropertyStore> store;
        if (SUCCEEDED(item->BindToHandler(nullptr, BHID_PropertyStore,
                                          IID_PPV_ARGS(&store)))) {
            PROPVARIANT pv;
            PropVariantInit(&pv);
            if (SUCCEEDED(store->GetValue(PKEY_AppUserModel_ID, &pv))) {
                PWSTR aumid = nullptr;
                if (SUCCEEDED(PropVariantToStringAlloc(pv, &aumid)) && aumid) {
                    bool match = (_wcsicmp(aumid, parsingName.c_str()) == 0);
                    CoTaskMemFree(aumid);
                    PropVariantClear(&pv);
                    if (match) return item;
                }
            }
            PropVariantClear(&pv);
        }

        item.Reset();
        fetched = 0;
    }

    return nullptr;
}

} // namespace detail

inline AppBitmap GetAppBitmap(const std::wstring& parsingName,
                              int desiredSize = 256) {
    AppBitmap result;
    if (parsingName.empty()) return result;

    HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    const bool weInitCom = SUCCEEDED(hr);

    // First try the fast path: file-system item (ends in .exe or is a real path)
    ComPtr<IShellItem> item;
    hr = SHCreateItemFromParsingName(parsingName.c_str(), nullptr,
                                     IID_PPV_ARGS(&item));
    if (FAILED(hr) || !item) {
        // Slow path: walk AppsFolder to find the matching virtual item.
        // This is the path taken for all UWP / MSIX / packaged apps.
        item = detail::FindItemInAppsFolder(parsingName);
    }

    if (item) {
        HBITMAP bitmap = detail::ExtractIconBitmapFromItem(item.Get(), desiredSize);
        if (bitmap) {
            result = detail::HBitmapToAppBitmap(bitmap);
            DeleteObject(bitmap);
        }
    }

    if (weInitCom) CoUninitialize();
    return result;
}

inline std::future<AppBitmap> GetAppBitmapAsync(const std::wstring& parsingName,
                                                int desiredSize = 256) {
    return std::async(std::launch::async,
                      [parsingName, desiredSize]() -> AppBitmap {
                          return GetAppBitmap(parsingName, desiredSize);
                      });
}