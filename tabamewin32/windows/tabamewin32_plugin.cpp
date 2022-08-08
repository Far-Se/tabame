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

#include <cctype>
#include <memory>
#include <sstream>
#include <regex>
#include <chrono>
#include <map>

// #include <shobjidl.h>
#include "virtdesktop.cpp"
#pragma warning(pop)
#pragma comment(lib, "ole32")
#include "audio.cpp"
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>, std::default_delete<flutter::MethodChannel<flutter::EncodableValue>>> channel = nullptr;

void CALLBACK mHandleWinEvent(HWINEVENTHOOK, DWORD, HWND, LONG, LONG, DWORD, DWORD);
LRESULT CALLBACK mHandleMouseHook(int, WPARAM, LPARAM);
HWINEVENTHOOK gEventHook = NULL;
HHOOK gMouseHook = NULL;
int mouseWatchButtons[7] = {0, 0, 0, 0, 0, 0, 0};
int mouseControlButtons[7] = {0, 0, 0, 0, 0, 0, 0};
#define EVENTHOOK 1
#define MOUSEHOOK 2

using namespace std;

///
LRESULT CALLBACK HandleKeyboardHook(int, WPARAM, LPARAM);
LRESULT CALLBACK HandleMouseHook(int, WPARAM, LPARAM);
VOID CALLBACK EventHook(HWINEVENTHOOK hWinEventHook, DWORD dwEvent, HWND hwnd, LONG idObject, LONG idChild, DWORD dwEventThread, DWORD dwmsEventTime);
HHOOK g_KeyboardHook;
HHOOK g_MouseHook;
HWINEVENTHOOK g_EventHook;
class Hotkey
{
public:
    wstring modifisers = L"";
    wstring hotkey = L"";
    bool activateWindowUnderCursor = false;
    bool listenToMovement = false;
    bool noopScreenBusy = false;
    string matchWindowBy = "";
    wstring matchWindowText = L"";
    string name = "";
    vector<string> prohibitedWindows = {};
    int regionX1 = 0;
    int regionX2 = 0;
    int regionY1 = 0;
    int regionY2 = 0;
    bool regionAsPercentage = false;
    bool regionOnScreen = true;
    int anchorType = 0;
};
/// HotKey
vector<Hotkey> hotkeys;
int activeHotKey = -1;
bool hotkeyPressed = false;
int hotkeyStartTimestamp = 0;
int hotkeyStartMousePosX = 0;
int hotkeyStartMousePosY = 0;
bool hotkeyCorrectName = false;
//
/// VIEWS
HWND foregroundWindow;
HWND movingWindow;
bool isViewsEnabled = false;
int viewsState = 0;
///
/// TRCKTIVITY
bool isTrcktivityEnabled = false;
// Mouse
int trkTimestamp = 0;
int trckMovementX = 0;
int trckMovementY = 0;
map<int, int> mouseDirectionData;
// Keyboard
int kbdTime = 0;
int kbdPressCount = 0;

