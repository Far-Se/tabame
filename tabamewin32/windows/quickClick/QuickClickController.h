#pragma once

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellscalingapi.h>
#include <thread>
#include <atomic>
#include <vector>
#include <map>
#include <string>
#include <chrono>
#include <functional>

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------
struct QuickClickConfig
{
    // Grid key arrays
    std::vector<char> horizontalKeys = { '1','2','3','4','5','6','7','8','9' };
    std::vector<char> verticalKeys   = { 'q','w','e','r','t','y','u','i','o' };

    // Nudge amount in logical pixels
    int nudgeAmount = 5;

    // Double-click detection window (ms)
    int doubleClickThresholdMs = 400;

    // Extra VK bindings for nudge directions (in addition to arrow keys)
    std::map<std::string, std::vector<int>> extraArrowBindings = {
        { "up",    {} },
        { "down",  {} },
        { "left",  {} },
        { "right", {} }
    };

    // Action keys (VK codes, all user-overridable)
    int leftClickKey   = VK_CONTROL; // single press  → left click
    int doubleClickKey = VK_CONTROL; // double press  → double click (same key as leftClickKey by default)
    int rightClickKey  = VK_MENU;    // single press  → right click
    int dragKey        = VK_MENU;    // hold          → drag        (same key as rightClickKey by default)

    // Scroll keys (VK codes, user-overridable)
    int scrollUpKey    = VK_OEM_4;   // [
    int scrollDownKey  = VK_OEM_6;   // ]
    int scrollLeftKey  = VK_OEM_1;   // ;
    int scrollRightKey = VK_OEM_7;   // '

    // Scroll delta per keypress (WHEEL_DELTA units)
    int scrollDelta = WHEEL_DELTA;
};

// ---------------------------------------------------------------------------
// Controller
// ---------------------------------------------------------------------------
class QuickClickController
{
public:
    explicit QuickClickController(QuickClickConfig config = {});
    ~QuickClickController();

    // Install the low-level keyboard hook and start the message-pump thread.
    void Start();

    // Remove the hook and join the thread.
    void Stop();

    // Toggle whether keystrokes are intercepted.
    void SetActive(bool active);
    bool IsActive() const { return active_.load(); }

    // Update configuration.
    void UpdateConfig(QuickClickConfig config);

    // Set callback for hotkey events.
    void SetEventCallback(std::function<void(const std::string&, const std::map<std::string, std::string>&)> callback) { eventCallback_ = callback; }

private:
    void TriggerEvent(const std::string& eventName, const std::map<std::string, std::string>& params = {}) {
        if (eventCallback_) eventCallback_(eventName, params);
    }
    // ---- Hook plumbing ----
    static LRESULT CALLBACK LowLevelKeyboardProc(int nCode, WPARAM wParam, LPARAM lParam);
    void HookThreadProc();

    // ---- Key dispatch ----
    // Returns true if the key should be suppressed (not passed to other apps).
    bool HandleKey(DWORD vkCode, bool keyDown);

    // ---- Grid movement ----
    void MoveToGridX(int index);
    void MoveToGridY(int index);

    // ---- Nudge ----
    void NudgeMouse(int dx, int dy);

    // ---- Click helpers ----
    void PerformLeftClick();
    void PerformRightClick();
    void PerformDoubleClick();

    // ---- Drag ----
    void SetDragging(bool dragging);

    // ---- Scroll ----
    void Scroll(int delta, bool horizontal);

    // ---- Monitor / DPI helpers ----
    // Returns the rect (in virtual-screen coords) of the monitor under the cursor,
    // and the DPI of that monitor.
    struct MonitorInfo { RECT rect; UINT dpi; };
    static MonitorInfo GetMonitorUnderCursor();

    // Scale a logical pixel delta by the monitor DPI.
    static int ScaleForDpi(int value, UINT dpi);

    // ---- Utility ----
    // Build a SendInput structure for a mouse event.
    static INPUT MakeMouseInput(DWORD flags, DWORD mouseData = 0, LONG dx = 0, LONG dy = 0);

    // ---- State ----
    QuickClickConfig  config_;
    std::atomic<bool> active_{ false };
    std::atomic<bool> isDragging_{ false };

    // Left-click / double-click bookkeeping (tracks leftClickKey / doubleClickKey)
    DWORD lastClickKeyPressTime_{ 0 };
    bool  clickKeyPendingSingle_{ false };

    // Drag key state (tracks dragKey)
    bool dragKeyDown_{ false };

    // Hook & thread
    HHOOK       hook_{ nullptr };
    std::thread hookThread_;
    DWORD       hookThreadId_{ 0 };

    std::function<void(const std::string&, const std::map<std::string, std::string>&)> eventCallback_;

    // Static instance pointer used to bridge the static hook callback.
    static QuickClickController* s_instance;
};
