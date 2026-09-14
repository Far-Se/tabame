import 'dart:async';
import 'dart:convert';
import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:ui' show FrameTiming, Size;

import 'package:ffi/ffi.dart';
import 'package:flutter/widgets.dart'
    show AppLifecycleState, NavigatorObserver, Route, WidgetsBinding, WidgetsBindingObserver;
import 'package:window_manager/window_manager.dart';

import '../models/win32/win32.dart';
import '../platform/app_paths.dart';
import '../platform/windows/tabamewin32_api.dart';
import '../platform/windows/win32_api.dart';

/// Independent evidence for a live Dart isolate with an unresponsive window.
/// Timings report raster work, not proof that DWM presented visible pixels.
class UiHealth with WidgetsBindingObserver, TabameListener {
  static final UiHealth _instance = UiHealth();
  static final _UiHealthNavigatorObserver _navigation = _UiHealthNavigatorObserver();
  static NavigatorObserver get navigatorObserver => _navigation;
  static bool quickMenuMounted = false;
  static bool _started = false;
  static Future<void> _writes = Future<void>.value();
  static Future<Size>? _nativeProbe;
  static int _nextStep = 0;
  static final Map<int, String> _pendingSteps = <int, String>{};
  static int _rasterFrames = 0;
  static DateTime? _lastRasterReport;
  static int _hotkeyEvents = 0;
  static DateTime? _lastHotkeyEvent;

  static String get filePath => AppPaths.currentPath('ui_health_$pid.jsonl');

  static void start() {
    if (_started) return;
    if (!Platform.isWindows) {
      //TODO: Implement multiplatform
      return;
    }
    _started = true;
    WidgetsBinding.instance.addObserver(_instance);
    WidgetsBinding.instance.addTimingsCallback(_onTimings);
    NativeHooks.addListener(_instance);
    record('start', <String, Object?>{'dart': Platform.version});
  }

  static void stop() {
    if (!_started) return;
    WidgetsBinding.instance.removeObserver(_instance);
    WidgetsBinding.instance.removeTimingsCallback(_onTimings);
    NativeHooks.removeListener(_instance);
    _started = false;
  }

  static void _onTimings(List<FrameTiming> timings) {
    _rasterFrames += timings.length;
    _lastRasterReport = DateTime.now();
  }

  @override
  void onHotKeyEvent(HotkeyEvent hotkeyInfo) {
    // Count configured hotkey events without recording what the user typed.
    _hotkeyEvents++;
    _lastHotkeyEvent = DateTime.now();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    record('lifecycle', <String, Object?>{'state': state.name});
  }

  static Map<String, Object?> _snapshot() {
    final WidgetsBinding binding = WidgetsBinding.instance;
    final Map<String, Object?> state = <String, Object?>{
      'lifecycle': binding.lifecycleState?.name,
      'framesEnabled': binding.framesEnabled,
      'hasScheduledFrame': binding.hasScheduledFrame,
      'schedulerPhase': binding.schedulerPhase.name,
      'rasterFrames': _rasterFrames,
      'lastRasterReport': _lastRasterReport?.toIso8601String(),
      'hotkeyEvents': _hotkeyEvents,
      'lastHotkeyEvent': _lastHotkeyEvent?.toIso8601String(),
      // This flag records registration intent; Windows can silently remove hooks.
      'hooksMarkedRegistered': NativeHooks.isRegistered,
      'pendingSteps': _pendingSteps.values.toList(),
      'quickMenuMounted': quickMenuMounted,
      'navigatorRouteCount': _navigation.routeCount,
      'rssBytes': ProcessInfo.currentRss,
    };
    if (!Platform.isWindows) return state;
    final int hwnd = Win32.hWnd;
    final Pointer<RECT> rect = calloc<RECT>();
    final Pointer<Uint8> alpha = calloc<Uint8>();
    final Pointer<Uint32> flags = calloc<Uint32>();
    try {
      state['hwnd'] = hwnd;
      state['windowValid'] = IsWindow(hwnd) != 0;
      state['windowVisible'] = IsWindowVisible(hwnd) != 0;
      state['minimized'] = IsIconic(hwnd) != 0;
      state['exStyle'] = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
      if (GetWindowRect(hwnd, rect) != 0) {
        state['rect'] = <int>[rect.ref.left, rect.ref.top, rect.ref.right, rect.ref.bottom];
      }
      if (GetLayeredWindowAttributes(hwnd, nullptr, alpha, flags) != 0) {
        state['layeredAlpha'] = alpha.value;
        state['layeredFlags'] = flags.value;
      }
    } finally {
      calloc.free(rect);
      calloc.free(alpha);
      calloc.free(flags);
    }
    return state;
  }

