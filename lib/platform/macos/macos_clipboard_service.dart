import 'dart:async';

import '../clipboard_service.dart';
import '../platform_models.dart';
import 'macos_platform_channel.dart';

class MacOSClipboardService extends ClipboardService {
  MacOSClipboardService({MacOSPlatformChannel? channel, Stream<Map<String, dynamic>>? events})
      : channel = channel ?? MacOSPlatformChannel.instance,
        _events = events ?? (channel ?? MacOSPlatformChannel.instance).events,
        _changes = StreamController<PlatformClipboardText>.broadcast();

  final MacOSPlatformChannel channel;
  final Stream<Map<String, dynamic>> _events;
  final StreamController<PlatformClipboardText> _changes;
  StreamSubscription<Map<String, dynamic>>? _nativeSubscription;
  bool _started = false;

  @override
  bool get isAvailable => channel.isAvailable;

  @override
  bool get isMonitoringAvailable => _started && isAvailable;

  @override
  String get unavailableReason => isAvailable
      ? 'Text clipboard monitoring could not be started. The visible launcher remains available.'
      : 'Text clipboard monitoring is unavailable on macOS in this process.';

  @override
  Stream<PlatformClipboardText> get changes => _changes.stream;

  @override
  Future<bool> start() async {
    if (_started) return true;
    if (!isAvailable) return false;
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
