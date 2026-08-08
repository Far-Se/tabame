import 'dart:math';

import '../input_service.dart';
import '../platform_models.dart';

/// macOS intentionally defers low-level event taps and CGEvent injection for
/// this migration. Global Carbon shortcut registration remains available via
/// [MacOSHotkeyService], while actions that require Accessibility/Input
/// Monitoring are capability-gated instead of pretending to work.
class MacOSInputService extends UnavailableInputService {
  const MacOSInputService();

  @override
  String get unavailableReason =>
      'Low-level keyboard/mouse observation and injection are deferred on macOS; use the visible Tabame window instead.';

  @override
  Future<bool> isPointerInRegion({
    required bool windowUnderCursor,
    required PlatformHotkeyRegion region,
  }) async =>
      false;

  @override
  Future<Point<int>?> cursorPosition() async => null;
}
