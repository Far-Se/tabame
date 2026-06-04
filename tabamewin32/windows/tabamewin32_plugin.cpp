#define _HAS_STD_BYTE 0
#include "tabamewin32_plugin.h"

#include <windows.h>

#include "include/encoding.h"
#include <ShellAPI.h>
#include <iostream>
#include <ole2.h>
#include <olectl.h>
#include <stdio.h>
#include <string>
#include <thread>
#include <vector>

#pragma warning(push)
#pragma warning(disable : 4201)
#include "capture_monitor.cpp"
#include "hicon_to_bytes.cpp"
#include "transparent.cpp"
#include "tray_info.cpp"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <atlimage.h>
#include <codecvt>

#include <cctype>
#include <chrono>
#include <functional>
#include <map>
#include <memory>
#include <regex>
#include <sstream>
#include <unordered_map>

#include "virtdesktop.cpp"
#pragma warning(pop)
#pragma comment(lib, "ole32")
#pragma comment(lib, "shell32")
#include "audio.cpp"
#include "screen_ocr.cpp"
#include "screen_recording.cpp"

// ---------------------------------------------------------------------------
// Method channel (shared with sub-modules)
// ---------------------------------------------------------------------------
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel =
    nullptr;

// ---------------------------------------------------------------------------
// Sub-modules
// ---------------------------------------------------------------------------
#include "../system_stats.cpp"
#include "appsfolder.cpp"
#include "clipboard.cpp"
#include "clipboard_extended.cpp"
#include "desktop_wallpaper.cpp"
#include "get_changed_folders.cpp"
#include "hotkeys.cpp"
#include "media_session.cpp"
#include "quickClick/QuickClickController.cpp"
#include "shellContextMenu/ShellContextMenu.cpp"
#include "shell_utils.cpp"
#include "system_utils.cpp"
#include "taskbar_uia.cpp"
#include "tray_extended.cpp"
#include "win_hooks.cpp"
#include "window_utils.cpp"
#include "windows_theme.cpp"

// ---------------------------------------------------------------------------
// GDI+ state
// ---------------------------------------------------------------------------
static ULONG_PTR gdiplusToken = 0;
static bool gdiInitialized = false;

using namespace std;

// ===========================================================================
// Type aliases & argument helpers — reduce Flutter boilerplate
// ===========================================================================
using MethodCall = flutter::MethodCall<flutter::EncodableValue>;
using MethodResult =
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>;
using EVal = flutter::EncodableValue;
using EMap = flutter::EncodableMap;

namespace Args {
inline const EMap &Map(const MethodCall &call) {
  return std::get<EMap>(*call.arguments());
}
inline int Int(const EMap &m, const char *k) {
  return std::get<int>(m.at(EVal(k)));
}
inline int64_t Int64(const EMap &m, const char *k) {
  const auto &v = m.at(EVal(k));
  if (std::holds_alternative<int64_t>(v))
    return std::get<int64_t>(v);
  return static_cast<int64_t>(std::get<int>(v));
}
inline bool Bool(const EMap &m, const char *k) {
  return std::get<bool>(m.at(EVal(k)));
}
inline double Double(const EMap &m, const char *k) {
  return std::get<double>(m.at(EVal(k)));
}
inline std::string Str(const EMap &m, const char *k) {
  return std::get<std::string>(m.at(EVal(k)));
}
} // namespace Args

inline void OK(MethodResult &r, const EVal &v) { r->Success(v); }
inline void OK(MethodResult &r) { r->Success(); }
inline void OK(MethodResult &r, bool v) { r->Success(EVal(v)); }
inline void OK(MethodResult &r, int v) { r->Success(EVal(v)); }
inline void OK(MethodResult &r, const std::string &v) { r->Success(EVal(v)); }

// ===========================================================================
// Encoding helpers — reusable serializers for common data types
// ===========================================================================
namespace Encode {
EMap DevicePropsToMap(const DeviceProps &d) {
  EMap m;
  m[EVal("id")] = EVal(Encoding::WideToUtf8(d.id));
  m[EVal("name")] = EVal(d.name);
  m[EVal("iconInfo")] = EVal(d.iconInfo);
  m[EVal("isActive")] = EVal(d.isActive);
  return m;
}

EMap ProcessVolumeToMap(const ProcessVolume &d) {
  EMap m;
  m[EVal("processId")] = EVal(d.processId);
  m[EVal("processPath")] = EVal(d.processPath);
  m[EVal("maxVolume")] = EVal(d.maxVolume);
  m[EVal("peakVolume")] = EVal(d.peakVolume);
  return m;
}

EMap ProcessVolumeListToMap(const std::vector<ProcessVolume> &list) {
  EMap map;
  for (const auto &d : list)
    map[EVal(d.processId)] = EVal(ProcessVolumeToMap(d));
  return map;
}

// Extract icon bytes from HICON, falling back from 32-bit to 24-bit.
// Returns {204,204,204} sentinel on failure.
std::vector<uint8_t> IconToBytes(HICON icon) {
  std::vector<CHAR> buff;
  if (GetIconData(icon, 32, buff) ||
      (buff.clear(), GetIconData(icon, 24, buff)))
    return {buff.begin(), buff.end()};
  return {204, 204, 204};
}

EMap TrayIconToMap(const TrayIconData &t) {
  EMap m;
  m[EVal("toolTip")] = EVal(Encoding::WideToUtf8(t.toolTip));
  m[EVal("isVisible")] = EVal(static_cast<int>(t.isVisible));
  m[EVal("processID")] = EVal(t.processID);
  m[EVal("hWnd")] =
      EVal(static_cast<int>(reinterpret_cast<LONG_PTR>(t.data.hwnd)));
  m[EVal("uID")] = EVal(static_cast<int>(t.data.uID));
  m[EVal("uCallbackMessage")] = EVal(static_cast<int>(t.data.uCallbackMessage));
  m[EVal("hIcon")] =
      EVal(static_cast<int>(reinterpret_cast<LONG_PTR>(t.data.hIcon)));
  return m;
}

EMap WindowDataToMap(const WindowData &win) {
  EMap m;
  m[EVal("helpText")] = EVal(Encoding::WideToUtf8(win.helpText));
  m[EVal("uiaName")] = EVal(Encoding::WideToUtf8(win.uiaName));
  return m;
}

EMap MonitorCaptureToMap(const MonitorCaptureResult &capture) {
  EMap m;
  m[EVal("pixels")] = EVal(capture.pixels);
  m[EVal("width")] = EVal(capture.width);
  m[EVal("height")] = EVal(capture.height);
  m[EVal("length")] = EVal(static_cast<int>(capture.pixels.size()));
  return m;
}

EMap ScreenRecordingStatusToMap(const ScreenRecordingStatus &status) {
  EMap m;
  m[EVal("isRecording")] = EVal(status.isRecording);
  m[EVal("outputPath")] = EVal(status.outputPath);
  m[EVal("audioMode")] = EVal(status.audioMode);
  m[EVal("elapsedMs")] = EVal(static_cast<int64_t>(status.elapsedMs));
  m[EVal("frameCount")] = EVal(status.frameCount);
  m[EVal("droppedFrames")] = EVal(status.droppedFrames);
  m[EVal("width")] = EVal(status.width);
  m[EVal("height")] = EVal(status.height);
  return m;
}

EMap ScreenRecordingStopResultToMap(const ScreenRecordingStopResult &result) {
  EMap m;
  m[EVal("success")] = EVal(result.success);
  m[EVal("filePath")] = EVal(result.filePath);
  m[EVal("durationMs")] = EVal(static_cast<int64_t>(result.durationMs));
  m[EVal("frameCount")] = EVal(result.frameCount);
  return m;
}

EMap RectToMap(const RECT &rect) {
  EMap m;
  m[EVal("left")] = EVal(static_cast<int>(rect.left));
  m[EVal("top")] = EVal(static_cast<int>(rect.top));
  m[EVal("right")] = EVal(static_cast<int>(rect.right));
  m[EVal("bottom")] = EVal(static_cast<int>(rect.bottom));
  return m;
}

EMap SystemStatsToMap(const SystemStats &stats, int memoryLoad) {
  EMap m;
  m[EVal("cpuLoad")] = EVal(stats.cpuUsage < 0 ? -1.0 : stats.cpuUsage / 100.0);
  m[EVal("cpuUsage")] = EVal(stats.cpuUsage);
  m[EVal("gpuUsage")] = EVal(stats.gpuUsage);
  m[EVal("cpuTemp")] = EVal(stats.cpuTemp);
  m[EVal("gpuTemp")] = EVal(stats.gpuTemp);
  m[EVal("memoryLoad")] = EVal(memoryLoad);
  return m;
}

EMap AppInfoToMap(const AppInfo &app) {
  EMap m;
  m[EVal("name")] = EVal(Encoding::WideToUtf8(app.name));
  m[EVal("executable")] = EVal(Encoding::WideToUtf8(app.executable));
  m[EVal("arguments")] = EVal(Encoding::WideToUtf8(app.arguments));
  m[EVal("appUserModelId")] = EVal(Encoding::WideToUtf8(app.appUserModelId));
  m[EVal("parsingName")] = EVal(Encoding::WideToUtf8(app.parsingName));
  return m;
}

EMap AppBitmapToMap(const AppBitmap &bitmap) {
  EMap m;
  m[EVal("pixels")] = EVal(bitmap.pixels);
  m[EVal("width")] = EVal(bitmap.width);
  m[EVal("height")] = EVal(bitmap.height);
  return m;
}

QuickClickConfig MapToQuickClickConfig(const EMap &m) {
  QuickClickConfig config;
  if (m.count(EVal("horizontalKeys"))) {
    auto s = Args::Str(m, "horizontalKeys");
    config.horizontalKeys.assign(s.begin(), s.end());
  }
  if (m.count(EVal("verticalKeys"))) {
    auto s = Args::Str(m, "verticalKeys");
    config.verticalKeys.assign(s.begin(), s.end());
  }
  if (m.count(EVal("nudgeAmount")))
    config.nudgeAmount = Args::Int(m, "nudgeAmount");
  if (m.count(EVal("shiftNudgeAmount")))
    config.shiftNudgeAmount = Args::Int(m, "shiftNudgeAmount");
  if (m.count(EVal("doubleClickThresholdMs")))
    config.doubleClickThresholdMs = Args::Int(m, "doubleClickThresholdMs");

  if (m.count(EVal("leftClickKey")))
    config.leftClickKey = Args::Int(m, "leftClickKey");
  if (m.count(EVal("rightClickKey")))
    config.rightClickKey = Args::Int(m, "rightClickKey");
  if (m.count(EVal("dragKey")))
    config.dragKey = Args::Int(m, "dragKey");

  if (m.count(EVal("scrollUpKey")))
    config.scrollUpKey = Args::Int(m, "scrollUpKey");
  if (m.count(EVal("scrollDownKey")))
    config.scrollDownKey = Args::Int(m, "scrollDownKey");
  if (m.count(EVal("scrollLeftKey")))
    config.scrollLeftKey = Args::Int(m, "scrollLeftKey");
  if (m.count(EVal("scrollRightKey")))
    config.scrollRightKey = Args::Int(m, "scrollRightKey");
  if (m.count(EVal("scrollDelta")))
    config.scrollDelta = Args::Int(m, "scrollDelta");

  if (m.count(EVal("escapeKey")))
    config.escapeKey = Args::Int(m, "escapeKey");
  if (m.count(EVal("zoneModeKey")))
    config.zoneModeKey = Args::Int(m, "zoneModeKey");
  if (m.count(EVal("nextMonitorKey")))
    config.nextMonitorKey = Args::Int(m, "nextMonitorKey");
  if (m.count(EVal("prevMonitorKey")))
    config.prevMonitorKey = Args::Int(m, "prevMonitorKey");
  if (m.count(EVal("toggleOverlayKey")))
    config.toggleOverlayKey = Args::Int(m, "toggleOverlayKey");
  if (m.count(EVal("infoKey")))
    config.infoKey = Args::Int(m, "infoKey");

  if (m.count(EVal("extraArrowBindings"))) {
    auto &bindings = std::get<EMap>(m.at(EVal("extraArrowBindings")));
    for (auto const &[k, v] : bindings) {
      std::string dir = std::get<std::string>(k);
      auto &list = std::get<flutter::EncodableList>(v);
      std::vector<int> vks;
      for (auto const &vk : list)
        vks.push_back(std::get<int>(vk));
      config.extraArrowBindings[dir] = vks;
    }
  }

  return config;
}

} // namespace Encode

