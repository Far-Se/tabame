import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../platform/app_paths.dart';
import '../platform/clipboard_service.dart';
import '../platform/platform_models.dart';
import 'classes/save_settings.dart';

enum ClipboardHistoryType {
  text,
  richText,
  image,
}

const int _clipboardHistorySchemaVersion = 2;
const int _clipboardHistoryPreviewLimit = 5000;

String _clipboardPreview(String value, [int limit = _clipboardHistoryPreviewLimit]) {
  if (value.length <= limit) return value;
  return value.substring(0, limit);
}

String _mapString(Map<String, dynamic> map, String key) {
  final dynamic value = map[key];
  return value is String ? value : '';
}

int _mapInt(Map<String, dynamic> map, String key, [int fallback = 0]) {
  final dynamic value = map[key];
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? fallback;
}

String _resolveClipboardImagePath(String storedPath) {
  if (storedPath.trim().isEmpty) return storedPath;
  try {
    final String normalizedStored = p.normalize(File(storedPath).absolute.path);
    final String normalizedLegacyRoot = p.normalize(
      AppPaths.legacyPath(p.join('cache', 'clipboard_images')),
    );
    final String comparisonStored = Platform.isWindows ? normalizedStored.toLowerCase() : normalizedStored;
    final String comparisonLegacy = Platform.isWindows ? normalizedLegacyRoot.toLowerCase() : normalizedLegacyRoot;
    final bool isLegacyImage =
        comparisonStored == comparisonLegacy || comparisonStored.startsWith('$comparisonLegacy${p.separator}');
    if (!isLegacyImage) return storedPath;

    final String relative = p.relative(normalizedStored, from: normalizedLegacyRoot);
    final String migratedPath = p.join(
      AppPaths.cachePath('clipboard_images', forWrite: true),
      relative,
    );
    return File(migratedPath).existsSync() ? migratedPath : storedPath;
  } catch (_) {
    return storedPath;
  }
}

String _clipboardPayloadRootPath() {
  return p.normalize(File(AppPaths.cachePath('clipboard_payloads', forWrite: true)).absolute.path);
}

bool _isInsideClipboardPayloadRoot(String path) {
  final String candidate = p.normalize(File(path).absolute.path);
  final String root = _clipboardPayloadRootPath();
  final String comparisonCandidate = Platform.isWindows ? candidate.toLowerCase() : candidate;
  final String comparisonRoot = Platform.isWindows ? root.toLowerCase() : root;
  return comparisonCandidate == comparisonRoot || comparisonCandidate.startsWith('$comparisonRoot${p.separator}');
}

String _resolveClipboardPayloadPath(String storedPath) {
  if (storedPath.trim().isEmpty) return '';
  try {
    final String candidate =
        p.isAbsolute(storedPath) ? File(storedPath).absolute.path : p.join(AppPaths.cacheDirectory, storedPath);
    final String normalized = p.normalize(candidate);
    return _isInsideClipboardPayloadRoot(normalized) ? normalized : '';
  } catch (_) {
    return '';
  }
}

String _serializeClipboardPayloadPath(String storedPath) {
  final String resolved = _resolveClipboardPayloadPath(storedPath);
  if (resolved.isEmpty) return '';
  try {
    return p.normalize(p.relative(resolved, from: AppPaths.cacheDirectory));
  } catch (_) {
    return '';
  }
}

class ClipboardHistoryEntry {
  ClipboardHistoryEntry({
    required this.id,
    required this.type,
    required this.createdAt,
    this.text = '',
    this.html = '',
    this.imagePath = '',
    this.textPath = '',
    this.htmlPath = '',
    this.contentHash = '',
    this.byteLength = 0,
    this.pinned = false,
    this.textLength,
    this.htmlLength,
  });

  final String id;
  final ClipboardHistoryType type;

