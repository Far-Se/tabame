#ifndef TABAMEWIN32_HOTKEYS
#define TABAMEWIN32_HOTKEYS

#include <windows.h>
#include <ShellAPI.h>
#include <psapi.h>
#include <string>
#include <vector>
#include <sstream>
#include <regex>
#include <chrono>
#include <algorithm>

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include "include/encoding.h"

// ---------------------------------------------------------------------------
// Forward-declared globals defined in tabamewin32_plugin.cpp
// ---------------------------------------------------------------------------
extern std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel;

// ---------------------------------------------------------------------------
// Hotkey data model
// ---------------------------------------------------------------------------
class Hotkey
{
public:
    std::wstring modifisers = L"";
    std::wstring hotkey = L"";
    int keyVK = -1;
    bool activateWindowUnderCursor = false;
    bool listenToMovement = false;
    bool noopScreenBusy = false;
    std::string matchWindowBy = "";
    std::wstring matchWindowText = L"";
    std::string name = "";
    std::vector<std::string> prohibitedWindows = {};
    int regionX1 = 0;
    int regionX2 = 0;
    int regionY1 = 0;
    int regionY2 = 0;
    bool regionAsPercentage = false;
    bool regionOnScreen = true;
    int anchorType = 0;
};

// ---------------------------------------------------------------------------
// Hotkey hook callbacks (forward declarations)
// ---------------------------------------------------------------------------
LRESULT CALLBACK HandleKeyboardHook(int, WPARAM, LPARAM);
LRESULT CALLBACK HandleMouseHook(int, WPARAM, LPARAM);
VOID CALLBACK EventHook(HWINEVENTHOOK, DWORD, HWND, LONG, LONG, DWORD, DWORD);

// ---------------------------------------------------------------------------
// Global state
// ---------------------------------------------------------------------------
static std::vector<Hotkey> hotkeys;
static int activeHotKey = -1;
static bool hotkeyPressed = false;
static int hotkeyStartTimestamp = 0;
static int hotkeyStartMousePosX = 0;
static int hotkeyStartMousePosY = 0;
static bool hotkeyCorrectName = false;
static std::wstring hotkeyName;

// Views
static HWND foregroundWindow = nullptr;
static HWND movingWindow = nullptr;
static bool isViewsEnabled = false;
static int viewsState = 0;

// Trcktivity
static bool isTrcktivityEnabled = false;
static int trkTimestamp = 0;
static int trckMovementX = 0;
static int trckMovementY = 0;
static int kbdTime = 0;
static int kbdPressCount = 0;

// Mouse position tracking during hotkey drag
static int htMousePosX = 0;
static int htMousePosY = 0;

// Hook handles for this subsystem
HHOOK g_KeyboardHook = nullptr;
HHOOK g_MouseHook = nullptr;
HWINEVENTHOOK g_EventHook = nullptr;

enum mouseButtons
{
    BTN_LEFT,
    BTN_RIGHT,
    BTN_MIDDLE,
    BTN_SWUP,
    BTN_SWDOWN,
    BTN_XBUTTON1,
    BTN_XBUTTON2,
    BTN_NONE
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
namespace
{
    int GetTimestamp()
    {
        return static_cast<int>(
            std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::system_clock::now().time_since_epoch())
                .count());
    }

    void SetAsActiveHotkey(size_t i, HWND /*hwnd*/)
    {
        activeHotKey = static_cast<int>(i);
        hotkeyStartTimestamp = GetTimestamp();

        POINT pos;
        GetCursorPos(&pos);
        hotkeyStartMousePosX = pos.x;
        hotkeyStartMousePosY = pos.y;
        hotkeyPressed = true;
    }

