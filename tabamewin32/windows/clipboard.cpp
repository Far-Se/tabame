#ifndef TABAMEWIN32_CLIPBOARD
#define TABAMEWIN32_CLIPBOARD

#include <windows.h>
#include <atlimage.h>
#include <fstream>
#include <vector>
#include <string>
#include <gdiplus.h>

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

// ---------------------------------------------------------------------------
// Save HBITMAP to PNG file via GDI+
// ---------------------------------------------------------------------------
bool SaveHbitmapToPngFile(HBITMAP hbitmap, const std::string &imagePath)
{
    if (hbitmap == nullptr)
        return false;

    std::vector<BYTE> buf;
    IStream *stream = nullptr;
    CreateStreamOnHGlobal(0, TRUE, &stream);

    CImage image;
    image.Attach(hbitmap);
    image.Save(stream, Gdiplus::ImageFormatPNG);

    ULARGE_INTEGER liSize;
    IStream_Size(stream, &liSize);
    DWORD len = liSize.LowPart;
    IStream_Reset(stream);
    buf.resize(len);
    IStream_Read(stream, buf.data(), len);
    stream->Release();

    std::fstream fi;
    fi.open(imagePath, std::fstream::binary | std::fstream::out);
    fi.write(reinterpret_cast<const char *>(buf.data()), buf.size() * sizeof(BYTE));
    fi.close();

    return true;
}

// ---------------------------------------------------------------------------
// Save clipboard bitmap to PNG
// ---------------------------------------------------------------------------
void SaveClipboardImageAsPngFile(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
{
    const flutter::EncodableMap &args =
        std::get<flutter::EncodableMap>(*method_call.arguments());
    std::string imagePath =
        std::get<std::string>(args.at(flutter::EncodableValue("imagePath")));

    flutter::EncodableMap resultMap;
    HBITMAP hbitmap = nullptr;

    OpenClipboard(nullptr);
    hbitmap = static_cast<HBITMAP>(GetClipboardData(CF_BITMAP));
    CloseClipboard();

    if (SaveHbitmapToPngFile(hbitmap, imagePath))
    {
        resultMap[flutter::EncodableValue("imagePath")] =
            flutter::EncodableValue(imagePath.c_str());
    }

    result->Success(flutter::EncodableValue(resultMap));
}

// ---------------------------------------------------------------------------
// Copy image file to clipboard as CF_BITMAP
// ---------------------------------------------------------------------------
bool CopyImageToClipboard(const wchar_t *filename)
{
    bool success = false;
    Gdiplus::Bitmap *gdibmp = Gdiplus::Bitmap::FromFile(filename);
    if (gdibmp)
    {
        HBITMAP hbitmap;
        gdibmp->GetHBITMAP(0, &hbitmap);
        if (OpenClipboard(nullptr))
        {
            EmptyClipboard();
            DIBSECTION ds;
            if (GetObject(hbitmap, sizeof(DIBSECTION), &ds))
            {
                HDC hdc = GetDC(HWND_DESKTOP);
                HBITMAP hbitmap_ddb = CreateDIBitmap(hdc, &ds.dsBmih, CBM_INIT,
                                                     ds.dsBm.bmBits,
                                                     reinterpret_cast<BITMAPINFO *>(&ds.dsBmih),
                                                     DIB_RGB_COLORS);
                ReleaseDC(HWND_DESKTOP, hdc);
                SetClipboardData(CF_BITMAP, hbitmap_ddb);
                // Note: do NOT DeleteObject(hbitmap_ddb) — clipboard owns it now
                success = true;
            }
            CloseClipboard();
        }
        DeleteObject(hbitmap);
        delete gdibmp;
    }
    return success;
}

#endif // TABAMEWIN32_CLIPBOARD