  /// In schema v2 these are bounded previews, never the full payload.
  final DateTime createdAt;
  final String text;
  final String html;
  final String imagePath;
  final String textPath;
  final String htmlPath;
  final String contentHash;
  final int byteLength;
  final bool pinned;
  final int? textLength;
  final int? htmlLength;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'schema': _clipboardHistorySchemaVersion,
      'id': id,
      'type': type.name,
      'createdAt': createdAt.toIso8601String(),
      'text': _clipboardPreview(text),
      'html': _clipboardPreview(html),
      'imagePath': imagePath,
      if (textPath.isNotEmpty) 'textPath': _serializeClipboardPayloadPath(textPath),
      if (htmlPath.isNotEmpty) 'htmlPath': _serializeClipboardPayloadPath(htmlPath),
      if (contentHash.isNotEmpty) 'contentHash': contentHash,
      'byteLength': byteLength,
      'pinned': pinned,
      if (textLength != null) 'textLength': textLength,
      if (htmlLength != null) 'htmlLength': htmlLength,
    };
  }

  factory ClipboardHistoryEntry.fromMap(Map<String, dynamic> map, {bool truncate = false}) {
    String text = _mapString(map, 'text');
    String html = _mapString(map, 'html');
    final int textTotalLength = _mapInt(map, 'textLength', text.length);
    final int htmlTotalLength = _mapInt(map, 'htmlLength', html.length);

    if (truncate) {
      text = _clipboardPreview(text);
      html = _clipboardPreview(html);
    }

    return ClipboardHistoryEntry(
      id: _mapString(map, 'id'),
      type: ClipboardHistoryType.values.firstWhere(
        (ClipboardHistoryType type) => type.name == map['type'],
        orElse: () => ClipboardHistoryType.text,
      ),
      createdAt: DateTime.tryParse(_mapString(map, 'createdAt')) ?? DateTime.fromMillisecondsSinceEpoch(0),
      text: text,
      html: html,
      imagePath: _resolveClipboardImagePath(_mapString(map, 'imagePath')),
      textPath: _resolveClipboardPayloadPath(
          _mapString(map, 'textPath').isNotEmpty ? _mapString(map, 'textPath') : _mapString(map, 'textFile')),
      htmlPath: _resolveClipboardPayloadPath(
          _mapString(map, 'htmlPath').isNotEmpty ? _mapString(map, 'htmlPath') : _mapString(map, 'htmlFile')),
      contentHash: _mapString(map, 'contentHash').isNotEmpty ? _mapString(map, 'contentHash') : _mapString(map, 'hash'),
      byteLength: _mapInt(map, 'byteLength'),
      pinned: map['pinned'] == true,
      textLength: textTotalLength,
      htmlLength: htmlTotalLength,
    );
  }

  ClipboardHistoryEntry copyWith({
    String? id,
    ClipboardHistoryType? type,
    DateTime? createdAt,
    String? text,
    String? html,
    String? imagePath,
    String? textPath,
    String? htmlPath,
    String? contentHash,
    int? byteLength,
    bool? pinned,
    int? textLength,
    int? htmlLength,
  }) {
    return ClipboardHistoryEntry(
      id: id ?? this.id,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      text: text ?? this.text,
      html: html ?? this.html,
      imagePath: imagePath ?? this.imagePath,
      textPath: textPath ?? this.textPath,
      htmlPath: htmlPath ?? this.htmlPath,
      contentHash: contentHash ?? this.contentHash,
      byteLength: byteLength ?? this.byteLength,
      pinned: pinned ?? this.pinned,
      textLength: textLength ?? this.textLength,
      htmlLength: htmlLength ?? this.htmlLength,
    );
  }
}

class ClipboardHistoryStore {
  ClipboardHistoryStore._();

  static const String enabledKey = 'clipboardHistoryEnabled';
  static const String cacheDaysKey = 'clipboardHistoryCacheDays';
  static const int defaultCacheDays = 3;
  static const int previewLimit = _clipboardHistoryPreviewLimit;
  static const int _clipboardReadAttempts = 5;

  /// Maximum number of recent entries kept in memory for duplicate detection.
  static const int _recentCacheSize = 10;

  static Future<void> _recordQueue = Future<void>.value();
  static Future<void>? _migrationFuture;

  /// In-memory ring of content hashes of the newest entries.
  /// Used only for duplicate detection — never exposed to the UI.
  static final List<String> _recentCache = <String>[];
  static bool _recentCacheLoaded = false;
  // A missing setting is treated as paused. First-run initialization also
  // writes this value explicitly so monitoring never starts by accident.
  static bool _fallbackEnabled = true;
  static int _fallbackCacheDays = defaultCacheDays;

  static bool get enabled => _readPersistedBool(enabledKey) ?? _fallbackEnabled;

  static int get cacheDays => _readPersistedInt(cacheDaysKey) ?? _fallbackCacheDays;

  static String get cacheDirectoryPath => AppPaths.cacheDirectory;
  static String get payloadDirectoryPath => AppPaths.cachePath('clipboard_payloads', forWrite: true);
  static String get imageDirectoryPath => AppPaths.cachePath('clipboard_images', forWrite: true);
  static String get historyFilePath => AppPaths.cachePath('clipboard_history.ndjson');
  static String get pinnedFilePath => AppPaths.cachePath('pinned_clipboard_history.ndjson');
  static String get _writableHistoryFilePath => AppPaths.cachePath('clipboard_history.ndjson', forWrite: true);
  static String get _writablePinnedFilePath => AppPaths.cachePath('pinned_clipboard_history.ndjson', forWrite: true);
  static String get _legacyHistoryFilePath => AppPaths.cachePath('clipboard.json');
  static String get _legacyPinnedFilePath => AppPaths.cachePath('pinned_clipboard.json');

  /// Whether the active adapter can capture a text clipboard directly to files.
  /// Windows uses this to keep large values out of Dart; other adapters use the
  /// portable read-and-write fallback below.
  static bool get supportsFileCapture => ClipboardService.instance.supportsClipboardFileCapture;

  static Future<void> setEnabled(bool value) async {
    _fallbackEnabled = value;
    try {
      final SaveSettings settings = await SaveSettings.getInstance();
      await settings.setBool(enabledKey, value);
    } catch (_) {}
  }