// ===========================================================================
// Plugin implementation
// ===========================================================================
namespace tabamewin32 {

namespace {
HardwareMonitor &GetHardwareMonitor() {
  static HardwareMonitor monitor;
  return monitor;
}
} // namespace

bool RegisterClipboardUpdateListener(Tabamewin32Plugin *plugin) {
  if (plugin == nullptr || plugin->registrar_ == nullptr ||
      plugin->registrar_->GetView() == nullptr)
    return false;

  HWND view_hwnd = plugin->registrar_->GetView()->GetNativeWindow();
  HWND root_hwnd =
      view_hwnd != nullptr ? ::GetAncestor(view_hwnd, GA_ROOT) : nullptr;
  bool registered = false;

  if (view_hwnd != nullptr && view_hwnd != plugin->clipboard_view_hwnd_) {
    AddClipboardFormatListener(view_hwnd);
    plugin->clipboard_view_hwnd_ = view_hwnd;
    registered = true;
  }

  if (root_hwnd != nullptr && root_hwnd != view_hwnd &&
      root_hwnd != plugin->clipboard_root_hwnd_) {
    AddClipboardFormatListener(root_hwnd);
    plugin->clipboard_root_hwnd_ = root_hwnd;
    registered = true;
  }

  return registered || plugin->clipboard_view_hwnd_ != nullptr ||
         plugin->clipboard_root_hwnd_ != nullptr;
}

void UnregisterClipboardUpdateListener(Tabamewin32Plugin *plugin) {
  if (plugin == nullptr)
    return;

  if (plugin->clipboard_view_hwnd_ != nullptr) {
    RemoveClipboardFormatListener(plugin->clipboard_view_hwnd_);
    plugin->clipboard_view_hwnd_ = nullptr;
  }

  if (plugin->clipboard_root_hwnd_ != nullptr) {
    RemoveClipboardFormatListener(plugin->clipboard_root_hwnd_);
    plugin->clipboard_root_hwnd_ = nullptr;
  }
}

// -----------------------------------------------------------------------
// Handler function type
// -----------------------------------------------------------------------
using HandlerFn = std::function<void(
    Tabamewin32Plugin *self, const MethodCall &call, MethodResult result)>;

// -----------------------------------------------------------------------
// Individual handlers — grouped by domain
// -----------------------------------------------------------------------
namespace Handlers {
// ===== Audio =====
void EnumAudioDevicesH(Tabamewin32Plugin *, const MethodCall &call,
                       MethodResult result) {
  auto &a = Args::Map(call);
  auto devices =
      EnumAudioDevices(static_cast<EDataFlow>(Args::Int(a, "deviceType")));
  if (devices.empty()) {
    OK(result, EVal(EMap()));
    return;
  }
  EMap map;
  for (const auto &d : devices)
    map[EVal(Encoding::WideToUtf8(d.id))] = EVal(Encode::DevicePropsToMap(d));
  OK(result, EVal(map));
}

void CanAccessAudioH(Tabamewin32Plugin *, const MethodCall &call,
                     MethodResult result) {
  auto &a = Args::Map(call);
  OK(result,
     canAccessAudio(static_cast<EDataFlow>(Args::Int(a, "deviceType"))));
}

void GetDefaultDeviceH(Tabamewin32Plugin *, const MethodCall &call,
                       MethodResult result) {
  auto &a = Args::Map(call);
  OK(result, EVal(Encode::DevicePropsToMap(getDefaultDevice(
                 static_cast<EDataFlow>(Args::Int(a, "deviceType"))))));
}

void SetDefaultAudioDeviceH(Tabamewin32Plugin *, const MethodCall &call,
                            MethodResult result) {
  auto &a = Args::Map(call);
  auto id = Encoding::Utf8ToWide(Args::Str(a, "deviceID"));
  HRESULT hr = setDefaultDevice(
      const_cast<LPWSTR>(id.c_str()), Args::Bool(a, "console"),
      Args::Bool(a, "multimedia"), Args::Bool(a, "communications"));
  OK(result, static_cast<int>(hr));
}

void GetAudioVolumeH(Tabamewin32Plugin *, const MethodCall &call,
                     MethodResult result) {
  auto &a = Args::Map(call);
  OK(result, EVal(static_cast<double>(getVolume(
                 static_cast<EDataFlow>(Args::Int(a, "deviceType"))))));
}

void SetAudioVolumeH(Tabamewin32Plugin *, const MethodCall &call,
                     MethodResult result) {
  auto &a = Args::Map(call);
  setVolume(static_cast<float>(Args::Double(a, "volumeLevel")),
            static_cast<EDataFlow>(Args::Int(a, "deviceType")));
  OK(result, 1);
}

void SetMuteAudioDeviceH(Tabamewin32Plugin *, const MethodCall &call,
                         MethodResult result) {
  auto &a = Args::Map(call);
  setMuteAudioDevice(Args::Bool(a, "muteState"),
                     static_cast<EDataFlow>(Args::Int(a, "deviceType")));
  OK(result, 1);
}

void GetMuteAudioDeviceH(Tabamewin32Plugin *, const MethodCall &call,
                         MethodResult result) {
  auto &a = Args::Map(call);
  OK(result,
     getMuteAudioDevice(static_cast<EDataFlow>(Args::Int(a, "deviceType"))));
}

void SwitchDefaultDeviceH(Tabamewin32Plugin *, const MethodCall &call,
                          MethodResult result) {
  auto &a = Args::Map(call);
  OK(result,
     switchDefaultDevice(static_cast<EDataFlow>(Args::Int(a, "deviceType")),
                         Args::Bool(a, "console"), Args::Bool(a, "multimedia"),
                         Args::Bool(a, "communications")));
}

void SetAudioDeviceVolumeH(Tabamewin32Plugin *, const MethodCall &call,
                           MethodResult result) {
  auto &a = Args::Map(call);
  auto devID = Encoding::Utf8ToWide(Args::Str(a, "deviceID"));
  float volume = static_cast<float>(Args::Double(a, "volumeLevel"));
  OK(result, setAudioDeviceVolume(volume, const_cast<LPWSTR>(devID.c_str())));
}

void GetAudioDeviceVolumeH(Tabamewin32Plugin *, const MethodCall &call,
                           MethodResult result) {
  auto &a = Args::Map(call);
  auto devID = Encoding::Utf8ToWide(Args::Str(a, "deviceID"));
  OK(result, EVal(static_cast<double>(
                 getAudioDeviceVolume(const_cast<LPWSTR>(devID.c_str())))));
}

void SetProcessVolumeByPathH(Tabamewin32Plugin *, const MethodCall &call,
                             MethodResult result) {
  auto &a = Args::Map(call);
  std::string path = Args::Str(a, "processPath");
  float volume = static_cast<float>(Args::Double(a, "volumeLevel"));
  OK(result, SetProcessVolumeByPath(eConsole, path, volume));
}

// ===== Audio Mixer =====
void EnumAudioMixerH(Tabamewin32Plugin *, const MethodCall &,
                     MethodResult result) {
  OK(result, EVal(Encode::ProcessVolumeListToMap(GetProcessVolumes())));
}

void SetAudioMixerVolumeH(Tabamewin32Plugin *, const MethodCall &call,
                          MethodResult result) {
  auto &a = Args::Map(call);
  auto devices =
      GetProcessVolumes(Args::Int(a, "processID"),
                        static_cast<float>(Args::Double(a, "volumeLevel")));
  OK(result, EVal(Encode::ProcessVolumeListToMap(devices)));
}

// ===== Icons =====
void IconToBytesH(Tabamewin32Plugin *, const MethodCall &call,
                  MethodResult result) {
  auto &a = Args::Map(call);
  auto loc = Encoding::Utf8ToWide(Args::Str(a, "iconLocation"));
  HICON icon =
      getIconFromFile(const_cast<LPWSTR>(loc.c_str()), Args::Int(a, "iconID"));
  auto bytes = Encode::IconToBytes(icon);
  if (icon)
    DestroyIcon(icon);
  OK(result, EVal(bytes));
}

void GetWindowIconH(Tabamewin32Plugin *, const MethodCall &call,
                    MethodResult result) {
  auto &a = Args::Map(call);
  HWND hwnd =
      reinterpret_cast<HWND>(static_cast<LONG_PTR>(Args::Int(a, "hWnd")));
  LRESULT ir = SendMessage(hwnd, WM_GETICON, 2, 0);
  if (ir == 0)
    ir = GetClassLongPtr(hwnd, -14);
  OK(result, EVal(ir ? Encode::IconToBytes(reinterpret_cast<HICON>(ir))
                     : std::vector<uint8_t>{204, 204, 204}));
}

void GetIconPngH(Tabamewin32Plugin *, const MethodCall &call,
                 MethodResult result) {
  auto &a = Args::Map(call);
  HICON icon =
      reinterpret_cast<HICON>(static_cast<LONG_PTR>(Args::Int(a, "hIcon")));
  OK(result, EVal(Encode::IconToBytes(icon)));
}

// ===== Window utilities =====
void GetHwndNameH(Tabamewin32Plugin *, const MethodCall &call,
                  MethodResult result) {
  auto &a = Args::Map(call);
  HWND hwnd =
      reinterpret_cast<HWND>(static_cast<LONG_PTR>(Args::Int(a, "hWnd")));
  OK(result, Encoding::WideToUtf8(getHwndName(hwnd)));
}

void FindTopWindowH(Tabamewin32Plugin *, const MethodCall &call,
                    MethodResult result) {
  auto &a = Args::Map(call);
  HWND hwnd = FindTopWindow(static_cast<DWORD>(Args::Int(a, "processID")));
  OK(result, EVal(static_cast<int>(reinterpret_cast<LONG_PTR>(hwnd))));
}

void EnumTrayIconsH(Tabamewin32Plugin *, const MethodCall &,
                    MethodResult result) {
  auto icons = EnumSystemTray();
  EMap map;
  for (const auto &t : icons)
    map[EVal(t.processID)] = EVal(Encode::TrayIconToMap(t));
  OK(result, EVal(map));
}

void ToggleTaskbarH(Tabamewin32Plugin *, const MethodCall &call,
                    MethodResult result) {
  auto &a = Args::Map(call);
  ToggleTaskbar(Args::Bool(a, "state"));
  OK(result, true);
}

// ===== Win Hooks (generic) =====
void InstallHooksH(Tabamewin32Plugin *, const MethodCall &call,
                   MethodResult result) {
  auto &a = Args::Map(call);
  int eventMin = Args::Int(a, "eventMin");
  int eventMax = Args::Int(a, "eventMax");
  int eventFilters = Args::Int(a, "eventFilters");

  gMouseHook = SetWindowsHookEx(WH_MOUSE_LL, mHandleMouseHook,
                                GetModuleHandle(nullptr), 0);
  gEventHook = (eventMin > 0)
                   ? SetWinEventHook(eventMin, eventMax, nullptr,
                                     mHandleWinEvent, 0, 0, eventFilters)
                   : nullptr;

  EMap out;
  out[EVal("mouseHookID")] =
      EVal(static_cast<int>(reinterpret_cast<LONG_PTR>(gMouseHook)));
  out[EVal("eventHookID")] =
      EVal(static_cast<int>(reinterpret_cast<LONG_PTR>(gEventHook)));
  OK(result, EVal(out));
}

void UninstallHooksH(Tabamewin32Plugin *, const MethodCall &,
                     MethodResult result) {
  if (gEventHook)
    UnhookWinEvent(gEventHook);
  if (gMouseHook)
    UnhookWindowsHookEx(gMouseHook);
  gEventHook = nullptr;
  gMouseHook = nullptr;
  OK(result, std::string("Hooks uninstalled"));
}

void CleanHooksH(Tabamewin32Plugin *, const MethodCall &, MethodResult result) {
  for (int i = 0; i < 7; i++) {
    mouseWatchButtons[i] = 0;
    mouseControlButtons[i] = 0;
  }
  OK(result, true);
}

void UninstallSpecificHookIDH(Tabamewin32Plugin *, const MethodCall &call,
                              MethodResult result) {
  auto &a = Args::Map(call);
  int hookID = Args::Int(a, "hookID");
  int hookType = Args::Int(a, "hookType");
  if (hookType == 1) {
    UnhookWinEvent(
        reinterpret_cast<HWINEVENTHOOK>(static_cast<DWORD_PTR>(hookID)));
    OK(result, std::string("Hook WinEvent Uninstalled."));
  } else if (hookType == 2) {
    UnhookWindowsHookEx(
        reinterpret_cast<HHOOK>(static_cast<DWORD_PTR>(hookID)));
    OK(result, std::string("Hook Mouse Uninstalled."));
  }
}

void ManageMouseHookH(Tabamewin32Plugin *, const MethodCall &call,
                      MethodResult result) {
  auto &a = Args::Map(call);
  int button = Args::Int(a, "button");
  int val = (Args::Str(a, "method") == "add") ? 1 : 0;
  if (Args::Str(a, "mouseEvent") == "hold")
    mouseControlButtons[button] = val;
  else
    mouseWatchButtons[button] = val;
  OK(result, true);
}

// ===== Acrylic / Transparency =====
void SetTransparentH(Tabamewin32Plugin *self, const MethodCall &,
                     MethodResult result) {
  setTransparent(
      ::GetAncestor(self->registrar_->GetView()->GetNativeWindow(), GA_ROOT));
  OK(result);
}

void GetMainHandleH(Tabamewin32Plugin *self, const MethodCall &,
                    MethodResult result) {
  HWND h =
      ::GetAncestor(self->registrar_->GetView()->GetNativeWindow(), GA_ROOT);
  OK(result, static_cast<int>(reinterpret_cast<LONG_PTR>(h)));
}

// ===== Virtual Desktops =====
void MoveWindowToDesktopH(Tabamewin32Plugin *, const MethodCall &call,
                          MethodResult result) {
  auto &a = Args::Map(call);
  int iHwnd = Args::Int(a, "hWnd");
  int direction = Args::Int(a, "direction");

  if (!CreateScratchDesktop()) {
    OK(result, false);
    return;
  }

  if (iHwnd == 0) {
    (direction > 0) ? NextDesktop() : PrevDesktop();
  } else {
    HWND hWnd = reinterpret_cast<HWND>(static_cast<LONG_PTR>(iHwnd));
    (direction > 0) ? NextDesktop() : PrevDesktop();
    MoveToCurrent(hWnd);
    DestoryScratchDesktop();
  }
  OK(result, true);
}

void SetSkipTaskbarH(Tabamewin32Plugin *, const MethodCall &call,
                     MethodResult result) {
  auto &a = Args::Map(call);
  HWND hWnd =
      reinterpret_cast<HWND>(static_cast<LONG_PTR>(Args::Int(a, "hWnd")));
  SetHwndSkipTaskbar(hWnd, Args::Bool(a, "skip"));
  OK(result, true);
}

void ConvertLinkToPathH(Tabamewin32Plugin *, const MethodCall &call,
                        MethodResult result) {
  auto &a = Args::Map(call);
  auto linkFile = Encoding::Utf8ToWide(Args::Str(a, "lnkPath"));
  TCHAR achPath[MAX_PATH] = {0};
  int ok = LinkToPath(linkFile.c_str(), achPath, _countof(achPath));
  OK(result, ok ? Encoding::WideToUtf8(achPath) : std::string(""));
}

// ===== Shortcuts / Startup =====
void SetStartOnSystemStartupH(Tabamewin32Plugin *, const MethodCall &call,
                              MethodResult result) {
  auto &a = Args::Map(call);
  WCHAR folder[MAX_PATH];
  SHGetFolderPathW(nullptr, CSIDL_STARTUP, nullptr, 0, folder);
  CreateShortcut(Args::Bool(a, "enabled"),
                 Encoding::Utf8ToWide(Args::Str(a, "exePath")), folder,
                 Args::Int(a, "showCmd"), Args::Str(a, "args"));
  OK(result, std::string(""));
}

void CreateShortcutH(Tabamewin32Plugin *, const MethodCall &call,
                     MethodResult result) {
  auto &a = Args::Map(call);
  CreateShortcut(
      Args::Bool(a, "enabled"), Encoding::Utf8ToWide(Args::Str(a, "exePath")),
      Encoding::Utf8ToWide(Args::Str(a, "destPath")), Args::Int(a, "showCmd"),
      Args::Str(a, "args"), Encoding::Utf8ToWide(Args::Str(a, "destExe")));
  OK(result, std::string(""));
}

void SetStartOnStartupAsAdminH(Tabamewin32Plugin *, const MethodCall &call,
                               MethodResult result) {
  auto &a = Args::Map(call);
  OK(result, SetStartOnStartupAsAdmin(Args::Bool(a, "enabled"),
                                      Args::Str(a, "exePath")));
}

// ===== System utilities =====
void GetSystemUsageH(Tabamewin32Plugin *, const MethodCall &call,
                     MethodResult result) {
  MEMORYSTATUSEX statex;
  statex.dwLength = sizeof(statex);
  GlobalMemoryStatusEx(&statex);

  bool onlyUsage = true;
  if (const auto *args = call.arguments();
      args != nullptr && std::holds_alternative<EMap>(*args)) {
    const auto &map = std::get<EMap>(*args);
    auto it = map.find(EVal("onlyUsage"));
    if (it != map.end() && std::holds_alternative<bool>(it->second))
      onlyUsage = std::get<bool>(it->second);
  }

  const auto stats = GetHardwareMonitor().GetStats(onlyUsage);
  OK(result, EVal(Encode::SystemStatsToMap(
                 stats, static_cast<int>(statex.dwMemoryLoad))));
}

void ToggleMonitorWallpaperH(Tabamewin32Plugin *, const MethodCall &call,
                             MethodResult result) {
  ToggleMonitorWallpaper(Args::Bool(Args::Map(call), "enabled"));
  OK(result, true);
}

void SetWallpaperColorH(Tabamewin32Plugin *, const MethodCall &call,
                        MethodResult result) {
  SetWallpaperColor(Args::Int(Args::Map(call), "color"));
  OK(result, true);
}

void BrowseFolderH(Tabamewin32Plugin *, const MethodCall &,
                   MethodResult result) {
  OK(result, BrowseFolder());
}

void GetAllAppsH(Tabamewin32Plugin *, const MethodCall &, MethodResult result) {
  auto shared_result =
      std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(
          std::move(result));

  std::thread([shared_result]() {
    const auto apps = GetAllApps();
    flutter::EncodableList list;
    list.reserve(apps.size());
    for (const auto &app : apps)
      list.emplace_back(EVal(Encode::AppInfoToMap(app)));
    shared_result->Success(EVal(std::move(list)));
  }).detach();
}

void GetAppIconH(Tabamewin32Plugin *, const MethodCall &call,
                 MethodResult result) {
  const auto &a = Args::Map(call);
  const auto parsingName = Encoding::Utf8ToWide(Args::Str(a, "parsingName"));
  int desiredSize = 256;
  auto sizeIt = a.find(EVal("size"));
  if (sizeIt != a.end()) {
    if (std::holds_alternative<int>(sizeIt->second))
      desiredSize = std::get<int>(sizeIt->second);
    else if (std::holds_alternative<int64_t>(sizeIt->second))
      desiredSize = static_cast<int>(std::get<int64_t>(sizeIt->second));
  }

  auto shared_result =
      std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(
          std::move(result));

  std::thread([shared_result, parsingName, desiredSize]() {
    const auto bitmap = GetAppBitmap(parsingName, desiredSize);
    if (bitmap.width == 0 || bitmap.pixels.empty()) {
      shared_result->Success(EVal());
      return;
    }
    shared_result->Success(EVal(Encode::AppBitmapToMap(bitmap)));
  }).detach();
}
// ===== Hotkeys =====
void HotkeyAddH(Tabamewin32Plugin *, const MethodCall &call,
                MethodResult result) {
  auto &a = Args::Map(call);
  Hotkey hk{};
  hk.hotkey = Encoding::Utf8ToWide(Args::Str(a, "hotkey"));
  hk.keyVK = Args::Int(a, "keyVK");
  hk.modifisers = Encoding::Utf8ToWide(Args::Str(a, "modifisers"));
  hk.matchWindowBy = Args::Str(a, "matchWindowBy");
  hk.matchWindowText = Encoding::Utf8ToWide(Args::Str(a, "matchWindowText"));
  hk.activateWindowUnderCursor = Args::Bool(a, "activateWindowUnderCursor");
  hk.regionAsPercentage = Args::Bool(a, "regionasPercentage");
  hk.regionOnScreen = Args::Bool(a, "regionOnScreen");
  hk.listenToMovement = Args::Bool(a, "listenToMovement");
  hk.noopScreenBusy = Args::Bool(a, "noopScreenBusy");
  hk.name = Args::Str(a, "name");
  hk.regionX1 = Args::Int(a, "regionX1");
  hk.regionX2 = Args::Int(a, "regionX2");
  hk.regionY1 = Args::Int(a, "regionY1");
  hk.regionY2 = Args::Int(a, "regionY2");
  hk.anchorType = Args::Int(a, "anchorType");

  std::string prohibited = Args::Str(a, "prohibitedWindows");
  if (!prohibited.empty()) {
    std::stringstream ss(prohibited);
    std::string token;
    while (std::getline(ss, token, ';'))
      hk.prohibitedWindows.push_back(token);
    if (hk.prohibitedWindows.empty())
      hk.prohibitedWindows.push_back(prohibited);
  }

  hotkeys.push_back(hk);
  OK(result, true);
}

void HotkeyResetH(Tabamewin32Plugin *, const MethodCall &,
                  MethodResult result) {
  hotkeys.clear();
  ResetActiveHotkeyState();
  ResetDoubleAltGestureState();
  OK(result, true);
}

void HotkeyUnHookH(Tabamewin32Plugin *, const MethodCall &,
                   MethodResult result) {
  if (g_EventHook)
    UnhookWinEvent(g_EventHook);
  if (g_MouseHook)
    UnhookWindowsHookEx(g_MouseHook);
  if (g_KeyboardHook)
    UnhookWindowsHookEx(g_KeyboardHook);
  g_EventHook = nullptr;
  g_MouseHook = nullptr;
  g_KeyboardHook = nullptr;
  ResetDoubleAltGestureState();
  OK(result, true);
}

void HotkeyHookH(Tabamewin32Plugin *, const MethodCall &, MethodResult result) {
  if (!g_MouseHook)
    g_MouseHook = SetWindowsHookEx(WH_MOUSE_LL, HandleMouseHook,
                                   GetModuleHandle(nullptr), 0);
  if (!g_KeyboardHook)
    g_KeyboardHook = SetWindowsHookEx(WH_KEYBOARD_LL, HandleKeyboardHook,
                                      GetModuleHandle(nullptr), 0);
  if (!g_EventHook)
    g_EventHook =
        SetWinEventHook(EVENT_MIN, EVENT_MAX, nullptr, EventHook, 0, 0,
                        WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);
  OK(result, true);
}

void StartKeyboardBlockerH(Tabamewin32Plugin *, const MethodCall &,
                           MethodResult result) {
  SetKeyboardBlockerEnabled(true);
  if (!g_KeyboardHook)
    g_KeyboardHook = SetWindowsHookEx(WH_KEYBOARD_LL, HandleKeyboardHook,
                                      GetModuleHandle(nullptr), 0);
  OK(result, g_KeyboardHook != nullptr);
}

void StopKeyboardBlockerH(Tabamewin32Plugin *, const MethodCall &,
                          MethodResult result) {
  SetKeyboardBlockerEnabled(false);
  OK(result, true);
}

void FreeHotkeyH(Tabamewin32Plugin *, const MethodCall &, MethodResult result) {
  ResetActiveHotkeyState();
  ResetDoubleAltGestureState();
  OK(result, true);
}

void TrcktivityH(Tabamewin32Plugin *, const MethodCall &call,
                 MethodResult result) {
  isTrcktivityEnabled = Args::Bool(Args::Map(call), "enabled");
  OK(result, true);
}

void ViewsH(Tabamewin32Plugin *, const MethodCall &call, MethodResult result) {
  isViewsEnabled = Args::Bool(Args::Map(call), "enabled");
  OK(result, true);
}

// ===== Shell / Misc =====
void ShellOpenH(Tabamewin32Plugin *, const MethodCall &call,
                MethodResult result) {
  auto &a = Args::Map(call);
  OK(result, LaunchWithExplorer(
                 Encoding::Utf8ToWide(Args::Str(a, "path")),
                 Encoding::Utf8ToWide(Args::Str(a, "arguments")),
                 Encoding::Utf8ToWide(Args::Str(a, "workingDirectory"))));
}

void LaunchWithExplorerH(Tabamewin32Plugin *, const MethodCall &call,
                         MethodResult result) {
  auto &a = Args::Map(call);
  OK(result, LaunchWithExplorer(
                 Encoding::Utf8ToWide(Args::Str(a, "file")),
                 Encoding::Utf8ToWide(Args::Str(a, "arguments")),
                 Encoding::Utf8ToWide(Args::Str(a, "workingDirectory"))));
}

void IsWindows11H(Tabamewin32Plugin *, const MethodCall &,
                  MethodResult result) {
  OK(result, IsWindows11OrGreater());
}

void EnableDebugH(Tabamewin32Plugin *, const MethodCall &call,
                  MethodResult result) {
  auto path = Args::Str(Args::Map(call), "path");
  debugging = true;
  debugFile = path;
  appendLineToFile(path, "INITIATED");
  setAudioDebugInfo(path);
  OK(result, true);
}

void SaveClipboardImageH(Tabamewin32Plugin *, const MethodCall &call,
                         MethodResult result) {
  SaveClipboardImageAsPngFile(call, std::move(result));
}

void CopyImageToClipboardH(Tabamewin32Plugin *, const MethodCall &call,
                           MethodResult result) {
  CopyImageToClipboard(
      Encoding::Utf8ToWide(Args::Str(Args::Map(call), "path")).c_str());
  OK(result, true);
}

void InitializeGDIH(Tabamewin32Plugin *, const MethodCall &,
                    MethodResult result) {
  if (!gdiInitialized) {
    Gdiplus::GdiplusStartupInput input;
    Gdiplus::GdiplusStartup(&gdiplusToken, &input, nullptr);
    gdiInitialized = true;
  }
  OK(result, true);
}

void SetDesktopWallpaperH(Tabamewin32Plugin *, const MethodCall &call,
                          MethodResult result) {
  auto &a = Args::Map(call);
  auto path = Encoding::Utf8ToWide(Args::Str(a, "imagePath"));
  int monitorIndex = Args::Int(a, "monitorIndex");
  int fillMode = Args::Int(a, "fillMode");

  try {
    ChangeWallpaperForMonitor(path, monitorIndex,
                              static_cast<WallpaperFillMode>(fillMode));
    OK(result, true);
  } catch (const std::exception &e) {
    result->Error("WALLPAPER_ERROR", e.what());
  }
}

// ===== Taskbar UIA =====
void GetTaskbarItemHelpTextsH(Tabamewin32Plugin *, const MethodCall &,
                              MethodResult result) {
  const auto windows = GetTaskbarWindowsUIA();
  flutter::EncodableList list;
  list.reserve(windows.size());
  for (const auto &win : windows) {
    list.emplace_back(EVal(Encode::WindowDataToMap(win)));
  }
  OK(result, EVal(list));
}

void ShutdownTaskbarUiaH(Tabamewin32Plugin *, const MethodCall &,
                         MethodResult result) {
  ShutdownTaskbarUia();
  OK(result, true);
}

void GetFocusedElementRectH(Tabamewin32Plugin *, const MethodCall &,
                            MethodResult result) {
  OK(result, EVal(Encode::RectToMap(GetFocusedElementRect())));
}
void GetFocusedElementCaretRectH(Tabamewin32Plugin *, const MethodCall &,
                                 MethodResult result) {
  OK(result, EVal(Encode::RectToMap(GetFocusedElementCaretRect())));
}
void GetHardwareDataH(Tabamewin32Plugin *, const MethodCall &,
                      MethodResult result) {
  const LibreData data = GetLibreHardwareMonitor();

  EMap map;
  map[EVal("cpuUsage")] = EVal(data.cpuUsage);
  map[EVal("cpuTemp")] = EVal(data.cpuTemp);
  map[EVal("ramUsage")] = EVal(data.ramUsage);
  map[EVal("gpuUsage")] = EVal(data.gpuUsage);
  map[EVal("gpuTemp")] = EVal(data.gpuTemp);

  OK(result, EVal(map));
}
// ===== Extended tray =====
void EnumAllTrayIconsH(Tabamewin32Plugin *, const MethodCall &,
                       MethodResult result) {
  const auto icons = EnumAllTrayIcons();
  flutter::EncodableList list;
  list.reserve(icons.size());
  for (const auto &icon : icons) {
    EMap m;
    m[EVal("toolTip")] = EVal(Encoding::WideToUtf8(icon.toolTip));
    m[EVal("processId")] = EVal(icon.processId);
    m[EVal("hWnd")] =
        EVal(static_cast<int>(reinterpret_cast<LONG_PTR>(icon.appHwnd)));
    m[EVal("uID")] = EVal(static_cast<int>(icon.uID));
    m[EVal("uCallbackMsg")] = EVal(static_cast<int>(icon.uCallbackMsg));
    m[EVal("hIcon")] =
        EVal(static_cast<int>(reinterpret_cast<LONG_PTR>(icon.hIcon)));
    m[EVal("isVisible")] = EVal(icon.isVisible);
    m[EVal("isOverflow")] = EVal(icon.isOverflow);
    list.emplace_back(EVal(m));
  }
  OK(result, EVal(list));
}

void ClickTrayNotifyIconH(Tabamewin32Plugin *, const MethodCall &call,
                          MethodResult result) {
  const auto &a = Args::Map(call);
  const auto tipName = Encoding::Utf8ToWide(Args::Str(a, "tipName"));
  const bool isOverflow = Args::Bool(a, "isOverflow");
  const int clickType =
      Args::Int(a, "clickType"); // 0=left,1=right,2=mid,3=dblclk
  OK(result, ClickTrayIconUia(tipName, isOverflow, clickType));
}

void SetWindowThemeH(Tabamewin32Plugin *, const MethodCall &call,
                     MethodResult result) {
  auto &a = Args::Map(call);
  OK(result, SetWindowTheme(Args::Int(a, "type")));
}

void CaptureMonitorH(Tabamewin32Plugin *, const MethodCall &call,
                     MethodResult result) {
  auto &a = Args::Map(call);
  MonitorCaptureResult capture;
  if (!CaptureMonitor(Args::Int(a, "monitorIndex"), capture)) {
    result->Error("CAPTURE_FAILED", "Unable to capture the requested monitor.");
    return;
  }
  OK(result, EVal(Encode::MonitorCaptureToMap(capture)));
}

void CaptureMonitorBitmapAlternativeH(Tabamewin32Plugin *,
                                      const MethodCall &call,
                                      MethodResult result) {
  auto &a = Args::Map(call);
  MonitorCaptureResult capture;
  if (!CaptureMonitorBitmapAlternative(Args::Int64(a, "monitorHandle"),
                                       capture)) {
    result->Error("CAPTURE_FAILED", "Unable to capture the requested monitor "
                                    "using the bitmap alternative.");
    return;
  }
  OK(result, EVal(Encode::MonitorCaptureToMap(capture)));
}

void GetTextOCRH(Tabamewin32Plugin *, const MethodCall &call,
                 MethodResult result) {
  auto &a = Args::Map(call);
  auto shared_result =
      std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(
          std::move(result));

  const int x = Args::Int(a, "x");
  const int y = Args::Int(a, "y");
  const int width = Args::Int(a, "width");
  const int height = Args::Int(a, "height");
  const int type = Args::Int(a, "type");

  std::thread([shared_result, x, y, width, height, type]() {
    const OcrResult ocr = GetTextOCR(x, y, width, height, type);
    if (!ocr.success) {
      shared_result->Error(ocr.errorCode, ocr.errorMessage);
      return;
    }
    shared_result->Success(EVal(ocr.text));
  }).detach();
}

void ExcludeWindowFromCaptureH(Tabamewin32Plugin *, const MethodCall &call,
                               MethodResult result) {
  auto &a = Args::Map(call);
  HWND hwnd =
      reinterpret_cast<HWND>(static_cast<LONG_PTR>(Args::Int64(a, "hWnd")));
  OK(result, ExcludeWindowFromCapture(hwnd));
}

void IncludeWindowFromCaptureH(Tabamewin32Plugin *, const MethodCall &call,
                               MethodResult result) {
  auto &a = Args::Map(call);
  HWND hwnd =
      reinterpret_cast<HWND>(static_cast<LONG_PTR>(Args::Int64(a, "hWnd")));
  OK(result, IncludeWindowFromCapture(hwnd));
}

void StartScreenRecordingH(Tabamewin32Plugin *, const MethodCall &call,
                           MethodResult result) {
  auto &a = Args::Map(call);
  screen_recording::Config config;
  const std::string targetType = Args::Str(a, "targetType");
  if (targetType == "monitor") {
    config.targetType = screen_recording::TargetType::Monitor;
  } else if (targetType == "window") {
    config.targetType = screen_recording::TargetType::Window;
  } else {
    config.targetType = screen_recording::TargetType::Region;
  }

  config.region.left =
      a.count(EVal("regionLeft")) ? Args::Int(a, "regionLeft") : 0;
  config.region.top =
      a.count(EVal("regionTop")) ? Args::Int(a, "regionTop") : 0;
  config.region.right =
      config.region.left +
      (a.count(EVal("regionWidth")) ? Args::Int(a, "regionWidth") : 0);
  config.region.bottom =
      config.region.top +
      (a.count(EVal("regionHeight")) ? Args::Int(a, "regionHeight") : 0);
  config.monitorHandle =
      a.count(EVal("monitorHandle")) ? Args::Int64(a, "monitorHandle") : 0;
  config.hWnd = a.count(EVal("hWnd")) ? Args::Int64(a, "hWnd") : 0;
  config.outputPath = Encoding::Utf8ToWide(Args::Str(a, "outputPath"));
  config.frameRate =
      a.count(EVal("frameRate")) ? Args::Int(a, "frameRate") : 30;
  config.videoBitrateMbps =
      a.count(EVal("videoBitrateMbps")) ? Args::Int(a, "videoBitrateMbps") : 12;
  config.captureCursor =
      !a.count(EVal("captureCursor")) || Args::Bool(a, "captureCursor");
  config.captureBorder =
      a.count(EVal("captureBorder")) && Args::Bool(a, "captureBorder");
  config.audioMode =
      a.count(EVal("audioMode")) ? Args::Str(a, "audioMode") : "none";
  if (a.count(EVal("micDeviceId")))
    config.micDeviceId = Encoding::Utf8ToWide(Args::Str(a, "micDeviceId"));
  if (a.count(EVal("systemAudioDeviceId")))
    config.systemAudioDeviceId =
        Encoding::Utf8ToWide(Args::Str(a, "systemAudioDeviceId"));

  std::string errorCode;
  std::string errorMessage;
  if (!StartScreenRecording(config, errorCode, errorMessage)) {
    result->Error(errorCode, errorMessage);
    return;
  }
  OK(result,
     EVal(Encode::ScreenRecordingStatusToMap(GetScreenRecordingStatus())));
}

void StopScreenRecordingH(Tabamewin32Plugin *, const MethodCall &,
                          MethodResult result) {
  ScreenRecordingStopResult stopResult;
  std::string errorCode;
  std::string errorMessage;
  if (!StopScreenRecording(stopResult, errorCode, errorMessage)) {
    result->Error(errorCode, errorMessage);
    return;
  }
  OK(result, EVal(Encode::ScreenRecordingStopResultToMap(stopResult)));
}

void CancelScreenRecordingH(Tabamewin32Plugin *, const MethodCall &,
                            MethodResult result) {
  std::string errorCode;
  std::string errorMessage;
  if (!CancelScreenRecording(errorCode, errorMessage)) {
    result->Error(errorCode, errorMessage);
    return;
  }
  OK(result, true);
}

void GetScreenRecordingStatusH(Tabamewin32Plugin *, const MethodCall &,
                               MethodResult result) {
  OK(result,
     EVal(Encode::ScreenRecordingStatusToMap(GetScreenRecordingStatus())));
}

// ===== Changed Folders =====
void GetChangedFoldersH(Tabamewin32Plugin *, const MethodCall &,
                        MethodResult result) {
  auto changed = GetChangedFolders();
  flutter::EncodableList list;
  for (const auto &path : changed)
    list.push_back(EVal(Encoding::WideToUtf8(path)));
  OK(result, EVal(list));
}

void AddFoldersToWatchlistH(Tabamewin32Plugin *, const MethodCall &call,
                            MethodResult result) {
  auto &a = Args::Map(call);
  auto pathsVal = a.at(EVal("paths"));
  std::vector<std::wstring> paths;
  if (std::holds_alternative<flutter::EncodableList>(pathsVal)) {
    for (const auto &v : std::get<flutter::EncodableList>(pathsVal)) {
      paths.push_back(Encoding::Utf8ToWide(std::get<std::string>(v)));
    }
  }
  AddFoldersToWatchlist(paths);
  OK(result, true);
}

void RemoveFoldersFromWatchlistH(Tabamewin32Plugin *, const MethodCall &call,
                                 MethodResult result) {
  auto &a = Args::Map(call);
  auto pathsVal = a.at(EVal("paths"));
  std::vector<std::wstring> paths;
  if (std::holds_alternative<flutter::EncodableList>(pathsVal)) {
    for (const auto &v : std::get<flutter::EncodableList>(pathsVal)) {
      paths.push_back(Encoding::Utf8ToWide(std::get<std::string>(v)));
    }
  }
  RemoveFoldersFromWatchlist(paths);
  OK(result, true);
}

void StartClipboardWatcherH(Tabamewin32Plugin *self, const MethodCall &,
                            MethodResult result) {
  OK(result, RegisterClipboardUpdateListener(self));
}

void StopClipboardWatcherH(Tabamewin32Plugin *self, const MethodCall &,
                           MethodResult result) {
  UnregisterClipboardUpdateListener(self);
  OK(result, true);
}

void ClipboardExtendedH(Tabamewin32Plugin *, const MethodCall &call,
                        MethodResult result) {
  ClipboardExtended::HandleMethodCall(call, std::move(result));
}
void GetMediaSessionsH(Tabamewin32Plugin *, const MethodCall &,
                       MethodResult result) {
  // Move result into a shared_ptr so it can be captured by the lambda.
  // unique_ptr cannot be copied into a lambda capture.
  auto shared_result =
      std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(
          std::move(result));

  std::thread([shared_result]() {
    // Init WinRT as MTA for this thread.
    // Flutter's platform thread is STA (it owns a window), and blocking
    // .get() calls on WinRT IAsyncOperation from STA triggers:
    //   !is_sta()  assertion in Windows.Foundation.h
    winrt::init_apartment(winrt::apartment_type::multi_threaded);

    auto value = MediaSession::GetMediaSessions();

    if (auto *map = std::get_if<EMap>(&value)) {
      auto it = map->find(EVal("error"));
      if (it != map->end()) {
        const auto *message = std::get_if<std::string>(&it->second);
        shared_result->Error(
            "SMTC_ERROR", message ? *message : "Unknown media session error");
        winrt::uninit_apartment();
        return;
      }
    }

    shared_result->Success(value);
    winrt::uninit_apartment();
  }).detach();
}

// ===== QuickClick =====
void RegisterQuickClickH(Tabamewin32Plugin *self, const MethodCall &call,
                         MethodResult result) {
  auto &a = Args::Map(call);
  QuickClickConfig config = Encode::MapToQuickClickConfig(a);
  if (!self->quickClickController_) {
    self->quickClickController_ =
        std::make_unique<QuickClickController>(std::move(config));
    self->quickClickController_->SetEventCallback(
        [](const std::string &eventName,
           const std::map<std::string, std::string> &params) {
          if (channel) {
            EMap m;
            m[EVal("eventName")] = EVal(eventName);
            for (auto const &[k, v] : params) {
              m[EVal(k)] = EVal(v);
            }
            channel->InvokeMethod("onQuickClickEvent",
                                  std::make_unique<EVal>(m));
          }
        });
    self->quickClickController_->Start();
  } else {
    self->quickClickController_->UpdateConfig(std::move(config));
  }
  OK(result, true);
}

void SetQuickClickHotkeysH(Tabamewin32Plugin *self, const MethodCall &call,
                           MethodResult result) {
  if (self->quickClickController_) {
    self->quickClickController_->UpdateConfig(
        Encode::MapToQuickClickConfig(Args::Map(call)));
  }
  OK(result, true);
}

void EnableQuickClickH(Tabamewin32Plugin *self, const MethodCall &,
                       MethodResult result) {
  if (self->quickClickController_)
    self->quickClickController_->SetActive(true);
  OK(result, true);
}

void DisableQuickClickH(Tabamewin32Plugin *self, const MethodCall &,
                        MethodResult result) {
  if (self->quickClickController_)
    self->quickClickController_->SetActive(false);
  OK(result, true);
}

void GetShellMenuItemsH(Tabamewin32Plugin *, const MethodCall &call,
                        MethodResult result) {
  auto &a = Args::Map(call);
  auto path = Encoding::Utf8ToWide(Args::Str(a, "path"));
  auto items = ShellContextMenu::GetMenuItems(path);
  flutter::EncodableList list;
  list.reserve(items.size());
  for (const auto &item : items) {
    EMap m;
    m[EVal("id")] = EVal(item.id);
    m[EVal("label")] = EVal(Encoding::WideToUtf8(item.label));
    m[EVal("verb")] = EVal(Encoding::WideToUtf8(item.verb));
    m[EVal("enabled")] = EVal(item.enabled);
    if (item.hIcon) {
      m[EVal("iconBytes")] = EVal(Encode::IconToBytes(item.hIcon));
      if (item.hIcon && item.ownsIcon) {
        DestroyIcon(item.hIcon);
      }
    } else {
      m[EVal("iconBytes")] = EVal();
    }
    list.emplace_back(EVal(m));
  }
  OK(result, EVal(list));
}

void InvokeShellMenuItemH(Tabamewin32Plugin *, const MethodCall &call,
                          MethodResult result) {
  auto &a = Args::Map(call);
  auto path = Encoding::Utf8ToWide(Args::Str(a, "path"));
  auto verb = Encoding::Utf8ToWide(Args::Str(a, "verb"));
  int id = Args::Int(a, "id");
  int hWndInt = Args::Int(a, "hWnd");

  HWND hWnd = reinterpret_cast<HWND>(static_cast<intptr_t>(hWndInt));
  OK(result, ShellContextMenu::Invoke(path, verb, id, hWnd));
}

} // namespace Handlers

// -----------------------------------------------------------------------
// Dispatch table — maps method names to handler functions
// -----------------------------------------------------------------------
static const std::unordered_map<std::string, HandlerFn> &GetDispatchTable() {
  static const std::unordered_map<std::string, HandlerFn> table = {
      // Audio
      {"enumAudioDevices", Handlers::EnumAudioDevicesH},
      {"canAccessAudio", Handlers::CanAccessAudioH},
      {"getDefaultDevice", Handlers::GetDefaultDeviceH},
      {"setDefaultAudioDevice", Handlers::SetDefaultAudioDeviceH},
      {"getAudioVolume", Handlers::GetAudioVolumeH},
      {"setAudioVolume", Handlers::SetAudioVolumeH},
      {"setMuteAudioDevice", Handlers::SetMuteAudioDeviceH},
      {"getMuteAudioDevice", Handlers::GetMuteAudioDeviceH},
      {"switchDefaultDevice", Handlers::SwitchDefaultDeviceH},
      {"setAudioDeviceVolume", Handlers::SetAudioDeviceVolumeH},
      {"getAudioDeviceVolume", Handlers::GetAudioDeviceVolumeH},
      {"setProcessVolumeByPath", Handlers::SetProcessVolumeByPathH},
      // Audio Mixer
      {"enumAudioMixer", Handlers::EnumAudioMixerH},
      {"setAudioMixerVolume", Handlers::SetAudioMixerVolumeH},
      // Icons
      {"iconToBytes", Handlers::IconToBytesH},
      {"getWindowIcon", Handlers::GetWindowIconH},
      {"getIconPng", Handlers::GetIconPngH},
      // Window utilities
      {"getHwndName", Handlers::GetHwndNameH},
      {"findTopWindow", Handlers::FindTopWindowH},
      {"enumTrayIcons", Handlers::EnumTrayIconsH},
      {"toggleTaskbar", Handlers::ToggleTaskbarH},
      // Win Hooks
      {"installHooks", Handlers::InstallHooksH},
      {"uninstallHooks", Handlers::UninstallHooksH},
      {"cleanHooks", Handlers::CleanHooksH},
      {"uninstallSpecificHookID", Handlers::UninstallSpecificHookIDH},
      {"manageMouseHook", Handlers::ManageMouseHookH},
      // Acrylic
      {"setTransparent", Handlers::SetTransparentH},
      {"getMainHandle", Handlers::GetMainHandleH},
      // Virtual Desktops
      {"moveWindowToDesktop", Handlers::MoveWindowToDesktopH},
      {"setSkipTaskbar", Handlers::SetSkipTaskbarH},
      {"convertLinkToPath", Handlers::ConvertLinkToPathH},
      // Shortcuts / Startup
      {"setStartOnSystemStartup", Handlers::SetStartOnSystemStartupH},
      {"createShortcut", Handlers::CreateShortcutH},
      {"setStartOnStartupAsAdmin", Handlers::SetStartOnStartupAsAdminH},
      // System
      {"getSystemUsage", Handlers::GetSystemUsageH},
      {"toggleMonitorWallpaper", Handlers::ToggleMonitorWallpaperH},
      {"setWallpaperColor", Handlers::SetWallpaperColorH},
      {"browseFolder", Handlers::BrowseFolderH},
      {"getAllApps", Handlers::GetAllAppsH},
      {"getAppIcon", Handlers::GetAppIconH},
      // Hotkeys
      {"hotkeyAdd", Handlers::HotkeyAddH},
      {"hotkeyReset", Handlers::HotkeyResetH},
      {"hotkeyUnHook", Handlers::HotkeyUnHookH},
      {"hotkeyHook", Handlers::HotkeyHookH},
      {"startKeyboardBlocker", Handlers::StartKeyboardBlockerH},
      {"stopKeyboardBlocker", Handlers::StopKeyboardBlockerH},
      {"freeHotkey", Handlers::FreeHotkeyH},
      {"trcktivity", Handlers::TrcktivityH},
      {"views", Handlers::ViewsH},
      // Shell / Misc
      {"shellOpen", Handlers::ShellOpenH},
      {"launchWithExplorer", Handlers::LaunchWithExplorerH},
      {"isWindows11", Handlers::IsWindows11H},
      {"enableDebug", Handlers::EnableDebugH},
      {"saveClipboardImageAsPngFile", Handlers::SaveClipboardImageH},
      {"copyImageToClipboard", Handlers::CopyImageToClipboardH},
      {"initializeGDI", Handlers::InitializeGDIH},
      {"setDesktopWallpaper", Handlers::SetDesktopWallpaperH},
      // Taskbar UIA
      {"getTaskbarItemHelpTexts", Handlers::GetTaskbarItemHelpTextsH},
      {"getFocusedElementRect", Handlers::GetFocusedElementRectH},
      {"getFocusedElementCaretRect", Handlers::GetFocusedElementCaretRectH},
      {"shutdownTaskbarUia", Handlers::ShutdownTaskbarUiaH},
      // Extended tray
      {"enumAllTrayIcons", Handlers::EnumAllTrayIconsH},
      {"getHardwareData", Handlers::GetHardwareDataH},
      {"clickTrayNotifyIcon", Handlers::ClickTrayNotifyIconH},
      {"setWindowTheme", Handlers::SetWindowThemeH},
      {"captureMonitor", Handlers::CaptureMonitorH},
      {"captureMonitorBitmapAlternative",
       Handlers::CaptureMonitorBitmapAlternativeH},
      {"getTextOCR", Handlers::GetTextOCRH},
      {"excludeWindowFromCapture", Handlers::ExcludeWindowFromCaptureH},
      {"includeWindowFromCapture", Handlers::IncludeWindowFromCaptureH},
      {"startScreenRecording", Handlers::StartScreenRecordingH},
      {"stopScreenRecording", Handlers::StopScreenRecordingH},
      {"cancelScreenRecording", Handlers::CancelScreenRecordingH},
      {"getScreenRecordingStatus", Handlers::GetScreenRecordingStatusH},
      {"getChangedFolders", Handlers::GetChangedFoldersH},
      {"addFoldersToWatchlist", Handlers::AddFoldersToWatchlistH},
      {"removeFoldersFromWatchlist", Handlers::RemoveFoldersFromWatchlistH},
      {"startClipboardWatcher", Handlers::StartClipboardWatcherH},
      {"stopClipboardWatcher", Handlers::StopClipboardWatcherH},
      {"clipboardExtendedCopy", Handlers::ClipboardExtendedH},
      {"clipboardExtendedCopyRichText", Handlers::ClipboardExtendedH},
      {"clipboardExtendedCopyMultiple", Handlers::ClipboardExtendedH},
      {"clipboardExtendedCopyImage", Handlers::ClipboardExtendedH},
      {"clipboardExtendedPaste", Handlers::ClipboardExtendedH},
      {"clipboardExtendedPasteRichText", Handlers::ClipboardExtendedH},
      {"clipboardExtendedPasteImage", Handlers::ClipboardExtendedH},
      {"clipboardExtendedGetContentType", Handlers::ClipboardExtendedH},
      {"clipboardExtendedHasData", Handlers::ClipboardExtendedH},
      {"clipboardExtendedClear", Handlers::ClipboardExtendedH},
      {"clipboardExtendedGetDataSize", Handlers::ClipboardExtendedH},
      {"clipboardExtendedStartMonitoring", Handlers::ClipboardExtendedH},
      {"clipboardExtendedStopMonitoring", Handlers::ClipboardExtendedH},
      {"getMediaSessions", Handlers::GetMediaSessionsH},
      // QuickClick
      {"registerQuickClick", Handlers::RegisterQuickClickH},
      {"setQuickClickHotkeys", Handlers::SetQuickClickHotkeysH},
      {"enableQuickClick", Handlers::EnableQuickClickH},
      {"disableQuickClick", Handlers::DisableQuickClickH},
      {"getShellMenuItems", Handlers::GetShellMenuItemsH},
      {"invokeShellMenuItem", Handlers::InvokeShellMenuItemH},
  };
  return table;
}

// -----------------------------------------------------------------------
// Plugin registration
// -----------------------------------------------------------------------
void Tabamewin32Plugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), "tabamewin32",
      &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<Tabamewin32Plugin>(registrar);
  RegisterClipboardUpdateListener(plugin.get());
  plugin->clipboard_proc_id_ = registrar->RegisterTopLevelWindowProcDelegate(
      [](HWND, UINT message, WPARAM, LPARAM) -> std::optional<LRESULT> {
        if (message == WM_CLIPBOARDUPDATE && channel) {
          channel->InvokeMethod(
              "ClipboardUpdate",
              std::make_unique<flutter::EncodableValue>(true));
        }
        return std::nullopt;
      });

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