    // Retrieve window info (title, exe name, or class) into |windowInfo|.
    void GetWindowInfoByType(HWND hwnd, const std::string &type, wchar_t *windowInfo, int bufSize)
    {
        if (type == "title")
        {
            GetWindowText(hwnd, windowInfo, bufSize);
        }
        else if (type == "exe")
        {
            DWORD ppID = 0;
            GetWindowThreadProcessId(hwnd, &ppID);
            HANDLE hProcess = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE, ppID);
            if (hProcess != nullptr)
            {
                wchar_t imgName[1024] = {};
                DWORD bufSz = MAX_PATH;
                if (QueryFullProcessImageName(hProcess, 0, imgName, &bufSz) != 0)
                {
                    GetModuleFileNameEx(hProcess, nullptr, windowInfo, MAX_PATH);
                    wchar_t *p = wcsrchr(windowInfo, L'\\');
                    if (p != nullptr)
                        wcscpy_s(windowInfo, bufSize, p + 1);
                }
                CloseHandle(hProcess);
            }
        }
        else if (type == "class")
        {
            GetClassName(hwnd, windowInfo, bufSize);
        }
    }

    HWND ResolveTargetWindow(const Hotkey &hk)
    {
        HWND hwnd = GetForegroundWindow();
        hwnd = GetAncestor(hwnd, GA_ROOT);
        if (hk.activateWindowUnderCursor)
        {
            POINT p;
            GetCursorPos(&p);
            hwnd = WindowFromPoint(p);
            hwnd = GetAncestor(hwnd, GA_ROOT);
        }
        return hwnd;
    }

    bool IsWindowsKey(DWORD vkCode)
    {
        return vkCode == VK_LWIN || vkCode == VK_RWIN;
    }

    bool IsModifierKey(DWORD vkCode)
    {
        switch (vkCode)
        {
        case VK_CONTROL:
        case VK_LCONTROL:
        case VK_RCONTROL:
        case VK_MENU:
        case VK_LMENU:
        case VK_RMENU:
        case VK_SHIFT:
        case VK_LSHIFT:
        case VK_RSHIFT:
        case VK_LWIN:
        case VK_RWIN:
            return true;
        default:
            return false;
        }
    }

    bool ActiveHotkeyUsesWindowsKey()
    {
        if (activeHotKey < 0 || activeHotKey >= static_cast<int>(hotkeys.size()))
            return false;

        return hotkeys[activeHotKey].hotkey.find(L"WIN+") != std::wstring::npos;
    }

    bool ShouldSuppressActiveHotkeyKeyDown(DWORD vkCode)
    {
        if (!hotkeyPressed || activeHotKey < 0 || activeHotKey >= static_cast<int>(hotkeys.size()))
            return false;

        const Hotkey &active = hotkeys[activeHotKey];
        return active.keyVK >= 0 && vkCode == static_cast<DWORD>(active.keyVK);
    }

    void NotifySystemWindowsHotkeyUsed()
    {
        constexpr WORD kSyntheticComboVk = VK_F24;
        INPUT inputs[2] = {};

        inputs[0].type = INPUT_KEYBOARD;
        inputs[0].ki.wVk = kSyntheticComboVk;

        inputs[1].type = INPUT_KEYBOARD;
        inputs[1].ki.wVk = kSyntheticComboVk;
        inputs[1].ki.dwFlags = KEYEVENTF_KEYUP;

        SendInput(2, inputs, sizeof(INPUT));
    }
} // anonymous namespace

// ---------------------------------------------------------------------------
// Check if the foreground/cursor window is on the prohibited list
// ---------------------------------------------------------------------------
static bool IsOnProhibitedWindow()
{
    HWND hwnd = ResolveTargetWindow(hotkeys[activeHotKey]);

    for (const auto &info : hotkeys[activeHotKey].prohibitedWindows)
    {
        std::vector<std::string> data;
        std::stringstream ss(info);
        std::string token;
        while (std::getline(ss, token, ':'))
            data.push_back(token);

        if (data.size() == 2)
        {
            wchar_t windowInfo[1024] = {};
            GetWindowInfoByType(hwnd, data[0], windowInfo, 1024);

            std::wstring ws(data[1].begin(), data[1].end());
            if (std::regex_search(windowInfo, std::wregex(ws, std::regex_constants::icase)))
                return true;
        }
    }
    return false;
}

