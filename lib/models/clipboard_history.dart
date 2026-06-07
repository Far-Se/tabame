import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:tabamewin32/tabamewin32.dart';

import 'classes/boxes.dart';
import 'settings.dart';
import 'win32/win_utils.dart';

enum ClipboardHistoryType {
  text,
  richText,
  image,
}

class ClipboardHistoryEntry {
  ClipboardHistoryEntry({
    required this.id,
    required this.type,
    required this.createdAt,
    this.text = '',
    this.html = '',
    this.imagePath = '',
    this.byteLength = 0,
    this.pinned = false,
    this.textLength,
    this.htmlLength,
  });

  final String id;
  final ClipboardHistoryType type;
  final DateTime createdAt;
  final String text;
  final String html;
  final String imagePath;
  final int byteLength;
  final bool pinned;
  final int? textLength; // total length of text
  final int? htmlLength; // total length of html

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'type': type.name,
      'createdAt': createdAt.toIso8601String(),
      'text': text,
      'html': html,
      'imagePath': imagePath,
      'byteLength': byteLength,
      'pinned': pinned,
      if (textLength != null) 'textLength': textLength,
      if (htmlLength != null) 'htmlLength': htmlLength,
    };
  }

  factory ClipboardHistoryEntry.fromMap(Map<String, dynamic> map, {bool truncate = false}) {
    String text = (map['text'] ?? '') as String;
    String html = (map['html'] ?? '') as String;
    int tLen = (map['textLength'] ?? text.length) as int;
    int hLen = (map['htmlLength'] ?? html.length) as int;

    if (truncate) {
      if (text.length > 40) text = text.substring(0, 40);
      if (html.length > 40) html = html.substring(0, 40);
    }

    return ClipboardHistoryEntry(
      id: (map['id'] ?? '') as String,
      type: ClipboardHistoryType.values.firstWhere(
        (ClipboardHistoryType type) => type.name == map['type'],
        orElse: () => ClipboardHistoryType.text,
      ),
      createdAt: DateTime.tryParse((map['createdAt'] ?? '') as String) ?? DateTime.fromMillisecondsSinceEpoch(0),
      text: text,
      html: html,
      imagePath: (map['imagePath'] ?? '') as String,
      byteLength: (map['byteLength'] ?? 0) as int,
      pinned: (map['pinned'] ?? false) as bool,
      textLength: tLen,
      htmlLength: hLen,
    );
  }

  ClipboardHistoryEntry copyWith({
    String? id,
    ClipboardHistoryType? type,
    DateTime? createdAt,
    String? text,
    String? html,
    String? imagePath,
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
  static const int _clipboardReadAttempts = 5;

  /// Maximum number of recent entries kept in memory for duplicate detection.
  static const int _recentCacheSize = 10;

  static bool _recording = false;

  /// In-memory ring of MD5 hashes of the most-recently recorded entries.
  /// Used only for duplicate detection — never exposed to the UI.
  /// Storing hashes instead of full entries keeps RAM usage negligible.
  static final List<String> _recentCache = <String>[];
  static bool _recentCacheLoaded = false;

  static bool get enabled => Boxes.pref.getBool(enabledKey) ?? true;
  static int get cacheDays => Boxes.pref.getInt(cacheDaysKey) ?? defaultCacheDays;

  static String get cacheDirectoryPath => '${WinUtils.getTabameAppDataFolder()}\\cache';
  static String get imageDirectoryPath => '$cacheDirectoryPath\\clipboard_images';
  static String get historyFilePath => '$cacheDirectoryPath\\clipboard.json';
  static String get pinnedFilePath => '$cacheDirectoryPath\\pinned_clipboard.json';

  static Future<void> setEnabled(bool value) async {
    await Boxes.updateSettings(enabledKey, value);
  }

  static Future<void> setCacheDays(int value) async {
    await Boxes.updateSettings(cacheDaysKey, value.clamp(1, 365));
    // Pruning is intentionally NOT done automatically here.
    // Call clearCache() explicitly when desired.
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Load pinned entries from disk.
  static Future<List<ClipboardHistoryEntry>> loadPinned() async {
    try {
      final File file = File(pinnedFilePath);
      if (!file.existsSync()) return <ClipboardHistoryEntry>[];
      final List<String> lines = await file.readAsLines();
      return lines
          .map((String line) {
            try {
              return ClipboardHistoryEntry.fromMap(jsonDecode(line) as Map<String, dynamic>, truncate: true);
            } catch (_) {
              return null;
            }
          })
          .whereType<ClipboardHistoryEntry>()
          .toList()
        ..sort((ClipboardHistoryEntry a, ClipboardHistoryEntry b) => b.createdAt.compareTo(a.createdAt));
    } catch (_) {
      return <ClipboardHistoryEntry>[];
    }
  }

  /// Load a paged slice of history from disk.
  static Future<List<ClipboardHistoryEntry>> loadPaged({
    int offset = 0,
    int limit = 30,
    String query = '',
  }) async {
    try {
      final File file = File(historyFilePath);
      if (!file.existsSync()) return <ClipboardHistoryEntry>[];

      final List<ClipboardHistoryEntry> entries = <ClipboardHistoryEntry>[];
      final List<String> lines = await file.readAsLines();
      final List<String> reversed = lines.reversed.toList();

      final String q = query.trim().toLowerCase();
      int skipCount = 0;

      for (final String line in reversed) {
        final String trimmed = line.trim();
        if (trimmed.isEmpty) continue;

        try {
          final Map<String, dynamic> map = jsonDecode(trimmed) as Map<String, dynamic>;
          // Simple search filter if query provided
          if (q.isNotEmpty) {
            final String text = (map['text'] ?? '').toString().toLowerCase();
            if (!text.contains(q)) continue;
          }

          // Apply offset before limit so we never exit early while still skipping.
          if (skipCount < offset) {
            skipCount++;
            continue;
          }

          if (entries.length >= limit) break;
          entries.add(ClipboardHistoryEntry.fromMap(map, truncate: true));
        } catch (_) {}
      }

      return entries;
    } catch (error) {
      Debug.print('ClipboardHistory: load failed $error');
      return <ClipboardHistoryEntry>[];
    }
  }

  /// Retrieve the full entry (non-truncated) by ID.
  static Future<ClipboardHistoryEntry?> getFullEntry(String id) async {
    // Check pinned first
    final File pinnedFile = File(pinnedFilePath);
    if (pinnedFile.existsSync()) {
      for (final String line in await pinnedFile.readAsLines()) {
        if (!line.startsWith('{')) continue;
        try {
          final Map<String, dynamic> map = jsonDecode(line) as Map<String, dynamic>;
          if (map['id'] == id) return ClipboardHistoryEntry.fromMap(map, truncate: false);
        } catch (x) {
          print(x);
        }
      }
    }

    // Then check history
    final File historyFile = File(historyFilePath);
    if (historyFile.existsSync()) {
      for (final String line in await historyFile.readAsLines()) {
        if (!line.startsWith('{')) continue;
        try {
          final Map<String, dynamic> map = jsonDecode(line) as Map<String, dynamic>;
          if (map['id'] == id) return ClipboardHistoryEntry.fromMap(map, truncate: false);
        } catch (x) {
          print(x);
        }
      }
    }
    return null;
  }

  @Deprecated("Use loadPaged or loadPinned instead")
  static Future<List<ClipboardHistoryEntry>> load() async => loadPaged(limit: 99999);

  /// Load ALL history entries from disk without any truncation.
  /// Must be used whenever entries will be rewritten back to disk,
  /// to avoid permanently losing content that exceeds the display limit.
  static Future<List<ClipboardHistoryEntry>> _loadAllFull() async {
    try {
      final File file = File(historyFilePath);
      if (!file.existsSync()) return <ClipboardHistoryEntry>[];
      final List<String> lines = await file.readAsLines();
      final List<ClipboardHistoryEntry> entries = <ClipboardHistoryEntry>[];
      for (final String line in lines) {
        final String trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        try {
          entries.add(
            ClipboardHistoryEntry.fromMap(
              jsonDecode(trimmed) as Map<String, dynamic>,
              truncate: false,
            ),
          );
        } catch (_) {}
      }
      return entries;
    } catch (error) {
      Debug.print('ClipboardHistory: _loadAllFull failed $error');
      return <ClipboardHistoryEntry>[];
    }
  }

  /// Load ALL pinned entries from disk without any truncation.
  static Future<List<ClipboardHistoryEntry>> _loadPinnedFull() async {
    try {
      final File file = File(pinnedFilePath);
      if (!file.existsSync()) return <ClipboardHistoryEntry>[];
      final List<String> lines = await file.readAsLines();
      final List<ClipboardHistoryEntry> entries = <ClipboardHistoryEntry>[];
      for (final String line in lines) {
        final String trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        try {
          entries.add(
            ClipboardHistoryEntry.fromMap(
              jsonDecode(trimmed) as Map<String, dynamic>,
              truncate: false,
            ),
          );
        } catch (_) {}
      }
      return entries;
    } catch (error) {
      Debug.print('ClipboardHistory: _loadPinnedFull failed $error');
      return <ClipboardHistoryEntry>[];
    }
  }

  /// Record the current clipboard contents.
  ///
  /// - Reads the clipboard once.
  /// - Checks the last [_recentCacheSize] items for duplicates.
  /// - If not a duplicate, appends a single JSON line to [historyFilePath].
  /// - Images are saved to [imageDirectoryPath].
  static Future<void> recordCurrentClipboard() async {
    if (!enabled || _recording) return;
    _recording = true;
    try {
      ClipboardHistoryEntry? entry = await _readImage();
      entry ??= await _readImageFromRichText();
      entry ??= await _readTextOrRichText();
      if (entry == null) return;

      // Lazy-load the recent cache from disk (only the first time).
      await _ensureRecentCacheLoaded();

      // Duplicate check against the recent in-memory window.
      final String entryHash = _contentHash(entry);
      final bool isDuplicate = _recentCache.contains(entryHash);
      if (isDuplicate) return;

      // Update lengths before appending
      final ClipboardHistoryEntry entryWithLengths = entry.copyWith(
        textLength: entry.text.length,
        htmlLength: entry.html.length,
      );

      // Append one NDJSON line — no full file read/write needed.
      await _appendEntry(entryWithLengths);

      // Update in-memory recent cache with the hash only.
      _recentCache.insert(0, entryHash);
      if (_recentCache.length > _recentCacheSize) {
        _recentCache.removeLast();
      }
    } catch (error) {
      Debug.print('ClipboardHistory: record failed $error');
    } finally {
      _recording = false;
    }
  }

  /// Prune entries older than [cacheDays] from disk and delete orphaned/expired images.
  ///
  /// Call this when the user explicitly requests it (e.g. "Prune History" button).
  static Future<void> clearCache() async {
    try {
      final List<ClipboardHistoryEntry> all = await _loadAllFull();
      final DateTime cutoff = DateTime.now().subtract(Duration(days: cacheDays));

      final List<ClipboardHistoryEntry> keptHistory =
          all.where((ClipboardHistoryEntry e) => e.createdAt.isAfter(cutoff)).toList();
      final List<ClipboardHistoryEntry> pinned = await _loadPinnedFull();

      // Rewrite the history file with only the kept entries.
      await _rewriteFile(keptHistory, historyFilePath);

      // Delete orphaned images and images older than cacheDays (unless pinned).
      _pruneImages(<ClipboardHistoryEntry>[...keptHistory, ...pinned], cutoff);

      // Rebuild in-memory cache from the survivors (hashes only).
      _recentCache
        ..clear()
        ..addAll(keptHistory.take(_recentCacheSize).map(_contentHash));
    } catch (error) {
      Debug.print('ClipboardHistory: clearCache failed $error');
    }
  }

  /// Copy a clipboard entry back to the system clipboard.
  static Future<void> copyEntry(ClipboardHistoryEntry entry) async {
    // Fetch full content if truncated
    ClipboardHistoryEntry? fullEntry = entry;
    if ((entry.textLength != null && entry.text.length < entry.textLength!) ||
        (entry.htmlLength != null && entry.html.length < entry.htmlLength!)) {
      fullEntry = await getFullEntry(entry.id);
    }
    if (fullEntry == null) return;
    if (fullEntry.type == ClipboardHistoryType.image) {
      final File file = File(fullEntry.imagePath);
      if (file.existsSync()) {
        await ClipboardExtended.copyImage(await file.readAsBytes());
      }
      return;
    }
    if (fullEntry.html.isNotEmpty) {
      await ClipboardExtended.copyRichText(text: fullEntry.text, html: _htmlFragment(fullEntry.html));
      return;
    }
    await ClipboardExtended.copy(fullEntry.text);
  }

  /// Remove a single entry from disk.
  static Future<void> remove(ClipboardHistoryEntry entry) async {
    final List<ClipboardHistoryEntry> all = await _loadAllFull();
    final List<ClipboardHistoryEntry> next = all.where((ClipboardHistoryEntry item) => item.id != entry.id).toList();
    await _rewriteFile(next, historyFilePath);

    final List<ClipboardHistoryEntry> pinned = await _loadPinnedFull();
    if (pinned.any((ClipboardHistoryEntry e) => e.id == entry.id)) {
      final List<ClipboardHistoryEntry> nextPinned =
          pinned.where((ClipboardHistoryEntry item) => item.id != entry.id).toList();
      await _rewriteFile(nextPinned, pinnedFilePath);
    }

    // Delete associated image file.
    if (entry.imagePath.isNotEmpty) {
      final File image = File(entry.imagePath);
      if (image.existsSync()) image.deleteSync();
    }

    // Sync recent cache — evict by hash.
    _recentCache.remove(_contentHash(entry));
  }

  /// Toggle the pinned state of an entry.
  static Future<void> setPinned(ClipboardHistoryEntry entry, bool pinned) async {
    // 1. Get full entry
    final ClipboardHistoryEntry? full = await getFullEntry(entry.id);
    if (full == null) return;

    // 2. Remove from both files
    final List<ClipboardHistoryEntry> allPinned = await _loadPinnedFull();
    final List<ClipboardHistoryEntry> allHistory = await _loadAllFull();

    final List<ClipboardHistoryEntry> nextPinned =
        allPinned.where((ClipboardHistoryEntry item) => item.id != entry.id).toList();
    final List<ClipboardHistoryEntry> nextHistory =
        allHistory.where((ClipboardHistoryEntry item) => item.id != entry.id).toList();

    // 3. Add to the target file
    final ClipboardHistoryEntry updated = full.copyWith(pinned: pinned);
    if (pinned) {
      nextPinned.insert(0, updated);
    } else {
      nextHistory.insert(0, updated);
    }

    // 4. Save both
    await _rewriteFile(nextHistory, historyFilePath);
    await _rewriteFile(nextPinned, pinnedFilePath);

    // Sync recent cache — replace old hash with updated hash (pinned flag is part of hash input? No —
    // pinned is not content, so the hash stays the same. Nothing to do here.
  }

  /// Delete ALL history and images.
  static Future<void> clear() async {
    await _rewriteFile(<ClipboardHistoryEntry>[], historyFilePath);
    await _rewriteFile(<ClipboardHistoryEntry>[], pinnedFilePath);
    _recentCache.clear();
    _recentCacheLoaded = false;

    final Directory imageDir = Directory(imageDirectoryPath);
    if (imageDir.existsSync()) {
      for (final FileSystemEntity entity in imageDir.listSync()) {
        if (entity is File) {
          try {
            entity.deleteSync();
          } catch (_) {}
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Lazily populate [_recentCache] from disk (last [_recentCacheSize] entries).
  static Future<void> _ensureRecentCacheLoaded() async {
    if (_recentCacheLoaded) return;
    _recentCacheLoaded = true;
    try {
      final List<ClipboardHistoryEntry> all = await _loadAllFull();
      _recentCache
        ..clear()
        ..addAll(all.take(_recentCacheSize).map(_contentHash));
    } catch (_) {}
  }

  /// Append a single entry as one NDJSON line to [historyFilePath].
  static Future<void> _appendEntry(ClipboardHistoryEntry entry) async {
    final Directory cacheDir = Directory(cacheDirectoryPath);
    if (!cacheDir.existsSync()) {
      cacheDir.createSync(recursive: true);
    }

    final File file = File(historyFilePath);
    final String line = '\n${jsonEncode(entry.toMap())}';
    await file.writeAsString(line, mode: FileMode.append);
  }

  /// Rewrite the entire file (used after edits/pruning).
  static Future<void> _rewriteFile(List<ClipboardHistoryEntry> entries, [String? path]) async {
    final Directory cacheDir = Directory(cacheDirectoryPath);
    if (!cacheDir.existsSync()) cacheDir.createSync(recursive: true);

    final File file = File(path ?? historyFilePath);
    final StringBuffer buffer = StringBuffer();

    for (final ClipboardHistoryEntry entry in entries) {
      buffer.writeln(jsonEncode(entry.toMap()));
    }
    await file.writeAsString(buffer.toString(), flush: true);
  }

  /// Delete image files that are not referenced by [kept] entries OR are older than [cutoff] (and not pinned).
  static void _pruneImages(List<ClipboardHistoryEntry> kept, DateTime cutoff) {
    final Map<String, bool> activeImagePinned = <String, bool>{};
    for (final ClipboardHistoryEntry e in kept) {
      if (e.imagePath.isNotEmpty) {
        final String path = _normalizedPath(e.imagePath);
        activeImagePinned[path] = (activeImagePinned[path] ?? false) || e.pinned;
      }
    }

    final Directory imageDir = Directory(imageDirectoryPath);
    if (!imageDir.existsSync()) return;

    for (final FileSystemEntity entity in imageDir.listSync()) {
      if (entity is! File) continue;
      final String normPath = _normalizedPath(entity.path);
      final bool isReferenced = activeImagePinned.containsKey(normPath);
      final bool isPinned = activeImagePinned[normPath] ?? false;

      if (!isReferenced) {
        try {
          entity.deleteSync();
        } catch (_) {}
        continue;
      }

      if (isPinned) continue;

      // For non-pinned referenced images, check age
      try {
        final DateTime modified = entity.statSync().modified;
        if (modified.isBefore(cutoff)) {
          entity.deleteSync();
        }
      } catch (_) {}
    }
  }

  static String _normalizedPath(String path) => File(path).absolute.path.toLowerCase();

  static Future<ClipboardHistoryEntry?> _readTextOrRichText() async {
    final Map<String, dynamic>? data = await _tryClipboardRead<Map<String, dynamic>?>(
      'rich text',
      () => ClipboardExtended.pasteRichText(),
    );
    if (data == null) return null;

    final String text = (data['text'] as String?)?.trim() ?? '';
    final String html = _htmlFragment((data['html'] as String?)?.trim() ?? '');
    if (text.isEmpty && html.isEmpty) return null;

    final DateTime now = DateTime.now();
    return ClipboardHistoryEntry(
      id: _entryId(now),
      type: html.isEmpty ? ClipboardHistoryType.text : ClipboardHistoryType.richText,
      createdAt: now,
      text: text,
      html: html,
      byteLength: utf8.encode(text + html).length,
    );
  }

  static Future<ClipboardHistoryEntry?> _readImageFromRichText() async {
    final Map<String, dynamic>? data = await _tryClipboardRead<Map<String, dynamic>?>(
      'rich text image',
      () => ClipboardExtended.pasteRichText(),
    );
    if (data == null) return null;

    final String html = _htmlFragment((data['html'] as String?)?.trim() ?? '');
    if (html.isEmpty) return null;

    final Uint8List? bytes = _extractEmbeddedImageBytes(html);
    if (bytes == null || bytes.isEmpty) return null;

    return _saveImageEntry(bytes);
  }

  static Future<ClipboardHistoryEntry?> _readImage() async {
    final Uint8List? bytes = await _tryClipboardRead<Uint8List?>(
      'image',
      () => ClipboardExtended.pasteImage(),
    );
    if (bytes == null || bytes.isEmpty) return null;

    return _saveImageEntry(bytes);
  }

  static Future<ClipboardHistoryEntry?> _saveImageEntry(Uint8List bytes) async {
    final DateTime now = DateTime.now();
    final String id = _entryId(now);
    final Directory imageDir = Directory(imageDirectoryPath);
    if (!imageDir.existsSync()) imageDir.createSync(recursive: true);
    final String imagePath = '${imageDir.path}\\$id.png';
    final File imageFile = File(imagePath);
    await imageFile.writeAsBytes(bytes, flush: true);
    if (!imageFile.existsSync()) return null;

    // Embed the bytes-hash in the `text` field so that _contentHash can use it
    // for duplicate detection without needing to re-read the file from disk.
    // The field is otherwise empty for image entries, so this is safe.
    final String bytesHash = _contentHashFromBytes(bytes);

    return ClipboardHistoryEntry(
      id: id,
      type: ClipboardHistoryType.image,
      createdAt: now,
      imagePath: imagePath,
      byteLength: bytes.length,
      text: bytesHash, // used only for dedup; not shown in UI
    );
  }

  static Uint8List? _extractEmbeddedImageBytes(String html) {
    final RegExp imgSrcPattern = RegExp(
      r"""<img\b[^>]*\bsrc\s*=\s*(["'])(.*?)\1""",
      caseSensitive: false,
      dotAll: true,
    );

    for (final RegExpMatch match in imgSrcPattern.allMatches(html)) {
      final String src = (match.group(2) ?? '').trim();
      final Uint8List? bytes = _decodeImageDataUri(src);
      if (bytes != null && bytes.isNotEmpty) return bytes;
    }

    return _decodeImageDataUri(html.trim());
  }

  static Uint8List? _decodeImageDataUri(String value) {
    final RegExpMatch? match = RegExp(
      r'^data:image\/[-+.a-zA-Z0-9]+;base64,([a-zA-Z0-9+/=\s]+)$',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(value);
    if (match == null) return null;

    final String payload = (match.group(1) ?? '').replaceAll(RegExp(r'\s+'), '');
    if (payload.isEmpty) return null;

    try {
      return base64Decode(payload);
    } catch (_) {
      return null;
    }
  }

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
      } on PlatformException catch (error) {
        final bool clipboardBusy = error.message?.contains('open clipboard') ?? false;
        final bool noImage = error.code == 'PASTE_IMAGE_ERROR';
        if (noImage) return null;
        if (!clipboardBusy || attempt == _clipboardReadAttempts - 1) {
          Debug.print('ClipboardHistory: $label read failed ${error.code}: ${error.message}');
          return null;
        }
      } catch (error) {
        Debug.print('ClipboardHistory: $label read failed $error');
        return null;
      }

      await Future<void>.delayed(Duration(milliseconds: 40 + (attempt * 35)));
    }
    return null;
  }

  /// Returns an MD5 hex digest that uniquely identifies the *content* of [entry].
  ///
  /// - Text / rich-text: MD5 of `"text:<text>\nhtml:<html>"` encoded as UTF-8.
  ///   Both fields are included so that the same plain text with different HTML
  ///   formatting is treated as a distinct entry.
  /// - Image: if [entry.text] contains the bytes-hash written by [_saveImageEntry],
  ///   that value is returned directly (it is already a unique content fingerprint).
  ///   Otherwise falls back to `"image:<byteLength>:<imagePath>"`.
  static String _contentHash(ClipboardHistoryEntry entry) {
    if (entry.type == ClipboardHistoryType.image) {
      // _saveImageEntry stores the MD5-of-bytes in the text field.
      if (entry.text.startsWith('img-bytes:')) return entry.text;
      return md5.convert(utf8.encode('image:${entry.byteLength}:${entry.imagePath}')).toString();
    }
    return md5.convert(utf8.encode('text:${entry.text}\nhtml:${entry.html}')).toString();
  }

  /// Compute a content hash directly from raw image [bytes].
  /// Use this inside [_saveImageEntry] so that two identical bitmaps
  /// that arrive at different timestamps still produce the same hash.
  static String _contentHashFromBytes(Uint8List bytes) {
    return 'img-bytes:${md5.convert(bytes)}';
  }

  static String _entryId(DateTime now) => now.microsecondsSinceEpoch.toString();
}
