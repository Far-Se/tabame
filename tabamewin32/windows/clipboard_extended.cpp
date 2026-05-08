#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <shlobj.h>
#include <shellapi.h>
#include <memory>
#include <sstream>
#include <vector>
#include <algorithm>
#include <string>

// GDI+ requires min/max macros which are disabled by NOMINMAX
// Define them explicitly for GDI+ headers
#ifndef min
#define min(a, b) (((a) < (b)) ? (a) : (b))
#endif
#ifndef max
#define max(a, b) (((a) > (b)) ? (a) : (b))
#endif

// Suppress warnings from GDI+ headers (C4458: declaration hides class member)
#pragma warning(push)
#pragma warning(disable: 4458)
#include <gdiplus.h>
#pragma warning(pop)

#undef min
#undef max
using namespace Gdiplus;
#pragma comment(lib, "gdiplus.lib")

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

namespace ClipboardExtended {

class ClipboardPluginImpl {
 public:
  ClipboardPluginImpl() {}

  virtual ~ClipboardPluginImpl() {}

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    
    const std::string& method = method_call.method_name();
    const auto* arguments = std::get_if<EncodableMap>(method_call.arguments());

    if (method == "copy" || method == "clipboardExtendedCopy") {
      HandleCopy(arguments, std::move(result));
    } else if (method == "copyRichText" || method == "clipboardExtendedCopyRichText") {
      HandleCopyRichText(arguments, std::move(result));
    } else if (method == "copyMultiple" || method == "clipboardExtendedCopyMultiple") {
      HandleCopyMultiple(arguments, std::move(result));
    } else if (method == "copyImage" || method == "clipboardExtendedCopyImage") {
      HandleCopyImage(arguments, std::move(result));
    } else if (method == "paste" || method == "clipboardExtendedPaste") {
      HandlePaste(std::move(result));
    } else if (method == "pasteRichText" || method == "clipboardExtendedPasteRichText") {
      HandlePasteRichText(std::move(result));
    } else if (method == "pasteImage" || method == "clipboardExtendedPasteImage") {
      HandlePasteImage(std::move(result));
    } else if (method == "getContentType" || method == "clipboardExtendedGetContentType") {
      HandleGetContentType(std::move(result));
    } else if (method == "hasData" || method == "clipboardExtendedHasData") {
      HandleHasData(std::move(result));
    } else if (method == "clear" || method == "clipboardExtendedClear") {
      HandleClear(std::move(result));
    } else if (method == "getDataSize" || method == "clipboardExtendedGetDataSize") {
      HandleGetDataSize(std::move(result));
    } else if (method == "startMonitoring" || method == "clipboardExtendedStartMonitoring") {
      result->Success(EncodableValue(true));
    } else if (method == "stopMonitoring" || method == "clipboardExtendedStopMonitoring") {
      result->Success(EncodableValue(true));
    } else {
      result->NotImplemented();
    }
  }

  void HandleCopy(const EncodableMap* arguments,
                  std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
    if (!arguments) {
      result->Error("INVALID_ARGUMENT", "Arguments are required");
      return;
    }

    auto text_it = arguments->find(EncodableValue("text"));
    if (text_it == arguments->end()) {
      result->Error("EMPTY_TEXT", "Text cannot be empty");
      return;
    }

    const auto* text = std::get_if<std::string>(&text_it->second);
    if (!text || text->empty()) {
      result->Error("EMPTY_TEXT", "Text cannot be empty");
      return;
    }

    if (OpenClipboard(nullptr)) {
      EmptyClipboard();
      
      // Convert to wide string for Windows
      int size_needed = MultiByteToWideChar(CP_UTF8, 0, text->c_str(), -1, NULL, 0);
      std::vector<wchar_t> wstr(size_needed);
      MultiByteToWideChar(CP_UTF8, 0, text->c_str(), -1, &wstr[0], size_needed);
      
      HGLOBAL hMem = GlobalAlloc(GMEM_MOVEABLE, (wstr.size()) * sizeof(wchar_t));
      if (hMem) {
        wchar_t* pMem = (wchar_t*)GlobalLock(hMem);
        wcscpy_s(pMem, wstr.size(), &wstr[0]);
        GlobalUnlock(hMem);
        SetClipboardData(CF_UNICODETEXT, hMem);
      }
      CloseClipboard();
      result->Success(EncodableValue(true));
    } else {
      result->Error("COPY_ERROR", "Failed to open clipboard");
    }
  }

