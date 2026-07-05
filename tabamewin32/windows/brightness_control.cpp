#ifndef TABAMEWIN32_BRIGHTNESS_CONTROL
#define TABAMEWIN32_BRIGHTNESS_CONTROL

#include <windows.h>

#include <highlevelmonitorconfigurationapi.h>
#include <physicalmonitorenumerationapi.h>

#include <objbase.h>
#include <oleauto.h>
#include <wbemidl.h>

#include <cstdio>
#include <string>
#include <vector>

#pragma comment(lib, "dxva2.lib")
#pragma comment(lib, "wbemuuid.lib")

// ---------------------------------------------------------------------------
// Hardware brightness control.
//
// Primary path is DDC-CI (VESA MCCS) via the dxva2 Physical Monitor API, which
// covers external monitors and many laptop panels. As a fallback for internal
// laptop displays that only expose brightness through ACPI/WMI, we also query
// root\WMI's WmiMonitorBrightness / WmiMonitorBrightnessMethods.
//
// Displays are identified by an opaque string id:
//   "ddc:<monitorIndex>:<physicalIndex>"  — resolved by re-enumeration on set.
//   "wmi:<instanceName>"                  — resolved by WMI instance path.
// ---------------------------------------------------------------------------

struct BrightnessDisplayInfo {
  std::string id;
  std::wstring name;
  bool supported = false;
  int minBrightness = 0;
  int curBrightness = 0;
  int maxBrightness = 100;
};

static std::string BrightnessWideToUtf8(const std::wstring &w) {
  if (w.empty())
    return std::string();
  int len = WideCharToMultiByte(CP_UTF8, 0, w.c_str(),
                                static_cast<int>(w.size()), nullptr, 0, nullptr,
                                nullptr);
  std::string out(len, '\0');
  WideCharToMultiByte(CP_UTF8, 0, w.c_str(), static_cast<int>(w.size()),
                      &out[0], len, nullptr, nullptr);
  return out;
}

static std::wstring BrightnessUtf8ToWide(const std::string &s) {
  if (s.empty())
    return std::wstring();
  int len = MultiByteToWideChar(CP_UTF8, 0, s.c_str(),
                                static_cast<int>(s.size()), nullptr, 0);
  std::wstring out(len, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()),
                      &out[0], len);
  return out;
}

static BOOL CALLBACK BrightnessEnumMonProc(HMONITOR h, HDC, LPRECT, LPARAM data) {
  reinterpret_cast<std::vector<HMONITOR> *>(data)->push_back(h);
  return TRUE;
}

static std::vector<HMONITOR> BrightnessEnumMonitors() {
  std::vector<HMONITOR> v;
  EnumDisplayMonitors(nullptr, nullptr, BrightnessEnumMonProc,
                      reinterpret_cast<LPARAM>(&v));
  return v;
}

// Doubles backslashes and escapes quotes so an InstanceName can be embedded in
// a WMI object path literal.
static std::wstring BrightnessEscapeWmi(const std::wstring &in) {
  std::wstring out;
  out.reserve(in.size() + 8);
  for (wchar_t c : in) {
    if (c == L'\\' || c == L'"')
      out.push_back(L'\\');
    out.push_back(c);
  }
  return out;
}

