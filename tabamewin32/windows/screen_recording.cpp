#ifndef TABAMEWIN32_SCREEN_RECORDING
#define TABAMEWIN32_SCREEN_RECORDING

#include <windows.h>

#include <Audioclient.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mmdeviceapi.h>
#include <roapi.h>
#include <windows.graphics.capture.interop.h>
#include <windows.graphics.directx.direct3d11.interop.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <deque>
#include <filesystem>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>
#include <winrt/Windows.Graphics.DirectX.h>
#include <winrt/base.h>

#include "include/encoding.h"

#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "dxgi.lib")
#pragma comment(lib, "windowsapp.lib")
#pragma comment(lib, "mf.lib")
#pragma comment(lib, "mfplat.lib")
#pragma comment(lib, "mfreadwrite.lib")
#pragma comment(lib, "mfuuid.lib")

struct ScreenRecordingStatus {
  bool isRecording = false;
  std::string outputPath;
  std::string audioMode = "none";
  int64_t elapsedMs = 0;
  int frameCount = 0;
  int droppedFrames = 0;
  int width = 0;
  int height = 0;
};

struct ScreenRecordingStopResult {
  bool success = false;
  std::string filePath;
  int64_t durationMs = 0;
  int frameCount = 0;
};

namespace screen_recording {
using winrt::Windows::Graphics::Capture::Direct3D11CaptureFrame;
using winrt::Windows::Graphics::Capture::Direct3D11CaptureFramePool;
using winrt::Windows::Graphics::Capture::GraphicsCaptureItem;
using winrt::Windows::Graphics::Capture::GraphicsCaptureSession;
using winrt::Windows::Graphics::DirectX::DirectXPixelFormat;
using winrt::Windows::Graphics::DirectX::Direct3D11::IDirect3DDevice;
using winrt::Windows::Graphics::DirectX::Direct3D11::IDirect3DSurface;

constexpr int kAudioSampleRate = 48000;
constexpr int kAudioChannels = 2;
constexpr int kAudioBitsPerSample = 16;
constexpr int kAudioChunkFrames = 480;

enum class TargetType { Region, Monitor, Window };

struct Config {
  TargetType targetType = TargetType::Region;
  RECT region = {0, 0, 0, 0};
  int64_t monitorHandle = 0;
  int64_t hWnd = 0;
  std::wstring outputPath;
  int frameRate = 30;
  int videoBitrateMbps = 12;
  bool captureCursor = true;
  bool captureBorder = false;
  bool useHardwareEncoder = true;
  std::string audioMode = "none";
  std::wstring micDeviceId;
  std::wstring systemAudioDeviceId;
};

struct CoTaskMemFreeDeleter {
  void operator()(WAVEFORMATEX *format) const {
    if (format != nullptr) {
      CoTaskMemFree(format);
    }
  }
};

struct AudioSource {
  std::wstring label;
  std::wstring deviceId;
  EDataFlow flow = eCapture;
  bool loopback = false;
  winrt::com_ptr<IMMDevice> device;
  winrt::com_ptr<IAudioClient> client;
  winrt::com_ptr<IAudioCaptureClient> capture;
  std::unique_ptr<WAVEFORMATEX, CoTaskMemFreeDeleter> format;
  std::deque<float> pendingStereo;
  std::vector<float> resampleCarry;
  double resamplePos = 0.0;
  UINT32 bufferFrameCount = 0;
  int sampleRate = kAudioSampleRate;
  int channelCount = kAudioChannels;
};

static bool EnsureWinRtInitialized() {
  static std::once_flag initOnce;
  static HRESULT initResult = E_FAIL;
  std::call_once(initOnce, []() {
    initResult = RoInitialize(RO_INIT_MULTITHREADED);
    if (initResult == RPC_E_CHANGED_MODE)
      initResult = S_OK;
  });
  return SUCCEEDED(initResult);
}

static bool EnsureMediaFoundationStarted() {
  static std::once_flag mfOnce;
  static HRESULT mfResult = E_FAIL;
  std::call_once(mfOnce, []() { mfResult = MFStartup(MF_VERSION); });
  return SUCCEEDED(mfResult);
}

static bool CreateD3D11Device(winrt::com_ptr<ID3D11Device> &device,
                              winrt::com_ptr<ID3D11DeviceContext> &context) {
  static const D3D_FEATURE_LEVEL kFeatureLevels[] = {
      D3D_FEATURE_LEVEL_11_1,
      D3D_FEATURE_LEVEL_11_0,
      D3D_FEATURE_LEVEL_10_1,
      D3D_FEATURE_LEVEL_10_0,
  };

  D3D_FEATURE_LEVEL featureLevel = D3D_FEATURE_LEVEL_11_0;
  const UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;
  HRESULT hr = D3D11CreateDevice(
      nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, flags, kFeatureLevels,
      static_cast<UINT>(std::size(kFeatureLevels)), D3D11_SDK_VERSION,
      device.put(), &featureLevel, context.put());
  if (SUCCEEDED(hr))
    return true;

  hr = D3D11CreateDevice(
      nullptr, D3D_DRIVER_TYPE_WARP, nullptr, flags, kFeatureLevels,
      static_cast<UINT>(std::size(kFeatureLevels)), D3D11_SDK_VERSION,
      device.put(), &featureLevel, context.put());
  return SUCCEEDED(hr);
}

static winrt::com_ptr<ID3D11Texture2D>
GetTextureFromFrame(const Direct3D11CaptureFrame &frame) {
  if (!frame)
    return nullptr;
  IDirect3DSurface surface = frame.Surface();
  if (!surface)
    return nullptr;

  winrt::com_ptr<
      ::Windows::Graphics::DirectX::Direct3D11::IDirect3DDxgiInterfaceAccess>
      access = surface.as<::Windows::Graphics::DirectX::Direct3D11::
                              IDirect3DDxgiInterfaceAccess>();
  winrt::com_ptr<ID3D11Texture2D> sourceTexture;
  if (FAILED(access->GetInterface(__uuidof(ID3D11Texture2D),
                                  sourceTexture.put_void()))) {
    return nullptr;
  }
  return sourceTexture;
}

static GraphicsCaptureItem CreateItemForMonitor(HMONITOR monitor) {
  auto interop = winrt::get_activation_factory<GraphicsCaptureItem,
                                               IGraphicsCaptureItemInterop>();
  GraphicsCaptureItem item{nullptr};
  const HRESULT hr = interop->CreateForMonitor(
      monitor,
      winrt::guid_of<winrt::Windows::Graphics::Capture::IGraphicsCaptureItem>(),
      winrt::put_abi(item));
  if (FAILED(hr))
    return nullptr;
  return item;
}

static GraphicsCaptureItem CreateItemForWindow(HWND hwnd) {
  auto interop = winrt::get_activation_factory<GraphicsCaptureItem,
                                               IGraphicsCaptureItemInterop>();
  GraphicsCaptureItem item{nullptr};
  const HRESULT hr = interop->CreateForWindow(
      hwnd,
      winrt::guid_of<winrt::Windows::Graphics::Capture::IGraphicsCaptureItem>(),
      winrt::put_abi(item));
  if (FAILED(hr))
    return nullptr;
  return item;
}

static RECT ClampRectToSize(const RECT &rect, int width, int height) {
  RECT out = rect;
  out.left = std::clamp(out.left, 0L, static_cast<LONG>(width));
  out.top = std::clamp(out.top, 0L, static_cast<LONG>(height));
  out.right = std::clamp(out.right, out.left, static_cast<LONG>(width));
  out.bottom = std::clamp(out.bottom, out.top, static_cast<LONG>(height));
  return out;
}

static bool DeviceExists(EDataFlow flow, const std::wstring &requestedId) {
  if (requestedId.empty())
    return true;
  const auto devices = EnumAudioDevices(flow);
  for (const auto &device : devices) {
    if (device.id == requestedId)
      return true;
  }
  return false;
}

static float ReadPcmSample(const BYTE *sampleBytes, int bitsPerSample) {
  switch (bitsPerSample) {
  case 8:
    return (static_cast<int>(*sampleBytes) - 128) / 128.0f;
  case 16: {
    const int16_t value = *reinterpret_cast<const int16_t *>(sampleBytes);
    return value / 32768.0f;
  }
  case 24: {
    int32_t value = (static_cast<int32_t>(sampleBytes[0])) |
                    (static_cast<int32_t>(sampleBytes[1]) << 8) |
                    (static_cast<int32_t>(sampleBytes[2]) << 16);
    if ((value & 0x800000) != 0)
      value |= ~0xFFFFFF;
    return value / 8388608.0f;
  }
  case 32: {
    const int32_t value = *reinterpret_cast<const int32_t *>(sampleBytes);
    return value / 2147483648.0f;
  }
  default:
    return 0.0f;
  }
}

static std::vector<float>
ConvertCapturedFramesToStereoFloat(const BYTE *data, UINT32 frames,
                                   const WAVEFORMATEX *format, DWORD flags) {
  std::vector<float> output;
  output.resize(static_cast<size_t>(frames) * 2, 0.0f);
  if ((flags & AUDCLNT_BUFFERFLAGS_SILENT) != 0 || data == nullptr ||
      format == nullptr) {
    return output;
  }

  GUID subtype = KSDATAFORMAT_SUBTYPE_PCM;
  int validBitsPerSample = format->wBitsPerSample;
  if (format->wFormatTag == WAVE_FORMAT_EXTENSIBLE &&
      format->cbSize >= sizeof(WAVEFORMATEXTENSIBLE) - sizeof(WAVEFORMATEX)) {
    const auto *extensible =
        reinterpret_cast<const WAVEFORMATEXTENSIBLE *>(format);
    subtype = extensible->SubFormat;
    validBitsPerSample = extensible->Samples.wValidBitsPerSample > 0
                             ? extensible->Samples.wValidBitsPerSample
                             : format->wBitsPerSample;
  }

  const bool isFloat = subtype == KSDATAFORMAT_SUBTYPE_IEEE_FLOAT ||
                       format->wFormatTag == WAVE_FORMAT_IEEE_FLOAT;
  const int channels = (std::max)(1, static_cast<int>(format->nChannels));
  const int bytesPerFrame = (std::max)(channels * format->wBitsPerSample / 8,
                                       static_cast<int>(format->nBlockAlign));

  for (UINT32 frame = 0; frame < frames; ++frame) {
    const BYTE *frameData = data + static_cast<size_t>(frame) * bytesPerFrame;
    float left = 0.0f;
    float right = 0.0f;

    for (int channel = 0; channel < channels; ++channel) {
      const BYTE *sampleBytes =
          frameData + channel * (format->wBitsPerSample / 8);
      float sample = 0.0f;
      if (isFloat && format->wBitsPerSample == 32) {
        sample = *reinterpret_cast<const float *>(sampleBytes);
      } else {
        sample = ReadPcmSample(sampleBytes, validBitsPerSample);
      }

      if (channel == 0) {
        left = sample;
        if (channels == 1)
          right = sample;
      } else if (channel == 1) {
        right = sample;
      }
    }

    output[static_cast<size_t>(frame) * 2] = left;
    output[static_cast<size_t>(frame) * 2 + 1] = right;
  }

  return output;
}

static std::vector<float>
ResampleStereoToTargetRate(AudioSource &source,
                           const std::vector<float> &stereoFrames) {
  if (stereoFrames.empty())
    return {};

  if (source.sampleRate == kAudioSampleRate) {
    return stereoFrames;
  }

  std::vector<float> combined = source.resampleCarry;
  combined.insert(combined.end(), stereoFrames.begin(), stereoFrames.end());
  const int totalFrames = static_cast<int>(combined.size() / 2);
  if (totalFrames < 2) {
    source.resampleCarry = std::move(combined);
    return {};
  }

  std::vector<float> output;
  const double step = static_cast<double>(source.sampleRate) /
                      static_cast<double>(kAudioSampleRate);

  while (source.resamplePos + 1.0 < totalFrames) {
    const int index = static_cast<int>(source.resamplePos);
    const double frac = source.resamplePos - static_cast<double>(index);
    const size_t base = static_cast<size_t>(index) * 2;
    const size_t next = static_cast<size_t>(index + 1) * 2;
    for (int channel = 0; channel < 2; ++channel) {
      const float a = combined[base + channel];
      const float b = combined[next + channel];
      output.push_back(a + static_cast<float>((b - a) * frac));
    }
    source.resamplePos += step;
  }

  const int consumedFrames = static_cast<int>(source.resamplePos);
  if (consumedFrames > 0) {
    const size_t consumedSamples = static_cast<size_t>(consumedFrames) * 2;
    source.resampleCarry.assign(combined.begin() + consumedSamples,
                                combined.end());
    source.resamplePos -= consumedFrames;
  } else {
    source.resampleCarry = std::move(combined);
  }

  return output;
}

// IsBorderRequired lives on IGraphicsCaptureSession3, which is absent from
// Windows SDK headers older than 10.0.19041. Declare its ABI interface directly
// so this compiles regardless of the installed SDK; try_as() returns null (and
// we simply skip it) when the running OS predates the API.
struct __declspec(uuid("f2cdd966-22ae-5ea1-9596-3a289344c3be"))
    IGraphicsCaptureSession3Abi : ::IInspectable {
  virtual HRESULT __stdcall get_IsBorderRequired(boolean *value) = 0;
  virtual HRESULT __stdcall put_IsBorderRequired(boolean value) = 0;
};

class ScreenRecordingSession {
public:
  bool Start(const Config &config, std::string &errorCode,
             std::string &errorMessage) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (isRecording_) {
      errorCode = "ALREADY_RECORDING";
      errorMessage = "A screen recording is already active.";
      return false;
    }

