#include "include/tabamewin32/tabamewin32_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "tabamewin32_plugin.h"

void Tabamewin32PluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  tabamewin32::Tabamewin32Plugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
