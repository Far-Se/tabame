#include "tabamewin32_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

#include <ole2.h>
#include <ShellAPI.h>
#include <olectl.h>
#include <stdio.h>
#include <iostream>
#include <string>
#include <vector>
#include "include/encoding.h"
//#include "hicon_to_bytes.cpp"

#pragma warning(push)
#pragma warning(disable : 4201)
#include "hicon_to_bytes.cpp"
#include "tray_info.cpp"
#include "transparent.cpp"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <sstream>

// #include <shobjidl.h>
#include "virtdesktop.cpp"
#pragma warning(pop)
#pragma comment(lib, "ole32")
#include "audio.cpp"
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>, std::default_delete<flutter::MethodChannel<flutter::EncodableValue>>> channel = nullptr;

void CALLBACK HandleWinEvent(HWINEVENTHOOK, DWORD, HWND, LONG, LONG, DWORD, DWORD);
LRESULT CALLBACK HandleMouseHook(int, WPARAM, LPARAM);
HWINEVENTHOOK g_EventHook = NULL;
HHOOK g_MouseHook = NULL;
int mouseWatchButtons[7] = {0, 0, 0, 0, 0, 0, 0};
int mouseControlButtons[7] = {0, 0, 0, 0, 0, 0, 0};
#define EVENTHOOK 1
#define MOUSEHOOK 2

using namespace std;

void ToggleMonitorWallpaper(bool enabled)
{
    CoInitialize(NULL);
    IDesktopWallpaper *p;
    if (SUCCEEDED(CoCreateInstance(__uuidof(DesktopWallpaper), 0, CLSCTX_LOCAL_SERVER, __uuidof(IDesktopWallpaper), (void **)&p)))
    {
        p->Enable(enabled);
        p->Release();
    }
    CoUninitialize();
}
void SetWallpaperColor(int color)
{
    CoInitialize(NULL);
    IDesktopWallpaper *p;
    if (SUCCEEDED(CoCreateInstance(__uuidof(DesktopWallpaper), 0, CLSCTX_LOCAL_SERVER, __uuidof(IDesktopWallpaper), (void **)&p)))
    {
        p->SetBackgroundColor((COLORREF)color);
        p->Release();
    }
    CoUninitialize();
}
void SetStartOnSystemStartup(bool fAutoStart, std::string exePath)
{

    WCHAR startMenuPath[MAX_PATH];
    HRESULT result = SHGetFolderPathW(NULL, CSIDL_PROGRAMS, NULL, 0, startMenuPath);
    std::string exe = exePath.substr(exePath.find_last_of("\\") + 1);
    std::wstring wExe = Encoding::Utf8ToWide(exe);
    wExe.replace(wExe.find(L".exe"), sizeof(L".exe") - 1, L".lnk");

    std::wstring wStartMenuPath = std::wstring(startMenuPath);
    wStartMenuPath.append(L"\\Startup\\");
    wStartMenuPath.append(wExe);
    if (!fAutoStart)
    {
        std::string startMenupath = Encoding::WideToUtf8(wStartMenuPath.c_str());
        std::remove(startMenupath.c_str());
        return;
    }

    CoInitialize(NULL);

    if (SUCCEEDED(result))
    {
        IShellLink *psl = NULL;
        HRESULT hres = CoCreateInstance(CLSID_ShellLink, NULL, CLSCTX_INPROC_SERVER, IID_IShellLink, reinterpret_cast<void **>(&psl));

        if (SUCCEEDED(hres))
        {
            TCHAR pszExePath[MAX_PATH];
            MultiByteToWideChar(CP_ACP, 0, exePath.c_str(), -1, pszExePath, MAX_PATH);
            psl->SetPath(pszExePath);
            PathRemoveFileSpec(pszExePath);
            psl->SetWorkingDirectory(pszExePath);
            psl->SetShowCmd(SW_SHOWMINNOACTIVE);
            IPersistFile *ppf = NULL;
            hres = psl->QueryInterface(IID_IPersistFile, reinterpret_cast<void **>(&ppf));
            if (SUCCEEDED(hres))
            {
                hres = ppf->Save(wStartMenuPath.c_str(), TRUE);
                ppf->Release();
            }
            psl->Release();
        }
    }
    CoUninitialize();
}
int LinkToPath(LPCTSTR path, LPTSTR lpszPath, int iPathBufferSize)
{
    // if (::CoInitializeEx(0, COINIT_MULTITHREADED) != S_OK)
    // {
    //     std::cout << "CoInitializeEx error" << std::endl;
    //     return 1;
    // }

    HRESULT rc;

    IShellLink *iShellLink;
    rc = CoCreateInstance(
        CLSID_ShellLink,
        NULL,
        CLSCTX_INPROC_SERVER,
        IID_IShellLink,
        (LPVOID *)&iShellLink);

    if (!SUCCEEDED(rc))
    {
        std::cout << "CoCreateInstance error" << std::endl;
        return 0;
    }

    IPersistFile *iPersistFile;

    rc = iShellLink->QueryInterface(IID_IPersistFile, (LPVOID *)&iPersistFile);

    if (!SUCCEEDED(rc))
    {
        std::cout << "QueryInterface(IID_IPersistFile) error" << std::endl;
        return 0;
    }
    // Load the shortcut.
    rc = iPersistFile->Load(path, STGM_READ);
    if (!SUCCEEDED(rc))
    {
        std::cout << "iPersistFile->Load() error" << std::endl;
        return 0;
    }
    rc = iShellLink->Resolve((HWND)0, 0);

    if (!SUCCEEDED(rc))
    {
        std::cout << "..." << std::endl;
        return 0;
    }
    rc = iShellLink->GetPath(
        lpszPath,
        iPathBufferSize,
        0,
        SLGP_SHORTPATH);

    iPersistFile->Release();
    iShellLink->Release();
    // ::CoUninitialize();
    return 1;
}

