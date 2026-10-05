import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../logic/error_handler.dart';

/// Startup state reported by Windows or the unpackaged Run registration.
enum StartupStatus {
  enabled,
  enabledByPolicy,
  disabled,
  disabledByUser,
  disabledByPolicy,
  unavailable,
  error;

  /// Whether Windows currently has Tabame enabled at sign-in.
  bool get isEnabled => this == enabled || this == enabledByPolicy;
}

/// Owns the Windows startup registration for both MSIX and Win32 installs.
///
/// The native runner detects package identity and uses StartupTask for MSIX,
/// or the current user's Run key for unpackaged builds.
class StartupManager {
  StartupManager._();

  static const MethodChannel _channel = MethodChannel('tabame/startup');

  static Future<bool> isPackaged() async {
    if (!Platform.isWindows) return false;

    try {
      return await _channel.invokeMethod<bool>('isPackaged') ?? false;
    } catch (error, stack) {
      _logError('Could not detect the Windows package state', error, stack);
      return false;
    }
  }

  static Future<bool> isEnabled() async => (await getStatus()).isEnabled;

  static Future<StartupStatus> getStatus() => _invokeStatus('getStatus');

  /// Requests startup and returns the state Windows actually reports.
  /// User-disabled and policy-disabled tasks remain disabled.
  static Future<StartupStatus> enable() => _invokeStatus('enable');

  /// Disables startup where Windows permits it and returns the resulting state.
  static Future<StartupStatus> disable() => _invokeStatus('disable');

  static Future<StartupStatus> _invokeStatus(String method) async {
    if (!Platform.isWindows) return StartupStatus.unavailable;

    try {
      final String? status = await _channel.invokeMethod<String>(method);
      return StartupStatus.values.firstWhere(
        (StartupStatus candidate) => candidate.name == status,
        orElse: () => StartupStatus.error,
      );
    } catch (error, stack) {
      _logError('Windows startup operation "$method" failed', error, stack);
      return StartupStatus.error;
    }
  }

  static void _logError(String message, Object error, StackTrace stack) {
    unawaited(ErrorLogger.log('StartupManager', '$message: $error', stack));
  }
}
