import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:audiotags/audiotags.dart';

import '../models/db/music_library_db.dart';
import 'music_artwork_cache.dart';

class MusicIndexResult {
  const MusicIndexResult({
    required this.indexedCount,
    required this.skippedCount,
  });

  final int indexedCount;
  final int skippedCount;
}

abstract class MusicMetadataReader {
  Future<LocalMusicMetadata> read(File file, {required String rootPath});
}

class AudioTagsMusicMetadataReader implements MusicMetadataReader {
  AudioTagsMusicMetadataReader({MusicArtworkCache? artworkCache})
      : _artworkCache = artworkCache ?? MusicArtworkCache.instance;

  final MusicArtworkCache _artworkCache;

  @override
  Future<LocalMusicMetadata> read(File file, {required String rootPath}) async {
    final FileStat stat = await file.stat();
    Tag? tag;
    try {
      tag = await AudioTags.read(file.path);
    } catch (e) {
      debugPrint('AudioTags metadata failed for ${file.path}: $e');
    }
    final MusicArtworkRecord? artwork = await _artworkCache.resolveForFile(
      audioFile: file,
      pictures: tag?.pictures,
    );
    return LocalMusicMetadata(
      path: file.path,
      rootPath: rootPath,
      parentPath: p.dirname(file.path),
      title: tag?.title?.trim().isNotEmpty == true ? tag!.title!.trim() : p.basenameWithoutExtension(file.path),
      artist: _blankToNull(tag?.trackArtist),
      album: _blankToNull(tag?.album),
      genre: _blankToNull(tag?.genre),
      year: tag?.year,
      trackIndex: tag?.trackNumber,
      trackCount: tag?.trackTotal,
      discIndex: tag?.discNumber,
      discCount: tag?.discTotal,
      durationSeconds: tag?.duration,
      artworkHash: artwork?.artworkHash,
      artworkSmallPath: artwork?.smallPath,
      artworkLargePath: artwork?.largePath,
      artworkSourcePath: artwork?.sourcePath,
      artworkSourceModifiedMillis: artwork?.sourceModifiedMillis,
      fileSize: stat.size,
      modifiedMillis: stat.modified.millisecondsSinceEpoch,
    );
  }

