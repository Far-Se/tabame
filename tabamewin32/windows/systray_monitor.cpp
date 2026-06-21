#pragma once
#ifndef UNICODE
#define UNICODE
#endif

#include <algorithm>
#include <atomic>
#include <commctrl.h>
#include <mutex>
#include <shellapi.h>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>
#include <windows.h>
#include <cwctype>

#include "include/encoding.h"

#ifndef NIS_HIDDEN
#define NIS_HIDDEN 0x00000001
#endif

namespace SystrayMonitorNative {

constexpr wchar_t kMonitorClassName[] = L"Shell_TrayWnd";
constexpr wchar_t kMonitorWindowTitle[] = L"TabameSystrayMonitor";

#pragma pack(push, 1)
struct NotifyIconDataWire {
  DWORD cbSize;
  DWORD hWnd;
  DWORD uID;
  DWORD uFlags;
  DWORD uCallbackMessage;
  DWORD hIcon;
  WCHAR szTip[128];
  DWORD dwState;
  DWORD dwStateMask;
  WCHAR szInfo[256];
  union {
    UINT uTimeout;
    UINT uVersion;
  } anonymous;
  WCHAR szInfoTitle[64];
  DWORD dwInfoFlags;
  GUID guidItem;
  DWORD hBalloonIcon;
};

struct ShellTrayDataWire {
  DWORD dwSignature;
  DWORD dwMessage;
  NotifyIconDataWire iconData;
};

struct WinNotifyIconIdentifierWire {
  DWORD message;
  DWORD hWnd;
  DWORD uID;
  GUID guidItem;
};
#pragma pack(pop)

struct MonitorIcon {
  ExtTrayIcon icon;
  UINT uVersion = 0;
  UINT messageType = 0;
};

static std::mutex g_mutex;
static std::unordered_map<std::wstring, MonitorIcon> g_icons;
static std::thread g_thread;
static std::atomic<bool> g_running{false};
static std::atomic<bool> g_ready{false};
static HWND g_hwnd = nullptr;
static HWND g_realTray = nullptr;

static UINT TaskbarCreatedMessage() {
  static const UINT message = RegisterWindowMessageW(L"TaskbarCreated");
  return message;
}

static int PackI32(int low, int high) {
  return static_cast<int>((low & 0xFFFF) | ((high & 0xFFFF) << 16));
}

static std::wstring ToLower(std::wstring value) {
  std::transform(value.begin(), value.end(), value.begin(),
                 [](wchar_t c) { return static_cast<wchar_t>(towlower(c)); });
  return value;
}

static std::wstring GetProcessPathFromHwnd(HWND hwnd) {
  DWORD pid = 0;
  GetWindowThreadProcessId(hwnd, &pid);
  if (pid == 0)
    return L"";

  HANDLE process =
      OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (!process)
    return L"";

  wchar_t buffer[MAX_PATH * 4]{};
  DWORD size = static_cast<DWORD>(MAX_PATH * 4);
  std::wstring result;
  if (QueryFullProcessImageNameW(process, 0, buffer, &size)) {
    result.assign(buffer, size);
  }
  CloseHandle(process);
  return result;
}

static bool IsExplorerWindow(HWND hwnd) {
  const std::wstring path = ToLower(GetProcessPathFromHwnd(hwnd));
  if (path.empty())
    return false;
  const size_t slash = path.find_last_of(L"\\/");
  const std::wstring base = slash == std::wstring::npos
                                ? path
                                : path.substr(slash + 1);
  return base == L"explorer.exe";
}

static HWND FindRealTrayHwnd(HWND ignoredHwnd) {
  HWND hwnd = nullptr;
  while (true) {
    hwnd = FindWindowExW(nullptr, hwnd, kMonitorClassName, nullptr);
    if (!hwnd)
      break;
    if (hwnd == ignoredHwnd)
      continue;
    if (IsExplorerWindow(hwnd))
      return hwnd;
  }
  return nullptr;
}

static std::wstring GuidToString(const GUID &guid) {
  wchar_t buffer[64]{};
  if (StringFromGUID2(guid, buffer, 64) > 0)
    return buffer;
  return L"";
}

static bool IsZeroGuid(const GUID &guid) {
  static const GUID zero{};
  return memcmp(&guid, &zero, sizeof(GUID)) == 0;
}

static std::wstring IconKey(HWND hwnd, UINT uID, const GUID &guid,
                            bool hasGuid) {
  if (hasGuid && !IsZeroGuid(guid))
    return L"guid:" + GuidToString(guid);
  return L"hwnd:" + std::to_wstring(reinterpret_cast<LONG_PTR>(hwnd)) +
         L":uid:" + std::to_wstring(uID);
}

static std::wstring ReadNullTerminated(const WCHAR *value, size_t length) {
  size_t end = 0;
  while (end < length && value[end] != L'\0')
    ++end;
  return std::wstring(value, end);
}

static void UpsertIcon(const ShellTrayDataWire &trayData) {
  const NotifyIconDataWire &nid = trayData.iconData;
  const HWND hwnd =
      reinterpret_cast<HWND>(static_cast<ULONG_PTR>(nid.hWnd));
  const UINT uID = static_cast<UINT>(nid.uID);
  const bool hasGuid = (nid.uFlags & NIF_GUID) != 0;
  const std::wstring key = IconKey(hwnd, uID, nid.guidItem, hasGuid);

  MonitorIcon next;
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    const auto existing = g_icons.find(key);
    if (existing != g_icons.end())
      next = existing->second;
  }

