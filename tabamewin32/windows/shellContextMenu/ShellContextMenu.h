#pragma once

#include <memory>
#include <shlobj.h>
#include <string>
#include <vector>
#include <windows.h>

struct ShellMenuItem {
  int id;             // Command offset ID
  std::wstring label; // Human-readable menu text
  std::wstring verb;  // Canonical verb (e.g., "open", "runas")
  bool enabled;       // Clickable state
  HICON hIcon;        // Extracted icon handle
  bool ownsIcon;
};

class ShellContextMenu {
public:
  // Retrieves all valid context menu items for a path, including icons
  static std::vector<ShellMenuItem> GetMenuItems(const std::wstring &path);

  // Invokes a canonical verb or a command ID on a target path
  static bool Invoke(const std::wstring &path, const std::wstring &verb,
                     int id = -1, HWND hwnd = nullptr);

private:
  static std::wstring StripAccelerators(const std::wstring &label);
};