Tabamewin32Plugin::Tabamewin32Plugin(flutter::PluginRegistrarWindows *registrar)
    : registrar_(registrar) {}

Tabamewin32Plugin::~Tabamewin32Plugin() {
  UnregisterClipboardUpdateListener(this);
  if (registrar_ != nullptr && clipboard_proc_id_ != -1)
    registrar_->UnregisterTopLevelWindowProcDelegate(clipboard_proc_id_);
  if (gEventHook)
    UnhookWinEvent(gEventHook);
  if (gMouseHook)
    UnhookWindowsHookEx(gMouseHook);
  if (g_EventHook)
    UnhookWinEvent(g_EventHook);
  if (g_MouseHook)
    UnhookWindowsHookEx(g_MouseHook);
  if (g_KeyboardHook)
    UnhookWindowsHookEx(g_KeyboardHook);
  if (gdiInitialized)
    Gdiplus::GdiplusShutdown(gdiplusToken);
  if (quickClickController_)
    quickClickController_->Stop();
  ShutdownScreenRecording();
  ShutdownTaskbarUia();
}

// -----------------------------------------------------------------------
// Method dispatch — O(1) lookup via hash map
// -----------------------------------------------------------------------
void Tabamewin32Plugin::HandleMethodCall(const MethodCall &method_call,
                                         MethodResult result) {
  const auto &name = method_call.method_name();
  if (debugging)
    appendLineToFile(debugFile, name);

  const auto &table = GetDispatchTable();
  auto it = table.find(name);
  if (it != table.end())
    it->second(this, method_call, std::move(result));
  else
    result->NotImplemented();

  if (debugging)
    appendLineToFile(debugFile, "-done");
}

} // namespace tabamewin32
