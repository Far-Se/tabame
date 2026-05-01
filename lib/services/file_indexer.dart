import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tabamewin32/tabamewin32.dart';

import '../models/classes/boxes.dart';
import '../models/db/file_index_db.dart';

class FileIndexer {
  static final FileIndexer instance = FileIndexer._();
  FileIndexer._();

  bool _isIndexing = false;
  bool get isIndexing => _isIndexing;

  final ValueNotifier<int> indexedCount = ValueNotifier<int>(0);
  final ValueNotifier<bool> isIndexingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isCompletedNotifier = ValueNotifier<bool>(false);

  /// Initializes the watchlist with current search folders.
  Future<void> init() async {
    final List<String> paths = Boxes.searchFolders.map((SearchFolder f) => f.path).toList();
    if (paths.isNotEmpty) {
      await FolderWatch.buildInitialState(paths);
    }
  }

  /// Synchronizes the database with the filesystem by checking for changes.
  Future<void> sync() async {
    if (_isIndexing) return;
    _isIndexing = true;
    isIndexingNotifier.value = true;
    isCompletedNotifier.value = false;
    indexedCount.value = 0;

    try {
      // Ensure DB is initialized
      await FileIndexDb.instance.database;

      // 1. Cleanup orphaned roots (folders removed from settings)
      final List<SearchFolder> allRootsConfig = Boxes.searchFolders;

      // This is a bit expensive if done every time, but necessary if we want to keep DB clean
      // For now, let's just trust removeFolder is called from UI,
      // but sync() should also do a sanity check occasionally.

      // 2. Index changed or missing folders
      final List<String> changedFolders = await FolderWatch.getChangedFolders();

      for (final SearchFolder config in allRootsConfig) {
        final int? existingRootId = FileIndexDb.instance.findNode(null, config.path);
        if (existingRootId == null || changedFolders.contains(config.path)) {
          await _indexFolder(config);
        }
      }
    } catch (e) {
      debugPrint('Error during file sync: $e');
    } finally {
      _isIndexing = false;
      isCompletedNotifier.value = true;
      Database db = await FileIndexDb.instance.database;
      db.execute('PRAGMA shrink_memory;'); // Releases the page cache back to OS
      // Wait 5 seconds before hiding progress
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
      await FileIndexDb.instance.database;
      await _indexFolder(folder);
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
      Database db = await FileIndexDb.instance.database;
      try {
        db.execute('DELETE FROM nodes');
      } catch (e) {
        if (e.toString().contains('malformed')) {
          debugPrint('FileIndexer: Malformed DB during fullReindex, repairing...');
          await FileIndexDb.instance.repair();
          db = await FileIndexDb.instance.database;
          // After repair, DB is already empty, no need to DELETE again
        } else {
          rethrow;
        }
      }

      for (final SearchFolder config in Boxes.searchFolders) {
        await _indexFolder(config);
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

  /// Removes a folder from the database index.
  Future<void> removeFolder(String path) async {
    await FileIndexDb.instance.database;
    final int? rootId = FileIndexDb.instance.findNode(null, path);
    if (rootId != null) {
      FileIndexDb.instance.deleteNode(rootId);
    }
  }

  Future<void> _indexFolder(SearchFolder config) async {
    final Directory dir = Directory(config.path);
    if (!await dir.exists()) return;

    final Database db = await FileIndexDb.instance.database;

    db.execute('BEGIN TRANSACTION');
    try {
      // Find or create root
      int? rootId = FileIndexDb.instance.findNode(null, config.path);
      if (rootId == null) {
        // Roots are always searchable if includeFolders is true
        rootId = FileIndexDb.instance.insertNode(null, config.path, true, isSearchable: config.includeFolders);
      } else {
        // Clear existing children to avoid duplicates and handle deletions
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
    // Fast basename for Windows paths
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
