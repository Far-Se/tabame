import 'dart:ffi';
import 'dart:typed_data';

import '../win32/imports.dart';
import '../win32/registry.dart';
import '../win32/win_utils.dart';

enum ContextMenuItemType { static, shellEx }

class ContextMenuItem {
  final String name;
  String registryPath;
  final RegistryHive hive;
  final ContextMenuItemType type;
  bool isEnabled;
  final String? command;
  final String? clsid;
  final String? iconSource;
  Uint8List? iconBytes;

  ContextMenuItem({
    required this.name,
    required this.registryPath,
    required this.hive,
    required this.type,
    required this.isEnabled,
    this.command,
    this.clsid,
    this.iconSource,
    this.iconBytes,
  });

  Future<void> toggle() async {
    final RegistryKey key = Registry.openPath(hive, path: registryPath, desiredAccessRights: AccessRights.allAccess64);
    try {
      if (type == ContextMenuItemType.static) {
        if (isEnabled) {
          key.createValue(const RegistryValue("LegacyDisable", RegistryValueType.string, ""));
        } else {
          key.deleteValue("LegacyDisable");
        }
      } else {
        // For ShellEx, we prefix the default value (CLSID) with a dash
        final RegistryValue? defaultValue = key.getValue("");
        if (defaultValue != null && defaultValue.data is String) {
          String clsidValue = defaultValue.data as String;
          if (isEnabled) {
            if (!clsidValue.startsWith("-")) {
              clsidValue = "-$clsidValue";
            }
          } else {
            if (clsidValue.startsWith("-")) {
              clsidValue = clsidValue.substring(1);
            }
          }
          key.createValue(RegistryValue("", RegistryValueType.string, clsidValue));
        } else {
          _toggleShellExtensionKeyName();
        }
      }
      isEnabled = !isEnabled;
      key.flush();
    } finally {
      key.close();
    }
    shChangeNotify(0x08000000, 0x0000, nullptr, nullptr);
  }

  void _toggleShellExtensionKeyName() {
    final int separatorIndex = registryPath.lastIndexOf(r"\");
    if (separatorIndex == -1) {
      throw ArgumentError.value(registryPath, "registryPath", "Expected a registry path with a parent key.");
    }

    final String parentPath = registryPath.substring(0, separatorIndex);
    final String currentName = registryPath.substring(separatorIndex + 1);
    final String nextName = isEnabled
        ? currentName.startsWith("-")
            ? currentName
            : "-$currentName"
        : currentName.startsWith("-")
            ? currentName.substring(1)
            : currentName;

    if (nextName == currentName) return;

    final RegistryKey parentKey =
        Registry.openPath(hive, path: parentPath, desiredAccessRights: AccessRights.allAccess64);
    try {
      parentKey.renameSubkey(currentName, nextName);
      registryPath = "$parentPath\\$nextName";
      parentKey.flush();
    } finally {
      parentKey.close();
    }
  }

  void fetchIcon() {
    if (iconSource != null && iconSource!.isNotEmpty) {
      String source = iconSource!;
      if (source.startsWith("@")) {
        source = source.substring(1);
      }
      // Expand environment variables
      source = WinUtils.expandEnvironmentVariables(source);

      // Icon source could be "path,index"
      final List<String> parts = source.split(",");
      final String path = parts[0].trim().replaceAll('"', '');
      int index = 0;
      if (parts.length > 1) {
        index = int.tryParse(parts[1].trim()) ?? 0;
      }
      iconBytes = WinUtils.extractIcon(path, iconID: index);
    } else if (command != null && command!.isNotEmpty) {
      // Extract from command string (usually starts with the exe path)
      final String cmd = command!.trim();
      String exePath = "";
      if (cmd.startsWith('"')) {
        final int endQuote = cmd.indexOf('"', 1);
        if (endQuote != -1) {
          exePath = cmd.substring(1, endQuote);
        }
      } else {
        exePath = cmd.split(" ").first;
      }
      if (exePath.isNotEmpty) {
        iconBytes = WinUtils.extractIcon(exePath);
      }
    }
  }
}