  static String? _blankToNull(String? value) {
    if (value == null) return null;
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

class MusicLocalIndexer {
  MusicLocalIndexer({
    MusicLibraryDb? db,
    MusicMetadataReader? metadataReader,
  })  : _db = db ?? MusicLibraryDb.instance,
        _metadataReader = metadataReader ?? AudioTagsMusicMetadataReader();

  static final MusicLocalIndexer instance = MusicLocalIndexer();

  static const Set<String> supportedExtensions = <String>{
    '.mp3',
    '.flac',
    '.m4a',
    '.mp4',
  };

  /// Time-box reading a single file so one corrupt/locked track can never hang
  /// the whole indexer (which previously looked like a permanent freeze at 0).
  static const Duration perFileTimeout = Duration(seconds: 30);

  /// Hand the event loop a chance to paint/handle input every N files so the UI
  /// (and the rest of the desktop) stays responsive during a large index.
  static const int yieldEveryFiles = 8;

  /// Hard ceiling on files visited per scope. Guards against runaway traversal
  /// from junctions/symlink loops or an accidentally huge root (e.g. C:\).
  static const int maxFilesPerScope = 100000;

  final MusicLibraryDb _db;
  final MusicMetadataReader _metadataReader;

  bool _isIndexing = false;
  bool get isIndexing => _isIndexing;

  final ValueNotifier<int> indexedCount = ValueNotifier<int>(0);
  final ValueNotifier<bool> isIndexingNotifier = ValueNotifier<bool>(false);

  Future<MusicIndexResult> reindexAll() async {
    if (_isIndexing) return MusicIndexResult(indexedCount: indexedCount.value, skippedCount: 0);
    _beginIndexing();
    int skippedCount = 0;
    try {
      final List<MusicRoot> roots = await _db.getRoots();
      int totalIndexed = 0;
      for (final MusicRoot root in roots) {
        final MusicIndexResult result = await _indexScope(rootPath: root.path, scopePath: root.path);
        totalIndexed += result.indexedCount;
        skippedCount += result.skippedCount;
      }
      return MusicIndexResult(indexedCount: totalIndexed, skippedCount: skippedCount);
    } finally {
      _finishIndexing();
    }
  }

  Future<MusicIndexResult> reindexFolder(String folderPath) async {
    if (_isIndexing) return MusicIndexResult(indexedCount: indexedCount.value, skippedCount: 0);
    _beginIndexing();
    try {
      final MusicRoot? root = await _findRootForPath(folderPath);
      if (root == null) return const MusicIndexResult(indexedCount: 0, skippedCount: 0);
      return await _indexScope(rootPath: root.path, scopePath: folderPath);
    } finally {
      _finishIndexing();
    }
  }

  Future<MusicIndexResult> _indexScope({
    required String rootPath,
    required String scopePath,
  }) async {
    final Directory scope = Directory(scopePath);
    if (!await scope.exists()) return const MusicIndexResult(indexedCount: 0, skippedCount: 0);

    final String indexToken = DateTime.now().microsecondsSinceEpoch.toString();
    int indexed = 0;
    int skipped = 0;
    int processed = 0;

    // Phase 1: collect all metadata outside any transaction so that
    // artwork DB writes (upsertArtworkRecord) on the same connection
    // don't execute inside an open transaction.
    //
    // This is the heavy phase (tag reads + artwork decoding), so it: updates
    // live progress per file (instead of sitting at 0 until phase 2), yields to
    // the event loop periodically, time-boxes each file, tolerates listing
    // errors (e.g. permission-denied subfolders) instead of aborting the whole
    // scan, and caps total files to avoid runaway traversal.
    final List<LocalMusicMetadata> collected = <LocalMusicMetadata>[];
    final Stream<FileSystemEntity> entities =
        scope.list(recursive: true, followLinks: false).handleError((Object error) {
      debugPrint('MusicLocalIndexer: directory listing error under $scopePath: $error');
    });
    await for (final FileSystemEntity entity in entities) {
      if (entity is! File || !isSupportedAudioFile(entity.path)) continue;

      if (processed >= maxFilesPerScope) {
        debugPrint('MusicLocalIndexer: reached $maxFilesPerScope file cap for $scopePath; stopping scan.');
        break;
      }

      File fileToProcess = entity;
      final String oldPath = fileToProcess.path;
      final String dir = p.dirname(oldPath);
      final String base = p.basename(oldPath);
      final String ext = p.extension(oldPath);
      final String name = p.basenameWithoutExtension(oldPath);

      final String sanitizedName = MusicLibraryDb.sanitize(name);
      final String newBase = '$sanitizedName$ext';

      if (base != newBase) {
        final String newPath = p.join(dir, newBase);
        try {
          if (!File(newPath).existsSync()) {
            fileToProcess = await fileToProcess.rename(newPath);
          } else {
            debugPrint('MusicLocalIndexer: rename skipped, destination already exists: $newPath');
          }
        } catch (e) {
          debugPrint('MusicLocalIndexer: rename failed for $oldPath: $e');
        }
      }

      try {
        final LocalMusicMetadata metadata =
            await _metadataReader.read(fileToProcess, rootPath: rootPath).timeout(perFileTimeout);
        collected.add(metadata);
      } on TimeoutException {
        skipped++;
        debugPrint('MusicLocalIndexer: timed out reading ${fileToProcess.path}; skipped.');
      } catch (e) {
        skipped++;
        debugPrint('MusicLocalIndexer: skipped ${fileToProcess.path}: $e');
      }

      processed++;
      indexedCount.value++; // live progress while scanning (the slow phase)
      if (processed % yieldEveryFiles == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    // Phase 2: write all collected metadata in a single transaction.
    final Database database = await _db.database;
    database.execute('BEGIN TRANSACTION');
    try {
      for (final LocalMusicMetadata metadata in collected) {
        try {
          await _db.upsertSong(metadata, indexToken);
          indexed++;
        } catch (e) {
          skipped++;
          debugPrint('MusicLocalIndexer: upsert failed for ${metadata.path}: $e');
        }
      }
      await _db.deleteSongsNotIndexedInScope(rootPath: rootPath, scopePath: scopePath, indexToken: indexToken);
      database.execute('COMMIT');
    } catch (e) {
      try {
        database.execute('ROLLBACK');
      } catch (_) {}
      rethrow;
    }

    return MusicIndexResult(indexedCount: indexed, skippedCount: skipped);
  }

  Future<MusicRoot?> _findRootForPath(String folderPath) async {
    final String normalizedFolder = MusicLibraryDb.normalizePath(folderPath);
    final List<MusicRoot> roots = await _db.getRoots();
    MusicRoot? bestMatch;
    for (final MusicRoot root in roots) {
      final String normalizedRoot = MusicLibraryDb.normalizePath(root.path);
      final bool matches = normalizedFolder == normalizedRoot || normalizedFolder.startsWith('$normalizedRoot\\');
      if (!matches) continue;
      if (bestMatch == null || root.path.length > bestMatch.path.length) bestMatch = root;
    }
    return bestMatch;
  }

  static bool isSupportedAudioFile(String path) {
    return supportedExtensions.contains(p.extension(path).toLowerCase());
  }

  void _beginIndexing() {
    _isIndexing = true;
    indexedCount.value = 0;
    isIndexingNotifier.value = true;
  }

  void _finishIndexing() {
    _isIndexing = false;
    isIndexingNotifier.value = false;
  }
}