static float CalculateCPULoad(unsigned long long idleTicks, unsigned long long totalTicks)
{
    static unsigned long long _previousTotalTicks = 0;
    static unsigned long long _previousIdleTicks = 0;

    unsigned long long totalTicksSinceLastTime = totalTicks - _previousTotalTicks;
    unsigned long long idleTicksSinceLastTime = idleTicks - _previousIdleTicks;

    float ret = 1.0f - ((totalTicksSinceLastTime > 0) ? ((float)idleTicksSinceLastTime) / totalTicksSinceLastTime : 0);

    _previousTotalTicks = totalTicks;
    _previousIdleTicks = idleTicks;
    return ret;
}

static unsigned long long FileTimeToInt64(const FILETIME &ft) { return (((unsigned long long)(ft.dwHighDateTime)) << 32) | ((unsigned long long)ft.dwLowDateTime); }

// Returns 1.0f for "CPU fully pinned", 0.0f for "CPU idle", or somewhere in between
// You'll need to call this at regular intervals, since it measures the load between
// the previous call and the current one.  Returns -1.0 on error.
float GetCPULoad()
{
    FILETIME idleTime, kernelTime, userTime;
    return GetSystemTimes(&idleTime, &kernelTime, &userTime) ? CalculateCPULoad(FileTimeToInt64(idleTime), FileTimeToInt64(kernelTime) + FileTimeToInt64(userTime)) : -1.0f;
}

