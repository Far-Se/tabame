#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <shlobj.h>
#include <shellapi.h>
#include <ole2.h>
#include <memory>
#include <sstream>
#include <vector>
#include <algorithm>
#include <string>
#include <thread>
#include <fstream>
#include <limits>
#include <cstring>
#include <cctype>
#include <bcrypt.h>

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
#pragma comment(lib, "bcrypt.lib")
#pragma comment(lib, "ole32.lib")

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

namespace ClipboardExtended {

// ── Local helpers for background-thread image saving ────────────────────────

// Convert a UTF-8 string (as received over the method channel) to UTF-16 for
// the Win32 file APIs.
static std::wstring Utf8ToWideLocal(const std::string& s) {
  if (s.empty()) return std::wstring();
  const int needed = MultiByteToWideChar(CP_UTF8, 0, s.c_str(),
                                         static_cast<int>(s.size()), nullptr, 0);
  std::wstring w(needed, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()), &w[0],
                      needed);
  return w;
}

// Write raw bytes to a file at a wide path (binary, truncating any existing
// file). Returns false if the file could not be opened or written.
static bool WriteBytesToFileW(const std::wstring& path,
                              const std::vector<uint8_t>& bytes) {
  std::ofstream file(path.c_str(), std::ios::binary | std::ios::trunc);
  if (!file.is_open()) return false;
  if (!bytes.empty()) {
    file.write(reinterpret_cast<const char*>(bytes.data()),
               static_cast<std::streamsize>(bytes.size()));
  }
  return file.good();
}

// Write a text payload through a temporary sibling and replace the destination
// only after the complete value is on disk. A clipboard event can arrive while
// the history process is terminating, so a partial payload must never look
// complete to a later copy operation.
static bool WriteStringToFileAtomicW(const std::wstring& path,
                                     const std::string& value) {
  const std::wstring temporaryPath = path + L".part";
  DeleteFileW(temporaryPath.c_str());

  std::ofstream file(temporaryPath.c_str(), std::ios::binary | std::ios::trunc);
  if (!file.is_open()) return false;
  if (!value.empty()) {
    file.write(value.data(), static_cast<std::streamsize>(value.size()));
  }
  file.close();
  if (!file.good()) {
    DeleteFileW(temporaryPath.c_str());
    return false;
  }

  if (!MoveFileExW(temporaryPath.c_str(), path.c_str(),
                   MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
    DeleteFileW(temporaryPath.c_str());
    return false;
  }
  return true;
}

static bool ReadStringFromFileW(const std::wstring& path, std::string& value) {
  std::ifstream file(path.c_str(), std::ios::binary);
  if (!file.is_open()) return false;
  file.seekg(0, std::ios::end);
  const std::streamoff length = file.tellg();
  if (length < 0) return false;
  file.seekg(0, std::ios::beg);
  value.assign(static_cast<size_t>(length), static_cast<char>(0));
  if (length > 0) {
    file.read(&value[0], length);
  }
  return file.good() || file.eof();
}

static std::string WideToUtf8Local(const std::wstring& value) {
  if (value.empty()) return std::string();
  int needed = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS,
                                   value.data(), static_cast<int>(value.size()),
                                   nullptr, 0, nullptr, nullptr);
  if (needed <= 0) {
    needed = WideCharToMultiByte(CP_UTF8, 0, value.data(),
                                 static_cast<int>(value.size()), nullptr, 0,
                                 nullptr, nullptr);
  }
  if (needed <= 0) return std::string();
  std::string result(static_cast<size_t>(needed), static_cast<char>(0));
  WideCharToMultiByte(CP_UTF8, 0, value.data(),
                      static_cast<int>(value.size()), &result[0], needed,
                      nullptr, nullptr);
  return result;
}