  static Future<void> setCacheDays(int value) async {
    final int clamped = value.clamp(1, 365);
    _fallbackCacheDays = clamped;
    try {
      final SaveSettings settings = await SaveSettings.getInstance();
      await settings.setInt(cacheDaysKey, clamped);
    } catch (_) {}
    // Pruning is intentionally NOT done automatically here.
    // Call clearCache() explicitly when desired.
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Load pinned metadata from disk. Payload files are not read.
  static Future<List<ClipboardHistoryEntry>> loadPinned() async {
    await _ensureStorageMigrated();
    try {
      final List<ClipboardHistoryEntry> entries = await _loadPinnedFull();
      entries.sort((ClipboardHistoryEntry a, ClipboardHistoryEntry b) => b.createdAt.compareTo(a.createdAt));
      return entries;
    } catch (_) {
      return <ClipboardHistoryEntry>[];
    }
  }

  /// Load a paged slice of metadata from disk. Payload files are not read.
  static Future<List<ClipboardHistoryEntry>> loadPaged({
    int offset = 0,
    int limit = 30,
    String query = '',
  }) async {
    await _ensureStorageMigrated();
    try {
      if (limit <= 0) return <ClipboardHistoryEntry>[];
      final List<ClipboardHistoryEntry> all = await _loadAllFull();
      final String q = query.trim().toLowerCase();
      final List<ClipboardHistoryEntry> entries = <ClipboardHistoryEntry>[];
      int skipCount = 0;

      for (final ClipboardHistoryEntry entry in all.reversed) {
        if (q.isNotEmpty && !'${entry.text}\n${entry.html}'.toLowerCase().contains(q)) continue;
        if (skipCount < offset) {
          skipCount++;
          continue;
        }
        entries.add(entry.copyWith(
          text: _clipboardPreview(entry.text),
          html: _clipboardPreview(entry.html),
        ));
        if (entries.length >= limit) break;
      }
      return entries;
    } catch (error) {
      _log('ClipboardHistory: load failed $error');
      return <ClipboardHistoryEntry>[];
    }
  }

  /// Retrieve metadata by ID without reading a payload file.
  static Future<ClipboardHistoryEntry?> getEntryById(String id) async {
    await _ensureStorageMigrated();
    return _findMetadataEntry(id);
  }

  /// Retrieve the full entry by reading its sidecar payload files.
  static Future<ClipboardHistoryEntry?> getFullEntry(String id) async {
    final ClipboardHistoryEntry? entry = await getEntryById(id);
    return entry == null ? null : _loadPayload(entry);
  }

  /// Copy an entry by ID without loading its full content into Dart on Windows.
  static Future<bool> copyById(String id) async {
    final ClipboardHistoryEntry? entry = await getEntryById(id);
    if (entry == null) return false;
    return _copyEntry(entry);
  }

  /// Copies the [index]th most recent unpinned entry to the system clipboard.
  /// Indexes are one-based, so index 1 is the newest entry.
  static Future<bool> copyByIndex(int index) async {
    if (index < 1) return false;
    final List<ClipboardHistoryEntry> entries = await loadPaged(limit: index);
    if (entries.length < index) return false;
    return copyEntry(entries[index - 1]);
  }

  @Deprecated('Use loadPaged or loadPinned instead')
  static Future<List<ClipboardHistoryEntry>> load() async => loadPaged(limit: 99999);

  /// Load all metadata entries. The historical name is retained for callers
  /// inside this store; it no longer implies loading large clipboard payloads.
  static Future<List<ClipboardHistoryEntry>> _loadAllFull() async {
    return _loadMetadataFile(historyFilePath);
  }

  static Future<List<ClipboardHistoryEntry>> _loadPinnedFull() async {
    return _loadMetadataFile(pinnedFilePath);
  }

  /// Record the current clipboard through the neutral platform contract.
  static Future<void> recordCurrentClipboard() {
    return _recordEntry(() async {
      if (supportsFileCapture) {
        // The native capture checks text/HTML first and writes directly to
        // sidecars. If it reports no textual payload, try the image adapter;
        // never fall back to pasteRichText on a Windows capture failure.
        final ClipboardHistoryEntry? text = await _captureTextToFiles();
        if (text != null) return text;
        return _readImage();
      }

      // Portable adapters do not expose a file-backed capture yet. Preserve
      // their image-first behavior, then write a single text read to sidecars.
      final ClipboardHistoryEntry? image = await _readImage();
      if (image != null) return image;
      final PlatformClipboardContent? content = await _tryClipboardRead<PlatformClipboardContent?>(
        'clipboard content',
        () => ClipboardService.instance.readContent(),
      );
      return content == null ? null : _saveContentEntry(content);
    });
  }

  /// Record an event payload when it is an authoritative snapshot. Notification
  /// events (Windows) trigger the file-backed current-clipboard capture instead.
  static Future<void> recordClipboardChange(PlatformClipboardText change) {
    if (!change.isSnapshot || change.text.isEmpty) return recordCurrentClipboard();
    return _recordEntry(() async => _saveContentEntry(PlatformClipboardContent(text: change.text)));
  }

  /// Prune entries older than [cacheDays] and delete orphaned payload files.
  static Future<void> clearCache() async {
    await _ensureStorageMigrated();
    try {
      final List<ClipboardHistoryEntry> all = await _loadAllFull();
      final DateTime cutoff = DateTime.now().subtract(Duration(days: cacheDays));
      final List<ClipboardHistoryEntry> keptHistory =
          all.where((ClipboardHistoryEntry e) => e.createdAt.isAfter(cutoff)).toList();
      final List<ClipboardHistoryEntry> pinned = await _loadPinnedFull();

      await _rewriteFile(keptHistory, historyFilePath);
      _prunePayloads(<ClipboardHistoryEntry>[...keptHistory, ...pinned]);
      _rebuildRecentCache(<ClipboardHistoryEntry>[...keptHistory, ...pinned]);
    } catch (error) {
      _log('ClipboardHistory: clearCache failed $error');
    }
  }

  /// Copy a clipboard entry back to the system clipboard.
  static Future<bool> copyEntry(ClipboardHistoryEntry entry) => _copyEntry(entry);

  static Future<bool> _copyEntry(ClipboardHistoryEntry entry) async {
    if (entry.type == ClipboardHistoryType.image) {
      if (entry.imagePath.isEmpty || !File(entry.imagePath).existsSync()) return false;
      return ClipboardService.instance.writeContentFromFiles(imagePath: entry.imagePath);
    }

    if (entry.textPath.isNotEmpty || entry.htmlPath.isNotEmpty) {
      final String textPath = _resolveClipboardPayloadPath(entry.textPath);
      final String htmlPath = _resolveClipboardPayloadPath(entry.htmlPath);
      final bool textExists = textPath.isEmpty || File(textPath).existsSync();
      final bool htmlExists = htmlPath.isEmpty || File(htmlPath).existsSync();
      if (!textExists || !htmlExists) return false;
      return ClipboardService.instance.writeContentFromFiles(
        textPath: textPath,
        htmlPath: htmlPath,
      );
    }

    // This is kept for callers that construct an entry in memory. Never copy a
    // bounded preview when the metadata says a larger payload should exist.
    if ((entry.textLength ?? entry.text.length) > entry.text.length ||
        (entry.htmlLength ?? entry.html.length) > entry.html.length) {
      return false;
    }
    if (entry.text.isEmpty && entry.html.isEmpty) return false;
    return ClipboardService.instance.writeContent(
      PlatformClipboardContent(
        text: entry.text,
        html: _htmlFragment(entry.html),
      ),
    );
  }

  /// Remove a single entry from metadata and delete payloads no longer used by
  /// either the history or pinned log.
  static Future<void> remove(ClipboardHistoryEntry entry) async {
    await _ensureStorageMigrated();
    final List<ClipboardHistoryEntry> all = await _loadAllFull();
    final List<ClipboardHistoryEntry> pinned = await _loadPinnedFull();
    final ClipboardHistoryEntry? stored = _firstById(<ClipboardHistoryEntry>[...all, ...pinned], entry.id);
    final List<ClipboardHistoryEntry> nextHistory =
        all.where((ClipboardHistoryEntry item) => item.id != entry.id).toList();
    final List<ClipboardHistoryEntry> nextPinned =
        pinned.where((ClipboardHistoryEntry item) => item.id != entry.id).toList();

    await _rewriteFile(nextHistory, historyFilePath);
    await _rewriteFile(nextPinned, pinnedFilePath);
    if (stored != null) {
      await _deletePayloadsIfUnreferenced(stored, <ClipboardHistoryEntry>[...nextHistory, ...nextPinned]);
    }
    _recentCache.removeWhere((String hash) => hash == _contentHash(stored ?? entry));
  }

  /// Toggle the pinned state of an entry without loading its payload.
  static Future<void> setPinned(ClipboardHistoryEntry entry, bool pinned) async {
    await _ensureStorageMigrated();
    final List<ClipboardHistoryEntry> allPinned = await _loadPinnedFull();
    final List<ClipboardHistoryEntry> allHistory = await _loadAllFull();
    final ClipboardHistoryEntry? stored = _firstById(<ClipboardHistoryEntry>[...allPinned, ...allHistory], entry.id);
    if (stored == null) return;

    final List<ClipboardHistoryEntry> nextPinned =
        allPinned.where((ClipboardHistoryEntry item) => item.id != entry.id).toList();
    final List<ClipboardHistoryEntry> nextHistory =
        allHistory.where((ClipboardHistoryEntry item) => item.id != entry.id).toList();
    final ClipboardHistoryEntry updated = stored.copyWith(pinned: pinned);
    (pinned ? nextPinned : nextHistory).add(updated);
    nextPinned.sort(_sortAscending);
    nextHistory.sort(_sortAscending);

    await _rewriteFile(nextHistory, historyFilePath);
    await _rewriteFile(nextPinned, pinnedFilePath);
    _rebuildRecentCache(<ClipboardHistoryEntry>[...nextHistory, ...nextPinned]);
  }

  /// Delete all metadata, payloads, and images.
  static Future<void> clear() async {
    await _ensureStorageMigrated();
    await _rewriteFile(<ClipboardHistoryEntry>[], historyFilePath);
    await _rewriteFile(<ClipboardHistoryEntry>[], pinnedFilePath);
    _recentCache.clear();
    _recentCacheLoaded = true;

    await _deleteFile(_legacyHistoryFilePath);
    await _deleteFile(_legacyPinnedFilePath);
    await _deleteDirectoryFiles(payloadDirectoryPath);
    await _deleteDirectoryFiles(imageDirectoryPath);
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  static Future<void> _recordEntry(Future<ClipboardHistoryEntry?> Function() readEntry) {
    final Future<void> operation = _recordQueue.then<void>((_) => _recordEntryNow(readEntry));
    _recordQueue = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        _log('ClipboardHistory: queued record failed $error');
      },
    );
    return operation;
  }

