import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../logic/error_handler.dart';
import '../../../models/settings.dart';
import 'plugin_debug.dart';
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
  LauncherPluginHost({required this.onFrame, required this.onCommand});

  /// Called on the UI isolate with every accepted render frame (and with an
  /// error frame if the process dies unexpectedly).
  final void Function(PluginRenderFrame frame) onFrame;

  /// Called with every `{"type":"command"}` message the plugin emits (copy,
  /// paste, open, hide, toast). The launcher executes the side effect.
  final void Function(PluginCommand command) onCommand;

  /// Protocol/lifecycle events shown in the dev-mode debug console. Always
  /// collected (it's a small ring buffer); only displayed for `"dev": true`
  /// plugins.
  final PluginDebugLog debugLog = PluginDebugLog();

  Process? _process;
  PluginManifest? _active;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;

  /// Dev mode: watches the plugin folder and hot-restarts the process on save.
  StreamSubscription<FileSystemEvent>? _devWatchSub;
  Timer? _devReloadDebounce;

  /// Last query text sent to the plugin, replayed after a dev-mode restart so
  /// the plugin resumes where the author was testing.
  String _lastQuery = '';

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
    if (_active?.id == manifest.id && _process != null) {
      // Already live (e.g. re-entering after a dev reload raced an exit) —
      // just bring the plugin up to date with the current query.
      sendQuery(initialQuery);
      return;
    }
    await deactivate();

    _closing = false;
    _active = manifest;
    _lastQuery = initialQuery;
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
        debugLog.add(PluginDebugKind.stderr, line);
        unawaited(ErrorLogger.log('Plugin:${manifest.id}', '[stderr] $line', null));
      });

      unawaited(process.exitCode.then(_handleExit));

      debugLog.add(PluginDebugKind.info,
          'Started ${manifest.runtime} ${manifest.args.isEmpty ? '' : '${manifest.args.join(' ')} '}${manifest.entry} (pid ${process.pid})');
      if (manifest.dev) _startDevWatcher(manifest);

      // Handshake: protocol version, theme (so plugins can generate matching
      // colors/images), and locale. `dark` is inferred from the backdrop
      // luminance, which tracks whatever theme mode is actually in effect.
      _send(<String, Object?>{
        'type': 'init',
        'query': initialQuery,
        'protocol': pluginProtocolVersion,
        'theme': <String, Object?>{
          'accent': pluginColorToHex(Design.accent),
          'text': pluginColorToHex(Design.text),
          'background': pluginColorToHex(Design.background),
          'dark': Design.background.computeLuminance() < 0.5,
        },
        'locale': Platform.localeName,
      });
      sendQuery(initialQuery);
    } catch (error, stack) {
      unawaited(ErrorLogger.log('LauncherPluginHost', 'Failed to start ${manifest.id}: $error', stack));
      debugLog.add(PluginDebugKind.error, 'Failed to start: $error');
      _process = null;
      _active = null;
      onFrame(PluginRenderFrame.errorFrame('Failed to launch "${manifest.name}"\n$error'));
    }
  }

  // ── Dev mode: hot reload ────────────────────────────────────────────────────

  /// Restarts the plugin process whenever a file inside its folder changes, so
  /// authors can edit → save → retest without leaving the launcher. Noise from
  /// interpreter caches is ignored.
  void _startDevWatcher(PluginManifest manifest) {
    try {
      _devWatchSub = Directory(manifest.directory).watch(recursive: true).listen((FileSystemEvent event) {
        final String path = event.path.replaceAll('\\', '/');
        if (path.contains('/__pycache__/') || path.contains('/node_modules/') || path.contains('/.git/')) return;
        if (path.endsWith('.log') || path.endsWith('.tmp')) return;
        _devReloadDebounce?.cancel();
        // Editors fire several events per save (write + metadata); coalesce
        // them into one restart.
        _devReloadDebounce = Timer(const Duration(milliseconds: 300), () {
          _devReloadDebounce = null;
          final String name = path.split('/').last;
          debugLog.add(PluginDebugKind.info, 'Change in $name — restarting');
          unawaited(_devReload());
        });
      });
    } catch (error, stack) {
      debugLog.add(PluginDebugKind.error, 'Dev watcher failed: $error');
      unawaited(ErrorLogger.log('LauncherPluginHost', 'Dev watcher for ${manifest.id} failed: $error', stack));
    }
  }

  /// Stops and relaunches the active plugin, replaying the last query. If the
  /// user exits the plugin during the (up to ~2s) shutdown await, the restarted
  /// process is merely a warm idle child — it receives no further events and is
  /// reused on re-entry or killed with the host.
  Future<void> _devReload() async {
    final PluginManifest? manifest = _active;
    if (manifest == null) return;
    final String query = _lastQuery;
    await deactivate();
    await activate(manifest, initialQuery: query);
  }

  /// Sends the user's current query text (already stripped of the keyword).
  void sendQuery(String text) {
    _rev++;
    _lastQuery = text;
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

  /// Delivers a form view's field values after the user submits.
  void sendFormSubmit(Map<String, Object?> values) {
    debugLog.add(PluginDebugKind.info, 'submit ${jsonEncode(values)}');
    _send(<String, Object?>{'type': 'submit', 'values': values});
  }

  /// Escape on a frame that declared `canGoBack` — the plugin should render
  /// its previous screen.
  void sendBack() {
    debugLog.add(PluginDebugKind.info, 'back');
    _send(<String, Object?>{'type': 'back', 'rev': _rev});
  }

  /// Tab pressed — [id] is the highlighted item (empty when there is none).
  /// Plugins typically respond with a `setQuery` command to autocomplete.
  void sendTab(String id) {
    _send(<String, Object?>{'type': 'tab', 'id': id, 'rev': _rev});
  }

  void _handleStdoutLine(String line) {
    final String trimmed = line.trim();
    if (trimmed.isEmpty) return;

    Map<String, dynamic>? message;
    if (trimmed.startsWith('{')) {
      try {
        final Object? decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic>) message = decoded;
      } catch (_) {
        debugLog.add(PluginDebugKind.error, 'Malformed JSON on stdout: ${_truncate(trimmed)}');
      }
    }
    if (message == null) {
      // Not a protocol message — treat as diagnostic output from the plugin.
      debugLog.add(PluginDebugKind.stdout, trimmed);
      unawaited(ErrorLogger.log('Plugin:${_active?.id ?? '?'}', '[stdout] $line', null));
      return;
    }

    final Object? type = message['type'];
    if (type == 'render') {
      final PluginRenderFrame frame = PluginRenderFrame.fromJson(message);
      // Drop stale responses: a frame answering an old query (rev < latest) is
      // superseded. rev == 0 means "unsolicited" (e.g. a background refresh) and
      // is always accepted.
      if (frame.rev != 0 && frame.rev < _rev) {
        debugLog.add(PluginDebugKind.dropped, 'Dropped stale frame (rev ${frame.rev} < $_rev)');
        return;
      }
      debugLog.add(PluginDebugKind.frame,
          'render rev=${frame.rev} view=${frame.view.name} items=${frame.items.length}${frame.loading ? ' loading' : ''}');
      onFrame(frame);
      return;
    }

    if (type == 'command') {
      final PluginCommand? command = PluginCommand.fromJson(message);
      if (command == null) {
        debugLog.add(PluginDebugKind.error, 'command message missing a "command" string: ${_truncate(trimmed)}');
        return;
      }
      if (!PluginCommand.knownCommands.contains(command.name)) {
        debugLog.add(PluginDebugKind.error, 'Unknown command "${command.name}"');
        return;
      }
      debugLog.add(PluginDebugKind.command, 'command ${command.name}${command.text != null ? ' text=${_truncate(command.text!)}' : ''}${command.url != null ? ' url=${_truncate(command.url!)}' : ''}');
      onCommand(command);
      return;
    }

    debugLog.add(PluginDebugKind.error, 'Unknown message type "$type"');
  }

  static String _truncate(String value) => value.length <= 120 ? value : '${value.substring(0, 120)}…';

  void _handleExit(int code) {
    if (_closing) return; // Expected shutdown.
    final PluginManifest? manifest = _active;
    _process = null;
    if (manifest != null) {
      debugLog.add(PluginDebugKind.error, 'Process exited unexpectedly (code $code)');
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

    _devReloadDebounce?.cancel();
    _devReloadDebounce = null;
    await _devWatchSub?.cancel();
    _devWatchSub = null;

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
