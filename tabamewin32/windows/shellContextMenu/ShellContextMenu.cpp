#include "ShellContextMenu.h"
#include "../include/encoding.h"

#include <ShlObj.h>
#include <Shlwapi.h>
#include <objbase.h>
#include <shellapi.h>

#include <iostream>

// ------------------------------
// Utility
// ------------------------------
std::wstring ShellContextMenu::StripAccelerators(const std::wstring &label) {
  std::wstring result;
  result.reserve(label.size());

  for (size_t i = 0; i < label.size(); ++i) {
    if (label[i] == L'&') {
      if (i + 1 < label.size() && label[i + 1] == L'&') {
        result += L'&';
        ++i;
      }
    } else {
      result += label[i];
    }
  }
  return result;
}

// ------------------------------
// Icon helper (safe fallback)
// ------------------------------
static HICON GetShellItemIconFromPidl(PIDLIST_ABSOLUTE pidl) {
  SHFILEINFOW sfi = {};
  if (SHGetFileInfoW((LPCWSTR)pidl, 0, &sfi, sizeof(sfi),
                     SHGFI_PIDL | SHGFI_ICON | SHGFI_SMALLICON)) {
    return sfi.hIcon;
  }
  return nullptr;
}
// Replace this helper — no longer needed for menu icons:
// static HICON GetShellItemIconFromPidl(...) { ... }

