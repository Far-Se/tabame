#include "QuickClickController.h"
#include <stdexcept>
#include <algorithm>
#include <cassert>

// Link against Shcore for GetDpiForMonitor
#pragma comment(lib, "Shcore.lib")

// ---------------------------------------------------------------------------
// Static instance pointer
// ---------------------------------------------------------------------------
QuickClickController* QuickClickController::s_instance = nullptr;

// ---------------------------------------------------------------------------
// Ctor / Dtor
// ---------------------------------------------------------------------------
QuickClickController::QuickClickController(QuickClickConfig config)
    : config_(std::move(config))
{
    assert(s_instance == nullptr && "Only one QuickClickController may exist at a time.");
    s_instance = this;
}

QuickClickController::~QuickClickController()
{
    Stop();
    s_instance = nullptr;
}

// ---------------------------------------------------------------------------
// Start / Stop / SetActive
// ---------------------------------------------------------------------------
void QuickClickController::Start()
{
    if (hook_) return;

    hookThread_ = std::thread([this]() { HookThreadProc(); });

    while (!hook_)
        Sleep(1);
}

void QuickClickController::Stop()
{
    if (!hookThread_.joinable()) return;

    if (hookThreadId_)
        PostThreadMessageW(hookThreadId_, WM_QUIT, 0, 0);

    hookThread_.join();
    hook_ = nullptr;
    hookThreadId_ = 0;
}

void QuickClickController::SetActive(bool active)
{
    if (!active && isDragging_.load())
        SetDragging(false);

    active_.store(active);
}

void QuickClickController::UpdateConfig(QuickClickConfig config)
{
    config_ = std::move(config);
}

// ---------------------------------------------------------------------------
// Hook thread
// ---------------------------------------------------------------------------
void QuickClickController::HookThreadProc()
{
    hookThreadId_ = GetCurrentThreadId();

    hook_ = SetWindowsHookExW(WH_KEYBOARD_LL, LowLevelKeyboardProc, nullptr, 0);
    if (!hook_)
        throw std::runtime_error("SetWindowsHookEx failed");

    MSG msg{};
    while (GetMessageW(&msg, nullptr, 0, 0) > 0)
    {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }

    UnhookWindowsHookEx(hook_);
}

// ---------------------------------------------------------------------------
// Low-level keyboard hook callback (static)
// ---------------------------------------------------------------------------
LRESULT CALLBACK QuickClickController::LowLevelKeyboardProc(int nCode, WPARAM wParam, LPARAM lParam)
{
    if (nCode < 0 || !s_instance || !s_instance->active_.load())
        return CallNextHookEx(nullptr, nCode, wParam, lParam);

    const auto* kbs = reinterpret_cast<KBDLLHOOKSTRUCT*>(lParam);
    const bool keyDown = (wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN);
    const bool keyUp   = (wParam == WM_KEYUP   || wParam == WM_SYSKEYUP);

    if (!keyDown && !keyUp)
        return CallNextHookEx(nullptr, nCode, wParam, lParam);

    const bool suppress = s_instance->HandleKey(kbs->vkCode, keyDown);
    if (suppress)
        return 1;

    return CallNextHookEx(nullptr, nCode, wParam, lParam);
}

