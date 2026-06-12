import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../models/win32/win_utils.dart';
import '../../../widgets/itzy/quickmenu/button_quickactions.dart';
import '../../launcher_search_models.dart';
import 'launcher_search_context.dart';
import 'search_utils.dart';

class FolderSearchHandler {
  static void handle(LauncherSearchContext context) {
    context.setSearching(true);
    Timer(const Duration(milliseconds: 150), () async {
      // Guard before the async gap.
      if (!context.isActiveSearch(context.requestId, context.query, trimLeft: true)) {
        context.setSearching(false);
        return;
      }

      final String? browsingPath = context.browsingPath;
      if (browsingPath != null && browsingPath.isNotEmpty) {
        List<Map<String, Object?>> serializedEntries = <Map<String, Object?>>[];
        try {
          serializedEntries = await compute(
            _listFolderContentsInBackground,
            <String, Object?>{
              'folderPath': browsingPath,
              'query': context.lowerQuery,
            },
          );
        } catch (_) {}

        if (!context.isActiveSearch(context.requestId, context.query, trimLeft: true)) {
          context.setSearching(false);
          return;
        }

        final List<LauncherSearchResultItem> results = deserializeFileMatches(serializedEntries);

        final List<LauncherSearchResultItem> pinned = <LauncherSearchResultItem>[
          _buildOpenInExplorerAction(
            folderPath: browsingPath,
            onOpen: context.onOpenFolderInExplorer,
          ),
          if (context.canGoBack) _buildGoBackAction(onGoBack: context.onGoBack),
        ];

        context.setResults(
          <LauncherSearchResultItem>[...pinned, ...results],
          isSearching: false,
          resetSelection: false,
        );
        return;
      }

      final String desktopPath = WinUtils.getKnownFolderCLSID(0x0000);
      final List<Map<String, Object?>> desktopSearchFolders = <Map<String, Object?>>[
        <String, Object?>{
          'path': desktopPath,
          'includeFolders': true,
          'includeFiles': true,
          'allowedExtensions': const <String>[],
          'maxDepth': context.lowerQuery.isEmpty ? 0 : null,
        }
      ];

      List<Map<String, Object?>> serializedMatches = <Map<String, Object?>>[];
      try {
        serializedMatches = await compute(
          searchAndSyncFileMatchesInBackground,
          <String, Object?>{
            'query': context.lowerQuery,
            'maxMatches': maxLauncherMatches,
            'searchFolders': desktopSearchFolders,
          },
        );
      } catch (_) {}

      if (!context.isActiveSearch(context.requestId, context.query, trimLeft: true)) {
        context.setSearching(false);
        return;
      }

      List<LauncherSearchResultItem> results = deserializeFileMatches(serializedMatches);
      results = results.where((LauncherSearchResultItem result) {
        final FileSystemEntity? entity = result.entity;
        if (entity == null) return true;
        return entity.uri.pathSegments.isEmpty || entity.uri.pathSegments.last.toLowerCase() != 'desktop.ini';
      }).toList(growable: false);

      context.setResults(results, isSearching: false, resetSelection: false);
    });
  }

  static LauncherSearchResultItem _buildOpenInExplorerAction({
    required String folderPath,
    void Function(String)? onOpen,
  }) {
    void execute() => onOpen?.call(folderPath);

    return LauncherSearchResultItem.quickAction(
      QuickActionMenuEntry(
        id: 'desktop_browse_open_explorer:$folderPath',
        title: 'Open Folder in Explorer',
        searchTerms: const <String>['open', 'explorer', 'folder'],
        allowRenderedFallbackExecute: true,
        onExecute: execute,
        builder: (BuildContext ctx) {
          final ThemeData theme = Theme.of(ctx);
          final Color accent = theme.colorScheme.primary;
          final Color onSurface = theme.colorScheme.onSurface;
          return QuickActionListItem(
            name: "Open Folder in Explorer",
            accent: accent,
            onSurface: onSurface,
            leading: SizedBox(
              width: 18,
              child: Icon(Icons.folder_open_rounded, size: 14, color: accent),
            ),
            onTap: execute,
          );
        },
      ),
    );
  }

  static LauncherSearchResultItem _buildGoBackAction({
    VoidCallback? onGoBack,
  }) {
    void execute() => onGoBack?.call();

    return LauncherSearchResultItem.quickAction(
      QuickActionMenuEntry(
        id: 'desktop_browse_go_back',
        title: 'Go Back',
        searchTerms: const <String>['back', 'up', 'parent'],
        allowRenderedFallbackExecute: true,
        onExecute: execute,
        builder: (BuildContext ctx) {
          final ThemeData theme = Theme.of(ctx);
          final Color accent = theme.colorScheme.primary;
          final Color onSurface = theme.colorScheme.onSurface;
          return QuickActionListItem(
            name: "Go Back",
            accent: accent,
            onSurface: onSurface,
            leading: SizedBox(
              width: 18,
              child: Icon(Icons.arrow_back_rounded, size: 14, color: accent),
            ),
            onTap: execute,
          );
        },
      ),
    );
  }
}

List<Map<String, Object?>> _listFolderContentsInBackground(Map<String, Object?> args) {
  final String folderPath = args['folderPath'] as String;
  // final String query = (args['query'] as String? ?? '').toLowerCase();

  final Directory dir = Directory(folderPath);
  if (!dir.existsSync()) return <Map<String, Object?>>[];

  final List<FileSystemEntity> entries = <FileSystemEntity>[];
  try {
    entries.addAll(dir.listSync(recursive: false, followLinks: false));
  } catch (_) {
    return <Map<String, Object?>>[];
  }
  // Sort: directories first, then files, both alphabetically.
  entries.sort((FileSystemEntity a, FileSystemEntity b) {
    final bool aDir = a is Directory;
    final bool bDir = b is Directory;
    if (aDir != bDir) return aDir ? -1 : 1;
    return a.path.toLowerCase().compareTo(b.path.toLowerCase());
  });

  final List<Map<String, Object?>> results = <Map<String, Object?>>[];
  for (final FileSystemEntity entity in entries) {
    final String name = entity.uri.pathSegments.lastWhere(
      (String s) => s.isNotEmpty,
      orElse: () => entity.path,
    );

    // Skip desktop.ini.
    if (name.toLowerCase() == 'desktop.ini') continue;

    // Filter by query when the user has typed something.
    // if (query.isNotEmpty && !name.toLowerCase().contains(query)) continue;

    results.add(<String, Object?>{
      'path': entity.path,
      'isDirectory': entity is Directory,
    });

    if (results.length >= maxLauncherMatches) break;
  }
  return results;
}
