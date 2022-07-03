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

// Check windows
#if _WIN32 || _WIN64
#if _WIN64
#define ENV64BIT
#else
#define ENV32BIT
#endif
#endif

// Check GCC
#if __GNUC__
#if __x86_64__ || __ppc64__
#define ENV64BIT
#else
#define ENV32BIT
#endif
#endif

typedef struct
{
    WORD idReserved; // must be 0
    WORD idType;     // 1 = ICON, 2 = CURSOR
    WORD idCount;    // number of images (and ICONDIRs)

} ICONHEADER;

typedef struct
{
    BYTE bWidth;
    BYTE bHeight;
    BYTE bColorCount;
    BYTE bReserved;
    WORD wPlanes;   // for cursors, this field = wXHotSpot
    WORD wBitCount; // for cursors, this field = wYHotSpot
    DWORD dwBytesInRes;
    DWORD dwImageOffset; // file-offset to the start of ICONIMAGE

} ICONDIR;

static UINT NumBitmapBytes(BITMAP *pBitmap)
{
    int nWidthBytes = pBitmap->bmWidthBytes;
    if (nWidthBytes & 3)
        nWidthBytes = (nWidthBytes + 4) & ~3;

    return nWidthBytes * pBitmap->bmHeight;
}

static UINT WriteIconData(BYTE *buffer, int *pBufferOffset, HBITMAP hBitmap)
{
    BITMAP bmp{};
    int i;
    BYTE *pIconData;

    UINT nBitmapBytes;

    GetObject(hBitmap, sizeof(BITMAP), &bmp);

    nBitmapBytes = NumBitmapBytes(&bmp);

    pIconData = (BYTE *)malloc(nBitmapBytes);

    GetBitmapBits(hBitmap, nBitmapBytes, pIconData);
    for (i = bmp.bmHeight - 1; i >= 0; i--)
    {
        memcpy(&buffer[*pBufferOffset], pIconData + (i * bmp.bmWidthBytes), bmp.bmWidthBytes);
        (*pBufferOffset) += bmp.bmWidthBytes;
        if (bmp.bmWidthBytes & 3)
        {
            DWORD padding = 0;
            memcpy(&buffer[*pBufferOffset], &padding, static_cast<size_t>(4) - bmp.bmWidthBytes);
            (*pBufferOffset) += 4 - bmp.bmWidthBytes;
        }
    }

    free(pIconData);

    return nBitmapBytes;
}

BOOL convertIconToBytes(HICON hIcon, BYTE *buffer)
{
    int nNumIcons = 1;
    int bufferOffset = 0;

    if (hIcon == 0 || nNumIcons < 1)
        return 0;

    ICONHEADER iconheader{};
    iconheader.idReserved = 0;            // Must be 0
    iconheader.idType = 1;                // Type 1 = ICON (type 2 = CURSOR)
    iconheader.idCount = (BYTE)nNumIcons; // number of ICONDIRs
    memcpy(&(buffer[bufferOffset]), &iconheader, sizeof(iconheader));
    bufferOffset += sizeof(iconheader);

    bufferOffset += sizeof(ICONDIR) * nNumIcons;
    ICONINFO iconInfo;
    BITMAP bmpColor{}, bmpMask{};
    // GetIconBitmapInfo(hIcon, &iconInfo, &bmpColor, &bmpMask);

    if (!GetIconInfo(hIcon, &iconInfo))
        return FALSE;

    if (!GetObject(iconInfo.hbmColor, sizeof(BITMAP), &bmpColor))
        return FALSE;

    if (!GetObject(iconInfo.hbmMask, sizeof(BITMAP), &bmpMask))
        return FALSE;

    int buffOffset = bufferOffset;

    BITMAPINFOHEADER biHeader;
    UINT nImageBytes;
    nImageBytes = NumBitmapBytes(&bmpColor) + NumBitmapBytes(&bmpMask);
    ZeroMemory(&biHeader, sizeof(biHeader));
    biHeader.biSize = sizeof(biHeader);
    biHeader.biWidth = bmpColor.bmWidth;
    biHeader.biHeight = bmpColor.bmHeight * 2; // height of color+mono
    biHeader.biPlanes = bmpColor.bmPlanes;
    biHeader.biBitCount = bmpColor.bmBitsPixel;
    biHeader.biSizeImage = nImageBytes;
    memcpy(&(buffer[bufferOffset]), &biHeader, sizeof(biHeader));
    bufferOffset += sizeof(biHeader);
    WriteIconData(buffer, &bufferOffset, iconInfo.hbmColor);
    WriteIconData(buffer, &bufferOffset, iconInfo.hbmMask);

    DeleteObject(iconInfo.hbmColor);
    DeleteObject(iconInfo.hbmMask);
    bufferOffset = sizeof(ICONHEADER);

    // Secon Part;
    ICONDIR iconDir{};
    UINT nColorCount;
    nImageBytes = NumBitmapBytes(&bmpColor) + NumBitmapBytes(&bmpMask);
    if (bmpColor.bmBitsPixel >= 8)
        nColorCount = 0;
    else
        nColorCount = 1 << (bmpColor.bmBitsPixel * bmpColor.bmPlanes);
    iconDir.bWidth = (BYTE)bmpColor.bmWidth;
    iconDir.bHeight = (BYTE)bmpColor.bmHeight;
    iconDir.bColorCount = (BYTE)nColorCount;
    iconDir.bReserved = 0;
    iconDir.wPlanes = bmpColor.bmPlanes;
    iconDir.wBitCount = bmpColor.bmBitsPixel;
    iconDir.dwBytesInRes = sizeof(BITMAPINFOHEADER) + nImageBytes;
    iconDir.dwImageOffset = buffOffset;
    memcpy(&buffer[bufferOffset], &iconDir, sizeof(iconDir));
    (bufferOffset) += sizeof(iconDir);
    DeleteObject(iconInfo.hbmColor);
    DeleteObject(iconInfo.hbmMask);

    return 1;
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