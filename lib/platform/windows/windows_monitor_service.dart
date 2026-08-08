import 'dart:io';

import '../monitor_service.dart';
import '../platform_models.dart';
import '../quick_snap_service.dart';
import '../../models/win32/mixed.dart';
import '../../models/win32/win32.dart';

/// Testable native boundary for Windows monitor geometry.
abstract class WindowsMonitorBridge {
  bool get isAvailable;
  Future<List<PlatformMonitor>> enumerate();
  Future<PlatformPoint?> cursorPosition();
}

/// Windows adapter for monitor bounds, DPI, cursor placement, and popup math.
class WindowsNativeMonitorBridge implements WindowsMonitorBridge {
  const WindowsNativeMonitorBridge();

  @override
  bool get isAvailable => Platform.isWindows;

  @override
  Future<List<PlatformMonitor>> enumerate() async {
    if (!isAvailable) return const <PlatformMonitor>[];
    Monitor.fetchMonitors();
    final List<int> handles = List<int>.from(Monitor.list);
    final List<PlatformMonitor> monitors = <PlatformMonitor>[];
    for (int index = 0; index < handles.length; index++) {
      final Square? bounds = Monitor.monitorSizes[handles[index]];
      if (bounds == null) continue;
      monitors.add(fromNative(handle: handles[index], bounds: bounds, isPrimary: index == 0));
    }
    return monitors;
  }

  @override
  Future<PlatformPoint?> cursorPosition() async {
    if (!isAvailable) return null;
    final ({int x, int y}) position = Win32.getCursorPosRaw();
    return PlatformPoint(x: position.x.toDouble(), y: position.y.toDouble());
  }

  static PlatformMonitor fromNative({required int handle, required Square bounds, required bool isPrimary}) {
    return PlatformMonitor(
      nativeId: '$handle',
      x: bounds.x.toDouble(),
      y: bounds.y.toDouble(),
      width: bounds.width.toDouble(),
      height: bounds.height.toDouble(),
      visibleX: bounds.x.toDouble(),
      visibleY: bounds.y.toDouble(),
      visibleWidth: bounds.width.toDouble(),
      visibleHeight: bounds.height.toDouble(),
      scaleFactor: Monitor.dpi[handle]?.coef ?? 1,
      isPrimary: isPrimary,
    );
  }
}

class WindowsMonitorService extends MonitorService {
  WindowsMonitorService({WindowsMonitorBridge? bridge}) : bridge = bridge ?? const WindowsNativeMonitorBridge();

  final WindowsMonitorBridge bridge;

  @override
  bool get isAvailable => bridge.isAvailable;

  @override
  String get unavailableReason => isAvailable ? '' : 'The Windows monitor service is unavailable.';

  @override
  Future<List<PlatformMonitor>> enumerate() => bridge.enumerate();

  @override
  Future<PlatformPoint?> cursorPosition() => bridge.cursorPosition();

  @override
  Future<PlatformMonitor?> cursorMonitor() async {
    final List<PlatformMonitor> monitors = await enumerate();
    if (monitors.isEmpty) return null;
    final PlatformPoint? cursor = await cursorPosition();
    if (cursor == null)
      return monitors.firstWhere(
        (PlatformMonitor monitor) => monitor.isPrimary,
        orElse: () => monitors.first,
      );
    return QuickSnapGeometry.monitorForPoint(cursor.x, cursor.y, monitors) ?? monitors.first;
  }

  @override
  Future<PlatformPopupPlacement?> placePopup({
    required double width,
    required double height,
    double margin = 8,
    String? monitorId,
  }) async {
    final List<PlatformMonitor> monitors = await enumerate();
    if (monitors.isEmpty || width <= 0 || height <= 0) return null;
    PlatformMonitor? requested;
    if (monitorId != null) {
      for (final PlatformMonitor candidate in monitors) {
        if (candidate.identity == monitorId) {
          requested = candidate;
          break;
        }
      }
    }
    final PlatformMonitor monitor = requested ?? await cursorMonitor() ?? monitors.first;
    final double left = monitor.visibleX + margin;
    final double top = monitor.visibleY + margin;
    final double rightEdge = monitor.visibleX + monitor.visibleWidth - margin - width;
    final double bottomEdge = monitor.visibleY + monitor.visibleHeight - margin - height;
    final double right = rightEdge > left ? rightEdge : left;
    final double bottom = bottomEdge > top ? bottomEdge : top;
    final double centeredX = monitor.visibleX + monitor.visibleWidth / 2 - width / 2;
    final double centeredY = monitor.visibleY + monitor.visibleHeight / 2 - height / 2;
    return PlatformPopupPlacement(
      x: centeredX.clamp(left, right).toDouble(),
      y: centeredY.clamp(top, bottom).toDouble(),
      width: width,
      height: height,
      monitorId: monitor.identity,
    );
  }
}
