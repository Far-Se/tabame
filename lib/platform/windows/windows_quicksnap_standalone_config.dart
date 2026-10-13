import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import '../app_paths.dart';
import 'win32_api.dart';

/// Standalone selections, keyed by monitor device identity and preset ID.
class WindowsQuickSnapStandaloneConfig {
  static const String fileName = 'quicksnap_standalone.json';

  final Map<String, String> monitorPresets = <String, String>{};

  void load() {
    monitorPresets.clear();
    try {
      final File file = File(AppPaths.settingsPath(fileName));
      if (!file.existsSync()) return;
      final Object? data = jsonDecode(file.readAsStringSync());
      if (data is! Map<String, dynamic> || data['monitors'] is! Map<String, dynamic>) {
        throw const FormatException('Expected a monitors object.');
      }
      final Map<String, dynamic> monitors = data['monitors'] as Map<String, dynamic>;
      for (final MapEntry<String, dynamic> entry in monitors.entries) {
        if (entry.value is String) monitorPresets[entry.key] = entry.value as String;
      }
    } on FileSystemException catch (error) {
      debugPrint('Could not read QuickSnap Standalone config: $error');
    } on FormatException catch (error) {
      debugPrint('Invalid QuickSnap Standalone config: $error');
    }
  }

  void save() {
    try {
      final File file = File(AppPaths.settingsPath(fileName, forWrite: true));
      file.parent.createSync(recursive: true);
      // Replace the complete file only after the new content has been flushed.
      // Synchronous writes keep rapid selections and immediate close ordered.
      final File temporary = File('${file.path}.tmp');
      temporary.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(<String, Object>{
          'version': 1,
          'monitors': monitorPresets,
        }),
        flush: true,
      );
      temporary.renameSync(file.path);
    } on FileSystemException catch (error) {
      debugPrint('Could not save QuickSnap Standalone config: $error');
    }
  }

  /// HMONITOR values are temporary. Prefer the monitor's device interface name,
  /// with its display device name as a fallback for virtual/remote displays.
  static String? monitorKey(int monitorId) {
    if (!Platform.isWindows) {
      //TODO: Implement multiplatform
      return null;
    }
    final Pointer<MONITORINFOEX> info = calloc<MONITORINFOEX>();
    try {
      info.ref.monitorInfo.cbSize = sizeOf<MONITORINFOEX>();
      if (GetMonitorInfo(monitorId, info.cast()) == 0) return null;
      final String displayName = info.ref.szDevice;
      if (displayName.isEmpty) return null;
      final Pointer<Utf16> name = displayName.toNativeUtf16();
      final Pointer<DISPLAY_DEVICE> device = calloc<DISPLAY_DEVICE>();
      try {
        const int getDeviceInterfaceName = 0x00000001; // EDD_GET_DEVICE_INTERFACE_NAME
        for (int index = 0;; index++) {
          device.ref.cb = sizeOf<DISPLAY_DEVICE>();
          if (EnumDisplayDevices(name, index, device, getDeviceInterfaceName) == 0) break;
          if ((device.ref.StateFlags & DISPLAY_DEVICE_ACTIVE) != 0 && device.ref.DeviceID.isNotEmpty) {
            return device.ref.DeviceID;
          }
        }
      } finally {
        calloc.free(device);
        calloc.free(name);
      }
      return displayName;
    } finally {
      calloc.free(info);
    }
  }
}