  void HandleCopyRichText(const EncodableMap* arguments,
                          std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
    if (!arguments) {
      result->Error("INVALID_ARGUMENT", "Arguments are required");
      return;
    }

    std::string text;
    std::string html;

    auto text_it = arguments->find(EncodableValue("text"));
    if (text_it != arguments->end()) {
      const auto* text_ptr = std::get_if<std::string>(&text_it->second);
      if (text_ptr) text = *text_ptr;
    }

    auto html_it = arguments->find(EncodableValue("html"));
    if (html_it != arguments->end()) {
      const auto* html_ptr = std::get_if<std::string>(&html_it->second);
      if (html_ptr) html = *html_ptr;
    }

    if (text.empty() && html.empty()) {
      result->Error("EMPTY_CONTENT", "Either text or html must be provided");
      return;
    }

    if (OpenClipboard(nullptr)) {
      EmptyClipboard();
      
      // Set text
      if (!text.empty()) {
        int size_needed = MultiByteToWideChar(CP_UTF8, 0, text.c_str(), -1, NULL, 0);
        std::vector<wchar_t> wstr(size_needed);
        MultiByteToWideChar(CP_UTF8, 0, text.c_str(), -1, &wstr[0], size_needed);
        
        HGLOBAL hMem = GlobalAlloc(GMEM_MOVEABLE, (wstr.size()) * sizeof(wchar_t));
        if (hMem) {
          wchar_t* pMem = (wchar_t*)GlobalLock(hMem);
          wcscpy_s(pMem, wstr.size(), &wstr[0]);
          GlobalUnlock(hMem);
          SetClipboardData(CF_UNICODETEXT, hMem);
        }
      }

      // Set HTML if available
      if (!html.empty()) {
        UINT cf_html = RegisterClipboardFormatA("HTML Format");
        if (cf_html != 0) {
          std::string html_format = "Version:0.9\r\nStartHTML:00000000\r\nEndHTML:00000000\r\nStartFragment:00000000\r\nEndFragment:00000000\r\n";
          html_format += "<html><body><!--StartFragment-->";
          html_format += html;
          html_format += "<!--EndFragment--></body></html>";
          
          HGLOBAL hMem = GlobalAlloc(GMEM_MOVEABLE, html_format.size() + 1);
          if (hMem) {
            char* pMem = (char*)GlobalLock(hMem);
            strcpy_s(pMem, html_format.size() + 1, html_format.c_str());
            GlobalUnlock(hMem);
            SetClipboardData(cf_html, hMem);
          }
        }
      }

      CloseClipboard();
      result->Success(EncodableValue(true));
    } else {
      result->Error("COPY_RICH_ERROR", "Failed to open clipboard");
    }
  }

