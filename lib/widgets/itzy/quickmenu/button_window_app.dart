import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../models/classes/boxes/boxes_base.dart';
import '../../../models/settings.dart';
import '../../../models/win32/win_utils.dart';
import '../../widgets/extracted_icon.dart';

class _IconRequest {
  final int id;
  final String path;
  const _IconRequest({required this.id, required this.path});
}

class _IconResponse {
  final int id;
  final ExtractedIcon data; // Uint8List | String | null
  const _IconResponse({required this.id, required this.data});
}

// Sent once, on startup, to give workers a port for teardown signals.
class _ShutdownSignal {
  const _ShutdownSignal();
}

void _iconWorkerEntry(SendPort mainSendPort) {
  final ReceivePort port = ReceivePort();
  mainSendPort.send(port.sendPort); // handshake

  port.listen((dynamic msg) {
    if (msg is _ShutdownSignal) {
      port.close();
      return;
    }
    if (msg is _IconRequest) {
      ExtractedIcon result;
      try {
        result = WinUtils.extractIcon(msg.path);
      } catch (e, st) {
        // Debug.add is isolate-safe because it only writes to a global list.
        Debug.add('worker: extractIcon failed for ${msg.path}: $e\n$st');
        result = null;
      }
      mainSendPort.send(_IconResponse(id: msg.id, data: result));
    }
  });
}

class _WorkerPool {
  _WorkerPool._();
  static final _WorkerPool instance = _WorkerPool._();

  static const int _poolSize = 3;
  static const Duration _timeout = Duration(seconds: 8);

  Future<void>? _initFuture;
  bool _disposed = false;

  final List<_Worker> _workers = <_Worker>[];
  final Map<int, _PendingRequest> _pending = <int, _PendingRequest>{};
  int _nextId = 0;
  int _rrIndex = 0;

  Future<void> _ensureReady() => _initFuture ??= _spawnAll();

  Future<void> _spawnAll() async {
    for (int i = 0; i < _poolSize; i++) {
      _workers.add(await _Worker.spawn(_onResponse));
    }
  }

  void _onResponse(_IconResponse resp) {
    final _PendingRequest? req = _pending.remove(resp.id);
    req?.complete(resp.data);
  }

  Future<ExtractedIcon> extractIcon(String path) async {
    if (_disposed) return null;
    await _ensureReady();

    final int id = _nextId++;
    final _PendingRequest req = _PendingRequest(id: id, path: path, timeout: _timeout, onTimeout: _onTimeout);
    _pending[id] = req;

    _workers[_rrIndex++ % _poolSize].send(_IconRequest(id: id, path: path));
    return req.future;
  }

  void _onTimeout(int id) {
    final _PendingRequest? req = _pending.remove(id);
    if (req != null) {
      Debug.add('worker: timeout for ${req.path}');
      req.complete(null);
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    for (final _PendingRequest req in _pending.values) {
      req.complete(null);
    }
    _pending.clear();
    for (final _Worker w in _workers) {
      w.shutdown();
    }
    _workers.clear();
    _initFuture = null;
  }
}

class _Worker {
  _Worker._(this._sendPort, this._receivePort);

  final SendPort _sendPort;
  final ReceivePort _receivePort;

  static Future<_Worker> spawn(void Function(_IconResponse) onResponse) async {
    final ReceivePort receivePort = ReceivePort();
    await Isolate.spawn(_iconWorkerEntry, receivePort.sendPort);

    final Completer<SendPort> ready = Completer<SendPort>();
    bool handshakeDone = false;

    receivePort.listen((dynamic msg) {
      if (!handshakeDone) {
        if (msg is SendPort && !ready.isCompleted) {
          handshakeDone = true;
          ready.complete(msg);
        }
        return;
      }
      if (msg is _IconResponse) onResponse(msg);
    });

    final SendPort workerSend = await ready.future;
    return _Worker._(workerSend, receivePort);
  }

  void send(_IconRequest req) => _sendPort.send(req);

  void shutdown() {
    _sendPort.send(const _ShutdownSignal());
    _receivePort.close();
  }
}

class _PendingRequest {
  _PendingRequest({
    required this.id,
    required this.path,
    required Duration timeout,
    required void Function(int) onTimeout,
  }) {
    _timer = Timer(timeout, () => onTimeout(id));
  }