  next.messageType = static_cast<UINT>(trayData.dwMessage);
  next.icon.appHwnd = hwnd;
  next.icon.uID = uID;
  next.icon.isVisible = true;
  next.icon.isOverflow = false;

  DWORD processId = 0;
  if (hwnd)
    GetWindowThreadProcessId(hwnd, &processId);
  next.icon.processId = static_cast<int>(processId);

  if ((nid.uFlags & NIF_MESSAGE) != 0)
    next.icon.uCallbackMsg = static_cast<UINT>(nid.uCallbackMessage);
  if ((nid.uFlags & NIF_ICON) != 0)
    next.icon.hIcon =
        reinterpret_cast<HICON>(static_cast<ULONG_PTR>(nid.hIcon));
  if ((nid.uFlags & NIF_TIP) != 0)
    next.icon.toolTip = ReadNullTerminated(nid.szTip, std::size(nid.szTip));
  if ((nid.uFlags & NIF_STATE) != 0 && (nid.dwStateMask & NIS_HIDDEN) != 0)
    next.icon.isVisible = (nid.dwState & NIS_HIDDEN) == 0;
  if (trayData.dwMessage == NIM_SETVERSION && nid.anonymous.uVersion <= 4)
    next.uVersion = nid.anonymous.uVersion;

  std::lock_guard<std::mutex> lock(g_mutex);
  g_icons[key] = next;
}

static void DeleteIcon(const ShellTrayDataWire &trayData) {
  const NotifyIconDataWire &nid = trayData.iconData;
  const HWND hwnd =
      reinterpret_cast<HWND>(static_cast<ULONG_PTR>(nid.hWnd));
  const bool hasGuid = (nid.uFlags & NIF_GUID) != 0;
  const std::wstring key =
      IconKey(hwnd, static_cast<UINT>(nid.uID), nid.guidItem, hasGuid);

  std::lock_guard<std::mutex> lock(g_mutex);
  g_icons.erase(key);
}

static void SeedFromExplorerToolbar() {
  const std::vector<ExtTrayIcon> current = EnumAllTrayIcons();
  std::lock_guard<std::mutex> lock(g_mutex);
  for (const ExtTrayIcon &icon : current) {
    const std::wstring key =
        IconKey(icon.appHwnd, icon.uID, GUID{}, false);
    MonitorIcon monitorIcon;
    const auto existing = g_icons.find(key);
    if (existing != g_icons.end())
      monitorIcon = existing->second;
    monitorIcon.icon = icon;
    g_icons[key] = monitorIcon;
  }
}

static LRESULT ForwardMessage(HWND hwnd, UINT msg, WPARAM wParam,
                              LPARAM lParam) {
  if (!g_realTray || !IsWindow(g_realTray))
    g_realTray = FindRealTrayHwnd(hwnd);
  if (!g_realTray)
    return DefWindowProcW(hwnd, msg, wParam, lParam);
  if (msg == WM_USER + 372) {
    PostMessageW(g_realTray, msg, wParam, lParam);
    return DefWindowProcW(hwnd, msg, wParam, lParam);
  }
  return SendMessageW(g_realTray, msg, wParam, lParam);
}

