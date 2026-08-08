import 'platform_models.dart';

/// Monitor geometry owned by the active platform adapter.
abstract class MonitorService {
  static MonitorService _instance = const UnavailableMonitorService();

  static MonitorService get instance => _instance;

  static void register(MonitorService service) {
    _instance = service;
  }

  const MonitorService();

  bool get isAvailable;
  String get unavailableReason;
  Future<List<PlatformMonitor>> enumerate();
  Future<PlatformMonitor?> cursorMonitor();

  /// Returns the cursor in the adapter's global logical coordinate space.
  /// Platforms that cannot expose a global pointer position may return null.
  Future<PlatformPoint?> cursorPosition() async => null;

  Future<PlatformPopupPlacement?> placePopup({
    required double width,
    required double height,
    double margin = 8,
    String? monitorId,
  });
}

class UnavailableMonitorService extends MonitorService {
  const UnavailableMonitorService();

  @override
  bool get isAvailable => false;

  @override
  String get unavailableReason => 'Monitor geometry is unavailable on this platform.';

  @override
  Future<List<PlatformMonitor>> enumerate() async => const <PlatformMonitor>[];

  @override
  Future<PlatformMonitor?> cursorMonitor() async => null;

  @override
  Future<PlatformPoint?> cursorPosition() async => null;

  @override
  Future<PlatformPopupPlacement?> placePopup({
    required double width,
    required double height,
    double margin = 8,
    String? monitorId,
  }) async =>
      null;
}
