import 'dart:async';

import '../models/clipboard_history.dart';
import '../platform/clipboard_service.dart';
import '../platform/platform_models.dart';
import 'native_integration_coordinator.dart';

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

    final NativeIntegrationCoordinator integrations = NativeIntegrationCoordinator.instance;
    if (!ClipboardHistoryStore.enabled || !integrations.canStart(NativeIntegrationId.clipboardHistory)) {
      integrations.reportDisabled(
        NativeIntegrationId.clipboardHistory,
        reason: integrations.denialReason(NativeIntegrationId.clipboardHistory) ??
            'Clipboard history is paused until you enable it.',
        reducedMode: true,
      );
      return false;
    }

    final bool started = await ClipboardService.instance.start();
    if (!started) {
      integrations.reportUnavailable(
        NativeIntegrationId.clipboardHistory,
        reason: ClipboardService.instance.unavailableReason,
      );
      return false;
    }

    _subscription = ClipboardService.instance.changes.listen(
      (PlatformClipboardText change) => unawaited(ClipboardHistoryStore.recordClipboardChange(change)),
      onError: (_) {},
    );
    integrations.reportRunning(NativeIntegrationId.clipboardHistory);
    return true;
  }

  Future<void> stop() async {
    await _startFuture;
    await _subscription?.cancel();
    _subscription = null;
    await ClipboardService.instance.stop();
    NativeIntegrationCoordinator.instance.reportDisabled(
      NativeIntegrationId.clipboardHistory,
      reason: 'Clipboard history monitoring is paused.',
      reducedMode: true,
    );
  }
}
