import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../models/classes/saved_maps.dart';
import '../../models/win32/imports.dart';
import '../../models/win32/mixed.dart';
import '../../models/win32/win32.dart';
import '../../models/win32/win_utils.dart';
import '../../models/win32/window.dart';
import '../monitor_service.dart';
import '../platform_models.dart';
import '../quick_snap_service.dart';
import 'tabamewin32_api.dart';
import 'win32_api.dart';

import 'windows_native_window_bridge.dart';

/// Event crossing the Windows adapter boundary before it becomes neutral.
class WindowsQuickSnapEvent {
  const WindowsQuickSnapEvent({required this.action, required this.handle});

  final String action;
  final int handle;
}

/// Testable boundary for Windows QuickSnap behavior.
abstract class WindowsQuickSnapBridge {
  bool get isAvailable;
  Stream<WindowsQuickSnapEvent> get events;

  Future<void> enable({bool rightClickToTrigger = true}) async {}
  Future<void> enableStandalone() async => enable(rightClickToTrigger: false);
  Future<void> disable() async {}

  Future<PlatformWindow?> resolveWindow(int handle) async => null;

  Future<bool> snap({
    required PlatformWindow window,
    required PlatformMonitor monitor,
    required PlatformSnapZone zone,
    double gap = 0,
    double topInset = 0,
  }) async =>
      false;

  Future<bool> restore(PlatformWindow window) async => false;
  Future<bool> restoreForDrag(PlatformWindow window) => restore(window);
  Future<bool> toggleStandalone() async => false;
  Future<PlatformQuickSnapOverlayState?> prepareOverlay(PlatformMonitor monitor) async => null;
  Future<void> restoreOverlay(PlatformQuickSnapOverlayState? state) async {}
}

/// Native Windows implementation. Win32 handles, DPI, DWM borders, and the
/// legacy native views event stream are deliberately kept in this adapter.
class WindowsNativeQuickSnapBridge extends WindowsQuickSnapBridge implements TabameListener {
  WindowsNativeQuickSnapBridge() {
    if (Platform.isWindows) {
      NativeHooks.registerCallHandler();
      NativeHooks.addListener(this);
    }
  }

  final StreamController<WindowsQuickSnapEvent> _events = StreamController<WindowsQuickSnapEvent>.broadcast();
  final Map<String, List<int>> _originalSizes = <String, List<int>>{};
  int? _overlayOriginalExStyle;

  @override
  bool get isAvailable => Platform.isWindows;

  @override
  Stream<WindowsQuickSnapEvent> get events => _events.stream;

  @override
  Future<void> enable({bool rightClickToTrigger = true}) async {
    if (!isAvailable) return;
    await enableViews(true, rightClickToTrigger: rightClickToTrigger);
  }

  @override
  Future<void> enableStandalone() async {
    if (!isAvailable) return;
    await enableViews(true, rightClickToTrigger: false);
    await NativeHooks.hook();
  }

  @override
  Future<void> disable() async {
    if (!isAvailable) return;
    await enableViews(false);
  }

  @override
  Future<PlatformWindow?> resolveWindow(int handle) async {
    if (!isAvailable || handle == 0) return null;
    final List<PlatformWindow> windows = await const WindowsNativeWindowBridge().enumerate();
    for (final PlatformWindow window in windows) {
      if (window.identity == '$handle') return window;
    }
    return null;
  }

  @override
  Future<bool> snap({
    required PlatformWindow window,
    required PlatformMonitor monitor,
    required PlatformSnapZone zone,
    double gap = 0,
    double topInset = 0,
  }) async {
    final int? handle = int.tryParse(window.identity);
    final int? monitorHandle = int.tryParse(monitor.identity);
    if (!isAvailable || handle == null || monitorHandle == null || !zone.isValid || IsWindow(handle) == 0) return false;

    Monitor.fetchMonitors();
    final Square? bounds = Monitor.monitorSizes[monitorHandle];
    if (bounds == null) return false;

    final Dpi? dpi = Monitor.dpi[monitorHandle];
    final double scaleX = dpi != null ? dpi.x / 96.0 : monitor.scaleFactor;
    final double scaleY = dpi != null ? dpi.y / 96.0 : monitor.scaleFactor;
    final double mx = bounds.x / scaleX;
    final double my = bounds.y / scaleY;
    final double mw = bounds.width / scaleX;
    final double mh = bounds.height / scaleY;

    Win32.restoreIfMaximized(handle);
    _originalSizes.putIfAbsent(window.identity, () {
      final ({int height, int width}) size = Win32.getSize(hwnd: handle);
      return <int>[size.width, size.height];
    });

    final ({int bottom, int left, int right, int top}) border = Win32.getInvisibleBorder(handle);
    final double borderLeft = border.left / scaleX;
    final double borderTop = border.top / scaleY;
    final double borderRight = border.right / scaleX;
    final double borderBottom = border.bottom / scaleY;
    final double logicalGap = gap / scaleX;
    final double halfGap = logicalGap / 2;
    final double logicalTopInset = topInset / scaleY;

    final double zx = mx + zone.left * mw;
    final double zy = my + zone.top * mh + logicalTopInset;
    final double zw = (zone.right - zone.left) * mw;
    final double zh = (zone.bottom - zone.top) * mh - logicalTopInset;
    final int x = (zx - borderLeft + halfGap).round();
    final int y = (zy - borderTop + halfGap).round();
    final int width = (zw + borderLeft + borderRight - logicalGap).round().clamp(100, mw.round()).toInt();
    final int height = (zh + borderTop + borderBottom - logicalGap).round().clamp(60, mh.round()).toInt();

    Win32.setPosDPI(handle, PointXY(X: x, Y: y), logicalWidth: width, logicalHeight: height);
    return true;
  }

