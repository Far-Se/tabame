import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../models/classes/app_items.dart';
import '../../../models/classes/boxes.dart';
import '../../../models/classes/saved_maps.dart';
import '../../../models/db/file_index_db.dart';
import '../../../models/settings.dart';
import '../../../models/util/quickmenu_modal.dart';
import '../../../models/win32/window.dart';
import '../../../models/window_watcher.dart';
import '../../../widgets/itzy/quickmenu/button_quickactions.dart';
import '../../launcher/result/result_item_bookmark.dart';
import '../../launcher_search_models.dart';

const int maxLauncherMatches = 30;

List<LauncherSearchResultItem> composeResults({
  required List<QuickActionMenuEntry> quickActionMatches,
  required List<Window> windowMatches,
  required List<LauncherSearchResultItem> fileMatches,
  required List<BookmarkSearchResult> bookmarkMatches,
}) {
  final List<LauncherSearchResultItem> results = <LauncherSearchResultItem>[];

  results.addAll(quickActionMatches.map(LauncherSearchResultItem.quickAction));
  results.addAll(windowMatches.map(LauncherSearchResultItem.window));
  results.addAll(fileMatches);
  results.addAll(bookmarkMatches.map(LauncherSearchResultItem.bookmark));

  return results;
}

List<LauncherSearchResultItem> deserializeSearchMatches(List<SearchResultNode> matches) {
  return matches.map((SearchResultNode entry) {
    if (entry.isApp) {
      return LauncherSearchResultItem.app(
        LauncherAppResult(
          name: entry.name,
          launchTarget: entry.launchTarget ?? '',
          appUserModelId: entry.appUserModelId ?? '',
          parsingName: entry.parsingName ?? '',
          subtitle: entry.subtitle ?? '',
          stableIdentity: entry.stableIdentity ?? '',
        ),
        entry.id,
      );
    }

    final FileSystemEntity entity = entry.isDirectory ? Directory(entry.path) : File(entry.path);
    return LauncherSearchResultItem.file(entity, entry.id);
  }).toList(growable: false);
}

List<LauncherSearchResultItem> deserializeFileMatches(List<Map<String, Object?>> serializedMatches) {
  return serializedMatches.map((Map<String, Object?> entry) {
    final String path = entry['path']! as String;
    final bool isDirectory = entry['isDirectory']! as bool;
    final int? id = entry['id'] as int?;
    final FileSystemEntity entity = isDirectory ? Directory(path) : File(path);
    return LauncherSearchResultItem.file(entity, id);
  }).toList(growable: false);
}

List<BookmarkSearchResult> findBookmarkMatches(
  String query, {
  bool includeAllOnEmpty = false,
  Set<BookmarkResultKind>? kinds,
}) {
  if (query.isEmpty && !includeAllOnEmpty) return <BookmarkSearchResult>[];

  final String lowerQuery = query.toLowerCase();
  final List<BookmarkSearchResult> results = <BookmarkSearchResult>[];

  for (final BookmarkGroup g in Boxes().bookmarks) {
    for (final BookmarkInfo b in g.bookmarks) {
      if (kinds != null && !kinds.contains(BookmarkResultKind.bookmark)) continue;
      if (query.isEmpty || b.title.toLowerCase().contains(lowerQuery)) {
        results.add(BookmarkSearchResult.bookmark(b));
      }
    }
  }

  for (final CliBookCategory category in Boxes().cliBook) {
    for (final CliBookItem item in category.items) {
      if (kinds != null && !kinds.contains(BookmarkResultKind.cliBook)) continue;
      if (item.key.isEmpty) continue;
      if (query.isEmpty ||
          item.key.toLowerCase().contains(lowerQuery) ||
          item.value.toLowerCase().contains(lowerQuery)) {
        results.add(BookmarkSearchResult.cli(item));
      }
    }
  }

  for (final AppCategory category in Boxes.appCategories) {
    for (final AppItem app in category.items) {
      if (kinds != null && !kinds.contains(BookmarkResultKind.appItem)) continue;
      if (query.isEmpty || app.name.toLowerCase().contains(lowerQuery) || app.path.toLowerCase().contains(lowerQuery)) {
        results.add(BookmarkSearchResult.app(app));
      }
    }
  }

  return results;
}

