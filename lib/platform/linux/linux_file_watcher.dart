import 'dart:async';
import 'dart:io';

/// Linux filesystem watching backed by Dart's inotify implementation.
///
/// The watcher is intentionally scoped to a directory and returns null for a
/// missing or inaccessible path. A failed watch must not make launcher startup
/// fail.
class LinuxFileWatcher {
  LinuxFileWatcher({bool? available}) : _availableOverride = available;

  final bool? _availableOverride;

  bool get isAvailable => _availableOverride ?? Platform.isLinux;

  String get unavailableReason => isAvailable ? '' : 'Linux filesystem watching is unavailable on this platform.';

  StreamSubscription<FileSystemEvent>? watch(
    String root,
    void Function(FileSystemEvent event) onEvent, {
    bool recursive = true,
    int events = FileSystemEvent.all,
  }) {
    if (!isAvailable) return null;
    try {
      final Directory directory = Directory(root);
      if (!directory.existsSync()) return null;
      return directory.watch(recursive: recursive, events: events).listen(onEvent, onError: (_) {});
    } on FileSystemException {
      return null;
    }
  }
}