// ---------------------------------------------------------------------------
// Central key dispatch
// ---------------------------------------------------------------------------
bool QuickClickController::HandleKey(DWORD vkCode, bool keyDown)
{
    auto isExtraBinding = [&](const std::string& dir) -> bool {
        auto it = config_.extraArrowBindings.find(dir);
        if (it == config_.extraArrowBindings.end()) return false;
        for (int vk : it->second)
            if (static_cast<DWORD>(vk) == vkCode) return true;
        return false;
    };

    // ----------------------------------------------------------------
    // Drag key  (hold = drag; configurable, default VK_MENU / Alt)
    //
    // When dragKey == rightClickKey (the default), drag takes full
    // ownership of that VK and right-click is never fired independently.
    // Assign them different VKs to get both behaviours simultaneously.
    // ----------------------------------------------------------------
    if (vkCode == static_cast<DWORD>(config_.dragKey))
    {
        if (keyDown && !dragKeyDown_)
        {
            dragKeyDown_ = true;
            SetDragging(true);
        }
        else if (!keyDown && dragKeyDown_)
        {
            dragKeyDown_ = false;
            SetDragging(false);
        }
        return true;
    }

    // ----------------------------------------------------------------
    // Right-click key  (configurable, default VK_MENU / Alt)
    // Only reached when rightClickKey differs from dragKey.
    // ----------------------------------------------------------------
    if (vkCode == static_cast<DWORD>(config_.rightClickKey))
    {
        if (keyDown)
            PerformRightClick();
        return true;
    }

    // ----------------------------------------------------------------
    // Left-click / double-click key  (configurable, default VK_CONTROL)
    //
    // • Same key for both (default): single press = left click,
    //   two presses within doubleClickThresholdMs = double click.
    // • Different keys: each fires its action immediately on keydown.
    // ----------------------------------------------------------------
    const bool isLeftClickKey   = (vkCode == static_cast<DWORD>(config_.leftClickKey));
    const bool isDoubleClickKey = (vkCode == static_cast<DWORD>(config_.doubleClickKey));

    if (isLeftClickKey || isDoubleClickKey)
    {
        const bool sameKey = (config_.leftClickKey == config_.doubleClickKey);

        if (keyDown)
        {
            if (sameKey)
            {
                // Double-click detection: two presses within the threshold.
                const DWORD now     = GetTickCount();
                const DWORD elapsed = now - lastClickKeyPressTime_;

                if (clickKeyPendingSingle_ &&
                    elapsed <= static_cast<DWORD>(config_.doubleClickThresholdMs))
                {
                    clickKeyPendingSingle_ = false;
                    PerformDoubleClick();
                }
                else
                {
                    lastClickKeyPressTime_ = now;
                    clickKeyPendingSingle_ = true;
                }
            }
            else
            {
                // Separate keys: fire immediately, no ambiguity.
                if (isDoubleClickKey)
                    PerformDoubleClick();
                else
                    PerformLeftClick();
            }
        }
        else // keyUp
        {
            // Only relevant in same-key mode: fire single click once the
            // threshold window expires without a second press.
            if (sameKey && clickKeyPendingSingle_)
            {
                const DWORD elapsed = GetTickCount() - lastClickKeyPressTime_;
                if (elapsed > static_cast<DWORD>(config_.doubleClickThresholdMs))
                {
                    clickKeyPendingSingle_ = false;
                    PerformLeftClick();
                }
            }
        }
        return true;
    }

    // ----------------------------------------------------------------
    // Only process the rest on keydown events
    // ----------------------------------------------------------------
    if (!keyDown)
        return false;

    // ----------------------------------------------------------------
    // Scroll keys
    // ----------------------------------------------------------------
    if (vkCode == static_cast<DWORD>(config_.scrollUpKey))    { Scroll( config_.scrollDelta, false); return true; }
    if (vkCode == static_cast<DWORD>(config_.scrollDownKey))  { Scroll(-config_.scrollDelta, false); return true; }
    if (vkCode == static_cast<DWORD>(config_.scrollLeftKey))  { Scroll(-config_.scrollDelta, true);  return true; }
    if (vkCode == static_cast<DWORD>(config_.scrollRightKey)) { Scroll( config_.scrollDelta, true);  return true; }

    // ----------------------------------------------------------------
    // Arrow keys (+ extra bindings) -> nudge
    // ----------------------------------------------------------------
    if (vkCode == VK_UP    || isExtraBinding("up"))    { NudgeMouse(0, -config_.nudgeAmount); return true; }
    if (vkCode == VK_DOWN  || isExtraBinding("down"))  { NudgeMouse(0,  config_.nudgeAmount); return true; }
    if (vkCode == VK_LEFT  || isExtraBinding("left"))  { NudgeMouse(-config_.nudgeAmount, 0); return true; }
    if (vkCode == VK_RIGHT || isExtraBinding("right")) { NudgeMouse( config_.nudgeAmount, 0); return true; }

    // ----------------------------------------------------------------
    // Grid keys
    // ----------------------------------------------------------------
    {
        char ch      = static_cast<char>(vkCode);
        char chLower = (ch >= 'A' && ch <= 'Z') ? static_cast<char>(ch + 32) : ch;

        for (int i = 0; i < static_cast<int>(config_.horizontalKeys.size()); ++i)
            if (config_.horizontalKeys[i] == chLower) { MoveToGridX(i); return true; }

        for (int i = 0; i < static_cast<int>(config_.verticalKeys.size()); ++i)
            if (config_.verticalKeys[i] == chLower)   { MoveToGridY(i); return true; }
    }

    return false;
}

// ---------------------------------------------------------------------------
// Grid movement
// ---------------------------------------------------------------------------
void QuickClickController::MoveToGridX(int index)
{
    const auto mi    = GetMonitorUnderCursor();
    const int  total = static_cast<int>(config_.horizontalKeys.size());
    if (total == 0) return;

    const int monitorWidth = mi.rect.right - mi.rect.left;
    const int x = mi.rect.left + static_cast<int>((index + 0.5) * monitorWidth / total);

    POINT cur{};
    GetCursorPos(&cur);
    SetCursorPos(x, cur.y);
    TriggerEvent("moveX", {{"index", std::to_string(index)}});
}

void QuickClickController::MoveToGridY(int index)
{
    const auto mi    = GetMonitorUnderCursor();
    const int  total = static_cast<int>(config_.verticalKeys.size());
    if (total == 0) return;

    const int monitorHeight = mi.rect.bottom - mi.rect.top;
    const int y = mi.rect.top + static_cast<int>((index + 0.5) * monitorHeight / total);

    POINT cur{};
    GetCursorPos(&cur);
    SetCursorPos(cur.x, y);
    TriggerEvent("moveY", {{"index", std::to_string(index)}});
}

