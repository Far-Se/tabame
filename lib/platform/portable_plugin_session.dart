import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../pages/launcher/plugins/plugin_manifest.dart';
import '../pages/launcher/plugins/plugin_protocol.dart';
import '../pages/launcher/plugins/plugin_storage.dart';
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
  Future<void> _writeChain = Future<void>.value();

  bool get isRunning => _process != null;

  Future<void> start(String query) async {
    await stop();
    try {
      final Process process = await Process.start(
        manifest.runtime,
        <String>[...manifest.args, manifest.entry],
        workingDirectory: manifest.directory,
        runInShell: false,
        environment: _environment(),
      );
      _process = process;

      _stdout = process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen(_handleLine);
      _stderr = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen((String line) {
        if (line.trim().isNotEmpty) onStatus(line.trim());
      });
      unawaited(process.exitCode.then((int code) {
        if (_process == process) {
          _process = null;
          onStatus('Plugin exited with code $code.');
        }
      }));
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
    await _stdout?.cancel();
    await _stderr?.cancel();
    _stdout = null;
    _stderr = null;
    if (process == null) return;
    try {
      process.stdin.writeln(jsonEncode(<String, String>{'type': 'close'}));
      await process.stdin.flush().timeout(const Duration(milliseconds: 250), onTimeout: () {});
    } catch (_) {
      // The child may have exited between the status callback and disposal.
    }
    try {
      process.kill();
    } catch (_) {
      // Disposal must remain safe even when the process is already gone.
    }
  }

  void _handleLine(String line) {
    final String trimmed = line.trim();
    if (trimmed.isEmpty) return;
    try {
      final Object? decoded = jsonDecode(trimmed);
      if (decoded is! Map<String, dynamic>) {
        onStatus(trimmed);
        return;
      }
      if (decoded['type'] == 'render') {
        onFrame(PluginRenderFrame.fromJson(decoded));
      } else if (decoded['type'] == 'command') {
        final PluginCommand? command = PluginCommand.fromJson(decoded);
        if (command != null) _handleCommand(command);
      }
    } catch (_) {
      onStatus(trimmed);
    }
  }

  void _handleCommand(PluginCommand command) {
    switch (command.name) {
      case 'copy':
        unawaited(Clipboard.setData(ClipboardData(text: command.text ?? '')));
        return;
      case 'open':
        if (command.url != null) unawaited(PortableActions.openExternal(command.url!));
        return;
      case 'hide':
        onHide();
        return;
      case 'toast':
        onStatus(command.text ?? 'Plugin message');
        return;
      case 'notify':
        final Object? title = command.data['title'];
        unawaited(NotificationCoordinator.instance.show(
          title: title is String && title.trim().isNotEmpty ? title : manifest.name,
          body: command.text ?? '',
        ));
        return;
      case 'setquery':
        if (command.text != null) sendQuery(command.text!);
        return;
      case 'storage':
        _handleStorage(command);
        return;
      default:
        onStatus('Unsupported plugin command: ${command.name}');
        return;
    }
  }

  void _handleStorage(PluginCommand command) {
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
        if (key is String && key.isNotEmpty) {
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