  void HandleCopyMultiple(const EncodableMap* arguments,
                          std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
    if (!arguments) {
      result->Error("INVALID_ARGUMENT", "Arguments are required");
      return;
    }

    auto formats_it = arguments->find(EncodableValue("formats"));
    if (formats_it == arguments->end()) {
      result->Error("EMPTY_FORMATS", "At least one format must be provided");
      return;
    }

    const auto* formats = std::get_if<EncodableMap>(&formats_it->second);
    if (!formats || formats->empty()) {
      result->Error("EMPTY_FORMATS", "At least one format must be provided");
      return;
    }

    if (OpenClipboard(nullptr)) {
      EmptyClipboard();

      // Handle image first
      auto image_it = formats->find(EncodableValue("image/png"));
      if (image_it != formats->end()) {
        const auto* image_bytes = std::get_if<EncodableList>(&image_it->second);
        if (image_bytes && !image_bytes->empty()) {
          std::vector<uint8_t> bytes;
          for (const auto& byte_val : *image_bytes) {
            if (const auto* byte_int32 = std::get_if<int32_t>(&byte_val)) {
              bytes.push_back(static_cast<uint8_t>(*byte_int32));
            } else if (const auto* byte_int64 = std::get_if<int64_t>(&byte_val)) {
              bytes.push_back(static_cast<uint8_t>(*byte_int64));
            }
          }
          if (!bytes.empty()) {
            SetClipboardImage(bytes);
          }
        }
      }

      // Handle text
      auto text_it = formats->find(EncodableValue("text/plain"));
      if (text_it != formats->end()) {
        const auto* text = std::get_if<std::string>(&text_it->second);
        if (text && !text->empty()) {
          int size_needed = MultiByteToWideChar(CP_UTF8, 0, text->c_str(), -1, NULL, 0);
          std::vector<wchar_t> wstr(size_needed);
          MultiByteToWideChar(CP_UTF8, 0, text->c_str(), -1, &wstr[0], size_needed);
          
          HGLOBAL hMem = GlobalAlloc(GMEM_MOVEABLE, (wstr.size()) * sizeof(wchar_t));
          if (hMem) {
            wchar_t* pMem = (wchar_t*)GlobalLock(hMem);
            wcscpy_s(pMem, wstr.size(), &wstr[0]);
            GlobalUnlock(hMem);
            SetClipboardData(CF_UNICODETEXT, hMem);
          }
        }
      }

      // Handle HTML
      auto html_it = formats->find(EncodableValue("text/html"));
      if (html_it != formats->end()) {
        const auto* html = std::get_if<std::string>(&html_it->second);
        if (html && !html->empty()) {
          UINT cf_html = RegisterClipboardFormatA("HTML Format");
          if (cf_html != 0) {
            std::string html_format = "Version:0.9\r\nStartHTML:00000000\r\nEndHTML:00000000\r\nStartFragment:00000000\r\nEndFragment:00000000\r\n";
            html_format += "<html><body><!--StartFragment-->";
            html_format += *html;
            html_format += "<!--EndFragment--></body></html>";
            
            HGLOBAL hMem = GlobalAlloc(GMEM_MOVEABLE, html_format.size() + 1);
            if (hMem) {
              char* pMem = (char*)GlobalLock(hMem);
              strcpy_s(pMem, html_format.size() + 1, html_format.c_str());
              GlobalUnlock(hMem);
              SetClipboardData(cf_html, hMem);
            }
          }
        }
      }

      CloseClipboard();
      result->Success(EncodableValue(true));
    } else {
      result->Error("COPY_MULTIPLE_ERROR", "Failed to open clipboard");
    }
  }