List<QuickActionMenuEntry> findQuickActionMatches(
  BuildContext context,
  String query, {
  bool includeAllOnEmpty = false,
}) {
  final List<QuickActionMenuEntry> allEntries = buildQuickActionMenuEntries(
    context,
    onStateChanged: () {
      // We might need to handle this differently if we are outside the state
    },
  );

  if (query.isEmpty || query == ' ') {
    if (!includeAllOnEmpty) return <QuickActionMenuEntry>[];
    return allEntries;
  }

  final List<QuickActionMenuEntry> matches =
      allEntries.where((QuickActionMenuEntry entry) => entry.matches(query)).toList();

  matches.sort((QuickActionMenuEntry a, QuickActionMenuEntry b) {
    final int rank = quickActionMatchRank(a, query).compareTo(quickActionMatchRank(b, query));
    if (rank != 0) return rank;

    final int length = a.title.length.compareTo(b.title.length);
    if (length != 0) return length;

    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });

  return matches.take(5).toList();
}

List<Window> findWindowMatches(String query, {bool includeAllOnEmpty = false}) {
  final List<Window> windows = List<Window>.from(WindowWatcher.list);
  if (query.isEmpty) {
    if (!includeAllOnEmpty) return <Window>[];
    return windows;
  }

  // Normalise here so callers don't have to — guards against any call site
  // that passes a mixed-case query and would otherwise get zero matches.
  final String lowerQuery = query.toLowerCase();

  final List<Window> matches = windows.where((Window window) {
    final String title = window.title.toLowerCase();
    final String exe = window.process.exe.toLowerCase();
    final String path = window.process.exePath.toLowerCase();
    return title.contains(lowerQuery) || exe.contains(lowerQuery) || path.contains(lowerQuery);
  }).toList();

  matches.sort((Window a, Window b) {
    final int rank = windowMatchRank(a, lowerQuery).compareTo(windowMatchRank(b, lowerQuery));
    if (rank != 0) return rank;
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });
  return matches;
}

int quickActionMatchRank(QuickActionMenuEntry entry, String query) {
  final String title = entry.title.toLowerCase();
  if (title == query) return 0;
  if (title.startsWith(query)) return 1;
  return 2;
}

Future<List<Map<String, Object?>>> searchAndSyncFileMatchesInBackground(Map<String, Object?> message) async {
  final String? dbPath = message['dbPath'] as String?;
  final String lowerQuery = (message['query'] ?? '') as String;
  final int maxMatches = (message['maxMatches'] ?? maxLauncherMatches) as int;

  final List<Map<String, Object?>> results = <Map<String, Object?>>[];

  if (dbPath != null) {
    FileIndexDb.instance.setDatabasePath(dbPath);
    await FileIndexDb.instance.database;
    // We don't do the DB search here anymore because the main thread does it.
    // But we need the DB open to sync new files found during the scan.
  }

  final List<dynamic>? searchFolders = message['searchFolders'] as List<dynamic>?;
  if (searchFolders == null || searchFolders.isEmpty) return <Map<String, Object?>>[];

  final Stopwatch stopwatch = Stopwatch()..start();

  for (final dynamic folderObj in searchFolders) {
    if (results.length >= maxMatches || stopwatch.elapsedMilliseconds > 2000) break;
    final Map<String, Object?> folder = Map<String, Object?>.from(folderObj);
    final String path = folder['path'] as String;
    final String excludePath = (folder['excludePath'] ?? '') as String;
    final bool includeFolders = (folder['includeFolders'] ?? true) as bool;
    final bool includeFiles = (folder['includeFiles'] ?? true) as bool;
    final Set<String> allowedExtensions = _normalizedAllowedExtensions(
      ((folder['allowedExtensions'] as List<dynamic>?) ?? const <dynamic>[]).map((dynamic value) => value.toString()),
    );
    final int? maxDepth = folder['maxDepth'] as int?;
    _recursiveSyncAndSearch(
      Directory(path),
      path,
      lowerQuery,
      results,
      maxMatches,
      includeFolders,
      includeFiles,
      allowedExtensions,
      excludePath,
      maxDepth,
      0,
      stopwatch,
    );
  }

  return results;
}

bool shouldRunFilesystemSearch({
  required LauncherSearchMode searchMode,
  required String normalizedQuery,
  required String rawQuery,
}) {
  if (searchMode == LauncherSearchMode.filesOnly) return true;
  if (searchMode != LauncherSearchMode.mixed) return false;
  if (rawQuery.isEmpty || rawQuery == ' ') return false;
  return normalizedQuery.length >= 3;
}