int getTimestamp()
{
    return (int)std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::system_clock::now().time_since_epoch()).count();
}
void SetAsActiveHotkey(size_t i, HWND hwnd)
{
    activeHotKey = static_cast<int>(i);

    if (hotkeys[activeHotKey].activateWindowUnderCursor)
    {
        // SetForegroundWindow(hwnd);
        // SetFocus(hwnd);
        // SetActiveWindow(hwnd);
        // SendMessage(hwnd, WM_UPDATEUISTATE, 2 & 0x2, 0);
    }
    hotkeyStartTimestamp = (int)std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::system_clock::now().time_since_epoch()).count();
    POINT hotkeyEndMousePos;
    GetCursorPos(&hotkeyEndMousePos);
    hotkeyStartMousePosX = hotkeyEndMousePos.x;
    hotkeyStartMousePosY = hotkeyEndMousePos.y;
    hotkeyPressed = true;
}
bool checkForPressedHotKey(wstring pressedHotkey)
{
    bool foundOne = false;
    for (std::size_t i = 0, e = hotkeys.size(); i != e; ++i)
    {
        Hotkey hotkey = hotkeys[i];
        if (hotkey.hotkey == pressedHotkey)
        {
            HWND hwnd = GetForegroundWindow();
            hwnd = GetAncestor(hwnd, GA_ROOT);
            if (hotkey.activateWindowUnderCursor)
            {
                POINT p;
                GetCursorPos(&p);
                hwnd = WindowFromPoint(p);
                hwnd = GetAncestor(hwnd, GA_ROOT);
            }
            if (hotkey.matchWindowBy.length() > 1)
            {
                wchar_t windowInfo[1024] = {};
                if (hotkey.matchWindowBy == "title")
                {
                    GetWindowText(hwnd, windowInfo, 1024);
                }
                if (hotkey.matchWindowBy == "exe")
                {
                    DWORD ppID;
                    GetWindowThreadProcessId(hwnd, &ppID);

                    HANDLE hProcess = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE, ppID);
                    if (hProcess != 0)
                    {
                        wchar_t imgName[1024] = {};
                        DWORD bufSize = MAX_PATH;
                        if (QueryFullProcessImageName(hProcess, 0, imgName, &bufSize) != 0)
                        {
                            GetModuleFileNameEx(hProcess, 0, windowInfo, MAX_PATH);
                            // extract exe from windowInfo
                            wchar_t *p = wcsrchr(windowInfo, L'\\');
                            if (p != NULL)
                            {
                                wcscpy_s(windowInfo, p + 1);
                            }
                        }
                    }
                    CloseHandle(hProcess);
                }
                if (hotkey.matchWindowBy == "class")
                {
                    GetClassName(hwnd, windowInfo, 1024);
                }
                bool output = std::regex_search(windowInfo, std::wregex(hotkey.matchWindowText, std::regex_constants::icase));
                if (!output)
                {
                    continue;
                }
                else
                {
                    if (hotkey.anchorType == 0)
                    {
                        hotkeyCorrectName = true;
                        SetAsActiveHotkey(i, hwnd);
                        return true;
                    }
                }
            }
            if (hotkey.anchorType > 0)
            {
                POINT lpPoint;
                GetCursorPos(&lpPoint);
                RECT lpRect;
                if (hotkey.regionOnScreen)
                {
                    hwnd = GetDesktopWindow();
                    GetWindowRect(hwnd, &lpRect);
                    while (lpPoint.x >= lpRect.right)
                    {
                        lpPoint.x = lpPoint.x - lpRect.right;
                    }
                    while (lpPoint.y >= lpRect.bottom)
                    {
                        lpPoint.y = lpPoint.y - lpRect.right;
                    }
                }
                else
                {
                    GetWindowRect(hwnd, &lpRect);
                }

                int x = 0, y = 0;
                int yTop = lpPoint.y - lpRect.top;
                int yBottom = lpPoint.y - lpRect.bottom;
                int xLeft = lpPoint.x - lpRect.left;
                int xRight = lpPoint.x - lpRect.right;
                int width = lpRect.right - lpRect.left;
                int height = lpRect.bottom - lpRect.top;

                if (hotkey.anchorType == 1)
                {
                    x = xLeft;
                    y = yTop;
                }
                else if (hotkey.anchorType == 2)
                {
                    x = xRight;
                    y = yTop;
                }
                else if (hotkey.anchorType == 3)
                {
                    x = xLeft;
                    y = yBottom;
                }
                else if (hotkey.anchorType == 4)
                {
                    x = xRight;
                    y = yBottom;
                }
                x = abs(x);
                y = abs(y);
                int percentageX = static_cast<int>((static_cast<double>(x) / width) * 100);
                int percentageY = static_cast<int>((static_cast<double>(y) / height) * 100);
                if (hotkey.regionAsPercentage)
                {
                    x = percentageX;
                    y = percentageY;
                }

                if (x >= hotkey.regionX1 && x <= hotkey.regionX2 && y >= hotkey.regionY1 && y <= hotkey.regionY2)
                {
                    hotkeyCorrectName = true;
                    SetAsActiveHotkey(i, hwnd);
                    return true;
                }
                else
                {
                    continue;
                }
            }
            SetAsActiveHotkey(i, hwnd);
            foundOne = true;
        }
    }
    if (foundOne)
        return true;
    return false;
}