// New helper: convert HBITMAP from menu item to HICON
static HICON HBitmapToHIcon(HBITMAP hBitmap) {
  if (!hBitmap)
    return nullptr;

  BITMAP bm = {};
  if (!GetObject(hBitmap, sizeof(bm), &bm))
    return nullptr;

  int w = bm.bmWidth;
  int h = bm.bmHeight;

  HDC hdcScreen = GetDC(nullptr);
  HDC hdcSrc = CreateCompatibleDC(hdcScreen);
  HDC hdcMask = CreateCompatibleDC(hdcScreen);

  // Read the raw 32bpp pixels including alpha
  BITMAPINFO bmi = {};
  bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bmi.bmiHeader.biWidth = w;
  bmi.bmiHeader.biHeight = -h; // top-down
  bmi.bmiHeader.biPlanes = 1;
  bmi.bmiHeader.biBitCount = 32;
  bmi.bmiHeader.biCompression = BI_RGB;

  std::vector<DWORD> pixels(w * h);
  HDC hdcTmp = CreateCompatibleDC(hdcScreen);
  HBITMAP hOldTmp = (HBITMAP)SelectObject(hdcTmp, hBitmap);
  // GetDIBits directly from the source — preserves the alpha byte
  if (!GetDIBits(hdcTmp, hBitmap, 0, h, pixels.data(), &bmi, DIB_RGB_COLORS)) {
    SelectObject(hdcTmp, hOldTmp);
    DeleteDC(hdcTmp);
    ReleaseDC(nullptr, hdcScreen);
    return nullptr;
  }
  SelectObject(hdcTmp, hOldTmp);
  DeleteDC(hdcTmp);

  // Check if any pixel actually has non-zero alpha.
  // Some shell bitmaps are 32bpp but with alpha=0 everywhere (legacy GDI path).
  bool hasAlpha = false;
  for (const DWORD px : pixels) {
    if ((px >> 24) != 0) {
      hasAlpha = true;
      break;
    }
  }

  // If no alpha data, treat as fully opaque by setting alpha=255 on all pixels
  if (!hasAlpha) {
    for (DWORD &px : pixels)
      px |= 0xFF000000;
  }

  // Create color DIB with corrected pixels
  void *pvBits = nullptr;
  HBITMAP hDib =
      CreateDIBSection(hdcScreen, &bmi, DIB_RGB_COLORS, &pvBits, nullptr, 0);
  if (!hDib) {
    DeleteDC(hdcMask);
    DeleteDC(hdcSrc);
    ReleaseDC(nullptr, hdcScreen);
    return nullptr;
  }
  memcpy(pvBits, pixels.data(), w * h * 4);

  // Build a 1bpp mask from alpha: pixel is "transparent" (mask=1) where
  // alpha==0
  HBITMAP hMask = CreateBitmap(w, h, 1, 1, nullptr);
  HBITMAP hOldMask = (HBITMAP)SelectObject(hdcMask, hMask);
  HBITMAP hOldSrc = (HBITMAP)SelectObject(hdcSrc, hDib);

  for (int y = 0; y < h; ++y) {
    for (int x = 0; x < w; ++x) {
      DWORD px = pixels[y * w + x];
      BYTE alpha = (BYTE)(px >> 24);
      // SetPixel on a 1bpp DC: white=transparent, black=opaque
      SetPixel(hdcMask, x, y, alpha < 128 ? RGB(255, 255, 255) : RGB(0, 0, 0));
    }
  }

  SelectObject(hdcMask, hOldMask);
  SelectObject(hdcSrc, hOldSrc);
  DeleteDC(hdcSrc);
  DeleteDC(hdcMask);
  ReleaseDC(nullptr, hdcScreen);

  ICONINFO ii = {};
  ii.fIcon = TRUE;
  ii.hbmColor = hDib;
  ii.hbmMask = hMask;
  HICON hIcon = CreateIconIndirect(&ii);

  DeleteObject(hDib);
  DeleteObject(hMask);
  return hIcon;
}
// ============================================================
// LEGACY CONTEXT MENU (used for "More options")
// ============================================================
std::vector<ShellMenuItem>
ShellContextMenu::GetMenuItems(const std::wstring &path) {
  std::vector<ShellMenuItem> result;

  HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED |
                                           COINIT_DISABLE_OLE1DDE);

  bool comInit = SUCCEEDED(hr) || hr == RPC_E_CHANGED_MODE;
  if (!comInit)
    return result;

  PIDLIST_ABSOLUTE pidl = nullptr;
  IShellFolder *parentFolder = nullptr;
  IContextMenu *contextMenu = nullptr;
  HMENU hMenu = nullptr;

  hr = SHParseDisplayName(path.c_str(), nullptr, &pidl, 0, nullptr);
  if (FAILED(hr) || !pidl)
    goto Cleanup;

  {
    PCUITEMID_CHILD child = nullptr;

    hr = SHBindToParent(pidl, IID_IShellFolder, (void **)&parentFolder, &child);

    if (FAILED(hr) || !parentFolder)
      goto Cleanup;

    hr = parentFolder->GetUIObjectOf(nullptr, 1, &child, IID_IContextMenu,
                                     nullptr, (void **)&contextMenu);

    if (FAILED(hr) || !contextMenu)
      goto Cleanup;
  }

  hMenu = CreatePopupMenu();
  if (!hMenu)
    goto Cleanup;

  hr = contextMenu->QueryContextMenu(hMenu, 0, 1, 0x7FFF,
                                     CMF_NORMAL | CMF_EXPLORE);

  if (FAILED(hr))
    goto Cleanup;

  {
    int count = GetMenuItemCount(hMenu);

    for (int i = 0; i < count; ++i) {
      WCHAR text[512] = {};

      MENUITEMINFOW mii = {};
      mii.cbSize = sizeof(mii);
      // Add MIIM_BITMAP to get the item's own icon bitmap
      mii.fMask = MIIM_STRING | MIIM_ID | MIIM_STATE | MIIM_FTYPE | MIIM_BITMAP;
      mii.dwTypeData = text;
      mii.cch = ARRAYSIZE(text);

      if (!GetMenuItemInfoW(hMenu, i, TRUE, &mii))
        continue;

      if (mii.fType & MFT_SEPARATOR)
        continue;

      std::wstring label = text;
      if (label.empty())
        continue;

      bool enabled = !(mii.fState & MFS_DISABLED) && !(mii.fState & MFS_GRAYED);
      int cmdOffset = static_cast<int>(mii.wID - 1);

      // Convert the per-item HBITMAP → HICON (nullptr if no bitmap)
      HICON icon = HBitmapToHIcon(mii.hbmpItem);

      result.push_back({
          cmdOffset, StripAccelerators(label), L"", enabled, icon,
          true // we own this icon (created via CreateIconIndirect)
      });
    }
  }

