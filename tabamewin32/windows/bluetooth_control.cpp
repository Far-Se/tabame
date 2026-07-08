#ifndef TABAMEWIN32_BLUETOOTH_CONTROL
#define TABAMEWIN32_BLUETOOTH_CONTROL

#include <windows.h>

#include <bluetoothapis.h>
#include <setupapi.h>

#include <cstdio>
#include <string>
#include <vector>

#pragma comment(lib, "bthprops.lib")
#pragma comment(lib, "setupapi.lib")

// ---------------------------------------------------------------------------
// Bluetooth quick-connect.
//
// Paired classic-Bluetooth devices are enumerated with the Win32 Bluetooth
// APIs. Connect/disconnect works by toggling the device's installed service
// enablement (BluetoothSetServiceState) — the same trick command-line BT
// tools use: enabling a service makes Windows connect it, disabling drops the
// link. Battery level comes from the DEVPKEY_Bluetooth_Battery PnP property
// that Windows exposes for HFP-capable devices (most headphones/earbuds).
// ---------------------------------------------------------------------------

struct BtDeviceInfo {
  std::wstring name;
  std::string address;            // display form "AA:BB:CC:DD:EE:FF"
  unsigned long long addressRaw = 0;
  bool connected = false;
  bool remembered = false;
  bool authenticated = false;
  unsigned long classOfDevice = 0;
  int battery = -1;               // percent, -1 when unknown
};

// {104EA319-6EE2-4701-BD47-8DDBF425BBE5}, 2 — battery percentage byte.
static const DEVPROPKEY kDevpkeyBluetoothBattery = {
    {0x104EA319, 0x6EE2, 0x4701, {0xBD, 0x47, 0x8D, 0xDB, 0xF4, 0x25, 0xBB, 0xE5}},
    2};

// A2DP AudioSink + Handsfree — the fallback service pair for audio devices
// that don't report their installed services.
static const GUID kBtAudioSinkGuid = {
    0x0000110B, 0x0000, 0x1000, {0x80, 0x00, 0x00, 0x80, 0x5F, 0x9B, 0x34, 0xFB}};
static const GUID kBtHandsfreeGuid = {
    0x0000111E, 0x0000, 0x1000, {0x80, 0x00, 0x00, 0x80, 0x5F, 0x9B, 0x34, 0xFB}};

static std::string BtFormatAddress(const BLUETOOTH_ADDRESS &address) {
  char buffer[18];
  sprintf_s(buffer, "%02X:%02X:%02X:%02X:%02X:%02X", address.rgBytes[5],
            address.rgBytes[4], address.rgBytes[3], address.rgBytes[2],
            address.rgBytes[1], address.rgBytes[0]);
  return std::string(buffer);
}

// Looks the device up among BTHENUM PnP nodes (instance ids embed the raw
// address as 12 hex chars) and reads the battery percentage property.
static int BtQueryBattery(const BLUETOOTH_ADDRESS &address) {
  wchar_t addrHex[13];
  swprintf_s(addrHex, L"%02X%02X%02X%02X%02X%02X", address.rgBytes[5],
             address.rgBytes[4], address.rgBytes[3], address.rgBytes[2],
             address.rgBytes[1], address.rgBytes[0]);

  HDEVINFO devs =
      SetupDiGetClassDevsW(nullptr, L"BTHENUM", nullptr, DIGCF_ALLCLASSES | DIGCF_PRESENT);
  if (devs == INVALID_HANDLE_VALUE)
    return -1;

  int battery = -1;
  SP_DEVINFO_DATA data;
  data.cbSize = sizeof(SP_DEVINFO_DATA);
  for (DWORD i = 0; SetupDiEnumDeviceInfo(devs, i, &data); ++i) {
    wchar_t instanceId[512];
    if (!SetupDiGetDeviceInstanceIdW(devs, &data, instanceId, 512, nullptr))
      continue;
    _wcsupr_s(instanceId);
    if (!wcsstr(instanceId, addrHex))
      continue;

    DEVPROPTYPE type = 0;
    BYTE value = 0;
    DWORD size = 0;
    if (SetupDiGetDevicePropertyW(devs, &data, &kDevpkeyBluetoothBattery,
                                  &type, &value, sizeof(value), &size, 0) &&
        type == DEVPROP_TYPE_BYTE) {
      battery = static_cast<int>(value);
      break;
    }
  }
  SetupDiDestroyDeviceInfoList(devs);
  return battery;
}