void HotKeyEvent(string name, string info)
{
    flutter::EncodableMap args = flutter::EncodableMap();
    args[flutter::EncodableValue("name")] = flutter::EncodableValue(hotkeyCorrectName ? name : "");
    args[flutter::EncodableValue("hotkey")] = flutter::EncodableValue(Encoding::WideToUtf8(hotkeys[activeHotKey].hotkey));
    args[flutter::EncodableValue("info")] = flutter::EncodableValue(info);
    args[flutter::EncodableValue("start")] = flutter::EncodableValue(hotkeyStartTimestamp);
    args[flutter::EncodableValue("end")] = flutter::EncodableValue((int)std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::system_clock::now().time_since_epoch()).count());
    args[flutter::EncodableValue("sX")] = flutter::EncodableValue(hotkeyStartMousePosX);
    args[flutter::EncodableValue("sY")] = flutter::EncodableValue(hotkeyStartMousePosY);
    POINT hotkeyEndMousePos;
    GetCursorPos(&hotkeyEndMousePos);
    args[flutter::EncodableValue("eX")] = flutter::EncodableValue(hotkeyEndMousePos.x);
    args[flutter::EncodableValue("eY")] = flutter::EncodableValue(hotkeyEndMousePos.y);
    channel->InvokeMethod("HotKeyEvent", std::make_unique<flutter::EncodableValue>(args));
}
void TrktivityEvent(string action, string info)
{
    flutter::EncodableMap args = flutter::EncodableMap();
    args[flutter::EncodableValue("action")] = flutter::EncodableValue(action);
    args[flutter::EncodableValue("info")] = flutter::EncodableValue(info);
    channel->InvokeMethod("TrktivityEvent", std::make_unique<flutter::EncodableValue>(args));
}
void ViewsEvent(string action, HWND hwnd)
{
    flutter::EncodableMap args = flutter::EncodableMap();
    if (hwnd != NULL)
    {
        args[flutter::EncodableValue("hwnd")] = flutter::EncodableValue((int)((DWORD_PTR)hwnd));
    }
    else
    {
        args[flutter::EncodableValue("hwnd")] = flutter::EncodableValue(-1);
    }
    args[flutter::EncodableValue("action")] = flutter::EncodableValue(action);
    channel->InvokeMethod("ViewsEvent", std::make_unique<flutter::EncodableValue>(args));
}
void WinEvent(string action, HWND hwnd)
{
    flutter::EncodableMap args = flutter::EncodableMap();
    if (hwnd != NULL)
    {
        args[flutter::EncodableValue("hwnd")] = flutter::EncodableValue((int)((DWORD_PTR)hwnd));
    }
    else
    {
        args[flutter::EncodableValue("hwnd")] = flutter::EncodableValue(-1);
    }
    args[flutter::EncodableValue("action")] = flutter::EncodableValue(action);
    channel->InvokeMethod("WinEvent", std::make_unique<flutter::EncodableValue>(args));
}
bool isOnProhibitedWindow()
{
    HWND hwnd = GetForegroundWindow();
    hwnd = GetAncestor(hwnd, GA_ROOT);
    if (hotkeys[activeHotKey].activateWindowUnderCursor)
    {
        POINT p;
        GetCursorPos(&p);
        hwnd = WindowFromPoint(p);
        hwnd = GetAncestor(hwnd, GA_ROOT);
    }
    for (auto &info : hotkeys[activeHotKey].prohibitedWindows)
    {
        std::vector<std::string> data;
        std::stringstream ss(info);
        std::string token;
        while (std::getline(ss, token, ':'))
        {
            data.push_back(token);
        }
        if (data.size() == 2)
        {

            wchar_t windowInfo[1024] = {};
            if (data[0] == "title")
            {
                GetWindowText(hwnd, windowInfo, 1024);
            }
            if (data[0] == "exe")
            {
                DWORD ppID;
                GetWindowThreadProcessId(hwnd, &ppID);

                HANDLE hProcess = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE, ppID);
                if (hProcess != 0)
                {
                    wchar_t imgName[1024] = {};
                    DWORD bufSize = MAX_PATH;
                    if (QueryFullProcessImageName(hProcess, 0, imgName, &bufSize) != 0)
                    {
                        GetModuleFileNameEx(hProcess, 0, windowInfo, MAX_PATH);
                        wchar_t *p = wcsrchr(windowInfo, L'\\');
                        if (p != NULL)
                        {
                            wcscpy_s(windowInfo, p + 1);
                        }
                    }
                }
                CloseHandle(hProcess);
            }
            if (data[0] == "class")
            {
                GetClassName(hwnd, windowInfo, 1024);
            }
            std::wstring ws(data[1].begin(), data[1].end());
            bool output = std::regex_search(windowInfo, std::wregex(ws, std::regex_constants::icase));
            if (output)
            {
                return true;
            }
        }
    }
    return false;
}
wstring hotkeyName;
LRESULT CALLBACK HandleKeyboardHook(int nCode, WPARAM wParam, LPARAM lParam)
{
    if (nCode < 0)
        return CallNextHookEx(g_KeyboardHook, nCode, wParam, lParam);
    KBDLLHOOKSTRUCT keyInfo = *((KBDLLHOOKSTRUCT *)lParam);
    if ((wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN) && !hotkeyPressed)
    {
        std::wstring pressedHotkey{};
        if (GetAsyncKeyState(VK_CONTROL) & 0x8000)
            pressedHotkey.append(L"CTRL+");
        if (GetAsyncKeyState(VK_MENU) & 0x8000)
            pressedHotkey.append(L"ALT+");
        if (GetAsyncKeyState(VK_SHIFT) & 0x8000)
            pressedHotkey.append(L"SHIFT+");
        if (GetAsyncKeyState(VK_LWIN) & 0x8000)
            pressedHotkey.append(L"WIN+");

        wchar_t buffer[32] = {};
        UINT key = (keyInfo.scanCode << 16);
        GetKeyNameText((LONG)key, buffer, 32);

        std::wstring keyName(buffer);
        std::transform(keyName.begin(), keyName.end(), keyName.begin(), [](int c) -> char
                       { return static_cast<char>(::toupper(c)); });

        pressedHotkey.append(keyName);
        bool result = checkForPressedHotKey(pressedHotkey);
        if (result)
        {
            // !check for Screen Busy
            if (hotkeys[activeHotKey].noopScreenBusy)
            {
                // create varialbe state
                QUERY_USER_NOTIFICATION_STATE state;
                SHQueryUserNotificationState(&state);
                if (state == QUNS_RUNNING_D3D_FULL_SCREEN || state == QUNS_BUSY)
                {
                    hotkeyPressed = false;
                    hotkeyCorrectName = false;
                    return CallNextHookEx(NULL, nCode, wParam, lParam);
                }
                // create variable state
            }
            // ! check for prohibited windows
            if (hotkeys[activeHotKey].prohibitedWindows.size() > 0)
            {
                if (isOnProhibitedWindow())
                {
                    hotkeyPressed = false;
                    hotkeyCorrectName = false;
                    return CallNextHookEx(NULL, nCode, wParam, lParam);
                }
            }
            hotkeyName = pressedHotkey;
            HotKeyEvent(hotkeys[activeHotKey].name, "pressed");
            return -1;
        }
        else
        {
            return CallNextHookEx(NULL, nCode, wParam, lParam);
        }
    }
    else if (wParam == WM_KEYUP)
    {
        if (isTrcktivityEnabled)
        {
            if (kbdTime == 0)
                kbdTime = keyInfo.time;
            if (keyInfo.time - kbdTime < 10000)
            {
                kbdPressCount++;
            }
            else
            {
                // ! Send trk to dart getTimestamp() : kbdPressCount
                TrktivityEvent("Keys", std::to_string(kbdPressCount));
                kbdTime = keyInfo.time;
                kbdPressCount = 0;
            }
        }
        //#h white
        if (hotkeyPressed)
        {
            if (!hotkeys[activeHotKey].listenToMovement)
            {
                HotKeyEvent(hotkeys[activeHotKey].name, "released");
                hotkeyPressed = false;
                hotkeyCorrectName = false;
                return CallNextHookEx(NULL, nCode, wParam, lParam);
            }
            std::wstring pressedHotkey{};
            if (GetAsyncKeyState(VK_CONTROL) & 0x8000)
                pressedHotkey.append(L"CTRL+");
            if (GetAsyncKeyState(VK_MENU) & 0x8000)
                pressedHotkey.append(L"ALT+");
            if (GetAsyncKeyState(VK_SHIFT) & 0x8000)
                pressedHotkey.append(L"SHIFT+");
            if (GetAsyncKeyState(VK_LWIN) & 0x8000)
                pressedHotkey.append(L"WIN+");
            if (pressedHotkey.length() < 2)
                return CallNextHookEx(NULL, nCode, wParam, lParam);

            wchar_t buffer[32] = {};
            UINT key = (keyInfo.scanCode << 16);
            GetKeyNameText((LONG)key, buffer, 32);

            std::wstring keyName(buffer);
            std::transform(keyName.begin(), keyName.end(), keyName.begin(), [](int c) -> char
                           { return static_cast<char>(::toupper(c)); });
            std::wstring modifisers(pressedHotkey);
            if (modifisers.length() > 0)
            {
                modifisers.erase(modifisers.length() - 1);
            }
            pressedHotkey.append(keyName);
            if (hotkeys[activeHotKey].hotkey == pressedHotkey || hotkeys[activeHotKey].modifisers == modifisers)
            {
                HotKeyEvent(hotkeys[activeHotKey].name, "released");
                hotkeyPressed = false;
                hotkeyCorrectName = false;
                // return 1;
                return CallNextHookEx(NULL, nCode, wParam, lParam);
            }
            // ! Send to dart hotkey released;
            // return 1;
        }
        //#e
    }

    return CallNextHookEx(NULL, nCode, wParam, lParam);
}
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
int htMousePosX;
int htMousePosY;
LRESULT CALLBACK HandleMouseHook(int nCode, WPARAM wParam, LPARAM lParam)
{
    if (nCode != HC_ACTION)
        return CallNextHookEx(NULL, nCode, wParam, lParam);

    MSLLHOOKSTRUCT *info = reinterpret_cast<MSLLHOOKSTRUCT *>(lParam);
    if (wParam == WM_MOUSEMOVE)
    {
        // while pressing
        if (hotkeyPressed)
        {
            POINT lpPoint;
            GetCursorPos(&lpPoint);
            if (htMousePosX == 0)
                htMousePosX = lpPoint.x;
            if (htMousePosY == 0)
                htMousePosY = lpPoint.y;

            // Left, Right, Up, Down;
            int
                diffX = lpPoint.x - htMousePosX,
                diffY = lpPoint.y - htMousePosY;

            if (abs(diffX) > 10 || abs(diffY) > 10)
            {
                Hotkey hotkey = hotkeys[activeHotKey];
                // ! send hotkey while pressed method with diff as value aswell, for opposite direction.
                HotKeyEvent(hotkey.name, "moved");
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
            mouseDirectionData[(int)floor(timeDiff / 3000)] = 1;
            if (timeDiff > 10000)
            {
                trkTimestamp = info->time;
                /// ! Send trk getTimestamp() : mouseDirectionData.size() to server.
                TrktivityEvent("Movement", std::to_string(mouseDirectionData.size()));
                mouseDirectionData.clear();
            }
        }
    }

    char const *up_down[] = {"up", "down"};
    bool down = false;
    mouseButtons button = BTN_NONE;
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
        down = static_cast<std::make_signed_t<WORD>>(HIWORD(info->mouseData)) < 0;
        if (!down)
            button = BTN_SWUP;
        else
            button = BTN_SWDOWN;
        break;
    }
    if (isViewsEnabled && button == BTN_RIGHT)
    {
        if (viewsState == 1 && !down)
        {
            viewsState = 2;
            // ! Send to dart views open
            ViewsEvent("open", NULL);
        }
        else if (viewsState == 2 && down)
        {
            viewsState = 3;
            // ! Send to dart selecting views
            ViewsEvent("selecting", NULL);
        }
        else if (viewsState == 3 && !down)
        {
            viewsState = 2;
            // ! Send to dart view selected;
            ViewsEvent("selected", NULL);
        }
    }
    if (isViewsEnabled && (button == BTN_SWUP || button == BTN_SWDOWN))
    {
        if (viewsState >= 2)
        {
            if (button == BTN_SWUP)
            {
                // ! Send to dart views switch up.
                ViewsEvent("switchup", NULL);
            }
            else
            {
                // ! Send to dart views switch down.
                ViewsEvent("switchdown", NULL);
            }
        }
    }
    if (button != BTN_NONE)
    {
        if (button == BTN_XBUTTON1)
        {
            if (HIWORD(info->mouseData) == 2)
                button = BTN_XBUTTON2;
        }
        int bID = (int)button;
        if (bID == 5 || bID == 6)
        {
            if (down)
            {
                bool result = false;
                if (bID == 5)
                    result = checkForPressedHotKey(L"MOUSEBUTTON4");
                else
                    result = checkForPressedHotKey(L"MOUSEBUTTON5");
                if (result)
                {
                    if (hotkeys[activeHotKey].noopScreenBusy)
                    {
                        // create varialbe state
                        QUERY_USER_NOTIFICATION_STATE state;
                        SHQueryUserNotificationState(&state);
                        if (state == QUNS_RUNNING_D3D_FULL_SCREEN || state == QUNS_BUSY)
                        {
                            hotkeyPressed = false;
                            hotkeyCorrectName = false;
                            return CallNextHookEx(NULL, nCode, wParam, lParam);
                        }
                        // create variable state
                    }
                    if (hotkeys[activeHotKey].prohibitedWindows.size() > 0)
                    {
                        if (isOnProhibitedWindow())
                        {
                            hotkeyPressed = false;
                            hotkeyCorrectName = false;
                            return CallNextHookEx(NULL, nCode, wParam, lParam);
                        }
                    }
                    // ! Send to dart hotkey success
                    HotKeyEvent(hotkeys[activeHotKey].name, "pressed");
                    return -1;
                }
            }
            else
            {
                if (hotkeyPressed)
                {
                    HotKeyEvent(hotkeys[activeHotKey].name, "released");
                    hotkeyPressed = false;
                    hotkeyCorrectName = false;
                    return 1;
                }
            }
        }
    }
    // ! Send output
    return CallNextHookEx(NULL, nCode, wParam, lParam);
}