static LRESULT HandleCopyData(HWND hwnd, UINT msg, WPARAM wParam,
                              LPARAM lParam) {
  auto *copyData = reinterpret_cast<COPYDATASTRUCT *>(lParam);
  if (!copyData || copyData->cbData == 0)
    return 0;

  if (copyData->dwData == 1 &&
      copyData->cbData >= sizeof(ShellTrayDataWire) && copyData->lpData) {
    auto *trayData = reinterpret_cast<ShellTrayDataWire *>(copyData->lpData);
    if (trayData->dwMessage == NIM_ADD ||
        trayData->dwMessage == NIM_MODIFY ||
        trayData->dwMessage == NIM_SETVERSION) {
      UpsertIcon(*trayData);
    } else if (trayData->dwMessage == NIM_DELETE) {
      DeleteIcon(*trayData);
    }
    return ForwardMessage(hwnd, msg, wParam, lParam);
  }

  if (copyData->dwData == 3 && copyData->lpData &&
      copyData->cbData >= sizeof(WinNotifyIconIdentifierWire)) {
    auto *identifier =
        reinterpret_cast<WinNotifyIconIdentifierWire *>(copyData->lpData);
    POINT cursor{};
    GetCursorPos(&cursor);
    if (identifier->message == 1)
      return PackI32(cursor.x, cursor.y + 1);
    if (identifier->message == 2)
      return PackI32(cursor.x + 1, cursor.y - 1);
    return 0;
  }

  return ForwardMessage(hwnd, msg, wParam, lParam);
}

static LRESULT CALLBACK WindowProc(HWND hwnd, UINT msg, WPARAM wParam,
                                   LPARAM lParam) {
  if (msg == WM_CLOSE) {
    DestroyWindow(hwnd);
    return 0;
  }
  if (msg == WM_DESTROY) {
    KillTimer(hwnd, 1);
    g_hwnd = nullptr;
    PostQuitMessage(0);
    return 0;
  }
  if (msg == TaskbarCreatedMessage()) {
    SetPropW(hwnd, L"TaskbandHWND", hwnd);
    g_realTray = nullptr;
    return 0;
  }
  if (msg == WM_TIMER) {
    SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    return 0;
  }
  if (msg == WM_COPYDATA)
    return HandleCopyData(hwnd, msg, wParam, lParam);
  if (msg == WM_ACTIVATEAPP || msg == WM_COMMAND || msg >= WM_USER)
    return ForwardMessage(hwnd, msg, wParam, lParam);
  return DefWindowProcW(hwnd, msg, wParam, lParam);
}

static void MessageThread() {
  WNDCLASSW wc{};
  wc.lpfnWndProc = WindowProc;
  wc.hInstance = GetModuleHandleW(nullptr);
  wc.lpszClassName = kMonitorClassName;
  if (!RegisterClassW(&wc) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
    g_running = false;
    g_ready = false;
    return;
  }

  HWND hwnd = CreateWindowExW(
      WS_EX_TOOLWINDOW | WS_EX_TOPMOST, kMonitorClassName,
      kMonitorWindowTitle, WS_POPUP | WS_CLIPCHILDREN | WS_CLIPSIBLINGS, 0, 0,
      0, 0, nullptr, nullptr, wc.hInstance, nullptr);
  if (!hwnd) {
    g_running = false;
    g_ready = false;
    return;
  }

  g_hwnd = hwnd;
  SetPropW(hwnd, L"TaskbandHWND", hwnd);
  SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  SetTimer(hwnd, 1, 100, nullptr);
  g_ready = true;

  MSG message{};
  while (GetMessageW(&message, nullptr, 0, 0) > 0) {
    TranslateMessage(&message);
    DispatchMessageW(&message);
  }

  g_ready = false;
  g_running = false;
}

} // namespace SystrayMonitorNative

bool StartSystrayMonitor() {
  using namespace SystrayMonitorNative;
  if (g_running)
    return true;

  SeedFromExplorerToolbar();
  g_running = true;
  g_ready = false;
  g_thread = std::thread(MessageThread);

  for (int i = 0; i < 20; ++i) {
    if (g_ready)
      return true;
    if (!g_running)
      break;
    Sleep(25);
  }
  if (!g_running && g_thread.joinable())
    g_thread.join();
  return g_ready;
}

bool StopSystrayMonitor() {
  using namespace SystrayMonitorNative;
  if (!g_running) {
    if (g_thread.joinable())
      g_thread.join();
    return true;
  }
  HWND hwnd = g_hwnd;
  if (hwnd)
    PostMessageW(hwnd, WM_CLOSE, 0, 0);
  if (g_thread.joinable())
    g_thread.join();
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    g_icons.clear();
  }
  g_realTray = nullptr;
  g_running = false;
  g_ready = false;
  return true;
}

std::vector<ExtTrayIcon> SnapshotSystrayMonitorIcons() {
  using namespace SystrayMonitorNative;
  bool isEmpty = false;
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    isEmpty = g_icons.empty();
  }
  if (isEmpty)
    SeedFromExplorerToolbar();

  std::vector<ExtTrayIcon> snapshot;
  std::lock_guard<std::mutex> lock(g_mutex);
  snapshot.reserve(g_icons.size());
  for (const auto &entry : g_icons)
    snapshot.push_back(entry.second.icon);
  return snapshot;
}
