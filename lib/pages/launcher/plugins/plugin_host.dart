import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../../logic/error_handler.dart';
import '../../../models/settings.dart';
import '../../../models/win32/win_utils.dart';
import 'plugin_debug.dart';
import 'plugin_manifest.dart';
import 'plugin_protocol.dart';
import 'plugin_storage.dart';

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

  /// Activation generation. Bumped on every activate/deactivate so stdout
  /// lines from a superseded (background-finishing) process can be told apart
  /// from the live plugin's: detached processes keep their storage/notify
  /// abilities but can no longer render frames or drive the UI.
  int _generation = 0;

  /// Extra shutdown grace requested via the `background` command: instead of
  /// being killed ~2s after `close`, the process gets this long to finish its
  /// work (uploads, syncs) — still able to write storage and fire native
  /// notifications, but detached from the UI.
  Duration? _backgroundGrace;

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
    _backgroundGrace = null;
    final int generation = ++_generation;

    // Install the plugin's dependencies before the first launch (pip for Python,
    // npm/bun for Node). This can block on the network, so it runs before the
    // process starts and shows a spinner meanwhile. If the user leaves the plugin
    // while it runs, bail out.
    final bool depsReady = await _ensureDependencies(manifest);
    if (!depsReady) return;
    if (_active?.id != manifest.id || _closing) return;

    try {
      final Process process = await Process.start(
        manifest.runtime,
        <String>[...manifest.args, manifest.entry],
        workingDirectory: manifest.directory,
        runInShell: false,
        environment: _buildEnvironment(manifest),
      );
      _process = process;

      _stdoutSub = process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen((String line) => _handleStdoutLine(generation, manifest, line));

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

  // ── Dependencies & environment ──────────────────────────────────────────────

  /// Folder Tabame installs a plugin's vendored Python packages into. Kept
  /// inside the plugin folder so the plugin stays self-contained and portable.
  static String _libsDir(PluginManifest manifest) =>
      '${manifest.directory}${Platform.pathSeparator}.pluginlibs';

  /// Builds the child process environment: UTF-8 defaults, a `PYTHONPATH` that
  /// includes the vendored `.pluginlibs` folder (when present), then the
  /// author's own `env` map on top.
  Map<String, String> _buildEnvironment(PluginManifest manifest) {
    final Map<String, String> env = <String, String>{
      // Force UTF-8 stdout/stdin so JSON with non-ASCII survives on Windows,
      // where interpreters otherwise default to the legacy code page.
      'PYTHONIOENCODING': 'utf-8',
      'PYTHONUTF8': '1',
    };
    final Directory libs = Directory(_libsDir(manifest));
    if (libs.existsSync()) {
      final String sep = Platform.isWindows ? ';' : ':';
      final String? existing = Platform.environment['PYTHONPATH'];
      env['PYTHONPATH'] =
          existing == null || existing.isEmpty ? libs.path : '${libs.path}$sep$existing';
    }
    // Author-declared vars win, so a plugin can override anything above.
    env.addAll(manifest.env);
    return env;
  }

  /// Ensures the plugin's dependencies are installed before launch, dispatching
  /// by runtime: pip for Python, npm/bun for Node. Returns false only when an
  /// install was attempted and failed (an error frame is already shown).
  Future<bool> _ensureDependencies(PluginManifest manifest) async {
    final String runtime = manifest.runtime.toLowerCase();
    if (runtime.contains('py')) return _ensurePythonDeps(manifest);
    if (runtime.contains('node') || runtime.contains('bun')) return _ensureNodeDeps(manifest);
    return true;
  }

  /// Runs `npm install` (or `bun install`) in a Node/Bun plugin's folder when it
  /// ships a `package.json` but its `node_modules` is missing or out of date, so
  /// the user never has to open a terminal. Skipped when there's no
  /// `package.json`, or the install signature (the `package.json` contents) is
  /// unchanged since the last install.
  Future<bool> _ensureNodeDeps(PluginManifest manifest) async {
    final String sep = Platform.pathSeparator;
    final File packageJson = File('${manifest.directory}${sep}package.json');
    if (!packageJson.existsSync()) return true; // Nothing declared.

    // Reinstall when node_modules is absent or when package.json changed.
    final String signature = packageJson.readAsStringSync();
    final Directory modules = Directory('${manifest.directory}${sep}node_modules');
    final File marker = File('${modules.path}$sep.tabame-install');
    if (modules.existsSync() && marker.existsSync() && marker.readAsStringSync() == signature) {
      return true;
    }

    final bool isBun = manifest.runtime.toLowerCase().contains('bun');
    final String tool = isBun ? 'bun' : 'npm';

    onFrame(PluginRenderFrame.statusFrame(
        'Installing dependencies for "${manifest.name}"… (first run can take a minute)'));
    debugLog.add(PluginDebugKind.info, '$tool install → node_modules');
    try {
      final ProcessResult result = await Process.run(
        tool,
        <String>['install'],
        workingDirectory: manifest.directory,
        // npm/bun are `.cmd`/`.ps1` shims on Windows, not `.exe`, so they must be
        // launched through a shell.
        runInShell: true,
      );
      if (result.exitCode != 0) {
        final String detail = '${result.stdout}\n${result.stderr}'.trim();
        debugLog.add(PluginDebugKind.error, '$tool install failed (exit ${result.exitCode})');
        unawaited(ErrorLogger.log('LauncherPluginHost', '$tool install for ${manifest.id} failed: $detail', null));
        _active = null;
        onFrame(PluginRenderFrame.errorFrame(
            'Could not install dependencies for "${manifest.name}".\nIs `$tool` on your PATH?\n\n$detail'));
        return false;
      }
      if (modules.existsSync()) marker.writeAsStringSync(signature);
      debugLog.add(PluginDebugKind.info, 'Dependencies installed into node_modules');
      return true;
    } catch (error, stack) {
      debugLog.add(PluginDebugKind.error, '$tool install error: $error');
      unawaited(ErrorLogger.log('LauncherPluginHost', '$tool install for ${manifest.id} error: $error', stack));
      _active = null;
      onFrame(PluginRenderFrame.errorFrame(
          'Could not install dependencies for "${manifest.name}".\nIs `$tool` on your PATH?\n$error'));
      return false;
    }
  }

  /// Installs a Python plugin's declared dependencies (`"pip"` array and/or a
  /// sibling `requirements.txt`) into `.pluginlibs`, but only when the declared
  /// set has changed since the last install. Returns false only when an install
  /// was attempted and failed (an error frame is shown); true otherwise —
  /// including the common "nothing to install" and "non-Python runtime" cases.
  Future<bool> _ensurePythonDeps(PluginManifest manifest) async {
    if (!manifest.runtime.toLowerCase().contains('py')) return true;

    final File reqFile = File('${manifest.directory}${Platform.pathSeparator}requirements.txt');
    final bool hasReqFile = reqFile.existsSync();
    final List<String> requirementArgs = <String>[
      if (hasReqFile) ...<String>['-r', 'requirements.txt'],
      ...manifest.pip,
    ];
    if (requirementArgs.isEmpty) return true; // Nothing declared.

    // Reinstall only when the declared dependency set actually changed.
    final String signature = <String>[
      manifest.pip.join(''),
      if (hasReqFile) reqFile.readAsStringSync(),
    ].join('');
    final Directory libs = Directory(_libsDir(manifest));
    final File marker = File('${libs.path}${Platform.pathSeparator}.tabame-install');
    if (libs.existsSync() && marker.existsSync() && marker.readAsStringSync() == signature) {
      return true;
    }

    onFrame(PluginRenderFrame.statusFrame('Installing dependencies for "${manifest.name}"…'));
    debugLog.add(PluginDebugKind.info, 'pip install ${requirementArgs.join(' ')} → .pluginlibs');
    try {
      await libs.create(recursive: true);
      final ProcessResult result = await Process.run(
        manifest.runtime,
        <String>['-m', 'pip', 'install', '--upgrade', '--target', libs.path, ...requirementArgs],
        workingDirectory: manifest.directory,
        runInShell: false,
        environment: <String, String>{'PYTHONIOENCODING': 'utf-8', 'PYTHONUTF8': '1'},
      );
      if (result.exitCode != 0) {
        final String detail = '${result.stdout}\n${result.stderr}'.trim();
        debugLog.add(PluginDebugKind.error, 'pip install failed (exit ${result.exitCode})');
        unawaited(ErrorLogger.log('LauncherPluginHost', 'pip install for ${manifest.id} failed: $detail', null));
        _active = null;
        onFrame(PluginRenderFrame.errorFrame('Could not install dependencies for "${manifest.name}".\n\n$detail'));
        return false;
      }
      marker.writeAsStringSync(signature);
      debugLog.add(PluginDebugKind.info, 'Dependencies installed into .pluginlibs');
      return true;
    } catch (error, stack) {
      debugLog.add(PluginDebugKind.error, 'pip install error: $error');
      unawaited(ErrorLogger.log('LauncherPluginHost', 'pip install for ${manifest.id} error: $error', stack));
      _active = null;
      onFrame(PluginRenderFrame.errorFrame('Could not install dependencies for "${manifest.name}".\n$error'));
      return false;
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
        if (path.contains('/__pycache__/') ||
            path.contains('/node_modules/') ||
            path.contains('/.pluginlibs/') ||
            path.contains('/.git/')) {
          return;
        }
        if (path.endsWith('.log') || path.endsWith('.tmp')) return;
        // Storage writes come from the plugin itself — never a reason to restart.
        if (path.endsWith('/${PluginStorage.storeFileName}')) return;
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

  /// Delivers a form view's field values after the user submits. [button] is
  /// the id of the pressed `form.buttons` entry, when the form declared any.
  void sendFormSubmit(Map<String, Object?> values, {String? button}) {
    debugLog.add(PluginDebugKind.info, 'submit ${jsonEncode(values)}');
    _send(<String, Object?>{
      'type': 'submit',
      'values': values,
      if (button != null) 'button': button,
    });
  }

  /// A watched form field changed — lets plugins re-render dependent fields.
  void sendFormChange(String fieldId, Map<String, Object?> values) {
    _send(<String, Object?>{'type': 'change', 'id': fieldId, 'values': values});
  }

  /// The user scrolled near the end of a `hasMore` list — the plugin should
  /// answer with a longer item list (same rev semantics as a query response).
  void sendLoadMore() {
    debugLog.add(PluginDebugKind.info, 'loadMore');
    _send(<String, Object?>{'type': 'loadMore', 'rev': _rev});
  }

  /// `inputMode: "submit"` — Enter submits the whole query text at once
  /// instead of streaming keystrokes.
  void sendSubmitQuery(String text) {
    _rev++;
    _lastQuery = text;
    debugLog.add(PluginDebugKind.info, 'submitQuery "${_truncate(text)}"');
    _send(<String, Object?>{'type': 'submitQuery', 'text': text, 'rev': _rev});
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

  void _handleStdoutLine(int generation, PluginManifest manifest, String line) {
    final String trimmed = line.trim();
    if (trimmed.isEmpty) return;

    // A line from a superseded process (the user left the plugin while it
    // finishes in the background): it may still persist state and notify, but
    // can no longer render frames or drive the launcher UI.
    final bool live = generation == _generation && _process != null;

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
      unawaited(ErrorLogger.log('Plugin:${manifest.id}', '[stdout] $line', null));
      return;
    }

    final Object? type = message['type'];
    if (type == 'render') {
      if (!live) {
        debugLog.add(PluginDebugKind.dropped, 'Dropped frame from background-finishing process');
        return;
      }
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
      // Host services (storage, clipboard, notifications, background grace)
      // are executed here; UI side effects are forwarded to the launcher.
      if (_handleHostCommand(command, manifest, live: live)) return;
      if (!live) {
        debugLog.add(PluginDebugKind.dropped, 'Dropped UI command "${command.name}" from background process');
        return;
      }
      onCommand(command);
      return;
    }

    debugLog.add(PluginDebugKind.error, 'Unknown message type "$type"');
  }

  /// Executes commands that are host services rather than launcher UI effects.
  /// Returns true when the command was consumed.
  bool _handleHostCommand(PluginCommand command, PluginManifest manifest, {required bool live}) {
    switch (command.name) {
      case 'storage':
        _handleStorageCommand(command, manifest, live: live);
        return true;
      case 'clipboardread':
        if (!live) return true;
        final Object? requestId = command.data['requestId'];
        unawaited(Clipboard.getData('text/plain').then((ClipboardData? data) {
          _send(<String, Object?>{
            'type': 'clipboard',
            if (requestId != null) 'requestId': requestId,
            'text': data?.text ?? '',
          });
        }));
        return true;
      case 'notify':
        // Works even from a background-finishing process — that's its point.
        final Object? title = command.data['title'];
        WinUtils.showWindowsNotification(
          title: title is String && title.trim().isNotEmpty ? title : manifest.name,
          body: command.text ?? '',
          onClick: () {},
        );
        return true;
      case 'background':
        if (!live) return true;
        final Object? timeout = command.data['timeout'];
        final int seconds = (timeout is num ? timeout.toInt() : 30).clamp(5, 300);
        _backgroundGrace = Duration(seconds: seconds);
        debugLog.add(PluginDebugKind.info, 'Background finish granted (${seconds}s after close)');
        return true;
    }
    return false;
  }

  /// `storage` command: `op` = get / set / delete / keys, with optional
  /// `secret: true` routing values to the Windows Credential Manager. `get`
  /// and `keys` reply with a `{"type":"storage"}` message echoing `requestId`.
  void _handleStorageCommand(PluginCommand command, PluginManifest manifest, {required bool live}) {
    final Object? op = command.data['op'];
    final Object? key = command.data['key'];
    final Object? requestId = command.data['requestId'];
    final bool secret = command.data['secret'] == true;
    switch (op) {
      case 'set':
        if (key is String && key.isNotEmpty) PluginStorage.set(manifest, key, command.data['value'], secret: secret);
        return;
      case 'delete':
        if (key is String && key.isNotEmpty) PluginStorage.delete(manifest, key, secret: secret);
        return;
      case 'get':
        if (!live || key is! String || key.isEmpty) return;
        _send(<String, Object?>{
          'type': 'storage',
          if (requestId != null) 'requestId': requestId,
          'key': key,
          'value': PluginStorage.get(manifest, key, secret: secret),
        });
        return;
      case 'keys':
        if (!live) return;
        _send(<String, Object?>{
          'type': 'storage',
          if (requestId != null) 'requestId': requestId,
          'keys': PluginStorage.keys(manifest),
        });
        return;
      default:
        debugLog.add(PluginDebugKind.error, 'storage command with unknown op "$op"');
    }
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
  /// grace period if it does not exit on its own. A plugin that requested
  /// `background` finishing instead keeps running (detached from the UI) for
  /// its granted grace period — still able to write storage and notify.
  Future<void> deactivate() async {
    final Process? process = _process;
    _process = null;
    _active = null;
    _closing = true;
    _generation++;

    _devReloadDebounce?.cancel();
    _devReloadDebounce = null;
    await _devWatchSub?.cancel();
    _devWatchSub = null;

    final StreamSubscription<String>? stdoutSub = _stdoutSub;
    final StreamSubscription<String>? stderrSub = _stderrSub;
    _stdoutSub = null;
    _stderrSub = null;

    final Duration? backgroundGrace = _backgroundGrace;
    _backgroundGrace = null;

    if (process == null) {
      await stdoutSub?.cancel();
      await stderrSub?.cancel();
      return;
    }
    // Let any in-flight write drain before sending `close`, so the two don't
    // overlap on the sink (see _send).
    await _writeChain.catchError((Object _) {});
    try {
      process.stdin.writeln(jsonEncode(<String, Object?>{'type': 'close'}));
      await process.stdin.flush();
    } catch (_) {
      // Ignore — the pipe may already be gone.
    }

    if (backgroundGrace != null) {
      // Detached finish: keep the stdout listener alive (storage writes and
      // notify commands still work; frames and UI commands are dropped by the
      // generation guard) and only kill once the grace runs out. Don't await —
      // a switch to another plugin must not block on this.
      debugLog.add(PluginDebugKind.info, 'Finishing in background (up to ${backgroundGrace.inSeconds}s)');
      unawaited(process.exitCode
          .timeout(backgroundGrace, onTimeout: () {
            process.kill();
            return -1;
          })
          .catchError((Object _) => -1)
          .whenComplete(() async {
            await stdoutSub?.cancel();
            await stderrSub?.cancel();
          }));
      return;
    }

    await stdoutSub?.cancel();
    await stderrSub?.cancel();
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
