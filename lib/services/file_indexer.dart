import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

import '../models/classes/boxes.dart';
import '../models/db/file_index_db.dart';

final class _FileTime extends Struct {
  @Uint32()
  external int dwLowDateTime;
  @Uint32()
  external int dwHighDateTime;
}

final class _Win32FileAttributeData extends Struct {
  @Uint32()
  external int dwFileAttributes;

  external _FileTime ftCreationTime;
  external _FileTime ftLastAccessTime;
  external _FileTime ftLastWriteTime;

  @Uint32()
  external int nFileSizeHigh;
  @Uint32()
  external int nFileSizeLow;
}

typedef _GetFileAttributesExNative = Int32 Function(
  Pointer<Utf16> lpFileName,
  Int32 fInfoLevelId,
  Pointer<_Win32FileAttributeData> lpFileInformation,
);
typedef _GetFileAttributesExDart = int Function(
  Pointer<Utf16> lpFileName,
  int fInfoLevelId,
  Pointer<_Win32FileAttributeData> lpFileInformation,
);

const int _kGetFileExInfoStandard = 0;

final _GetFileAttributesExDart _getFileAttributesEx = () {
  final DynamicLibrary kernel32 = DynamicLibrary.open('kernel32.dll');
  return kernel32
      .lookup<NativeFunction<_GetFileAttributesExNative>>('GetFileAttributesExW')
      .asFunction<_GetFileAttributesExDart>();
}();

int _getFolderLastWriteTimeMs(String path) {
  final Pointer<Utf16> pathPtr = path.toNativeUtf16();
  final Pointer<_Win32FileAttributeData> data = calloc<_Win32FileAttributeData>();
  try {
    final int result = _getFileAttributesEx(pathPtr, _kGetFileExInfoStandard, data);
    if (result == 0) return 0;

    final _FileTime ft = data.ref.ftLastWriteTime;
    final int ticks = (ft.dwHighDateTime << 32) | ft.dwLowDateTime;
    const int epochOffsetTicks = 116444736000000000;
    if (ticks < epochOffsetTicks) return 0;
    return (ticks - epochOffsetTicks) ~/ 10000;
  } finally {
    calloc.free(data);
    calloc.free(pathPtr);
  }
}

class FolderWatch {
  FolderWatch._();

  static Future<void> buildInitialState(List<String> paths) async {
    for (final String path in paths) {
      final int stored = FileIndexDb.instance.getFolderWatchTime(path);
      if (stored == 0) {
        final int now = _getFolderLastWriteTimeMs(path);
        FileIndexDb.instance.setFolderWatchTime(path, now);
      }
    }
  }

  static Future<List<String>> getChangedFolders() async {
    final Map<String, int> stored = FileIndexDb.instance.getAllFolderWatchTimes();
    final List<String> changed = <String>[];

    for (final MapEntry<String, int> entry in stored.entries) {
      final String path = entry.key;
      final int storedTime = entry.value;
      final int currentTime = _getFolderLastWriteTimeMs(path);

      if (currentTime != storedTime) {
        changed.add(path);
        FileIndexDb.instance.setFolderWatchTime(path, currentTime);
      }
    }

    return changed;
  }

  static void addFolders(List<String> paths) {
    for (final String path in paths) {
      final int stored = FileIndexDb.instance.getFolderWatchTime(path);
      if (stored == 0) {
        FileIndexDb.instance.setFolderWatchTime(path, _getFolderLastWriteTimeMs(path));
      }
    }
  }

  static void removeFolders(List<String> paths) {
    for (final String path in paths) {
      FileIndexDb.instance.deleteFolderWatch(path);
    }
  }

