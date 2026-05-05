import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../models/classes/boxes/boxes_base.dart';
import '../../../models/settings.dart';
import '../../../models/win32/win_utils.dart';

// ── Messages ─────────────────────────────────────────────────────────────────

class _IconRequest {
  final int id;
  final String path;
  const _IconRequest({required this.id, required this.path});
}

class _IconResponse {
  final int id;
  final Uint8List? data;
  const _IconResponse({required this.id, required this.data});
}

// ── Worker entry point ────────────────────────────────────────────────────────

void _iconWorkerEntry(SendPort mainSendPort) {
  final ReceivePort workerPort = ReceivePort();
  mainSendPort.send(workerPort.sendPort);

  workerPort.listen((dynamic message) {
    if (message is _IconRequest) {
      try {
        final Uint8List? data = WinUtils.extractIcon(message.path);
        mainSendPort.send(_IconResponse(id: message.id, data: data));
      } catch (e, st) {
        // Log the real error so you can see why null is returned.
        Debug.add('Worker error for ${message.path}: $e');
        Debug.add('$st');
        mainSendPort.send(_IconResponse(id: message.id, data: null));
      }
    }
  });
}

// ── Worker pool ───────────────────────────────────────────────────────────────

class _WorkerHandle {
  final ReceivePort responsePort;
  final Completer<SendPort> ready = Completer<SendPort>();

  _WorkerHandle(this.responsePort);
}

class _IconWorkerPool {
  _IconWorkerPool._();
  static final _IconWorkerPool instance = _IconWorkerPool._();

  static const int _poolSize = 3;
  static const Duration _requestTimeout = Duration(seconds: 8);

  final List<SendPort> _workerSendPorts = <SendPort>[];
  final Map<int, Completer<Uint8List?>> _pending = <int, Completer<Uint8List?>>{};
  int _nextId = 0;
  int _rrIndex = 0;

  Future<void>? _initFuture;

  Future<void> _ensureInitialized() {
    _initFuture ??= _spawnAll();
    return _initFuture!;
  }

  Future<void> _spawnAll() async {
    for (int i = 0; i < _poolSize; i++) {
      final ReceivePort responsePort = ReceivePort();
      final _WorkerHandle handle = _WorkerHandle(responsePort);

      responsePort.listen((dynamic message) {
        if (message is SendPort) {
          if (!handle.ready.isCompleted) {
            handle.ready.complete(message);
          }
          return;
        }

        if (message is _IconResponse) {
          final Completer<Uint8List?>? completer = _pending.remove(message.id);
          if (completer != null && !completer.isCompleted) {
            completer.complete(message.data);
          }
        }
      });

      await Isolate.spawn(_iconWorkerEntry, responsePort.sendPort);

      final SendPort workerSendPort = await handle.ready.future;
      _workerSendPorts.add(workerSendPort);
    }
  }

  Future<Uint8List?> extractIcon(String path) async {
    await _ensureInitialized();

    final int id = _nextId++;
    final Completer<Uint8List?> completer = Completer<Uint8List?>();
    _pending[id] = completer;

    final SendPort port = _workerSendPorts[_rrIndex++ % _poolSize];
    port.send(_IconRequest(id: id, path: path));

    final Timer timeout = Timer(_requestTimeout, () {
      final Completer<Uint8List?>? pendingCompleter = _pending.remove(id);
      if (pendingCompleter != null && !pendingCompleter.isCompleted) {
        Debug.add('Icon extraction timed out for $path');
        pendingCompleter.complete(null);
      }
    });

    return completer.future.whenComplete(timeout.cancel);
  }
}

// ── Widget ────────────────────────────────────────────────────────────────────

class WindowsAppButton extends StatefulWidget {
  static final Map<String, Future<Uint8List?>> iconFutureCache = <String, Future<Uint8List?>>{};

  final String path;
  final String? arguments;
  final VoidCallback? onTap;
  final Widget? placeholder;

  const WindowsAppButton({
    super.key,
    required this.path,
    this.arguments,
    this.onTap,
    this.placeholder,
  });

  static Future<Uint8List?> getIcon(String path) {
    if (path.endsWith('.url')) {
      return Future<Uint8List?>(() => WinUtils.extractIcon(path));
    }
    if (path.trim().isEmpty) {
      return Future<Uint8List?>.value(null);
    }
    if (iconFutureCache.length > 100) {
      iconFutureCache.remove(iconFutureCache.keys.first);
    }
    return iconFutureCache.putIfAbsent(
      path,
      () {
        return _IconWorkerPool.instance.extractIcon(path).catchError((Object error, StackTrace stackTrace) {
          Debug.add('Icon extraction failed for $path: $error');
          Debug.add('$stackTrace');
          iconFutureCache.remove(path);
          return null;
        });
      },
    );
  }

  static int getCacheSize() {
    return iconFutureCache.length;
  }

  static Future<String> getCacheInKb() async {
    int totalSize = 0;
    for (final Future<Uint8List?> future in iconFutureCache.values) {
      final Uint8List? data = await future;
      if (data != null) {
        totalSize += data.length;
      }
    }
    return "${(totalSize / 1024).toStringAsFixed(2)} KB";
  }

  @override
  State<WindowsAppButton> createState() => _WindowsAppButtonState();
}

class _WindowsAppButtonState extends State<WindowsAppButton> {
  late Future<Uint8List?> _iconFuture;
  late String _displayPath;

  @override
  void initState() {
    super.initState();
    _initIcon();
  }

  void _initIcon() {
    _displayPath = widget.path;
    final String rewrite = Boxes.getIconRewrite(_displayPath);
    if (rewrite != "") {
      _displayPath = rewrite;
    }
    _iconFuture = WindowsAppButton.getIcon(_displayPath);
  }

  @override
  void didUpdateWidget(covariant WindowsAppButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _initIcon();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: FutureBuilder<Uint8List?>(
        future:
            widget.path.endsWith('.url') ? Future<Uint8List?>(() => WinUtils.extractIcon(widget.path)) : _iconFuture,
        // future: widget.path.endsWith('.url') ? WindowsAppButton.getIcon(widget.path) : _iconFuture,
        builder: (BuildContext context, AsyncSnapshot<Uint8List?> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return widget.placeholder ?? const SizedBox(width: 32, height: 32);
          }

          if (snapshot.hasError) {
            Debug.add('FutureBuilder error: ${snapshot.error}');
            return widget.placeholder ?? const SizedBox(width: 32, height: 32);
          }

          if (snapshot.data == null) {
            Debug.add('Icon bytes are null for path: $_displayPath');
            return widget.placeholder ?? const SizedBox(width: 32, height: 32);
          }

          return Image.memory(
            snapshot.data!,
            width: 32,
            height: 32,
            gaplessPlayback: true,
          );
        },
      ),
    );
  }
}
