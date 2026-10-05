#include "startup_manager.h"

#include <windows.h>
#include <appmodel.h>
#include <shlobj.h>

#include <winrt/Windows.ApplicationModel.h>
#include <winrt/Windows.Foundation.h>

#include <array>
#include <cstring>
#include <string>
#include <utility>
#include <vector>

namespace startup_manager {
namespace {

constexpr wchar_t kRunKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr wchar_t kStartupApprovedRunKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\StartupApproved\\Run";
constexpr wchar_t kRunValueName[] = L"Tabame";
constexpr wchar_t kStartupTaskId[] = L"TabameStartup";
constexpr wchar_t kLegacyShortcutName[] = L"tabame.lnk";

using winrt::Windows::ApplicationModel::StartupTask;
using winrt::Windows::ApplicationModel::StartupTaskState;

Result Success(std::string value) { return {true, std::move(value), {}}; }

Result Failure(std::string error) { return {false, {}, std::move(error)}; }

Result WindowsFailure(const char* operation, LONG code) {
  return Failure(std::string(operation) + " failed with Windows error " +
                 std::to_string(code));
}

const char* StatusName(StartupTaskState state) {
  switch (state) {
    case StartupTaskState::Enabled:
      return "enabled";
    case StartupTaskState::EnabledByPolicy:
      return "enabledByPolicy";
    case StartupTaskState::Disabled:
      return "disabled";
    case StartupTaskState::DisabledByUser:
      return "disabledByUser";
    case StartupTaskState::DisabledByPolicy:
      return "disabledByPolicy";
  }
  return "error";
}

Result DetectPackage(bool* packaged) {
  UINT32 package_name_length = 0;
  const LONG result = GetCurrentPackageFullName(&package_name_length, nullptr);
  if (result == APPMODEL_ERROR_NO_PACKAGE) {
    *packaged = false;
    return Success("unpackaged");
  }
  if (result == ERROR_INSUFFICIENT_BUFFER || result == ERROR_SUCCESS) {
    *packaged = true;
    return Success("packaged");
  }
  return WindowsFailure("GetCurrentPackageFullName", result);
}

std::wstring LegacyShortcutPath() {
  PWSTR startup_folder = nullptr;
  const HRESULT result =
      SHGetKnownFolderPath(FOLDERID_Startup, KF_FLAG_DEFAULT, nullptr,
                           &startup_folder);
  if (FAILED(result) || startup_folder == nullptr) {
    return {};
  }

  std::wstring path(startup_folder);
  CoTaskMemFree(startup_folder);
  if (!path.empty() && path.back() != L'\\') {
    path.push_back(L'\\');
  }
  path.append(kLegacyShortcutName);
  return path;
}

bool HasLegacyShortcut() {
  const std::wstring path = LegacyShortcutPath();
  return !path.empty() && GetFileAttributesW(path.c_str()) != INVALID_FILE_ATTRIBUTES;
}

Result RemoveLegacyShortcut() {
  const std::wstring path = LegacyShortcutPath();
  if (path.empty()) {
    return Success("disabled");
  }
  if (DeleteFileW(path.c_str()) || GetLastError() == ERROR_FILE_NOT_FOUND ||
      GetLastError() == ERROR_PATH_NOT_FOUND) {
    return Success("disabled");
  }
  return WindowsFailure("DeleteFileW for the legacy startup shortcut",
                        GetLastError());
}

Result HasRunValue(bool* exists) {
  HKEY key = nullptr;
  LSTATUS result = RegOpenKeyExW(HKEY_CURRENT_USER, kRunKey, 0, KEY_QUERY_VALUE,
                                 &key);
  if (result == ERROR_FILE_NOT_FOUND || result == ERROR_PATH_NOT_FOUND) {
    *exists = false;
    return Success("disabled");
  }
  if (result != ERROR_SUCCESS) {
    return WindowsFailure("RegOpenKeyExW for startup status", result);
  }

  DWORD type = 0;
  DWORD size = 0;
  result = RegQueryValueExW(key, kRunValueName, nullptr, &type, nullptr, &size);
  RegCloseKey(key);
  if (result == ERROR_FILE_NOT_FOUND) {
    *exists = false;
    return Success("disabled");
  }
  if (result != ERROR_SUCCESS) {
    return WindowsFailure("RegQueryValueExW for startup status", result);
  }
  *exists = true;
  return Success("enabled");
}

Result IsStartupEntryDisabledByUser(const wchar_t* approval_key,
                                    const wchar_t* value_name,
                                    bool* disabled) {
  *disabled = false;
  HKEY key = nullptr;
  LSTATUS result = RegOpenKeyExW(HKEY_CURRENT_USER, approval_key, 0,
                                 KEY_QUERY_VALUE, &key);
  if (result == ERROR_FILE_NOT_FOUND || result == ERROR_PATH_NOT_FOUND) {
    return Success("disabled");
  }
  if (result != ERROR_SUCCESS) {
    return WindowsFailure("RegOpenKeyExW for Windows startup approval", result);
  }

  std::array<BYTE, 64> approval_data{};
  DWORD type = 0;
  DWORD size = static_cast<DWORD>(approval_data.size());
  result = RegQueryValueExW(key, value_name, nullptr, &type,
                            approval_data.data(), &size);
  RegCloseKey(key);
  if (result == ERROR_FILE_NOT_FOUND) {
    return Success("disabled");
  }
  if (result != ERROR_SUCCESS) {
    return WindowsFailure("RegQueryValueExW for Windows startup approval",
                          result);
  }

  // Startup Apps stores per-entry approval state under StartupApproved. Leave
  // that Windows-owned data untouched and honor its known disabled marker.
  if (type == REG_BINARY && size >= sizeof(DWORD)) {
    DWORD state = 0;
    std::memcpy(&state, approval_data.data(), sizeof(state));
    *disabled = state == 3;
  }
  return Success("disabled");
}

Result IsRunValueDisabledByUser(bool* disabled) {
  return IsStartupEntryDisabledByUser(kStartupApprovedRunKey, kRunValueName,
                                      disabled);
}

Result IsLegacyShortcutDisabledByUser(bool* disabled) {
  constexpr wchar_t kStartupApprovedFolderKey[] =
      L"Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\StartupApproved\\StartupFolder";
  return IsStartupEntryDisabledByUser(kStartupApprovedFolderKey,
                                      kLegacyShortcutName, disabled);
}

Result SetRunValue() {
  std::vector<wchar_t> executable_path(32768, L'\0');
  const DWORD path_length = GetModuleFileNameW(
      nullptr, executable_path.data(),
      static_cast<DWORD>(executable_path.size()));
  const DWORD path_capacity = static_cast<DWORD>(executable_path.size());
  if (path_length == 0 || path_length >= path_capacity) {
    return WindowsFailure("GetModuleFileNameW", GetLastError());
  }

  std::wstring command = L"\"";
  command.append(executable_path.data(), path_length);
  command.append(L"\" --startup");

  HKEY key = nullptr;
  LSTATUS result = RegCreateKeyExW(HKEY_CURRENT_USER, kRunKey, 0, nullptr, 0,
                                  KEY_SET_VALUE, nullptr, &key, nullptr);
  if (result != ERROR_SUCCESS) {
    return WindowsFailure("RegCreateKeyExW for startup", result);
  }

  const DWORD data_size =
      static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t));
  result = RegSetValueExW(
      key, kRunValueName, 0, REG_SZ,
      reinterpret_cast<const BYTE*>(command.c_str()), data_size);
  RegCloseKey(key);
  if (result != ERROR_SUCCESS) {
    return WindowsFailure("RegSetValueExW for startup", result);
  }
  return Success("enabled");
}

