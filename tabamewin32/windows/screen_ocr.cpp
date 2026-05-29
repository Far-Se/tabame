#include <windows.h>

#include <algorithm>
#include <mutex>
#include <roapi.h>
#include <stdint.h>
#include <string>
#include <vector>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Graphics.Imaging.h>
#include <winrt/Windows.Media.Ocr.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/base.h>

struct OcrResult {
  bool success = false;
  std::string text;
  std::string errorCode;
  std::string errorMessage;
};

enum class OcrCaptureType {
  BitBlt = 0,
  DirectX = 1,
};

namespace {
using winrt::Windows::Graphics::Imaging::BitmapAlphaMode;
using winrt::Windows::Graphics::Imaging::BitmapPixelFormat;
using winrt::Windows::Graphics::Imaging::SoftwareBitmap;
using winrt::Windows::Media::Ocr::OcrEngine;
using winrt::Windows::Storage::Streams::DataWriter;

bool EnsureOcrWinRtInitialized() {
  static std::once_flag initOnce;
  static HRESULT initResult = E_FAIL;

  std::call_once(initOnce, []() {
    initResult = RoInitialize(RO_INIT_MULTITHREADED);
    if (initResult == RPC_E_CHANGED_MODE)
      initResult = S_OK;
  });

  return SUCCEEDED(initResult);
}

std::string HStringToUtf8(const winrt::hstring &value) {
  return Encoding::WideToUtf8(std::wstring(value.c_str(), value.size()));
}

bool CaptureRectWithBitBlt(int x, int y, int width, int height,
                           std::vector<uint8_t> &pixels) {
  HDC screenDc = GetDC(nullptr);
  if (screenDc == nullptr)
    return false;

  HDC memDc = CreateCompatibleDC(screenDc);
  HBITMAP bitmap = CreateCompatibleBitmap(screenDc, width, height);
  if (memDc == nullptr || bitmap == nullptr) {
    if (bitmap != nullptr)
      DeleteObject(bitmap);
    if (memDc != nullptr)
      DeleteDC(memDc);
    ReleaseDC(nullptr, screenDc);
    return false;
  }

  HGDIOBJ oldObject = SelectObject(memDc, bitmap);
  const BOOL copied =
      BitBlt(memDc, 0, 0, width, height, screenDc, x, y, SRCCOPY | CAPTUREBLT);
  SelectObject(memDc, oldObject);

  if (!copied) {
    DeleteObject(bitmap);
    DeleteDC(memDc);
    ReleaseDC(nullptr, screenDc);
    return false;
  }

  BITMAPINFO bmi = {};
  bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bmi.bmiHeader.biWidth = width;
  bmi.bmiHeader.biHeight = -height;
  bmi.bmiHeader.biPlanes = 1;
  bmi.bmiHeader.biBitCount = 32;
  bmi.bmiHeader.biCompression = BI_RGB;

  pixels.assign(static_cast<size_t>(width) * height * 4, 0);
  const int lines =
      GetDIBits(memDc, bitmap, 0, height, pixels.data(), &bmi, DIB_RGB_COLORS);

  DeleteObject(bitmap);
  DeleteDC(memDc);
  ReleaseDC(nullptr, screenDc);
  return lines != 0;
}

bool CropMonitorCaptureToRect(const MonitorCaptureResult &capture,
                              const RECT &monitorRect, int x, int y, int width,
                              int height, std::vector<uint8_t> &pixels) {
  if (capture.pixels.empty() || capture.width <= 0 || capture.height <= 0)
    return false;

  pixels.assign(static_cast<size_t>(width) * height * 4, 255);
  for (int row = 0; row < height; ++row) {
    const int screenY = y + row;
    const int sourceY = screenY - monitorRect.top;
    if (sourceY < 0 || sourceY >= capture.height)
      continue;

    for (int col = 0; col < width; ++col) {
      const int screenX = x + col;
      const int sourceX = screenX - monitorRect.left;
      if (sourceX < 0 || sourceX >= capture.width)
        continue;

      const size_t sourceIndex =
          (static_cast<size_t>(sourceY) * capture.width + sourceX) * 4;
      const size_t destIndex =
          (static_cast<size_t>(row) * width + col) * 4;
      pixels[destIndex] = capture.pixels[sourceIndex];
      pixels[destIndex + 1] = capture.pixels[sourceIndex + 1];
      pixels[destIndex + 2] = capture.pixels[sourceIndex + 2];
      pixels[destIndex + 3] = 255;
    }
  }
  return true;
}

bool CaptureRectWithDirectX(int x, int y, int width, int height,
                            std::vector<uint8_t> &pixels) {
  RECT requested = {x, y, x + width, y + height};
  HMONITOR monitor = MonitorFromRect(&requested, MONITOR_DEFAULTTONEAREST);
  if (monitor == nullptr)
    return false;

  MONITORINFO info = {};
  info.cbSize = sizeof(MONITORINFO);
  if (!GetMonitorInfo(monitor, &info))
    return false;

  MonitorCaptureResult capture;
  if (!CaptureMonitorBitmapAlternative(
          static_cast<int64_t>(reinterpret_cast<LONG_PTR>(monitor)), capture))
    return false;

  return CropMonitorCaptureToRect(capture, info.rcMonitor, x, y, width, height,
                                  pixels);
}

OcrResult RecognizeBgraPixels(const std::vector<uint8_t> &pixels, int width,
                              int height) {
  OcrResult out;
  if (pixels.empty() || width <= 0 || height <= 0) {
    out.errorCode = "OCR_EMPTY_IMAGE";
    out.errorMessage = "No pixels were captured for OCR.";
    return out;
  }

  try {
    if (!EnsureOcrWinRtInitialized()) {
      out.errorCode = "OCR_WINRT_INIT_FAILED";
      out.errorMessage = "Unable to initialize WinRT for OCR.";
      return out;
    }

    OcrEngine engine = OcrEngine::TryCreateFromUserProfileLanguages();
    if (!engine) {
      out.errorCode = "OCR_ENGINE_UNAVAILABLE";
      out.errorMessage = "Windows OCR is not available for the current user.";
      return out;
    }

    const uint32_t maxDimension = OcrEngine::MaxImageDimension();
    if (static_cast<uint32_t>(width) > maxDimension ||
        static_cast<uint32_t>(height) > maxDimension) {
      out.errorCode = "OCR_IMAGE_TOO_LARGE";
      out.errorMessage =
          "The selected region is larger than Windows OCR allows.";
      return out;
    }

    SoftwareBitmap bitmap(BitmapPixelFormat::Bgra8, width, height,
                          BitmapAlphaMode::Premultiplied);
    DataWriter writer;
    writer.WriteBytes(winrt::array_view<const uint8_t>(pixels));
    bitmap.CopyFromBuffer(writer.DetachBuffer());

    const auto result = engine.RecognizeAsync(bitmap).get();
    out.text = HStringToUtf8(result.Text());
    out.success = true;
    return out;
  } catch (const winrt::hresult_error &e) {
    out.errorCode = "OCR_FAILED";
    out.errorMessage = HStringToUtf8(e.message());
    return out;
  } catch (const std::exception &e) {
    out.errorCode = "OCR_FAILED";
    out.errorMessage = e.what();
    return out;
  } catch (...) {
    out.errorCode = "OCR_FAILED";
    out.errorMessage = "Windows OCR failed.";
    return out;
  }
}
} // namespace

OcrResult GetTextOCR(int x, int y, int width, int height, int type) {
  OcrResult result;
  width = std::clamp(width, 1, 1000000);
  height = std::clamp(height, 1, 1000000);

  std::vector<uint8_t> pixels;
  const OcrCaptureType captureType =
      type == static_cast<int>(OcrCaptureType::DirectX) ? OcrCaptureType::DirectX
                                                       : OcrCaptureType::BitBlt;
  const bool captured =
      captureType == OcrCaptureType::DirectX
          ? CaptureRectWithDirectX(x, y, width, height, pixels)
          : CaptureRectWithBitBlt(x, y, width, height, pixels);

  if (!captured) {
    result.errorCode = "OCR_CAPTURE_FAILED";
    result.errorMessage = "Unable to capture the requested screen region.";
    return result;
  }

  return RecognizeBgraPixels(pixels, width, height);
}
