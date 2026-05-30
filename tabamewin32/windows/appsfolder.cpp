#include <propkey.h>
#include <propvarutil.h>
#include <shellapi.h>
#include <shlguid.h>
#include <shlobj.h>
#include <shlwapi.h>
#include <shobjidl.h>
#include <windows.h>
#include <wrl/client.h>

#include <cstdint>
#include <filesystem>
#include <future>
#include <string>
#include <vector>

#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "propsys.lib")

using Microsoft::WRL::ComPtr;
namespace fs = std::filesystem;

struct AppInfo {
  std::wstring name;
  // For protocol-URI entries (steam://, epicgames://, …) this is the path to
  // the backing .url file on disk; for Win32 .lnk shortcuts it is the .lnk
  // path; for plain .exe entries it equals parsingName.
  std::wstring executable;
  std::wstring arguments;
  std::wstring appUserModelId;
  std::wstring parsingName;
};

struct AppBitmap {
  std::vector<uint8_t> pixels; // BGRA, premultiplied alpha already un-done
  int width = 0;
  int height = 0;
};

// PKEY_Link_TargetParsingPath and PKEY_Link_Arguments are declared extern in
// propkey.h; their definitions live in propsys.lib (already linked above).
// We just need the lib to be linked — no local redefinition needed.
#pragma comment(lib, "propsys.lib") // already listed above, harmless duplicate

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
  if (!hbmp)
    return result;

  DIBSECTION ds{};
  if (GetObject(hbmp, sizeof(ds), &ds) != sizeof(ds)) {
    // Not a DIB section — fall back to GetDIBits (icons from .exe files)
    BITMAP bm{};
    if (!GetObject(hbmp, sizeof(bm), &bm))
      return result;

    BITMAPINFOHEADER bi{};
    bi.biSize = sizeof(bi);
    bi.biWidth = bm.bmWidth;
    bi.biHeight = -bm.bmHeight;
    bi.biPlanes = 1;
    bi.biBitCount = 32;
    bi.biCompression = BI_RGB;

    const size_t bytes = static_cast<size_t>(bm.bmWidth * 4) * bm.bmHeight;
    result.pixels.resize(bytes);
    result.width = bm.bmWidth;
    result.height = bm.bmHeight;

    HDC hdc = GetDC(nullptr);
    GetDIBits(hdc, hbmp, 0, bm.bmHeight, result.pixels.data(),
              reinterpret_cast<BITMAPINFO *>(&bi), DIB_RGB_COLORS);
    ReleaseDC(nullptr, hdc);

    // Force alpha to 255 for plain HBITMAP (no real alpha channel)
    for (size_t i = 3; i < bytes; i += 4)
      result.pixels[i] = 255;

    return result;
  }

  // DIB section: ds.dsBm.bmBits points directly at the pixel data.
  const int w = ds.dsBm.bmWidth;
  const int h = ds.dsBm.bmHeight;
  if (w <= 0 || h == 0 || !ds.dsBm.bmBits)
    return result;

  const int absH = (h < 0) ? -h : h;
  const size_t bytes = static_cast<size_t>(w * 4) * absH;

  result.pixels.resize(bytes);
  result.width = w;
  result.height = absH;

  // The DIB section is top-down when biHeight < 0, bottom-up when > 0.
  // bmBits always starts at the first row as stored.
  const uint8_t *src = static_cast<const uint8_t *>(ds.dsBm.bmBits);

  if (h < 0) {
    // Top-down: copy directly
    std::memcpy(result.pixels.data(), src, bytes);
  } else {
    // Bottom-up: flip rows
    const size_t stride = static_cast<size_t>(w * 4);
    for (int row = 0; row < absH; ++row) {
      std::memcpy(result.pixels.data() + row * stride,
                  src + (absH - 1 - row) * stride, stride);
    }
  }

  // Un-premultiply alpha so Dart/Flutter sees straight BGRA.
  // Premultiplied: stored_B = real_B * alpha/255
  // Straight:      real_B   = stored_B * 255 / alpha
  uint8_t *px = result.pixels.data();
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
// CropAndScaleBitmap: if the actual icon content occupies only a small
// region of the bitmap (padded by transparency), crop to that region and
// scale it up to desiredSize x desiredSize using nearest-neighbour.
// This fixes .url file icons that come back padded with transparent space.
// ---------------------------------------------------------------------------
inline AppBitmap CropAndScaleIfPadded(AppBitmap src, int desiredSize) {
  if (src.pixels.empty())
    return src;

  const int w = src.width;
  const int h = src.height;

  // Skip the outer 5% on each side (likely a decorative border).
  // Then check the next 5% band — if it's fully transparent, the icon
  // is small and centered; crop to where content actually starts.
  int skip = max(1, w * 5 / 100);  // 5% of width (use width for both axes)
  int probe = max(1, w * 5 / 100); // next 5% band to check

  // Check top band [skip .. skip+probe)
  auto bandTransparent = [&](int x0, int y0, int x1, int y1) -> bool {
    for (int y = y0; y < y1; ++y)
      for (int x = x0; x < x1; ++x)
        if (src.pixels[(y * w + x) * 4 + 3] > 8)
          return false;
    return true;
  };

  bool topClear = bandTransparent(skip, skip, w - skip, skip + probe);
  bool bottomClear =
      bandTransparent(skip, h - skip - probe, w - skip, h - skip);
  bool leftClear = bandTransparent(skip, skip, skip + probe, h - skip);
  bool rightClear = bandTransparent(w - skip - probe, skip, w - skip, h - skip);

  if (!topClear && !bottomClear && !leftClear && !rightClear)
    return src; // icon already fills the canvas, nothing to do

  // Find bounding box of non-transparent pixels starting from skip+probe
  // inward.
  int startX = skip + probe;
  int startY = skip + probe;
  int endX = w - skip - probe;
  int endY = h - skip - probe;

  int minX = endX, maxX = startX - 1;
  int minY = endY, maxY = startY - 1;

  for (int y = startY; y < endY; ++y) {
    for (int x = startX; x < endX; ++x) {
      if (src.pixels[(y * w + x) * 4 + 3] > 8) {
        if (x < minX)
          minX = x;
        if (x > maxX)
          maxX = x;
        if (y < minY)
          minY = y;
        if (y > maxY)
          maxY = y;
      }
    }
  }

  if (maxX < minX || maxY < minY)
    return src; // nothing found

  int contentW = maxX - minX + 1;
  int contentH = maxY - minY + 1;

  // Scale the cropped region up to desiredSize x desiredSize (bilinear).
  AppBitmap result;
  result.width = desiredSize;
  result.height = desiredSize;
  result.pixels.resize(static_cast<size_t>(desiredSize * desiredSize * 4));

  for (int dy = 0; dy < desiredSize; ++dy) {
    for (int dx = 0; dx < desiredSize; ++dx) {
      float sx = minX + (dx + 0.5f) * contentW / desiredSize - 0.5f;
      float sy = minY + (dy + 0.5f) * contentH / desiredSize - 0.5f;

      int x0 = static_cast<int>(sx), y0 = static_cast<int>(sy);
      int x1 = x0 + 1, y1 = y0 + 1;
      float fx = sx - x0, fy = sy - y0;

      x0 = max(0, min(w - 1, x0));
      x1 = max(0, min(w - 1, x1));
      y0 = max(0, min(h - 1, y0));
      y1 = max(0, min(h - 1, y1));

      for (int c = 0; c < 4; ++c) {
        float v = src.pixels[(y0 * w + x0) * 4 + c] * (1 - fx) * (1 - fy) +
                  src.pixels[(y0 * w + x1) * 4 + c] * fx * (1 - fy) +
                  src.pixels[(y1 * w + x0) * 4 + c] * (1 - fx) * fy +
                  src.pixels[(y1 * w + x1) * 4 + c] * fx * fy;
        result.pixels[(dy * desiredSize + dx) * 4 + c] =
            static_cast<uint8_t>(v + 0.5f);
      }
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
inline HBITMAP ExtractIconBitmapFromItem(IShellItem *item,
                                         int desiredSize = 256) {
  ComPtr<IShellItemImageFactory> factory;
  if (FAILED(item->QueryInterface(IID_PPV_ARGS(&factory))))
    return nullptr;

  SIZE sz{desiredSize, desiredSize};
  HBITMAP bitmap = nullptr;

  // SIIGBF_SCALEUP ensures the icon is scaled up to fill desiredSize,
  // preventing the "tiny icon in a sea of transparency" problem from
  // .url files whose native icon is smaller than desiredSize.
  HRESULT hr = factory->GetImage(
      sz, SIIGBF_RESIZETOFIT | SIIGBF_SCALEUP | SIIGBF_ICONONLY, &bitmap);

  if (FAILED(hr) || !bitmap) {
    // Some .url / internet-shortcut items only expose their icon via the
    // thumbnail path — drop SIIGBF_ICONONLY as a fallback.
    hr = factory->GetImage(sz, SIIGBF_RESIZETOFIT | SIIGBF_SCALEUP, &bitmap);
  }

  if (FAILED(hr) || !bitmap) {
    // Last resort: smaller fixed size.
    sz = {48, 48};
    hr = factory->GetImage(
        sz, SIIGBF_RESIZETOFIT | SIIGBF_SCALEUP | SIIGBF_ICONONLY, &bitmap);
  }

  return SUCCEEDED(hr) ? bitmap : nullptr;
}

inline std::wstring ReadStringProp(IPropertyStore *store,
                                   const PROPERTYKEY &key) {
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
    {0x9F4C2855,
     0x9F79,
     0x4B39,
     {0xA8, 0xD0, 0xE1, 0xD4, 0x2D, 0xE1, 0xD5, 0xF3}},
    5};
// {9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3}, 8  — relative exe inside package
// static const PROPERTYKEY PKEY_AppUserModel_HostEnvironment = {
//     {0x9F4C2855, 0x9F79, 0x4B39, {0xA8, 0xD0, 0xE1, 0xD4, 0x2D, 0xE1, 0xD5,
//     0xF3}}, 8
// };

// Returns true if the string looks like a protocol URI (contains "://" and
// does NOT look like a Windows file path).
inline bool IsProtocolUri(const std::wstring &s) {
  auto pos = s.find(L"://");
  if (pos == std::wstring::npos)
    return false;
  // A file-system path on Windows either starts with a drive letter (C:\)
  // or a UNC prefix (\\). Neither contains "://".
  return true;
}

inline void ResolveExecutableAndArgs(IShellItem *item,
                                     const std::wstring &parsingName,
                                     std::wstring &outExe,
                                     std::wstring &outArgs) {
  outExe.clear();
  outArgs.clear();

  // ── (a) Plain .exe in AppsFolder ────────────────────────────────────────
  if (parsingName.size() > 4) {
    auto ext = parsingName.substr(parsingName.size() - 4);
    for (auto &c : ext)
      c = static_cast<wchar_t>(towlower(c));
    if (ext == L".exe") {
      outExe = parsingName;
      return;
    }
  }

  // Get IShellItem2 once — used in both (b) and (c).
  ComPtr<IShellItem2> item2;
  item->QueryInterface(IID_PPV_ARGS(&item2));

  // ── (b) Protocol-URI entries (steam://, epicgames://, battle.net://, …) ──
  // The parsingName IS the URI. The item is backed by a .url Internet
  // Shortcut file on disk. Read its file-system path from PKEY_ItemPathDisplay
  // so callers can use it (e.g. to extract the icon).
  if (IsProtocolUri(parsingName)) {
    if (item2) {
      PWSTR filePath = nullptr;
      // PKEY_ItemPathDisplay is the full file-system path of the item.
      if (SUCCEEDED(item2->GetString(PKEY_ItemPathDisplay, &filePath)) &&
          filePath && filePath[0]) {
        outExe = filePath; // path to the .url file on disk
        CoTaskMemFree(filePath);
        return;
      }
      if (filePath)
        CoTaskMemFree(filePath);

      // Fallback: PKEY_ParsingPath sometimes carries the .url path.
      PWSTR parsingPath = nullptr;
      if (SUCCEEDED(item2->GetString(PKEY_ParsingPath, &parsingPath)) &&
          parsingPath && parsingPath[0] &&
          !IsProtocolUri(parsingPath)) { // must not be another URI
        outExe = parsingPath;
        CoTaskMemFree(parsingPath);
        return;
      }
      if (parsingPath)
        CoTaskMemFree(parsingPath);
    }
    // Could not resolve the .url file path — leave outExe empty.
    return;
  }

  // ── (c) Shell link (classic Win32 shortcut exposed as app entry) ─────────
  if (item2) {
    PWSTR target = nullptr;
    if (SUCCEEDED(item2->GetString(PKEY_Link_TargetParsingPath, &target)) &&
        target && target[0]) {
      outExe = target;
      CoTaskMemFree(target);

      PWSTR args = nullptr;
      if (SUCCEEDED(item2->GetString(PKEY_Link_Arguments, &args)) && args) {
        outArgs = args;
        CoTaskMemFree(args);
      }
      return;
    }
    if (target)
      CoTaskMemFree(target);
  }

  // ── (d) Packaged (UWP/MSIX) app ─────────────────────────────────────────
  ComPtr<IPropertyStore> store;
  if (SUCCEEDED(item->BindToHandler(nullptr, BHID_PropertyStore,
                                    IID_PPV_ARGS(&store)))) {
    std::wstring installPath =
        ReadStringProp(store.Get(), PKEY_AppUserModel_PackageInstallPath);
    if (!installPath.empty())
      outExe = installPath;
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
  if (FAILED(hr)) {
    if (weInitCom)
      CoUninitialize();
    return apps;
  }

  ComPtr<IEnumShellItems> enumerator;
  hr = appsFolder->BindToHandler(nullptr, BHID_EnumItems,
                                 IID_PPV_ARGS(&enumerator));
  if (FAILED(hr)) {
    if (weInitCom)
      CoUninitialize();
    return apps;
  }

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
    if (SUCCEEDED(
            item->GetDisplayName(SIGDN_DESKTOPABSOLUTEPARSING, &parsing)) &&
        parsing) {
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

  if (weInitCom)
    CoUninitialize();
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

inline ComPtr<IShellItem>
FindItemInAppsFolder(const std::wstring &parsingName) {
  ComPtr<IShellItem> appsFolder;
  if (FAILED(SHGetKnownFolderItem(FOLDERID_AppsFolder, KF_FLAG_DEFAULT, nullptr,
                                  IID_PPV_ARGS(&appsFolder))))
    return nullptr;

  ComPtr<IEnumShellItems> enumerator;
  if (FAILED(appsFolder->BindToHandler(nullptr, BHID_EnumItems,
                                       IID_PPV_ARGS(&enumerator))))
    return nullptr;

  ComPtr<IShellItem> item;
  ULONG fetched = 0;

  while (enumerator->Next(1, &item, &fetched) == S_OK && fetched) {
    PWSTR parsing = nullptr;
    if (SUCCEEDED(
            item->GetDisplayName(SIGDN_DESKTOPABSOLUTEPARSING, &parsing)) &&
        parsing) {
      bool match = (_wcsicmp(parsing, parsingName.c_str()) == 0);
      CoTaskMemFree(parsing);
      if (match)
        return item;
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
          if (match)
            return item;
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

inline AppBitmap GetAppBitmap(const std::wstring &parsingName,
                              int desiredSize = 256) {
  AppBitmap result;
  if (parsingName.empty())
    return result;

  HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  const bool weInitCom = SUCCEEDED(hr);

  ComPtr<IShellItem> item;

  if (detail::IsProtocolUri(parsingName)) {
    // Protocol-URI entries (steam://, epicgames://, …) are backed by a
    // .url Internet Shortcut file.  We must find that file via the
    // AppsFolder enumerator, read its on-disk path, then create a shell
    // item from THAT path — the .url file has the icon reference embedded.
    ComPtr<IShellItem> virtualItem = detail::FindItemInAppsFolder(parsingName);
    if (virtualItem) {
      // Read the file-system path of the .url file.
      ComPtr<IShellItem2> item2;
      if (SUCCEEDED(virtualItem->QueryInterface(IID_PPV_ARGS(&item2)))) {
        PWSTR filePath = nullptr;
        bool gotPath = false;

        if (SUCCEEDED(item2->GetString(PKEY_ItemPathDisplay, &filePath)) &&
            filePath && filePath[0]) {
          gotPath = true;
        }
        // Fallback key
        if (!gotPath) {
          if (filePath) {
            CoTaskMemFree(filePath);
            filePath = nullptr;
          }
          if (SUCCEEDED(item2->GetString(PKEY_ParsingPath, &filePath)) &&
              filePath && filePath[0] && !detail::IsProtocolUri(filePath)) {
            gotPath = true;
          }
        }

        if (gotPath && filePath) {
          // Create a shell item from the actual .url file path so
          // IShellItemImageFactory can read the embedded icon.
          SHCreateItemFromParsingName(filePath, nullptr, IID_PPV_ARGS(&item));
        }
        if (filePath)
          CoTaskMemFree(filePath);
      }

      // If we still don't have a file-based item, try the virtual item
      // directly — some launchers do register a proper icon factory.
      if (!item)
        item = virtualItem;
    }
  } else {
    // Fast path: file-system item (.exe, .lnk, package install path, …)
    hr = SHCreateItemFromParsingName(parsingName.c_str(), nullptr,
                                     IID_PPV_ARGS(&item));
    if (FAILED(hr) || !item) {
      // Slow path for UWP / MSIX AUMIDs
      item = detail::FindItemInAppsFolder(parsingName);
    }
  }

  if (item) {
    HBITMAP bitmap = detail::ExtractIconBitmapFromItem(item.Get(), desiredSize);
    if (bitmap) {
      result = detail::HBitmapToAppBitmap(bitmap);
      DeleteObject(bitmap);
      // Fix padded .url icons: crop transparent border and scale up.
      result = detail::CropAndScaleIfPadded(std::move(result), desiredSize);
    }
  }

  if (weInitCom)
    CoUninitialize();
  return result;
}

inline std::future<AppBitmap> GetAppBitmapAsync(const std::wstring &parsingName,
                                                int desiredSize = 256) {
  return std::async(std::launch::async,
                    [parsingName, desiredSize]() -> AppBitmap {
                      return GetAppBitmap(parsingName, desiredSize);
                    });
}
