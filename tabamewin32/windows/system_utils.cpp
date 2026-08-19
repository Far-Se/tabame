#ifndef TABAMEWIN32_SYSTEM_UTILS
#define TABAMEWIN32_SYSTEM_UTILS

#include <ShellAPI.h>
#include <VersionHelpers.h>
#include <comdef.h>
#include <fstream>
#include <iostream>
#include <map>
#include <shobjidl.h>
#include <string>
#include <wbemidl.h>
#include <windows.h>

#pragma comment(lib, "wbemuuid.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "oleaut32.lib")

// ---------------------------------------------------------------------------
// Debug logging
// ---------------------------------------------------------------------------
static bool debugging = false;
static std::string debugFile;

void appendLineToFile(const std::string &name, const std::string &content) {
  if (!debugging)
    return;
  std::ofstream outfile;
  outfile.open(name, std::ios_base::app);
  outfile << content << std::endl;
  outfile.close();
}

// ---------------------------------------------------------------------------
// Windows version check
// ---------------------------------------------------------------------------
#define _WIN32_WINNT_WIN11 0x0B00

bool IsWindows11OrGreater() {
  return IsWindowsVersionOrGreater(HIBYTE(_WIN32_WINNT_WIN11),
                                   LOBYTE(_WIN32_WINNT_WIN11), 0);
}

// ---------------------------------------------------------------------------
// CPU load measurement
// ---------------------------------------------------------------------------
namespace {
unsigned long long FileTimeToInt64(const FILETIME &ft) {
  return (static_cast<unsigned long long>(ft.dwHighDateTime) << 32) |
         static_cast<unsigned long long>(ft.dwLowDateTime);
}

float CalculateCPULoad(unsigned long long idleTicks,
                       unsigned long long totalTicks) {
  static unsigned long long previousTotalTicks = 0;
  static unsigned long long previousIdleTicks = 0;

  unsigned long long totalDiff = totalTicks - previousTotalTicks;
  unsigned long long idleDiff = idleTicks - previousIdleTicks;

  float ret =
      1.0f - (totalDiff > 0 ? static_cast<float>(idleDiff) / totalDiff : 0.0f);

  previousTotalTicks = totalTicks;
  previousIdleTicks = idleTicks;
  return ret;
}
} // anonymous namespace

float GetCPULoad() {
  FILETIME idleTime, kernelTime, userTime;
  if (GetSystemTimes(&idleTime, &kernelTime, &userTime))
    return CalculateCPULoad(FileTimeToInt64(idleTime),
                            FileTimeToInt64(kernelTime) +
                                FileTimeToInt64(userTime));
  return -1.0f;
}

// ---------------------------------------------------------------------------
// Window transparency (layered window)
// ---------------------------------------------------------------------------
void SetTransparent(HWND target_window, bool makeTransparent) {
  typedef BOOL(WINAPI * SetLayeredWindowAttributesFn)(HWND, COLORREF, BYTE,
                                                      DWORD);
  static auto pSetLayered = reinterpret_cast<SetLayeredWindowAttributesFn>(
      GetProcAddress(GetModuleHandle(L"user32"), "SetLayeredWindowAttributes"));

  DWORD exstyle = GetWindowLong(target_window, GWL_EXSTYLE);
  if (!pSetLayered || !exstyle)
    return;

  if (!makeTransparent) {
    SetWindowLong(target_window, GWL_EXSTYLE, exstyle & ~WS_EX_LAYERED);
  } else {
    SetWindowLong(target_window, GWL_EXSTYLE, exstyle | WS_EX_LAYERED);
    pSetLayered(target_window, 0, 0, LWA_ALPHA);
  }
}

// ---------------------------------------------------------------------------
// Taskbar toggle
// ---------------------------------------------------------------------------
void ToggleTaskbar(bool visible) {
  APPBARDATA abd = {sizeof(abd)};
  abd.lParam = visible ? ABS_ALWAYSONTOP : ABS_AUTOHIDE;
  SHAppBarMessage(ABM_SETSTATE, &abd);

  HWND mainHwnd = FindWindow(L"Shell_traywnd", L"");
  SetTransparent(mainHwnd, !visible);

  HWND hwndNext = nullptr;
  HWND hwnd = nullptr;
  do {
    hwnd = FindWindowEx(nullptr, hwndNext, L"Shell_SecondaryTrayWnd", L"");
    if (hwnd)
      SetTransparent(hwnd, !visible);
    hwndNext = hwnd;
  } while (hwnd != nullptr);

  SHAppBarMessage(ABM_WINDOWPOSCHANGED, &abd);
}

// ---------------------------------------------------------------------------
// Desktop wallpaper
// ---------------------------------------------------------------------------
void ToggleMonitorWallpaper(bool enabled) {
  CoInitialize(nullptr);
  IDesktopWallpaper *p = nullptr;
  if (SUCCEEDED(CoCreateInstance(
          __uuidof(DesktopWallpaper), 0, CLSCTX_LOCAL_SERVER,
          __uuidof(IDesktopWallpaper), reinterpret_cast<void **>(&p)))) {
    p->Enable(enabled);
    p->Release();
  }
  CoUninitialize();
}

void SetWallpaperColor(int color) {
  CoInitialize(nullptr);
  IDesktopWallpaper *p = nullptr;
  if (SUCCEEDED(CoCreateInstance(
          __uuidof(DesktopWallpaper), 0, CLSCTX_LOCAL_SERVER,
          __uuidof(IDesktopWallpaper), reinterpret_cast<void **>(&p)))) {
    p->SetBackgroundColor(static_cast<COLORREF>(color));
    p->Release();
  }
  CoUninitialize();
}

#endif // TABAMEWIN32_SYSTEM_UTILS
