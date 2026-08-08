import '../platform_capabilities.dart';
import '../platform_models.dart';
import '../window_service.dart';
import 'macos_platform_channel.dart';

class MacOSWindowService extends WindowService {
  MacOSWindowService({MacOSPlatformChannel? channel}) : channel = channel ?? MacOSPlatformChannel.instance;

  final MacOSPlatformChannel channel;

  @override
  bool get isAvailable => channel.isAvailable && PlatformCapabilities.current.windowEnumeration;

  @override
  String get unavailableReason {
    if (!channel.isAvailable) return 'The macOS window service is unavailable.';
    if (!PlatformCapabilities.current.windowEnumeration) {
      return 'Window search requires macOS Screen Recording permission.';
    }
    return '';
  }

  @override
  bool get isActivationAvailable => channel.isAvailable && PlatformCapabilities.current.windowActivation;

  @override
  String get activationUnavailableReason {
    if (!channel.isAvailable) return 'The macOS window service is unavailable.';
    if (!PlatformCapabilities.current.windowActivation) {
      return 'Activating another app requires macOS Accessibility permission.';
    }
    return '';
  }

  @override
  Future<List<PlatformWindow>> enumerate() async {
    if (!isAvailable) return const <PlatformWindow>[];
    return channel.listWindows();
  }

  @override
  Future<bool> activate(PlatformWindow window) =>
      isActivationAvailable ? channel.activateWindow(window.nativeId) : Future<bool>.value(false);

  @override
  Future<String?> captureFocus() => channel.captureFocus();

  @override
  Future<bool> restoreFocus(String? token) => channel.restoreFocus(token);
}