  static Future<void> _recordEntryNow(Future<ClipboardHistoryEntry?> Function() readEntry) async {
    if (!enabled) return;
    await _ensureStorageMigrated();

    ClipboardHistoryEntry? entry;
    try {
      entry = await readEntry();
      if (entry == null) return;

      await _ensureRecentCacheLoaded();
      final String entryHash = _contentHash(entry);
      if (entryHash.isNotEmpty && _recentCache.contains(entryHash)) {
        await _deletePayloads(entry);
        return;
      }

      final ClipboardHistoryEntry metadata = entry.copyWith(
        text: _clipboardPreview(entry.text),
        html: _clipboardPreview(entry.html),
        textLength: entry.textLength ?? entry.text.length,
        htmlLength: entry.htmlLength ?? entry.html.length,
        contentHash: entryHash,
      );
      await _appendEntry(metadata);

      if (entryHash.isNotEmpty) {
        _recentCache.insert(0, entryHash);
        if (_recentCache.length > _recentCacheSize) _recentCache.removeLast();
      }
    } catch (error) {
      if (entry != null) await _deletePayloads(entry);
      _log('ClipboardHistory: record failed $error');
    }
  }

  static Future<void> _ensureRecentCacheLoaded() async {
    if (_recentCacheLoaded) return;
    _recentCacheLoaded = true;
    try {
      final List<ClipboardHistoryEntry> all = <ClipboardHistoryEntry>[
        ...await _loadAllFull(),
        ...await _loadPinnedFull(),
      ]..sort((ClipboardHistoryEntry a, ClipboardHistoryEntry b) => b.createdAt.compareTo(a.createdAt));
      _rebuildRecentCache(all);
    } catch (_) {}
  }