static void BrightnessAppendWmi(std::vector<BrightnessDisplayInfo> &out) {
  HRESULT hrInit = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  bool didInit = SUCCEEDED(hrInit);

  IWbemLocator *loc = nullptr;
  if (SUCCEEDED(CoCreateInstance(CLSID_WbemLocator, nullptr,
                                 CLSCTX_INPROC_SERVER, IID_IWbemLocator,
                                 reinterpret_cast<void **>(&loc)))) {
    IWbemServices *svc = nullptr;
    BSTR ns = SysAllocString(L"ROOT\\WMI");
    HRESULT hrConn = loc->ConnectServer(ns, nullptr, nullptr, nullptr, 0,
                                        nullptr, nullptr, &svc);
    SysFreeString(ns);
    if (SUCCEEDED(hrConn) && svc) {
      CoSetProxyBlanket(svc, RPC_C_AUTHN_WINNT, RPC_C_AUTHZ_NONE, nullptr,
                        RPC_C_AUTHN_LEVEL_CALL, RPC_C_IMP_LEVEL_IMPERSONATE,
                        nullptr, EOAC_NONE);

      BSTR wql = SysAllocString(L"WQL");
      BSTR query = SysAllocString(L"SELECT * FROM WmiMonitorBrightness");
      IEnumWbemClassObject *en = nullptr;
      if (SUCCEEDED(svc->ExecQuery(wql, query,
                                   WBEM_FLAG_FORWARD_ONLY |
                                       WBEM_FLAG_RETURN_IMMEDIATELY,
                                   nullptr, &en)) &&
          en) {
        IWbemClassObject *obj = nullptr;
        ULONG ret = 0;
        while (en->Next(WBEM_INFINITE, 1, &obj, &ret) == WBEM_S_NO_ERROR &&
               ret) {
          BrightnessDisplayInfo info;
          info.supported = true;
          info.minBrightness = 0;
          info.maxBrightness = 100;

          VARIANT v;
          VariantInit(&v);
          if (SUCCEEDED(obj->Get(L"CurrentBrightness", 0, &v, nullptr,
                                 nullptr))) {
            if (v.vt == VT_UI1)
              info.curBrightness = v.bVal;
            else if (v.vt == VT_I4)
              info.curBrightness = v.lVal;
          }
          VariantClear(&v);

          std::wstring instance;
          VARIANT vi;
          VariantInit(&vi);
          if (SUCCEEDED(
                  obj->Get(L"InstanceName", 0, &vi, nullptr, nullptr)) &&
              vi.vt == VT_BSTR && vi.bstrVal) {
            instance = vi.bstrVal;
          }
          VariantClear(&vi);

          info.name = L"Built-in display";
          info.id = "wmi:" + BrightnessWideToUtf8(instance);
          out.push_back(std::move(info));
          obj->Release();
          obj = nullptr;
        }
        en->Release();
      }
      SysFreeString(wql);
      SysFreeString(query);
      svc->Release();
    }
    loc->Release();
  }

  if (didInit)
    CoUninitialize();
}

static bool BrightnessWmiSet(const std::string &instanceUtf8, int value) {
  std::wstring instance = BrightnessUtf8ToWide(instanceUtf8);
  HRESULT hrInit = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  bool didInit = SUCCEEDED(hrInit);
  bool ok = false;

  IWbemLocator *loc = nullptr;
  if (SUCCEEDED(CoCreateInstance(CLSID_WbemLocator, nullptr,
                                 CLSCTX_INPROC_SERVER, IID_IWbemLocator,
                                 reinterpret_cast<void **>(&loc)))) {
    IWbemServices *svc = nullptr;
    BSTR ns = SysAllocString(L"ROOT\\WMI");
    HRESULT hrConn = loc->ConnectServer(ns, nullptr, nullptr, nullptr, 0,
                                        nullptr, nullptr, &svc);
    SysFreeString(ns);
    if (SUCCEEDED(hrConn) && svc) {
      CoSetProxyBlanket(svc, RPC_C_AUTHN_WINNT, RPC_C_AUTHZ_NONE, nullptr,
                        RPC_C_AUTHN_LEVEL_CALL, RPC_C_IMP_LEVEL_IMPERSONATE,
                        nullptr, EOAC_NONE);

      BSTR className = SysAllocString(L"WmiMonitorBrightnessMethods");
      IWbemClassObject *cls = nullptr;
      if (SUCCEEDED(svc->GetObject(className, 0, nullptr, &cls, nullptr)) &&
          cls) {
        IWbemClassObject *inSig = nullptr;
        if (SUCCEEDED(cls->GetMethod(L"WmiSetBrightness", 0, &inSig,
                                     nullptr)) &&
            inSig) {
          IWbemClassObject *inInst = nullptr;
          if (SUCCEEDED(inSig->SpawnInstance(0, &inInst)) && inInst) {
            VARIANT vt;
            VariantInit(&vt);
            vt.vt = VT_I4;
            vt.lVal = 0;
            inInst->Put(L"Timeout", 0, &vt, 0);
            VariantClear(&vt);

            VARIANT vb;
            VariantInit(&vb);
            vb.vt = VT_UI1;
            vb.bVal = static_cast<BYTE>(value);
            inInst->Put(L"Brightness", 0, &vb, 0);
            VariantClear(&vb);

            std::wstring path = L"WmiMonitorBrightnessMethods.InstanceName=\"" +
                                BrightnessEscapeWmi(instance) + L"\"";
            BSTR objPath = SysAllocString(path.c_str());
            BSTR method = SysAllocString(L"WmiSetBrightness");
            IWbemClassObject *outParams = nullptr;
            HRESULT hr = svc->ExecMethod(objPath, method, 0, nullptr, inInst,
                                         &outParams, nullptr);
            ok = SUCCEEDED(hr);
            if (outParams)
              outParams->Release();
            SysFreeString(objPath);
            SysFreeString(method);
            inInst->Release();
          }
          inSig->Release();
        }
        cls->Release();
      }
      SysFreeString(className);
      svc->Release();
    }
    loc->Release();
  }

  if (didInit)
    CoUninitialize();
  return ok;
}