  /// Serialize writes and keep one previous 2 MiB log. Never await disk I/O
  /// from window transitions, and never erase evidence on startup.
  static void record(String event, [Map<String, Object?> details = const <String, Object?>{}]) {
    if (!_started) return;
    try {
      final String line = '${jsonEncode(<String, Object?>{
            'time': DateTime.now().toIso8601String(),
            'pid': pid,
            'event': event,
            ..._snapshot(),
            ...details,
          })}\n';
      _writes = _writes.then((_) async {
        try {
          final File file = File(filePath);
          if (await file.exists() && await file.length() > 2 * 1024 * 1024) {
            final File previous = File('$filePath.previous');
            if (await previous.exists()) await previous.delete();
            await file.rename(previous.path);
          }
          await file.writeAsString(line, mode: FileMode.append, flush: true);
        } catch (error) {
          print('UiHealth log error: $error');
        }
      });
    } catch (error) {
      print('UiHealth snapshot error: $error');
    }
  }

  /// Observe a slow operation without pretending a timeout cancels its work.
  static Future<T> step<T>(String name, Future<T> Function() operation) async {
    final int id = _nextStep++;
    _pendingSteps[id] = name;
    bool slow = false;
    final Timer timer = Timer(const Duration(seconds: 3), () {
      slow = true;
      record('step.stalled', <String, Object?>{'step': name});
    });
    try {
      final T result = await operation();
      if (slow) record('step.resumed', <String, Object?>{'step': name});
      return result;
    } catch (error, stack) {
      record('step.error', <String, Object?>{'step': name, 'error': '$error', 'stack': '$stack'});
      rethrow;
    } finally {
      timer.cancel();
      _pendingSteps.remove(id);
    }
  }

  /// An end-of-frame future is only a framework fence and can wait forever
  /// when frame production stops. Timing it out does not cancel application work.
  static Future<bool> waitForFrame(String reason) async {
    try {
      await WidgetsBinding.instance.endOfFrame.timeout(const Duration(seconds: 2));
      return true;
    } on TimeoutException {
      record('frame.timeout', <String, Object?>{'reason': reason});
      return false;
    }
  }

  /// A read-only method channel round trip distinguishes a native/platform
  /// stall from a Dart timer that is still running. Allow only one pending call.
  static Future<bool> probeNative() async {
    final Stopwatch elapsed = Stopwatch()..start();
    final Future<Size> probe = _nativeProbe ??= windowManager.getSize();
    try {
      final Size size = await probe.timeout(const Duration(seconds: 2));
      _nativeProbe = null;
      record('native.ok', <String, Object?>{
        'elapsedMs': elapsed.elapsedMilliseconds,
        'size': <double>[size.width, size.height],
      });
      return true;
    } on TimeoutException {
      record('native.timeout');
      return false;
    } catch (error, stack) {
      _nativeProbe = null;
      record('native.error', <String, Object?>{'error': '$error', 'stack': '$stack'});
      return false;
    }
  }
}

/// Capture route removal at the call site; a later native dump cannot recover
/// the Dart stack that removed the application's last page.
class _UiHealthNavigatorObserver extends NavigatorObserver {
  final List<Route<dynamic>> _routes = <Route<dynamic>>[];

  int get routeCount => _routes.length;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    UiHealth.record('navigation.push', <String, Object?>{'routeType': '${route.runtimeType}'});
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _recordRemoval('navigation.pop', route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _recordRemoval('navigation.remove', route);
  }

  void _recordRemoval(String event, Route<dynamic> route) {
    _routes.remove(route);
    UiHealth.record(event, <String, Object?>{
      'routeType': '${route.runtimeType}',
      'removedLastRoute': _routes.isEmpty,
      if (_routes.isEmpty) 'stack': '${StackTrace.current}',
    });
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final int index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0) _routes.removeAt(index);
    if (newRoute != null) _routes.insert(index < 0 ? _routes.length : index, newRoute);
    UiHealth.record('navigation.replace');
  }
}