  void HandleCopyImage(const EncodableMap* arguments,
                       std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
    if (!arguments) {
      result->Error("INVALID_ARGUMENT", "Arguments are required");
      return;
    }

    auto image_bytes_it = arguments->find(EncodableValue("imageBytes"));
    if (image_bytes_it == arguments->end()) {
      result->Error("EMPTY_IMAGE", "Image bytes cannot be empty");
      return;
    }

    const auto* image_bytes = std::get_if<EncodableList>(&image_bytes_it->second);
    if (!image_bytes || image_bytes->empty()) {
      result->Error("EMPTY_IMAGE", "Image bytes cannot be empty");
      return;
    }

    std::vector<uint8_t> bytes;
    for (const auto& byte_val : *image_bytes) {
      if (const auto* byte_int32 = std::get_if<int32_t>(&byte_val)) {
        bytes.push_back(static_cast<uint8_t>(*byte_int32));
      } else if (const auto* byte_int64 = std::get_if<int64_t>(&byte_val)) {
        bytes.push_back(static_cast<uint8_t>(*byte_int64));
      }
    }

    if (bytes.empty()) {
      result->Error("EMPTY_IMAGE", "Image bytes cannot be empty");
      return;
    }

    if (OpenClipboard(nullptr)) {
      EmptyClipboard();
      bool success = SetClipboardImage(bytes);
      CloseClipboard();
      
      if (success) {
        result->Success(EncodableValue(true));
      } else {
        result->Error("COPY_IMAGE_ERROR", "Failed to copy image to clipboard");
      }
    } else {
      result->Error("COPY_IMAGE_ERROR", "Failed to open clipboard");
    }
  }
bool SetClipboardImage(const std::vector<uint8_t>& png_bytes) {
  if (png_bytes.empty()) return false;

  auto SetClipboardRawData = [](UINT format, const void* data, size_t size) -> bool {
    if (format == 0 || data == nullptr || size == 0) return false;
    HGLOBAL hData = GlobalAlloc(GMEM_MOVEABLE, size);
    if (!hData) return false;
    void* pData = GlobalLock(hData);
    if (!pData) { GlobalFree(hData); return false; }
    memcpy(pData, data, size);
    GlobalUnlock(hData);
    if (SetClipboardData(format, hData) == NULL) { GlobalFree(hData); return false; }
    return true;
  };

  GdiplusStartupInput gdiplusStartupInput;
  ULONG_PTR gdiplusToken;
  GdiplusStartup(&gdiplusToken, &gdiplusStartupInput, nullptr);

  // Load PNG into GDI+ bitmap
  HGLOBAL hMem = GlobalAlloc(GMEM_MOVEABLE, png_bytes.size());
  if (!hMem) { GdiplusShutdown(gdiplusToken); return false; }
  void* pMem = GlobalLock(hMem);
  if (!pMem) { GlobalFree(hMem); GdiplusShutdown(gdiplusToken); return false; }
  memcpy(pMem, png_bytes.data(), png_bytes.size());
  GlobalUnlock(hMem);

  IStream* pStream = nullptr;
  if (CreateStreamOnHGlobal(hMem, TRUE, &pStream) != S_OK) {
    GlobalFree(hMem);
    GdiplusShutdown(gdiplusToken);
    return false;
  }

  Bitmap* pBitmap = Bitmap::FromStream(pStream);
  if (!pBitmap || pBitmap->GetLastStatus() != Ok) {
    pStream->Release();
    GdiplusShutdown(gdiplusToken);
    if (pBitmap) delete pBitmap;
    return false;
  }

  int width  = pBitmap->GetWidth();
  int height = pBitmap->GetHeight();
  int rowSize = ((width * 32 + 31) / 32) * 4;

  BitmapData bitmapData;
  Rect rect(0, 0, width, height);
  if (pBitmap->LockBits(&rect, ImageLockModeRead, PixelFormat32bppARGB, &bitmapData) != Ok) {
    delete pBitmap;
    pStream->Release();
    GdiplusShutdown(gdiplusToken);
    return false;
  }
  BYTE* pSource = (BYTE*)bitmapData.Scan0;

  // ── CF_DIBV5 — full ARGB transparency, understood by most modern apps ──
  size_t v5Size = sizeof(BITMAPV5HEADER) + rowSize * height;
  HGLOBAL hDibV5 = GlobalAlloc(GMEM_MOVEABLE, v5Size);
  bool dibV5Success = false;
  if (hDibV5) {
    BYTE* pDibV5 = (BYTE*)GlobalLock(hDibV5);
    if (pDibV5) {
      BITMAPV5HEADER* pv5 = (BITMAPV5HEADER*)pDibV5;
      ZeroMemory(pv5, sizeof(BITMAPV5HEADER));
      pv5->bV5Size        = sizeof(BITMAPV5HEADER);
      pv5->bV5Width       = width;
      pv5->bV5Height      = height; // bottom-up
      pv5->bV5Planes      = 1;
      pv5->bV5BitCount    = 32;
      pv5->bV5Compression = BI_BITFIELDS;
      pv5->bV5RedMask     = 0x00FF0000;
      pv5->bV5GreenMask   = 0x0000FF00;
      pv5->bV5BlueMask    = 0x000000FF;
      pv5->bV5AlphaMask   = 0xFF000000; // preserve alpha
      pv5->bV5CSType      = LCS_sRGB;
      pv5->bV5Intent      = LCS_GM_IMAGES;

      BYTE* pBits = pDibV5 + sizeof(BITMAPV5HEADER);
      for (int y = 0; y < height; y++) {
        int dstY = height - 1 - y; // flip to bottom-up
        for (int x = 0; x < width; x++) {
          BYTE b = pSource[y * bitmapData.Stride + x * 4 + 0];
          BYTE g = pSource[y * bitmapData.Stride + x * 4 + 1];
          BYTE r = pSource[y * bitmapData.Stride + x * 4 + 2];
          BYTE a = pSource[y * bitmapData.Stride + x * 4 + 3];
          pBits[dstY * rowSize + x * 4 + 0] = b;
          pBits[dstY * rowSize + x * 4 + 1] = g;
          pBits[dstY * rowSize + x * 4 + 2] = r;
          pBits[dstY * rowSize + x * 4 + 3] = a;
        }
      }
      GlobalUnlock(hDibV5);
      dibV5Success = (SetClipboardData(CF_DIBV5, hDibV5) != NULL);
      if (!dibV5Success) GlobalFree(hDibV5);
    } else {
      GlobalFree(hDibV5);
    }
  }

  // ── CF_DIB fallback — no alpha, composite transparent pixels onto white ──
  // so apps that only read CF_DIB don't see black where transparency was.
  HGLOBAL hDib = GlobalAlloc(GMEM_MOVEABLE, sizeof(BITMAPINFOHEADER) + rowSize * height);
  bool dibSuccess = false;
  if (hDib) {
    BYTE* pDib = (BYTE*)GlobalLock(hDib);
    if (pDib) {
      BITMAPINFOHEADER* pbih = (BITMAPINFOHEADER*)pDib;
      ZeroMemory(pbih, sizeof(BITMAPINFOHEADER));
      pbih->biSize        = sizeof(BITMAPINFOHEADER);
      pbih->biWidth       = width;
      pbih->biHeight      = height;
      pbih->biPlanes      = 1;
      pbih->biBitCount    = 32;
      pbih->biCompression = BI_RGB;

      BYTE* pBits = pDib + sizeof(BITMAPINFOHEADER);
      for (int y = 0; y < height; y++) {
        int dstY = height - 1 - y;
        for (int x = 0; x < width; x++) {
          BYTE b = pSource[y * bitmapData.Stride + x * 4 + 0];
          BYTE g = pSource[y * bitmapData.Stride + x * 4 + 1];
          BYTE r = pSource[y * bitmapData.Stride + x * 4 + 2];
          BYTE a = pSource[y * bitmapData.Stride + x * 4 + 3];
          // Pre-multiply against white so transparency -> white, not black
          pBits[dstY * rowSize + x * 4 + 0] = (BYTE)(b + (255 - a));
          pBits[dstY * rowSize + x * 4 + 1] = (BYTE)(g + (255 - a));
          pBits[dstY * rowSize + x * 4 + 2] = (BYTE)(r + (255 - a));
          pBits[dstY * rowSize + x * 4 + 3] = 0; // ignored by BI_RGB consumers
        }
      }
      GlobalUnlock(hDib);
      dibSuccess = (SetClipboardData(CF_DIB, hDib) != NULL);
      if (!dibSuccess) GlobalFree(hDib);
    } else {
      GlobalFree(hDib);
    }
  }

  pBitmap->UnlockBits(&bitmapData);
  delete pBitmap;
  pStream->Release();
  GdiplusShutdown(gdiplusToken);

  // PNG format for apps like Discord that prefer it
  const UINT pngFormat = RegisterClipboardFormatW(L"PNG");
  const bool pngSuccess = SetClipboardRawData(pngFormat, png_bytes.data(), png_bytes.size());

  return pngSuccess || dibV5Success || dibSuccess;
}

