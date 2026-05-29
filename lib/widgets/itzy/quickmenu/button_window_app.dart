import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';

import '../../../models/classes/boxes/boxes_base.dart';
import '../../../models/settings.dart';
import '../../../models/win32/win_utils.dart';
import '../../widgets/extracted_icon.dart';

// ── Messages ─────────────────────────────────────────────────────────────────

class _IconRequest {
  final int id;
  final String path;
  const _IconRequest({required this.id, required this.path});
}

class _IconResponse {
  final int id;
  final ExtractedIcon data;
  const _IconResponse({required this.id, required this.data});
}

// ── Worker entry point ────────────────────────────────────────────────────────

void _iconWorkerEntry(SendPort mainSendPort) {
  final ReceivePort workerPort = ReceivePort();
  mainSendPort.send(workerPort.sendPort);

  workerPort.listen((dynamic message) {
    if (message is _IconRequest) {
      try {
        final ExtractedIcon data = WinUtils.extractIcon(message.path);
        mainSendPort.send(_IconResponse(id: message.id, data: data));
      } catch (e, st) {
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
  final Map<int, Completer<ExtractedIcon>> _pending = <int, Completer<ExtractedIcon>>{};
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
          final Completer<ExtractedIcon>? completer = _pending.remove(message.id);
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

  Future<ExtractedIcon> extractIcon(String path) async {
    await _ensureInitialized();

    final int id = _nextId++;
    final Completer<ExtractedIcon> completer = Completer<ExtractedIcon>();
    _pending[id] = completer;

    final SendPort port = _workerSendPorts[_rrIndex++ % _poolSize];
    port.send(_IconRequest(id: id, path: path));

    final Timer timeout = Timer(_requestTimeout, () {
      final Completer<ExtractedIcon>? pendingCompleter = _pending.remove(id);
      if (pendingCompleter != null && !pendingCompleter.isCompleted) {
        Debug.add('Icon extraction timed out for $path');
        pendingCompleter.complete(null);
      }
    });

    return completer.future.whenComplete(timeout.cancel);
  }
}

// ── Extension-type icon cache (with TTL) ─────────────────────────────────────

class _ExtIconEntry {
  final ExtractedIcon icon;
  final DateTime expiresAt;

  _ExtIconEntry(this.icon) : expiresAt = DateTime.now().add(_ExtIconCache._ttl);

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class _ExtIconCache {
  _ExtIconCache._();
  static final _ExtIconCache instance = _ExtIconCache._();

  static const Duration _ttl = Duration(minutes: 15);

  // Extensions whose icon depends on the specific file, not just its type.
  // These are always looked up per-path and never stored in this cache.
  static const Set<String> _perFileExtensions = <String>{
    '.exe',
    '.lnk',
    '.url',
    '.ico',
  };

  final Map<String, _ExtIconEntry> _cache = <String, _ExtIconEntry>{};

  /// Returns the extension key for [path], or null if this path must be
  /// resolved per-file (custom icon types, directories, empty paths).
  static String? extensionKey(String path) {
    final String trimmed = path.trim();
    if (trimmed.isEmpty) return null;

    // Treat bare directory paths (no extension) as per-file.
    final String ext = trimmed.contains('.') ? '.${trimmed.split('.').last.toLowerCase()}' : '';
    if (ext.isEmpty || _perFileExtensions.contains(ext)) return null;

    // Also treat paths that look like directories (end with separator).
    if (trimmed.endsWith('/') || trimmed.endsWith(r'\')) return null;

    try {
      if (Directory(trimmed).existsSync()) return null;
    } catch (_) {}

    return ext;
  }

  ExtractedIcon? get(String ext) {
    final _ExtIconEntry? entry = _cache[ext];
    if (entry == null) return null;
    if (entry.isExpired) {
      _cache.remove(ext);
      return null;
    }
    return entry.icon;
  }

  /// Returns true if a live (non-expired) entry exists for [ext].
  bool has(String ext) {
    final _ExtIconEntry? entry = _cache[ext];
    if (entry == null) return false;
    if (entry.isExpired) {
      _cache.remove(ext);
      return false;
    }
    return true;
  }

  void set(String ext, ExtractedIcon icon) {
    _cache[ext] = _ExtIconEntry(icon);
  }

  void remove(String ext) => _cache.remove(ext);

  int get length => _cache.length;

  /// Evict all expired entries. Call periodically if needed.
  void evictExpired() {
    _cache.removeWhere((_, _ExtIconEntry e) => e.isExpired);
  }
}

// ── Widget ────────────────────────────────────────────────────────────────────

class WindowsAppButton extends StatefulWidget {
  // Per-path cache for files whose icon is file-specific (.exe, .lnk, etc.).
  static final Map<String, Future<ExtractedIcon>> iconFutureCache = <String, Future<ExtractedIcon>>{};
  static Future<ExtractedIcon>? _defaultFolderIconFuture;

  // Tracks which paths in iconFutureCache have already resolved.
  // We can't ask a Future if it's complete directly in Dart, so we maintain
  // this set ourselves inside the .then() callback.
  static final Set<String> _resolvedPaths = <String>{};

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

  static Future<ExtractedIcon> getIcon(String path) {
    if (path.trim().isEmpty) {
      return Future<ExtractedIcon>.value(null);
    }

    // .url files are never cached — they can change their target at any time.
    if (path.endsWith('.url')) {
      return _IconWorkerPool.instance.extractIcon(path);
    }

    if (WinUtils.usesDefaultFolderIcon(path)) {
      return _defaultFolderIconFuture ??= _IconWorkerPool.instance.extractIcon(path).then((ExtractedIcon result) {
        if (result is Uint8List) {
          final String hash = crypto.md5.convert(result).toString();
          if (hash == 'a326e0850b34c1935b2e3499fc986380' || hash == '5b290ed4dac06a15d465c7f0f9d5003b') {
            _defaultFolderIconFuture = null;
            return null;
          }
        }
        return result;
      }).catchError((Object error, StackTrace stackTrace) {
        Debug.add('Folder icon extraction failed for $path: $error');
        Debug.add('$stackTrace');
        _defaultFolderIconFuture = null;
        return null as ExtractedIcon;
      });
    }

    // ── Extension-type cache (e.g. .mp3, .txt, .pdf …) ──────────────────────
    final String? extKey = _ExtIconCache.extensionKey(path);
    if (extKey != null) {
      if (_ExtIconCache.instance.has(extKey)) {
        return Future<ExtractedIcon>.value(_ExtIconCache.instance.get(extKey));
      }
      // Not cached yet — extract once, then store by extension.
      return _IconWorkerPool.instance.extractIcon(path).then((ExtractedIcon result) {
        if (result == null) return null;
        if (result is Uint8List) {
          final String hash = crypto.md5.convert(result).toString();
          if (hash == 'a326e0850b34c1935b2e3499fc986380' || hash == '5b290ed4dac06a15d465c7f0f9d5003b') {
            return null;
          }
        }
        _ExtIconCache.instance.set(extKey, result);
        return result;
      }).catchError((Object error, StackTrace stackTrace) {
        Debug.add('Icon extraction failed for $path ($extKey): $error');
        Debug.add('$stackTrace');
        return null as ExtractedIcon;
      });
    }

    // ── Per-path cache (.exe, .lnk, directories …) ───────────────────────────
    //
    // Only evict when over the limit, and only evict entries that have already
    // resolved. Evicting an in-flight future would leave any widget still
    // awaiting it hanging forever — the .then() would never fire because the
    // future object was removed from the cache but the worker still owns it.
    if (iconFutureCache.length > 100) {
      _evictOneResolvedEntry();
    }

    return iconFutureCache.putIfAbsent(
      path,
      () {
        final Future<ExtractedIcon> future = _IconWorkerPool.instance.extractIcon(path).then((ExtractedIcon result) {
          // Mark resolved regardless of outcome so eviction can find this entry.
          _resolvedPaths.add(path);
          if (result == null) {
            // Keep a resolved-null sentinel so we don't re-request on every
            // rebuild — the widget will just show the placeholder.
            return null;
          }
          if (result is Uint8List) {
            final String hash = crypto.md5.convert(result).toString();
            if (hash == 'a326e0850b34c1935b2e3499fc986380' || hash == '5b290ed4dac06a15d465c7f0f9d5003b') {
              return null;
            }
          }
          return result;
        }).catchError((Object error, StackTrace stackTrace) {
          Debug.add('Icon extraction failed for $path: $error');
          Debug.add('$stackTrace');
          // Mark resolved on error too so the eviction set stays consistent.
          _resolvedPaths.add(path);
          return null as ExtractedIcon;
        });
        return future;
      },
    );
  }

  /// Evict the oldest resolved entry from [iconFutureCache].
  ///
  /// We track resolved paths in [_resolvedPaths] (populated inside each
  /// future's .then/.catchError) so we never have to inspect a Future's
  /// completion state directly — Dart provides no synchronous API for that.
  /// Evicting only resolved entries means we never yank a future out from
  /// under a widget that is still awaiting it.
  static void _evictOneResolvedEntry() {
    // iconFutureCache is a LinkedHashMap — keys are in insertion order, so
    // the first resolved key we find is the oldest one.
    for (final String key in iconFutureCache.keys.toList()) {
      if (_resolvedPaths.contains(key)) {
        iconFutureCache.remove(key);
        _resolvedPaths.remove(key);
        return;
      }
    }
    // All entries are still in-flight — nothing safe to evict this cycle.
  }

  static int getCacheSize() {
    return iconFutureCache.length + _ExtIconCache.instance.length;
  }

  static Future<String> getCacheInKb() async {
    int totalSize = 0;

    // Per-path cache
    for (final Future<ExtractedIcon> future in iconFutureCache.values) {
      final ExtractedIcon data = await future;
      if (data is Uint8List) {
        totalSize += data.length;
      } else if (data is String && File(data).existsSync()) {
        totalSize += File(data).lengthSync();
      }
    }

    // Extension-type cache (values are already resolved)
    _ExtIconCache.instance.evictExpired();
    for (final _ExtIconEntry entry in _ExtIconCache.instance._cache.values) {
      final ExtractedIcon data = entry.icon;
      if (data is Uint8List) {
        totalSize += data.length;
      } else if (data is String && File(data).existsSync()) {
        totalSize += File(data).lengthSync();
      }
    }

    return "${(totalSize / 1024).toStringAsFixed(2)} KB";
  }

  @override
  State<WindowsAppButton> createState() => _WindowsAppButtonState();
}

class _WindowsAppButtonState extends State<WindowsAppButton> {
  // The resolved icon, or null while loading / on error.
  ExtractedIcon? _icon;

  // Tracks which path the current load belongs to so stale callbacks are
  // discarded when the widget is updated before the future resolves.
  String? _loadingFor;

  @override
  void initState() {
    super.initState();
    _startLoad(widget.path);
  }

  @override
  void didUpdateWidget(covariant WindowsAppButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      // Clear the stale icon immediately so the placeholder shows while the
      // new one loads, then kick off a fresh load.
      setState(() => _icon = null);
      _startLoad(widget.path);
    }
  }

  void _startLoad(String path) {
    String displayPath = path;
    final String rewrite = Boxes.getIconRewrite(displayPath);
    if (rewrite.isNotEmpty) displayPath = rewrite;

    // Record which path this load is for so we can detect stale results.
    _loadingFor = displayPath;

    // Capture the expected path in a local variable so the closure below
    // always compares against the path it was started for, not whatever
    // _loadingFor happens to be when the future resolves.
    final String expectedPath = displayPath;

    WindowsAppButton.getIcon(displayPath).then((ExtractedIcon? result) {
      // Discard the result if the widget is gone or has already moved on to a
      // different path.
      if (!mounted || _loadingFor != expectedPath) return;
      setState(() => _icon = result);
    }).catchError((Object error, StackTrace stackTrace) {
      Debug.add('_startLoad error for $displayPath: $error');
      Debug.add('$stackTrace');
      if (!mounted || _loadingFor != expectedPath) return;
      setState(() => _icon = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final Widget fallback = widget.placeholder ?? const SizedBox(width: 32, height: 32);

    if (_icon == null) return GestureDetector(onTap: widget.onTap, child: fallback);

    return GestureDetector(
      onTap: widget.onTap,
      child: buildExtractedIcon(
        _icon,
        width: 32,
        height: 32,
        gaplessPlayback: true,
        fallback: fallback,
      ),
    );
  }
}
