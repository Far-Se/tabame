import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/material.dart';

import '../../../models/win32/win32.dart';

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
        debugPrint('Worker error for ${message.path}: $e');
        debugPrint('$st');
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
          _pending.remove(message.id)?.complete(message.data);
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

    return completer.future;
  }
}

// ── Widget ────────────────────────────────────────────────────────────────────

class WindowsAppButton extends StatefulWidget {
  static final Map<String, Future<Uint8List?>> _iconFutureCache = <String, Future<Uint8List?>>{};

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
    return _iconFutureCache.putIfAbsent(
      path,
      () => _IconWorkerPool.instance.extractIcon(path),
    );
  }

  @override
  State<WindowsAppButton> createState() => _WindowsAppButtonState();
}

class _WindowsAppButtonState extends State<WindowsAppButton> {
  late Future<Uint8List?> _iconFuture;

  @override
  void initState() {
    super.initState();
    _iconFuture = WindowsAppButton.getIcon(widget.path);
  }

  @override
  void didUpdateWidget(covariant WindowsAppButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _iconFuture = WindowsAppButton.getIcon(widget.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: FutureBuilder<Uint8List?>(
        future: _iconFuture,
        builder: (BuildContext context, AsyncSnapshot<Uint8List?> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return widget.placeholder ?? const SizedBox(width: 32, height: 32);
          }

          if (snapshot.hasError) {
            debugPrint('FutureBuilder error: ${snapshot.error}');
            return widget.placeholder ?? const SizedBox(width: 32, height: 32);
          }

          if (snapshot.data == null) {
            debugPrint('Icon bytes are null for path: ${widget.path}');
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
