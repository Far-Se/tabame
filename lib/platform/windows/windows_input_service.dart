import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:math';

import 'package:ffi/ffi.dart';

import '../../models/win32/keys.dart';
import '../../models/win32/mixed.dart';
import '../input_service.dart';
import '../platform_models.dart';
import '../../services/native_integration_coordinator.dart';
import 'win32_api.dart';

/// Windows implementation of the neutral input contract.
///
/// The native identifiers used to resolve cursor-relative regions stay inside
/// this adapter. Shared hotkey models receive only boolean results and points.
class WindowsInputService extends InputService {
  const WindowsInputService();

  @override
  bool get isAvailable => Platform.isWindows;

  @override
  bool get supportsKeyboardInjection => isAvailable;

  @override
  bool get supportsMouseInjection => isAvailable;

  @override
  bool get supportsGlobalObservation => isAvailable;

  @override
  bool get supportsMouseGestures => isAvailable;

  @override
  String get unavailableReason => isAvailable ? '' : 'Windows input is unavailable on this platform.';

  @override
  Stream<PlatformInputEvent> get events => const Stream<PlatformInputEvent>.empty();

  @override
  Future<Point<int>?> cursorPosition() async {
    if (!isAvailable) return null;
    final Pointer<POINT> point = calloc<POINT>();
    try {
      if (GetCursorPos(point) == 0) return null;
      return Point<int>(point.ref.x, point.ref.y);
    } finally {
      free(point);
    }
  }

  @override
  Future<bool> setCursorPosition(Point<int> position) async {
    if (!isAvailable) return false;
    if (!await NativeIntegrationCoordinator.instance.authorizeInvocation(NativeIntegrationId.inputInjection)) {
      return false;
    }
    return SetCursorPos(position.x, position.y) != 0;
  }

  @override
  Future<bool> injectKeySequence(String sequence) async {
    if (!isAvailable || sequence.isEmpty) return false;
    if (!await NativeIntegrationCoordinator.instance.authorizeInvocation(NativeIntegrationId.inputInjection)) {
      return false;
    }
    WinKeys.safeSendHotkey(() {
      WinKeys.send(sequence);
    });
    return true;
  }

  @override
  Future<bool> injectClick(
      {required Point<int> position, PlatformMouseButton button = PlatformMouseButton.left}) async {
    if (!isAvailable) return false;
    if (!await NativeIntegrationCoordinator.instance.authorizeInvocation(NativeIntegrationId.inputInjection)) {
      return false;
    }
    await setCursorPosition(position);
    final String key = switch (button) {
      PlatformMouseButton.left => '{LMB}',
      PlatformMouseButton.right => '{RMB}',
      PlatformMouseButton.middle => '{MMB}',
      PlatformMouseButton.button4 => '{X1}',
      PlatformMouseButton.button5 => '{X2}',
    };
    WinKeys.safeSendHotkey(() {
      WinKeys.send(key);
    });
    return true;
  }

  @override
  Future<bool> isPointerInRegion({
    required bool windowUnderCursor,
    required PlatformHotkeyRegion region,
  }) async {
    if (!isAvailable) return false;
    final Point<int>? cursor = await cursorPosition();
    if (cursor == null) return false;

    int left = 0;
    int top = 0;
    int right = 0;
    int bottom = 0;
    if (!windowUnderCursor) {
      final int monitor = Monitor.getCursorMonitor();
      if (!Monitor.monitorSizes.containsKey(monitor)) Monitor.fetchMonitors();
      final Square? bounds = Monitor.monitorSizes[monitor];
      if (bounds == null) return false;
      left = bounds.x;
      top = bounds.y;
      right = bounds.x + bounds.width;
      bottom = bounds.y + bounds.height;
    } else {
      final Pointer<POINT> point = calloc<POINT>();
      final Pointer<RECT> rect = calloc<RECT>();
      try {
        point.ref.x = cursor.x;
        point.ref.y = cursor.y;
        final int window = GetAncestor(WindowFromPoint(point.ref), 2);
        if (window == 0 || GetWindowRect(window, rect) == 0) return false;
        left = rect.ref.left;
        top = rect.ref.top;
        right = rect.ref.right;
        bottom = rect.ref.bottom;
      } finally {
        free(point);
        free(rect);
      }
    }

    final int width = right - left;
    final int height = bottom - top;
    final int fromLeft = cursor.x - left;
    final int fromTop = cursor.y - top;
    final int fromRight = cursor.x - right;
    final int fromBottom = cursor.y - bottom;

    int resolvedX = 0;
    int resolvedY = 0;
    switch (region.anchorType) {
      case 1:
        resolvedX = fromLeft;
        resolvedY = fromTop;
      case 2:
        resolvedX = fromRight;
        resolvedY = fromTop;
      case 3:
        resolvedX = fromLeft;
        resolvedY = fromBottom;
      case 4:
        resolvedX = fromRight;
        resolvedY = fromBottom;
      default:
        resolvedX = fromLeft;
        resolvedY = fromTop;
    }

    resolvedX = resolvedX.abs();
    resolvedY = resolvedY.abs();
    if (region.asPercentage) {
      if (width > 0) resolvedX = ((resolvedX / width) * 100).ceil();
      if (height > 0) resolvedY = ((resolvedY / height) * 100).ceil();
    }

    return resolvedX >= region.x1 && resolvedX <= region.x2 && resolvedY >= region.y1 && resolvedY <= region.y2;
  }

  @override
  Future<void> startObservation() async {}

  @override
  Future<void> stopObservation() async {}
}
