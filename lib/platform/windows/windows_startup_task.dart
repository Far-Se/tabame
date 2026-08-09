import 'dart:io';

import 'package:flutter/services.dart';

enum WindowsStartupTaskState {
  disabled,
  disabledByUser,
  enabled,
  disabledByPolicy,
  unavailable,
}

/// Thin bridge for the MSIX StartupTask API. It deliberately has no shortcut
/// fallback: a packaged profile must use the manifest-declared task.
class WindowsStartupTaskBridge {
  const WindowsStartupTaskBridge();

  static const MethodChannel _channel = MethodChannel('tabamewin32');

  Future<WindowsStartupTaskState> read() async {
    if (!Platform.isWindows) return WindowsStartupTaskState.unavailable;
    try {
      final int? value = await _channel.invokeMethod<int>('getStartupTaskState');
      return _fromNativeState(value);
    } on MissingPluginException {
      return WindowsStartupTaskState.unavailable;
    } on PlatformException {
      return WindowsStartupTaskState.unavailable;
    }
  }

  Future<WindowsStartupTaskState> requestEnable() async {
    if (!Platform.isWindows) return WindowsStartupTaskState.unavailable;
    try {
      final int? value = await _channel.invokeMethod<int>('requestEnableStartupTask');
      return _fromNativeState(value);
    } on MissingPluginException {
      return WindowsStartupTaskState.unavailable;
    } on PlatformException {
      return WindowsStartupTaskState.unavailable;
    }
  }

  Future<WindowsStartupTaskState> disable() async {
    if (!Platform.isWindows) return WindowsStartupTaskState.unavailable;
    try {
      final int? value = await _channel.invokeMethod<int>('disableStartupTask');
      return _fromNativeState(value);
    } on MissingPluginException {
      return WindowsStartupTaskState.unavailable;
    } on PlatformException {
      return WindowsStartupTaskState.unavailable;
    }
  }

  WindowsStartupTaskState _fromNativeState(int? value) {
    switch (value) {
      case 0:
        return WindowsStartupTaskState.disabled;
      case 1:
        return WindowsStartupTaskState.disabledByUser;
      case 2:
        return WindowsStartupTaskState.enabled;
      case 3:
        return WindowsStartupTaskState.disabledByPolicy;
      default:
        return WindowsStartupTaskState.unavailable;
    }
  }
}
