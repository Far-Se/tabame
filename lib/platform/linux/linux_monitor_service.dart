import '../monitor_service.dart';
import '../platform_models.dart';
import 'linux_platform_channel.dart';

class LinuxMonitorService extends MonitorService {
  LinuxMonitorService({LinuxPlatformChannel? channel}) : channel = channel ?? LinuxPlatformChannel.instance;

  final LinuxPlatformChannel channel;

  @override
  bool get isAvailable => channel.cachedCapabilities.monitorGeometry;

  @override
  String get unavailableReason {
    if (isAvailable) return '';
    final String probedReason = channel.cachedCapabilities.reasonFor('monitorGeometry');
    if (probedReason.isNotEmpty) return probedReason;
    if (channel.cachedCapabilities.isWaylandOnly) {
      return 'X11 monitor geometry is not exposed by the Linux Wayland adapter.';
    }
    return 'The Linux monitor service is unavailable.';
  }

  @override
  Future<List<PlatformMonitor>> enumerate() => channel.listMonitors();

  @override
  Future<PlatformMonitor?> cursorMonitor() => channel.cursorMonitor();

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
