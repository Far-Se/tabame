import 'dart:io';

import '../notification_service.dart';
import 'macos_platform_channel.dart';

/// Notification permission is requested on first use, not during startup.
class MacOSNotificationService extends NotificationService {
  MacOSNotificationService({
    MacOSPlatformChannel? channel,
    String appName = 'Tabame',
  })  : channel = channel ?? MacOSPlatformChannel.instance,
        delegate = LocalNotifierNotificationService(appName: appName);

  final MacOSPlatformChannel channel;
  final LocalNotifierNotificationService delegate;
  MacOSPermissionStatus _status = MacOSPermissionStatus.unknown;

  @override
  bool get isAvailable => Platform.isMacOS && channel.isAvailable;

  @override
  String get unavailableReason {
    if (!isAvailable) return 'macOS notifications are unavailable in this process.';
    if (_status == MacOSPermissionStatus.denied) {
      return 'Notifications are disabled for Tabame. Enable them in System Settings to receive alerts.';
    }
    return '';
  }

  @override
  Future<bool> initialize() async {
    if (!isAvailable) return false;
    // local_notifier setup is non-interactive; the native permission request is
    // deliberately deferred until the first notification is sent.
    return delegate.initialize();
  }

  @override
  Future<bool> show(NotificationRequest request) async {
    if (!isAvailable) return false;
    final MacOSPermissionSnapshot snapshot = await channel.permissionStates();
    MacOSPermissionState state = snapshot.stateFor(MacOSPermission.notifications);
    if (!state.isGranted) {
      state = await channel.requestPermission(MacOSPermission.notifications);
    }
    _status = state.status;
    if (!state.isGranted) return false;
    return delegate.show(request);
  }
}