//! VIRTUAL DESKTOP
void SetTransparent(HWND target_window, bool type)
{
    DWORD exstyle;
    typedef BOOL(WINAPI * MySetLayeredWindowAttributesType)(HWND, COLORREF, BYTE, DWORD);
    static MySetLayeredWindowAttributesType MySetLayeredWindowAttributes = (MySetLayeredWindowAttributesType)
        GetProcAddress(GetModuleHandle(L"user32"), "SetLayeredWindowAttributes");
    exstyle = GetWindowLong(target_window, GWL_EXSTYLE);
    if (!MySetLayeredWindowAttributes || !exstyle)
        return;
    if (!type)
    {
        SetWindowLong(target_window, GWL_EXSTYLE, exstyle & ~WS_EX_LAYERED);
        // InvalidateRect(target_window, NULL, TRUE);
    }
    else
    {
        SetWindowLong(target_window, GWL_EXSTYLE, exstyle | WS_EX_LAYERED);
        MySetLayeredWindowAttributes(target_window, 0, 0, LWA_ALPHA);
    }
}
void ToggleTaskbar(bool visible)
{
    APPBARDATA abd = {sizeof abd};
    abd.lParam = visible ? ABS_ALWAYSONTOP : ABS_AUTOHIDE;
    SHAppBarMessage(ABM_SETSTATE, &abd);
    // SHAppBarMessage(ABM_WINDOWPOSCHANGED, &abd);
    HWND mainHwnd = FindWindow(L"Shell_traywnd", L"");
    SetTransparent(mainHwnd, !visible);
    // ShowWindow(mainHwnd, visible ? SW_SHOWNA : SW_HIDE);
    // SHAppBarMessage(ABM_WINDOWPOSCHANGED, &abd);

    HWND hwndNext = nullptr;
    HWND hwnd = nullptr;
    do
    {
        hwnd = FindWindowEx(NULL, hwndNext, L"Shell_SecondaryTrayWnd", L"");
        if (hwnd)
        {
            // ShowWindow(hwnd, visible ? SW_SHOWNA : SW_HIDE);
            SetTransparent(hwnd, !visible);
        }
        hwndNext = hwnd;
    } while (hwnd != nullptr);
    SHAppBarMessage(ABM_WINDOWPOSCHANGED, &abd);
}
void SetHwndSkipTaskbar(HWND hWnd, bool skip)
{
    ITaskbarList3 *taskbar_ = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_TaskbarList, NULL, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&taskbar_));
    if (SUCCEEDED(hr))
    {
        taskbar_->HrInit();
        if (!skip)
        {
            taskbar_->AddTab(hWnd);
        }
        else
        {
            taskbar_->DeleteTab(hWnd);
        }
        taskbar_->Release();
    }
}
//! Hooks
LRESULT CALLBACK
HandleMouseHook(int nCode, WPARAM wParam, LPARAM lParam)
{
    if (nCode != HC_ACTION) // Nothing to do :(
        return CallNextHookEx(NULL, nCode, wParam, lParam);

    MSLLHOOKSTRUCT *info = reinterpret_cast<MSLLHOOKSTRUCT *>(lParam);
    enum
    {
        BTN_LEFT,
        BTN_RIGHT,
        BTN_MIDDLE,
        BTN_SWUP,
        BTN_SWDOWN,
        BTN_XBUTTON1,
        BTN_XBUTTON2,
        BTN_NONE
    } button = BTN_NONE;

    char const *up_down[] = {"up", "down"};
    bool down = false;

    switch (wParam)
    {

    case WM_LBUTTONDOWN:
        down = true;
    case WM_LBUTTONUP:
        button = BTN_LEFT;
        break;

    case WM_RBUTTONDOWN:
        down = true;
    case WM_RBUTTONUP:
        button = BTN_RIGHT;
        break;

    case WM_MBUTTONDOWN:
        down = true;
    case WM_MBUTTONUP:
        button = BTN_MIDDLE;
        break;

    case WM_XBUTTONDOWN:
        down = true;
    case WM_XBUTTONUP:
        button = BTN_XBUTTON1;
        break;

    case WM_MOUSEWHEEL:
        // the hi order word might be negative, but WORD is unsigned, so
        // we need some signed type of an appropriate size:
        down = static_cast<std::make_signed_t<WORD>>(HIWORD(info->mouseData)) < 0;
        if (!down)
            button = BTN_SWUP;
        else
            button = BTN_SWDOWN;
        break;
    }

    if (button != BTN_NONE)
    {
        if (button == BTN_XBUTTON1)
        {
            if (HIWORD(info->mouseData) == 2)
                button = BTN_XBUTTON2;
        }
        int bID = (int)button;
        if (bID < 7 && (mouseWatchButtons[bID] == 1 || mouseControlButtons[bID] == 1))
        {
            flutter::EncodableMap args = flutter::EncodableMap();
            args[flutter::EncodableValue("hookID")] = flutter::EncodableValue((int)((DWORD_PTR)g_MouseHook)); // DWORD_PTR
            args[flutter::EncodableValue("hookType")] = flutter::EncodableValue(MOUSEHOOK);
            args[flutter::EncodableValue("state")] = flutter::EncodableValue(down);
            args[flutter::EncodableValue("button")] = flutter::EncodableValue(bID);
            if (mouseWatchButtons[bID] == 1)
            {
                args[flutter::EncodableValue("type")] = flutter::EncodableValue("watch");
            }
            if (mouseControlButtons[bID] == 1)
            {
                args[flutter::EncodableValue("type")] = flutter::EncodableValue("control");
                channel->InvokeMethod("onEvent", std::make_unique<flutter::EncodableValue>(args));
                return -1;
            }
            channel->InvokeMethod("onEvent", std::make_unique<flutter::EncodableValue>(args));
        }
    }
    // send output
    return CallNextHookEx(NULL, nCode, wParam, lParam);
}

void CALLBACK HandleWinEvent(HWINEVENTHOOK hook, DWORD event, HWND hWnd, LONG idObject, LONG idChild, DWORD dwEventThread, DWORD dwmsEventTime)
{
    flutter::EncodableMap args = flutter::EncodableMap();

    args[flutter::EncodableValue("hookID")] = flutter::EncodableValue((int)((DWORD_PTR)g_EventHook)); // DWORD_PTR
    args[flutter::EncodableValue("hookType")] = flutter::EncodableValue(EVENTHOOK);
    args[flutter::EncodableValue("event")] = flutter::EncodableValue((int)event);
    args[flutter::EncodableValue("hWnd")] = flutter::EncodableValue((int)((DWORD_PTR)hWnd));
    args[flutter::EncodableValue("idObject")] = flutter::EncodableValue(idObject);
    args[flutter::EncodableValue("idChild")] = flutter::EncodableValue(idChild);
    args[flutter::EncodableValue("dwEventThread")] = flutter::EncodableValue((int)dwEventThread);
    args[flutter::EncodableValue("dwmsEventTime")] = flutter::EncodableValue((int)dwmsEventTime);
    channel->InvokeMethod("onEvent", std::make_unique<flutter::EncodableValue>(args));
    // _EmitEvent(args, (int)((DWORD_PTR)hook), EVENTHOOK);
    // _EmitEvent(args, (int)((DWORD_PTR)g_EventHook), EVENTHOOK);
}

