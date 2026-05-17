#include "QuickClickController.h"
#include <algorithm>
#include <cassert>

#pragma comment(lib, "Shcore.lib")

QuickClickController *QuickClickController::s_instance = nullptr;

QuickClickController::QuickClickController(QuickClickConfig config)
    : config_(std::move(config)) {
  assert(s_instance == nullptr);
  s_instance = this;
}

QuickClickController::~QuickClickController() {
  Stop();
  s_instance = nullptr;
}

void QuickClickController::Start() {
  if (running_)
    return;
  running_ = true;

  hookThread_ = std::thread([this]() { HookThreadProc(); });
  moveThread_ = std::thread([this]() { MovementThreadProc(); });

  while (!hook_)
    Sleep(1);
}

void QuickClickController::Stop() {
  running_ = false;
  if (hookThreadId_)
    PostThreadMessageW(hookThreadId_, WM_QUIT, 0, 0);

  if (hookThread_.joinable())
    hookThread_.join();
  if (moveThread_.joinable())
    moveThread_.join();

  hook_ = nullptr;
}

void QuickClickController::SetActive(bool active) {
  if (!active && isDragging_.load())
    SetDragging(false);
  active_.store(active);
}

void QuickClickController::UpdateConfig(QuickClickConfig config) {
  config_ = std::move(config);
}

void QuickClickController::HookThreadProc() {
  hookThreadId_ = GetCurrentThreadId();
  hook_ = SetWindowsHookExW(WH_KEYBOARD_LL, LowLevelKeyboardProc, nullptr, 0);

  MSG msg{};
  while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
    TranslateMessage(&msg);
    DispatchMessageW(&msg);
  }
  UnhookWindowsHookEx(hook_);
}

// ---------------------------------------------------------------------------
// Movement Loop (Handles Diagonal, Shift Speed, and Triggers)
// ---------------------------------------------------------------------------
void QuickClickController::MovementThreadProc() {
  auto lastShiftReset = std::chrono::steady_clock::now();
  bool shiftWasHeld = false;

  while (running_) {
    if (active_.load() && (moveUp_ || moveDown_ || moveLeft_ || moveRight_)) {
      int dx = 0, dy = 0;
      if (moveUp_)
        dy -= config_.nudgeAmount;
      if (moveDown_)
        dy += config_.nudgeAmount;
      if (moveLeft_)
        dx -= config_.nudgeAmount;
      if (moveRight_)
        dx += config_.nudgeAmount;

      int multiplier = 1;
      bool shiftIsHeld = (GetKeyState(VK_SHIFT) & 0x8000) != 0;

      if (shiftIsHeld) {
        if (!shiftWasHeld) {
          lastShiftReset = std::chrono::steady_clock::now();
          shiftWasHeld = true;
        }

        auto now = std::chrono::steady_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(
                            now - lastShiftReset)
                            .count();

        if (duration >= 1000) {
          multiplier = 8;
        } else {
          multiplier = 5;
        }
      } else {
        shiftWasHeld = false;
      }

      if (dx != 0 || dy != 0) {
        dx *= multiplier;
        dy *= multiplier;

        const auto mi = GetMonitorUnderCursor();
        INPUT inp = MakeMouseInput(MOUSEEVENTF_MOVE, 0, ScaleForDpi(dx, mi.dpi),
                                   ScaleForDpi(dy, mi.dpi));
        SendInput(1, &inp, sizeof(INPUT));

        TriggerEvent("nudge", {{"dx", std::to_string(dx)},
                               {"dy", std::to_string(dy)},
                               {"multiplier", std::to_string(multiplier)}});
      }
    } else {
      // Reset shift tracking if no movement keys are held
      shiftWasHeld = false;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(16));
  }
}

LRESULT CALLBACK QuickClickController::LowLevelKeyboardProc(int nCode,
                                                            WPARAM wParam,
                                                            LPARAM lParam) {
  if (nCode < 0 || !s_instance || !s_instance->active_.load())
    return CallNextHookEx(nullptr, nCode, wParam, lParam);

  const auto *kbs = reinterpret_cast<KBDLLHOOKSTRUCT *>(lParam);
  const bool keyDown = (wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN);

  if (s_instance->HandleKey(kbs->vkCode, keyDown))
    return 1;

  return CallNextHookEx(nullptr, nCode, wParam, lParam);
}