// ---------------------------------------------------------------------------
// Check all registered hotkeys against the pressed key combination
// ---------------------------------------------------------------------------
static bool CheckForPressedHotKey(const std::wstring &pressedHotkey)
{
    bool foundOne = false;
    for (size_t i = 0, e = hotkeys.size(); i != e; ++i)
    {
        const Hotkey &hk = hotkeys[i];
        if (hk.hotkey != pressedHotkey)
            continue;

        HWND hwnd = ResolveTargetWindow(hk);

        // Match window filter
        if (hk.matchWindowBy.length() > 1)
        {
            wchar_t windowInfo[1024] = {};
            GetWindowInfoByType(hwnd, hk.matchWindowBy, windowInfo, 1024);

            bool matched = std::regex_search(windowInfo,
                                             std::wregex(hk.matchWindowText, std::regex_constants::icase));
            if (!matched)
                continue;

            if (hk.anchorType == 0)
            {
                hotkeyCorrectName = true;
                SetAsActiveHotkey(i, hwnd);
                return true;
            }
        }

        // Region / anchor check
        if (hk.anchorType > 0)
        {
            POINT lpPoint;
            GetCursorPos(&lpPoint);
            RECT lpRect;

            if (hk.regionOnScreen)
            {
                HWND desktop = GetDesktopWindow();
                GetWindowRect(desktop, &lpRect);
                while (lpPoint.x >= lpRect.right)
                    lpPoint.x -= lpRect.right;
                while (lpPoint.y >= lpRect.bottom)
                    lpPoint.y -= lpRect.bottom;
            }
            else
            {
                GetWindowRect(hwnd, &lpRect);
            }

            int yTop = lpPoint.y - lpRect.top;
            int yBottom = lpPoint.y - lpRect.bottom;
            int xLeft = lpPoint.x - lpRect.left;
            int xRight = lpPoint.x - lpRect.right;
            int width = lpRect.right - lpRect.left;
            int height = lpRect.bottom - lpRect.top;

            int x = 0, y = 0;
            switch (hk.anchorType)
            {
            case 1:
                x = xLeft;
                y = yTop;
                break;
            case 2:
                x = xRight;
                y = yTop;
                break;
            case 3:
                x = xLeft;
                y = yBottom;
                break;
            case 4:
                x = xRight;
                y = yBottom;
                break;
            }
            x = abs(x);
            y = abs(y);

            if (hk.regionAsPercentage && width > 0 && height > 0)
            {
                x = static_cast<int>((static_cast<double>(x) / width) * 100);
                y = static_cast<int>((static_cast<double>(y) / height) * 100);
            }

            if (x >= hk.regionX1 && x <= hk.regionX2 && y >= hk.regionY1 && y <= hk.regionY2)
            {
                hotkeyCorrectName = true;
                SetAsActiveHotkey(i, hwnd);
                return true;
            }
            continue;
        }

        SetAsActiveHotkey(i, hwnd);
        foundOne = true;
    }
    return foundOne;
}

// ---------------------------------------------------------------------------
// Flutter channel event helpers
// ---------------------------------------------------------------------------
static void HotKeyEvent(const std::string &name, const std::string &info, int vk = 0)
{
    flutter::EncodableMap args;
    args[flutter::EncodableValue("name")] = flutter::EncodableValue(hotkeyCorrectName ? name : "");
    args[flutter::EncodableValue("hotkey")] = flutter::EncodableValue(Encoding::WideToUtf8(hotkeys[activeHotKey].hotkey));
    args[flutter::EncodableValue("vk")] = flutter::EncodableValue(vk);
    args[flutter::EncodableValue("info")] = flutter::EncodableValue(info);
    args[flutter::EncodableValue("start")] = flutter::EncodableValue(hotkeyStartTimestamp);
    args[flutter::EncodableValue("end")] = flutter::EncodableValue(GetTimestamp());
    args[flutter::EncodableValue("sX")] = flutter::EncodableValue(hotkeyStartMousePosX);
    args[flutter::EncodableValue("sY")] = flutter::EncodableValue(hotkeyStartMousePosY);

    POINT endPos;
    GetCursorPos(&endPos);
    args[flutter::EncodableValue("eX")] = flutter::EncodableValue(static_cast<int>(endPos.x));
    args[flutter::EncodableValue("eY")] = flutter::EncodableValue(static_cast<int>(endPos.y));

    channel->InvokeMethod("HotKeyEvent", std::make_unique<flutter::EncodableValue>(args));
}