  final int id;
  final String path;
  final Completer<ExtractedIcon> _completer = Completer<ExtractedIcon>();
  late final Timer _timer;

  Future<ExtractedIcon> get future => _completer.future;

  void complete(ExtractedIcon data) {
    _timer.cancel();
    if (!_completer.isCompleted) _completer.complete(data);
  }
}

class IconDiskCache {
  IconDiskCache._();
  static final IconDiskCache instance = IconDiskCache._();

  static const Duration _ttl = Duration(days: 7);

  static const Set<String> _junkHashes = <String>{
    'a326e0850b34c1935b2e3499fc986380',
    '5b290ed4dac06a15d465c7f0f9d5003b',
  };

  late final String _cacheDir;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _cacheDir = p.join(WinUtils.getTabameAppDataFolder(), 'cache', 'icon_cache');
    await Directory(_cacheDir).create(recursive: true);
    _initialized = true;
  }

  Future<Uint8List?> load(String sourceKey) async {
    final File f = _fileFor(sourceKey);
    if (!f.existsSync()) return null;
    if (DateTime.now().difference(f.lastModifiedSync()) > _ttl) {
      f.deleteSync();
      return null;
    }
    try {
      return await f.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  Future<bool> save(String sourceKey, Uint8List bytes) async {
    final String hash = crypto.md5.convert(bytes).toString();
    if (_junkHashes.contains(hash)) return false;
    try {
      await _fileFor(sourceKey).writeAsBytes(bytes, flush: true);
    } catch (_) {}
    return true;
  }

  Future<void> evictExpired() async {
    try {
      await for (final FileSystemEntity e in Directory(_cacheDir).list()) {
        if (e is File) {
          final DateTime mod = e.lastModifiedSync();
          if (DateTime.now().difference(mod) > _ttl) await e.delete();
        }
      }
    } catch (_) {}
  }

  Future<int> sizeInBytes() async {
    int total = 0;
    try {
      await for (final FileSystemEntity e in Directory(_cacheDir).list()) {
        if (e is File) total += e.lengthSync();
      }
    } catch (_) {}
    return total;
  }

  File _fileFor(String key) {
    final String hash = crypto.sha1.convert(key.codeUnits).toString();
    return File(p.join(_cacheDir, '$hash.ico'));
  }
}

class _LruEntry {
  _LruEntry({required this.icon, required this.key});
  final ExtractedIcon icon;
  final String key;
  final DateTime expiresAt = DateTime.now().add(_MemCache._ttl);
  bool get expired => DateTime.now().isAfter(expiresAt);
}

class _MemCache {
  _MemCache(this._maxEntries);

  static const Duration _ttl = Duration(minutes: 15);
  final int _maxEntries;

  final Map<String, _LruEntry> _map = <String, _LruEntry>{};

  ExtractedIcon? get(String key) {
    final _LruEntry? e = _map[key];
    if (e == null) return null;
    if (e.expired) {
      _map.remove(key);
      return null;
    }
    _map.remove(key);
    _map[key] = e;
    return e.icon;
  }

  bool has(String key) => get(key) != null;

  void put(String key, ExtractedIcon icon) {
    _map.remove(key);
    _map[key] = _LruEntry(icon: icon, key: key);
    _evictIfNeeded();
  }

  void _evictIfNeeded() {
    while (_map.length > _maxEntries) {
      _map.remove(_map.keys.first);
    }
  }

  void evictExpired() => _map.removeWhere((_, _LruEntry e) => e.expired);

  int get length => _map.length;
}

const Set<String> _perFileExtensions = <String>{'.exe', '.lnk', '.url', '.ico'};

// resolved per-file.
String? _extKey(String path) {
  final String t = path.trim();
  if (t.isEmpty || t.endsWith('/') || t.endsWith(r'\')) return null;
  try {
    if (Directory(t).existsSync()) return null;
  } catch (_) {}
  final int dot = t.lastIndexOf('.');
  if (dot < 0) return null;
  final String ext = '.${t.substring(dot + 1).toLowerCase()}';
  return _perFileExtensions.contains(ext) ? null : ext;
}

class IconService {
  IconService._();
  static final IconService instance = IconService._();

  final _MemCache _extMem = _MemCache(200);
  final _MemCache _pathMem = _MemCache(150);

  final Map<String, Future<ExtractedIcon>> _inFlight = <String, Future<ExtractedIcon>>{};

  Future<ExtractedIcon>? _folderIconFuture;

  bool _diskReady = false;

  // ── Initialisation ──────────────────────────────────────────────────────

  Future<void> init() async {
    if (_diskReady) return;
    await IconDiskCache.instance.init();
    _diskReady = true;
  }

  // ── Public API ──────────────────────────────────────────────────────────

  Future<ExtractedIcon> getIcon(String rawPath) {
    final String path = _applyRewrite(rawPath);
    if (path.isEmpty) return Future<ExtractedIcon>.value(null);
    return _resolve(path);
  }

  void prefetch(Iterable<String> paths) {
    for (final String p in paths) {
      getIcon(p);
    }
  }

  // ── Resolution pipeline ─────────────────────────────────────────────────

  Future<ExtractedIcon> _resolve(String path) {
    // ── .url: never cache (target can change at any time) ────────────────
    if (path.toLowerCase().endsWith('.url')) {
      return _WorkerPool.instance.extractIcon(path);
    }

    // ── Default folder icon (shared singleton) ───────────────────────────
    if (WinUtils.usesDefaultFolderIcon(path)) {
      return _resolveFolderIcon(path);
    }

    // ── Extension-type cache (.mp3, .pdf, …) ────────────────────────────
    final String? ek = _extKey(path);
    if (ek != null) return _resolveByExt(path, ek);

    // ── Per-path cache (.exe, .lnk, directories, …) ─────────────────────
    return _resolveByPath(path);
  }

  Future<ExtractedIcon> _resolveFolderIcon(String path) {
    return _folderIconFuture ??= _resolveFolderAsync(path);
  }

  Future<ExtractedIcon> _resolveFolderAsync(String path) async {
    try {
      final ExtractedIcon icon = await _fetchAndCache(path);
      if (!_isUsable(icon)) {
        _folderIconFuture = null;
        return null;
      }
      return icon;
    } catch (e, st) {
      Debug.add('IconService: folder icon failed for $path: $e\n$st');
      _folderIconFuture = null;
      return null;
    }
  }

  Future<ExtractedIcon> _resolveByExt(String path, String extKey) {
    final ExtractedIcon? mem = _extMem.get(extKey);
    if (mem != null) return Future<ExtractedIcon>.value(mem);

    return _inFlight.putIfAbsent(extKey, () => _resolveExtAsync(path, extKey));
  }

  Future<ExtractedIcon> _resolveExtAsync(String path, String extKey) async {
    try {
      if (_diskReady) {
        final Uint8List? disk = await IconDiskCache.instance.load(extKey);
        if (disk != null) {
          _extMem.put(extKey, disk);
          return disk;
        }
      }
      return await _fetchAndCache(path, cacheKey: extKey, useExtMem: true);
    } finally {
      _inFlight.remove(extKey);
    }
  }

  Future<ExtractedIcon> _resolveByPath(String path) {
    final ExtractedIcon? mem = _pathMem.get(path);
    if (mem != null) return Future<ExtractedIcon>.value(mem);

    return _inFlight.putIfAbsent(path, () => _resolvePathAsync(path));
  }

  Future<ExtractedIcon> _resolvePathAsync(String path) async {
    try {
      if (_diskReady) {
        final Uint8List? disk = await IconDiskCache.instance.load(path);
        if (disk != null) {
          _pathMem.put(path, disk);
          return disk;
        }
      }
      return await _fetchAndCache(path, cacheKey: path, useExtMem: false);
    } finally {
      _inFlight.remove(path);
    }
  }

  Future<ExtractedIcon> _fetchAndCache(
    String path, {
    String? cacheKey,
    bool useExtMem = false,
    ExtractedIcon Function(ExtractedIcon)? onSuccess,
    void Function()? onError,
  }) async {
    try {
      ExtractedIcon raw = await _WorkerPool.instance.extractIcon(path);
      if (onSuccess != null) raw = onSuccess(raw);

      if (!_isUsable(raw)) return null;

      if (raw is Uint8List && _diskReady) {
        final String key = cacheKey ?? path;
        final bool saved = await IconDiskCache.instance.save(key, raw);
        if (!saved) return null; // junk icon — don't cache
      }

      // Promote to memory cache.
      if (cacheKey != null) {
        if (useExtMem) {
          _extMem.put(cacheKey, raw);
        } else {
          _pathMem.put(cacheKey, raw);
        }
      }

      return raw;
    } catch (e, st) {
      Debug.add('IconService: extraction failed for $path: $e\n$st');
      onError?.call();
      return null;
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  static String _applyRewrite(String path) {
    if (path.trim().isEmpty) return '';
    final String rewrite = Boxes.getIconRewrite(path);
    return rewrite.isNotEmpty ? rewrite : path;
  }

  static bool _isUsable(ExtractedIcon icon) {
    if (icon == null) return false;
    if (icon is Uint8List) {
      if (icon.isEmpty) return false;
      const Set<String> junk = <String>{
        'a326e0850b34c1935b2e3499fc986380',
        '5b290ed4dac06a15d465c7f0f9d5003b',
      };
      return !junk.contains(crypto.md5.convert(icon).toString());
    }
    if (icon is String) return icon.isNotEmpty;
    return false;
  }

  // ── Stats & maintenance ──────────────────────────────────────────────────

  int get memCacheSize => _extMem.length + _pathMem.length;
  int get inFlightCount => _inFlight.length;

  Future<String> diskCacheSizeKb() async {
    final int bytes = await IconDiskCache.instance.sizeInBytes();
    return '${(bytes / 1024).toStringAsFixed(2)} KB';
  }

  void evictExpiredMemory() {
    _extMem.evictExpired();
    _pathMem.evictExpired();
  }

  Future<void> evictExpiredDisk() => IconDiskCache.instance.evictExpired();

  Future<void> dispose() async {
    _inFlight.clear();
    await _WorkerPool.instance.dispose();
  }
}

class WindowsAppButton extends StatefulWidget {
  const WindowsAppButton({
    super.key,
    required this.path,
    this.arguments,
    this.onTap,
    this.placeholder,
  });

  final String path;
  final String? arguments;
  final VoidCallback? onTap;
  final Widget? placeholder;

  static Future<ExtractedIcon> getIcon(String path) => IconService.instance.getIcon(path);

  static void prefetch(Iterable<String> paths) => IconService.instance.prefetch(paths);

  static int getCacheSize() => IconService.instance.memCacheSize;
  static Future<String> getCacheInKb() => IconService.instance.diskCacheSizeKb();

  @override
  State<WindowsAppButton> createState() => _WindowsAppButtonState();
}

class _WindowsAppButtonState extends State<WindowsAppButton> {
  ExtractedIcon? _icon;
  Object? _loadTag;

  @override
  void initState() {
    super.initState();
    _load(widget.path);
  }

  @override
  void didUpdateWidget(covariant WindowsAppButton old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      setState(() => _icon = null);
      _load(widget.path);
    }
  }

  @override
  void dispose() {
    _loadTag = null;
    super.dispose();
  }

  void _load(String path) {
    final Object tag = Object();
    _loadTag = tag;

    IconService.instance.getIcon(path).then((ExtractedIcon? icon) {
      if (!mounted || _loadTag != tag) return;
      setState(() => _icon = icon);
    }, onError: (Object e, StackTrace st) {
      Debug.add('WindowsAppButton: load error for $path: $e\n$st');
      if (!mounted || _loadTag != tag) return;
      setState(() => _icon = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final Widget fallback = widget.placeholder ?? const SizedBox(width: 32, height: 32);

    return GestureDetector(
      onTap: widget.onTap,
      child: _icon == null
          ? fallback
          : buildExtractedIcon(
              _icon,
              width: 32,
              height: 32,
              gaplessPlayback: true,
              fallback: fallback,
            ),
    );
  }
}