  void HandlePaste(std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
    if (OpenClipboard(nullptr)) {
      if (IsClipboardFormatAvailable(CF_UNICODETEXT)) {
        HGLOBAL hMem = GetClipboardData(CF_UNICODETEXT);
        if (hMem) {
          wchar_t* pMem = (wchar_t*)GlobalLock(hMem);
          int size_needed = WideCharToMultiByte(CP_UTF8, 0, pMem, -1, NULL, 0, NULL, NULL);
          std::vector<char> str(size_needed);
          WideCharToMultiByte(CP_UTF8, 0, pMem, -1, &str[0], size_needed, NULL, NULL);
          GlobalUnlock(hMem);
          
          EncodableMap result_map;
          result_map[EncodableValue("text")] = EncodableValue(std::string(&str[0]));
          result->Success(EncodableValue(result_map));
        } else {
          result->Success(EncodableValue(EncodableMap{{EncodableValue("text"), EncodableValue("")}}));
        }
      } else {
        result->Success(EncodableValue(EncodableMap{{EncodableValue("text"), EncodableValue("")}}));
      }
      CloseClipboard();
    } else {
      result->Error("PASTE_ERROR", "Failed to open clipboard");
    }
  }

  void HandlePasteRichText(std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
    EncodableMap result_map;
    
    if (OpenClipboard(nullptr)) {
      // Get text
      std::string text;
      if (IsClipboardFormatAvailable(CF_UNICODETEXT)) {
        HGLOBAL hMem = GetClipboardData(CF_UNICODETEXT);
        if (hMem) {
          wchar_t* pMem = (wchar_t*)GlobalLock(hMem);
          int size_needed = WideCharToMultiByte(CP_UTF8, 0, pMem, -1, NULL, 0, NULL, NULL);
          std::vector<char> str(size_needed);
          WideCharToMultiByte(CP_UTF8, 0, pMem, -1, &str[0], size_needed, NULL, NULL);
          GlobalUnlock(hMem);
          text = std::string(&str[0]);
        }
      }
      result_map[EncodableValue("text")] = EncodableValue(text);

      // Get HTML
      UINT cf_html = RegisterClipboardFormatA("HTML Format");
      std::string html;
      if (cf_html != 0 && IsClipboardFormatAvailable(cf_html)) {
        HGLOBAL hMem = GetClipboardData(cf_html);
        if (hMem) {
          char* pMem = (char*)GlobalLock(hMem);
          html = std::string(pMem);
          GlobalUnlock(hMem);
        }
      }
      result_map[EncodableValue("html")] = EncodableValue(html);

      result_map[EncodableValue("timestamp")] = EncodableValue(static_cast<int64_t>(GetTickCount64()));
      
      CloseClipboard();
      result->Success(EncodableValue(result_map));
    } else {
      result->Error("PASTE_RICH_ERROR", "Failed to open clipboard");
    }
  }

