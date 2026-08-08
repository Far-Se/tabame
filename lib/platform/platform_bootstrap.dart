import 'dart:io';

import 'file_picker_service.dart';

import 'portable_file_picker_service.dart';
import 'windows/windows_bootstrap.dart';
import 'macos/macos_bootstrap.dart';
import 'linux/linux_bootstrap.dart';

/// Selects platform startup behavior without exposing native APIs to callers.
class PlatformBootstrap {
  PlatformBootstrap._();

  static bool get isWindows => Platform.isWindows;
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    if (Platform.isWindows) {
      WindowsBootstrap.initialize();
      return;
    }
    if (Platform.isMacOS) {
      await MacOSBootstrap.initialize();
      FilePickerService.register(const PortableFilePickerService());
      return;
    }
    if (Platform.isLinux) {
      FilePickerService.register(const PortableFilePickerService());
      await LinuxBootstrap.initialize();
    }
  }
}