std::vector<BtDeviceInfo> EnumBluetoothDevices() {
  std::vector<BtDeviceInfo> out;

  BLUETOOTH_DEVICE_SEARCH_PARAMS search;
  ZeroMemory(&search, sizeof(search));
  search.dwSize = sizeof(search);
  search.fReturnAuthenticated = TRUE;
  search.fReturnRemembered = TRUE;
  search.fReturnConnected = TRUE;
  search.fReturnUnknown = FALSE;
  search.fIssueInquiry = FALSE; // paired devices only — no radio inquiry delay
  search.cTimeoutMultiplier = 0;
  search.hRadio = nullptr; // all local radios

  BLUETOOTH_DEVICE_INFO info;
  ZeroMemory(&info, sizeof(info));
  info.dwSize = sizeof(info);

  HBLUETOOTH_DEVICE_FIND find = BluetoothFindFirstDevice(&search, &info);
  if (!find)
    return out;

  do {
    BtDeviceInfo device;
    device.name = info.szName;
    device.addressRaw = info.Address.ullLong;
    device.address = BtFormatAddress(info.Address);
    device.connected = info.fConnected != FALSE;
    device.remembered = info.fRemembered != FALSE;
    device.authenticated = info.fAuthenticated != FALSE;
    device.classOfDevice = info.ulClassofDevice;
    device.battery = BtQueryBattery(info.Address);
    out.push_back(std::move(device));

    ZeroMemory(&info, sizeof(info));
    info.dwSize = sizeof(info);
  } while (BluetoothFindNextDevice(find, &info));
  BluetoothFindDeviceClose(find);

  return out;
}

bool SetBluetoothDeviceConnection(unsigned long long addressRaw, bool connect) {
  BLUETOOTH_DEVICE_INFO info;
  ZeroMemory(&info, sizeof(info));
  info.dwSize = sizeof(info);
  info.Address.ullLong = addressRaw;
  if (BluetoothGetDeviceInfo(nullptr, &info) != ERROR_SUCCESS)
    return false;

  // Prefer the services actually installed for this device; fall back to the
  // audio pair when the device doesn't report any.
  GUID services[16];
  DWORD count = 16;
  std::vector<GUID> toToggle;
  if (BluetoothEnumerateInstalledServices(nullptr, &info, &count, services) ==
          ERROR_SUCCESS &&
      count > 0) {
    for (DWORD i = 0; i < count && i < 16; ++i)
      toToggle.push_back(services[i]);
  } else {
    toToggle.push_back(kBtAudioSinkGuid);
    toToggle.push_back(kBtHandsfreeGuid);
  }

  bool any = false;
  for (const GUID &guid : toToggle) {
    if (connect) {
      // Cycle the service so Windows issues a fresh connection attempt even
      // when the service is already marked enabled.
      BluetoothSetServiceState(nullptr, &info, &guid, BLUETOOTH_SERVICE_DISABLE);
      any |= BluetoothSetServiceState(nullptr, &info, &guid,
                                      BLUETOOTH_SERVICE_ENABLE) == ERROR_SUCCESS;
    } else {
      any |= BluetoothSetServiceState(nullptr, &info, &guid,
                                      BLUETOOTH_SERVICE_DISABLE) == ERROR_SUCCESS;
    }
  }
  return any;
}

#endif // TABAMEWIN32_BLUETOOTH_CONTROL