Cleanup:
  if (hMenu)
    DestroyMenu(hMenu);
  if (contextMenu)
    contextMenu->Release();
  if (parentFolder)
    parentFolder->Release();
  if (pidl)
    ILFree(pidl);

  if (comInit && hr != RPC_E_CHANGED_MODE)
    CoUninitialize();

  return result;
}

// ============================================================
// INVOKE (LEGACY EXECUTION)
// ============================================================
bool ShellContextMenu::Invoke(const std::wstring &path,
                              const std::wstring &verb, int id,
                              HWND hwnd) // <-- add hwnd parameter
{
  HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED |
                                           COINIT_DISABLE_OLE1DDE);
  bool comInit = SUCCEEDED(hr) || hr == RPC_E_CHANGED_MODE;
  if (!comInit)
    return false;

  PIDLIST_ABSOLUTE pidl = nullptr;
  IShellFolder *parentFolder = nullptr;
  IContextMenu *contextMenu = nullptr;
  HMENU hMenu = nullptr;
  bool success = false;

  hr = SHParseDisplayName(path.c_str(), nullptr, &pidl, 0, nullptr);
  if (FAILED(hr) || !pidl)
    goto Cleanup;

  {
    PCUITEMID_CHILD child = nullptr;
    hr = SHBindToParent(pidl, IID_IShellFolder, (void **)&parentFolder, &child);
    if (FAILED(hr) || !parentFolder)
      goto Cleanup;

    hr = parentFolder->GetUIObjectOf(nullptr, 1, &child, IID_IContextMenu,
                                     nullptr, (void **)&contextMenu);
    if (FAILED(hr) || !contextMenu)
      goto Cleanup;
  }

  // Must call QueryContextMenu first — initializes the handler internally
  hMenu = CreatePopupMenu();
  if (!hMenu)
    goto Cleanup;

  hr = contextMenu->QueryContextMenu(hMenu, 0, 1, 0x7FFF,
                                     CMF_NORMAL | CMF_EXPLORE);
  if (FAILED(hr))
    goto Cleanup;

  {
    CMINVOKECOMMANDINFOEX ci = {};
    ci.cbSize = sizeof(ci);
    ci.hwnd = hwnd; // valid HWND — many verbs need this
    ci.nShow = SW_SHOWNORMAL;
    ci.fMask = CMIC_MASK_UNICODE;

    std::string ansiVerb = Encoding::WideToAnsi(verb);

    if (id != -1 && verb.empty()) {
      // id is the cmdOffset (0-based) from GetMenuItems,
      // InvokeCommand expects 0-based offset from idCmdFirst=1,
      // so pass id directly as MAKEINTRESOURCE
      ci.lpVerb = MAKEINTRESOURCEA(id);
      ci.lpVerbW = MAKEINTRESOURCEW(id);
    } else {
      ci.lpVerb = ansiVerb.c_str();
      ci.lpVerbW = verb.c_str();
    }

    hr = contextMenu->InvokeCommand(
        reinterpret_cast<LPCMINVOKECOMMANDINFO>(&ci));
    success = SUCCEEDED(hr);
  }

Cleanup:
  if (hMenu)
    DestroyMenu(hMenu);
  if (contextMenu)
    contextMenu->Release();
  if (parentFolder)
    parentFolder->Release();
  if (pidl)
    ILFree(pidl);

  if (comInit && hr != RPC_E_CHANGED_MODE)
    CoUninitialize();

  return success;
}
