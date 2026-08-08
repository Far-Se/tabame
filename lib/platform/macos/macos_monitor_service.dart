import '../monitor_service.dart';
import '../platform_models.dart';
import 'macos_platform_channel.dart';

class MacOSMonitorService extends MonitorService {
  MacOSMonitorService({MacOSPlatformChannel? channel}) : channel = channel ?? MacOSPlatformChannel.instance;

  final MacOSPlatformChannel channel;

  @override
  bool get isAvailable => channel.isAvailable;

  @override
  String get unavailableReason => isAvailable ? '' : 'The macOS monitor service is unavailable.';

  @override
  Future<List<PlatformMonitor>> enumerate() => channel.listMonitors();

  @override
  Future<PlatformMonitor?> cursorMonitor() => channel.cursorMonitor();

  @override
  Future<PlatformPoint?> cursorPosition() => channel.cursorPosition();

  @override
  Future<PlatformPopupPlacement?> placePopup({
    required double width,
    required double height,
    double margin = 8,
    String? monitorId,
  }) {
    return channel.placePopup(
      width: width,
      height: height,
      margin: margin,
      monitorId: monitorId,
    );
  }
}
