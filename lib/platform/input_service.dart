import 'dart:math';

import 'platform_models.dart';

/// Platform-neutral input observation and injection boundary.
///
/// Native key codes, mouse flags, and window handles belong in an adapter. The
/// shared hotkey dispatcher only deals with logical key sequences, points, and
/// input events described by this contract.
abstract class InputService {
  static InputService _instance = const UnavailableInputService();

  static InputService get instance => _instance;

  static void register(InputService service) {
    _instance = service;
  }

  const InputService();

  bool get isAvailable;
  bool get supportsKeyboardInjection;
  bool get supportsMouseInjection;
  bool get supportsGlobalObservation;
  bool get supportsMouseGestures;
  String get unavailableReason;
  Stream<PlatformInputEvent> get events;

  Future<Point<int>?> cursorPosition();

  Future<bool> setCursorPosition(Point<int> position);

  Future<bool> injectKeySequence(String sequence);

  Future<bool> injectClick({required Point<int> position, PlatformMouseButton button = PlatformMouseButton.left});

  Future<bool> isPointerInRegion({
    required bool windowUnderCursor,
    required PlatformHotkeyRegion region,
  });

  Future<void> startObservation();

  Future<void> stopObservation();
}

class UnavailableInputService extends InputService {
  const UnavailableInputService({this.reason = 'Low-level keyboard and mouse input are unavailable on this platform.'});

  final String reason;

  @override
  bool get isAvailable => false;

  @override
  bool get supportsKeyboardInjection => false;

  @override
  bool get supportsMouseInjection => false;

  @override
  bool get supportsGlobalObservation => false;

  @override
  bool get supportsMouseGestures => false;

  @override
  String get unavailableReason => reason;

  @override
  Stream<PlatformInputEvent> get events => const Stream<PlatformInputEvent>.empty();

  @override
  Future<Point<int>?> cursorPosition() async => null;

  @override
  Future<bool> setCursorPosition(Point<int> position) async => false;

  @override
  Future<bool> injectKeySequence(String sequence) async => false;

  @override
  Future<bool> injectClick(
          {required Point<int> position, PlatformMouseButton button = PlatformMouseButton.left}) async =>
      false;

  @override
  Future<bool> isPointerInRegion({
    required bool windowUnderCursor,
    required PlatformHotkeyRegion region,
  }) async =>
      false;

  @override
  Future<void> startObservation() async {}

  @override
  Future<void> stopObservation() async {}
}
