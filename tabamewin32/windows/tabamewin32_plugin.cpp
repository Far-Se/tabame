#define _HAS_STD_BYTE 0
#include "tabamewin32_plugin.h"

#include <windows.h>

#include <ole2.h>
#include <ShellAPI.h>
#include <olectl.h>
#include <stdio.h>
#include <iostream>
#include <string>
#include <vector>
#include "include/encoding.h"

#pragma warning(push)
#pragma warning(disable : 4201)
#include "hicon_to_bytes.cpp"
#include "tray_info.cpp"
#include "transparent.cpp"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <atlimage.h>
#include <codecvt>

#include <cctype>
#include <memory>
#include <sstream>
#include <regex>
#include <chrono>
#include <map>
#include <unordered_map>
#include <functional>

#include "virtdesktop.cpp"
#pragma warning(pop)
#pragma comment(lib, "ole32")
#include "audio.cpp"

// ---------------------------------------------------------------------------
// Method channel (shared with sub-modules)
// ---------------------------------------------------------------------------
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel = nullptr;

// ---------------------------------------------------------------------------
// Sub-modules
// ---------------------------------------------------------------------------
#include "system_utils.cpp"
#include "clipboard.cpp"
#include "window_utils.cpp"
#include "shell_utils.cpp"
#include "win_hooks.cpp"
#include "hotkeys.cpp"

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
using MethodResult = std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>;
using EVal = flutter::EncodableValue;
using EMap = flutter::EncodableMap;

namespace Args
{
    inline const EMap &Map(const MethodCall &call) { return std::get<EMap>(*call.arguments()); }
    inline int Int(const EMap &m, const char *k) { return std::get<int>(m.at(EVal(k))); }
    inline bool Bool(const EMap &m, const char *k) { return std::get<bool>(m.at(EVal(k))); }
    inline double Double(const EMap &m, const char *k) { return std::get<double>(m.at(EVal(k))); }
    inline std::string Str(const EMap &m, const char *k) { return std::get<std::string>(m.at(EVal(k))); }
} // namespace Args

inline void OK(MethodResult &r, const EVal &v) { r->Success(v); }
inline void OK(MethodResult &r) { r->Success(); }
inline void OK(MethodResult &r, bool v) { r->Success(EVal(v)); }
inline void OK(MethodResult &r, int v) { r->Success(EVal(v)); }
inline void OK(MethodResult &r, const std::string &v) { r->Success(EVal(v)); }

// ===========================================================================
// Encoding helpers — reusable serializers for common data types
// ===========================================================================
namespace Encode
{
    EMap DevicePropsToMap(const DeviceProps &d)
    {
        EMap m;
        m[EVal("id")] = EVal(Encoding::WideToUtf8(d.id));
        m[EVal("name")] = EVal(d.name);
        m[EVal("iconInfo")] = EVal(d.iconInfo);
        m[EVal("isActive")] = EVal(d.isActive);
        return m;
    }

    EMap ProcessVolumeToMap(const ProcessVolume &d)
    {
        EMap m;
        m[EVal("processId")] = EVal(d.processId);
        m[EVal("processPath")] = EVal(d.processPath);
        m[EVal("maxVolume")] = EVal(d.maxVolume);
        m[EVal("peakVolume")] = EVal(d.peakVolume);
        return m;
    }

    EMap ProcessVolumeListToMap(const std::vector<ProcessVolume> &list)
    {
        EMap map;
        for (const auto &d : list)
            map[EVal(d.processId)] = EVal(ProcessVolumeToMap(d));
        return map;
    }

    // Extract icon bytes from HICON, falling back from 32-bit to 24-bit.
    // Returns {204,204,204} sentinel on failure.
    std::vector<uint8_t> IconToBytes(HICON icon)
    {
        std::vector<CHAR> buff;
        if (GetIconData(icon, 32, buff) || (buff.clear(), GetIconData(icon, 24, buff)))
            return {buff.begin(), buff.end()};
        return {204, 204, 204};
    }