Result RemoveRunValue() {
  HKEY key = nullptr;
  LSTATUS result = RegOpenKeyExW(HKEY_CURRENT_USER, kRunKey, 0, KEY_SET_VALUE,
                                 &key);
  if (result == ERROR_FILE_NOT_FOUND || result == ERROR_PATH_NOT_FOUND) {
    return Success("disabled");
  }
  if (result != ERROR_SUCCESS) {
    return WindowsFailure("RegOpenKeyExW for startup removal", result);
  }

  result = RegDeleteValueW(key, kRunValueName);
  RegCloseKey(key);
  if (result == ERROR_FILE_NOT_FOUND) {
    return Success("disabled");
  }
  if (result != ERROR_SUCCESS) {
    return WindowsFailure("RegDeleteValueW for startup", result);
  }
  return Success("disabled");
}

Result GetUnpackagedStatus() {
  bool has_run_value = false;
  Result run_result = HasRunValue(&has_run_value);
  if (!run_result.success) {
    return run_result;
  }

  const bool has_legacy_shortcut = HasLegacyShortcut();
  if (has_legacy_shortcut && !has_run_value) {
    bool shortcut_disabled_by_user = false;
    Result approval_result =
        IsLegacyShortcutDisabledByUser(&shortcut_disabled_by_user);
    if (!approval_result.success) return approval_result;
    if (shortcut_disabled_by_user) {
      return Success("disabledByUser");
    }
  }

  if (has_legacy_shortcut && !has_run_value) {
    run_result = SetRunValue();
    if (!run_result.success) {
      return run_result;
    }
    has_run_value = true;
  }

  if (has_legacy_shortcut) {
    Result remove_result = RemoveLegacyShortcut();
    if (!remove_result.success) {
      return remove_result;
    }
  }

  if (has_run_value) {
    bool disabled_by_user = false;
    Result approval_result = IsRunValueDisabledByUser(&disabled_by_user);
    if (!approval_result.success) return approval_result;
    if (disabled_by_user) return Success("disabledByUser");
  }
  return Success(has_run_value ? "enabled" : "disabled");
}