VOID CALLBACK EventHook(HWINEVENTHOOK hWinEventHook, DWORD dwEvent, HWND hwnd, LONG idObject, LONG idChild, DWORD dwEventThread, DWORD dwmsEventTime)
{
    if (dwEvent == EVENT_SYSTEM_FOREGROUND)
    {
        // ! Send to server event_foreground hwnd;
        WinEvent("foreground", hwnd);
    }
    if (isTrcktivityEnabled && dwEvent == EVENT_OBJECT_NAMECHANGE)
    {
        if ((int)((DWORD_PTR)hwnd) <= 0)
            return;
        if (GetForegroundWindow() == hwnd)
        {
            // ! Send to server event_namechange hwnd;
            WinEvent("namechange", hwnd);
        }
    }
    if (isViewsEnabled)
    {
        if (dwEvent == EVENT_SYSTEM_MOVESIZESTART)
        {
            // ! Send to dart movestart;
            ViewsEvent("movestart", hwnd);
            movingWindow = hwnd;
            viewsState = 1;
        }
        else if (dwEvent == EVENT_SYSTEM_MOVESIZEEND)
        {
            // ! send to dart moves ended;
            ViewsEvent("moveend", hwnd);
            movingWindow = 0;
            viewsState = 0;
        }
    }
}

