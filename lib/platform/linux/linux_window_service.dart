import '../platform_models.dart';
import '../window_service.dart';
import 'linux_platform_channel.dart';

class LinuxWindowService extends WindowService {
  LinuxWindowService({LinuxPlatformChannel? channel}) : channel = channel ?? LinuxPlatformChannel.instance;

  final LinuxPlatformChannel channel;

  @override
  bool get isAvailable => channel.cachedCapabilities.windowEnumeration;

  @override
  String get unavailableReason {
    if (isAvailable) return '';
    final String probedReason = channel.cachedCapabilities.reasonFor('windowEnumeration');
    if (probedReason.isNotEmpty) return probedReason;
    if (channel.cachedCapabilities.isWaylandOnly) {
      return 'X11 window enumeration is unavailable in a Wayland session.';
    }
    return 'The Linux X11 window service is unavailable.';
  }

  @override
  Future<List<PlatformWindow>> enumerate() => channel.listWindows();

  @override
  Future<bool> activate(PlatformWindow window) => channel.activateWindow(window.nativeId);

  @override
  Future<String?> captureFocus() => channel.captureFocus();

  @override
  Future<bool> restoreFocus(String? token) => channel.restoreFocus(token);
}