    EMap TrayIconToMap(const TrayIconData &t)
    {
        EMap m;
        m[EVal("toolTip")] = EVal(Encoding::WideToUtf8(t.toolTip));
        m[EVal("isVisible")] = EVal(static_cast<int>(t.isVisible));
        m[EVal("processID")] = EVal(t.processID);
        m[EVal("hWnd")] = EVal(static_cast<int>(reinterpret_cast<LONG_PTR>(t.data.hwnd)));
        m[EVal("uID")] = EVal(static_cast<int>(t.data.uID));
        m[EVal("uCallbackMessage")] = EVal(static_cast<int>(t.data.uCallbackMessage));
        m[EVal("hIcon")] = EVal(static_cast<int>(reinterpret_cast<LONG_PTR>(t.data.hIcon)));
        return m;
    }
} // namespace Encode

// ===========================================================================
// Plugin implementation
// ===========================================================================
namespace tabamewin32
{
    // -----------------------------------------------------------------------
    // Handler function type
    // -----------------------------------------------------------------------
    using HandlerFn = std::function<void(
        Tabamewin32Plugin *self,
        const MethodCall &call,
        MethodResult result)>;

    // -----------------------------------------------------------------------
    // Individual handlers — grouped by domain
    // -----------------------------------------------------------------------
    namespace Handlers
    {
        // ===== Audio =====
        void EnumAudioDevicesH(Tabamewin32Plugin *, const MethodCall &call, MethodResult result)
        {
            auto &a = Args::Map(call);
            auto devices = EnumAudioDevices(static_cast<EDataFlow>(Args::Int(a, "deviceType")));
            if (devices.empty()) { OK(result, EVal(EMap())); return; }
            EMap map;
            for (const auto &d : devices)
                map[EVal(Encoding::WideToUtf8(d.id))] = EVal(Encode::DevicePropsToMap(d));
            OK(result, EVal(map));
        }

        void CanAccessAudioH(Tabamewin32Plugin *, const MethodCall &call, MethodResult result)
        {
            auto &a = Args::Map(call);
            OK(result, canAccessAudio(static_cast<EDataFlow>(Args::Int(a, "deviceType"))));
        }

        void GetDefaultDeviceH(Tabamewin32Plugin *, const MethodCall &call, MethodResult result)
        {
            auto &a = Args::Map(call);
            OK(result, EVal(Encode::DevicePropsToMap(
                getDefaultDevice(static_cast<EDataFlow>(Args::Int(a, "deviceType"))))));
        }

        void SetDefaultAudioDeviceH(Tabamewin32Plugin *, const MethodCall &call, MethodResult result)
        {
            auto &a = Args::Map(call);
            auto id = Encoding::Utf8ToWide(Args::Str(a, "deviceID"));
            HRESULT hr = setDefaultDevice(const_cast<LPWSTR>(id.c_str()),
                                          Args::Bool(a, "console"),
                                          Args::Bool(a, "multimedia"),
                                          Args::Bool(a, "communications"));
            OK(result, static_cast<int>(hr));
        }

        void GetAudioVolumeH(Tabamewin32Plugin *, const MethodCall &call, MethodResult result)
        {
            auto &a = Args::Map(call);
            OK(result, EVal(static_cast<double>(getVolume(static_cast<EDataFlow>(Args::Int(a, "deviceType"))))));
        }

        void SetAudioVolumeH(Tabamewin32Plugin *, const MethodCall &call, MethodResult result)
        {
            auto &a = Args::Map(call);
            setVolume(static_cast<float>(Args::Double(a, "volumeLevel")),
                      static_cast<EDataFlow>(Args::Int(a, "deviceType")));
            OK(result, 1);
        }