static std::string WidePrefixToUtf8(const std::wstring& value,
                                    size_t characterLimit) {
  if (value.empty() || characterLimit == 0) return std::string();
  size_t count = std::min(characterLimit, value.size());
  if (count < value.size() && count > 0 &&
      value[count - 1] >= 0xD800 && value[count - 1] <= 0xDBFF &&
      value[count] >= 0xDC00 && value[count] <= 0xDFFF) {
    --count;
  }
  return WideToUtf8Local(value.substr(0, count));
}

static std::string Utf8PreviewLocal(const std::string& value,
                                    size_t characterLimit) {
  if (value.empty() || characterLimit == 0) return std::string();
  const std::wstring wide = Utf8ToWideLocal(value);
  if (!wide.empty()) return WidePrefixToUtf8(wide, characterLimit);
  return value.substr(0, std::min(characterLimit, value.size()));
}

static std::string TrimAsciiLocal(const std::string& value) {
  size_t start = 0;
  while (start < value.size() &&
         std::isspace(static_cast<unsigned char>(value[start]))) {
    ++start;
  }
  size_t end = value.size();
  while (end > start &&
         std::isspace(static_cast<unsigned char>(value[end - 1]))) {
    --end;
  }
  return value.substr(start, end - start);
}

// CF_HTML offsets are byte offsets into the original clipboard buffer. The
// history payload stores only the fragment so the copy path can wrap it once,
// without carrying the provider's header and full-document boilerplate.
static std::string ExtractHtmlFragmentLocal(const std::string& value) {
  auto readOffset = [&value](const char* field, size_t& result) -> bool {
    const size_t start = value.find(field);
    if (start == std::string::npos) return false;
    size_t cursor = start + std::strlen(field);
    if (cursor >= value.size() || value[cursor] < '0' || value[cursor] > '9') return false;
    uint64_t parsed = 0;
    while (cursor < value.size() && value[cursor] >= '0' && value[cursor] <= '9') {
      parsed = (parsed * 10) + static_cast<uint64_t>(value[cursor] - '0');
      if (parsed > value.size()) return false;
      ++cursor;
    }
    result = static_cast<size_t>(parsed);
    return true;
  };

  size_t start = 0;
  size_t end = 0;
  if (readOffset("StartFragment:", start) && readOffset("EndFragment:", end) &&
      end > start && end <= value.size()) {
    return TrimAsciiLocal(value.substr(start, end - start));
  }

  const std::string startMarker = "<!--StartFragment-->";
  const std::string endMarker = "<!--EndFragment-->";
  const size_t markerStart = value.find(startMarker);
  const size_t markerEnd = value.find(endMarker);
  if (markerStart != std::string::npos && markerEnd > markerStart) {
    return TrimAsciiLocal(value.substr(markerStart + startMarker.size(),
                                        markerEnd - markerStart - startMarker.size()));
  }
  return TrimAsciiLocal(value);
}

// MD5 hex digest of a byte buffer, byte-for-byte identical to Dart's
// `md5.convert(bytes).toString()`. Used so image entries dedup consistently with
// the existing clipboard-history format (`img-bytes:<md5>`).
static std::string Md5Hex(const std::vector<uint8_t>& data) {
  std::string result;
  BCRYPT_ALG_HANDLE alg = nullptr;
  if (!BCRYPT_SUCCESS(
          BCryptOpenAlgorithmProvider(&alg, BCRYPT_MD5_ALGORITHM, nullptr, 0))) {
    return result;
  }
  BCRYPT_HASH_HANDLE hash = nullptr;
  if (BCRYPT_SUCCESS(BCryptCreateHash(alg, &hash, nullptr, 0, nullptr, 0, 0))) {
    if (BCRYPT_SUCCESS(BCryptHashData(
            hash, reinterpret_cast<PUCHAR>(const_cast<uint8_t*>(data.data())),
            static_cast<ULONG>(data.size()), 0))) {
      UCHAR digest[16] = {0};
      if (BCRYPT_SUCCESS(BCryptFinishHash(hash, digest, sizeof(digest), 0))) {
        static const char* kHex = "0123456789abcdef";
        result.reserve(32);
        for (unsigned char b : digest) {
          result.push_back(kHex[b >> 4]);
          result.push_back(kHex[b & 0x0F]);
        }
      }
    }
    BCryptDestroyHash(hash);
  }
  BCryptCloseAlgorithmProvider(alg, 0);
  return result;
}