  void HandlePasteImage(std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
    EncodableMap result_map;
    
    // Initialize GDI+
    GdiplusStartupInput gdiplusStartupInput;
    ULONG_PTR gdiplusToken;
    GdiplusStartup(&gdiplusToken, &gdiplusStartupInput, nullptr);

    Bitmap* pBitmap = nullptr;
    bool clipboardOpened = false;

    // Try multiple approaches to get the image
    // Method 1: Try CF_BITMAP (works for many apps)
    if (!pBitmap && OpenClipboard(nullptr)) {
      clipboardOpened = true;
      if (IsClipboardFormatAvailable(CF_BITMAP)) {
        HBITMAP hBitmap = (HBITMAP)GetClipboardData(CF_BITMAP);
        if (hBitmap) {
          // Create a copy of the bitmap before closing clipboard
          HDC hdcScreen = GetDC(nullptr);
          HDC hdcMem = CreateCompatibleDC(hdcScreen);
          if (hdcMem) {
            BITMAP bm;
            GetObject(hBitmap, sizeof(BITMAP), &bm);
            HBITMAP hBitmapCopy = CreateCompatibleBitmap(hdcScreen, bm.bmWidth, bm.bmHeight);
            if (hBitmapCopy) {
              SelectObject(hdcMem, hBitmapCopy);
              HDC hdcSource = CreateCompatibleDC(hdcScreen);
              if (hdcSource) {
                SelectObject(hdcSource, hBitmap);
                BitBlt(hdcMem, 0, 0, bm.bmWidth, bm.bmHeight, hdcSource, 0, 0, SRCCOPY);
                DeleteDC(hdcSource);
              }
              // Close clipboard now that we have a copy
              CloseClipboard();
              clipboardOpened = false;
              
              pBitmap = Bitmap::FromHBITMAP(hBitmapCopy, nullptr);
              DeleteObject(hBitmapCopy);
              if (pBitmap && pBitmap->GetLastStatus() != Ok) {
                delete pBitmap;
                pBitmap = nullptr;
              }
            }
            DeleteDC(hdcMem);
          }
          ReleaseDC(nullptr, hdcScreen);
        }
      }
      // Close clipboard if Method 1 didn't succeed
      if (clipboardOpened) {
        CloseClipboard();
        clipboardOpened = false;
      }
    }

    // Method 2: Try CF_DIBV5 (Device Independent Bitmap V5 - preferred by modern apps)
    if (!pBitmap && OpenClipboard(nullptr)) {
      clipboardOpened = true;
      UINT dibFormat = CF_DIBV5;
      if (IsClipboardFormatAvailable(CF_DIBV5)) {
        dibFormat = CF_DIBV5;
      } else if (IsClipboardFormatAvailable(CF_DIB)) {
        dibFormat = CF_DIB;
      }
      
      if (dibFormat == CF_DIBV5 || dibFormat == CF_DIB) {
        HGLOBAL hMem = GetClipboardData(dibFormat);
        if (hMem) {
          void* pDib = GlobalLock(hMem);
          if (pDib) {
            BITMAPINFOHEADER* pBih = (BITMAPINFOHEADER*)pDib;
            
            // Validate header
            if (pBih->biSize >= sizeof(BITMAPINFOHEADER) && 
                pBih->biWidth > 0 && pBih->biHeight != 0) {
              
              // Make a complete copy before closing clipboard
              SIZE_T dibSizeT = GlobalSize(hMem);
              DWORD dibSize = (dibSizeT > 0xFFFFFFFF) ? 0xFFFFFFFF : static_cast<DWORD>(dibSizeT);
              std::vector<BYTE> dibData(dibSize);
              memcpy(dibData.data(), pDib, dibSize);
              
              GlobalUnlock(hMem);
              CloseClipboard();
              clipboardOpened = false;
              
              // Now convert DIB to GDI+ Bitmap using CreateDIBSection
              HDC hdc = CreateCompatibleDC(nullptr);
              if (hdc) {
                BITMAPINFO* pbmi = (BITMAPINFO*)dibData.data();
                void* pBits = nullptr;
                
                // Create DIB section - this allocates memory for us
                HBITMAP hDibSection = CreateDIBSection(hdc, pbmi, DIB_RGB_COLORS, &pBits, nullptr, 0);
                if (hDibSection && pBits) {
                  // Calculate source pixel data offset
                  void* pSourceBits = dibData.data() + pBih->biSize;
                  if (pBih->biBitCount <= 8) {
                    int colorTableSize = static_cast<int>((1ULL << pBih->biBitCount) * sizeof(RGBQUAD));
                    pSourceBits = dibData.data() + pBih->biSize + colorTableSize;
                  }
                  
                  // Copy pixel data using SetDIBits (handles all conversions automatically)
                  int height = abs(pBih->biHeight);
                  SelectObject(hdc, hDibSection);
                  SetDIBits(hdc, hDibSection, 0, height, pSourceBits, pbmi, DIB_RGB_COLORS);
                  
                  // Create GDI+ Bitmap from the DIB section
                  pBitmap = Bitmap::FromHBITMAP(hDibSection, nullptr);
                  DeleteObject(hDibSection);
                  
                  if (pBitmap && pBitmap->GetLastStatus() != Ok) {
                    delete pBitmap;
                    pBitmap = nullptr;
                  }
                }
                DeleteDC(hdc);
              }
            } else {
              GlobalUnlock(hMem);
            }
          }
        }
      }
      // Close clipboard if Method 2 didn't succeed
      if (clipboardOpened) {
        CloseClipboard();
        clipboardOpened = false;
      }
    }

    // Method 3: Try CF_HDROP (file paths - when copying files from Explorer)
    if (!pBitmap) {
      if (!clipboardOpened) {
        clipboardOpened = OpenClipboard(nullptr);
      }
      
      if (clipboardOpened && IsClipboardFormatAvailable(CF_HDROP)) {
        HDROP hDrop = (HDROP)GetClipboardData(CF_HDROP);
        if (hDrop) {
          // Get number of files
          UINT fileCount = DragQueryFile(hDrop, 0xFFFFFFFF, nullptr, 0);
          
          // Try each file path
          for (UINT i = 0; i < fileCount && !pBitmap; i++) {
            // Get file path length
            UINT pathLen = DragQueryFile(hDrop, i, nullptr, 0);
            if (pathLen > 0) {
              std::vector<wchar_t> filePath(pathLen + 1);
              if (DragQueryFile(hDrop, i, filePath.data(), pathLen + 1) > 0) {
                // Try to load image from file using GDI+
                pBitmap = Bitmap::FromFile(filePath.data());
                if (pBitmap) {
                  if (pBitmap->GetLastStatus() != Ok) {
                    delete pBitmap;
                    pBitmap = nullptr;
                  } else {
                    // Check if it's actually an image file (by checking file extension)
                    std::wstring path(filePath.data());
                    std::wstring ext = path.substr(path.find_last_of(L".") + 1);
                    // Convert to lowercase for comparison
                    for (wchar_t& c : ext) {
                      c = towlower(c);
                    }
                    
                    // Supported image extensions
                    if (ext != L"jpg" && ext != L"jpeg" && ext != L"png" && 
                        ext != L"bmp" && ext != L"gif" && ext != L"tiff" && 
                        ext != L"tif" && ext != L"ico" && ext != L"webp") {
                      delete pBitmap;
                      pBitmap = nullptr;
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    // Close clipboard if still open
    if (clipboardOpened) {
      CloseClipboard();
    }

    // If we still don't have a bitmap, return error
    if (!pBitmap) {
      GdiplusShutdown(gdiplusToken);
      result->Error("PASTE_IMAGE_ERROR", "No image found in clipboard. Copy an image (not a file) or try pasting after copying image data from a browser/app.");
      return;
    }

    // Convert bitmap to PNG bytes
    IStream* pStream = nullptr;
    if (CreateStreamOnHGlobal(nullptr, TRUE, &pStream) != S_OK) {
      delete pBitmap;
      GdiplusShutdown(gdiplusToken);
      result->Error("PASTE_IMAGE_ERROR", "Failed to create stream");
      return;
    }

    // Save as PNG
    CLSID clsidPng;
    if (CLSIDFromString(L"{557CF406-1A04-11D3-9A73-0000F81EF32E}", &clsidPng) == S_OK) {
      if (pBitmap->Save(pStream, &clsidPng, nullptr) == Ok) {
        // Get stream size
        STATSTG stat;
        if (pStream->Stat(&stat, STATFLAG_NONAME) == S_OK) {
          ULARGE_INTEGER pos;
          LARGE_INTEGER zero = {0};
          pStream->Seek(zero, STREAM_SEEK_SET, &pos);

          // Read PNG bytes
          ULONG bytesRead = 0;
          std::vector<uint8_t> pngBytes(stat.cbSize.LowPart);
          HRESULT hr = pStream->Read(pngBytes.data(), stat.cbSize.LowPart, &bytesRead);
          
          if (SUCCEEDED(hr) && bytesRead > 0) {
            // Convert to EncodableList for Flutter
            EncodableList imageBytes;
            imageBytes.reserve(bytesRead);
            for (ULONG i = 0; i < bytesRead; i++) {
              imageBytes.push_back(EncodableValue(static_cast<int32_t>(pngBytes[i])));
            }
            result_map[EncodableValue("imageBytes")] = EncodableValue(imageBytes);
          }
        }
      }
    }

    pStream->Release();
    delete pBitmap;
    GdiplusShutdown(gdiplusToken);

    if (result_map.find(EncodableValue("imageBytes")) != result_map.end()) {
      result->Success(EncodableValue(result_map));
    } else {
      result->Error("PASTE_IMAGE_ERROR", "Failed to convert image to PNG format");
    }
  }

  void HandleGetContentType(std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
    // Don't access clipboard automatically
    result->Success(EncodableValue("unknown"));
  }

  void HandleHasData(std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
    // Don't access clipboard automatically
    result->Success(EncodableValue(false));
  }

  void HandleClear(std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
    if (OpenClipboard(nullptr)) {
      EmptyClipboard();
      CloseClipboard();
      result->Success(EncodableValue(true));
    } else {
      result->Error("CLEAR_ERROR", "Failed to open clipboard");
    }
  }

  void HandleGetDataSize(std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
    // Don't access clipboard automatically
    result->Success(EncodableValue(0));
  }
};

void HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  static ClipboardPluginImpl plugin;
  plugin.HandleMethodCall(method_call, std::move(result));
}

}  // namespace ClipboardExtended
