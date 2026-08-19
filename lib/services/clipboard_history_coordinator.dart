import 'dart:async';

import '../models/clipboard_history.dart';
import '../platform/clipboard_service.dart';
import '../platform/platform_models.dart';

/// Owns clipboard watcher lifecycle independently from any one QuickMenu page.
///
/// The old Windows implementation attached a native listener to the QuickMenu
/// widget. Keeping the subscription here lets Windows, Linux/X11, and macOS
/// share the same history orchestration while their adapters own native events.
class ClipboardHistoryCoordinator {
  ClipboardHistoryCoordinator._();

  static final ClipboardHistoryCoordinator instance = ClipboardHistoryCoordinator._();

  StreamSubscription<PlatformClipboardText>? _subscription;
  Future<bool>? _startFuture;

  bool get isRunning => _subscription != null;

  Future<bool> start() {
    return _startFuture ??= _start().whenComplete(() => _startFuture = null);
  }

  Future<bool> _start() async {
    if (_subscription != null) return ClipboardService.instance.isMonitoringAvailable;

    final bool started = await ClipboardService.instance.start();
    if (!started) return false;

    _subscription = ClipboardService.instance.changes.listen(
      (PlatformClipboardText change) => unawaited(ClipboardHistoryStore.recordClipboardChange(change)),
      onError: (_) {},
    );
    return true;
  }

  Future<void> stop() async {
    await _startFuture;
    await _subscription?.cancel();
    _subscription = null;
    await ClipboardService.instance.stop();
  }
}
