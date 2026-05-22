#pragma once

#define WIN32_LEAN_AND_MEAN
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <functional>
#include <map>
#include <shellscalingapi.h>
#include <string>
#include <thread>
#include <vector>
#include <windows.h>

struct QuickClickConfig {
  std::vector<char> horizontalKeys = {'1', '2', '3', '4', '5',
                                      '6', '7', '8', '9'};
  std::vector<char> verticalKeys = {'q', 'w', 'e', 'r', 't',
                                    'y', 'u', 'i', 'o'};

  int nudgeAmount = 5; // Base speed
  int shiftNudgeAmount = 25;
  int doubleClickThresholdMs = 400;

  std::map<std::string, std::vector<int>> extraArrowBindings = {
      {"up", {}}, {"down", {}}, {"left", {}}, {"right", {}}};

  int leftClickKey = VK_CONTROL;
  int rightClickKey = VK_MENU;
  int dragKey = VK_MENU;

  int scrollUpKey = VK_OEM_4;
  int scrollDownKey = VK_OEM_6;
  int scrollLeftKey = VK_OEM_1;
  int scrollRightKey = VK_OEM_7;

  int scrollDelta = WHEEL_DELTA;

  int escapeKey = VK_ESCAPE;
  int zoneModeKey = 0;
  int nextMonitorKey = 0;
  int prevMonitorKey = 0;
  int toggleOverlayKey = 0;
  int infoKey = VK_OEM_2; // VK_OEM_2 is usually '/' or '?'
};

class QuickClickController {
public:
  explicit QuickClickController(QuickClickConfig config = {});
  ~QuickClickController();

  void Start();
  void Stop();
  void SetActive(bool active);
  bool IsActive() const { return active_.load(); }
  void UpdateConfig(QuickClickConfig config);
  void SetEventCallback(
      std::function<void(const std::string &,
                         const std::map<std::string, std::string> &)>
          callback) {
    eventCallback_ = callback;
  }

private:
  void TriggerEvent(const std::string &eventName,
                    const std::map<std::string, std::string> &params = {}) {
    if (eventCallback_)
      eventCallback_(eventName, params);
  }

  static LRESULT CALLBACK LowLevelKeyboardProc(int nCode, WPARAM wParam,
                                               LPARAM lParam);
  void HookThreadProc();

  // Continuous movement thread logic
  void MovementThreadProc();

  bool HandleKey(DWORD vkCode, bool keyDown);
  void MoveToGridX(int index);
  void MoveToGridY(int index);
  void PerformRightClick();
  void SetDragging(bool dragging);
  void Scroll(int delta, bool horizontal);
  void CycleMonitor(int direction);

  struct MonitorInfo {
    RECT rect;
    UINT dpi;
  };
  static MonitorInfo GetMonitorUnderCursor();
  static int ScaleForDpi(int value, UINT dpi);
  static INPUT MakeMouseInput(DWORD flags, DWORD mouseData = 0, LONG dx = 0,
                              LONG dy = 0);

  QuickClickConfig config_;
  std::atomic<bool> active_{false};
  std::atomic<bool> isDragging_{false};
  std::atomic<bool> running_{false};

  // Directional states for diagonal movement
  std::atomic<bool> moveUp_{false};
  std::atomic<bool> moveDown_{false};
  std::atomic<bool> moveLeft_{false};
  std::atomic<bool> moveRight_{false};

  HHOOK hook_{nullptr};
  std::thread hookThread_;
  std::thread moveThread_;
  DWORD hookThreadId_{0};

  std::function<void(const std::string &,
                     const std::map<std::string, std::string> &)>
      eventCallback_;
  static QuickClickController *s_instance;
};
