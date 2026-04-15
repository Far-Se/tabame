import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/globals.dart';
import '../../../models/win32/win32.dart';

class _QueuedIconRequest {
  _QueuedIconRequest({
    required this.path,
    required this.completer,
  });

  final String path;
  final Completer<Uint8List?> completer;
}

class WindowsAppButton extends StatefulWidget {
  static final Map<String, Future<Uint8List?>> _iconFutureCache = <String, Future<Uint8List?>>{};
  static final Queue<_QueuedIconRequest> _iconLoadQueue = Queue<_QueuedIconRequest>();
  static const int _maxConcurrentIconLoads = 10;
  static int _activeIconLoads = 0;

  final String path;
  final String? arguments;
  final VoidCallback? onTap;
  final Widget? placeholder;
  const WindowsAppButton({super.key, required this.path, this.arguments, this.onTap, this.placeholder});

  @override
  State<WindowsAppButton> createState() => _WindowsAppButtonState();

  static Future<Uint8List?> enqueueIconLoad(String path) {
    final Completer<Uint8List?> completer = Completer<Uint8List?>();
    _iconLoadQueue.add(
      _QueuedIconRequest(
        path: path,
        completer: completer,
      ),
    );
    _pumpIconQueue();
    return completer.future;
  }

  static void _pumpIconQueue() {
    while (_activeIconLoads < _maxConcurrentIconLoads && _iconLoadQueue.isNotEmpty) {
      final _QueuedIconRequest request = _iconLoadQueue.removeFirst();
      _activeIconLoads += 1;

      Future<Uint8List?>(
        () => WinUtils.extractIcon(request.path),
      ).then(request.completer.complete).catchError(request.completer.completeError).whenComplete(() {
        _activeIconLoads -= 1;
        _pumpIconQueue();
      });
    }
  }
}

class _WindowsAppButtonState extends State<WindowsAppButton> {
  Future<Uint8List?>? _iconFuture;

  @override
  void initState() {
    super.initState();
    _scheduleIconLoad();
  }

  @override
  void didUpdateWidget(covariant WindowsAppButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _iconFuture = null;
      _scheduleIconLoad();
    }
  }

  void _scheduleIconLoad() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _iconFuture != null || !File(widget.path).existsSync()) return;

      setState(() {
        _iconFuture = WindowsAppButton._iconFutureCache.putIfAbsent(
          widget.path,
          _loadIconBytes,
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final double size = Theme.of(context).iconTheme.size ?? 15;
    if (!File(widget.path).existsSync()) return const SizedBox();
    // PaintingBinding.instance.imageCache.maximumSizeBytes = 1024 * 1024 * 7;

    return SizedBox(
      width: size + 6,
      height: size + 6,
      child: FutureBuilder<Uint8List?>(
        future: _iconFuture,
        builder: (BuildContext context, AsyncSnapshot<Object?> snapshot) {
          return InkWell(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.0),
              child: snapshot.data is Uint8List
                  ? Tooltip(
                      message: widget.path.substring(widget.path.lastIndexOf('\\') + 1),
                      child: Image.memory(
                        snapshot.data! as Uint8List,
                        fit: BoxFit.scaleDown,
                        width: size,
                        gaplessPlayback: true,
                        errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) => const Icon(
                          Icons.check_box_outline_blank,
                          size: 16,
                        ),
                      ),
                    )
                  : widget.placeholder ?? Icon(Icons.circle_outlined, size: size),
            ),
            onTap: widget.onTap ??
                () {
                  WinUtils.open(widget.path, arguments: widget.arguments);
                  if (kReleaseMode) QuickMenuFunctions.toggleQuickMenu(visible: false);
                },
          );
        },
      ),
    );
  }

  Future<Uint8List?> _loadIconBytes() async {
    if (Globals.getIconRewrite(widget.path) != "") {
      final String x = Globals.getIconRewrite(widget.path);
      final ByteData bytes = await rootBundle.load(x);
      return bytes.buffer.asUint8List();
    }
    return WindowsAppButton.enqueueIconLoad(widget.path);
  }
}