        void SetMuteAudioDeviceH(Tabamewin32Plugin *, const MethodCall &call, MethodResult result)
        {
            auto &a = Args::Map(call);
            setMuteAudioDevice(Args::Bool(a, "muteState"),
                               static_cast<EDataFlow>(Args::Int(a, "deviceType")));
            OK(result, 1);
        }

        void GetMuteAudioDeviceH(Tabamewin32Plugin *, const MethodCall &call, MethodResult result)
        {
            auto &a = Args::Map(call);
            OK(result, getMuteAudioDevice(static_cast<EDataFlow>(Args::Int(a, "deviceType"))));
        }

        void SwitchDefaultDeviceH(Tabamewin32Plugin *, const MethodCall &call, MethodResult result)
        {
            auto &a = Args::Map(call);
            OK(result, switchDefaultDevice(
                           static_cast<EDataFlow>(Args::Int(a, "deviceType")),
                           Args::Bool(a, "console"),
                           Args::Bool(a, "multimedia"),
                           Args::Bool(a, "communications")));
        }

        // ===== Audio Mixer =====
        void EnumAudioMixerH(Tabamewin32Plugin *, const MethodCall &, MethodResult result)
        {
            OK(result, EVal(Encode::ProcessVolumeListToMap(GetProcessVolumes())));
        }

        void SetAudioMixerVolumeH(Tabamewin32Plugin *, const MethodCall &call, MethodResult result)
        {
            auto &a = Args::Map(call);
            auto devices = GetProcessVolumes(Args::Int(a, "processID"),
                                             static_cast<float>(Args::Double(a, "volumeLevel")));
            OK(result, EVal(Encode::ProcessVolumeListToMap(devices)));
        }

        // ===== Icons =====
        void IconToBytesH(Tabamewin32Plugin *, const MethodCall &call, MethodResult result)
        {
            auto &a = Args::Map(call);
            auto loc = Encoding::Utf8ToWide(Args::Str(a, "iconLocation"));
            HICON icon = getIconFromFile(const_cast<LPWSTR>(loc.c_str()), Args::Int(a, "iconID"));
            auto bytes = Encode::IconToBytes(icon);
            if (icon) DestroyIcon(icon);
            OK(result, EVal(bytes));
        }

        void GetWindowIconH(Tabamewin32Plugin *, const MethodCall &call, MethodResult result)
        {
            auto &a = Args::Map(call);
            HWND hwnd = reinterpret_cast<HWND>(static_cast<LONG_PTR>(Args::Int(a, "hWnd")));
            LRESULT ir = SendMessage(hwnd, WM_GETICON, 2, 0);
            if (ir == 0) ir = GetClassLongPtr(hwnd, -14);
            OK(result, EVal(ir ? Encode::IconToBytes(reinterpret_cast<HICON>(ir))
                               : std::vector<uint8_t>{204, 204, 204}));
        }

        void GetIconPngH(Tabamewin32Plugin *, const MethodCall &call, MethodResult result)
        {
            auto &a = Args::Map(call);
            HICON icon = reinterpret_cast<HICON>(static_cast<LONG_PTR>(Args::Int(a, "hIcon")));
            OK(result, EVal(Encode::IconToBytes(icon)));
        }

        // ===== Window utilities =====
        void GetHwndNameH(Tabamewin32Plugin *, const MethodCall &call, MethodResult result)
        {
            auto &a = Args::Map(call);
            HWND hwnd = reinterpret_cast<HWND>(static_cast<LONG_PTR>(Args::Int(a, "hWnd")));
            OK(result, Encoding::WideToUtf8(getHwndName(hwnd)));
        }

        void FindTopWindowH(Tabamewin32Plugin *, const MethodCall &call, MethodResult result)
        {
            auto &a = Args::Map(call);
            HWND hwnd = FindTopWindow(static_cast<DWORD>(Args::Int(a, "processID")));
            OK(result, EVal(static_cast<int>(reinterpret_cast<LONG_PTR>(hwnd))));
        }

