import 'dart:async';

import '../clipboard_service.dart';
import '../platform_models.dart';
import 'linux_platform_channel.dart';

class LinuxClipboardService extends ClipboardService {
  LinuxClipboardService({LinuxPlatformChannel? channel, Stream<Map<String, dynamic>>? events})
      : channel = channel ?? LinuxPlatformChannel.instance,
        _events = events ?? (channel ?? LinuxPlatformChannel.instance).events,
        _changes = StreamController<PlatformClipboardText>.broadcast();

  final LinuxPlatformChannel channel;
  final Stream<Map<String, dynamic>> _events;
  final StreamController<PlatformClipboardText> _changes;
  StreamSubscription<Map<String, dynamic>>? _nativeSubscription;
  bool _started = false;

  @override
  bool get isAvailable => channel.cachedCapabilities.clipboardMonitoring;

  @override
  bool get isMonitoringAvailable => _started && isAvailable;

  @override
  String get unavailableReason {
    if (isAvailable) return '';
    final String probedReason = channel.cachedCapabilities.reasonFor('clipboardMonitoring');
    if (probedReason.isNotEmpty) return probedReason;
    if (channel.cachedCapabilities.isWaylandOnly) {
      return 'Text clipboard monitoring through the X11 selection is unavailable in a Wayland session.';
    }
    return 'The Linux X11 clipboard service is unavailable; text history remains disabled.';
  }

  @override
  Stream<PlatformClipboardText> get changes => _changes.stream;

  @override
  Future<bool> start() async {
    if (_started) return true;
    final bool probePending = channel.cachedCapabilities.displayServer == 'unknown';
    // Let the native adapter make one safe attempt while the asynchronous
    // capability probe is pending. It returns false immediately on Wayland or
    // when the native channel is unavailable.
    if (!isAvailable && !probePending) return false;
    _nativeSubscription = _events.listen(
      (Map<String, dynamic> event) {
        if (event['type'] != 'clipboardChanged') return;
        final dynamic text = event['text'];
        if (text is! String) return;
        final dynamic changeCount = event['changeCount'];
        _changes.add(
          PlatformClipboardText(
            text: text,
            changeCount: changeCount is num ? changeCount.toInt() : null,
          ),
        );
      },
      onError: (_) {},
    );
    final bool started = await channel.startClipboardMonitoring();
    if (!started) {
      await _nativeSubscription?.cancel();
      _nativeSubscription = null;
      return false;
    }
    _started = true;
    return true;
  }

  @override
  Future<void> stop() async {
    if (!_started && _nativeSubscription == null) return;
    _started = false;
    await _nativeSubscription?.cancel();
    _nativeSubscription = null;
    await channel.stopClipboardMonitoring();
  }

  @override
  Future<PlatformClipboardContent?> readContent() async {
    final String? text = await channel.readClipboardText();
    return text == null ? null : PlatformClipboardContent(text: text);
  }

  @override
  Future<bool> writeContent(PlatformClipboardContent content) {
    if (content.hasImage || content.hasRichText) return Future<bool>.value(false);
    return channel.writeClipboardText(content.text);
  }

  Future<void> dispose() async {
    await stop();
    await _changes.close();
  }
}