Result RemoveLegacyRegistrations() {
  Result registry_result = RemoveRunValue();
  Result shortcut_result = RemoveLegacyShortcut();
  if (!registry_result.success) return registry_result;
  if (!shortcut_result.success) return shortcut_result;
  return Success("disabled");
}

Result GetPackagedStatus() {
  StartupTask task = StartupTask::GetAsync(kStartupTaskId).get();
  StartupTaskState state = task.State();

  bool has_legacy_run_value = false;
  Result run_result = HasRunValue(&has_legacy_run_value);
  if (!run_result.success) return run_result;
  const bool has_legacy_shortcut = HasLegacyShortcut();
  const bool migrate_existing_opt_in =
      has_legacy_run_value || has_legacy_shortcut;

  if (migrate_existing_opt_in) {
    bool legacy_disabled_by_user = false;
    Result approval_result = has_legacy_run_value
                                 ? IsRunValueDisabledByUser(
                                       &legacy_disabled_by_user)
                                 : IsLegacyShortcutDisabledByUser(
                                       &legacy_disabled_by_user);
    if (!approval_result.success) return approval_result;
    if (state == StartupTaskState::Disabled && legacy_disabled_by_user) {
      if (has_legacy_run_value && has_legacy_shortcut) {
        Result shortcut_cleanup = RemoveLegacyShortcut();
        if (!shortcut_cleanup.success) return shortcut_cleanup;
      }
      return Success("disabledByUser");
    }

    Result cleanup = RemoveLegacyRegistrations();
    if (!cleanup.success) return cleanup;

    // A legacy startup registration records a prior user choice. Migrate that
    // choice only while the new task is ordinarily disabled; Windows-owned
    // user and policy states always take precedence.
    if (state == StartupTaskState::Disabled) {
      state = task.RequestEnableAsync().get();
    }
  }

  return Success(StatusName(state));
}

}  // namespace

Result IsPackaged() {
  bool packaged = false;
  Result detection = DetectPackage(&packaged);
  if (!detection.success) return detection;
  return Success(packaged ? "true" : "false");
}

Result GetStatus() {
  bool packaged = false;
  Result detection = DetectPackage(&packaged);
  if (!detection.success) return detection;

  try {
    return packaged ? GetPackagedStatus() : GetUnpackagedStatus();
  } catch (const winrt::hresult_error& error) {
    return Failure("Windows StartupTask failed: " +
                   winrt::to_string(error.message()));
  } catch (...) {
    return Failure("Windows startup status could not be read");
  }
}

Result Enable() {
  bool packaged = false;
  Result detection = DetectPackage(&packaged);
  if (!detection.success) return detection;

  try {
    if (!packaged) {
      Result current = GetUnpackagedStatus();
      if (!current.success || current.value == "enabled" ||
          current.value == "disabledByUser") {
        return current;
      }
      Result set_result = SetRunValue();
      if (!set_result.success) return set_result;
      Result remove_result = RemoveLegacyShortcut();
      if (!remove_result.success) return remove_result;
      return GetUnpackagedStatus();
    }

    Result current = GetPackagedStatus();
    if (!current.success) return current;
    if (current.value == "disabledByUser" ||
        current.value == "disabledByPolicy" ||
        current.value == "enabledByPolicy") {
      return current;
    }

    StartupTask task = StartupTask::GetAsync(kStartupTaskId).get();
    if (task.State() == StartupTaskState::Disabled) {
      task.RequestEnableAsync().get();
    }
    return Success(StatusName(task.State()));
  } catch (const winrt::hresult_error& error) {
    return Failure("Could not enable Windows startup: " +
                   winrt::to_string(error.message()));
  } catch (...) {
    return Failure("Could not enable Windows startup");
  }
}

Result Disable() {
  bool packaged = false;
  Result detection = DetectPackage(&packaged);
  if (!detection.success) return detection;

  if (!packaged) {
    Result cleanup = RemoveLegacyRegistrations();
    if (!cleanup.success) return cleanup;
    return GetUnpackagedStatus();
  }

  try {
    StartupTask task = StartupTask::GetAsync(kStartupTaskId).get();
    Result cleanup = RemoveLegacyRegistrations();
    if (!cleanup.success) return cleanup;

    const StartupTaskState current_state = task.State();
    if (current_state == StartupTaskState::Enabled) {
      task.Disable();
    }
    return Success(StatusName(task.State()));
  } catch (const winrt::hresult_error& error) {
    return Failure("Could not disable Windows startup: " +
                   winrt::to_string(error.message()));
  } catch (...) {
    return Failure("Could not disable Windows startup");
  }
}

}  // namespace startup_manager