        void EnumTrayIconsH(Tabamewin32Plugin *, const MethodCall &, MethodResult result)
        {
            auto icons = EnumSystemTray();
            EMap map;
            for (const auto &t : icons)
                map[EVal(t.processID)] = EVal(Encode::TrayIconToMap(t));
            OK(result, EVal(map));
        }

        void ToggleTaskbarH(Tabamewin32Plugin *, const MethodCall &call, MethodResult result)
        {
            auto &a = Args::Map(call);
            ToggleTaskbar(Args::Bool(a, "state"));
            OK(result, true);
        }

        // ===== Win Hooks (generic) =====
        void InstallHooksH(Tabamewin32Plugin *, const MethodCall &call, MethodResult result)
        {
            auto &a = Args::Map(call);
            int eventMin = Args::Int(a, "eventMin");
            int eventMax = Args::Int(a, "eventMax");
            int eventFilters = Args::Int(a, "eventFilters");

            gMouseHook = SetWindowsHookEx(WH_MOUSE_LL, mHandleMouseHook, GetModuleHandle(nullptr), 0);
            gEventHook = (eventMin > 0)
                             ? SetWinEventHook(eventMin, eventMax, nullptr, mHandleWinEvent, 0, 0, eventFilters)
                             : nullptr;

            EMap out;
            out[EVal("mouseHookID")] = EVal(static_cast<int>(reinterpret_cast<LONG_PTR>(gMouseHook)));
            out[EVal("eventHookID")] = EVal(static_cast<int>(reinterpret_cast<LONG_PTR>(gEventHook)));
            OK(result, EVal(out));
        }

        void UninstallHooksH(Tabamewin32Plugin *, const MethodCall &, MethodResult result)
        {
            if (gEventHook) UnhookWinEvent(gEventHook);
            if (gMouseHook) UnhookWindowsHookEx(gMouseHook);
            gEventHook = nullptr;
            gMouseHook = nullptr;
            OK(result, std::string("Hooks uninstalled"));
        }

        void CleanHooksH(Tabamewin32Plugin *, const MethodCall &, MethodResult result)
        {
            for (int i = 0; i < 7; i++) { mouseWatchButtons[i] = 0; mouseControlButtons[i] = 0; }
            OK(result, true);
        }

        void UninstallSpecificHookIDH(Tabamewin32Plugin *, const MethodCall &call, MethodResult result)
        {
            auto &a = Args::Map(call);
            int hookID = Args::Int(a, "hookID");
            int hookType = Args::Int(a, "hookType");
            if (hookType == 1) {
                UnhookWinEvent(reinterpret_cast<HWINEVENTHOOK>(static_cast<DWORD_PTR>(hookID)));
                OK(result, std::string("Hook WinEvent Uninstalled."));
            } else if (hookType == 2) {
                UnhookWindowsHookEx(reinterpret_cast<HHOOK>(static_cast<DWORD_PTR>(hookID)));
                OK(result, std::string("Hook Mouse Uninstalled."));
            }
        }

