import 'dart:io';

import 'package:local_notifier/local_notifier.dart';

import '../notification_service.dart';

/// Native seam for the Windows desktop notification backend.
///
/// The shared notification contract never sees LocalNotification or Windows
/// registration details. Tests can inject a fake backend without loading the
/// Windows plugin.
abstract class WindowsNotificationBackend {
  bool get isAvailable;
  bool get supportsClick;
  Future<bool> initialize();
  Future<bool> show(NotificationRequest request);
}

/// Uses local_notifier for the existing Windows toast behavior.
class LocalNotifierWindowsNotificationBackend implements WindowsNotificationBackend {
  LocalNotifierWindowsNotificationBackend({this.appName = 'Tabame'});

  final String appName;
  bool _initialized = false;
  Future<bool>? _initialization;

  @override
  bool get isAvailable => Platform.isWindows;

  @override
  bool get supportsClick => isAvailable;

  @override
  Future<bool> initialize() {
    if (!isAvailable) return Future<bool>.value(false);
    if (_initialized) return Future<bool>.value(true);
    return _initialization ??= _initialize();
  }

  Future<bool> _initialize() async {
    try {
      await localNotifier.setup(
        appName: appName,
        shortcutPolicy: ShortcutPolicy.requireCreate,
      );
      _initialized = true;
      return true;
    } catch (_) {
      return false;
    } finally {
      _initialization = null;
    }
  }

  @override
  Future<bool> show(NotificationRequest request) async {
    if (!await initialize()) return false;
    try {
      final LocalNotification notification = LocalNotification(
        title: request.title,
        body: request.body,
      );
      if (request.onClick != null) {
        notification.onClick = () => request.onClick!.call();
      }
      await notification.show();
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// Windows adapter for the neutral [NotificationService] contract.
class WindowsNotificationService extends NotificationService {
  WindowsNotificationService({WindowsNotificationBackend? backend})
      : backend = backend ?? LocalNotifierWindowsNotificationBackend();

  final WindowsNotificationBackend backend;

  @override
  bool get isAvailable => backend.isAvailable;

  @override
  bool get supportsClick => backend.supportsClick;

  @override
  String get unavailableReason => isAvailable ? '' : 'Windows desktop notifications are unavailable.';

  @override
  Future<bool> initialize() async {
    try {
      return await backend.initialize();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> show(NotificationRequest request) async {
    try {
      return await backend.show(request);
    } catch (_) {
      return false;
    }
  }
}
