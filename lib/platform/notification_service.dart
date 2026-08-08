import 'dart:io';

import 'package:local_notifier/local_notifier.dart';

/// Platform-neutral notification payload.
///
/// Native identifiers, D-Bus values, and OS-specific callback objects stay in
/// the adapter. A click handler is optional because some desktop daemons only
/// support fire-and-forget delivery.
class NotificationRequest {
  const NotificationRequest({
    required this.title,
    required this.body,
    this.onClick,
  });

  final String title;
  final String body;
  final void Function()? onClick;
}

abstract class NotificationService {
  static NotificationService _instance = const UnavailableNotificationService();

  static NotificationService get instance => _instance;

  static void register(NotificationService service) {
    _instance = service;
  }

  const NotificationService();

  bool get isAvailable;
  bool get supportsClick => false;
  String get unavailableReason;
  Future<bool> initialize();
  Future<bool> show(NotificationRequest request);
}

class UnavailableNotificationService extends NotificationService {
  const UnavailableNotificationService();

  @override
  bool get isAvailable => false;

  @override
  String get unavailableReason => 'Desktop notifications are unavailable on this platform.';

  @override
  Future<bool> initialize() async => false;

  @override
  Future<bool> show(NotificationRequest request) async => false;
}

/// Uses the existing local_notifier plugin on desktop targets supported by its
/// generated plugin implementations. Failures become a recoverable status,
/// never a startup exception.
class LocalNotifierNotificationService extends NotificationService {
  LocalNotifierNotificationService({this.appName = 'Tabame'});

  final String appName;
  bool _initialized = false;

  @override
  bool get isAvailable => Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  @override
  bool get supportsClick => isAvailable;

  @override
  String get unavailableReason => isAvailable ? '' : 'Desktop notifications are unavailable on this platform.';

  @override
  Future<bool> initialize() async {
    if (!isAvailable) return false;
    if (_initialized) return true;
    try {
      await localNotifier.setup(appName: appName);
      _initialized = true;
      return true;
    } catch (_) {
      return false;
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