std::vector<BrightnessDisplayInfo> GetBrightnessDisplays() {
  std::vector<BrightnessDisplayInfo> out;

  std::vector<HMONITOR> monitors = BrightnessEnumMonitors();
  for (size_t mi = 0; mi < monitors.size(); ++mi) {
    DWORD count = 0;
    if (!GetNumberOfPhysicalMonitorsFromHMONITOR(monitors[mi], &count) ||
        count == 0)
      continue;

    std::vector<PHYSICAL_MONITOR> phys(count);
    if (!GetPhysicalMonitorsFromHMONITOR(monitors[mi], count, phys.data()))
      continue;

    for (DWORD pi = 0; pi < count; ++pi) {
      BrightnessDisplayInfo info;
      info.id = "ddc:" + std::to_string(mi) + ":" + std::to_string(pi);
      info.name = phys[pi].szPhysicalMonitorDescription;
      if (info.name.empty())
        info.name = L"Display";

      DWORD mn = 0, cur = 0, mx = 0;
      if (GetMonitorBrightness(phys[pi].hPhysicalMonitor, &mn, &cur, &mx)) {
        info.supported = true;
        info.minBrightness = static_cast<int>(mn);
        info.curBrightness = static_cast<int>(cur);
        info.maxBrightness = static_cast<int>(mx);
      }
      out.push_back(std::move(info));
    }
    DestroyPhysicalMonitors(count, phys.data());
  }

  BrightnessAppendWmi(out);
  return out;
}

bool SetBrightnessForDisplay(const std::string &id, int value) {
  if (id.rfind("wmi:", 0) == 0)
    return BrightnessWmiSet(id.substr(4), value);

  int mi = -1, pi = -1;
  if (sscanf_s(id.c_str(), "ddc:%d:%d", &mi, &pi) != 2)
    return false;

  std::vector<HMONITOR> monitors = BrightnessEnumMonitors();
  if (mi < 0 || mi >= static_cast<int>(monitors.size()))
    return false;

  DWORD count = 0;
  if (!GetNumberOfPhysicalMonitorsFromHMONITOR(monitors[mi], &count) ||
      count == 0)
    return false;

  std::vector<PHYSICAL_MONITOR> phys(count);
  if (!GetPhysicalMonitorsFromHMONITOR(monitors[mi], count, phys.data()))
    return false;

  bool ok = false;
  if (pi >= 0 && pi < static_cast<int>(count)) {
    ok = SetMonitorBrightness(phys[pi].hPhysicalMonitor,
                              static_cast<DWORD>(value)) != 0;
  }
  DestroyPhysicalMonitors(count, phys.data());
  return ok;
}

#endif // TABAMEWIN32_BRIGHTNESS_CONTROL