  @override
  Future<bool> restore(PlatformWindow window) async {
    final int? handle = int.tryParse(window.identity);
    final List<int>? original = _originalSizes.remove(window.identity);
    if (!isAvailable || handle == null || original == null || IsWindow(handle) == 0) return false;
    final Square current = Win32.getWindowRect(hwnd: handle);
    Win32.changePosition(handle, current.x, current.y, original[0], original[1]);
    return true;
  }

  @override
  Future<bool> restoreForDrag(PlatformWindow window) async {
    final int? handle = int.tryParse(window.identity);
    final List<int>? original = _originalSizes.remove(window.identity);
    if (!isAvailable || handle == null || original == null || IsWindow(handle) == 0) return false;
    WinUtils.restoreAndReattachDrag(handle, original[0], original[1]);
    return true;
  }

  @override
  Future<bool> toggleStandalone() async {
    if (!isAvailable) return false;
    final int existing = Win32.findWindow('Tabame QuickSnap');
    if (existing != 0) {
      Win32.closeWindow(existing);
      return true;
    }
    WinUtils.startTabame(closeCurrent: false, arguments: '-quickSnap', admin: true);
    return true;
  }

  @override
  Future<PlatformQuickSnapOverlayState?> prepareOverlay(PlatformMonitor monitor) async {
    if (!isAvailable || Win32.hWnd == 0) return null;
    final Size size = await windowManager.getSize();
    final int exStyle = GetWindowLong(Win32.hWnd, GWL_EXSTYLE);
    _overlayOriginalExStyle = exStyle;
    SetWindowLongPtr(Win32.hWnd, GWL_EXSTYLE, exStyle | WS_EX_LAYERED | WS_EX_TOOLWINDOW);
    SetLayeredWindowAttributes(Win32.hWnd, 0, 0, LWA_ALPHA);

    final ({int? x, int? y, int? width, int? height}) sizeData = Win32.setDPIAware(
      Win32.hWnd,
      monitor.x.round(),
      monitor.y.round(),
      monitor.width.round(),
      monitor.height.round(),
    );
    if (sizeData.x != null && sizeData.y != null && sizeData.width != null && sizeData.height != null) {
      SetWindowPos(
        Win32.hWnd,
        HWND_TOP,
        sizeData.x!,
        sizeData.y!,
        sizeData.width!,
        sizeData.height!,
        SWP_NOZORDER | SWP_NOACTIVATE,
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    SetLayeredWindowAttributes(Win32.hWnd, 0, 255, LWA_ALPHA);
    return PlatformQuickSnapOverlayState(width: size.width, height: size.height);
  }

  @override
  Future<void> restoreOverlay(PlatformQuickSnapOverlayState? state) async {
    if (!isAvailable || Win32.hWnd == 0) return;
    SetLayeredWindowAttributes(Win32.hWnd, 0, 0, LWA_ALPHA);
    await Future<void>.delayed(const Duration(milliseconds: 32));
    if (state != null && state.width > 0 && state.height > 0) {
      await windowManager.setSize(Size(state.width, state.height));
    }
    final int exStyle = _overlayOriginalExStyle ?? GetWindowLong(Win32.hWnd, GWL_EXSTYLE);
    SetWindowLongPtr(Win32.hWnd, GWL_EXSTYLE, exStyle & ~WS_EX_TRANSPARENT & ~WS_EX_LAYERED & ~WS_EX_TOOLWINDOW);
    SetLayeredWindowAttributes(Win32.hWnd, 0, 255, LWA_ALPHA);
    _overlayOriginalExStyle = null;
  }

  @override
  void onHotKeyEvent(HotkeyEvent hotkeyInfo) {}

  @override
  void onDisplayChange(MonitorEvent hotkeyInfo) {}

  @override
  void onForegroundWindowChanged(int hWnd) {}

  @override
  void onTricktivityEvent(String action, String info) {}

  @override
  void onWinEventReceived(int hWnd, WinEventType type) {}

  @override
  void onQuickClickEvent(String eventName, Map<String, String> params) {}

  @override
  void onKeyVizEvent(KeyVizEvent event) {}

  @override
  void onMouseGesture(String button, String pattern, int durationMs) {}

  @override
  void onViewsEvent(ViewsAction action, int hWnd) {
    if (!_events.isClosed) _events.add(WindowsQuickSnapEvent(action: action.name, handle: hWnd));
  }
}

/// Dart contract implementation for the Windows adapter.
class WindowsQuickSnapService extends QuickSnapService {
  WindowsQuickSnapService({WindowsQuickSnapBridge? bridge}) : bridge = bridge ?? WindowsNativeQuickSnapBridge() {
    _bridgeEvents = this.bridge.events.listen(_onBridgeEvent);
  }

  final WindowsQuickSnapBridge bridge;
  late final StreamSubscription<WindowsQuickSnapEvent> _bridgeEvents;
  final StreamController<PlatformQuickSnapEvent> _events = StreamController<PlatformQuickSnapEvent>.broadcast();

  @override
  bool get isAvailable => bridge.isAvailable;

  @override
  bool get supportsDragTriggers => isAvailable;

  @override
  bool get supportsStandalone => isAvailable;

  @override
  String get unavailableReason => isAvailable ? '' : 'Windows QuickSnap is unavailable on this platform.';

  @override
  String get dragUnavailableReason => isAvailable ? '' : unavailableReason;

  @override
  Stream<PlatformQuickSnapEvent> get events => _events.stream;

  @override
  Future<void> enable({bool rightClickToTrigger = true}) => bridge.enable(rightClickToTrigger: rightClickToTrigger);

  @override
  Future<void> enableStandalone() => bridge.enableStandalone();

  @override
  Future<void> disable() => bridge.disable();

  @override
  Future<bool> snap({
    required PlatformWindow window,
    required PlatformMonitor monitor,
    required PlatformSnapZone zone,
    double gap = 0,
    double topInset = 0,
  }) =>
      bridge.snap(window: window, monitor: monitor, zone: zone, gap: gap, topInset: topInset);

  @override
  Future<bool> restore(PlatformWindow window) => bridge.restore(window);

  @override
  Future<bool> toggleStandalone() => bridge.toggleStandalone();

  @override
  Future<PlatformQuickSnapOverlayState?> prepareOverlay(PlatformMonitor monitor) => bridge.prepareOverlay(monitor);

  @override
  Future<void> restoreOverlay(PlatformQuickSnapOverlayState? state) => bridge.restoreOverlay(state);

  Future<void> _onBridgeEvent(WindowsQuickSnapEvent event) async {
    final PlatformQuickSnapEventType? type = _eventType(event.action);
    if (type == null) return;
    final PlatformWindow? window = await bridge.resolveWindow(event.handle);
    if (type == PlatformQuickSnapEventType.moveStart && window != null) {
      await bridge.restoreForDrag(window);
    }
    if (!_events.isClosed) _events.add(PlatformQuickSnapEvent(type: type, window: window));
  }

  Future<void> dispose() async {
    await _bridgeEvents.cancel();
    await _events.close();
  }

  static PlatformQuickSnapEventType? _eventType(String value) {
    for (final PlatformQuickSnapEventType type in PlatformQuickSnapEventType.values) {
      if (type.name == value) return type;
    }
    return null;
  }

  /// Bridges the legacy Windows overlay's opaque event handle to the neutral
  /// service. The handle stays inside this adapter; the overlay never performs
  /// Win32 placement itself.
  static Future<bool> applyToHandle(
    int handle,
    QuickGridRect zone,
    int gap,
    int monitorHandle, {
    double topInsetPhysical = 0,
  }) async {
    final QuickSnapService service = QuickSnapService.instance;
    if (service is! WindowsQuickSnapService) return false;
    final PlatformWindow? window = await service.bridge.resolveWindow(handle);
    if (window == null) return false;
    final List<PlatformMonitor> monitors = await MonitorService.instance.enumerate();
    PlatformMonitor? monitor;
    for (final PlatformMonitor candidate in monitors) {
      if (candidate.identity == '$monitorHandle') {
        monitor = candidate;
        break;
      }
    }
    if (monitor == null) return false;
    return service.snap(
      window: window,
      monitor: monitor,
      zone: PlatformSnapZone(left: zone.left, top: zone.top, right: zone.right, bottom: zone.bottom),
      gap: gap.toDouble(),
      topInset: topInsetPhysical,
    );
  }

  /// Converts the legacy taskbar model at the Windows adapter boundary.
  static PlatformWindow fromLegacyWindow(Window window) {
    final Square bounds = Win32.getWindowRect(hwnd: window.hWnd);
    return PlatformWindow(
      nativeId: '${window.hWnd}',
      title: window.title,
      applicationName: window.process.exe,
      bundleIdentifier: window.process.exe,
      processId: window.process.mainPID,
      x: bounds.x.toDouble(),
      y: bounds.y.toDouble(),
      width: bounds.width.toDouble(),
      height: bounds.height.toDouble(),
      executable: window.process.exe,
      executablePath: window.process.path,
      className: window.process.className,
      isPinned: window.isPinned,
      isMinimized: false,
    );
  }
}