    if (!EnsureWinRtInitialized()) {
      errorCode = "WINRT_INIT_FAILED";
      errorMessage = "Unable to initialize WinRT for screen recording.";
      return false;
    }
    if (!EnsureMediaFoundationStarted()) {
      errorCode = "MEDIA_FOUNDATION_INIT_FAILED";
      errorMessage = "Unable to initialize Media Foundation.";
      return false;
    }
    if (config.outputPath.empty()) {
      errorCode = "INVALID_OUTPUT";
      errorMessage = "An output file path is required.";
      return false;
    }

    if ((config.audioMode == "mic" || config.audioMode == "systemAndMic") &&
        !DeviceExists(eCapture, config.micDeviceId)) {
      errorCode = "AUDIO_DEVICE_UNAVAILABLE";
      errorMessage = "The selected microphone device is unavailable.";
      return false;
    }
    if ((config.audioMode == "system" || config.audioMode == "systemAndMic") &&
        !DeviceExists(eRender, config.systemAudioDeviceId)) {
      errorCode = "AUDIO_DEVICE_UNAVAILABLE";
      errorMessage = "The selected system audio device is unavailable.";
      return false;
    }

    Config normalized = config;
    normalized.frameRate =
        normalized.frameRate == 24 || normalized.frameRate == 60
            ? normalized.frameRate
            : 30;
    normalized.videoBitrateMbps =
        normalized.videoBitrateMbps == 6 || normalized.videoBitrateMbps == 20
            ? normalized.videoBitrateMbps
            : 12;

