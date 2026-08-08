import '../notification_service.dart';
import 'linux_platform_channel.dart';

/// Sends notifications through org.freedesktop.Notifications. The native
/// adapter checks for the D-Bus service before advertising this capability.
class LinuxNotificationService extends NotificationService {
  LinuxNotificationService({LinuxPlatformChannel? channel}) : channel = channel ?? LinuxPlatformChannel.instance;

  final LinuxPlatformChannel channel;

  @override
  bool get isAvailable => channel.cachedCapabilities.notifications;

  @override
  bool get supportsClick => false;

  @override
  String get unavailableReason {
    if (isAvailable) return '';
    final String probedReason = channel.cachedCapabilities.reasonFor('notifications');
    return probedReason.isNotEmpty
        ? probedReason
        : 'No freedesktop notification daemon is available on the current Linux session.';
  }

  @override
  Future<bool> initialize() async {
    await channel.refreshCapabilities();
    return isAvailable;
  }

  @override
  Future<bool> show(NotificationRequest request) async {
    if (!await initialize()) return false;
    return channel.showNotification(title: request.title, body: request.body);
  }
}