// ---------------------------------------------------------------------------
// Nudge
// ---------------------------------------------------------------------------
void QuickClickController::NudgeMouse(int dx, int dy)
{
    const auto mi       = GetMonitorUnderCursor();
    const int  scaledDx = ScaleForDpi(dx, mi.dpi);
    const int  scaledDy = ScaleForDpi(dy, mi.dpi);

    INPUT inp = MakeMouseInput(MOUSEEVENTF_MOVE, 0,
                               static_cast<LONG>(scaledDx),
                               static_cast<LONG>(scaledDy));
    SendInput(1, &inp, sizeof(INPUT));
    TriggerEvent("nudge", {{"dx", std::to_string(dx)}, {"dy", std::to_string(dy)}});
}

// ---------------------------------------------------------------------------
// Clicks
// ---------------------------------------------------------------------------
void QuickClickController::PerformLeftClick()
{
    INPUT inputs[2]{};
    inputs[0] = MakeMouseInput(MOUSEEVENTF_LEFTDOWN);
    inputs[1] = MakeMouseInput(MOUSEEVENTF_LEFTUP);
    SendInput(2, inputs, sizeof(INPUT));
    TriggerEvent("leftClick");
}

void QuickClickController::PerformRightClick()
{
    INPUT inputs[2]{};
    inputs[0] = MakeMouseInput(MOUSEEVENTF_RIGHTDOWN);
    inputs[1] = MakeMouseInput(MOUSEEVENTF_RIGHTUP);
    SendInput(2, inputs, sizeof(INPUT));
    TriggerEvent("rightClick");
}

void QuickClickController::PerformDoubleClick()
{
    INPUT inputs[4]{};
    inputs[0] = MakeMouseInput(MOUSEEVENTF_LEFTDOWN);
    inputs[1] = MakeMouseInput(MOUSEEVENTF_LEFTUP);
    inputs[2] = MakeMouseInput(MOUSEEVENTF_LEFTDOWN);
    inputs[3] = MakeMouseInput(MOUSEEVENTF_LEFTUP);
    SendInput(4, inputs, sizeof(INPUT));
    TriggerEvent("doubleClick");
}

// ---------------------------------------------------------------------------
// Drag
// ---------------------------------------------------------------------------
void QuickClickController::SetDragging(bool dragging)
{
    if (dragging == isDragging_.load()) return;
    isDragging_.store(dragging);

    INPUT inp = MakeMouseInput(dragging ? MOUSEEVENTF_LEFTDOWN : MOUSEEVENTF_LEFTUP);
    SendInput(1, &inp, sizeof(INPUT));
    TriggerEvent(dragging ? "dragStart" : "dragEnd");
}

// ---------------------------------------------------------------------------
// Scroll
// ---------------------------------------------------------------------------
void QuickClickController::Scroll(int delta, bool horizontal)
{
    DWORD flags = horizontal ? MOUSEEVENTF_HWHEEL : MOUSEEVENTF_WHEEL;
    INPUT inp   = MakeMouseInput(flags, static_cast<DWORD>(delta));
    SendInput(1, &inp, sizeof(INPUT));
    TriggerEvent("scroll", {{"delta", std::to_string(delta)}, {"horizontal", horizontal ? "true" : "false"}});
}

// ---------------------------------------------------------------------------
// Monitor / DPI helpers
// ---------------------------------------------------------------------------
QuickClickController::MonitorInfo QuickClickController::GetMonitorUnderCursor()
{
    POINT cursor{};
    GetCursorPos(&cursor);

    HMONITOR hMon = MonitorFromPoint(cursor, MONITOR_DEFAULTTONEAREST);

    MONITORINFO mi{};
    mi.cbSize = sizeof(mi);
    GetMonitorInfoW(hMon, &mi);

    UINT dpiX = 96, dpiY = 96;
    GetDpiForMonitor(hMon, MDT_EFFECTIVE_DPI, &dpiX, &dpiY);

    return { mi.rcMonitor, dpiX };
}

int QuickClickController::ScaleForDpi(int value, UINT dpi)
{
    return MulDiv(value, static_cast<int>(dpi), 96);
}

// ---------------------------------------------------------------------------
// Utility
// ---------------------------------------------------------------------------
INPUT QuickClickController::MakeMouseInput(DWORD flags, DWORD mouseData, LONG dx, LONG dy)
{
    INPUT inp{};
    inp.type           = INPUT_MOUSE;
    inp.mi.dwFlags     = flags;
    inp.mi.mouseData   = mouseData;
    inp.mi.dx          = dx;
    inp.mi.dy          = dy;
    inp.mi.time        = 0;
    inp.mi.dwExtraInfo = 0;
    return inp;
}