  static void _rebuildRecentCache(List<ClipboardHistoryEntry> entries) {
    final List<ClipboardHistoryEntry> ordered = List<ClipboardHistoryEntry>.from(entries)
      ..sort((ClipboardHistoryEntry a, ClipboardHistoryEntry b) => b.createdAt.compareTo(a.createdAt));
    _recentCache
      ..clear()
      ..addAll(ordered.map(_contentHash).where((String hash) => hash.isNotEmpty).take(_recentCacheSize));
    _recentCacheLoaded = true;
  }

  static Future<ClipboardHistoryEntry?> _captureTextToFiles() async {
    final DateTime now = DateTime.now();
    final String id = _entryId(now);
    final Directory payloadDirectory = Directory(payloadDirectoryPath);
    if (!payloadDirectory.existsSync()) await payloadDirectory.create(recursive: true);
    final String textPath = p.join(payloadDirectory.path, '$id.txt');
    final String htmlPath = p.join(payloadDirectory.path, '$id.html');

    final PlatformClipboardFileCapture? capture = await _tryClipboardRead<PlatformClipboardFileCapture?>(
      'text file capture',
      () => ClipboardService.instance.captureClipboardToFiles(
        textPath: textPath,
        htmlPath: htmlPath,
        previewLimit: previewLimit,
      ),
    );
    if (capture == null || !capture.captured || capture.contentHash.isEmpty) {
      await _deleteFile(textPath);
      await _deleteFile(htmlPath);
      await _deleteFile('$textPath.part');
      await _deleteFile('$htmlPath.part');
      return null;
    }

    return ClipboardHistoryEntry(
      id: id,
      type: capture.htmlLength > 0 ? ClipboardHistoryType.richText : ClipboardHistoryType.text,
      createdAt: now,
      text: _clipboardPreview(capture.textPreview),
      html: _clipboardPreview(capture.htmlPreview),
      textPath: capture.textLength > 0 ? _storedPayloadPath(textPath) : '',
      htmlPath: capture.htmlLength > 0 ? _storedPayloadPath(htmlPath) : '',
      contentHash: capture.contentHash,
      byteLength: capture.byteLength,
      textLength: capture.textLength,
      htmlLength: capture.htmlLength,
    );
  }