static void TrktivityEvent(const std::string &action, const std::string &info)
{
    flutter::EncodableMap args;
    args[flutter::EncodableValue("action")] = flutter::EncodableValue(action);
    args[flutter::EncodableValue("info")] = flutter::EncodableValue(info);
    channel->InvokeMethod("TrktivityEvent", std::make_unique<flutter::EncodableValue>(args));
}

static void ViewsEvent(const std::string &action, HWND hwnd)
{
    flutter::EncodableMap args;
    args[flutter::EncodableValue("hwnd")] = flutter::EncodableValue(
        hwnd != nullptr ? static_cast<int>(reinterpret_cast<DWORD_PTR>(hwnd)) : -1);
    args[flutter::EncodableValue("action")] = flutter::EncodableValue(action);
    channel->InvokeMethod("ViewsEvent", std::make_unique<flutter::EncodableValue>(args));
}

static void WinEvent(const std::string &action, HWND hwnd)
{
    flutter::EncodableMap args;
    args[flutter::EncodableValue("hwnd")] = flutter::EncodableValue(
        hwnd != nullptr ? static_cast<int>(reinterpret_cast<DWORD_PTR>(hwnd)) : -1);
    args[flutter::EncodableValue("action")] = flutter::EncodableValue(action);
    channel->InvokeMethod("WinEvent", std::make_unique<flutter::EncodableValue>(args));
}

// ---------------------------------------------------------------------------
// Check if screen-busy should suppress the hotkey
// ---------------------------------------------------------------------------
static bool ShouldSuppressForScreenBusy()
{
    QUERY_USER_NOTIFICATION_STATE state;
    SHQueryUserNotificationState(&state);
    return (state == QUNS_RUNNING_D3D_FULL_SCREEN || state == QUNS_BUSY);
}

static bool ShouldSuppressHotkey()
{
    if (hotkeys[activeHotKey].noopScreenBusy && ShouldSuppressForScreenBusy())
    {
        hotkeyPressed = false;
        hotkeyCorrectName = false;
        return true;
    }
    if (!hotkeys[activeHotKey].prohibitedWindows.empty() && IsOnProhibitedWindow())
    {
        hotkeyPressed = false;
        hotkeyCorrectName = false;
        return true;
    }
    return false;
}