    std::error_code fsError;
    std::filesystem::path outPath(normalized.outputPath);
    if (!outPath.parent_path().empty()) {
      std::filesystem::create_directories(outPath.parent_path(), fsError);
    }

    if (!CreateD3D11Device(d3dDevice_, d3dContext_)) {
      errorCode = "D3D_INIT_FAILED";
      errorMessage = "Unable to initialize the D3D11 device for recording.";
      CleanupResourcesLocked();
      return false;
    }

    winrt::com_ptr<IDXGIDevice> dxgiDevice;
    if (FAILED(d3dDevice_->QueryInterface(__uuidof(IDXGIDevice),
                                          dxgiDevice.put_void()))) {
      errorCode = "DXGI_DEVICE_FAILED";
      errorMessage = "Unable to access the DXGI device for recording.";
      CleanupResourcesLocked();
      return false;
    }

    winrt::com_ptr<::IInspectable> inspectableDevice;
    if (FAILED(CreateDirect3D11DeviceFromDXGIDevice(dxgiDevice.get(),
                                                    inspectableDevice.put()))) {
      errorCode = "WINRT_DEVICE_FAILED";
      errorMessage = "Unable to wrap the D3D device for Windows capture.";
      CleanupResourcesLocked();
      return false;
    }
    winrtDevice_ = inspectableDevice.as<IDirect3DDevice>();

    if (!ResolveCaptureItemLocked(normalized, errorCode, errorMessage)) {
      CleanupResourcesLocked();
      return false;
    }

    captureConfig_ = normalized;
    audioEnabled_ = normalized.audioMode != "none";

    if (!InitializeSinkWriterLocked(normalized, errorCode, errorMessage)) {
      CleanupResourcesLocked();
      return false;
    }

    stopRequested_ = false;
    cancelRequested_ = false;
    paused_ = false;
    pausedDurationUs_ = 0;
    frameCount_ = 0;
    droppedFrames_ = 0;
    audioFramesWritten_ = 0;
    audioStartTime_ = {};
    audioInitDone_ = false;
    audioInitSucceeded_ = false;
    audioSources_.clear();
    audioErrorCode_.clear();
    audioErrorMessage_.clear();

    frameEvent_.reset(CreateEvent(nullptr, FALSE, FALSE, nullptr));
    if (!frameEvent_) {
      errorCode = "EVENT_CREATE_FAILED";
      errorMessage = "Unable to create the frame event for recording.";
      CleanupResourcesLocked();
      return false;
    }

    audioInitEvent_.reset(CreateEvent(nullptr, TRUE, FALSE, nullptr));
    if (!audioInitEvent_) {
      errorCode = "EVENT_CREATE_FAILED";
      errorMessage = "Unable to create the audio initialization event.";
      CleanupResourcesLocked();
      return false;
    }

    try {
      startTime_ = std::chrono::steady_clock::now();
      isRecording_ = true;

      if (audioEnabled_) {
        audioThread_ = std::thread([this]() { AudioLoop(); });
        const DWORD wait = WaitForSingleObject(audioInitEvent_.get(), 15000);
        if (wait != WAIT_OBJECT_0 || !audioInitSucceeded_) {
          errorCode =
              audioErrorCode_.empty() ? "AUDIO_INIT_FAILED" : audioErrorCode_;
          errorMessage =
              audioErrorMessage_.empty()
                  ? "Unable to initialize the audio capture pipeline."
                  : audioErrorMessage_;
          stopRequested_ = true;
          if (audioThread_.joinable())
            audioThread_.join();
          CleanupResourcesLocked();
          return false;
        }
      }

      framePool_ = Direct3D11CaptureFramePool::CreateFreeThreaded(
          winrtDevice_, DirectXPixelFormat::B8G8R8A8UIntNormalized, 2,
          item_.Size());
      session_ = framePool_.CreateCaptureSession(item_);
      session_.IsCursorCaptureEnabled(normalized.captureCursor);
      // IsBorderRequired controls the yellow capture border Windows draws around
      // the captured surface. Reached via its ABI interface so it works on SDKs
      // that don't project it; null when the OS is too old (Win10 pre-2004).
      try {
        if (auto borderApi = session_.try_as<IGraphicsCaptureSession3Abi>()) {
          borderApi->put_IsBorderRequired(normalized.captureBorder ? TRUE
                                                                   : FALSE);
        }
      } catch (...) {
      }
      frameArrivedToken_ = framePool_.FrameArrived([this](auto &&, auto &&) {
        if (frameEvent_)
          SetEvent(frameEvent_.get());
      });
      session_.StartCapture();
      frameThread_ = std::thread([this]() { FrameLoop(); });
    } catch (...) {
      errorCode = "CAPTURE_START_FAILED";
      errorMessage = "Unable to start the Windows Graphics Capture session.";
      stopRequested_ = true;
      if (audioThread_.joinable())
        audioThread_.join();
      CleanupResourcesLocked();
      return false;
    }

    return true;
  }

  bool Stop(ScreenRecordingStopResult &result, std::string &errorCode,
            std::string &errorMessage) {
    return Finish(false, result, errorCode, errorMessage);
  }

  bool Cancel(std::string &errorCode, std::string &errorMessage) {
    ScreenRecordingStopResult ignored;
    return Finish(true, ignored, errorCode, errorMessage);
  }

  ScreenRecordingStatus GetStatus() {
    std::lock_guard<std::mutex> lock(mutex_);
    ScreenRecordingStatus status;
    status.isRecording = isRecording_;
    status.outputPath = Encoding::WideToUtf8(captureConfig_.outputPath);
    status.audioMode = captureConfig_.audioMode;
    status.frameCount = frameCount_.load();
    status.droppedFrames = droppedFrames_.load();
    status.width = outputWidth_;
    status.height = outputHeight_;
    if (isRecording_) {
      status.elapsedMs = std::chrono::duration_cast<std::chrono::milliseconds>(
                             std::chrono::steady_clock::now() - startTime_)
                             .count();
    }
    return status;
  }

