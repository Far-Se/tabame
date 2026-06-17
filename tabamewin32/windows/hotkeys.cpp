#ifndef TABAMEWIN32_HOTKEYS
#define TABAMEWIN32_HOTKEYS

#include <ShellAPI.h>
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <psapi.h>
#include <regex>
#include <sstream>
#include <string>
#include <vector>
#include <windows.h>

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
class Hotkey {
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
static std::atomic_bool keyboardBlockerEnabled = false;

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
static bool hasHotkeyMouseBaseline = false;

// Double Alt gesture tracking. The first standalone Alt tap primes the gesture;
// the next Alt press within 100ms becomes the actual hotkey press.
static constexpr int kDoubleAltPrimeTimeoutMs = 100;
static constexpr int kDoubleAltChainTimeoutMs = 300;
static int doubleAltPrimerTimestamp = 0;
static int doubleAltRecognizedReleaseTimestamp = 0;
static bool doubleAltCandidateDown = false;
static bool doubleAltCandidateHadOtherKey = false;
static bool doubleAltCandidateForwardedAltDown = false;
static DWORD doubleAltCandidateVk = 0;
static DWORD doubleAltActiveVk = 0;

// Hook handles for this subsystem
HHOOK g_KeyboardHook = nullptr;
HHOOK g_MouseHook = nullptr;
// Win event hooks — one entry per registered event range (see InstallEventHooks).
std::vector<HWINEVENTHOOK> g_EventHooks;

void SetKeyboardBlockerEnabled(bool enabled) {
  keyboardBlockerEnabled.store(enabled);
}

enum mouseButtons {
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
namespace {
void ResetActiveHotkeyState() {
  activeHotKey = -1;
  hotkeyPressed = false;
  hotkeyCorrectName = false;
  hotkeyName.clear();
  hotkeyStartTimestamp = 0;
  hotkeyStartMousePosX = 0;
  hotkeyStartMousePosY = 0;
  htMousePosX = 0;
  htMousePosY = 0;
  hasHotkeyMouseBaseline = false;
  doubleAltActiveVk = 0;
}

void ClearDoubleAltCandidate() {
  doubleAltCandidateDown = false;
  doubleAltCandidateHadOtherKey = false;
  doubleAltCandidateForwardedAltDown = false;
  doubleAltCandidateVk = 0;
}

void ResetDoubleAltGestureState() {
  ClearDoubleAltCandidate();
  doubleAltPrimerTimestamp = 0;
  doubleAltRecognizedReleaseTimestamp = 0;
  doubleAltActiveVk = 0;
}

const Hotkey *GetActiveHotkey() {
  if (activeHotKey < 0 || activeHotKey >= static_cast<int>(hotkeys.size()))
    return nullptr;

  return &hotkeys[activeHotKey];
}

int GetTimestamp() {
  return static_cast<int>(
      std::chrono::duration_cast<std::chrono::milliseconds>(
          std::chrono::system_clock::now().time_since_epoch())
          .count());
}

void SetAsActiveHotkey(size_t i, HWND /*hwnd*/) {
  activeHotKey = static_cast<int>(i);
  hotkeyStartTimestamp = GetTimestamp();

  POINT pos;
  GetCursorPos(&pos);
  hotkeyStartMousePosX = pos.x;
  hotkeyStartMousePosY = pos.y;
  hotkeyPressed = true;
  hasHotkeyMouseBaseline = false;
}

// Retrieve window info (title, exe name, or class) into |windowInfo|.
void GetWindowInfoByType(HWND hwnd, const std::string &type,
                         wchar_t *windowInfo, int bufSize) {
  if (type == "title") {
    GetWindowText(hwnd, windowInfo, bufSize);
  } else if (type == "exe") {
    DWORD ppID = 0;
    GetWindowThreadProcessId(hwnd, &ppID);
    HANDLE hProcess =
        OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE, ppID);
    if (hProcess != nullptr) {
      wchar_t imgName[1024] = {};
      DWORD bufSz = MAX_PATH;
      if (QueryFullProcessImageName(hProcess, 0, imgName, &bufSz) != 0) {
        GetModuleFileNameEx(hProcess, nullptr, windowInfo, MAX_PATH);
        wchar_t *p = wcsrchr(windowInfo, L'\\');
        if (p != nullptr)
          wcscpy_s(windowInfo, bufSize, p + 1);
      }
      CloseHandle(hProcess);
    }
  } else if (type == "class") {
    GetClassName(hwnd, windowInfo, bufSize);
  }
}

HWND ResolveTargetWindow(const Hotkey &hk) {
  HWND hwnd = GetForegroundWindow();
  hwnd = GetAncestor(hwnd, GA_ROOT);
  if (hk.activateWindowUnderCursor) {
    POINT p;
    GetCursorPos(&p);
    hwnd = WindowFromPoint(p);
    hwnd = GetAncestor(hwnd, GA_ROOT);
  }
  return hwnd;
}

bool IsWindowsKey(DWORD vkCode) {
  return vkCode == VK_LWIN || vkCode == VK_RWIN;
}

bool IsAltKey(DWORD vkCode) {
  return vkCode == VK_MENU || vkCode == VK_LMENU || vkCode == VK_RMENU;
}

bool IsPlainAltGesture(DWORD vkCode) {
  if (!IsAltKey(vkCode))
    return false;

  if (GetAsyncKeyState(VK_CONTROL) & 0x8000)
    return false;
  if (GetAsyncKeyState(VK_SHIFT) & 0x8000)
    return false;
  if ((GetAsyncKeyState(VK_LWIN) & 0x8000) ||
      (GetAsyncKeyState(VK_RWIN) & 0x8000))
    return false;

  return true;
}

bool IsTimestampWithin(int timestamp, int now, int timeoutMs) {
  if (timestamp == 0)
    return false;

  int elapsed = now - timestamp;
  return elapsed >= 0 && elapsed <= timeoutMs;
}

bool HasRegisteredHotkey(const std::wstring &hotkey) {
  return std::any_of(
      hotkeys.begin(), hotkeys.end(),
      [&hotkey](const Hotkey &hk) { return hk.hotkey == hotkey; });
}

bool IsActiveDoubleAltHotkey() {
  const Hotkey *activeHotkey = GetActiveHotkey();
  return hotkeyPressed && activeHotkey != nullptr &&
         activeHotkey->hotkey == L"DOUBLEALT";
}

void SendSyntheticAltModifiedKeyDown(const KBDLLHOOKSTRUCT &keyInfo) {
  INPUT inputs[2] = {};

  inputs[0].type = INPUT_KEYBOARD;
  inputs[0].ki.wVk = VK_MENU;

  inputs[1].type = INPUT_KEYBOARD;
  inputs[1].ki.wVk = static_cast<WORD>(keyInfo.vkCode);
  inputs[1].ki.wScan = static_cast<WORD>(keyInfo.scanCode);
  if (keyInfo.flags & LLKHF_EXTENDED)
    inputs[1].ki.dwFlags = KEYEVENTF_EXTENDEDKEY;

  SendInput(2, inputs, sizeof(INPUT));
}

bool IsModifierKey(DWORD vkCode) {
  switch (vkCode) {
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

std::wstring NormalizePressedKeyName(DWORD vkCode, std::wstring keyName) {
  switch (vkCode) {
  case VK_SPACE:
    return L"SPACE";
  case VK_LEFT:
    return L"LEFT";
  case VK_RIGHT:
    return L"RIGHT";
  case VK_UP:
    return L"UP";
  case VK_DOWN:
    return L"DOWN";
  case VK_NUMPAD0:
    return L"NUMPAD0";
  case VK_NUMPAD1:
    return L"NUMPAD1";
  case VK_NUMPAD2:
    return L"NUMPAD2";
  case VK_NUMPAD3:
    return L"NUMPAD3";
  case VK_NUMPAD4:
    return L"NUMPAD4";
  case VK_NUMPAD5:
    return L"NUMPAD5";
  case VK_NUMPAD6:
    return L"NUMPAD6";
  case VK_NUMPAD7:
    return L"NUMPAD7";
  case VK_NUMPAD8:
    return L"NUMPAD8";
  case VK_NUMPAD9:
    return L"NUMPAD9";
  case VK_MULTIPLY:
    return L"NUMPADMULTIPLY";
  case VK_ADD:
    return L"NUMPADADD";
  case VK_SEPARATOR:
    return L"NUMPADSEPARATOR";
  case VK_SUBTRACT:
    return L"NUMPADSUBTRACT";
  case VK_DECIMAL:
    return L"NUMPADDECIMAL";
  case VK_DIVIDE:
    return L"NUMPADDIVIDE";
  case VK_ESCAPE:
    return L"ESCAPE";
  case VK_RETURN:
    return L"RETURN";
  case VK_BACK:
    return L"BACK";
  case VK_DELETE:
    return L"DELETE";

  case VK_PRIOR:
    return L"PRIOR";
  case VK_NEXT:
    return L"NEXT";

  case VK_INSERT:
    return L"INSERT";

  case VK_CONTROL:
    return L"CONTROL";
  case VK_LCONTROL:
    return L"LCONTROL";
  case VK_RCONTROL:
    return L"RCONTROL";

  case VK_MENU:
    return L"MENU";
  case VK_LMENU:
    return L"LMENU";
  case VK_RMENU:
    return L"RMENU";

  case VK_SHIFT:
    return L"SHIFT";
  case VK_LSHIFT:
    return L"LSHIFT";
  case VK_RSHIFT:
    return L"RSHIFT";

  case VK_LWIN:
    return L"LWIN";
  case VK_RWIN:
    return L"RWIN";

  case VK_CAPITAL:
    return L"CAPITAL";
  case VK_NUMLOCK:
    return L"NUMLOCK";
  case VK_SCROLL:
    return L"SCROLL";

  case VK_SNAPSHOT:
    return L"SNAPSHOT";
  default:
    break;
  }

  if (keyName == L"SPACEBAR")
    return L"SPACE";

  return keyName;
}

bool ActiveHotkeyUsesWindowsKey() {
  const Hotkey *activeHotkey = GetActiveHotkey();
  if (activeHotkey == nullptr)
    return false;

  return activeHotkey->hotkey.find(L"WIN+") != std::wstring::npos;
}

bool ShouldSuppressActiveHotkeyKeyDown(DWORD vkCode) {
  if (!hotkeyPressed)
    return false;

  const Hotkey *activeHotkey = GetActiveHotkey();
  if (activeHotkey == nullptr) {
    ResetActiveHotkeyState();
    return false;
  }

  return activeHotkey->keyVK >= 0 &&
         vkCode == static_cast<DWORD>(activeHotkey->keyVK);
}

bool IsValidRegexMatch(const wchar_t *text, const std::wstring &pattern) {
  try {
    return std::regex_search(text,
                             std::wregex(pattern, std::regex_constants::icase));
  } catch (const std::regex_error &) {
    return false;
  }
}

bool IsActiveXButtonHotkey(mouseButtons button) {
  const Hotkey *activeHotkey = GetActiveHotkey();
  if (activeHotkey == nullptr)
    return false;

  if (button == BTN_XBUTTON1)
    return activeHotkey->hotkey == L"MOUSEBUTTON4";
  if (button == BTN_XBUTTON2)
    return activeHotkey->hotkey == L"MOUSEBUTTON5";
  return false;
}

void NotifySystemWindowsHotkeyUsed() {
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
static bool IsOnProhibitedWindow() {
  const Hotkey *activeHotkey = GetActiveHotkey();
  if (activeHotkey == nullptr)
    return false;

  HWND hwnd = ResolveTargetWindow(*activeHotkey);

  for (const auto &info : activeHotkey->prohibitedWindows) {
    std::vector<std::string> data;
    std::stringstream ss(info);
    std::string token;
    while (std::getline(ss, token, ':'))
      data.push_back(token);

    if (data.size() == 2) {
      wchar_t windowInfo[1024] = {};
      GetWindowInfoByType(hwnd, data[0], windowInfo, 1024);

      std::wstring ws(data[1].begin(), data[1].end());
      if (IsValidRegexMatch(windowInfo, ws))
        return true;
    }
  }
  return false;
}

// ---------------------------------------------------------------------------
// Check all registered hotkeys against the pressed key combination
// ---------------------------------------------------------------------------
static bool CheckForPressedHotKey(const std::wstring &pressedHotkey) {
  bool foundOne = false;
  for (size_t i = 0, e = hotkeys.size(); i != e; ++i) {
    const Hotkey &hk = hotkeys[i];
    if (hk.hotkey != pressedHotkey)
      continue;

    HWND hwnd = ResolveTargetWindow(hk);

    // Match window filter
    if (hk.matchWindowBy.length() > 1) {
      wchar_t windowInfo[1024] = {};
      GetWindowInfoByType(hwnd, hk.matchWindowBy, windowInfo, 1024);

      bool matched = IsValidRegexMatch(windowInfo, hk.matchWindowText);
      if (!matched)
        continue;

      if (hk.anchorType == 0) {
        hotkeyCorrectName = true;
        SetAsActiveHotkey(i, hwnd);
        return true;
      }
    }

    // Region / anchor check
    if (hk.anchorType > 0) {
      POINT lpPoint;
      GetCursorPos(&lpPoint);
      RECT lpRect;

      if (hk.regionOnScreen) {
        HWND desktop = GetDesktopWindow();
        GetWindowRect(desktop, &lpRect);
        while (lpPoint.x >= lpRect.right)
          lpPoint.x -= lpRect.right;
        while (lpPoint.y >= lpRect.bottom)
          lpPoint.y -= lpRect.bottom;
      } else {
        GetWindowRect(hwnd, &lpRect);
      }

      int yTop = lpPoint.y - lpRect.top;
      int yBottom = lpPoint.y - lpRect.bottom;
      int xLeft = lpPoint.x - lpRect.left;
      int xRight = lpPoint.x - lpRect.right;
      int width = lpRect.right - lpRect.left;
      int height = lpRect.bottom - lpRect.top;

      int x = 0, y = 0;
      switch (hk.anchorType) {
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

      if (hk.regionAsPercentage && width > 0 && height > 0) {
        x = static_cast<int>((static_cast<double>(x) / width) * 100);
        y = static_cast<int>((static_cast<double>(y) / height) * 100);
      }

      if (x >= hk.regionX1 && x <= hk.regionX2 && y >= hk.regionY1 &&
          y <= hk.regionY2) {
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
static void HotKeyEvent(const std::string &name, const std::string &info,
                        int vk = 0) {
  const Hotkey *activeHotkey = GetActiveHotkey();
  if (activeHotkey == nullptr) {
    ResetActiveHotkeyState();
    return;
  }

  flutter::EncodableMap args;
  args[flutter::EncodableValue("name")] =
      flutter::EncodableValue(hotkeyCorrectName ? name : "");
  args[flutter::EncodableValue("hotkey")] =
      flutter::EncodableValue(Encoding::WideToUtf8(activeHotkey->hotkey));
  args[flutter::EncodableValue("vk")] = flutter::EncodableValue(vk);
  args[flutter::EncodableValue("info")] = flutter::EncodableValue(info);
  args[flutter::EncodableValue("start")] =
      flutter::EncodableValue(hotkeyStartTimestamp);
  args[flutter::EncodableValue("end")] =
      flutter::EncodableValue(GetTimestamp());
  args[flutter::EncodableValue("sX")] =
      flutter::EncodableValue(hotkeyStartMousePosX);
  args[flutter::EncodableValue("sY")] =
      flutter::EncodableValue(hotkeyStartMousePosY);

  POINT endPos;
  GetCursorPos(&endPos);
  args[flutter::EncodableValue("eX")] =
      flutter::EncodableValue(static_cast<int>(endPos.x));
  args[flutter::EncodableValue("eY")] =
      flutter::EncodableValue(static_cast<int>(endPos.y));

  channel->InvokeMethod("HotKeyEvent",
                        std::make_unique<flutter::EncodableValue>(args));
}

static void TrktivityEvent(const std::string &action, const std::string &info) {
  flutter::EncodableMap args;
  args[flutter::EncodableValue("action")] = flutter::EncodableValue(action);
  args[flutter::EncodableValue("info")] = flutter::EncodableValue(info);
  channel->InvokeMethod("TrktivityEvent",
                        std::make_unique<flutter::EncodableValue>(args));
}

static void ViewsEvent(const std::string &action, HWND hwnd) {
  flutter::EncodableMap args;
  args[flutter::EncodableValue("hwnd")] = flutter::EncodableValue(
      hwnd != nullptr ? static_cast<int64_t>(reinterpret_cast<intptr_t>(hwnd))
                      : static_cast<int64_t>(-1));
  args[flutter::EncodableValue("action")] = flutter::EncodableValue(action);
  channel->InvokeMethod("ViewsEvent",
                        std::make_unique<flutter::EncodableValue>(args));
}

static void WinEvent(const std::string &action, HWND hwnd) {
  flutter::EncodableMap args;
  args[flutter::EncodableValue("hwnd")] = flutter::EncodableValue(
      hwnd != nullptr ? static_cast<int64_t>(reinterpret_cast<intptr_t>(hwnd))
                      : static_cast<int64_t>(-1));
  args[flutter::EncodableValue("action")] = flutter::EncodableValue(action);
  channel->InvokeMethod("WinEvent",
                        std::make_unique<flutter::EncodableValue>(args));
}

// ---------------------------------------------------------------------------
// Check if screen-busy should suppress the hotkey
// ---------------------------------------------------------------------------
static bool ShouldSuppressForScreenBusy() {
  QUERY_USER_NOTIFICATION_STATE state;
  SHQueryUserNotificationState(&state);
  return (state == QUNS_RUNNING_D3D_FULL_SCREEN || state == QUNS_BUSY);
}

static bool ShouldSuppressHotkey() {
  const Hotkey *activeHotkey = GetActiveHotkey();
  if (activeHotkey == nullptr) {
    ResetActiveHotkeyState();
    return true;
  }

  if (activeHotkey->noopScreenBusy && ShouldSuppressForScreenBusy()) {
    ResetActiveHotkeyState();
    return true;
  }
  if (!activeHotkey->prohibitedWindows.empty() && IsOnProhibitedWindow()) {
    ResetActiveHotkeyState();
    return true;
  }
  return false;
}

static bool TryHandleDoubleAltGesture(WPARAM wParam,
                                      const KBDLLHOOKSTRUCT &keyInfo,
                                      LRESULT &result) {
  const bool keyDown = (wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN);
  const bool keyUp = (wParam == WM_KEYUP || wParam == WM_SYSKEYUP);
  if (!keyDown && !keyUp)
    return false;

  const bool isAlt = IsAltKey(keyInfo.vkCode);

  if (IsActiveDoubleAltHotkey()) {
    if (isAlt && keyDown) {
      result = -1;
      return true;
    }

    const bool sameActiveKey =
        doubleAltActiveVk == 0 || doubleAltActiveVk == keyInfo.vkCode ||
        doubleAltActiveVk == VK_MENU || keyInfo.vkCode == VK_MENU;
    if (isAlt && keyUp && sameActiveKey) {
      const Hotkey *activeHotkey = GetActiveHotkey();
      if (activeHotkey != nullptr)
        HotKeyEvent(activeHotkey->name, "released");
      ResetActiveHotkeyState();
      doubleAltRecognizedReleaseTimestamp = GetTimestamp();
      result = -1;
      return true;
    }

    return false;
  }

  if (doubleAltCandidateDown && keyDown && !isAlt) {
    if (!doubleAltCandidateForwardedAltDown) {
      SendSyntheticAltModifiedKeyDown(keyInfo);
      doubleAltCandidateForwardedAltDown = true;
      doubleAltCandidateHadOtherKey = true;
      doubleAltPrimerTimestamp = 0;
      doubleAltRecognizedReleaseTimestamp = 0;
      result = -1;
      return true;
    }
    doubleAltCandidateHadOtherKey = true;
    doubleAltPrimerTimestamp = 0;
    doubleAltRecognizedReleaseTimestamp = 0;
    return false;
  }

  if (!isAlt)
    return false;

  if (!HasRegisteredHotkey(L"DOUBLEALT")) {
    ResetDoubleAltGestureState();
    return false;
  }

  if (!IsPlainAltGesture(keyInfo.vkCode)) {
    ResetDoubleAltGestureState();
    return false;
  }

  if (keyDown) {
    if (doubleAltCandidateDown) {
      result = -1;
      return true;
    }

    if (hotkeyPressed)
      return false;

    const int now = GetTimestamp();
    const bool shouldTrigger =
        IsTimestampWithin(doubleAltPrimerTimestamp, now,
                          kDoubleAltPrimeTimeoutMs) ||
        IsTimestampWithin(doubleAltRecognizedReleaseTimestamp, now,
                          kDoubleAltChainTimeoutMs);

    if (shouldTrigger) {
      ClearDoubleAltCandidate();
      doubleAltPrimerTimestamp = 0;
      doubleAltActiveVk = keyInfo.vkCode;

      if (CheckForPressedHotKey(L"DOUBLEALT")) {
        if (!ShouldSuppressHotkey()) {
          const Hotkey *activeHotkey = GetActiveHotkey();
          if (activeHotkey != nullptr) {
            HotKeyEvent(activeHotkey->name, "pressed");
            result = -1;
            return true;
          }
        }
      }

      ResetActiveHotkeyState();
      doubleAltCandidateDown = true;
      doubleAltCandidateVk = keyInfo.vkCode;
      result = -1;
      return true;
    }

    doubleAltCandidateDown = true;
    doubleAltCandidateHadOtherKey = false;
    doubleAltCandidateForwardedAltDown = false;
    doubleAltCandidateVk = keyInfo.vkCode;
    result = -1;
    return true;
  }

  if (keyUp && doubleAltCandidateDown) {
    const bool sameCandidateKey = doubleAltCandidateVk == 0 ||
                                  doubleAltCandidateVk == keyInfo.vkCode ||
                                  IsAltKey(doubleAltCandidateVk);

    if (!doubleAltCandidateHadOtherKey && sameCandidateKey) {
      ClearDoubleAltCandidate();
      doubleAltPrimerTimestamp = GetTimestamp();
      result = -1;
      return true;
    }

    ClearDoubleAltCandidate();
    return false;
  }

  return false;
}

// ---------------------------------------------------------------------------
// Keyboard hook callback
// ---------------------------------------------------------------------------
LRESULT CALLBACK HandleKeyboardHook(int nCode, WPARAM wParam, LPARAM lParam) {
  if (nCode < 0)
    return CallNextHookEx(g_KeyboardHook, nCode, wParam, lParam);

  if (keyboardBlockerEnabled.load())
    return 1;

  KBDLLHOOKSTRUCT keyInfo = *reinterpret_cast<KBDLLHOOKSTRUCT *>(lParam);

  if (keyInfo.flags & LLKHF_INJECTED)
    return CallNextHookEx(g_KeyboardHook, nCode, wParam, lParam);

  const bool keyDown = (wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN);
  const bool keyUp = (wParam == WM_KEYUP || wParam == WM_SYSKEYUP);

  if (keyInfo.vkCode == VK_RMENU && HasRegisteredHotkey(L"RIGHTALT")) {
    if (keyDown) {
      if (!hotkeyPressed) {
        if (CheckForPressedHotKey(L"RIGHTALT")) {
          if (!ShouldSuppressHotkey()) {
            const Hotkey *activeHotkey = GetActiveHotkey();
            if (activeHotkey != nullptr) {
              HotKeyEvent(activeHotkey->name, "pressed");
              return -1;
            }
          }
          ResetActiveHotkeyState();
        }
      } else {
        const Hotkey *activeHotkey = GetActiveHotkey();
        if (activeHotkey != nullptr && activeHotkey->hotkey == L"RIGHTALT") {
          return -1;
        }
      }
    } else if (keyUp) {
      if (hotkeyPressed) {
        const Hotkey *activeHotkey = GetActiveHotkey();
        if (activeHotkey != nullptr && activeHotkey->hotkey == L"RIGHTALT") {
          HotKeyEvent(activeHotkey->name, "released");
          ResetActiveHotkeyState();
          return -1;
        }
      }
    }
    return CallNextHookEx(nullptr, nCode, wParam, lParam);
  }

  if (keyInfo.vkCode == VK_RCONTROL && HasRegisteredHotkey(L"RIGHTCONTROL")) {
    if (keyDown) {
      if (!hotkeyPressed) {
        if (CheckForPressedHotKey(L"RIGHTCONTROL")) {
          if (!ShouldSuppressHotkey()) {
            const Hotkey *activeHotkey = GetActiveHotkey();
            if (activeHotkey != nullptr) {
              HotKeyEvent(activeHotkey->name, "pressed");
              return -1;
            }
          }
          ResetActiveHotkeyState();
        }
      } else {
        const Hotkey *activeHotkey = GetActiveHotkey();
        if (activeHotkey != nullptr &&
            activeHotkey->hotkey == L"RIGHTCONTROL") {
          return -1;
        }
      }
    } else if (keyUp) {
      if (hotkeyPressed) {
        const Hotkey *activeHotkey = GetActiveHotkey();
        if (activeHotkey != nullptr &&
            activeHotkey->hotkey == L"RIGHTCONTROL") {
          HotKeyEvent(activeHotkey->name, "released");
          ResetActiveHotkeyState();
          return -1;
        }
      }
    }
    return CallNextHookEx(nullptr, nCode, wParam, lParam);
  }

  LRESULT doubleAltResult = 0;
  if (TryHandleDoubleAltGesture(wParam, keyInfo, doubleAltResult))
    return doubleAltResult;

  if ((wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN) && hotkeyPressed) {
    if (ShouldSuppressActiveHotkeyKeyDown(keyInfo.vkCode))
      return -1;
  }

  if ((wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN) && !hotkeyPressed) {
    std::wstring pressedHotkey;
    if (GetAsyncKeyState(VK_CONTROL) & 0x8000)
      pressedHotkey.append(L"CTRL+");
    if (GetAsyncKeyState(VK_MENU) & 0x8000)
      pressedHotkey.append(L"ALT+");
    if (GetAsyncKeyState(VK_SHIFT) & 0x8000)
      pressedHotkey.append(L"SHIFT+");
    if ((GetAsyncKeyState(VK_LWIN) & 0x8000) ||
        (GetAsyncKeyState(VK_RWIN) & 0x8000))
      pressedHotkey.append(L"WIN+");

    wchar_t buffer[32] = {};
    UINT key = (keyInfo.scanCode << 16);
    GetKeyNameText(static_cast<LONG>(key), buffer, 32);

    std::wstring keyName(buffer);
    std::transform(keyName.begin(), keyName.end(), keyName.begin(),
                   [](wchar_t c) -> wchar_t {
                     return static_cast<wchar_t>(::toupper(c));
                   });
    keyName = NormalizePressedKeyName(keyInfo.vkCode, std::move(keyName));

    pressedHotkey.append(keyName);

    if (CheckForPressedHotKey(pressedHotkey)) {
      if (ShouldSuppressHotkey())
        return CallNextHookEx(nullptr, nCode, wParam, lParam);

      const Hotkey *activeHotkey = GetActiveHotkey();
      if (activeHotkey == nullptr) {
        ResetActiveHotkeyState();
        return CallNextHookEx(nullptr, nCode, wParam, lParam);
      }

      if (ActiveHotkeyUsesWindowsKey())
        NotifySystemWindowsHotkeyUsed();

      hotkeyName = pressedHotkey;
      HotKeyEvent(activeHotkey->name, "pressedKbd");
      return -1;
    }
    return CallNextHookEx(nullptr, nCode, wParam, lParam);
  } else if (wParam == WM_KEYUP || wParam == WM_SYSKEYUP) {
    // Trcktivity keyboard tracking
    if (isTrcktivityEnabled) {
      if (kbdTime == 0)
        kbdTime = keyInfo.time;
      if (static_cast<int>(keyInfo.time) - kbdTime < 10000) {
        kbdPressCount++;
      } else {
        TrktivityEvent("Keys", std::to_string(kbdPressCount));
        kbdTime = keyInfo.time;
        kbdPressCount = 0;
      }
    }

    // Release the active keyboard hotkey immediately in native code so
    // quick re-presses do not race against an async Dart round-trip.
    if (hotkeyPressed && ShouldSuppressActiveHotkeyKeyDown(keyInfo.vkCode)) {
      const Hotkey *activeHotkey = GetActiveHotkey();
      if (activeHotkey != nullptr)
        HotKeyEvent(activeHotkey->name, "releaseKbd", keyInfo.vkCode);
      ResetActiveHotkeyState();
      return -1;
    }
  }

  return CallNextHookEx(nullptr, nCode, wParam, lParam);
}

// ---------------------------------------------------------------------------
// Mouse hook callback (hotkey-aware)
// ---------------------------------------------------------------------------
LRESULT CALLBACK HandleMouseHook(int nCode, WPARAM wParam, LPARAM lParam) {
  if (nCode != HC_ACTION)
    return CallNextHookEx(nullptr, nCode, wParam, lParam);

  MSLLHOOKSTRUCT *info = reinterpret_cast<MSLLHOOKSTRUCT *>(lParam);

  // ---- Mouse movement ----
  if (wParam == WM_MOUSEMOVE) {
    if (hotkeyPressed) {
      if (GetActiveHotkey() == nullptr) {
        ResetActiveHotkeyState();
        return CallNextHookEx(nullptr, nCode, wParam, lParam);
      }

      POINT lpPoint;
      GetCursorPos(&lpPoint);
      if (!hasHotkeyMouseBaseline) {
        htMousePosX = lpPoint.x;
        htMousePosY = lpPoint.y;
        hasHotkeyMouseBaseline = true;
      }

      int diffX = lpPoint.x - htMousePosX;
      int diffY = lpPoint.y - htMousePosY;

      if (abs(diffX) > 10 || abs(diffY) > 10) {
        const Hotkey *activeHotkey = GetActiveHotkey();
        if (activeHotkey != nullptr)
          HotKeyEvent(activeHotkey->name, "moved");
        else
          ResetActiveHotkeyState();
        htMousePosX = 0;
        htMousePosY = 0;
        hasHotkeyMouseBaseline = false;
      }
    }
    if (isTrcktivityEnabled) {
      if (trckMovementX == 0)
        trckMovementX = info->pt.x;
      if (trckMovementY == 0)
        trckMovementY = info->pt.y;
      if (trkTimestamp == 0)
        trkTimestamp = info->time;

      trckMovementX = info->pt.x;
      trckMovementY = info->pt.y;
      int timeDiff = info->time - trkTimestamp;
      if (timeDiff > 3000) {
        trkTimestamp = info->time;
        TrktivityEvent("Movement", "mouse");
      }
    }
  }

  // ---- Button classification ----
  bool down = false;
  mouseButtons button = BTN_NONE;
  switch (wParam) {
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
  if (isViewsEnabled && button == BTN_RIGHT) {
    if (viewsState == 1 && !down) {
      viewsState = 2;
      ViewsEvent("open", nullptr);
    } else if (viewsState == 2 && down) {
      viewsState = 3;
      ViewsEvent("selecting", nullptr);
    } else if (viewsState == 3 && !down) {
      viewsState = 2;
      ViewsEvent("selected", nullptr);
    }
  }
  if (isViewsEnabled && (button == BTN_SWUP || button == BTN_SWDOWN) &&
      viewsState >= 2) {
    ViewsEvent(button == BTN_SWUP ? "switchUp" : "switchDown", nullptr);
  }

  // ---- XButton hotkey handling ----
  if (button != BTN_NONE) {
    if (button == BTN_XBUTTON1 && HIWORD(info->mouseData) == 2)
      button = BTN_XBUTTON2;

    int bID = static_cast<int>(button);
    if (bID == 5 || bID == 6) {
      if (down) {
        bool result = (bID == 5) ? CheckForPressedHotKey(L"MOUSEBUTTON4")
                                 : CheckForPressedHotKey(L"MOUSEBUTTON5");
        if (result) {
          if (ShouldSuppressHotkey())
            return CallNextHookEx(nullptr, nCode, wParam, lParam);

          const Hotkey *activeHotkey = GetActiveHotkey();
          if (activeHotkey == nullptr) {
            ResetActiveHotkeyState();
            return CallNextHookEx(nullptr, nCode, wParam, lParam);
          }

          HotKeyEvent(activeHotkey->name, "pressed");
          return -1;
        }
      } else if (hotkeyPressed && IsActiveXButtonHotkey(button)) {
        const Hotkey *activeHotkey = GetActiveHotkey();
        if (activeHotkey != nullptr)
          HotKeyEvent(activeHotkey->name, "released");
        ResetActiveHotkeyState();
        return 1;
      }
    }
  }

  return CallNextHookEx(nullptr, nCode, wParam, lParam);
}

// ---------------------------------------------------------------------------
// Win event hook callback
// ---------------------------------------------------------------------------
VOID CALLBACK EventHook(HWINEVENTHOOK /*hWinEventHook*/, DWORD dwEvent,
                        HWND hwnd, LONG /*idObject*/, LONG /*idChild*/,
                        DWORD /*dwEventThread*/, DWORD /*dwmsEventTime*/) {
  if (dwEvent == EVENT_SYSTEM_FOREGROUND)
    WinEvent("foreground", hwnd);

  if (isTrcktivityEnabled && dwEvent == EVENT_OBJECT_NAMECHANGE) {
    if (reinterpret_cast<DWORD_PTR>(hwnd) == 0)
      return;
    if (GetForegroundWindow() == hwnd)
      WinEvent("namechange", hwnd);
  }

  if (isViewsEnabled) {
    if (dwEvent == EVENT_SYSTEM_MOVESIZESTART) {
      ViewsEvent("moveStart", hwnd);
      movingWindow = hwnd;
      viewsState = 1;
    } else if (dwEvent == EVENT_SYSTEM_MOVESIZEEND) {
      ViewsEvent("moveEnd", hwnd);
      movingWindow = nullptr;
      viewsState = 0;
    }
  }
}

// ---------------------------------------------------------------------------
// Win event hook install / uninstall
// ---------------------------------------------------------------------------
// Register only the specific events EventHook() actually consumes. Registering
// the full EVENT_MIN..EVENT_MAX range would invoke the callback for every
// accessibility event system-wide — most notably EVENT_OBJECT_LOCATIONCHANGE,
// which fires on every mouse move/caret blink — adding needless overhead to the
// whole OS input pipeline. MOVESIZESTART/MOVESIZEEND are contiguous so they
// share one range; NAMECHANGE uses a single-event range to exclude the adjacent
// (and very noisy) LOCATIONCHANGE.
void InstallEventHooks() {
  static const struct {
    DWORD eventMin;
    DWORD eventMax;
  } kRanges[] = {
      {EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND},
      {EVENT_SYSTEM_MOVESIZESTART, EVENT_SYSTEM_MOVESIZEEND},
      {EVENT_OBJECT_NAMECHANGE, EVENT_OBJECT_NAMECHANGE},
  };

  if (!g_EventHooks.empty())
    return;

  for (const auto &range : kRanges) {
    HWINEVENTHOOK hook =
        SetWinEventHook(range.eventMin, range.eventMax, nullptr, EventHook, 0, 0,
                        WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);
    if (hook)
      g_EventHooks.push_back(hook);
  }
}

void UninstallEventHooks() {
  for (HWINEVENTHOOK hook : g_EventHooks)
    UnhookWinEvent(hook);
  g_EventHooks.clear();
}

#endif // TABAMEWIN32_HOTKEYS