//! Mixed
std::wstring getHwndName(HWND hWnd)
{
    std::wstring processName;
    DWORD pid;
    GetWindowThreadProcessId(hWnd, &pid);

    HANDLE hSnapProcess = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, NULL);
    if (hSnapProcess != INVALID_HANDLE_VALUE)
    {
        PROCESSENTRY32 process;
        process.dwSize = sizeof(PROCESSENTRY32);
        Process32First(hSnapProcess, &process);
        do
        {
            if (process.th32ProcessID == pid)
            {
                processName = process.szExeFile;
                break;
            }

        } while (Process32Next(hSnapProcess, &process));
    }
    else
    {
        processName = L"-";
    }
    CloseHandle(hSnapProcess);
    return processName;
}

HWND FindTopWindow(DWORD pid)
{
    std::pair<HWND, DWORD> params = {0, pid};

    // Enumerate the windows using a lambda to process each window
    BOOL bResult = EnumWindows([](HWND hwnd, LPARAM lParam) -> BOOL
                               {
        auto pParams = (std::pair<HWND, DWORD>*)(lParam);

        DWORD processId;
        if (GetWindowThreadProcessId(hwnd, &processId) && processId == pParams->second)
        {
            // Stop enumerating
            SetLastError((DWORD)-1);
            pParams->first = hwnd;
            return FALSE;
        }

        // Continue enumerating
        return TRUE; },
                               (LPARAM)&params);

    if (!bResult && GetLastError() == -1 && params.first)
    {
        return params.first;
    }

    return 0;
}

namespace tabamewin32
{

    // static
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

    Tabamewin32Plugin::Tabamewin32Plugin(flutter::PluginRegistrarWindows *registrar) : registrar_(registrar)
    {
    }

