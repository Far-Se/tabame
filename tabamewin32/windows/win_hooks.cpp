#ifndef TABAMEWIN32_WIN_HOOKS
#define TABAMEWIN32_WIN_HOOKS

#include <windows.h>
#include <type_traits>

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

// ---------------------------------------------------------------------------
// Forward-declared globals
// ---------------------------------------------------------------------------
extern std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel;

#define EVENTHOOK 1
#define MOUSEHOOK 2

// ---------------------------------------------------------------------------
// Hook handles & button state (generic hook system)
// ---------------------------------------------------------------------------
HWINEVENTHOOK gEventHook = nullptr;
HHOOK gMouseHook = nullptr;
int mouseWatchButtons[7] = {0, 0, 0, 0, 0, 0, 0};
int mouseControlButtons[7] = {0, 0, 0, 0, 0, 0, 0};

// ---------------------------------------------------------------------------
// Forward declarations
// ---------------------------------------------------------------------------
void CALLBACK mHandleWinEvent(HWINEVENTHOOK, DWORD, HWND, LONG, LONG, DWORD, DWORD);
LRESULT CALLBACK mHandleMouseHook(int, WPARAM, LPARAM);

// ---------------------------------------------------------------------------
// Generic mouse hook (button watch/control system)
// ---------------------------------------------------------------------------
LRESULT CALLBACK mHandleMouseHook(int nCode, WPARAM wParam, LPARAM lParam)
{
    if (nCode != HC_ACTION)
        return CallNextHookEx(nullptr, nCode, wParam, lParam);

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

    bool down = false;

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

    if (button != BTN_NONE)
    {
        if (button == BTN_XBUTTON1 && HIWORD(info->mouseData) == 2)
            button = BTN_XBUTTON2;

        int bID = static_cast<int>(button);
        if (bID < 7 && (mouseWatchButtons[bID] == 1 || mouseControlButtons[bID] == 1))
        {
            flutter::EncodableMap args;
            args[flutter::EncodableValue("hookID")] = flutter::EncodableValue(static_cast<int>(reinterpret_cast<DWORD_PTR>(gMouseHook)));
            args[flutter::EncodableValue("hookType")] = flutter::EncodableValue(MOUSEHOOK);
            args[flutter::EncodableValue("state")] = flutter::EncodableValue(down);
            args[flutter::EncodableValue("button")] = flutter::EncodableValue(bID);

            if (mouseControlButtons[bID] == 1)
            {
                args[flutter::EncodableValue("type")] = flutter::EncodableValue("control");
                channel->InvokeMethod("onEvent", std::make_unique<flutter::EncodableValue>(args));
                return -1;
            }

            args[flutter::EncodableValue("type")] = flutter::EncodableValue("watch");
            channel->InvokeMethod("onEvent", std::make_unique<flutter::EncodableValue>(args));
        }
    }

    return CallNextHookEx(nullptr, nCode, wParam, lParam);
}

// ---------------------------------------------------------------------------
// Generic win event hook
// ---------------------------------------------------------------------------
void CALLBACK mHandleWinEvent(HWINEVENTHOOK /*hook*/, DWORD event, HWND hWnd,
                              LONG idObject, LONG idChild,
                              DWORD dwEventThread, DWORD dwmsEventTime)
{
    flutter::EncodableMap args;
    args[flutter::EncodableValue("hookID")] = flutter::EncodableValue(static_cast<int>(reinterpret_cast<DWORD_PTR>(gEventHook)));
    args[flutter::EncodableValue("hookType")] = flutter::EncodableValue(EVENTHOOK);
    args[flutter::EncodableValue("event")] = flutter::EncodableValue(static_cast<int>(event));
    args[flutter::EncodableValue("hWnd")] = flutter::EncodableValue(static_cast<int>(reinterpret_cast<DWORD_PTR>(hWnd)));
    args[flutter::EncodableValue("idObject")] = flutter::EncodableValue(idObject);
    args[flutter::EncodableValue("idChild")] = flutter::EncodableValue(idChild);
    args[flutter::EncodableValue("dwEventThread")] = flutter::EncodableValue(static_cast<int>(dwEventThread));
    args[flutter::EncodableValue("dwmsEventTime")] = flutter::EncodableValue(static_cast<int>(dwmsEventTime));
    channel->InvokeMethod("onEvent", std::make_unique<flutter::EncodableValue>(args));
}

#endif // TABAMEWIN32_WIN_HOOKS