  static Future<ClipboardHistoryEntry?> _saveContentEntry(PlatformClipboardContent content) async {
    final String text = content.text;
    final String html = content.html.isEmpty ? '' : _htmlFragment(content.html);
    if (text.isEmpty && html.isEmpty) return null;

    final DateTime now = DateTime.now();
    final String id = _entryId(now);
    final Directory payloadDirectory = Directory(payloadDirectoryPath);
    if (!payloadDirectory.existsSync()) await payloadDirectory.create(recursive: true);

    final String textPath = p.join(payloadDirectory.path, '$id.txt');
    final String htmlPath = p.join(payloadDirectory.path, '$id.html');
    bool textSaved = false;
    bool htmlSaved = false;
    try {
      final List<int> textBytes = utf8.encode(text);
      final List<int> htmlBytes = utf8.encode(html);
      if (text.isNotEmpty) {
        await File(textPath).writeAsBytes(textBytes, flush: true);
        textSaved = true;
      }
      if (html.isNotEmpty) {
        await File(htmlPath).writeAsBytes(htmlBytes, flush: true);
        htmlSaved = true;
      }

      return ClipboardHistoryEntry(
        id: id,
        type: html.isEmpty ? ClipboardHistoryType.text : ClipboardHistoryType.richText,
        createdAt: now,
        text: _clipboardPreview(text),
        html: _clipboardPreview(html),
        textPath: textSaved ? _storedPayloadPath(textPath) : '',
        htmlPath: htmlSaved ? _storedPayloadPath(htmlPath) : '',
        contentHash: _contentHashFromPayload(text, html),
        byteLength: textBytes.length + htmlBytes.length,
        textLength: text.length,
        htmlLength: html.length,
      );
    } catch (_) {
      await _deleteFile(textPath);
      await _deleteFile(htmlPath);
      return null;
    }
  }

  static Future<ClipboardHistoryEntry?> _readImage() async {
    final DateTime now = DateTime.now();
    final String id = _entryId(now);
    final Directory imageDir = Directory(imageDirectoryPath);
    if (!imageDir.existsSync()) await imageDir.create(recursive: true);
    final String imagePath = p.join(imageDir.path, '$id.png');

    final PlatformClipboardImageInfo? info = await _tryClipboardRead<PlatformClipboardImageInfo?>(
      'image',
      () => ClipboardService.instance.saveImageToFile(imagePath),
    );
    if (info == null) return null;

    return ClipboardHistoryEntry(
      id: id,
      type: ClipboardHistoryType.image,
      createdAt: now,
      imagePath: info.path,
      byteLength: info.byteLength,
      contentHash: info.hash.isNotEmpty ? 'img-bytes:${info.hash}' : '',
    );
  }