    Tabamewin32Plugin::~Tabamewin32Plugin()
    {
        if (g_EventHook != NULL)
            UnhookWinEvent(g_EventHook);
        if (g_MouseHook != NULL)
            UnhookWindowsHookEx(g_MouseHook);
    }
    void Tabamewin32Plugin::HandleMethodCall(const flutter::MethodCall<flutter::EncodableValue> &method_call, std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
    {

        std::string method_name = method_call.method_name();
        //?

        //#h white
        //? Audio
        if (method_name.compare("enumAudioDevices") == 0)
        {
            const flutter::EncodableMap &args = std::get<flutter::EncodableMap>(*method_call.arguments());
            int deviceType = std::get<int>(args.at(flutter::EncodableValue("deviceType")));
            std::vector<DeviceProps> devices = EnumAudioDevices((EDataFlow)deviceType);
            // loop through devices and add them to a map
            flutter::EncodableMap map;
            for (const auto &device : devices)
            {
                flutter::EncodableMap deviceMap;
                deviceMap[flutter::EncodableValue("id")] = flutter::EncodableValue(Encoding::WideToUtf8(device.id));
                deviceMap[flutter::EncodableValue("name")] = flutter::EncodableValue(Encoding::WideToUtf8(device.name));
                deviceMap[flutter::EncodableValue("iconInfo")] = flutter::EncodableValue(Encoding::WideToUtf8(device.iconInfo));
                deviceMap[flutter::EncodableValue("isActive")] = flutter::EncodableValue(device.isActive);
                map[flutter::EncodableValue(Encoding::WideToUtf8(device.id))] = flutter::EncodableValue(deviceMap);
            }
            result->Success(flutter::EncodableValue(map));
        }
        else if (method_name.compare("getDefaultDevice") == 0)
        {
            const flutter::EncodableMap &args = std::get<flutter::EncodableMap>(*method_call.arguments());
            int deviceType = std::get<int>(args.at(flutter::EncodableValue("deviceType")));
            DeviceProps device = getDefaultDevice((EDataFlow)deviceType);

            flutter::EncodableMap deviceMap;
            deviceMap[flutter::EncodableValue("id")] = flutter::EncodableValue(Encoding::WideToUtf8(device.id));
            deviceMap[flutter::EncodableValue("name")] = flutter::EncodableValue(Encoding::WideToUtf8(device.name));
            deviceMap[flutter::EncodableValue("iconInfo")] = flutter::EncodableValue(Encoding::WideToUtf8(device.iconInfo));
            deviceMap[flutter::EncodableValue("isActive")] = flutter::EncodableValue(device.isActive);
            result->Success(flutter::EncodableValue(deviceMap));
        }
        else if (method_name.compare("setDefaultAudioDevice") == 0)
        {
            const flutter::EncodableMap &args = std::get<flutter::EncodableMap>(*method_call.arguments());
            std::string deviceID = std::get<std::string>(args.at(flutter::EncodableValue("deviceID")));
            std::wstring deviceIDW = Encoding::Utf8ToWide(deviceID);
            HRESULT nativeFuncResult = setDefaultDevice((LPWSTR)deviceIDW.c_str());
            result->Success(flutter::EncodableValue((int)nativeFuncResult));
        }
        else if (method_name.compare("getAudioVolume") == 0)
        {
            const flutter::EncodableMap &args = std::get<flutter::EncodableMap>(*method_call.arguments());
            int deviceType = std::get<int>(args.at(flutter::EncodableValue("deviceType")));
            float nativeFuncResult = getVolume((EDataFlow)deviceType);
            result->Success(flutter::EncodableValue((double)nativeFuncResult));
        }
        else if (method_name.compare("setAudioVolume") == 0)
        {
            const flutter::EncodableMap &args = std::get<flutter::EncodableMap>(*method_call.arguments());
            int deviceType = std::get<int>(args.at(flutter::EncodableValue("deviceType")));
            double volumeLevel = std::get<double>(args.at(flutter::EncodableValue("volumeLevel")));
            setVolume((float)volumeLevel, (EDataFlow)deviceType);
            result->Success(flutter::EncodableValue((int)1));
        }
        else if (method_name.compare("setMuteAudioDevice") == 0)
        {
            const flutter::EncodableMap &args = std::get<flutter::EncodableMap>(*method_call.arguments());
            int deviceType = std::get<int>(args.at(flutter::EncodableValue("deviceType")));
            bool state = std::get<bool>(args.at(flutter::EncodableValue("muteState")));
            setMuteAudioDevice(state, (EDataFlow)deviceType);
            result->Success(flutter::EncodableValue((int)1));
        }
        else if (method_name.compare("getMuteAudioDevice") == 0)
        {
            const flutter::EncodableMap &args = std::get<flutter::EncodableMap>(*method_call.arguments());
            int deviceType = std::get<int>(args.at(flutter::EncodableValue("deviceType")));
            bool muteState = getMuteAudioDevice((EDataFlow)deviceType);
            result->Success(flutter::EncodableValue(muteState));
        }
        else if (method_name.compare("switchDefaultDevice") == 0)
        {
            const flutter::EncodableMap &args = std::get<flutter::EncodableMap>(*method_call.arguments());
            int deviceType = std::get<int>(args.at(flutter::EncodableValue("deviceType")));
            bool nativeFuncResult = switchDefaultDevice((EDataFlow)deviceType);
            result->Success(flutter::EncodableValue(nativeFuncResult));
        }
        //? AudioMixer
        else if (method_name.compare("enumAudioMixer") == 0)
        {
            std::vector<ProcessVolume> devices = GetProcessVolumes();
            // loop through devices and add them to a map
            flutter::EncodableMap map;
            for (const auto &device : devices)
            {
                flutter::EncodableMap deviceMap;
                deviceMap[flutter::EncodableValue("processId")] = flutter::EncodableValue(device.processId);
                deviceMap[flutter::EncodableValue("processPath")] = flutter::EncodableValue(device.processPath);
                deviceMap[flutter::EncodableValue("maxVolume")] = flutter::EncodableValue(device.maxVolume);
                deviceMap[flutter::EncodableValue("peakVolume")] = flutter::EncodableValue(device.peakVolume);
                map[flutter::EncodableValue(device.processId)] = flutter::EncodableValue(deviceMap);
            }
            result->Success(flutter::EncodableValue(map));
        }
        else if (method_name.compare("setAudioMixerVolume") == 0)
        {

            const flutter::EncodableMap &args = std::get<flutter::EncodableMap>(*method_call.arguments());
            int processID = std::get<int>(args.at(flutter::EncodableValue("processID")));
            double volumeLevel = std::get<double>(args.at(flutter::EncodableValue("volumeLevel")));
            std::vector<ProcessVolume> devices = GetProcessVolumes(processID, (float)volumeLevel);

            flutter::EncodableMap map;
            for (const auto &device : devices)
            {
                flutter::EncodableMap deviceMap;
                deviceMap[flutter::EncodableValue("processId")] = flutter::EncodableValue(device.processId);
                deviceMap[flutter::EncodableValue("processPath")] = flutter::EncodableValue(device.processPath);
                deviceMap[flutter::EncodableValue("maxVolume")] = flutter::EncodableValue(device.maxVolume);
                deviceMap[flutter::EncodableValue("peakVolume")] = flutter::EncodableValue(device.peakVolume);
                map[flutter::EncodableValue(device.processId)] = flutter::EncodableValue(deviceMap);
            }
            result->Success(flutter::EncodableValue(map));
        }
        //#e
        //? Utilities
        else if (method_name.compare("iconToBytes") == 0)
        {
            const flutter::EncodableMap &args = std::get<flutter::EncodableMap>(*method_call.arguments());
            std::string iconLocation = std::get<std::string>(args.at(flutter::EncodableValue("iconLocation")));
            int iconID = std::get<int>(args.at(flutter::EncodableValue("iconID")));
            std::wstring iconLocationW = Encoding::Utf8ToWide(iconLocation);
            HICON icon = getIconFromFile((LPWSTR)iconLocationW.c_str(), iconID);

            std::vector<CHAR> buff;
            bool resultIcon = GetIconData(icon, 32, buff);
            if (!resultIcon)
            {
                buff.clear();
                resultIcon = GetIconData(icon, 24, buff);
            }
            std::vector<uint8_t> buff_uint8;
            for (auto i : buff)
            {
                buff_uint8.push_back(i);
            }
            result->Success(flutter::EncodableValue(buff_uint8));
        }
        else if (method_name.compare("getWindowIcon") == 0)
        {
            const flutter::EncodableMap &args = std::get<flutter::EncodableMap>(*method_call.arguments());
            int hWND = std::get<int>(args.at(flutter::EncodableValue("hWnd")));

            LRESULT iconResult = SendMessage((HWND)((LONG_PTR)hWND), WM_GETICON, 2, 0); // ICON_SMALL2 - User Made Apps
            if (iconResult == 0)
                iconResult = GetClassLongPtr((HWND)((LONG_PTR)hWND), -14); // GCLP_HICON - Microsoft Win Apps
            if (iconResult != 0)
            {

                HICON icon = (HICON)iconResult;
                std::vector<CHAR> buff;
                bool resultIcon = GetIconData(icon, 32, buff);
                if (!resultIcon)
                {
                    buff.clear();
                    resultIcon = GetIconData(icon, 24, buff);
                }
                if (resultIcon)
                {
                    std::vector<uint8_t> buff_uint8;
                    for (auto i : buff)
                    {
                        buff_uint8.push_back(i);
                    }
                    result->Success(flutter::EncodableValue(buff_uint8));
                }
                else
                {
                    std::vector<uint8_t> iconBytes;
                    iconBytes.push_back(204);
                    iconBytes.push_back(204);
                    iconBytes.push_back(204);
                    result->Success(flutter::EncodableValue(iconBytes));
                }
            }
            else
            {

                std::vector<uint8_t> iconBytes;
                iconBytes.push_back(204);
                iconBytes.push_back(204);
                iconBytes.push_back(204);
                result->Success(flutter::EncodableValue(iconBytes));
            }
        }
        else if (method_name.compare("getIconPng") == 0)
        {
            const flutter::EncodableMap &args = std::get<flutter::EncodableMap>(*method_call.arguments());
            int hIcon = std::get<int>(args.at(flutter::EncodableValue("hIcon")));
            std::vector<CHAR> buff;
            bool resultIcon = GetIconData((HICON)((LONG_PTR)hIcon), 32, buff);
            if (!resultIcon)
            {
                buff.clear();
                resultIcon = GetIconData((HICON)((LONG_PTR)hIcon), 24, buff);
            }
            if (resultIcon)
            {
                std::vector<uint8_t> buff_uint8;
                for (auto i : buff)
                {
                    buff_uint8.push_back(i);
                }
                result->Success(flutter::EncodableValue(buff_uint8));
            }
            else
            {
                std::vector<uint8_t> iconBytes;
                iconBytes.push_back(204);
                iconBytes.push_back(204);
                iconBytes.push_back(204);
                result->Success(flutter::EncodableValue(iconBytes));
            }
        }
        else if (method_name.compare("getHwndName") == 0)
        {
            const flutter::EncodableMap &args = std::get<flutter::EncodableMap>(*method_call.arguments());
            int hWND = std::get<int>(args.at(flutter::EncodableValue("hWnd")));
            std::wstring name = getHwndName((HWND)((LONG_PTR)hWND));
            result->Success(flutter::EncodableValue(Encoding::WideToUtf8(name)));
        }
        else if (method_name.compare("findTopWindow") == 0)
        {
            const flutter::EncodableMap &args = std::get<flutter::EncodableMap>(*method_call.arguments());
            int processID = std::get<int>(args.at(flutter::EncodableValue("processID")));
            HWND name = FindTopWindow((DWORD)processID);
            result->Success(flutter::EncodableValue((LONG_PTR)name));
        }

        else if (method_name.compare("enumTrayIcons") == 0)
        {
            std::vector<TrayIconData> trayIcons = EnumSystemTray();
            // loop through devices and add them to a map
            flutter::EncodableMap map;
            for (const auto &trayIcon : trayIcons)
            {
                flutter::EncodableMap trayIconMap;
                trayIconMap[flutter::EncodableValue("toolTip")] = flutter::EncodableValue(Encoding::WideToUtf8(trayIcon.toolTip));
                // std::cout << Encoding::WideToUtf8(trayIcon.toolTip) << endl;
                trayIconMap[flutter::EncodableValue("isVisible")] = flutter::EncodableValue((int)trayIcon.isVisible);
                trayIconMap[flutter::EncodableValue("processID")] = flutter::EncodableValue((int)trayIcon.processID);
                trayIconMap[flutter::EncodableValue("hWnd")] = flutter::EncodableValue((int)((LONG_PTR)trayIcon.data.hwnd));
                trayIconMap[flutter::EncodableValue("uID")] = flutter::EncodableValue((int)trayIcon.data.uID);
                trayIconMap[flutter::EncodableValue("uCallbackMessage")] = flutter::EncodableValue((int)trayIcon.data.uCallbackMessage);
                trayIconMap[flutter::EncodableValue("hIcon")] = flutter::EncodableValue((int)((LONG_PTR)trayIcon.data.hIcon));
                map[flutter::EncodableValue(trayIcon.processID)] = flutter::EncodableValue(trayIconMap);
            }
            result->Success(flutter::EncodableValue(map));
        }
        else if (method_name.compare("toggleTaskbar") == 0)
        {
            const flutter::EncodableMap &args = std::get<flutter::EncodableMap>(*method_call.arguments());
            bool state = std::get<bool>(args.at(flutter::EncodableValue("state")));
            ToggleTaskbar(state);
            result->Success(flutter::EncodableValue(true));
        }
        //#h white
        //? WIN HOOKS
        else if (method_name.compare("installHooks") == 0)
        {

            const flutter::EncodableMap &getArgs = std::get<flutter::EncodableMap>(*method_call.arguments());
            int eventMin = std::get<int>(getArgs.at(flutter::EncodableValue("eventMin")));
            int eventMax = std::get<int>(getArgs.at(flutter::EncodableValue("eventMax")));
            int eventFilters = std::get<int>(getArgs.at(flutter::EncodableValue("eventFilters")));

            g_MouseHook = SetWindowsHookEx(WH_MOUSE_LL, HandleMouseHook, GetModuleHandle(NULL), 0);

            if (eventMin > 0)
                g_EventHook = SetWinEventHook(eventMin, eventMax, NULL, HandleWinEvent, 0, 0, eventFilters);
            else
                g_EventHook = NULL;

            flutter::EncodableMap args = flutter::EncodableMap();
            args[flutter::EncodableValue("mouseHookID")] = flutter::EncodableValue((int)((LONG_PTR)g_MouseHook)); // DWORD_PTR
            args[flutter::EncodableValue("eventHookID")] = flutter::EncodableValue((int)((LONG_PTR)g_EventHook)); // DWORD_PTR
            result->Success(flutter::EncodableValue(args));
        }
        else if (method_name.compare("uninstallHooks") == 0)
        {
            if (g_EventHook != NULL)
                UnhookWinEvent(g_EventHook);
            if (g_MouseHook != NULL)
                UnhookWindowsHookEx(g_MouseHook);
            g_EventHook = NULL;
            g_MouseHook = NULL;
            result->Success(flutter::EncodableValue("Hooks uninstalled"));
        }
        else if (method_name.compare("cleanHooks") == 0)
        {
            for (int i = 0; i < 7; i++)
            {
                mouseWatchButtons[i] = 0;
                mouseControlButtons[i] = 0;
            }
            result->Success(flutter::EncodableValue(true));
        }
        else if (method_name.compare("uninstallSpecificHookID") == 0)
        {
            const flutter::EncodableMap &args = std::get<flutter::EncodableMap>(*method_call.arguments());
            int hookID = std::get<int>(args.at(flutter::EncodableValue("hookID")));
            int hookType = std::get<int>(args.at(flutter::EncodableValue("hookType")));
            if (hookType == 1)
            {
                UnhookWinEvent((HWINEVENTHOOK)((DWORD_PTR)hookID));
                result->Success(flutter::EncodableValue("Hook WinEvent Uninstalled."));
            }
            else if (hookType == 2)
            {
                UnhookWindowsHookEx((HHOOK)((DWORD_PTR)hookID));
                result->Success(flutter::EncodableValue("Hook Mouse Uninstalled."));
            }
        }
        else if (method_name.compare("manageMouseHook") == 0)
        {
            const flutter::EncodableMap &args = std::get<flutter::EncodableMap>(*method_call.arguments());
            int button = std::get<int>(args.at(flutter::EncodableValue("button")));
            std::string method = std::get<std::string>(args.at(flutter::EncodableValue("method")));
            std::string mouseEvent = std::get<std::string>(args.at(flutter::EncodableValue("mouseEvent")));

            if (mouseEvent == "hold")
                mouseControlButtons[button] = method == "add" ? 1 : 0;
            else
                mouseWatchButtons[button] = method == "add" ? 1 : 0;
            result->Success(flutter::EncodableValue(true));
        }
        //#e
        //? ACRYLIC
        else if (method_name.compare("setTransparent") == 0)
        {
            // if (!alreadySetTransparent)
            // {
            // alreadySetTransparent = true;
            setTransparent(::GetAncestor(registrar_->GetView()->GetNativeWindow(), GA_ROOT));
            //}
            result->Success();
        }
        else if (method_name.compare("getMainHandle") == 0)
        {
            HWND handle = ::GetAncestor(registrar_->GetView()->GetNativeWindow(), GA_ROOT);
            result->Success(flutter::EncodableValue((int)((LONG_PTR)handle)));
        }

        //? Virtual Desktops
        else if (method_name.compare("moveWindowToDesktop") == 0)
        {
            const flutter::EncodableMap &getArgs = std::get<flutter::EncodableMap>(*method_call.arguments());
            int iHwnd = std::get<int>(getArgs.at(flutter::EncodableValue("hWnd")));
            int eventMin = std::get<int>(getArgs.at(flutter::EncodableValue("direction")));

            if (CreateScratchDesktop())
            {
                if (iHwnd == 0)
                {
                    if (eventMin > 0)
                        NextDesktop();
                    else
                        PrevDesktop();
                }
                else
                {
                    HWND hWnd = (HWND)((LONG_PTR)iHwnd);
                    if (eventMin > 0)
                    {
                        NextDesktop();
                        MoveToCurrent(hWnd);
                    }
                    else
                    {
                        PrevDesktop();
                        MoveToCurrent(hWnd);
                    }
                    DestoryScratchDesktop();
                }
                result->Success(flutter::EncodableValue(true));
            }
            else
                result->Success(flutter::EncodableValue(false));
        }
        else if (method_name.compare("setSkipTaskbar") == 0)
        {

            const flutter::EncodableMap &getArgs = std::get<flutter::EncodableMap>(*method_call.arguments());
            int iHwnd = std::get<int>(getArgs.at(flutter::EncodableValue("hWnd")));
            bool skip = std::get<bool>(getArgs.at(flutter::EncodableValue("skip")));

            HWND hWnd = (HWND)((LONG_PTR)iHwnd);
            SetHwndSkipTaskbar(hWnd, skip);
            result->Success(flutter::EncodableValue(true));
        }
        else if (method_name.compare("convertLinkToPath") == 0)
        {
            const flutter::EncodableMap &args = std::get<flutter::EncodableMap>(*method_call.arguments());
            std::string deviceID = std::get<std::string>(args.at(flutter::EncodableValue("lnkPath")));
            std::wstring linkFile = Encoding::Utf8ToWide(deviceID);

            TCHAR achPath[MAX_PATH] = {0};
            HRESULT hres;
            hres = LinkToPath(linkFile.c_str(), achPath, _countof(achPath));
            if (hres)
            {
                result->Success(flutter::EncodableValue(Encoding::WideToUtf8(achPath)));
            }
            else
            {
                cout << "ResolveIt Failed" << endl;
                result->Success(flutter::EncodableValue(""));
            }
        }
        else if (method_name.compare("setStartOnSystemStartup") == 0)
        {
            const flutter::EncodableMap &args = std::get<flutter::EncodableMap>(*method_call.arguments());
            std::string exePath = std::get<std::string>(args.at(flutter::EncodableValue("exePath")));
            bool enabled = std::get<bool>(args.at(flutter::EncodableValue("enabled")));

            SetStartOnSystemStartup(enabled, exePath);
            result->Success(flutter::EncodableValue(""));
        }
        else if (method_name.compare("getSystemUsage") == 0)
        {
            float cpuLoad = GetCPULoad();

            MEMORYSTATUSEX statex;
            statex.dwLength = sizeof(statex);
            GlobalMemoryStatusEx(&statex);
            int memoryLoad = statex.dwMemoryLoad;

            flutter::EncodableMap map;
            map.emplace(flutter::EncodableValue("cpuLoad"), flutter::EncodableValue(cpuLoad));
            map.emplace(flutter::EncodableValue("memoryLoad"), flutter::EncodableValue(memoryLoad));
            result->Success(flutter::EncodableValue(map));
        }
        else if (method_name.compare("toggleMonitorWallpaper") == 0)
        {

            const flutter::EncodableMap &args = std::get<flutter::EncodableMap>(*method_call.arguments());
            bool enabled = std::get<bool>(args.at(flutter::EncodableValue("enabled")));

            ToggleMonitorWallpaper(enabled);
            result->Success(flutter::EncodableValue(true));
        }
        else if (method_name.compare("setWallpaperColor") == 0)
        {

            const flutter::EncodableMap &args = std::get<flutter::EncodableMap>(*method_call.arguments());
            int color = std::get<int>(args.at(flutter::EncodableValue("color")));

            SetWallpaperColor(color);
            result->Success(flutter::EncodableValue(true));
        }

        else
        {
            result->NotImplemented();
        }
    }
    //#e
} // namespace tabamewin32