bool QuickClickController::HandleKey(DWORD vkCode, bool keyDown) {
  DWORD norm = vkCode;
  if (vkCode == VK_LCONTROL || vkCode == VK_RCONTROL)
    norm = VK_CONTROL;
  else if (vkCode == VK_LMENU || vkCode == VK_RMENU)
    norm = VK_MENU;
  else if (vkCode == VK_LSHIFT || vkCode == VK_RSHIFT)
    norm = VK_SHIFT;

  auto isBound = [&](const std::string &dir) {
    auto it = config_.extraArrowBindings.find(dir);
    if (it == config_.extraArrowBindings.end())
      return false;
    for (int v : it->second)
      if ((DWORD)v == norm || (DWORD)v == vkCode)
        return true;
    return false;
  };

  // 1. Left Click Hold/Release
  if (norm == (DWORD)config_.leftClickKey ||
      vkCode == (DWORD)config_.leftClickKey) {
    INPUT inp =
        MakeMouseInput(keyDown ? MOUSEEVENTF_LEFTDOWN : MOUSEEVENTF_LEFTUP);
    SendInput(1, &inp, sizeof(INPUT));

    TriggerEvent(keyDown ? "leftClickDown" : "leftClickUp");
    return true; // Blocks both down and up!
  }

  // 2. Toggle Drag
  if (norm == (DWORD)config_.dragKey || vkCode == (DWORD)config_.dragKey) {
    if (keyDown) {
      SetDragging(!isDragging_.load());
    }
    return true; // Blocks both down and up!
  }

  // 3. Movement Directions (State-based)
  bool isDir = false;
  if (vkCode == VK_UP || isBound("up")) {
    moveUp_ = keyDown;
    isDir = true;
  }
  if (vkCode == VK_DOWN || isBound("down")) {
    moveDown_ = keyDown;
    isDir = true;
  }
  if (vkCode == VK_LEFT || isBound("left")) {
    moveLeft_ = keyDown;
    isDir = true;
  }
  if (vkCode == VK_RIGHT || isBound("right")) {
    moveRight_ = keyDown;
    isDir = true;
  }
  if (isDir)
    return true; // Blocks both down and up!

  // --- CRITICAL FIX ---
  // We handle non-movement actions on Key Down, but we must STILL return true
  // on Key Up so the release event isn't leaked to other applications!

  if (config_.escapeKey != 0 && (norm == (DWORD)config_.escapeKey ||
                                 vkCode == (DWORD)config_.escapeKey)) {
    if (keyDown)
      TriggerEvent("Esc");
    return true;
  }

  if (config_.zoneModeKey != 0 && (norm == (DWORD)config_.zoneModeKey ||
                                   vkCode == (DWORD)config_.zoneModeKey)) {
    if (keyDown)
      TriggerEvent("zoneMode");
    return true;
  }

  if (config_.nextMonitorKey != 0 &&
      (norm == (DWORD)config_.nextMonitorKey ||
       vkCode == (DWORD)config_.nextMonitorKey)) {
    if (keyDown)
      CycleMonitor(1);
    return true;
  }

  if (config_.prevMonitorKey != 0 &&
      (norm == (DWORD)config_.prevMonitorKey ||
       vkCode == (DWORD)config_.prevMonitorKey)) {
    if (keyDown)
      CycleMonitor(-1);
    return true;
  }

  if (config_.infoKey != 0 &&
      (norm == (DWORD)config_.infoKey || vkCode == (DWORD)config_.infoKey)) {
    if (keyDown)
      TriggerEvent("info");
    return true;
  }
  if (config_.toggleOverlayKey != 0 &&
      (norm == (DWORD)config_.toggleOverlayKey ||
       vkCode == (DWORD)config_.toggleOverlayKey)) {
    if (keyDown)
      TriggerEvent("overlay");
    return true;
  }

  if (norm == (DWORD)config_.rightClickKey) {
    if (keyDown)
      PerformRightClick();
    return true;
  }

  // Scroll
  if (norm == (DWORD)config_.scrollUpKey) {
    if (keyDown)
      Scroll(config_.scrollDelta, false);
    return true;
  }
  if (norm == (DWORD)config_.scrollDownKey) {
    if (keyDown)
      Scroll(-config_.scrollDelta, false);
    return true;
  }
  if (norm == (DWORD)config_.scrollLeftKey) {
    if (keyDown)
      Scroll(-config_.scrollDelta, true);
    return true;
  }
  if (norm == (DWORD)config_.scrollRightKey) {
    if (keyDown)
      Scroll(config_.scrollDelta, true);
    return true;
  }

  // 4. Grid Navigation (Letters & Numbers)
  UINT charCode = MapVirtualKeyW(vkCode, MAPVK_VK_TO_CHAR);
  if (charCode != 0) {
    char chLower = (char)tolower((int)charCode);

    for (int i = 0; i < (int)config_.horizontalKeys.size(); ++i) {
      if (config_.horizontalKeys[i] == chLower) {
        if (keyDown)
          TriggerEvent("moveX", {{"index", std::to_string(i)}});
        return true; // Block both down and up steps for grid keys!
      }
    }

    for (int i = 0; i < (int)config_.verticalKeys.size(); ++i) {
      if (config_.verticalKeys[i] == chLower) {
        if (keyDown)
          TriggerEvent("moveY", {{"index", std::to_string(i)}});
        return true; // Block both down and up steps for grid keys!
      }
    }
  }

  // Pass through any other key that isn't mapped to QuickClick features
  return false;
}

