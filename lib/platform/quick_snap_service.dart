import 'platform_models.dart';

/// A platform-neutral rectangle in global logical desktop coordinates.
class PlatformRect {
  const PlatformRect({required this.left, required this.top, required this.right, required this.bottom});

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right > left ? right - left : 0;
  double get height => bottom > top ? bottom - top : 0;
  double get centerX => left + width / 2;
  double get centerY => top + height / 2;

  bool contains(double x, double y) => x >= left && x <= right && y >= top && y <= bottom;
}

/// Fractional monitor-relative coordinates persisted by the QuickSnap editor.
class PlatformSnapZone {
  const PlatformSnapZone({required this.left, required this.top, required this.right, required this.bottom});

  final double left;
  final double top;
  final double right;
  final double bottom;

  bool get isValid => left >= 0 && top >= 0 && right <= 1 && bottom <= 1 && right > left && bottom > top;
}

enum PlatformQuickSnapEventType {
  open,
  moveStart,
  moveEnd,
  selecting,
  selected,
  switchUp,
  switchDown,
}

/// Neutral event emitted by a platform adapter's optional drag-trigger path.
/// [window] is a complete neutral snapshot; its identity remains opaque.
class PlatformQuickSnapEvent {
  const PlatformQuickSnapEvent({required this.type, this.window});

  final PlatformQuickSnapEventType type;
  final PlatformWindow? window;
}

/// Opaque state returned while the Windows QuickSnap overlay temporarily takes
/// over the Tabame window. Shared code can pass it back without knowing styles,
/// handles, or native window state.
class PlatformQuickSnapOverlayState {
  const PlatformQuickSnapOverlayState({this.width = 0, this.height = 0});

  final double width;
  final double height;
}

/// Shared monitor/window selection and zone geometry used by every adapter.
class QuickSnapGeometry {
  QuickSnapGeometry._();

  static PlatformMonitor? monitorForWindow(PlatformWindow window, Iterable<PlatformMonitor> monitors) {
    final List<PlatformMonitor> available = monitors.toList(growable: false);
    if (available.isEmpty) return null;

    final double centerX = window.x + window.width / 2;
    final double centerY = window.y + window.height / 2;
    return monitorForPoint(centerX, centerY, available) ?? _nearestMonitor(centerX, centerY, available);
  }

  static PlatformMonitor? monitorForPoint(double x, double y, Iterable<PlatformMonitor> monitors) {
    for (final PlatformMonitor monitor in monitors) {
      if (x >= monitor.x && x <= monitor.x + monitor.width && y >= monitor.y && y <= monitor.y + monitor.height) {
        return monitor;
      }
    }
    return null;
  }

  static PlatformMonitor? _nearestMonitor(double x, double y, List<PlatformMonitor> monitors) {
    PlatformMonitor? nearest;
    double bestDistance = double.infinity;
    for (final PlatformMonitor monitor in monitors) {
      final double dx = x < monitor.x
          ? monitor.x - x
          : x > monitor.x + monitor.width
              ? x - (monitor.x + monitor.width)
              : 0;
      final double dy = y < monitor.y
          ? monitor.y - y
          : y > monitor.y + monitor.height
              ? y - (monitor.y + monitor.height)
              : 0;
      final double distance = dx * dx + dy * dy;
      if (distance < bestDistance) {
        bestDistance = distance;
        nearest = monitor;
      }
    }
    return nearest;
  }

  /// Resolves a zone with a symmetric gap. [topInset] reserves space at the
  /// top of the zone for an adapter-owned overlay strip.
  static PlatformRect zoneRect(
    PlatformMonitor monitor,
    PlatformSnapZone zone, {
    double gap = 0,
    double topInset = 0,
  }) {
    final double left = monitor.x + zone.left * monitor.width;
    final double top = monitor.y + zone.top * monitor.height;
    final double right = monitor.x + zone.right * monitor.width;
    final double bottom = monitor.y + zone.bottom * monitor.height;
    final double halfGap = gap / 2;
    final double resolvedLeft = left + halfGap;
    final double resolvedTop = top + topInset + halfGap;
    final double resolvedRight = right - halfGap > resolvedLeft ? right - halfGap : resolvedLeft;
    final double resolvedBottom = bottom - halfGap > resolvedTop ? bottom - halfGap : resolvedTop;
    return PlatformRect(
      left: resolvedLeft,
      top: resolvedTop,
      right: resolvedRight,
      bottom: resolvedBottom,
    );
  }
}

/// Contract for monitor-aware window snapping and its optional drag triggers.
/// Native identifiers never cross this API as typed handles.
abstract class QuickSnapService {
  static QuickSnapService _instance = const UnavailableQuickSnapService();

  static QuickSnapService get instance => _instance;

  static void register(QuickSnapService service) {
    _instance = service;
  }

  const QuickSnapService();

  bool get isAvailable;
  bool get supportsDragTriggers => false;
  bool get supportsStandalone => false;
  String get unavailableReason;
  String get dragUnavailableReason => 'Window drag-triggered QuickSnap is unavailable on this platform.';

  Stream<PlatformQuickSnapEvent> get events;

  Future<void> enable({bool rightClickToTrigger = true}) async {}

  Future<void> enableStandalone() async => enable(rightClickToTrigger: false);

  Future<void> disable() async {}

  Future<bool> snap({
    required PlatformWindow window,
    required PlatformMonitor monitor,
    required PlatformSnapZone zone,
    double gap = 0,
    double topInset = 0,
  }) async =>
      false;

  Future<bool> restore(PlatformWindow window) async => false;

  Future<bool> toggleStandalone() async => false;

  Future<PlatformQuickSnapOverlayState?> prepareOverlay(PlatformMonitor monitor) async => null;

  Future<void> restoreOverlay(PlatformQuickSnapOverlayState? state) async {}
}

class UnavailableQuickSnapService extends QuickSnapService {
  const UnavailableQuickSnapService();

  @override
  bool get isAvailable => false;

  @override
  String get unavailableReason => 'Monitor-aware window snapping is unavailable on this platform.';

  @override
  Stream<PlatformQuickSnapEvent> get events => const Stream<PlatformQuickSnapEvent>.empty();
}
