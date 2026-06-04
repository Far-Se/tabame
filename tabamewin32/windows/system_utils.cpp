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

struct LibreData {
  double cpuUsage = 0.0;
  double cpuTemp = 0.0;
  double ramUsage = 0.0; // percentage
  double gpuUsage = 0.0;
  double gpuTemp = 0.0;
};

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

LibreData GetLibreHardwareMonitor() {
  LibreData result;

  // CoInitialize only if not already done on this thread
  HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  bool comInitialized = SUCCEEDED(hr) && hr != S_FALSE;

  IWbemLocator *pLoc = nullptr;
  IWbemServices *pSvc = nullptr;
  IEnumWbemClassObject *pEnum = nullptr;

  hr = CoCreateInstance(CLSID_WbemLocator, nullptr, CLSCTX_INPROC_SERVER,
                        IID_IWbemLocator, reinterpret_cast<LPVOID *>(&pLoc));
  if (FAILED(hr))
    goto cleanup;

  hr = pLoc->ConnectServer(_bstr_t(L"ROOT\\LibreHardwareMonitor"),
                           nullptr, // user    — nullptr = current process token
                           nullptr, // password
                           nullptr, // locale
                           0,
                           nullptr, // authority
                           nullptr, &pSvc);
  if (FAILED(hr))
    goto cleanup;

  // KEY FIX: EOAC_STATIC_CLOAKING passes the thread token (not process token)
  // This lets an elevated process talk to a namespace owned by the base user
  hr = CoSetProxyBlanket(
      pSvc, RPC_C_AUTHN_WINNT, RPC_C_AUTHZ_NONE, nullptr,
      RPC_C_AUTHN_LEVEL_PKT_PRIVACY, RPC_C_IMP_LEVEL_IMPERSONATE, nullptr,
      EOAC_STATIC_CLOAKING // <-- this is the important change
  );
  if (FAILED(hr))
    goto cleanup;

  // Query all sensors at once
  hr = pSvc->ExecQuery(
      _bstr_t(L"WQL"),
      _bstr_t(L"SELECT Name, Value, SensorType, Parent FROM Sensor"),
      WBEM_FLAG_FORWARD_ONLY | WBEM_FLAG_RETURN_IMMEDIATELY, nullptr, &pEnum);
  if (FAILED(hr))
    goto cleanup;

  {
    IWbemClassObject *pObj = nullptr;
    ULONG returned = 0;

    bool cpuTempFound = false;
    bool cpuLoadFound = false;
    bool ramLoadFound = false;
    bool gpuTempFound = false;
    bool gpuLoadFound = false;

    while (pEnum->Next(WBEM_INFINITE, 1, &pObj, &returned) == S_OK) {
      VARIANT vName, vValue, vType, vParent;
      VariantInit(&vName);
      VariantInit(&vValue);
      VariantInit(&vType);
      VariantInit(&vParent);

      pObj->Get(L"Name", 0, &vName, nullptr, nullptr);
      pObj->Get(L"Value", 0, &vValue, nullptr, nullptr);
      pObj->Get(L"SensorType", 0, &vType, nullptr, nullptr);
      pObj->Get(L"Parent", 0, &vParent, nullptr, nullptr);

      if (vName.vt == VT_BSTR && vValue.vt == VT_R4 && vType.vt == VT_BSTR &&
          vParent.vt == VT_BSTR) {
        std::wstring name = vName.bstrVal;
        std::wstring type = vType.bstrVal;
        std::wstring parent = vParent.bstrVal;
        float val = vValue.fltVal;

        // CPU Load — first "CPU Total" load sensor
        if (!cpuLoadFound && type == L"Load" && name == L"CPU Total") {
          result.cpuUsage = static_cast<double>(val);
          cpuLoadFound = true;
        }

        // CPU Temperature — first "CPU Package" or "Core Average"
        if (!cpuTempFound && type == L"Temperature" &&
            (name == L"CPU Package" || name == L"Core Average" ||
             name.find(L"CPU") != std::wstring::npos)) {
          result.cpuTemp = static_cast<double>(val);
          cpuTempFound = true;
        }

        // RAM Load
        if (!ramLoadFound && type == L"Load" && name == L"Memory") {
          result.ramUsage = static_cast<double>(val);
          ramLoadFound = true;
        }

        // GPU Load — parent path contains "gpu" (case-insensitive)
        if (!gpuLoadFound && type == L"Load") {
          std::wstring parentLow = parent;
          for (auto &c : parentLow)
            c = towlower(c);
          if (parentLow.find(L"gpu") != std::wstring::npos &&
              name == L"GPU Core") {
            result.gpuUsage = static_cast<double>(val);
            gpuLoadFound = true;
          }
        }

        // GPU Temperature
        if (!gpuTempFound && type == L"Temperature") {
          std::wstring parentLow = parent;
          for (auto &c : parentLow)
            c = towlower(c);
          if (parentLow.find(L"gpu") != std::wstring::npos &&
              name == L"GPU Core") {
            result.gpuTemp = static_cast<double>(val);
            gpuTempFound = true;
          }
        }
      }

      VariantClear(&vName);
      VariantClear(&vValue);
      VariantClear(&vType);
      VariantClear(&vParent);
      pObj->Release();
    }
  }

cleanup:
  if (pEnum)
    pEnum->Release();
  if (pSvc)
    pSvc->Release();
  if (pLoc)
    pLoc->Release();
  if (comInitialized)
    CoUninitialize();

  return result;
}
#endif // TABAMEWIN32_SYSTEM_UTILS
