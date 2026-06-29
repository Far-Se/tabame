#ifndef TABAMEWIN32_HDR_CONTROL
#define TABAMEWIN32_HDR_CONTROL

#include <string>
#include <vector>
#include <windows.h>

#pragma comment(lib, "user32.lib")

// ---------------------------------------------------------------------------
// HDR / Advanced Color control via the Win32 DisplayConfig API.
//
// Mirrors the approach from the ToggleHDRExtension reference: enumerate active
// display paths with QueryDisplayConfig, read each target's advanced-color
// state, and flip it with DISPLAYCONFIG_SET_ADVANCED_COLOR_STATE. Displays are
// identified by their (adapterId LUID + target id) so the identity survives a
// re-query, rather than by a positional index.
// ---------------------------------------------------------------------------

struct HDRDisplayInfo {
  uint32_t adapterIdLow = 0;
  int32_t adapterIdHigh = 0;
  uint32_t id = 0;
  std::wstring name;
  bool supportsHDR = false;
  bool isHDREnabled = false;
};

std::vector<HDRDisplayInfo> GetHDRDisplays() {
  std::vector<HDRDisplayInfo> displays;

  UINT32 pathCount = 0;
  UINT32 modeCount = 0;
  if (GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, &pathCount,
                                  &modeCount) != ERROR_SUCCESS) {
    return displays;
  }

  std::vector<DISPLAYCONFIG_PATH_INFO> paths(pathCount);
  std::vector<DISPLAYCONFIG_MODE_INFO> modes(modeCount);
  if (QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, &pathCount, paths.data(),
                         &modeCount, modes.data(), nullptr) != ERROR_SUCCESS) {
    return displays;
  }
  paths.resize(pathCount);

  for (const auto &path : paths) {
    HDRDisplayInfo info;
    info.adapterIdLow = path.targetInfo.adapterId.LowPart;
    info.adapterIdHigh = path.targetInfo.adapterId.HighPart;
    info.id = path.targetInfo.id;

    // Friendly monitor name.
    DISPLAYCONFIG_TARGET_DEVICE_NAME nameInfo = {};
    nameInfo.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME;
    nameInfo.header.size = sizeof(nameInfo);
    nameInfo.header.adapterId = path.targetInfo.adapterId;
    nameInfo.header.id = path.targetInfo.id;
    if (DisplayConfigGetDeviceInfo(&nameInfo.header) == ERROR_SUCCESS) {
      info.name = nameInfo.monitorFriendlyDeviceName;
    }
    if (info.name.empty())
      info.name = L"Display";

    // Advanced color (HDR) capability + current state.
    DISPLAYCONFIG_GET_ADVANCED_COLOR_INFO colorInfo = {};
    colorInfo.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_ADVANCED_COLOR_INFO;
    colorInfo.header.size = sizeof(colorInfo);
    colorInfo.header.adapterId = path.targetInfo.adapterId;
    colorInfo.header.id = path.targetInfo.id;
    if (DisplayConfigGetDeviceInfo(&colorInfo.header) == ERROR_SUCCESS) {
      info.supportsHDR = colorInfo.advancedColorSupported != 0;
      info.isHDREnabled = colorInfo.advancedColorEnabled != 0;
    }

    displays.push_back(std::move(info));
  }

  return displays;
}

bool SetHDRStateForDisplay(uint32_t adapterIdLow, int32_t adapterIdHigh,
                           uint32_t id, bool enable) {
  DISPLAYCONFIG_SET_ADVANCED_COLOR_STATE setState = {};
  setState.header.type = DISPLAYCONFIG_DEVICE_INFO_SET_ADVANCED_COLOR_STATE;
  setState.header.size = sizeof(setState);
  setState.header.adapterId.LowPart = adapterIdLow;
  setState.header.adapterId.HighPart = adapterIdHigh;
  setState.header.id = id;
  setState.enableAdvancedColor = enable ? 1 : 0;

  return DisplayConfigSetDeviceInfo(&setState.header) == ERROR_SUCCESS;
}

#endif // TABAMEWIN32_HDR_CONTROL