// ---------------------------------------------------------------------------
// Keyboard hook callback
// ---------------------------------------------------------------------------
LRESULT CALLBACK HandleKeyboardHook(int nCode, WPARAM wParam, LPARAM lParam)
{
    if (nCode < 0)
        return CallNextHookEx(g_KeyboardHook, nCode, wParam, lParam);

    KBDLLHOOKSTRUCT keyInfo = *reinterpret_cast<KBDLLHOOKSTRUCT *>(lParam);

    if (keyInfo.flags & LLKHF_INJECTED)
        return CallNextHookEx(g_KeyboardHook, nCode, wParam, lParam);

    if ((wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN) && hotkeyPressed)
    {
        if (ShouldSuppressActiveHotkeyKeyDown(keyInfo.vkCode))
            return -1;
    }

    if ((wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN) && !hotkeyPressed)
    {
        std::wstring pressedHotkey;
        if (GetAsyncKeyState(VK_CONTROL) & 0x8000)
            pressedHotkey.append(L"CTRL+");
        if (GetAsyncKeyState(VK_MENU) & 0x8000)
            pressedHotkey.append(L"ALT+");
        if (GetAsyncKeyState(VK_SHIFT) & 0x8000)
            pressedHotkey.append(L"SHIFT+");
        if ((GetAsyncKeyState(VK_LWIN) & 0x8000) || (GetAsyncKeyState(VK_RWIN) & 0x8000))
            pressedHotkey.append(L"WIN+");

        wchar_t buffer[32] = {};
        UINT key = (keyInfo.scanCode << 16);
        GetKeyNameText(static_cast<LONG>(key), buffer, 32);

        std::wstring keyName(buffer);
        std::transform(keyName.begin(), keyName.end(), keyName.begin(),
                       [](wchar_t c) -> wchar_t
                       { return static_cast<wchar_t>(::toupper(c)); });

        pressedHotkey.append(keyName);

        if (CheckForPressedHotKey(pressedHotkey))
        {
            if (ShouldSuppressHotkey())
                return CallNextHookEx(nullptr, nCode, wParam, lParam);

            if (ActiveHotkeyUsesWindowsKey())
                NotifySystemWindowsHotkeyUsed();

            hotkeyName = pressedHotkey;
            HotKeyEvent(hotkeys[activeHotKey].name, "pressedKbd");
            return -1;
        }
        return CallNextHookEx(nullptr, nCode, wParam, lParam);
    }
    else if (wParam == WM_KEYUP || wParam == WM_SYSKEYUP)
    {
        // Trcktivity keyboard tracking
        if (isTrcktivityEnabled)
        {
            if (kbdTime == 0)
                kbdTime = keyInfo.time;
            if (static_cast<int>(keyInfo.time) - kbdTime < 10000)
            {
                kbdPressCount++;
            }
            else
            {
                TrktivityEvent("Keys", std::to_string(kbdPressCount));
                kbdTime = keyInfo.time;
                kbdPressCount = 0;
            }
        }

        // Release the active keyboard hotkey immediately in native code so
        // quick re-presses do not race against an async Dart round-trip.
        if (hotkeyPressed && ShouldSuppressActiveHotkeyKeyDown(keyInfo.vkCode))
        {
            HotKeyEvent(hotkeys[activeHotKey].name, "releaseKbd", keyInfo.vkCode);
            hotkeyPressed = false;
            hotkeyCorrectName = false;
            htMousePosX = 0;
            htMousePosY = 0;
            return -1;
        }
    }

    return CallNextHookEx(nullptr, nCode, wParam, lParam);
}