  static Future<List<ClipboardHistoryEntry>> _loadMetadataFile(String path) async {
    final File file = File(path);
    if (!file.existsSync()) return <ClipboardHistoryEntry>[];
    final List<String> lines = await file.readAsLines();
    final List<ClipboardHistoryEntry> entries = <ClipboardHistoryEntry>[];
    for (final String line in lines) {
      final String trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      try {
        final dynamic decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic>) {
          entries.add(ClipboardHistoryEntry.fromMap(decoded, truncate: true));
        } else if (decoded is Map) {
          entries.add(ClipboardHistoryEntry.fromMap(Map<String, dynamic>.from(decoded), truncate: true));
        }
      } catch (_) {}
    }
    return entries;
  }

  static ClipboardHistoryEntry? _firstById(List<ClipboardHistoryEntry> entries, String id) {
    for (final ClipboardHistoryEntry entry in entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  static Future<ClipboardHistoryEntry?> _findMetadataEntry(String id) async {
    final ClipboardHistoryEntry? pinned = _firstById(await _loadPinnedFull(), id);
    if (pinned != null) return pinned;
    return _firstById(await _loadAllFull(), id);
  }

  static Future<ClipboardHistoryEntry?> _loadPayload(ClipboardHistoryEntry entry) async {
    if (entry.type == ClipboardHistoryType.image) return entry;
    try {
      String text = entry.text;
      String html = entry.html;
      if (entry.textPath.isNotEmpty) text = await File(entry.textPath).readAsString();
      if (entry.htmlPath.isNotEmpty) html = await File(entry.htmlPath).readAsString();
      return entry.copyWith(text: text, html: html);
    } catch (error) {
      _log('ClipboardHistory: payload read failed $error');
      return null;
    }
  }

  static String _storedPayloadPath(String absolutePath) {
    try {
      return p.normalize(p.relative(absolutePath, from: cacheDirectoryPath));
    } catch (_) {
      return absolutePath;
    }
  }

  static int _sortAscending(ClipboardHistoryEntry a, ClipboardHistoryEntry b) => a.createdAt.compareTo(b.createdAt);

  static Future<void> _appendEntry(ClipboardHistoryEntry entry) async {
    final Directory cacheDir = Directory(cacheDirectoryPath);
    if (!cacheDir.existsSync()) await cacheDir.create(recursive: true);
    final File file = File(_writableHistoryFilePath);
    await file.writeAsString('${jsonEncode(entry.toMap())}\n', mode: FileMode.append, flush: true);
  }

  static Future<void> _rewriteFile(List<ClipboardHistoryEntry> entries, [String? path]) async {
    final Directory cacheDir = Directory(cacheDirectoryPath);
    if (!cacheDir.existsSync()) await cacheDir.create(recursive: true);

    final String requestedPath = path ?? historyFilePath;
    final String targetPath = requestedPath == historyFilePath
        ? _writableHistoryFilePath
        : requestedPath == pinnedFilePath
            ? _writablePinnedFilePath
            : requestedPath;
    final File file = File(targetPath);
    final StringBuffer buffer = StringBuffer();
    for (final ClipboardHistoryEntry entry in entries) {
      buffer.writeln(jsonEncode(entry.toMap()));
    }
    await file.writeAsString(buffer.toString(), flush: true);
  }

  static void _prunePayloads(List<ClipboardHistoryEntry> kept) {
    final Set<String> active = <String>{};
    for (final ClipboardHistoryEntry entry in kept) {
      if (entry.textPath.isNotEmpty) active.add(_normalizedPath(entry.textPath));
      if (entry.htmlPath.isNotEmpty) active.add(_normalizedPath(entry.htmlPath));
    }

    final Directory payloadDir = Directory(payloadDirectoryPath);
    if (!payloadDir.existsSync()) return;
    for (final FileSystemEntity entity in payloadDir.listSync()) {
      if (entity is! File) continue;
      if (entity.path.endsWith('.part') || !active.contains(_normalizedPath(entity.path))) {
        try {
          entity.deleteSync();
        } catch (_) {}
      }
    }
  }

  static Future<void> _deletePayloadsIfUnreferenced(
    ClipboardHistoryEntry entry,
    List<ClipboardHistoryEntry> remaining,
  ) async {
    final bool stillReferenced = remaining.any((ClipboardHistoryEntry item) =>
        item.id == entry.id ||
        (entry.textPath.isNotEmpty && item.textPath == entry.textPath) ||
        (entry.htmlPath.isNotEmpty && item.htmlPath == entry.htmlPath) ||
        (entry.imagePath.isNotEmpty && item.imagePath == entry.imagePath));
    if (stillReferenced) return;
    await _deletePayloads(entry);
  }

  static Future<void> _deletePayloads(ClipboardHistoryEntry entry) async {
    await _deleteFile(_resolveClipboardPayloadPath(entry.textPath));
    await _deleteFile(_resolveClipboardPayloadPath(entry.htmlPath));
    await _deleteFile(entry.imagePath);
  }

  static String _normalizedPath(String path) => File(path).absolute.path.toLowerCase();

  static String _contentHash(ClipboardHistoryEntry entry) {
    if (entry.contentHash.isNotEmpty) return entry.contentHash;
    if (entry.type == ClipboardHistoryType.image) {
      if (entry.text.startsWith('img-bytes:')) return entry.text;
      return md5.convert(utf8.encode('image:${entry.byteLength}:${entry.imagePath}')).toString();
    }
    return _contentHashFromPayload(entry.text, entry.html);
  }

  static String _contentHashFromPayload(String text, String html) {
    return md5.convert(utf8.encode('text:$text\nhtml:$html')).toString();
  }

  static String _entryId(DateTime now) => now.microsecondsSinceEpoch.toString();

  static String _htmlFragment(String html) {
    if (html.isEmpty) return '';

    final RegExpMatch? offsetMatch = RegExp(r'StartFragment:(\d+)\s+EndFragment:(\d+)', dotAll: true).firstMatch(html);
    if (offsetMatch != null) {
      final int? start = int.tryParse(offsetMatch.group(1) ?? '');
      final int? end = int.tryParse(offsetMatch.group(2) ?? '');
      if (start != null && end != null && start >= 0 && end > start && end <= html.length) {
        return html.substring(start, end).trim();
      }
    }

    const String startMarker = '<!--StartFragment-->';
    const String endMarker = '<!--EndFragment-->';
    final int markerStart = html.indexOf(startMarker);
    final int markerEnd = html.indexOf(endMarker);
    if (markerStart >= 0 && markerEnd > markerStart) {
      return html.substring(markerStart + startMarker.length, markerEnd).trim();
    }

    return html
        .replaceFirst(RegExp(r'^Version:.*?EndFragment:\d+\s*', dotAll: true), '')
        .replaceAll(startMarker, '')
        .replaceAll(endMarker, '')
        .trim();
  }

  static Future<T?> _tryClipboardRead<T>(String label, Future<T> Function() read) async {
    for (int attempt = 0; attempt < _clipboardReadAttempts; attempt++) {
      try {
        return await read();
      } catch (error) {
        if (attempt == _clipboardReadAttempts - 1) {
          _log('ClipboardHistory: $label read failed $error');
          return null;
        }
      }
      await Future<void>.delayed(Duration(milliseconds: 40 + (attempt * 35)));
    }
    return null;
  }

  static Future<void> _ensureStorageMigrated() {
    return _migrationFuture ??= _migrateLegacyStorage();
  }

  static Future<void> _migrateLegacyStorage() async {
    try {
      final List<List<String>> migrations = <List<String>>[
        <String>[_legacyHistoryFilePath, _writableHistoryFilePath, payloadDirectoryPath],
        <String>[_legacyPinnedFilePath, _writablePinnedFilePath, payloadDirectoryPath],
      ];
      for (final List<String> args in migrations) {
        final File target = File(args[1]);
        if (target.existsSync()) continue;
        final File source = File(args[0]);
        if (!source.existsSync()) continue;
        await Isolate.run<void>(() => _migrateLegacyClipboardFile(args));
      }

      // Keep the legacy files until the user clears clipboard history. This is
      // deliberate: a pre-existing v2 target is not proof that every legacy
      // line was migrated successfully, and deleting the source would make a
      // corrupt or interrupted conversion irreversible.
    } catch (error) {
      _log('ClipboardHistory: legacy migration failed $error');
    }
  }

  static Future<void> _deleteFile(String path) async {
    if (path.isEmpty) return;
    try {
      final File file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static Future<void> _deleteDirectoryFiles(String path) async {
    if (path.isEmpty) return;
    try {
      final Directory directory = Directory(path);
      if (!await directory.exists()) return;
      await for (final FileSystemEntity entity in directory.list()) {
        if (entity is File) await entity.delete();
      }
    } catch (_) {}
  }

  static bool? _readPersistedBool(String key) {
    final dynamic value = _readPersistedValue(key);
    return value is bool ? value : null;
  }

  static int? _readPersistedInt(String key) {
    final dynamic value = _readPersistedValue(key);
    return value is num ? value.toInt() : int.tryParse('$value');
  }

  static dynamic _readPersistedValue(String key) {
    try {
      final File file = File(AppPaths.settingsPath('settings.json'));
      if (!file.existsSync()) return null;
      final dynamic decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map<dynamic, dynamic>) return null;
      return decoded['flutter.$key'] ?? decoded[key];
    } catch (_) {
      return null;
    }
  }

  static void _log(String message) {
    // Keep the history model independent from the Windows settings/debug graph.
    print(message);
  }

  static void resetForTesting() {
    _recordQueue = Future<void>.value();
    _migrationFuture = null;
    _recentCache.clear();
    _recentCacheLoaded = false;
    _fallbackEnabled = true;
    _fallbackCacheDays = defaultCacheDays;
  }
}

/// Migrate one legacy inline NDJSON file away from the Flutter isolate. The
/// source is intentionally retained after migration, so an interrupted or
/// lossy conversion can never destroy the old record automatically.
Future<void> _migrateLegacyClipboardFile(List<String> args) async {
  final String sourcePath = args[0];
  final String targetPath = args[1];
  final String payloadDirectoryPath = args[2];
  final File source = File(sourcePath);
  if (!await source.exists() || await File(targetPath).exists()) return;

  await Directory(payloadDirectoryPath).create(recursive: true);
  final File temporaryTarget = File('$targetPath.part');
  if (await temporaryTarget.exists()) await temporaryTarget.delete();
  final IOSink output = temporaryTarget.openWrite();
  bool committed = false;
  try {
    await for (final String line in source.openRead().transform(utf8.decoder).transform(const LineSplitter())) {
      final String trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      try {
        final dynamic decoded = jsonDecode(trimmed);
        if (decoded is! Map) continue;
        final Map<String, dynamic> map = Map<String, dynamic>.from(decoded);
        if (map['schema'] == _clipboardHistorySchemaVersion || map['textPath'] != null || map['htmlPath'] != null) {
          output.writeln(jsonEncode(map));
          continue;
        }

        final String id =
            _mapString(map, 'id').isEmpty ? DateTime.now().microsecondsSinceEpoch.toString() : _mapString(map, 'id');
        final String type = _mapString(map, 'type').isEmpty ? ClipboardHistoryType.text.name : _mapString(map, 'type');
        final String text = _mapString(map, 'text');
        final String html = _mapString(map, 'html');
        final String textPath = text.isEmpty ? '' : p.join('clipboard_payloads', '$id.txt');
        final String htmlPath = html.isEmpty ? '' : p.join('clipboard_payloads', '$id.html');

        if (text.isNotEmpty) {
          await File(p.join(payloadDirectoryPath, '$id.txt')).writeAsString(text, flush: true);
        }
        if (html.isNotEmpty) {
          await File(p.join(payloadDirectoryPath, '$id.html')).writeAsString(html, flush: true);
        }

        String hash = _mapString(map, 'contentHash');
        if (hash.isEmpty) {
          if (type == ClipboardHistoryType.image.name && text.startsWith('img-bytes:')) {
            hash = text;
          } else {
            hash = _contentHashForMigration(text, html);
          }
        }

        final Map<String, dynamic> migrated = <String, dynamic>{
          'schema': _clipboardHistorySchemaVersion,
          'id': id,
          'type': type,
          'createdAt': _mapString(map, 'createdAt'),
          'text': _clipboardPreview(text),
          'html': _clipboardPreview(html),
          'imagePath': _mapString(map, 'imagePath'),
          if (textPath.isNotEmpty) 'textPath': textPath,
          if (htmlPath.isNotEmpty) 'htmlPath': htmlPath,
          if (hash.isNotEmpty) 'contentHash': hash,
          'byteLength': _mapInt(map, 'byteLength', utf8.encode(text + html).length),
          'pinned': map['pinned'] == true,
          'textLength': _mapInt(map, 'textLength', text.length),
          'htmlLength': _mapInt(map, 'htmlLength', html.length),
        };
        output.writeln(jsonEncode(migrated));
      } catch (_) {}
    }
    await output.close();
    await temporaryTarget.rename(targetPath);
    committed = true;
  } catch (_) {
    await output.close();
    rethrow;
  } finally {
    if (!committed && await temporaryTarget.exists()) {
      try {
        await temporaryTarget.delete();
      } catch (_) {}
    }
  }
}

String _contentHashForMigration(String text, String html) {
  return md5.convert(utf8.encode('text:$text\nhtml:$html')).toString();
}