// Hash the exact same logical content as Dart's
// md5(utf8.encode('text:<text>\\nhtml:<html>')) without constructing a second
// 30 MB concatenated buffer.
static std::string Md5HexTextHtml(const std::string& text,
                                  const std::string& html) {
  std::string result;
  BCRYPT_ALG_HANDLE alg = nullptr;
  if (!BCRYPT_SUCCESS(
          BCryptOpenAlgorithmProvider(&alg, BCRYPT_MD5_ALGORITHM, nullptr, 0))) {
    return result;
  }

  BCRYPT_HASH_HANDLE hash = nullptr;
  bool success = BCRYPT_SUCCESS(
      BCryptCreateHash(alg, &hash, nullptr, 0, nullptr, 0, 0));
  auto update = [&hash, &success](const char* data, size_t length) {
    while (success && length > 0) {
      const ULONG chunk = static_cast<ULONG>(std::min(
          length, static_cast<size_t>(std::numeric_limits<ULONG>::max())));
      success = BCRYPT_SUCCESS(BCryptHashData(
          hash, reinterpret_cast<PUCHAR>(const_cast<char*>(data)), chunk, 0));
      data += chunk;
      length -= chunk;
    }
  };

  update("text:", 5);
  update(text.data(), text.size());
  update("\nhtml:", 6);
  update(html.data(), html.size());

  if (success) {
    UCHAR digest[16] = {0};
    success = BCRYPT_SUCCESS(BCryptFinishHash(hash, digest, sizeof(digest), 0));
    if (success) {
      static const char* kHex = "0123456789abcdef";
      result.reserve(32);
      for (unsigned char b : digest) {
        result.push_back(kHex[b >> 4]);
        result.push_back(kHex[b & 0x0F]);
      }
    }
  }

  if (hash != nullptr) BCryptDestroyHash(hash);
  BCryptCloseAlgorithmProvider(alg, 0);
  return result;
}

static bool WriteRichTextToClipboard(const std::string& text,
                                     const std::string& html) {
  if (text.empty() && html.empty()) return false;
  if (!OpenClipboard(nullptr)) return false;

  EmptyClipboard();
  bool success = true;

  if (!text.empty()) {
    const int sizeNeeded = MultiByteToWideChar(
        CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()), nullptr, 0);
    if (sizeNeeded <= 0) {
      success = false;
    } else {
      std::vector<wchar_t> wide(static_cast<size_t>(sizeNeeded) + 1, static_cast<wchar_t>(0));
      MultiByteToWideChar(CP_UTF8, 0, text.c_str(),
                          static_cast<int>(text.size()), wide.data(), sizeNeeded);
      const SIZE_T bytes = (wide.size()) * sizeof(wchar_t);
      HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, bytes);
      if (memory == nullptr) {
        success = false;
      } else {
        wchar_t* target = static_cast<wchar_t*>(GlobalLock(memory));
        if (target == nullptr) {
          GlobalFree(memory);
          success = false;
        } else {
          memcpy(target, wide.data(), bytes);
          GlobalUnlock(memory);
          if (SetClipboardData(CF_UNICODETEXT, memory) == nullptr) {
            GlobalFree(memory);
            success = false;
          }
        }
      }
    }
  }

  if (success && !html.empty()) {
    const UINT cfHtml = RegisterClipboardFormatA("HTML Format");
    if (cfHtml == 0) {
      success = false;
    } else {
      std::string htmlFormat =
          "Version:0.9\r\nStartHTML:00000000\r\nEndHTML:00000000\r\n"
          "StartFragment:00000000\r\nEndFragment:00000000\r\n";
      htmlFormat += "<html><body><!--StartFragment-->";
      htmlFormat += html;
      htmlFormat += "<!--EndFragment--></body></html>";
      HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, htmlFormat.size() + 1);
      if (memory == nullptr) {
        success = false;
      } else {
        char* target = static_cast<char*>(GlobalLock(memory));
        if (target == nullptr) {
          GlobalFree(memory);
          success = false;
        } else {
          memcpy(target, htmlFormat.c_str(), htmlFormat.size() + 1);
          GlobalUnlock(memory);
          if (SetClipboardData(cfHtml, memory) == 0) {
            GlobalFree(memory);
            success = false;
          }
        }
      }
    }
  }

  CloseClipboard();
  return success;
}

