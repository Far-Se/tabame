import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../logic/error_handler.dart';
import 'plugin_manifest.dart';
import 'plugin_protocol.dart';

/// Owns the lifecycle of a single running plugin process and the newline-
/// delimited JSON conversation with it.
///
/// The launcher creates one host for its whole lifetime and calls [activate]
/// when the user enters a plugin's keyword. The process stays alive across
/// keystrokes (each keystroke is just a `query` event) until the user leaves the
/// plugin, at which point [deactivate] shuts it down gracefully.
///
/// Modelled on the ffmpeg streaming pattern in `screen_recording.dart`:
/// `Process.start(..., runInShell: false)`, decode stdout line-by-line, write
/// events to stdin, and stop by asking nicely before killing.
class LauncherPluginHost {
  LauncherPluginHost({required this.onFrame});

  /// Called on the UI isolate with every accepted render frame (and with an
  /// error frame if the process dies unexpectedly).
  final void Function(PluginRenderFrame frame) onFrame;

  Process? _process;
  PluginManifest? _active;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;

  /// Latest query generation sent to the plugin. Frames tagged with an older
  /// `rev` are dropped, mirroring the launcher's own staleness guard.
  int _rev = 0;
  bool _closing = false;

  /// Serializes stdin writes. Each `writeln` + `flush` must fully complete
  /// before the next starts: `flush()` temporarily marks the sink as "bound to
  /// a stream", and writing during that window throws `StateError`. Chaining
  /// through this future guarantees writes never overlap.
  Future<void> _writeChain = Future<void>.value();

  PluginManifest? get activeManifest => _active;
  bool get isActive => _process != null && _active != null;

  /// Ensures the process for [manifest] is running, restarting only when a
  /// *different* plugin was previously active. Returns immediately if the same
  /// plugin is already live.
  Future<void> activate(PluginManifest manifest, {required String initialQuery}) async {
    if (_active?.id == manifest.id && _process != null) return;
    await deactivate();

    _closing = false;
    _active = manifest;
    try {
      final Process process = await Process.start(
        manifest.runtime,
        <String>[...manifest.args, manifest.entry],
        workingDirectory: manifest.directory,
        runInShell: false,
        // Force UTF-8 stdout/stderr so JSON with non-ASCII survives on Windows,
        // where interpreters otherwise default to the legacy code page.
        environment: <String, String>{'PYTHONIOENCODING': 'utf-8', 'PYTHONUTF8': '1'},
      );
      _process = process;

      _stdoutSub = process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen(_handleStdoutLine);

      _stderrSub = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen((String line) {
        if (line.trim().isEmpty) return;
        unawaited(ErrorLogger.log('Plugin:${manifest.id}', '[stderr] $line', null));
      });

      unawaited(process.exitCode.then(_handleExit));

      _send(<String, Object?>{'type': 'init', 'query': initialQuery});
      sendQuery(initialQuery);
    } catch (error, stack) {
      unawaited(ErrorLogger.log('LauncherPluginHost', 'Failed to start ${manifest.id}: $error', stack));
      _process = null;
      _active = null;
      onFrame(PluginRenderFrame.errorFrame('Failed to launch "${manifest.name}"\n$error'));
    }
  }

  /// Sends the user's current query text (already stripped of the keyword).
  void sendQuery(String text) {
    _rev++;
    _send(<String, Object?>{'type': 'query', 'text': text, 'rev': _rev});
  }

  /// Notifies the plugin that the highlighted item changed (drives the preview
  /// pane and any per-selection work the plugin wants to do).
  void sendSelect(String id) {
    _send(<String, Object?>{'type': 'select', 'id': id, 'rev': _rev});
  }

  /// Triggers an action for an item — `default` on Enter, or a Ctrl+K action id.
  void sendAction(String id, String action) {
    _send(<String, Object?>{'type': 'action', 'id': id, 'action': action});
  }

  void _handleStdoutLine(String line) {
    final PluginRenderFrame? frame = PluginRenderFrame.tryParseLine(line);
    if (frame == null) {
      // Not a render frame — treat as diagnostic output from the plugin.
      if (line.trim().isNotEmpty) {
        unawaited(ErrorLogger.log('Plugin:${_active?.id ?? '?'}', '[stdout] $line', null));
      }
      return;
    }
    // Drop stale responses: a frame answering an old query (rev < latest) is
    // superseded. rev == 0 means "unsolicited" (e.g. a background refresh) and
    // is always accepted.
    if (frame.rev != 0 && frame.rev < _rev) return;
    onFrame(frame);
  }

  void _handleExit(int code) {
    if (_closing) return; // Expected shutdown.
    final PluginManifest? manifest = _active;
    _process = null;
    if (manifest != null) {
      onFrame(PluginRenderFrame.errorFrame('"${manifest.name}" exited unexpectedly (code $code).'));
    }
  }

  void _send(Map<String, Object?> message) {
    final Process? process = _process;
    if (process == null || _closing) return;
    final String encoded = jsonEncode(message);
    // Chain behind any in-flight write so `writeln` never runs while a previous
    // `flush()` is still pending (which throws "StreamSink is bound to a
    // stream"). Flushing each line keeps keystroke/select/action events
    // reaching the child immediately instead of sitting in the sink buffer.
    _writeChain = _writeChain.then((_) async {
      if (_process != process || _closing) return; // Superseded/shut down.
      process.stdin.writeln(encoded);
      await process.stdin.flush();
    }).catchError((Object error, StackTrace stack) {
      // The pipe may close as the plugin exits; log but keep the chain alive.
      unawaited(ErrorLogger.log('LauncherPluginHost', 'stdin write failed: $error', stack));
    });
  }

  /// Gracefully stops the current plugin: send `close`, then kill after a short
  /// grace period if it does not exit on its own.
  Future<void> deactivate() async {
    final Process? process = _process;
    _process = null;
    _active = null;
    _closing = true;

    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;

    if (process == null) return;
    // Let any in-flight write drain before sending `close`, so the two don't
    // overlap on the sink (see _send).
    await _writeChain.catchError((Object _) {});
    try {
      process.stdin.writeln(jsonEncode(<String, Object?>{'type': 'close'}));
      await process.stdin.flush();
    } catch (_) {
      // Ignore — the pipe may already be gone.
    }
    try {
      await process.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          process.kill();
          return -1;
        },
      );
    } catch (_) {
      process.kill();
    }
  }

  /// Fire-and-forget shutdown for [State.dispose].
  void dispose() {
    unawaited(deactivate());
  }
}