int windowMatchRank(Window window, String query) {
  final String title = window.title.toLowerCase();
  final String exe = window.process.exe.toLowerCase().replaceFirst('.exe', '');

  if (title == query || exe == query) return 0;
  if (title.startsWith(query) || exe.startsWith(query)) return 1;
  return 2;
}

// ignore: unused_element
QuickActionMenuEntry _buildQuickActionsLauncherEntry() {
  return QuickActionMenuEntry(
    id: 'launcher-quick-actions-menu',
    title: 'Quick Actions',
    searchTerms: const <String>[
      'Quick Actions',
      'quick actions menu',
      'QuickActionsMenuButton',
      'launcher catalog',
    ],
    builder: (BuildContext context) {
      final ThemeData theme = Theme.of(context);
      final Color accent = userSettings.themeColors.accent;
      final Color onSurface = theme.colorScheme.onSurface;
      return InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          unawaited(showQuickMenuModal(
            context: context,
            child: const QuickActionWidget(popup: false),
          ));
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: <Widget>[
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withAlpha(24),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.grid_view_rounded, size: 18, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Quick Actions',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Open the Quick Actions modal',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: onSurface.withAlpha(140),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.open_in_new_rounded, size: 14, color: onSurface.withAlpha(100)),
            ],
          ),
        ),
      );
    },
  );
}

bool _isAllowedExtension(String name, Set<String> allowedExtensions) {
  if (allowedExtensions.isEmpty) return true;
  final String extension = p.extension(name).toLowerCase();
  return allowedExtensions.contains(extension);
}

Set<String> _normalizedAllowedExtensions(Iterable<String> extensions) {
  return extensions
      .map((String extension) => extension.trim().toLowerCase())
      .where((String extension) => extension.isNotEmpty)
      .map((String extension) => extension.startsWith('.') ? extension : '.$extension')
      .toSet();
}

void _recursiveSyncAndSearch(
  Directory dir,
  String rootPath,
  String query,
  List<Map<String, Object?>> results,
  int maxMatches,
  bool includeFolders,
  bool includeFiles,
  Set<String> allowedExtensions,
  String excludePath,
  int? maxDepth,
  int currentDepth,
  Stopwatch stopwatch,
) {
  // Stop everything if we have enough results or time is up
  if (results.length >= maxMatches) return;
  if (stopwatch.elapsedMilliseconds > 2000) return; // Hard 2s limit for live search
  if (maxDepth != null && currentDepth > maxDepth) return;

  try {
    final List<FileSystemEntity> entities = dir.listSync();
    for (final FileSystemEntity entity in entities) {
      if (results.length >= maxMatches) return;
      if (stopwatch.elapsedMilliseconds > 2000) return;

      if (excludePath != "" && RegExp(excludePath, caseSensitive: false).hasMatch(entity.path)) continue;
      final String name = p.basename(entity.path);
      final String lowerName = name.toLowerCase();
      final bool isDir = entity is Directory;

      int? currentId;
      final bool shouldInclude = isDir ? includeFolders : includeFiles && _isAllowedExtension(name, allowedExtensions);

      if (shouldInclude) {
        if (query.isEmpty || lowerName.contains(query)) {
          // If we found a match, ensure it and its parents are in the DB
          // so it appears instantly next time.
          try {
            currentId = FileIndexDb.instance.cachePath(
              rootPath,
              entity.path,
              isDir,
              rootIsSearchable: includeFolders,
              directoryIsSearchable: includeFolders,
            );
          } catch (_) {}

          results.add(<String, Object?>{
            'path': entity.path,
            'isDirectory': isDir,
            'id': currentId,
          });
        }
      }

      // Re-check the time limit after the potentially-slow cachePath DB write
      // so we don't overshoot the 2s budget before reaching the recursion guard.
      if (stopwatch.elapsedMilliseconds > 2000) return;

      if (isDir && (maxDepth == null || currentDepth < maxDepth)) {
        _recursiveSyncAndSearch(
          entity,
          rootPath,
          query,
          results,
          maxMatches,
          includeFolders,
          includeFiles,
          allowedExtensions,
          excludePath,
          maxDepth,
          currentDepth + 1,
          stopwatch,
        );
      }
    }
  } catch (_) {}
}