        void ManageMouseHookH(Tabamewin32Plugin *, const MethodCall &call, MethodResult result)
        {
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
        void SetTransparentH(Tabamewin32Plugin *self, const MethodCall &, MethodResult result)
        {
            setTransparent(::GetAncestor(self->registrar_->GetView()->GetNativeWindow(), GA_ROOT));
            OK(result);
        }

        void GetMainHandleH(Tabamewin32Plugin *self, const MethodCall &, MethodResult result)
        {
            HWND h = ::GetAncestor(self->registrar_->GetView()->GetNativeWindow(), GA_ROOT);
            OK(result, static_cast<int>(reinterpret_cast<LONG_PTR>(h)));
        }

        // ===== Virtual Desktops =====
        void MoveWindowToDesktopH(Tabamewin32Plugin *, const MethodCall &call, MethodResult result)
        {
            auto &a = Args::Map(call);
            int iHwnd = Args::Int(a, "hWnd");
            int direction = Args::Int(a, "direction");

            if (!CreateScratchDesktop()) { OK(result, false); return; }

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

        void SetSkipTaskbarH(Tabamewin32Plugin *, const MethodCall &call, MethodResult result)
        {
            auto &a = Args::Map(call);
            HWND hWnd = reinterpret_cast<HWND>(static_cast<LONG_PTR>(Args::Int(a, "hWnd")));
            SetHwndSkipTaskbar(hWnd, Args::Bool(a, "skip"));
            OK(result, true);
        }

        void ConvertLinkToPathH(Tabamewin32Plugin *, const MethodCall &call, MethodResult result)
        {
            auto &a = Args::Map(call);
            auto linkFile = Encoding::Utf8ToWide(Args::Str(a, "lnkPath"));
            TCHAR achPath[MAX_PATH] = {0};
            int ok = LinkToPath(linkFile.c_str(), achPath, _countof(achPath));
            OK(result, ok ? Encoding::WideToUtf8(achPath) : std::string(""));
        }

        // ===== Shortcuts / Startup =====
        void SetStartOnSystemStartupH(Tabamewin32Plugin *, const MethodCall &call, MethodResult result)
        {
            auto &a = Args::Map(call);
            WCHAR folder[MAX_PATH];
            SHGetFolderPathW(nullptr, CSIDL_STARTUP, nullptr, 0, folder);
            CreateShortcut(Args::Bool(a, "enabled"),
                           Encoding::Utf8ToWide(Args::Str(a, "exePath")),
                           folder, Args::Int(a, "showCmd"), Args::Str(a, "args"));
            OK(result, std::string(""));
        }

        void CreateShortcutH(Tabamewin32Plugin *, const MethodCall &call, MethodResult result)
        {
            auto &a = Args::Map(call);
            CreateShortcut(Args::Bool(a, "enabled"),
                           Encoding::Utf8ToWide(Args::Str(a, "exePath")),
                           Encoding::Utf8ToWide(Args::Str(a, "destPath")),
                           Args::Int(a, "showCmd"), Args::Str(a, "args"),
                           Encoding::Utf8ToWide(Args::Str(a, "destExe")));
            OK(result, std::string(""));
        }

        void SetStartOnStartupAsAdminH(Tabamewin32Plugin *, const MethodCall &call, MethodResult result)
        {
            auto &a = Args::Map(call);
            OK(result, SetStartOnStartupAsAdmin(Args::Bool(a, "enabled"), Args::Str(a, "exePath")));
        }

        // ===== System utilities =====
        void GetSystemUsageH(Tabamewin32Plugin *, const MethodCall &, MethodResult result)
        {
            MEMORYSTATUSEX statex;
            statex.dwLength = sizeof(statex);
            GlobalMemoryStatusEx(&statex);

            EMap map;
            map[EVal("cpuLoad")] = EVal(GetCPULoad());
            map[EVal("memoryLoad")] = EVal(static_cast<int>(statex.dwMemoryLoad));
            OK(result, EVal(map));
        }

        void ToggleMonitorWallpaperH(Tabamewin32Plugin *, const MethodCall &call, MethodResult result)
        {
            ToggleMonitorWallpaper(Args::Bool(Args::Map(call), "enabled"));
            OK(result, true);
        }

        void SetWallpaperColorH(Tabamewin32Plugin *, const MethodCall &call, MethodResult result)
        {
            SetWallpaperColor(Args::Int(Args::Map(call), "color"));
            OK(result, true);
        }

        void BrowseFolderH(Tabamewin32Plugin *, const MethodCall &, MethodResult result)
        {
            OK(result, BrowseFolder());
        }

        // ===== Hotkeys =====
        void HotkeyAddH(Tabamewin32Plugin *, const MethodCall &call, MethodResult result)
        {
            auto &a = Args::Map(call);
            Hotkey hk{};
            hk.hotkey                   = Encoding::Utf8ToWide(Args::Str(a, "hotkey"));
            hk.keyVK                    = Args::Int(a, "keyVK");
            hk.modifisers               = Encoding::Utf8ToWide(Args::Str(a, "modifisers"));
            hk.matchWindowBy            = Args::Str(a, "matchWindowBy");
            hk.matchWindowText          = Encoding::Utf8ToWide(Args::Str(a, "matchWindowText"));
            hk.activateWindowUnderCursor = Args::Bool(a, "activateWindowUnderCursor");
            hk.regionAsPercentage       = Args::Bool(a, "regionasPercentage");
            hk.regionOnScreen           = Args::Bool(a, "regionOnScreen");
            hk.listenToMovement         = Args::Bool(a, "listenToMovement");
            hk.noopScreenBusy           = Args::Bool(a, "noopScreenBusy");
            hk.name                     = Args::Str(a, "name");
            hk.regionX1                 = Args::Int(a, "regionX1");
            hk.regionX2                 = Args::Int(a, "regionX2");
            hk.regionY1                 = Args::Int(a, "regionY1");
            hk.regionY2                 = Args::Int(a, "regionY2");
            hk.anchorType               = Args::Int(a, "anchorType");

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

        void HotkeyResetH(Tabamewin32Plugin *, const MethodCall &, MethodResult result)
        {
            hotkeys.clear();
            OK(result, true);
        }

        void HotkeyUnHookH(Tabamewin32Plugin *, const MethodCall &, MethodResult result)
        {
            if (g_EventHook) UnhookWinEvent(g_EventHook);
            if (g_MouseHook) UnhookWindowsHookEx(g_MouseHook);
            if (g_KeyboardHook) UnhookWindowsHookEx(g_KeyboardHook);
            g_EventHook = nullptr;
            g_MouseHook = nullptr;
            g_KeyboardHook = nullptr;
            OK(result, true);
        }

        void HotkeyHookH(Tabamewin32Plugin *, const MethodCall &, MethodResult result)
        {
            if (!g_MouseHook)
                g_MouseHook = SetWindowsHookEx(WH_MOUSE_LL, HandleMouseHook, GetModuleHandle(nullptr), 0);
            if (!g_KeyboardHook)
                g_KeyboardHook = SetWindowsHookEx(WH_KEYBOARD_LL, HandleKeyboardHook, GetModuleHandle(nullptr), 0);
            if (!g_EventHook)
                g_EventHook = SetWinEventHook(EVENT_MIN, EVENT_MAX, nullptr, EventHook, 0, 0,
                                              WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);
            OK(result, true);
        }

        void FreeHotkeyH(Tabamewin32Plugin *, const MethodCall &, MethodResult result)
        {
            hotkeyPressed = false;
            hotkeyCorrectName = false;
            OK(result, true);
        }

        void TrcktivityH(Tabamewin32Plugin *, const MethodCall &call, MethodResult result)
        {
            isTrcktivityEnabled = Args::Bool(Args::Map(call), "enabled");
            OK(result, true);
        }

        void ViewsH(Tabamewin32Plugin *, const MethodCall &call, MethodResult result)
        {
            isViewsEnabled = Args::Bool(Args::Map(call), "enabled");
            OK(result, true);
        }

        // ===== Shell / Misc =====
        void ShellOpenH(Tabamewin32Plugin *, const MethodCall &call, MethodResult result)
        {
            auto &a = Args::Map(call);
            OK(result, LaunchWithExplorer(Encoding::Utf8ToWide(Args::Str(a, "path")),
                                          Encoding::Utf8ToWide(Args::Str(a, "arguments")),
                                          Encoding::Utf8ToWide(Args::Str(a, "workingDirectory"))));
        }

        void LaunchWithExplorerH(Tabamewin32Plugin *, const MethodCall &call, MethodResult result)
        {
            auto &a = Args::Map(call);
            OK(result, LaunchWithExplorer(Encoding::Utf8ToWide(Args::Str(a, "file")),
                                          Encoding::Utf8ToWide(Args::Str(a, "arguments")),
                                          Encoding::Utf8ToWide(Args::Str(a, "workingDirectory"))));
        }

        void IsWindows11H(Tabamewin32Plugin *, const MethodCall &, MethodResult result)
        {
            OK(result, IsWindows11OrGreater());
        }

        void EnableDebugH(Tabamewin32Plugin *, const MethodCall &call, MethodResult result)
        {
            auto path = Args::Str(Args::Map(call), "path");
            debugging = true;
            debugFile = path;
            appendLineToFile(path, "INITIATED");
            setAudioDebugInfo(path);
            OK(result, true);
        }

        void SaveClipboardImageH(Tabamewin32Plugin *, const MethodCall &call, MethodResult result)
        {
            SaveClipboardImageAsPngFile(call, std::move(result));
        }

        void CopyImageToClipboardH(Tabamewin32Plugin *, const MethodCall &call, MethodResult result)
        {
            CopyImageToClipboard(Encoding::Utf8ToWide(Args::Str(Args::Map(call), "path")).c_str());
            OK(result, true);
        }

        void InitializeGDIH(Tabamewin32Plugin *, const MethodCall &, MethodResult result)
        {
            if (!gdiInitialized) {
                Gdiplus::GdiplusStartupInput input;
                Gdiplus::GdiplusStartup(&gdiplusToken, &input, nullptr);
                gdiInitialized = true;
            }
            OK(result, true);
        }
    } // namespace Handlers

    // -----------------------------------------------------------------------
    // Dispatch table — maps method names to handler functions
    // -----------------------------------------------------------------------
    static const std::unordered_map<std::string, HandlerFn> &GetDispatchTable()
    {
        static const std::unordered_map<std::string, HandlerFn> table = {
            // Audio
            {"enumAudioDevices",       Handlers::EnumAudioDevicesH},
            {"canAccessAudio",         Handlers::CanAccessAudioH},
            {"getDefaultDevice",       Handlers::GetDefaultDeviceH},
            {"setDefaultAudioDevice",  Handlers::SetDefaultAudioDeviceH},
            {"getAudioVolume",         Handlers::GetAudioVolumeH},
            {"setAudioVolume",         Handlers::SetAudioVolumeH},
            {"setMuteAudioDevice",     Handlers::SetMuteAudioDeviceH},
            {"getMuteAudioDevice",     Handlers::GetMuteAudioDeviceH},
            {"switchDefaultDevice",    Handlers::SwitchDefaultDeviceH},
            // Audio Mixer
            {"enumAudioMixer",         Handlers::EnumAudioMixerH},
            {"setAudioMixerVolume",    Handlers::SetAudioMixerVolumeH},
            // Icons
            {"iconToBytes",            Handlers::IconToBytesH},
            {"getWindowIcon",          Handlers::GetWindowIconH},
            {"getIconPng",             Handlers::GetIconPngH},
            // Window utilities
            {"getHwndName",            Handlers::GetHwndNameH},
            {"findTopWindow",          Handlers::FindTopWindowH},
            {"enumTrayIcons",          Handlers::EnumTrayIconsH},
            {"toggleTaskbar",          Handlers::ToggleTaskbarH},
            // Win Hooks
            {"installHooks",           Handlers::InstallHooksH},
            {"uninstallHooks",         Handlers::UninstallHooksH},
            {"cleanHooks",             Handlers::CleanHooksH},
            {"uninstallSpecificHookID", Handlers::UninstallSpecificHookIDH},
            {"manageMouseHook",        Handlers::ManageMouseHookH},
            // Acrylic
            {"setTransparent",         Handlers::SetTransparentH},
            {"getMainHandle",          Handlers::GetMainHandleH},
            // Virtual Desktops
            {"moveWindowToDesktop",    Handlers::MoveWindowToDesktopH},
            {"setSkipTaskbar",         Handlers::SetSkipTaskbarH},
            {"convertLinkToPath",      Handlers::ConvertLinkToPathH},
            // Shortcuts / Startup
            {"setStartOnSystemStartup", Handlers::SetStartOnSystemStartupH},
            {"createShortcut",         Handlers::CreateShortcutH},
            {"setStartOnStartupAsAdmin", Handlers::SetStartOnStartupAsAdminH},
            // System
            {"getSystemUsage",         Handlers::GetSystemUsageH},
            {"toggleMonitorWallpaper", Handlers::ToggleMonitorWallpaperH},
            {"setWallpaperColor",      Handlers::SetWallpaperColorH},
            {"browseFolder",           Handlers::BrowseFolderH},
            // Hotkeys
            {"hotkeyAdd",              Handlers::HotkeyAddH},
            {"hotkeyReset",            Handlers::HotkeyResetH},
            {"hotkeyUnHook",           Handlers::HotkeyUnHookH},
            {"hotkeyHook",             Handlers::HotkeyHookH},
            {"freeHotkey",             Handlers::FreeHotkeyH},
            {"trcktivity",             Handlers::TrcktivityH},
            {"views",                  Handlers::ViewsH},
            // Shell / Misc
            {"shellOpen",              Handlers::ShellOpenH},
            {"launchWithExplorer",     Handlers::LaunchWithExplorerH},
            {"isWindows11",            Handlers::IsWindows11H},
            {"enableDebug",            Handlers::EnableDebugH},
            {"saveClipboardImageAsPngFile", Handlers::SaveClipboardImageH},
            {"copyImageToClipboard",   Handlers::CopyImageToClipboardH},
            {"initializeGDI",          Handlers::InitializeGDIH},
        };
        return table;
    }

    // -----------------------------------------------------------------------
    // Plugin registration
    // -----------------------------------------------------------------------
    void Tabamewin32Plugin::RegisterWithRegistrar(
        flutter::PluginRegistrarWindows *registrar)
    {
        channel =
            std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
                registrar->messenger(), "tabamewin32",
                &flutter::StandardMethodCodec::GetInstance());

        auto plugin = std::make_unique<Tabamewin32Plugin>(registrar);

        channel->SetMethodCallHandler(
            [plugin_pointer = plugin.get()](const auto &call, auto result)
            {
                plugin_pointer->HandleMethodCall(call, std::move(result));
            });

        registrar->AddPlugin(std::move(plugin));
    }

    Tabamewin32Plugin::Tabamewin32Plugin(flutter::PluginRegistrarWindows *registrar)
        : registrar_(registrar) {}

    Tabamewin32Plugin::~Tabamewin32Plugin()
    {
        if (gEventHook) UnhookWinEvent(gEventHook);
        if (gMouseHook) UnhookWindowsHookEx(gMouseHook);
        if (g_EventHook) UnhookWinEvent(g_EventHook);
        if (g_MouseHook) UnhookWindowsHookEx(g_MouseHook);
        if (g_KeyboardHook) UnhookWindowsHookEx(g_KeyboardHook);
        if (gdiInitialized) Gdiplus::GdiplusShutdown(gdiplusToken);
    }

    // -----------------------------------------------------------------------
    // Method dispatch — O(1) lookup via hash map
    // -----------------------------------------------------------------------
    void Tabamewin32Plugin::HandleMethodCall(
        const MethodCall &method_call,
        MethodResult result)
    {
        const auto &name = method_call.method_name();
        if (debugging) appendLineToFile(debugFile, name);

        const auto &table = GetDispatchTable();
        auto it = table.find(name);
        if (it != table.end())
            it->second(this, method_call, std::move(result));
        else
            result->NotImplemented();

        if (debugging) appendLineToFile(debugFile, "-done");
    }

} // namespace tabamewin32