  bool Pause() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!isRecording_ || paused_)
      return false;
    pauseStartedAt_ = std::chrono::steady_clock::now();
    paused_ = true;
    return true;
  }

  bool Resume() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!isRecording_ || !paused_)
      return false;
    pausedDurationUs_ += std::chrono::duration_cast<std::chrono::microseconds>(
                             std::chrono::steady_clock::now() - pauseStartedAt_)
                             .count();
    paused_ = false;
    return true;
  }

  void Shutdown() {
    std::string code;
    std::string message;
    ScreenRecordingStopResult ignored;
    Finish(true, ignored, code, message);
  }

private:
  struct HandleCloser {
    void operator()(HANDLE handle) const {
      if (handle != nullptr)
        CloseHandle(handle);
    }
  };

  bool Finish(bool cancel, ScreenRecordingStopResult &result,
              std::string &errorCode, std::string &errorMessage) {
    std::unique_lock<std::mutex> lock(mutex_);
    if (!isRecording_) {
      errorCode = "NOT_RECORDING";
      errorMessage = "No screen recording is currently active.";
      return false;
    }

    cancelRequested_ = cancel;
    stopRequested_ = true;
    if (frameEvent_)
      SetEvent(frameEvent_.get());

    std::thread frameThread = std::move(frameThread_);
    std::thread audioThread = std::move(audioThread_);
    lock.unlock();

    if (frameThread.joinable())
      frameThread.join();
    if (audioThread.joinable())
      audioThread.join();

    lock.lock();
    HRESULT finalizeHr = S_OK;
    {
      std::lock_guard<std::mutex> sinkLock(sinkWriterMutex_);
      if (sinkWriter_)
        finalizeHr = sinkWriter_->Finalize();
    }
    result.success = SUCCEEDED(finalizeHr) && !cancelRequested_;
    result.filePath = Encoding::WideToUtf8(captureConfig_.outputPath);
    result.frameCount = frameCount_.load();
    result.durationMs = std::chrono::duration_cast<std::chrono::milliseconds>(
                            std::chrono::steady_clock::now() - startTime_)
                            .count();

    if (cancelRequested_) {
      _wremove(captureConfig_.outputPath.c_str());
    }

    CleanupResourcesLocked();

    if (FAILED(finalizeHr) && !cancelRequested_) {
      errorCode = "FINALIZE_FAILED";
      errorMessage = "Unable to finalize the MP4 recording file.";
      return false;
    }

    return true;
  }

  bool ResolveCaptureItemLocked(const Config &config, std::string &errorCode,
                                std::string &errorMessage) {
    sourceRect_ = {0, 0, 0, 0};
    targetWindow_ = nullptr;

    if (config.targetType == TargetType::Monitor) {
      HMONITOR monitor = reinterpret_cast<HMONITOR>(
          static_cast<LONG_PTR>(config.monitorHandle));
      if (!monitor) {
        errorCode = "INVALID_MONITOR";
        errorMessage = "A valid monitor target is required.";
        return false;
      }
      item_ = CreateItemForMonitor(monitor);
      if (!item_) {
        errorCode = "CAPTURE_ITEM_FAILED";
        errorMessage = "Unable to create a capture item for the monitor.";
        return false;
      }
      const auto size = item_.Size();
      sourceRect_ = {0, 0, size.Width, size.Height};
      outputWidth_ = (std::max)(2, size.Width & ~1);
      outputHeight_ = (std::max)(2, size.Height & ~1);
      return true;
    }

    if (config.targetType == TargetType::Window) {
      targetWindow_ =
          reinterpret_cast<HWND>(static_cast<LONG_PTR>(config.hWnd));
      if (!targetWindow_ || !IsWindow(targetWindow_)) {
        errorCode = "INVALID_WINDOW";
        errorMessage = "A valid window target is required.";
        return false;
      }
      item_ = CreateItemForWindow(targetWindow_);
      if (!item_) {
        errorCode = "CAPTURE_ITEM_FAILED";
        errorMessage = "Unable to create a capture item for the window.";
        return false;
      }
      const auto size = item_.Size();
      sourceRect_ = {0, 0, size.Width, size.Height};
      outputWidth_ = (std::max)(2, size.Width & ~1);
      outputHeight_ = (std::max)(2, size.Height & ~1);
      return true;
    }

    POINT anchor = {config.region.left + 1, config.region.top + 1};
    HMONITOR monitor = MonitorFromPoint(anchor, MONITOR_DEFAULTTONEAREST);
    if (!monitor) {
      errorCode = "INVALID_REGION";
      errorMessage = "Unable to resolve a monitor for the selected region.";
      return false;
    }

    MONITORINFOEXW monitorInfo = {};
    monitorInfo.cbSize = sizeof(monitorInfo);
    if (!GetMonitorInfoW(monitor, &monitorInfo)) {
      errorCode = "MONITOR_INFO_FAILED";
      errorMessage = "Unable to read monitor information for the region.";
      return false;
    }

    item_ = CreateItemForMonitor(monitor);
    if (!item_) {
      errorCode = "CAPTURE_ITEM_FAILED";
      errorMessage = "Unable to create a capture item for the selected region.";
      return false;
    }

    sourceRect_.left = config.region.left - monitorInfo.rcMonitor.left;
    sourceRect_.top = config.region.top - monitorInfo.rcMonitor.top;
    sourceRect_.right =
        sourceRect_.left + (config.region.right - config.region.left);
    sourceRect_.bottom =
        sourceRect_.top + (config.region.bottom - config.region.top);

    sourceRect_ =
        ClampRectToSize(sourceRect_, item_.Size().Width, item_.Size().Height);
    const int regionWidth =
        static_cast<int>(sourceRect_.right - sourceRect_.left) & ~1;
    const int regionHeight =
        static_cast<int>(sourceRect_.bottom - sourceRect_.top) & ~1;
    outputWidth_ = (std::max)(2, regionWidth);
    outputHeight_ = (std::max)(2, regionHeight);
    sourceRect_.right = sourceRect_.left + outputWidth_;
    sourceRect_.bottom = sourceRect_.top + outputHeight_;
    return true;
  }

  bool InitializeSinkWriterLocked(const Config &config, std::string &errorCode,
                                  std::string &errorMessage) {
    winrt::com_ptr<IMFAttributes> attributes;
    if (FAILED(MFCreateAttributes(attributes.put(), 4))) {
      errorCode = "MF_ATTRIBUTES_FAILED";
      errorMessage = "Unable to create Media Foundation attributes.";
      return false;
    }
    attributes->SetUINT32(MF_READWRITE_ENABLE_HARDWARE_TRANSFORMS,
                          config.useHardwareEncoder ? TRUE : FALSE);
    attributes->SetUINT32(MF_SINK_WRITER_DISABLE_THROTTLING, TRUE);

    if (FAILED(MFCreateSinkWriterFromURL(config.outputPath.c_str(), nullptr,
                                         attributes.get(),
                                         sinkWriter_.put()))) {
      errorCode = "SINK_WRITER_FAILED";
      errorMessage = "Unable to create the MP4 sink writer.";
      return false;
    }

    winrt::com_ptr<IMFMediaType> videoOutputType;
    if (FAILED(MFCreateMediaType(videoOutputType.put()))) {
      errorCode = "VIDEO_TYPE_FAILED";
      errorMessage = "Unable to create the H.264 media type.";
      return false;
    }
    videoOutputType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    videoOutputType->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_H264);
    videoOutputType->SetUINT32(
        MF_MT_AVG_BITRATE,
        static_cast<UINT32>(config.videoBitrateMbps * 1000 * 1000));
    videoOutputType->SetUINT32(MF_MT_INTERLACE_MODE,
                               MFVideoInterlace_Progressive);
    MFSetAttributeSize(videoOutputType.get(), MF_MT_FRAME_SIZE, outputWidth_,
                       outputHeight_);
    MFSetAttributeRatio(videoOutputType.get(), MF_MT_FRAME_RATE,
                        config.frameRate, 1);
    MFSetAttributeRatio(videoOutputType.get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1);

    if (FAILED(sinkWriter_->AddStream(videoOutputType.get(),
                                      &videoStreamIndex_))) {
      errorCode = "ADD_VIDEO_STREAM_FAILED";
      errorMessage = "Unable to add the MP4 video stream.";
      return false;
    }

    winrt::com_ptr<IMFMediaType> videoInputType;
    if (FAILED(MFCreateMediaType(videoInputType.put()))) {
      errorCode = "VIDEO_INPUT_TYPE_FAILED";
      errorMessage = "Unable to create the video input type.";
      return false;
    }
    videoInputType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    videoInputType->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_ARGB32);
    videoInputType->SetUINT32(MF_MT_INTERLACE_MODE,
                              MFVideoInterlace_Progressive);
    MFSetAttributeSize(videoInputType.get(), MF_MT_FRAME_SIZE, outputWidth_,
                       outputHeight_);
    MFSetAttributeRatio(videoInputType.get(), MF_MT_FRAME_RATE,
                        config.frameRate, 1);
    MFSetAttributeRatio(videoInputType.get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1);

    if (FAILED(sinkWriter_->SetInputMediaType(videoStreamIndex_,
                                              videoInputType.get(), nullptr))) {
      errorCode = "SET_INPUT_TYPE_FAILED";
      errorMessage = "Unable to set the video input type for recording.";
      return false;
    }

    audioStreamIndex_ = 0;
    audioEnabled_ = config.audioMode != "none";
    if (audioEnabled_) {
      winrt::com_ptr<IMFMediaType> audioOutputType;
      if (FAILED(MFCreateMediaType(audioOutputType.put()))) {
        errorCode = "AUDIO_TYPE_FAILED";
        errorMessage = "Unable to create the AAC media type.";
        return false;
      }
      audioOutputType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
      audioOutputType->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_AAC);
      audioOutputType->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, kAudioChannels);
      audioOutputType->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND,
                                 kAudioSampleRate);
      audioOutputType->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
      audioOutputType->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, 24000);
      audioOutputType->SetUINT32(MF_MT_AAC_AUDIO_PROFILE_LEVEL_INDICATION,
                                 0x29);

      if (FAILED(sinkWriter_->AddStream(audioOutputType.get(),
                                        &audioStreamIndex_))) {
        errorCode = "ADD_AUDIO_STREAM_FAILED";
        errorMessage = "Unable to add the AAC audio stream.";
        return false;
      }

      winrt::com_ptr<IMFMediaType> audioInputType;
      if (FAILED(MFCreateMediaType(audioInputType.put()))) {
        errorCode = "AUDIO_INPUT_TYPE_FAILED";
        errorMessage = "Unable to create the PCM input type.";
        return false;
      }
      audioInputType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
      audioInputType->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM);
      audioInputType->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, kAudioChannels);
      audioInputType->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND,
                                kAudioSampleRate);
      audioInputType->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE,
                                kAudioBitsPerSample);
      audioInputType->SetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT,
                                kAudioChannels * kAudioBitsPerSample / 8);
      audioInputType->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND,
                                kAudioSampleRate * kAudioChannels *
                                    kAudioBitsPerSample / 8);

      if (FAILED(sinkWriter_->SetInputMediaType(
              audioStreamIndex_, audioInputType.get(), nullptr))) {
        errorCode = "SET_AUDIO_INPUT_FAILED";
        errorMessage = "Unable to set the PCM audio input type.";
        return false;
      }
    }

    if (FAILED(sinkWriter_->BeginWriting())) {
      errorCode = "BEGIN_WRITING_FAILED";
      errorMessage = "Unable to begin writing the MP4 file.";
      return false;
    }

    return true;
  }

  bool InitializeAudioSource(AudioSource &source, std::string &errorCode,
                             std::string &errorMessage) {
    winrt::com_ptr<IMMDeviceEnumerator> enumerator;
    HRESULT hr = CoCreateInstance(
        __uuidof(MMDeviceEnumerator), nullptr, CLSCTX_INPROC_SERVER,
        __uuidof(IMMDeviceEnumerator), enumerator.put_void());
    if (FAILED(hr)) {
      errorCode = "AUDIO_ENUMERATOR_FAILED";
      errorMessage = "Unable to create the audio device enumerator.";
      return false;
    }

    if (source.deviceId.empty()) {
      hr = enumerator->GetDefaultAudioEndpoint(source.flow, eMultimedia,
                                               source.device.put());
    } else {
      hr = enumerator->GetDevice(source.deviceId.c_str(), source.device.put());
    }
    if (FAILED(hr) || !source.device) {
      errorCode = "AUDIO_DEVICE_UNAVAILABLE";
      errorMessage =
          "Unable to open one of the requested audio capture devices.";
      return false;
    }

    hr = source.device->Activate(__uuidof(IAudioClient), CLSCTX_INPROC_SERVER,
                                 nullptr, source.client.put_void());
    if (FAILED(hr) || !source.client) {
      errorCode = "AUDIO_CLIENT_FAILED";
      errorMessage = "Unable to activate the audio client.";
      return false;
    }

    WAVEFORMATEX desired = {};
    desired.wFormatTag = WAVE_FORMAT_IEEE_FLOAT;
    desired.nChannels = kAudioChannels;
    desired.nSamplesPerSec = kAudioSampleRate;
    desired.wBitsPerSample = 32;
    desired.nBlockAlign = desired.nChannels * desired.wBitsPerSample / 8;
    desired.nAvgBytesPerSec = desired.nSamplesPerSec * desired.nBlockAlign;
    desired.cbSize = 0;

    WAVEFORMATEX *closestMatch = nullptr;
    hr = source.client->IsFormatSupported(AUDCLNT_SHAREMODE_SHARED, &desired,
                                          &closestMatch);
    if (hr == S_OK) {
      source.format.reset(reinterpret_cast<WAVEFORMATEX *>(
          CoTaskMemAlloc(sizeof(WAVEFORMATEX))));
      if (!source.format) {
        errorCode = "AUDIO_FORMAT_FAILED";
        errorMessage = "Unable to allocate the desired audio format.";
        return false;
      }
      *source.format = desired;
    } else if (hr == S_FALSE && closestMatch != nullptr) {
      source.format.reset(closestMatch);
      closestMatch = nullptr;
    } else {
      WAVEFORMATEX *mixFormat = nullptr;
      hr = source.client->GetMixFormat(&mixFormat);
      if (FAILED(hr) || mixFormat == nullptr) {
        errorCode = "AUDIO_FORMAT_FAILED";
        errorMessage = "Unable to determine the device mix format.";
        if (closestMatch != nullptr)
          CoTaskMemFree(closestMatch);
        return false;
      }
      source.format.reset(mixFormat);
    }
    if (closestMatch != nullptr)
      CoTaskMemFree(closestMatch);

    source.sampleRate =
        (std::max)(1, static_cast<int>(source.format->nSamplesPerSec));
    source.channelCount =
        (std::max)(1, static_cast<int>(source.format->nChannels));

    DWORD streamFlags = 0;
    if (source.loopback)
      streamFlags |= AUDCLNT_STREAMFLAGS_LOOPBACK;
    hr = source.client->Initialize(AUDCLNT_SHAREMODE_SHARED, streamFlags, 0, 0,
                                   source.format.get(), nullptr);
    if (FAILED(hr)) {
      errorCode = "AUDIO_INIT_FAILED";
      errorMessage = "Unable to initialize the shared-mode audio client.";
      return false;
    }

    hr = source.client->GetService(__uuidof(IAudioCaptureClient),
                                   source.capture.put_void());
    if (FAILED(hr) || !source.capture) {
      errorCode = "AUDIO_CAPTURE_SERVICE_FAILED";
      errorMessage = "Unable to open the audio capture service.";
      return false;
    }

    hr = source.client->GetBufferSize(&source.bufferFrameCount);
    if (FAILED(hr)) {
      errorCode = "AUDIO_BUFFER_SIZE_FAILED";
      errorMessage = "Unable to determine the audio buffer size.";
      return false;
    }

    return true;
  }

  bool PumpAudioPackets(AudioSource &source) {
    UINT32 packetFrames = 0;
    HRESULT hr = source.capture->GetNextPacketSize(&packetFrames);
    if (FAILED(hr))
      return false;

    while (SUCCEEDED(hr) && packetFrames > 0) {
      BYTE *data = nullptr;
      UINT32 frames = 0;
      DWORD flags = 0;
      hr = source.capture->GetBuffer(&data, &frames, &flags, nullptr, nullptr);
      if (FAILED(hr))
        return false;

      std::vector<float> stereoFloat = ConvertCapturedFramesToStereoFloat(
          data, frames, source.format.get(), flags);
      source.capture->ReleaseBuffer(frames);

      stereoFloat = ResampleStereoToTargetRate(source, stereoFloat);
      for (float sample : stereoFloat) {
        source.pendingStereo.push_back(sample);
      }

      hr = source.capture->GetNextPacketSize(&packetFrames);
    }

    return true;
  }

  bool WriteMixedAudioChunk(int framesToWrite) {
    if (framesToWrite <= 0)
      return true;

    std::vector<int16_t> pcm;
    pcm.resize(static_cast<size_t>(framesToWrite) * kAudioChannels, 0);

    for (int frame = 0; frame < framesToWrite; ++frame) {
      float left = 0.0f;
      float right = 0.0f;

      for (AudioSource &source : audioSources_) {
        if (source.pendingStereo.size() >= 2) {
          left += source.pendingStereo[0];
          right += source.pendingStereo[1];
          source.pendingStereo.pop_front();
          source.pendingStereo.pop_front();
        }
      }

      left = std::clamp(left, -1.0f, 1.0f);
      right = std::clamp(right, -1.0f, 1.0f);
      pcm[static_cast<size_t>(frame) * 2] =
          static_cast<int16_t>(left * 32767.0f);
      pcm[static_cast<size_t>(frame) * 2 + 1] =
          static_cast<int16_t>(right * 32767.0f);
    }

    winrt::com_ptr<IMFMediaBuffer> buffer;
    HRESULT hr = MFCreateMemoryBuffer(
        static_cast<DWORD>(pcm.size() * sizeof(int16_t)), buffer.put());
    if (FAILED(hr))
      return false;

    BYTE *data = nullptr;
    DWORD maxLength = 0;
    DWORD currentLength = 0;
    hr = buffer->Lock(&data, &maxLength, &currentLength);
    if (FAILED(hr))
      return false;
    std::memcpy(data, pcm.data(), pcm.size() * sizeof(int16_t));
    buffer->Unlock();
    buffer->SetCurrentLength(static_cast<DWORD>(pcm.size() * sizeof(int16_t)));

    winrt::com_ptr<IMFSample> sample;
    hr = MFCreateSample(sample.put());
    if (FAILED(hr) || FAILED(sample->AddBuffer(buffer.get())))
      return false;

    // Compute the timestamp for this chunk relative to the recording origin
    // (startTime_).  audioStartTime_ marks when IAudioClient::Start() was
    // called; audioFramesWritten_ counts samples since that moment.  Together
    // they give a sample-accurate position on the same timeline as video.
    const int64_t audioOriginHns =
        std::chrono::duration_cast<
            std::chrono::duration<int64_t, std::ratio<1, 10'000'000>>>(
            audioStartTime_ - startTime_)
            .count();
    const LONGLONG sampleTime =
        audioOriginHns + audioFramesWritten_ * 10'000'000LL / kAudioSampleRate;
    const LONGLONG sampleDuration =
        static_cast<LONGLONG>(framesToWrite) * 10'000'000LL / kAudioSampleRate;
    sample->SetSampleTime(sampleTime);
    sample->SetSampleDuration(sampleDuration);

    {
      std::lock_guard<std::mutex> lock(sinkWriterMutex_);
      hr = sinkWriter_->WriteSample(audioStreamIndex_, sample.get());
    }
    if (FAILED(hr))
      return false;

    audioFramesWritten_ += framesToWrite;
    return true;
  }

  void SignalAudioInitFailure(const std::string &code,
                              const std::string &message) {
    audioErrorCode_ = code;
    audioErrorMessage_ = message;
    audioInitSucceeded_ = false;
    audioInitDone_ = true;
    if (audioInitEvent_)
      SetEvent(audioInitEvent_.get());
  }

  void AudioLoop() {
    const HRESULT coHr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    if (FAILED(coHr) && coHr != RPC_E_CHANGED_MODE) {
      SignalAudioInitFailure("AUDIO_COM_INIT_FAILED",
                             "Unable to initialize COM for audio capture.");
      return;
    }

    std::string errorCode;
    std::string errorMessage;
    if (captureConfig_.audioMode == "system" ||
        captureConfig_.audioMode == "systemAndMic") {
      AudioSource system;
      system.label = L"system";
      system.deviceId = captureConfig_.systemAudioDeviceId;
      system.flow = eRender;
      system.loopback = true;
      if (!InitializeAudioSource(system, errorCode, errorMessage)) {
        SignalAudioInitFailure(errorCode, errorMessage);
        CoUninitialize();
        return;
      }
      audioSources_.push_back(std::move(system));
    }

    if (captureConfig_.audioMode == "mic" ||
        captureConfig_.audioMode == "systemAndMic") {
      AudioSource mic;
      mic.label = L"mic";
      mic.deviceId = captureConfig_.micDeviceId;
      mic.flow = eCapture;
      mic.loopback = false;
      if (!InitializeAudioSource(mic, errorCode, errorMessage)) {
        SignalAudioInitFailure(errorCode, errorMessage);
        CoUninitialize();
        return;
      }
      audioSources_.push_back(std::move(mic));
    }

    for (AudioSource &source : audioSources_) {
      if (FAILED(source.client->Start())) {
        SignalAudioInitFailure("AUDIO_START_FAILED",
                               "Unable to start one of the audio streams.");
        for (AudioSource &started : audioSources_) {
          if (started.client)
            started.client->Stop();
        }
        CoUninitialize();
        return;
      }
    }

    // Record the moment audio capture actually starts so that audio
    // timestamps can be expressed relative to the same origin as video.
    audioStartTime_ = std::chrono::steady_clock::now();

    audioInitSucceeded_ = true;
    audioInitDone_ = true;
    if (audioInitEvent_)
      SetEvent(audioInitEvent_.get());

    while (!stopRequested_) {
      bool ok = true;
      for (AudioSource &source : audioSources_) {
        ok = PumpAudioPackets(source) && ok;
      }
      if (!ok)
        break;

      // While paused, discard captured audio so the muxed track has no gap and
      // stays aligned with the paused-adjusted video timeline. Pumping above
      // still drains the WASAPI buffers so they don't back up.
      if (paused_) {
        for (AudioSource &source : audioSources_) {
          source.pendingStereo.clear();
        }
        Sleep(5);
        continue;
      }

      bool canWrite = true;
      for (AudioSource &source : audioSources_) {
        if (static_cast<int>(source.pendingStereo.size() / 2) <
            kAudioChunkFrames) {
          canWrite = false;
          break;
        }
      }
      if (canWrite) {
        if (!WriteMixedAudioChunk(kAudioChunkFrames))
          break;
      } else {
        Sleep(5);
      }
    }

    for (AudioSource &source : audioSources_) {
      if (source.client)
        source.client->Stop();
    }

    bool hasPending = true;
    while (hasPending) {
      hasPending = false;
      int maxFrames = 0;
      for (AudioSource &source : audioSources_) {
        maxFrames =
            (std::max)(maxFrames,
                       static_cast<int>(source.pendingStereo.size() / 2));
      }
      if (maxFrames > 0) {
        hasPending = true;
        const int frames = (std::min)(kAudioChunkFrames, maxFrames);
        if (!WriteMixedAudioChunk(frames)) {
          break;
        }
      }
    }

    audioSources_.clear();
    if (SUCCEEDED(coHr) || coHr == RPC_E_CHANGED_MODE) {
      CoUninitialize();
    }
  }

  void FrameLoop() {
    // Interval in microseconds between frames at the configured frame rate.
    const int64_t frameIntervalUs =
        1'000'000LL / (std::max)(1, captureConfig_.frameRate);
    // Timestamp of the last frame we actually encoded, in microseconds
    // since the recording start.
    int64_t nextFrameDeadlineUs = 0;

    while (!stopRequested_) {
      if (targetWindow_ != nullptr && !IsWindow(targetWindow_)) {
        stopRequested_ = true;
        break;
      }

      const DWORD waitResult = WaitForSingleObject(frameEvent_.get(), 250);
      if (waitResult != WAIT_OBJECT_0)
        continue;

      // Drain all pending frames but only encode the most recent one
      // that falls on or after the next scheduled deadline.
      try {
        Direct3D11CaptureFrame latestFrame{nullptr};
        Direct3D11CaptureFrame frame = framePool_.TryGetNextFrame();
        while (frame) {
          latestFrame = std::move(frame);
          frame = framePool_.TryGetNextFrame();
        }
        if (!latestFrame)
          continue;

        // Drop frames while paused (we still drained the pool above so it
        // doesn't back up). Timestamps subtract the accumulated paused span,
        // so the encoded video has no gap across a pause.
        if (paused_)
          continue;

        // Check wall-clock time to decide whether we should encode this frame.
        const int64_t elapsedUs =
            std::chrono::duration_cast<std::chrono::microseconds>(
                std::chrono::steady_clock::now() - startTime_)
                .count();

        if (elapsedUs >= nextFrameDeadlineUs) {
          ProcessFrame(latestFrame);
          // Advance deadline; don't let it drift behind real time if we're
          // slow.
          nextFrameDeadlineUs += frameIntervalUs;
          if (nextFrameDeadlineUs < elapsedUs) {
            nextFrameDeadlineUs = elapsedUs + frameIntervalUs;
          }
        }
        // else: frame arrived too early — drop it (skips frame, no slow-mo)
      } catch (...) {
        ++droppedFrames_;
      }
    }

    try {
      if (framePool_)
        framePool_.FrameArrived(frameArrivedToken_);
    } catch (...) {
    }
    try {
      if (session_)
        session_.Close();
    } catch (...) {
    }
    try {
      if (framePool_)
        framePool_.Close();
    } catch (...) {
    }
  }

  void ProcessFrame(const Direct3D11CaptureFrame &frame) {
    winrt::com_ptr<ID3D11Texture2D> sourceTexture = GetTextureFromFrame(frame);
    if (!sourceTexture) {
      ++droppedFrames_;
      return;
    }

    D3D11_TEXTURE2D_DESC desc = {};
    sourceTexture->GetDesc(&desc);
    if (desc.Width == 0 || desc.Height == 0) {
      ++droppedFrames_;
      return;
    }

    if (!EnsureStagingTexture(static_cast<int>(desc.Width),
                              static_cast<int>(desc.Height))) {
      ++droppedFrames_;
      return;
    }

    d3dContext_->CopyResource(stagingTexture_.get(), sourceTexture.get());

    D3D11_MAPPED_SUBRESOURCE mapped = {};
    if (FAILED(d3dContext_->Map(stagingTexture_.get(), 0, D3D11_MAP_READ, 0,
                                &mapped))) {
      ++droppedFrames_;
      return;
    }

    std::vector<uint8_t> argb;
    argb.resize(static_cast<size_t>(outputWidth_) * outputHeight_ * 4, 0);
    const RECT clamped =
        ClampRectToSize(sourceRect_, static_cast<int>(desc.Width),
                        static_cast<int>(desc.Height));
    const int copyWidth =
        (std::min)(outputWidth_,
                   static_cast<int>(clamped.right - clamped.left));
    const int copyHeight =
        (std::min)(outputHeight_,
                   static_cast<int>(clamped.bottom - clamped.top));

    for (int y = 0; y < copyHeight; ++y) {
      const uint8_t *src =
          static_cast<const uint8_t *>(mapped.pData) +
          static_cast<size_t>(clamped.top + y) * mapped.RowPitch +
          static_cast<size_t>(clamped.left) * 4;
      uint8_t *dst = argb.data() + static_cast<size_t>(y) * outputWidth_ * 4;
      std::memcpy(dst, src, static_cast<size_t>(copyWidth) * 4);
    }
    d3dContext_->Unmap(stagingTexture_.get(), 0);

    winrt::com_ptr<IMFMediaBuffer> buffer;
    if (FAILED(MFCreateMemoryBuffer(static_cast<DWORD>(argb.size()),
                                    buffer.put()))) {
      ++droppedFrames_;
      return;
    }

    BYTE *data = nullptr;
    DWORD maxLength = 0;
    DWORD currentLength = 0;
    if (FAILED(buffer->Lock(&data, &maxLength, &currentLength))) {
      ++droppedFrames_;
      return;
    }
    std::memcpy(data, argb.data(), argb.size());
    buffer->Unlock();
    buffer->SetCurrentLength(static_cast<DWORD>(argb.size()));

    winrt::com_ptr<IMFSample> sample;
    if (FAILED(MFCreateSample(sample.put())) ||
        FAILED(sample->AddBuffer(buffer.get()))) {
      ++droppedFrames_;
      return;
    }

    // Timestamp this frame relative to the recording start using the wall
    // clock.  This keeps video and audio on the same timeline: both are
    // expressed as (now - startTime_) in 100-ns units.  Using the frame's
    // SystemRelativeTime() is theoretically more accurate but requires
    // converting a QPC-epoch value to a steady_clock epoch, which is not
    // straightforward across all Windows versions.  The wall-clock approach
    // is correct as long as ProcessFrame() is called promptly after capture
    // (guaranteed by FrameLoop's deadline logic).
    const LONGLONG sampleTime =
        std::chrono::duration_cast<
            std::chrono::duration<LONGLONG, std::ratio<1, 10'000'000>>>(
            std::chrono::steady_clock::now() - startTime_)
            .count() -
        pausedDurationUs_.load() * 10LL;
    const LONGLONG sampleDuration = 10'000'000LL / captureConfig_.frameRate;
    sample->SetSampleTime(sampleTime);
    sample->SetSampleDuration(sampleDuration);

    HRESULT hr = S_OK;
    {
      std::lock_guard<std::mutex> lock(sinkWriterMutex_);
      hr = sinkWriter_->WriteSample(videoStreamIndex_, sample.get());
    }
    if (FAILED(hr)) {
      ++droppedFrames_;
      return;
    }
    ++frameCount_;
  }

  bool EnsureStagingTexture(int width, int height) {
    if (stagingTexture_ && stagingWidth_ == width && stagingHeight_ == height) {
      return true;
    }
    stagingTexture_ = nullptr;
    stagingWidth_ = width;
    stagingHeight_ = height;

    D3D11_TEXTURE2D_DESC desc = {};
    desc.Width = static_cast<UINT>(width);
    desc.Height = static_cast<UINT>(height);
    desc.MipLevels = 1;
    desc.ArraySize = 1;
    desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    desc.SampleDesc.Count = 1;
    desc.Usage = D3D11_USAGE_STAGING;
    desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    desc.BindFlags = 0;
    desc.MiscFlags = 0;
    return SUCCEEDED(
        d3dDevice_->CreateTexture2D(&desc, nullptr, stagingTexture_.put()));
  }

  void CleanupResourcesLocked() {
    isRecording_ = false;
    stopRequested_ = false;
    paused_ = false;
    pausedDurationUs_ = 0;
    cancelRequested_ = false;
    audioEnabled_ = false;
    videoStreamIndex_ = 0;
    audioStreamIndex_ = 0;
    outputWidth_ = 0;
    outputHeight_ = 0;
    stagingWidth_ = 0;
    stagingHeight_ = 0;
    targetWindow_ = nullptr;
    sourceRect_ = {0, 0, 0, 0};
    audioFramesWritten_ = 0;
    audioSources_.clear();
    audioErrorCode_.clear();
    audioErrorMessage_.clear();
    try {
      if (framePool_)
        framePool_.Close();
    } catch (...) {
    }
    try {
      if (session_)
        session_.Close();
    } catch (...) {
    }
    framePool_ = nullptr;
    session_ = nullptr;
    item_ = nullptr;
    sinkWriter_ = nullptr;
    stagingTexture_ = nullptr;
    d3dContext_ = nullptr;
    d3dDevice_ = nullptr;
    winrtDevice_ = nullptr;
    frameEvent_.reset();
    audioInitEvent_.reset();
  }

  std::mutex mutex_;
  std::mutex sinkWriterMutex_;
  bool isRecording_ = false;
  bool audioEnabled_ = false;
  std::atomic<bool> stopRequested_{false};
  std::atomic<bool> paused_{false};
  std::atomic<int64_t> pausedDurationUs_{0};
  std::chrono::steady_clock::time_point pauseStartedAt_{};
  bool cancelRequested_ = false;
  std::atomic<int> frameCount_{0};
  std::atomic<int> droppedFrames_{0};
  int64_t audioFramesWritten_ = 0;
  std::chrono::steady_clock::time_point startTime_{};
  std::chrono::steady_clock::time_point audioStartTime_{};
  Config captureConfig_;
  RECT sourceRect_{0, 0, 0, 0};
  int outputWidth_ = 0;
  int outputHeight_ = 0;
  int stagingWidth_ = 0;
  int stagingHeight_ = 0;
  HWND targetWindow_ = nullptr;
  DWORD videoStreamIndex_ = 0;
  DWORD audioStreamIndex_ = 0;
  std::thread frameThread_;
  std::thread audioThread_;
  std::unique_ptr<void, HandleCloser> frameEvent_{nullptr};
  std::unique_ptr<void, HandleCloser> audioInitEvent_{nullptr};
  bool audioInitDone_ = false;
  bool audioInitSucceeded_ = false;
  std::string audioErrorCode_;
  std::string audioErrorMessage_;
  std::vector<AudioSource> audioSources_;
  winrt::com_ptr<ID3D11Device> d3dDevice_;
  winrt::com_ptr<ID3D11DeviceContext> d3dContext_;
  winrt::com_ptr<ID3D11Texture2D> stagingTexture_;
  IDirect3DDevice winrtDevice_{nullptr};
  GraphicsCaptureItem item_{nullptr};
  Direct3D11CaptureFramePool framePool_{nullptr};
  GraphicsCaptureSession session_{nullptr};
  winrt::event_token frameArrivedToken_{};
  winrt::com_ptr<IMFSinkWriter> sinkWriter_;
};

ScreenRecordingSession &GetSession() {
  static ScreenRecordingSession session;
  return session;
}

} // namespace screen_recording

static bool StartScreenRecording(const screen_recording::Config &config,
                                 std::string &errorCode,
                                 std::string &errorMessage) {
  return screen_recording::GetSession().Start(config, errorCode, errorMessage);
}

static bool StopScreenRecording(ScreenRecordingStopResult &result,
                                std::string &errorCode,
                                std::string &errorMessage) {
  return screen_recording::GetSession().Stop(result, errorCode, errorMessage);
}

static bool CancelScreenRecording(std::string &errorCode,
                                  std::string &errorMessage) {
  return screen_recording::GetSession().Cancel(errorCode, errorMessage);
}

static bool PauseScreenRecording() {
  return screen_recording::GetSession().Pause();
}

static bool ResumeScreenRecording() {
  return screen_recording::GetSession().Resume();
}

static ScreenRecordingStatus GetScreenRecordingStatus() {
  return screen_recording::GetSession().GetStatus();
}

static void ShutdownScreenRecording() {
  screen_recording::GetSession().Shutdown();
}

#endif
