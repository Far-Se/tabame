import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tabamewin32/tabamewin32.dart';

import '../logic/error_handler.dart';
import '../models/settings.dart';
import '../models/win32/mixed.dart';
import '../models/win32/win_utils.dart';

/// Background "instant replay" DVR. When enabled it records every monitor as
/// short rolling mp4 segments (hardware H.264 via WGC), pruning anything older
/// than the retention window. Exporting stitches the tail segments covering the
/// last N minutes into a single mp4 per monitor in the FancyShot folder.
///
/// One recorder session runs per monitor; session ids start at [_sessionBase] so
/// they never collide with the standalone recorder page (session id 0).
class RewindlyService {
  RewindlyService._();
  static final RewindlyService instance = RewindlyService._();

  static const Duration _segmentLength = Duration(seconds: 15);
  static const int _sessionBase = 1000;
  static final RegExp _segPattern = RegExp(r'seg_(\d+)\.mp4$');

  Timer? _rotationTimer;
  bool _running = false;
  bool _busy = false; // serializes rotate/export so sessions don't overlap
  List<int> _monitors = <int>[]; // monitor handles currently being recorded

  final ValueNotifier<bool> runningNotifier = ValueNotifier<bool>(false);

  bool get isRunning => _running;
  int get monitorCount => _monitors.length;

  /// Called once from `registerAll()` in the main process.
  void init() {
    if (user.rewindlyEnabled) start();
  }

  Future<void> start() async {
    if (_running) return;
    _running = true;
    runningNotifier.value = true;
    _monitors = List<int>.from(Monitor.list);
    for (int i = 0; i < _monitors.length; i++) {
      await _startSegment(i);
    }
    _rotationTimer?.cancel();
    _rotationTimer = Timer.periodic(_segmentLength, (_) => _rotate());
  }

  /// Stops all recorders but keeps the buffer on disk.
  Future<void> stop() async {
    _rotationTimer?.cancel();
    _rotationTimer = null;
    if (!_running) return;
    _running = false;
    runningNotifier.value = false;
    for (int i = 0; i < _monitors.length; i++) {
      try {
        await stopScreenRecording(sessionId: _sessionBase + i);
      } catch (_) {}
    }
  }

  /// Apply changed settings (e.g. fps) to a running buffer.
  Future<void> restart() async {
    if (!_running) return;
    await stop();
    await start();
  }

  Directory _monitorDir(int index) {
    final Directory dir = Directory('${WinUtils.getRewindlyFolder()}\\$index');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<void> _startSegment(int index) async {
    if (index >= _monitors.length) return;
    final int epoch = DateTime.now().millisecondsSinceEpoch;
    final String path = '${_monitorDir(index).path}\\seg_$epoch.mp4';
    final ScreenRecordingConfig config = ScreenRecordingConfig(
      targetType: ScreenRecordingTargetType.monitor,
      monitorHandle: _monitors[index],
      outputPath: path,
      frameRate: user.rewindlyFps.clamp(1, 10),
      videoBitrateMbps: 6,
      captureCursor: true,
      useHardwareEncoder: true,
      audioMode: ScreenRecordingAudioMode.none,
      sessionId: _sessionBase + index,
    );
    try {
      await startScreenRecording(config);
    } catch (e, s) {
      ErrorLogger.log('RewindlyService._startSegment', e.toString(), s);
    }
  }

  Future<void> _rotate() async {
    if (!_running || _busy) return;
    _busy = true;
    try {
      for (int i = 0; i < _monitors.length; i++) {
        try {
          await stopScreenRecording(sessionId: _sessionBase + i);
        } catch (_) {}
        await _startSegment(i);
      }
      _sweepRetention();
    } finally {
      _busy = false;
    }
  }

  void _sweepRetention() {
    final int cutoff =
        DateTime.now().millisecondsSinceEpoch - user.rewindlyRetentionMinutes * 60 * 1000;
    for (int i = 0; i < _monitors.length; i++) {
      for (final FileSystemEntity entity in _monitorDir(i).listSync()) {
        if (entity is! File) continue;
        final int? epoch = _epochOf(entity.path);
        if (epoch != null && epoch < cutoff) {
          try {
            entity.deleteSync();
          } catch (_) {}
        }
      }
    }
  }

  int? _epochOf(String path) {
    final RegExpMatch? match = _segPattern.firstMatch(path);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  List<File> _sortedSegments(int index) {
    final List<File> segments = _monitorDir(index)
        .listSync()
        .whereType<File>()
        .where((File f) => _epochOf(f.path) != null)
        .toList()
      ..sort((File a, File b) => _epochOf(a.path)!.compareTo(_epochOf(b.path)!));
    return segments;
  }

  /// Approximate total size of the rolling buffer on disk, in bytes.
  int bufferSizeBytes() {
    int total = 0;
    for (int i = 0; i < _monitors.length; i++) {
      for (final File f in _sortedSegments(i)) {
        try {
          total += f.lengthSync();
        } catch (_) {}
      }
    }
    return total;
  }

  /// Exports the last [Settings.rewindlyClipMinutes] minutes as one mp4 per
  /// monitor into the FancyShot folder. Returns the exported file paths.
  Future<List<String>> exportLastClip() async {
    if (!_running || _busy) return <String>[];
    _busy = true;
    final List<String> exported = <String>[];
    try {
      final int windowMs = user.rewindlyClipMinutes.clamp(1, 10) * 60 * 1000;
      final int now = DateTime.now().millisecondsSinceEpoch;
      final String stamp = _timestamp();

      // Finalize the in-progress segments so the newest footage is included.
      for (int i = 0; i < _monitors.length; i++) {
        try {
          await stopScreenRecording(sessionId: _sessionBase + i);
        } catch (_) {}
      }

      final String fancyshot = WinUtils.getFancyshotFolder();
      final Directory fancyshotDir = Directory(fancyshot);
      if (!fancyshotDir.existsSync()) fancyshotDir.createSync(recursive: true);

      final int cutoff = now - windowMs;
      for (int i = 0; i < _monitors.length; i++) {
        final List<File> segments = _sortedSegments(i);
        final List<String> inputs = <String>[];
        for (int j = 0; j < segments.length; j++) {
          // A segment covers [start, nextStart); include it if that span reaches
          // into the requested window.
          final int nextStart =
              j + 1 < segments.length ? _epochOf(segments[j + 1].path)! : now;
          if (nextStart > cutoff) inputs.add(segments[j].path);
        }
        if (inputs.isEmpty) continue;
        final String out = '$fancyshot\\rewindly_${stamp}_mon${i + 1}.mp4';
        try {
          final bool ok = await concatScreenRecordings(inputs: inputs, outputPath: out);
          if (ok) exported.add(out);
        } catch (e, s) {
          ErrorLogger.log('RewindlyService.exportLastClip', e.toString(), s);
        }
      }

      // Resume the rolling buffer.
      for (int i = 0; i < _monitors.length; i++) {
        await _startSegment(i);
      }
    } finally {
      _busy = false;
    }
    return exported;
  }

  String _timestamp() {
    final DateTime n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)}_${two(n.hour)}${two(n.minute)}${two(n.second)}';
  }
}