// RAII initializer for an OLE/COM apartment on the calling thread. Browser
// clipboard data (Chrome, Edge, …) is delivered through the OLE clipboard, and
// GDI+ image codecs use COM internally — both require COM to be initialized on
// whatever thread touches them. The platform thread already has this; a worker
// thread does not, so clipboard image capture/encoding silently fails there
// unless we initialize COM ourselves.
struct ScopedOleApartment {
  const HRESULT hr;
  ScopedOleApartment() : hr(OleInitialize(nullptr)) {}
  ~ScopedOleApartment() {
    if (SUCCEEDED(hr)) OleUninitialize();
  }
  ScopedOleApartment(const ScopedOleApartment&) = delete;
  ScopedOleApartment& operator=(const ScopedOleApartment&) = delete;
};

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
    } else if (method == "saveImage" || method == "clipboardExtendedSaveImage") {
      HandleSaveImage(arguments, std::move(result));
    } else if (method == "captureTextToFiles" || method == "clipboardExtendedCaptureTextToFiles") {
      HandleCaptureTextToFiles(arguments, std::move(result));
    } else if (method == "copyContentFromFiles" || method == "clipboardExtendedCopyContentFromFiles") {
      HandleCopyContentFromFiles(arguments, std::move(result));
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
        std::vector<uint8_t> bytes;
        // Fast path: typed data (Uint8List) — a single byte buffer, no unboxing.
        if (const auto* byte_vec = std::get_if<std::vector<uint8_t>>(&image_it->second)) {
          bytes = *byte_vec;
        } else if (const auto* image_bytes = std::get_if<EncodableList>(&image_it->second)) {
          // Backward-compat: list of ints.
          bytes.reserve(image_bytes->size());
          for (const auto& byte_val : *image_bytes) {
            if (const auto* byte_int32 = std::get_if<int32_t>(&byte_val)) {
              bytes.push_back(static_cast<uint8_t>(*byte_int32));
            } else if (const auto* byte_int64 = std::get_if<int64_t>(&byte_val)) {
              bytes.push_back(static_cast<uint8_t>(*byte_int64));
            }
          }
        }
        if (!bytes.empty()) {
          SetClipboardImage(bytes);
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

    std::vector<uint8_t> bytes;
    // Fast path: typed data (Uint8List) — a single byte buffer, no unboxing.
    if (const auto* byte_vec = std::get_if<std::vector<uint8_t>>(&image_bytes_it->second)) {
      bytes = *byte_vec;
    } else if (const auto* image_bytes = std::get_if<EncodableList>(&image_bytes_it->second)) {
      // Backward-compat: list of ints.
      bytes.reserve(image_bytes->size());
      for (const auto& byte_val : *image_bytes) {
        if (const auto* byte_int32 = std::get_if<int32_t>(&byte_val)) {
          bytes.push_back(static_cast<uint8_t>(*byte_int32));
        } else if (const auto* byte_int64 = std::get_if<int64_t>(&byte_val)) {
          bytes.push_back(static_cast<uint8_t>(*byte_int64));
        }
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

  // Captures the current clipboard image and encodes it to PNG bytes into [out].
  // Returns an empty string on success; otherwise a short error code (currently
  // always "PASTE_IMAGE_ERROR") when no image could be produced. Shared by the
  // synchronous paste path and the background-thread save path — it touches no
  // instance state, so it is safe to call from a worker thread.
  std::string CaptureClipboardPng(std::vector<uint8_t>& out) {
    out.clear();

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

    // If we still don't have a bitmap, no image was available.
    if (!pBitmap) {
      GdiplusShutdown(gdiplusToken);
      return "PASTE_IMAGE_ERROR";
    }

    // Convert bitmap to PNG bytes.
    IStream* pStream = nullptr;
    if (CreateStreamOnHGlobal(nullptr, TRUE, &pStream) != S_OK) {
      delete pBitmap;
      GdiplusShutdown(gdiplusToken);
      return "PASTE_IMAGE_ERROR";
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
            // Return the PNG as typed data (-> Dart Uint8List). Previously every
            // byte was boxed into its own EncodableValue(int32); for a large
            // image that blocked the platform thread — and therefore the
            // low-level mouse hook that lives on it — long enough to freeze
            // system input. A byte vector serializes as a single buffer.
            if (bytesRead < pngBytes.size()) pngBytes.resize(bytesRead);
            out = std::move(pngBytes);
          }
        }
      }
    }

    pStream->Release();
    delete pBitmap;
    GdiplusShutdown(gdiplusToken);

    return out.empty() ? "PASTE_IMAGE_ERROR" : "";
  }

  void HandlePasteImage(std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
    std::vector<uint8_t> pngBytes;
    const std::string error = CaptureClipboardPng(pngBytes);
    if (!error.empty()) {
      result->Error(error, "No image found in clipboard. Copy an image (not a file) or try pasting after copying image data from a browser/app.");
      return;
    }
    EncodableMap result_map;
    result_map[EncodableValue("imageBytes")] = EncodableValue(std::move(pngBytes));
    result->Success(EncodableValue(result_map));
  }

  // Capture + encode + write the current clipboard image to disk, then return
  // only lightweight metadata (path, byte length, MD5 hash) to Dart. All heavy
  // work runs on a detached background thread, so the platform thread — which
  // owns the global WH_MOUSE_LL mouse hook — is never blocked; that is what
  // keeps copying an image from freezing system input. The reply is delivered
  // from the worker thread through a shared MethodResult, the same pattern the
  // media-session handler in tabamewin32_plugin.cpp uses.
  void HandleSaveImage(const EncodableMap* arguments,
                       std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
    if (!arguments) {
      result->Error("INVALID_ARGUMENT", "Arguments are required");
      return;
    }
    auto path_it = arguments->find(EncodableValue("path"));
    const std::string* path_ptr = (path_it != arguments->end())
                                      ? std::get_if<std::string>(&path_it->second)
                                      : nullptr;
    if (!path_ptr || path_ptr->empty()) {
      result->Error("INVALID_ARGUMENT", "A non-empty 'path' is required");
      return;
    }
    const std::string utf8Path = *path_ptr;

    std::shared_ptr<flutter::MethodResult<EncodableValue>> shared_result(
        std::move(result));

    std::thread([this, shared_result, utf8Path]() {
      // Browser OLE clipboard reads and GDI+ PNG encoding both need COM on this
      // thread; without it, capture/encode fails and no image is produced.
      const ScopedOleApartment ole;

      std::vector<uint8_t> pngBytes;
      const std::string error = CaptureClipboardPng(pngBytes);
      if (!error.empty()) {
        shared_result->Error(error, "No image found in clipboard.");
        return;
      }
      if (!WriteBytesToFileW(Utf8ToWideLocal(utf8Path), pngBytes)) {
        shared_result->Error("SAVE_IMAGE_ERROR", "Failed to write image file");
        return;
      }
      EncodableMap out;
      out[EncodableValue("saved")] = EncodableValue(true);
      out[EncodableValue("path")] = EncodableValue(utf8Path);
      out[EncodableValue("byteLength")] =
          EncodableValue(static_cast<int32_t>(pngBytes.size()));
      out[EncodableValue("hash")] = EncodableValue(Md5Hex(pngBytes));
      shared_result->Success(EncodableValue(out));
    }).detach();
  }

  // Reads the current text formats once on a worker, writes raw UTF-8 payload
  // files, and returns only metadata. In particular, no large string is ever
  // put into an EncodableValue.
  void HandleCaptureTextToFiles(
      const EncodableMap* arguments,
      std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
    if (!arguments) {
      result->Error("INVALID_ARGUMENT", "Arguments are required");
      return;
    }

    auto readStringArgument = [arguments](const char* key) -> std::string {
      const auto it = arguments->find(EncodableValue(key));
      if (it == arguments->end()) return std::string();
      const auto* value = std::get_if<std::string>(&it->second);
      return value == nullptr ? std::string() : *value;
    };

    const std::string textPath = readStringArgument("textPath");
    const std::string htmlPath = readStringArgument("htmlPath");
    if (textPath.empty() || htmlPath.empty()) {
      result->Error("INVALID_ARGUMENT", "Text and HTML payload paths are required");
      return;
    }

    int previewLimit = 5000;
    const auto previewIt = arguments->find(EncodableValue("previewLimit"));
    if (previewIt != arguments->end()) {
      if (const auto* value = std::get_if<int32_t>(&previewIt->second)) {
        previewLimit = *value;
      } else if (const auto* valuex = std::get_if<int64_t>(&previewIt->second)) {
        previewLimit = static_cast<int>(*valuex);
      }
    }
    previewLimit = std::max(1, std::min(previewLimit, 5000));

    std::shared_ptr<flutter::MethodResult<EncodableValue>> sharedResult(
        std::move(result));
    std::thread([sharedResult, textPath, htmlPath, previewLimit]() {
      const ScopedOleApartment ole;
      std::wstring textWide;
      std::string htmlRaw;

      if (!OpenClipboard(nullptr)) {
        sharedResult->Error("CAPTURE_CLIPBOARD_ERROR", "Failed to open clipboard");
        return;
      }

      if (IsClipboardFormatAvailable(CF_UNICODETEXT)) {
        HGLOBAL memory = GetClipboardData(CF_UNICODETEXT);
        if (memory != nullptr) {
          const SIZE_T bytes = GlobalSize(memory);
          const wchar_t* source = static_cast<const wchar_t*>(GlobalLock(memory));
          if (source != nullptr) {
            const size_t maxCharacters = bytes / sizeof(wchar_t);
            size_t length = 0;
            while (length < maxCharacters && source[length] != static_cast<wchar_t>(0)) ++length;
            textWide.assign(source, length);
            GlobalUnlock(memory);
          }
        }
      }

      const UINT cfHtml = RegisterClipboardFormatA("HTML Format");
      if (cfHtml != 0 && IsClipboardFormatAvailable(cfHtml)) {
        HGLOBAL memory = GetClipboardData(cfHtml);
        if (memory != nullptr) {
          const SIZE_T bytes = GlobalSize(memory);
          const char* source = static_cast<const char*>(GlobalLock(memory));
          if (source != nullptr) {
            const size_t maxBytes = static_cast<size_t>(bytes);
            size_t length = 0;
            while (length < maxBytes && source[length] != static_cast<char>(0)) ++length;
            htmlRaw.assign(source, length);
            GlobalUnlock(memory);
          }
        }
      }
      CloseClipboard();

      const std::string text = WideToUtf8Local(textWide);
      const std::string html = ExtractHtmlFragmentLocal(htmlRaw);
      if (text.empty() && html.empty()) {
        EncodableMap out;
        out[EncodableValue("captured")] = EncodableValue(false);
        sharedResult->Success(EncodableValue(out));
        return;
      }

      const std::wstring textFilePath = Utf8ToWideLocal(textPath);
      const std::wstring htmlFilePath = Utf8ToWideLocal(htmlPath);
      if (!text.empty() && !WriteStringToFileAtomicW(textFilePath, text)) {
        sharedResult->Error("CAPTURE_WRITE_ERROR", "Failed to write text payload");
        return;
      }
      if (!html.empty() && !WriteStringToFileAtomicW(htmlFilePath, html)) {
        DeleteFileW(textFilePath.c_str());
        sharedResult->Error("CAPTURE_WRITE_ERROR", "Failed to write HTML payload");
        return;
      }

      EncodableMap out;
      out[EncodableValue("captured")] = EncodableValue(true);
      out[EncodableValue("textPreview")] = EncodableValue(
          WidePrefixToUtf8(textWide, static_cast<size_t>(previewLimit)));
      out[EncodableValue("htmlPreview")] = EncodableValue(
          Utf8PreviewLocal(html, static_cast<size_t>(previewLimit)));
      out[EncodableValue("textLength")] =
          EncodableValue(static_cast<int64_t>(textWide.size()));
      const std::wstring htmlWide = Utf8ToWideLocal(html);
      out[EncodableValue("htmlLength")] = EncodableValue(static_cast<int64_t>(
          htmlWide.empty() && !html.empty() ? html.size() : htmlWide.size()));
      out[EncodableValue("byteLength")] = EncodableValue(static_cast<int64_t>(
          text.size() + html.size()));
      out[EncodableValue("contentHash")] = EncodableValue(Md5HexTextHtml(text, html));
      sharedResult->Success(EncodableValue(out));
    }).detach();
  }

  // Restores clipboard contents from sidecar files. The files are read and the
  // clipboard allocation is performed on a worker so a large paste does not
  // block Flutter's platform thread or the global input hook.
  void HandleCopyContentFromFiles(
      const EncodableMap* arguments,
      std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
    if (!arguments) {
      result->Error("INVALID_ARGUMENT", "Arguments are required");
      return;
    }

    auto readStringArgument = [arguments](const char* key) -> std::string {
      const auto it = arguments->find(EncodableValue(key));
      if (it == arguments->end()) return std::string();
      const auto* value = std::get_if<std::string>(&it->second);
      return value == nullptr ? std::string() : *value;
    };

    const std::string textPath = readStringArgument("textPath");
    const std::string htmlPath = readStringArgument("htmlPath");
    const std::string imagePath = readStringArgument("imagePath");
    if (textPath.empty() && htmlPath.empty() && imagePath.empty()) {
      result->Error("INVALID_ARGUMENT", "A payload path is required");
      return;
    }

    std::shared_ptr<flutter::MethodResult<EncodableValue>> sharedResult(
        std::move(result));
    std::thread([sharedResult, textPath, htmlPath, imagePath]() {
      const ScopedOleApartment ole;
      if (!imagePath.empty()) {
        GdiplusStartupInput gdiplusStartupInput;
        ULONG_PTR gdiplusToken = 0;
        const bool gdiStarted =
            GdiplusStartup(&gdiplusToken, &gdiplusStartupInput, nullptr) == Ok;
        const std::wstring path = Utf8ToWideLocal(imagePath);
        const bool copied = gdiStarted && CopyImageToClipboard(path.c_str());
        if (gdiStarted) GdiplusShutdown(gdiplusToken);
        if (copied) {
          sharedResult->Success(EncodableValue(true));
        } else {
          sharedResult->Error("COPY_FILE_ERROR", "Failed to copy image payload");
        }
        return;
      }

      std::string text;
      std::string html;
      if (!textPath.empty() &&
          !ReadStringFromFileW(Utf8ToWideLocal(textPath), text)) {
        sharedResult->Error("COPY_FILE_ERROR", "Failed to read text payload");
        return;
      }
      if (!htmlPath.empty() &&
          !ReadStringFromFileW(Utf8ToWideLocal(htmlPath), html)) {
        sharedResult->Error("COPY_FILE_ERROR", "Failed to read HTML payload");
        return;
      }
      if (!WriteRichTextToClipboard(text, html)) {
        sharedResult->Error("COPY_FILE_ERROR", "Failed to write clipboard payload");
        return;
      }
      sharedResult->Success(EncodableValue(true));
    }).detach();
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
