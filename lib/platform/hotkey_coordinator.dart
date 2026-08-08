import 'dart:async';

import 'hotkey_service.dart';
import 'platform_models.dart';

typedef PlatformHotkeyEventHandler = FutureOr<void> Function(PlatformHotkeyEvent event);

/// Connects a platform adapter's event stream to shared hotkey orchestration.
///
/// The coordinator deliberately knows nothing about native event channels. A
/// platform adapter owns registration and event translation; the caller owns
/// the domain action handler.
class HotkeyCoordinator {
  HotkeyCoordinator({HotkeyService? service, required this.onEvent}) : service = service ?? HotkeyService.instance;

  final HotkeyService service;
  final PlatformHotkeyEventHandler onEvent;
  StreamSubscription<PlatformHotkeyEvent>? _subscription;

  bool get isRunning => _subscription != null;

  Future<void> start() async {
    await stop();
    _subscription = service.events.listen(
      (PlatformHotkeyEvent event) {
        unawaited(Future<void>.sync(() => onEvent(event)));
      },
      onError: (_) {},
    );
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
