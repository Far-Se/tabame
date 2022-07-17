#include <tchar.h>
#include <iostream>
#include <windows.h>
#include <fstream>
#include <cassert>
#include <shellapi.h>
#include <shlobj.h>
#include <mmc.h>
#include <commoncontrols.h>
#include <atlstr.h>
#include <vector>
#include <cstdlib>
using namespace std;

struct ICONDIRENTRY
{
    UCHAR nWidth;
    UCHAR nHeight;
    UCHAR nNumColorsInPalette;
    UCHAR nReserved;
    WORD nNumColorPlanes;
    WORD nBitsPerPixel;
    ULONG nDataLength;
    ULONG nOffset;
};

bool GetIconData(HICON hIcon, int nColorBits, std::vector<char> &buff)
{
    HDC dc = CreateCompatibleDC(NULL);
    char icoHeader[6] = {0, 0, 1, 0, 1, 0};
    buff.insert(buff.end(), reinterpret_cast<const char *>(icoHeader), reinterpret_cast<const char *>(icoHeader) + sizeof(icoHeader));

    ICONINFO iconInfo;
    GetIconInfo(hIcon, &iconInfo);
    BITMAPINFO bmInfo = {0};
    bmInfo.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bmInfo.bmiHeader.biBitCount = 0;
    if (!GetDIBits(dc, iconInfo.hbmColor, 0, 0, NULL, &bmInfo, DIB_RGB_COLORS))
    {
        return false;
    }

    int nBmInfoSize = sizeof(BITMAPINFOHEADER);
    if (nColorBits < 24)
    {
        nBmInfoSize += sizeof(RGBQUAD) * (int)(static_cast<unsigned long long>(1) << nColorBits);
    }

    std::vector<UCHAR> bitmapInfo;
    bitmapInfo.resize(nBmInfoSize);
    BITMAPINFO *pBmInfo = (BITMAPINFO *)bitmapInfo.data();
    memcpy(pBmInfo, &bmInfo, sizeof(BITMAPINFOHEADER));

    if (!bmInfo.bmiHeader.biSizeImage)
        return false;
    std::vector<UCHAR> bits;
    bits.resize(bmInfo.bmiHeader.biSizeImage);
    pBmInfo->bmiHeader.biBitCount = (WORD)nColorBits;
    pBmInfo->bmiHeader.biCompression = BI_RGB;
    if (!GetDIBits(dc, iconInfo.hbmColor, 0, bmInfo.bmiHeader.biHeight, bits.data(), pBmInfo, DIB_RGB_COLORS))
    {
        return false;
    }

    BITMAPINFO maskInfo = {0};
    maskInfo.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    maskInfo.bmiHeader.biBitCount = 0;
    if (!GetDIBits(dc, iconInfo.hbmMask, 0, 0, NULL, &maskInfo, DIB_RGB_COLORS) || maskInfo.bmiHeader.biBitCount != 1)
        return false;

    std::vector<UCHAR> maskBits;
    maskBits.resize(maskInfo.bmiHeader.biSizeImage);
    std::vector<UCHAR> maskInfoBytes;
    maskInfoBytes.resize(sizeof(BITMAPINFO) + 2 * sizeof(RGBQUAD));
    BITMAPINFO *pMaskInfo = (BITMAPINFO *)maskInfoBytes.data();
    memcpy(pMaskInfo, &maskInfo, sizeof(maskInfo));
    if (!GetDIBits(dc, iconInfo.hbmMask, 0, maskInfo.bmiHeader.biHeight, maskBits.data(), pMaskInfo, DIB_RGB_COLORS))
    {
        return false;
    }

    ICONDIRENTRY dir;
    dir.nWidth = (UCHAR)pBmInfo->bmiHeader.biWidth;
    dir.nHeight = (UCHAR)pBmInfo->bmiHeader.biHeight;
    dir.nNumColorsInPalette = (nColorBits == 4 ? 16 : 0);
    dir.nReserved = 0;
    dir.nNumColorPlanes = 0;
    dir.nBitsPerPixel = pBmInfo->bmiHeader.biBitCount;
    dir.nDataLength = pBmInfo->bmiHeader.biSizeImage + pMaskInfo->bmiHeader.biSizeImage + nBmInfoSize;
    dir.nOffset = sizeof(dir) + sizeof(icoHeader);
    buff.insert(buff.end(), reinterpret_cast<const char *>(&dir), reinterpret_cast<const char *>(&dir) + sizeof(dir));
    int nBitsSize = pBmInfo->bmiHeader.biSizeImage;
    pBmInfo->bmiHeader.biHeight *= 2;
    pBmInfo->bmiHeader.biCompression = 0;
    pBmInfo->bmiHeader.biSizeImage += pMaskInfo->bmiHeader.biSizeImage;
    buff.insert(buff.end(), reinterpret_cast<const char *>(&pBmInfo->bmiHeader), reinterpret_cast<const char *>(&pBmInfo->bmiHeader) + nBmInfoSize);

    buff.insert(buff.end(), reinterpret_cast<const char *>(bits.data()), reinterpret_cast<const char *>(bits.data()) + nBitsSize);
    buff.insert(buff.end(), reinterpret_cast<const char *>(maskBits.data()), reinterpret_cast<const char *>(maskBits.data()) + pMaskInfo->bmiHeader.biSizeImage);

    DeleteObject(iconInfo.hbmColor);
    DeleteObject(iconInfo.hbmMask);

    DeleteDC(dc);

    return true;
}
HICON getIconFromFile(wstring file, int index = 0)
{
    HICON hIcon;
    LPWSTR filePath = const_cast<LPTSTR>(file.c_str());
    if (file.find(L".dll") != std::string::npos)
    {

        ExtractIconEx(filePath, index, &hIcon, NULL, 1);
    }
    else
    {
        HINSTANCE instance = GetModuleHandle(NULL);
        WORD iconID = 0;
        hIcon = ExtractAssociatedIcon(instance, filePath, &iconID);
    }
    return hIcon;
}