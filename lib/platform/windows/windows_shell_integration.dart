import 'dart:io';

import '../shell_integration_service.dart';
import 'tabamewin32_api.dart';
import '../../models/win32/win32.dart';

/// Windows adapter for the reversible taskbar shell operation.
class WindowsTaskbarVisibilityService extends TaskbarVisibilityController {
  WindowsTaskbarVisibilityService({TaskbarVisibilityAdapter? adapter})
      : super(adapter: adapter ?? const _WindowsTaskbarVisibilityAdapter());
}

class _WindowsTaskbarVisibilityAdapter implements TaskbarVisibilityAdapter {
  const _WindowsTaskbarVisibilityAdapter();

  @override
  bool get isAvailable => Platform.isWindows;

  @override
  bool get isVisible {
    try {
      return Win32.isTaskbarVisible();
    } catch (_) {
      return true;
    }
  }

  @override
  String get unavailableReason => isAvailable
      ? 'Windows taskbar integration is unavailable; the normal taskbar remains visible.'
      : 'Taskbar shell integration is only available on Windows.';

  @override
  Future<bool> setVisible(bool visible) async {
    if (!isAvailable) return false;
    try {
      return await setTaskbarVisibility(visible);
    } catch (_) {
      return false;
    }
  }
}