///!!
///!!
///!!
///!!
///!!
///!!
static int CALLBACK BrowseCallbackProc(HWND hwnd, UINT uMsg, LPARAM lParam, LPARAM lpData)
{
    return 0;
}
std::string BrowseFolder()
{

    BROWSEINFO bi = {0};
    bi.lpszTitle = _T("Browse for folder...");
    bi.ulFlags = BIF_RETURNONLYFSDIRS | BIF_NEWDIALOGSTYLE;
    bi.lpfn = BrowseCallbackProc;
    // bi.lParam = (LPARAM)wpath.c_str();

    LPITEMIDLIST pidl = SHBrowseForFolder(&bi);

    if (pidl != 0)
    {
        TCHAR path[MAX_PATH];
        SHGetPathFromIDList(pidl, path);

        // free memory used
        IMalloc *imalloc = 0;
        if (SUCCEEDED(SHGetMalloc(&imalloc)))
        {
            imalloc->Free(pidl);
            imalloc->Release();
        }

        return Encoding::WideToUtf8(path);
    }

    return "";
}

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
void SetStartOnSystemStartup(bool fAutoStart, std::string exePath, int ShowCmd, std::string args)
{
    WCHAR startMenuPath[MAX_PATH];
    HRESULT result = SHGetFolderPathW(NULL, CSIDL_STARTUP, NULL, 0, startMenuPath);
    std::string exe = exePath.substr(exePath.find_last_of("\\") + 1);
    std::wstring wExe = Encoding::Utf8ToWide(exe);
    wExe.replace(wExe.find(L".exe"), sizeof(L".exe") - 1, L".lnk");

    std::wstring wStartMenuPath = std::wstring(startMenuPath);
    wStartMenuPath.append(L"\\");
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
            psl->SetShowCmd(ShowCmd);
            if (!args.empty())
            {
                std::wstring wArgs = Encoding::Utf8ToWide(args);
                psl->SetArguments(wArgs.c_str());
            }
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
int SetStartOnStartupAsAdmin(bool enabled, std::string exePath)
{

    HRESULT result;
    IShellLink *link;
    IPersistFile *file;

    result = CoInitialize(NULL);
    result = CoCreateInstance(CLSID_ShellLink,
                              NULL,
                              CLSCTX_INPROC_SERVER,
                              IID_IShellLink,
                              (void **)&link);
    if (result != S_OK)
    {
        CoUninitialize();
        return -1;
    }

    // Retreive the IPersistFile
    result = link->QueryInterface(IID_IPersistFile, (void **)&file);
    if (result != S_OK)
    {
        link->Release();
        CoUninitialize();
        return -2;
    }

    WCHAR startMenuPath[MAX_PATH];
    result = SHGetFolderPathW(NULL, CSIDL_STARTUP, NULL, 0, startMenuPath);
    std::string exe = exePath.substr(exePath.find_last_of("\\") + 1);
    std::wstring wExe = Encoding::Utf8ToWide(exe);
    wExe.replace(wExe.find(L".exe"), sizeof(L".exe") - 1, L".lnk");
    std::wstring wStartMenuPath = std::wstring(startMenuPath);
    wStartMenuPath.append(L"\\");
    wStartMenuPath.append(wExe);

    // Load the link data from the file
    result = file->Load(wStartMenuPath.c_str(), STGM_READ);
    if (result != S_OK)
    {
        file->Release();
        link->Release();
        CoUninitialize();
        return -3;
    }

    IShellLinkDataList *pdl;

    result = link->QueryInterface(IID_IShellLinkDataList, (void **)&pdl);
    if (result != S_OK)
    {
        file->Release();
        link->Release();
        CoUninitialize();
        return -4;
    }

    DWORD dwFlags = 0;

    result = pdl->GetFlags(&dwFlags);
    if (result != S_OK)
    {
        pdl->Release();
        file->Release();
        link->Release();
        CoUninitialize();
        return -5;
    }
    if ((SLDF_RUNAS_USER & dwFlags) != SLDF_RUNAS_USER && enabled)
    {
        result = pdl->SetFlags(SLDF_RUNAS_USER | dwFlags);
        if (result != S_OK)
        {
            pdl->Release();
            file->Release();
            link->Release();
            CoUninitialize();
            return -6;
        }
    }
    else if ((SLDF_RUNAS_USER & dwFlags) == SLDF_RUNAS_USER && !enabled)
    {
        result = pdl->SetFlags(dwFlags & ~SLDF_RUNAS_USER);
        if (result != S_OK)
        {
            pdl->Release();
            file->Release();
            link->Release();
            CoUninitialize();
            return -7;
        }
    }
    else
    {
        pdl->Release();
        file->Release();
        link->Release();
        CoUninitialize();
        return 0;
    }

    result = file->Save(NULL, true);
    if (result != S_OK)
    {
        pdl->Release();
        file->Release();
        link->Release();
        CoUninitialize();
        return -8;
    }
    result = file->SaveCompleted(NULL);
    if (result != S_OK)
    {
        pdl->Release();
        file->Release();
        link->Release();
        CoUninitialize();
        return -9;
    }

    pdl->Release();
    file->Release();
    link->Release();
    CoUninitialize();
    return ERROR_SUCCESS;
}
int LinkToPath(LPCTSTR path, LPTSTR lpszPath, int iPathBufferSize)
{
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
        return 0;
    }

    IPersistFile *iPersistFile;

    rc = iShellLink->QueryInterface(IID_IPersistFile, (LPVOID *)&iPersistFile);

    if (!SUCCEEDED(rc))
    {
        return 0;
    }
    // Load the shortcut.
    rc = iPersistFile->Load(path, STGM_READ);
    if (!SUCCEEDED(rc))
    {
        return 0;
    }
    rc = iShellLink->Resolve((HWND)0, 0);

    if (!SUCCEEDED(rc))
    {
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
mHandleMouseHook(int nCode, WPARAM wParam, LPARAM lParam)
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
            args[flutter::EncodableValue("hookID")] = flutter::EncodableValue((int)((DWORD_PTR)gMouseHook)); // DWORD_PTR
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

void CALLBACK mHandleWinEvent(HWINEVENTHOOK hook, DWORD event, HWND hWnd, LONG idObject, LONG idChild, DWORD dwEventThread, DWORD dwmsEventTime)
{
    flutter::EncodableMap args = flutter::EncodableMap();

    args[flutter::EncodableValue("hookID")] = flutter::EncodableValue((int)((DWORD_PTR)gEventHook)); // DWORD_PTR
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

        if (g_MouseHook != NULL)
            g_MouseHook = SetWindowsHookEx(WH_MOUSE_LL, HandleMouseHook, GetModuleHandle(NULL), 0);
        if (g_KeyboardHook != NULL)
            g_KeyboardHook = SetWindowsHookEx(WH_KEYBOARD_LL, HandleKeyboardHook, GetModuleHandle(NULL), 0);
        if (g_EventHook != NULL)
            g_EventHook = SetWinEventHook(EVENT_MIN, EVENT_MAX, nullptr, EventHook, 0, 0, WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);
    }

    Tabamewin32Plugin::~Tabamewin32Plugin()
    {
        if (gEventHook != NULL)
            UnhookWinEvent(gEventHook);
        if (gMouseHook != NULL)
            UnhookWindowsHookEx(gMouseHook);

        if (g_EventHook != NULL)
            UnhookWinEvent(g_EventHook);
        if (g_MouseHook != NULL)
            UnhookWindowsHookEx(g_MouseHook);
        if (g_KeyboardHook != NULL)
            UnhookWindowsHookEx(g_KeyboardHook);
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

            gMouseHook = SetWindowsHookEx(WH_MOUSE_LL, mHandleMouseHook, GetModuleHandle(NULL), 0);

            if (eventMin > 0)
                gEventHook = SetWinEventHook(eventMin, eventMax, NULL, mHandleWinEvent, 0, 0, eventFilters);
            else
                gEventHook = NULL;

            flutter::EncodableMap args = flutter::EncodableMap();
            args[flutter::EncodableValue("mouseHookID")] = flutter::EncodableValue((int)((LONG_PTR)gMouseHook)); // DWORD_PTR
            args[flutter::EncodableValue("eventHookID")] = flutter::EncodableValue((int)((LONG_PTR)gEventHook)); // DWORD_PTR
            result->Success(flutter::EncodableValue(args));
        }
        else if (method_name.compare("uninstallHooks") == 0)
        {
            if (gEventHook != NULL)
                UnhookWinEvent(gEventHook);
            if (gMouseHook != NULL)
                UnhookWindowsHookEx(gMouseHook);
            gEventHook = NULL;
            gMouseHook = NULL;
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
                result->Success(flutter::EncodableValue(""));
            }
        }
        else if (method_name.compare("setStartOnSystemStartup") == 0)
        {
            const flutter::EncodableMap &args = std::get<flutter::EncodableMap>(*method_call.arguments());

            std::string exePath = std::get<std::string>(args.at(flutter::EncodableValue("exePath")));
            bool enabled = std::get<bool>(args.at(flutter::EncodableValue("enabled")));
            int ShowCmd = std::get<int>(args.at(flutter::EncodableValue("showCmd")));
            std::string startArgs = std::get<std::string>(args.at(flutter::EncodableValue("args")));

            SetStartOnSystemStartup(enabled, exePath, ShowCmd, startArgs);

            result->Success(flutter::EncodableValue(""));
        }
        else if (method_name.compare("setStartOnStartupAsAdmin") == 0)
        {
            const flutter::EncodableMap &args = std::get<flutter::EncodableMap>(*method_call.arguments());
            std::string exePath = std::get<std::string>(args.at(flutter::EncodableValue("exePath")));
            bool enabled = std::get<bool>(args.at(flutter::EncodableValue("enabled")));

            int output = SetStartOnStartupAsAdmin(enabled, exePath);
            result->Success(flutter::EncodableValue(output));
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
        else if (method_name.compare("browseFolder") == 0)
        {
            std::string out = BrowseFolder();
            result->Success(flutter::EncodableValue(out));
        }
        //#h white
        else if (method_name.compare("hotkeyAdd") == 0)
        {
            const flutter::EncodableMap &args = std::get<flutter::EncodableMap>(*method_call.arguments());
            string key = std::get<std::string>(args.at(flutter::EncodableValue("hotkey")));
            string modifisers = std::get<std::string>(args.at(flutter::EncodableValue("modifisers")));
            string matchWindowBy = std::get<std::string>(args.at(flutter::EncodableValue("matchWindowBy")));
            string matchWindowText = std::get<std::string>(args.at(flutter::EncodableValue("matchWindowText")));
            string prohibitedWindows = std::get<std::string>(args.at(flutter::EncodableValue("prohibitedWindows")));

            bool activateWindowUnderCursor = std::get<bool>(args.at(flutter::EncodableValue("activateWindowUnderCursor")));
            bool regionasPercentage = std::get<bool>(args.at(flutter::EncodableValue("regionasPercentage")));
            bool regionOnScreen = std::get<bool>(args.at(flutter::EncodableValue("regionOnScreen")));
            bool listenToMovement = std::get<bool>(args.at(flutter::EncodableValue("listenToMovement")));
            bool noopScreenBusy = std::get<bool>(args.at(flutter::EncodableValue("noopScreenBusy")));

            string name = std::get<std::string>(args.at(flutter::EncodableValue("name")));

            int regionX1 = std::get<int>(args.at(flutter::EncodableValue("regionX1")));
            int regionX2 = std::get<int>(args.at(flutter::EncodableValue("regionX2")));
            int regionY1 = std::get<int>(args.at(flutter::EncodableValue("regionY1")));
            int regionY2 = std::get<int>(args.at(flutter::EncodableValue("regionY2")));
            int anchorType = std::get<int>(args.at(flutter::EncodableValue("anchorType")));
            Hotkey hotkey{};

            hotkey.hotkey = Encoding::Utf8ToWide(key);
            hotkey.modifisers = Encoding::Utf8ToWide(modifisers);
            hotkey.activateWindowUnderCursor = activateWindowUnderCursor;
            hotkey.listenToMovement = listenToMovement;
            hotkey.matchWindowBy = matchWindowBy;
            hotkey.matchWindowText = Encoding::Utf8ToWide(matchWindowText);

            hotkey.noopScreenBusy = noopScreenBusy;
            if (prohibitedWindows.length() > 0)
            {
                std::vector<std::string> prohibitedWindowsVector;
                std::stringstream ss(prohibitedWindows);
                std::string token;
                while (std::getline(ss, token, ';'))
                {
                    prohibitedWindowsVector.push_back(token);
                }
                if (prohibitedWindowsVector.size() == 0)
                {
                    hotkey.prohibitedWindows.push_back(prohibitedWindows);
                }
                else
                    hotkey.prohibitedWindows = prohibitedWindowsVector;
            }

            hotkey.name = name;

            hotkey.regionX1 = regionX1;
            hotkey.regionX2 = regionX2;
            hotkey.regionY1 = regionY1;
            hotkey.regionY2 = regionY2;

            hotkey.regionAsPercentage = regionasPercentage;
            hotkey.regionOnScreen = regionOnScreen;
            hotkey.anchorType = anchorType;

            hotkeys.push_back(hotkey);
            result->Success(flutter::EncodableValue(true));
        }
        else if (method_name.compare("hotkeyReset") == 0)
        {
            hotkeys.clear();
            result->Success(flutter::EncodableValue(true));
        }
        else if (method_name.compare("hotkeyUnHook") == 0)
        {
            if (g_EventHook != NULL)
                UnhookWinEvent(g_EventHook);
            if (g_MouseHook != NULL)
                UnhookWindowsHookEx(g_MouseHook);
            if (g_KeyboardHook != NULL)
                UnhookWindowsHookEx(g_KeyboardHook);
            g_EventHook = NULL;
            g_MouseHook = NULL;
            g_KeyboardHook = NULL;
            result->Success(flutter::EncodableValue(true));
        }
        else if (method_name.compare("hotkeyHook") == 0)
        {
            if (g_MouseHook == NULL)
                g_MouseHook = SetWindowsHookEx(WH_MOUSE_LL, HandleMouseHook, GetModuleHandle(NULL), 0);
            if (g_KeyboardHook == NULL)
                g_KeyboardHook = SetWindowsHookEx(WH_KEYBOARD_LL, HandleKeyboardHook, GetModuleHandle(NULL), 0);
            if (g_EventHook == NULL)
                g_EventHook = SetWinEventHook(EVENT_MIN, EVENT_MAX, nullptr, EventHook, 0, 0, WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);
            result->Success(flutter::EncodableValue(true));
        }
        else if (method_name.compare("trcktivity") == 0)
        {
            const flutter::EncodableMap &args = std::get<flutter::EncodableMap>(*method_call.arguments());
            // bool
            bool enabled = std::get<bool>(args.at(flutter::EncodableValue("enabled")));
            isTrcktivityEnabled = enabled;
            result->Success(flutter::EncodableValue(true));
        }
        else if (method_name.compare("views") == 0)
        {
            const flutter::EncodableMap &args = std::get<flutter::EncodableMap>(*method_call.arguments());
            // bool
            bool enabled = std::get<bool>(args.at(flutter::EncodableValue("enabled")));
            isViewsEnabled = enabled;
            result->Success(flutter::EncodableValue(true));
        }

        //#e
        else
        {
            result->NotImplemented();
        }
    }
    //#e
} // namespace tabamewin32