// ---------------------------------------------------------------------------
// Mouse hook callback (hotkey-aware)
// ---------------------------------------------------------------------------
LRESULT CALLBACK HandleMouseHook(int nCode, WPARAM wParam, LPARAM lParam)
{
    if (nCode != HC_ACTION)
        return CallNextHookEx(nullptr, nCode, wParam, lParam);

    MSLLHOOKSTRUCT *info = reinterpret_cast<MSLLHOOKSTRUCT *>(lParam);

    // ---- Mouse movement ----
    if (wParam == WM_MOUSEMOVE)
    {
        if (hotkeyPressed)
        {
            POINT lpPoint;
            GetCursorPos(&lpPoint);
            if (htMousePosX == 0)
                htMousePosX = lpPoint.x;
            if (htMousePosY == 0)
                htMousePosY = lpPoint.y;

            int diffX = lpPoint.x - htMousePosX;
            int diffY = lpPoint.y - htMousePosY;

            if (abs(diffX) > 10 || abs(diffY) > 10)
            {
                HotKeyEvent(hotkeys[activeHotKey].name, "moved");
                htMousePosX = 0;
                htMousePosY = 0;
            }
        }
        if (isTrcktivityEnabled)
        {
            if (trckMovementX == 0)
                trckMovementX = info->pt.x;
            if (trckMovementY == 0)
                trckMovementY = info->pt.y;
            if (trkTimestamp == 0)
                trkTimestamp = info->time;

            trckMovementX = info->pt.x;
            trckMovementY = info->pt.y;
            int timeDiff = info->time - trkTimestamp;
            if (timeDiff > 3000)
            {
                trkTimestamp = info->time;
                TrktivityEvent("Movement", "mouse");
            }
        }
    }

    // ---- Button classification ----
    bool down = false;
    mouseButtons button = BTN_NONE;
    switch (wParam)
    {
    case WM_LBUTTONDOWN:
        down = true;
        [[fallthrough]];
    case WM_LBUTTONUP:
        button = BTN_LEFT;
        break;
    case WM_RBUTTONDOWN:
        down = true;
        [[fallthrough]];
    case WM_RBUTTONUP:
        button = BTN_RIGHT;
        break;
    case WM_MBUTTONDOWN:
        down = true;
        [[fallthrough]];
    case WM_MBUTTONUP:
        button = BTN_MIDDLE;
        break;
    case WM_XBUTTONDOWN:
        down = true;
        [[fallthrough]];
    case WM_XBUTTONUP:
        button = BTN_XBUTTON1;
        break;
    case WM_MOUSEWHEEL:
        down = static_cast<std::make_signed_t<WORD>>(HIWORD(info->mouseData)) < 0;
        button = down ? BTN_SWDOWN : BTN_SWUP;
        break;
    }

    // ---- Views integration ----
    if (isViewsEnabled && button == BTN_RIGHT)
    {
        if (viewsState == 1 && !down)
        {
            viewsState = 2;
            ViewsEvent("open", nullptr);
        }
        else if (viewsState == 2 && down)
        {
            viewsState = 3;
            ViewsEvent("selecting", nullptr);
        }
        else if (viewsState == 3 && !down)
        {
            viewsState = 2;
            ViewsEvent("selected", nullptr);
        }
    }
    if (isViewsEnabled && (button == BTN_SWUP || button == BTN_SWDOWN) && viewsState >= 2)
    {
        ViewsEvent(button == BTN_SWUP ? "switchUp" : "switchDown", nullptr);
    }

    // ---- XButton hotkey handling ----
    if (button != BTN_NONE)
    {
        if (button == BTN_XBUTTON1 && HIWORD(info->mouseData) == 2)
            button = BTN_XBUTTON2;

        int bID = static_cast<int>(button);
        if (bID == 5 || bID == 6)
        {
            if (down)
            {
                bool result = (bID == 5)
                                  ? CheckForPressedHotKey(L"MOUSEBUTTON4")
                                  : CheckForPressedHotKey(L"MOUSEBUTTON5");
                if (result)
                {
                    if (ShouldSuppressHotkey())
                        return CallNextHookEx(nullptr, nCode, wParam, lParam);

                    HotKeyEvent(hotkeys[activeHotKey].name, "pressed");
                    return -1;
                }
            }
            else if (hotkeyPressed)
            {
                HotKeyEvent(hotkeys[activeHotKey].name, "released");
                hotkeyPressed = false;
                hotkeyCorrectName = false;
                return 1;
            }
        }
    }

    return CallNextHookEx(nullptr, nCode, wParam, lParam);
}

// ---------------------------------------------------------------------------
// Win event hook callback
// ---------------------------------------------------------------------------
VOID CALLBACK EventHook(HWINEVENTHOOK /*hWinEventHook*/, DWORD dwEvent, HWND hwnd,
                        LONG /*idObject*/, LONG /*idChild*/, DWORD /*dwEventThread*/, DWORD /*dwmsEventTime*/)
{
    if (dwEvent == EVENT_SYSTEM_FOREGROUND)
        WinEvent("foreground", hwnd);

    if (isTrcktivityEnabled && dwEvent == EVENT_OBJECT_NAMECHANGE)
    {
        if (reinterpret_cast<DWORD_PTR>(hwnd) == 0)
            return;
        if (GetForegroundWindow() == hwnd)
            WinEvent("namechange", hwnd);
    }

    if (isViewsEnabled)
    {
        if (dwEvent == EVENT_SYSTEM_MOVESIZESTART)
        {
            ViewsEvent("moveStart", hwnd);
            movingWindow = hwnd;
            viewsState = 1;
        }
        else if (dwEvent == EVENT_SYSTEM_MOVESIZEEND)
        {
            ViewsEvent("moveEnd", hwnd);
            movingWindow = nullptr;
            viewsState = 0;
        }
    }
}

#endif // TABAMEWIN32_HOTKEYS
