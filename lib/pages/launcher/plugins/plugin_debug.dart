import 'package:flutter/foundation.dart';

/// What produced a [PluginDebugEntry], used to color/badge it in the console.
enum PluginDebugKind { info, stderr, stdout, frame, dropped, command, error }

/// One line in the plugin debug console.
class PluginDebugEntry {
  PluginDebugEntry({required this.kind, required this.message}) : time = DateTime.now();

  final DateTime time;
  final PluginDebugKind kind;
  final String message;

  String get timestamp =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
}

/// Ring buffer of protocol/lifecycle events for one plugin host, feeding the
/// dev-mode debug console. Collection is cheap enough to run for every plugin;
/// only the console UI is gated on the manifest's `dev` flag.
class PluginDebugLog {
  static const int maxEntries = 200;

  final List<PluginDebugEntry> _entries = <PluginDebugEntry>[];

  /// Bumped on every [add]/[clear] so the console can rebuild cheaply.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  List<PluginDebugEntry> get entries => _entries;

  void add(PluginDebugKind kind, String message) {
    _entries.add(PluginDebugEntry(kind: kind, message: message));
    if (_entries.length > maxEntries) _entries.removeRange(0, _entries.length - maxEntries);
    revision.value++;
  }

  void clear() {
    _entries.clear();
    revision.value++;
  }

  void dispose() {
    revision.dispose();
  }
}