  static void markSynced(String path) {
    final int now = _getFolderLastWriteTimeMs(path);
    FileIndexDb.instance.setFolderWatchTime(path, now);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FileIndexer
// ─────────────────────────────────────────────────────────────────────────────

class FileIndexer {
  static final FileIndexer instance = FileIndexer._();
  FileIndexer._();

  bool _isIndexing = false;
  bool get isIndexing => _isIndexing;

  final ValueNotifier<int> indexedCount = ValueNotifier<int>(0);
  final ValueNotifier<bool> isIndexingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isCompletedNotifier = ValueNotifier<bool>(false);

  Future<Database> _ensureDb() async {
    try {
      final Database db = await FileIndexDb.instance.database;
      db.execute('SELECT 1');
      return db;
    } catch (_) {
      await FileIndexDb.instance.reopen();
      return FileIndexDb.instance.database;
    }
  }

  Future<void> init() async {
    final List<String> paths = Boxes.searchFolders.map((SearchFolder f) => f.path).toList();
    if (paths.isNotEmpty) {
      await _ensureDb();
      await FolderWatch.buildInitialState(paths);
    }
  }

  Future<void> sync() async {
    if (_isIndexing) return;
    _isIndexing = true;
    isIndexingNotifier.value = true;
    isCompletedNotifier.value = false;
    indexedCount.value = 0;

    try {
      await _ensureDb();

      final List<SearchFolder> allRootsConfig = Boxes.searchFolders;

      final List<String> changedFolders = await FolderWatch.getChangedFolders();

      for (final SearchFolder config in allRootsConfig) {
        final int? existingRootId = FileIndexDb.instance.findNode(null, config.path);
        if (existingRootId == null || changedFolders.contains(config.path)) {
          await _indexFolder(config);
          FolderWatch.markSynced(config.path);
        }
      }
    } catch (e) {
      debugPrint('Error during file sync: $e');
    } finally {
      _isIndexing = false;
      isCompletedNotifier.value = true;
      try {
        final Database db = await FileIndexDb.instance.database;
        db.execute('PRAGMA shrink_memory;');
      } catch (_) {}
      Future<void>.delayed(const Duration(seconds: 5), () {
        if (!_isIndexing) {
          isIndexingNotifier.value = false;
          isCompletedNotifier.value = false;
        }
      });
    }
  }

  /// Synchronizes a specific folder.
  Future<void> syncFolder(SearchFolder folder) async {
    if (_isIndexing) return;
    _isIndexing = true;
    isIndexingNotifier.value = true;
    isCompletedNotifier.value = false;
    indexedCount.value = 0;

    try {
      await _ensureDb();
      await _indexFolder(folder);
      FolderWatch.markSynced(folder.path);
    } finally {
      _isIndexing = false;
      isCompletedNotifier.value = true;
      Future<void>.delayed(const Duration(seconds: 5), () {
        if (!_isIndexing) {
          isIndexingNotifier.value = false;
          isCompletedNotifier.value = false;
        }
      });
    }
  }

  /// Full re-index of all configured folders.
  Future<void> fullReindex() async {
    if (_isIndexing) return;
    _isIndexing = true;
    isIndexingNotifier.value = true;
    isCompletedNotifier.value = false;
    indexedCount.value = 0;

    try {
      await _ensureDb();
      try {
        FileIndexDb.instance.deleteRootsByEntryType(SearchResultEntryType.file);
      } catch (e) {
        if (e.toString().contains('malformed')) {
          debugPrint('FileIndexer: Malformed DB during fullReindex, repairing...');
          await FileIndexDb.instance.repair();
          await FileIndexDb.instance.database;
          FileIndexDb.instance.deleteRootsByEntryType(SearchResultEntryType.file);
        } else {
          rethrow;
        }
      }

      for (final SearchFolder config in Boxes.searchFolders) {
        await _indexFolder(config);
        FolderWatch.markSynced(config.path);
      }
    } catch (e) {
      debugPrint('Error during full reindex: $e');
    } finally {
      _isIndexing = false;
      isCompletedNotifier.value = true;
      Future<void>.delayed(const Duration(seconds: 5), () {
        if (!_isIndexing) {
          isIndexingNotifier.value = false;
          isCompletedNotifier.value = false;
        }
      });
    }
  }

  /// Removes a folder from the index and from the watch table.
  Future<void> removeFolder(String path) async {
    await _ensureDb();
    final int? rootId = FileIndexDb.instance.findNode(null, path);
    if (rootId != null) {
      FileIndexDb.instance.deleteNode(rootId);
    }
    FolderWatch.removeFolders(<String>[path]);
  }

  Future<void> _indexFolder(SearchFolder config) async {
    final Directory dir = Directory(config.path);
    if (!await dir.exists()) return;

    final Database db = await _ensureDb();

    db.execute('BEGIN TRANSACTION');
    try {
      int? rootId = FileIndexDb.instance.findNode(null, config.path);
      if (rootId == null) {
        rootId = FileIndexDb.instance.insertNode(null, config.path, true, isSearchable: config.includeFolders);
      } else {
        FileIndexDb.instance.updateNodeSearchable(rootId, config.includeFolders);
        FileIndexDb.instance.deleteChildren(rootId);
      }

      await _crawl(
        dir,
        rootId,
        currentDepth: 1,
        config: config,
        allowedExtensions: _normalizedAllowedExtensions(config.allowedExtensions),
      );

      db.execute('COMMIT');
    } catch (e) {
      try {
        db.execute('ROLLBACK');
      } catch (_) {}
      debugPrint('Error indexing folder ${config.path}: $e');
    }
  }

  Future<int> _crawl(
    Directory dir,
    int parentId, {
    required int currentDepth,
    required SearchFolder config,
    required Set<String> allowedExtensions,
  }) async {
    if (config.maxDepth != null && currentDepth > config.maxDepth!) return 0;

    int indexedItems = 0;

    try {
      final List<FileSystemEntity> entities = await dir.list(recursive: false, followLinks: false).toList();
      for (final FileSystemEntity entity in entities) {
        final String name = _getBasename(entity.path);
        if (config.excludePath != null && RegExp(config.excludePath!, caseSensitive: false).hasMatch(entity.path)) {
          continue;
        }
        final bool isDir = entity is Directory;

        if (isDir) {
          final bool isSearchable = config.includeFolders;
          final int id = FileIndexDb.instance.insertNode(parentId, name, true, isSearchable: isSearchable);
          indexedCount.value++;

          final int childCount = await _crawl(
            entity,
            id,
            currentDepth: currentDepth + 1,
            config: config,
            allowedExtensions: allowedExtensions,
          );

          if (!isSearchable && childCount == 0) {
            FileIndexDb.instance.deleteNode(id);
            if (indexedCount.value > 0) indexedCount.value--;
            continue;
          }

          indexedItems += childCount + 1;
          continue;
        }

        if (!_shouldIndexFile(name, config.includeFiles, allowedExtensions)) {
          continue;
        }

        FileIndexDb.instance.insertNode(parentId, name, false);
        indexedCount.value++;
        indexedItems++;
      }
    } catch (e) {
      // debugPrint('Error indexing child items in ${dir.path}: $e');
    }

    return indexedItems;
  }

  Set<String> _normalizedAllowedExtensions(List<String> extensions) {
    return extensions
        .map((String extension) => extension.trim().toLowerCase())
        .where((String extension) => extension.isNotEmpty)
        .map((String extension) => extension.startsWith('.') ? extension : '.$extension')
        .toSet();
  }

  bool _shouldIndexFile(String name, bool includeFiles, Set<String> allowedExtensions) {
    if (!includeFiles) return false;
    if (allowedExtensions.isEmpty) return true;
    return allowedExtensions.contains(_getExtension(name).toLowerCase());
  }

  String _getBasename(String path) {
    final int index = path.lastIndexOf('\\');
    if (index == -1) return path;
    return path.substring(index + 1);
  }

  String _getExtension(String name) {
    final int index = name.lastIndexOf('.');
    if (index == -1 || index == 0) return '';
    return name.substring(index);
  }
}