void QuickClickController::SetDragging(bool dragging) {
  isDragging_.store(dragging);
  INPUT inp =
      MakeMouseInput(dragging ? MOUSEEVENTF_LEFTDOWN : MOUSEEVENTF_LEFTUP);
  SendInput(1, &inp, sizeof(INPUT));
  TriggerEvent(dragging ? "dragStart" : "dragEnd");
}

void QuickClickController::PerformRightClick() {
  INPUT inputs[2]{};
  inputs[0] = MakeMouseInput(MOUSEEVENTF_RIGHTDOWN);
  inputs[1] = MakeMouseInput(MOUSEEVENTF_RIGHTUP);
  SendInput(2, inputs, sizeof(INPUT));
  TriggerEvent("rightClick");
}

void QuickClickController::Scroll(int delta, bool horizontal) {
  DWORD flags = horizontal ? MOUSEEVENTF_HWHEEL : MOUSEEVENTF_WHEEL;
  INPUT inp = MakeMouseInput(flags, (DWORD)delta);
  SendInput(1, &inp, sizeof(INPUT));
  TriggerEvent("scroll", {{"delta", std::to_string(delta)},
                          {"horizontal", horizontal ? "true" : "false"}});
}

struct MonitorEnumData {
  std::vector<HMONITOR> monitors;
};

static BOOL CALLBACK MonitorEnumProc(HMONITOR hMonitor, HDC hdcMonitor,
                                     LPRECT lprcMonitor, LPARAM dwData) {
  auto *data = reinterpret_cast<MonitorEnumData *>(dwData);
  data->monitors.push_back(hMonitor);
  return TRUE;
}

void QuickClickController::CycleMonitor(int direction) {
  MonitorEnumData data;
  EnumDisplayMonitors(NULL, NULL, MonitorEnumProc,
                      reinterpret_cast<LPARAM>(&data));
  if (data.monitors.empty())
    return;

  // Sort monitors left-to-right
  std::sort(data.monitors.begin(), data.monitors.end(),
            [](HMONITOR a, HMONITOR b) {
              MONITORINFO mia{sizeof(mia)}, mib{sizeof(mib)};
              GetMonitorInfoW(a, &mia);
              GetMonitorInfoW(b, &mib);
              if (mia.rcMonitor.left == mib.rcMonitor.left)
                return mia.rcMonitor.top < mib.rcMonitor.top;
              return mia.rcMonitor.left < mib.rcMonitor.left;
            });

  POINT cur{};
  GetCursorPos(&cur);
  HMONITOR current = MonitorFromPoint(cur, MONITOR_DEFAULTTONEAREST);

  int currentIndex = 0;
  for (int i = 0; i < (int)data.monitors.size(); ++i) {
    if (data.monitors[i] == current) {
      currentIndex = i;
      break;
    }
  }
  int monitorCount = static_cast<int>(data.monitors.size());

  if (monitorCount == 0)
    return;

  int newIndex = (currentIndex + direction + monitorCount) % monitorCount;
  HMONITOR target = data.monitors[newIndex];
  MONITORINFO mi{sizeof(mi)};
  GetMonitorInfoW(target, &mi);

  int centerX =
      mi.rcMonitor.left + (mi.rcMonitor.right - mi.rcMonitor.left) / 2;
  int centerY = mi.rcMonitor.top + (mi.rcMonitor.bottom - mi.rcMonitor.top) / 2;
  SetCursorPos(centerX, centerY);

  TriggerEvent(direction > 0 ? "nextMonitor" : "prevMonitor");
}

QuickClickController::MonitorInfo
QuickClickController::GetMonitorUnderCursor() {
  POINT cur{};
  GetCursorPos(&cur);
  HMONITOR h = MonitorFromPoint(cur, MONITOR_DEFAULTTONEAREST);
  MONITORINFO mi{sizeof(mi)};
  GetMonitorInfoW(h, &mi);
  UINT dx, dy;
  GetDpiForMonitor(h, MDT_EFFECTIVE_DPI, &dx, &dy);
  return {mi.rcMonitor, dx};
}

int QuickClickController::ScaleForDpi(int v, UINT dpi) {
  return MulDiv(v, (int)dpi, 96);
}

INPUT QuickClickController::MakeMouseInput(DWORD flags, DWORD data, LONG dx,
                                           LONG dy) {
  INPUT i{};
  i.type = INPUT_MOUSE;
  i.mi.dwFlags = flags;
  i.mi.mouseData = data;
  i.mi.dx = dx;
  i.mi.dy = dy;
  return i;
}
