import '../platform_capabilities.dart';
import '../platform_models.dart';
import '../quick_snap_service.dart';
import 'macos_platform_channel.dart';

/// macOS target adapter for manual QuickSnap placement.
///
/// Accessibility owns the actual move/resize operation. The adapter accepts
/// only neutral bounds and translates the opaque window identity inside the
/// native bridge. macOS does not expose a Windows-style move/size drag stream,
/// so drag-triggered and standalone overlay modes remain unavailable.
class MacOSQuickSnapService extends QuickSnapService {
  MacOSQuickSnapService({MacOSPlatformChannel? channel, bool? available})
      : channel = channel ?? MacOSPlatformChannel.instance,
        _availableOverride = available;

  final MacOSPlatformChannel channel;
  final bool? _availableOverride;

  @override
  bool get isAvailable =>
      _availableOverride ??
      (channel.isAvailable &&
          PlatformCapabilities.current.windowEnumeration &&
          PlatformCapabilities.current.windowActivation);

  @override
  String get unavailableReason {
    if (!channel.isAvailable) return 'The macOS QuickSnap adapter is unavailable.';
    if (!PlatformCapabilities.current.windowEnumeration && _availableOverride != true) {
      return 'QuickSnap needs macOS Screen Recording permission to list windows.';
    }
    if (!PlatformCapabilities.current.windowActivation && _availableOverride != true) {
      return 'QuickSnap needs macOS Accessibility permission to move and resize windows.';
    }
    return isAvailable ? '' : 'macOS window snapping is unavailable.';
  }

  @override
  String get dragUnavailableReason =>
      'macOS manual QuickSnap is available, but native window-drag triggers are intentionally deferred.';

  @override
  Stream<PlatformQuickSnapEvent> get events => const Stream<PlatformQuickSnapEvent>.empty();

  @override
  Future<bool> snap({
    required PlatformWindow window,
    required PlatformMonitor monitor,
    required PlatformSnapZone zone,
    double gap = 0,
    double topInset = 0,
  }) async {
    if (!isAvailable || !zone.isValid) return false;
    final PlatformRect rect = QuickSnapGeometry.zoneRect(
      monitor,
      zone,
      gap: gap,
      topInset: topInset,
    );
    return channel.snapWindow(
      nativeId: window.identity,
      x: rect.left,
      y: rect.top,
      width: rect.width,
      height: rect.height,
    );
  }

  @override
  Future<bool> restore(PlatformWindow window) =>
      isAvailable ? channel.restoreWindow(window.identity) : Future<bool>.value(false);
}
