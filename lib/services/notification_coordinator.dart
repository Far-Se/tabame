import '../platform/notification_service.dart';

/// Shared notification orchestration for timers, reminders, plugins, and UI.
///
/// Callers provide only user-facing content. The coordinator keeps delivery
/// best-effort so a missing desktop daemon or a native backend failure cannot
/// escape from a timer callback or background plugin process.
class NotificationCoordinator {
  NotificationCoordinator._();

  static final NotificationCoordinator instance = NotificationCoordinator._();

  bool get isAvailable => NotificationService.instance.isAvailable;
  bool get supportsClick => NotificationService.instance.supportsClick;
  String get unavailableReason => NotificationService.instance.unavailableReason;

  Future<bool> show({
    required String title,
    required String body,
    void Function()? onClick,
  }) async {
    try {
      return await NotificationService.instance.show(
        NotificationRequest(
          title: title,
          body: body,
          onClick: onClick,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
