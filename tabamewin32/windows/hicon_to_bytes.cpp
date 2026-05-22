#include <atlstr.h>
#include <cassert>
#include <commctrl.h>
#include <commoncontrols.h>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <mmc.h>
#include <shellapi.h>
#include <shlobj.h>
#include <tchar.h>
#include <vector>
#include <windows.h>
using namespace std;

struct ICONDIRENTRY {
  UCHAR nWidth;
  UCHAR nHeight;
  UCHAR nNumColorsInPalette;
  UCHAR nReserved;
  WORD nNumColorPlanes;
  WORD nBitsPerPixel;
  ULONG nDataLength;
  ULONG nOffset;
};

bool GetIconData(HICON hIcon, int nColorBits, std::vector<char> &buff) {
  HDC dc = CreateCompatibleDC(NULL);
  if (!dc)
    return false;

  ICONINFO iconInfo = {};
  if (!GetIconInfo(hIcon, &iconInfo)) {
    DeleteDC(dc);
    return false;
  }

  // Helper to clean up all resources and return
  auto Cleanup = [&](bool success) -> bool {
    DeleteObject(iconInfo.hbmColor);
    DeleteObject(iconInfo.hbmMask);
    DeleteDC(dc);
    return success;
  };

  // --- Query color bitmap dimensions ---
  BITMAPINFO bmInfo = {};
  bmInfo.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bmInfo.bmiHeader.biBitCount = 0;
  if (!GetDIBits(dc, iconInfo.hbmColor, 0, 0, NULL, &bmInfo, DIB_RGB_COLORS))
    return Cleanup(false);

  if (bmInfo.bmiHeader.biSizeImage == 0)
    return Cleanup(false);

  // --- Allocate BITMAPINFO with room for palette ---
  int nBmInfoSize = sizeof(BITMAPINFOHEADER);
  if (nColorBits < 24)
    nBmInfoSize += sizeof(RGBQUAD) * (1ULL << nColorBits);

  std::vector<UCHAR> bitmapInfo(nBmInfoSize);
  BITMAPINFO *pBmInfo = (BITMAPINFO *)bitmapInfo.data();
  memcpy(pBmInfo, &bmInfo, sizeof(BITMAPINFOHEADER));

  // --- Get color pixel data ---
  std::vector<UCHAR> bits(bmInfo.bmiHeader.biSizeImage);
  pBmInfo->bmiHeader.biBitCount = (WORD)nColorBits;
  pBmInfo->bmiHeader.biCompression = BI_RGB;

  if (!GetDIBits(dc, iconInfo.hbmColor, 0, bmInfo.bmiHeader.biHeight,
                 bits.data(), pBmInfo, DIB_RGB_COLORS))
    return Cleanup(false);

  // After forcing biBitCount the driver may leave biSizeImage = 0 — compute
  // manually
  if (pBmInfo->bmiHeader.biSizeImage == 0) {
    DWORD stride =
        ((pBmInfo->bmiHeader.biWidth * pBmInfo->bmiHeader.biBitCount + 31) /
         32) *
        4;
    pBmInfo->bmiHeader.biSizeImage = stride * abs(pBmInfo->bmiHeader.biHeight);
  }
  if (pBmInfo->bmiHeader.biSizeImage == 0)
    return Cleanup(false);

  // --- Query mask bitmap ---
  BITMAPINFO maskInfo = {};
  maskInfo.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  maskInfo.bmiHeader.biBitCount = 0;
  if (!GetDIBits(dc, iconInfo.hbmMask, 0, 0, NULL, &maskInfo, DIB_RGB_COLORS))
    return Cleanup(false);
  if (maskInfo.bmiHeader.biBitCount != 1)
    return Cleanup(false);

  // --- Get mask pixel data ---
  std::vector<UCHAR> maskBits(maskInfo.bmiHeader.biSizeImage);
  std::vector<UCHAR> maskInfoBytes(sizeof(BITMAPINFO) + 2 * sizeof(RGBQUAD));
  BITMAPINFO *pMaskInfo = (BITMAPINFO *)maskInfoBytes.data();
  memcpy(pMaskInfo, &maskInfo, sizeof(maskInfo));

  if (!GetDIBits(dc, iconInfo.hbmMask, 0, maskInfo.bmiHeader.biHeight,
                 maskBits.data(), pMaskInfo, DIB_RGB_COLORS))
    return Cleanup(false);

  // --- Build ICO header (6 bytes) ---
  char icoHeader[6] = {0, 0, 1, 0, 1, 0};
  buff.insert(buff.end(), icoHeader, icoHeader + sizeof(icoHeader));

  // --- Build ICONDIRENTRY ---
  ICONDIRENTRY dir = {};
  dir.nWidth = (UCHAR)pBmInfo->bmiHeader.biWidth;
  dir.nHeight = (UCHAR)pBmInfo->bmiHeader.biHeight;
  dir.nNumColorsInPalette = (nColorBits == 4 ? 16 : 0);
  dir.nReserved = 0;
  dir.nNumColorPlanes = 0;
  dir.nBitsPerPixel = pBmInfo->bmiHeader.biBitCount;
  dir.nDataLength = pBmInfo->bmiHeader.biSizeImage +
                    pMaskInfo->bmiHeader.biSizeImage + nBmInfoSize;
  dir.nOffset = sizeof(icoHeader) + sizeof(dir);
  buff.insert(buff.end(), reinterpret_cast<const char *>(&dir),
              reinterpret_cast<const char *>(&dir) + sizeof(dir));

  // --- Write BITMAPINFOHEADER + pixel data + mask ---
  // ICO format requires biHeight to cover both color and mask rows
  int nBitsSize = pBmInfo->bmiHeader.biSizeImage;
  pBmInfo->bmiHeader.biHeight *= 2;
  pBmInfo->bmiHeader.biCompression = 0;
  pBmInfo->bmiHeader.biSizeImage += pMaskInfo->bmiHeader.biSizeImage;

  buff.insert(buff.end(), reinterpret_cast<const char *>(&pBmInfo->bmiHeader),
              reinterpret_cast<const char *>(&pBmInfo->bmiHeader) +
                  nBmInfoSize);
  buff.insert(buff.end(), reinterpret_cast<const char *>(bits.data()),
              reinterpret_cast<const char *>(bits.data()) + nBitsSize);
  buff.insert(buff.end(), reinterpret_cast<const char *>(maskBits.data()),
              reinterpret_cast<const char *>(maskBits.data()) +
                  pMaskInfo->bmiHeader.biSizeImage);

  return Cleanup(true);
}

HICON getIconFromFile(wstring file, int index = 0) {
  HICON hIcon;
  LPWSTR filePath = const_cast<LPTSTR>(file.c_str());
  if (file.find(L".dll") != std::string::npos) {

    ExtractIconEx(filePath, index, &hIcon, NULL, 1);
  } else {
    HINSTANCE instance = GetModuleHandle(NULL);
    WORD iconID = 0;
    hIcon = ExtractAssociatedIcon(instance, filePath, &iconID);
  }
  return hIcon;
}
