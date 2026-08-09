import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../pages/launcher/plugins/plugin_manifest.dart';
import '../pages/launcher/plugins/plugin_protocol.dart';
import '../pages/launcher/plugins/plugin_storage.dart';
import '../services/extension_policy.dart';
import '../services/notification_coordinator.dart';
import 'portable_actions.dart';
import 'portable_settings.dart';

/// Minimal protocol host for the portable shell. It keeps the existing
/// newline-delimited JSON protocol and storage format, while avoiding the
/// Windows-only launcher widget/host graph.
class PortablePluginSession {
  PortablePluginSession({
    required this.manifest,
    required this.settings,
    required this.onFrame,
    required this.onStatus,
    required this.onHide,
  });

  final PluginManifest manifest;
  final PortableSettings settings;
  final void Function(PluginRenderFrame? frame) onFrame;
  final void Function(String message) onStatus;
  final VoidCallback onHide;

  Process? _process;
  StreamSubscription<String>? _stdout;
  StreamSubscription<String>? _stderr;
  Completer<void>? _stdoutDone;
  Completer<void>? _stderrDone;
  Future<void> _writeChain = Future<void>.value();
  int _generation = 0;
  bool _closing = false;
  Duration? _backgroundGrace;

  bool get isRunning => _process != null;

  Future<void> start(String query) async {
    await stop();
    final ExtensionPolicy policy = ExtensionPolicy.current;
    if (!policy.canExecutePlugin(
      id: manifest.id,
      source: manifest.source,
      enabled: manifest.enabled,
      publisher: manifest.publisher,
      artifactHashVerified: false,
      signatureVerified: false,
      consentGranted: false,
    )) {
      onStatus(policy.pluginDisabledMessage);
      onFrame(PluginRenderFrame.errorFrame(policy.pluginDisabledMessage));
      return;
    }
    _closing = false;
    _backgroundGrace = null;
    final int generation = ++_generation;
    try {
      final Process process = await Process.start(
        manifest.runtime,
        <String>[...manifest.args, manifest.entry],
        workingDirectory: manifest.directory,
        runInShell: false,
        environment: _environment(),
      );
      _process = process;

      final Completer<void> stdoutDone = Completer<void>();
      final Completer<void> stderrDone = Completer<void>();
      _stdoutDone = stdoutDone;
      _stderrDone = stderrDone;
      _stdout =
          process.stdout.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()).listen(
        (String line) => _handleLine(process, generation, line),
        onDone: () {
          if (!stdoutDone.isCompleted) stdoutDone.complete();
        },
      );
      _stderr =
          process.stderr.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()).listen(
        (String line) {
          if (generation == _generation && _process == process && line.trim().isNotEmpty) {
            onStatus(line.trim());
          }
        },
        onDone: () {
          if (!stderrDone.isCompleted) stderrDone.complete();
        },
      );
      unawaited(process.exitCode.then((int code) => _handleExit(process, generation, code)));
      _send(<String, Object?>{
        'type': 'init',
        'query': query,
        'protocol': pluginProtocolVersion,
        'theme': <String, Object?>{
          'accent': _hex(settings.accentColor),
          'background': _hex(settings.theme.colorScheme.surface),
          'text': _hex(settings.theme.colorScheme.onSurface),
          'dark': settings.darkMode,
        },
        'locale': Platform.localeName,
      });
      onStatus('Plugin started.');
    } catch (error) {
      onStatus('Could not start plugin: $error');
      onFrame(PluginRenderFrame.errorFrame('Could not start "${manifest.name}".'));
    }
  }

  void sendQuery(String query) {
    _send(<String, Object?>{'type': 'query', 'text': query});
  }

  void sendSelect(String id) {
    _send(<String, Object?>{'type': 'select', 'id': id});
  }

  void sendAction(String itemId, String actionId) {
    _send(<String, Object?>{'type': 'action', 'id': itemId, 'action': actionId});
  }

  Future<void> stop() async {
    final Process? process = _process;
    _process = null;
    _closing = true;
    _generation++;
    final Duration? backgroundGrace = _backgroundGrace;
    _backgroundGrace = null;
    final StreamSubscription<String>? stdout = _stdout;
    final StreamSubscription<String>? stderr = _stderr;
    final Future<void>? stdoutDone = _stdoutDone?.future;
    final Future<void>? stderrDone = _stderrDone?.future;
    _stdout = null;
    _stderr = null;
    _stdoutDone = null;
    _stderrDone = null;

    if (process == null) {
      await stdout?.cancel();
      await stderr?.cancel();
      return;
    }

    await _writeChain.catchError((Object _) {});
    try {
      process.stdin.writeln(jsonEncode(<String, String>{'type': 'close'}));
      await process.stdin.flush();
    } catch (_) {
      // The child may have exited between the status callback and disposal.
    }

    if (backgroundGrace != null) {
      // Keep the pipes alive so a detached `notify` command can arrive after
      // the portable shell has left the plugin view.
      unawaited(_finishDetachedProcess(
        process,
        backgroundGrace,
        stdout,
        stderr,
        stdoutDone,
        stderrDone,
      ));
      return;
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
    await _drainProcessOutput(stdoutDone, stderrDone);
    await stdout?.cancel();
    await stderr?.cancel();
  }

  void _handleLine(Process process, int generation, String line) {
    final String trimmed = line.trim();
    if (trimmed.isEmpty) return;
    final bool live = generation == _generation && _process == process;
    try {
      final Object? decoded = jsonDecode(trimmed);
      if (decoded is! Map<String, dynamic>) {
        if (live) onStatus(trimmed);
        return;
      }
      if (decoded['type'] == 'render') {
        if (live) onFrame(PluginRenderFrame.fromJson(decoded));
      } else if (decoded['type'] == 'command') {
        final PluginCommand? command = PluginCommand.fromJson(decoded);
        if (command != null) _handleCommand(command, live: live);
      }
    } catch (_) {
      if (live) onStatus(trimmed);
    }
  }

  void _handleCommand(PluginCommand command, {required bool live}) {
    switch (command.name) {
      case 'copy':
        if (live) unawaited(Clipboard.setData(ClipboardData(text: command.text ?? '')));
        return;
      case 'open':
        if (live && command.url != null) unawaited(PortableActions.openExternal(command.url!));
        return;
      case 'hide':
        if (live) onHide();
        return;
      case 'toast':
        if (live) onStatus(command.text ?? 'Plugin message');
        return;
      case 'notify':
        final Object? title = command.data['title'];
        unawaited(NotificationCoordinator.instance.show(
          title: title is String && title.trim().isNotEmpty ? title : manifest.name,
          body: command.text ?? '',
        ));
        return;
      case 'background':
        if (!live) return;
        final Object? timeout = command.data['timeout'];
        final int seconds = (timeout is num ? timeout.toInt() : 30).clamp(5, 300);
        _backgroundGrace = Duration(seconds: seconds);
        onStatus('Background finish granted (${seconds}s).');
        return;
      case 'setquery':
        if (live && command.text != null) sendQuery(command.text!);
        return;
      case 'storage':
        _handleStorage(command, live: live);
        return;
      default:
        if (live) onStatus('Unsupported plugin command: ${command.name}');
        return;
    }
  }

  void _handleStorage(PluginCommand command, {required bool live}) {
    final Object? key = command.data['key'];
    final Object? requestId = command.data['requestId'];
    final bool secret = command.data['secret'] == true;
    switch (command.data['op']) {
      case 'set':
        if (key is String && key.isNotEmpty) PluginStorage.set(manifest, key, command.data['value'], secret: secret);
        return;
      case 'delete':
        if (key is String && key.isNotEmpty) PluginStorage.delete(manifest, key, secret: secret);
        return;
      case 'get':
        if (live && key is String && key.isNotEmpty) {
          _send(<String, Object?>{
            'type': 'storage',
            if (requestId != null) 'requestId': requestId,
            'key': key,
            'value': PluginStorage.get(manifest, key, secret: secret),
          });
        }
        return;
      case 'keys':
        _send(<String, Object?>{
          'type': 'storage',
          if (requestId != null) 'requestId': requestId,
          'keys': PluginStorage.keys(manifest),
        });
        return;
      default:
        return;
    }
  }

  Map<String, String> _environment() {
    final Map<String, String> environment = <String, String>{
      ...Platform.environment,
      'PYTHONIOENCODING': 'utf-8',
      'PYTHONUTF8': '1',
      ...manifest.env,
    };
    final Directory libs = Directory(p.join(manifest.directory, '.pluginlibs'));
    if (libs.existsSync()) {
      final String? existing = environment['PYTHONPATH'];
      final String separator = Platform.isWindows ? ';' : ':';
      environment['PYTHONPATH'] = existing == null || existing.isEmpty ? libs.path : '${libs.path}$separator$existing';
    }
    return environment;
  }

  void _handleExit(Process process, int generation, int code) {
    if (generation != _generation || _process != process || _closing) return;
    _process = null;
    onStatus('Plugin exited with code $code.');
  }

  Future<void> _drainProcessOutput(Future<void>? stdoutDone, Future<void>? stderrDone) async {
    final List<Future<void>> pending = <Future<void>>[
      if (stdoutDone != null) stdoutDone,
      if (stderrDone != null) stderrDone,
    ];
    if (pending.isEmpty) return;
    try {
      await Future.wait<void>(pending).timeout(const Duration(seconds: 2));
    } catch (_) {
      // A broken pipe or killed child must not hold shutdown open forever.
    }
  }

  Future<void> _finishDetachedProcess(
    Process process,
    Duration grace,
    StreamSubscription<String>? stdout,
    StreamSubscription<String>? stderr,
    Future<void>? stdoutDone,
    Future<void>? stderrDone,
  ) async {
    try {
      await process.exitCode.timeout(
        grace,
        onTimeout: () {
          process.kill();
          return -1;
        },
      );
    } catch (_) {
      process.kill();
    }
    await _drainProcessOutput(stdoutDone, stderrDone);
    await stdout?.cancel();
    await stderr?.cancel();
  }

  void _send(Map<String, Object?> message) {
    final Process? process = _process;
    if (process == null) return;
    final String encoded = jsonEncode(message);
    _writeChain = _writeChain.then((_) async {
      if (_process != process) return;
      process.stdin.writeln(encoded);
      await process.stdin.flush();
    }).catchError((Object error) {
      onStatus('Plugin input failed: $error');
    });
  }

  String _hex(Color color) => '#${(color.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0')}';
}
