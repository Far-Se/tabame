import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/db/file_index_db.dart';
import '../../../models/win32/window.dart';
import '../../../widgets/itzy/quickmenu/button_quickactions.dart';
import '../../interface/result_item_bookmark.dart';
import '../../launcher_search_models.dart';
import 'launcher_search_context.dart';
import 'search_utils.dart';

class MixedSearchHandler {
  static void handle(LauncherSearchContext context, LauncherSearchMode searchMode) {
    final bool shouldRunFilesystem = shouldRunFilesystemSearch(
      searchMode: searchMode,
      normalizedQuery: context.normalizedQuery,
      rawQuery: context.query,
    );

    final List<QuickActionMenuEntry> quickActionMatches = searchMode == LauncherSearchMode.filesOnly
        ? <QuickActionMenuEntry>[]
        : findQuickActionMatches(
            context.buildContext,
            context.lowerQuery,
            includeAllOnEmpty: searchMode == LauncherSearchMode.actionsOnly,
          );

    if (searchMode == LauncherSearchMode.actionsOnly) {
      final List<LauncherSearchResultItem> results =
          quickActionMatches.map(LauncherSearchResultItem.quickAction).toList();
      context.setResults(results, isSearching: false);
      return;
    }

    final bool showAllHistory = (searchMode == LauncherSearchMode.filesOnly && context.normalizedQuery.isEmpty) ||
        (searchMode == LauncherSearchMode.mixed && context.query == ' ');

    if (showAllHistory) {
      final List<SearchResultNode> topNodes = FileIndexDb.instance.getTopOpened(limit: 20);
      final List<LauncherSearchResultItem> historyResults = deserializeSearchMatches(topNodes);
      context.setResults(historyResults, isSearching: false);
      return;
    }

    // Phase 1: Immediate Results (Main Isolate)
    // Gather everything fast: Windows, Bookmarks, and Database Files
    final List<Window> windowMatches = searchMode == LauncherSearchMode.filesOnly
        ? <Window>[]
        : findWindowMatches(
            context.lowerQuery,
            includeAllOnEmpty: false,
          );

    final List<BookmarkSearchResult> bookmarkMatches =
        searchMode == LauncherSearchMode.filesOnly ? <BookmarkSearchResult>[] : findBookmarkMatches(context.lowerQuery);

    final List<SearchResultNode> dbMatches = shouldRunFilesystem
        ? FileIndexDb.instance.search(context.lowerQuery, limit: maxLauncherMatches)
        : <SearchResultNode>[];

    final List<LauncherSearchResultItem> initialFileResults = deserializeSearchMatches(dbMatches);

    final List<LauncherSearchResultItem> results = searchMode == LauncherSearchMode.filesOnly
        ? initialFileResults
        : composeResults(
            quickActionMatches: quickActionMatches,
            windowMatches: windowMatches,
            fileMatches: initialFileResults,
            bookmarkMatches: bookmarkMatches,
          );

    // Show initial results immediately
    context.setResults(results, isSearching: shouldRunFilesystem, resetSelection: false);

    if (!shouldRunFilesystem) return;

    Timer(const Duration(milliseconds: 300), () async {
      // Guard: query changed during debounce — stop spinner and bail out
      if (!context.isActiveSearch(context.requestId, context.query, trimLeft: true)) {
        context.setSearching(false);
        return;
      }

      List<Map<String, Object?>> scanMatches = <Map<String, Object?>>[];
      try {
        scanMatches = await compute(
          searchAndSyncFileMatchesInBackground,
          <String, Object?>{
            'query': context.lowerQuery,
            'maxMatches': maxLauncherMatches,
            'searchFolders': Boxes.searchFolders
                .map((SearchFolder folder) => <String, Object?>{
                      'path': folder.path,
                      'includeFolders': folder.includeFolders,
                      'includeFiles': folder.includeFiles,
                      'allowedExtensions': folder.allowedExtensions,
                      'maxDepth': folder.maxDepth,
                    })
                .toList(growable: false),
            'dbPath': FileIndexDb.instance.dbPath,
          },
        );
      } catch (_) {}

      // Guard: query changed while background scan was running — stop spinner and bail out
      if (!context.isActiveSearch(context.requestId, context.query, trimLeft: true)) {
        context.setSearching(false);
        return;
      }

      // Phase 2: Merge results
      final List<LauncherSearchResultItem> backgroundResults = deserializeFileMatches(scanMatches);
      final List<LauncherSearchResultItem> combinedFileResults =
          List<LauncherSearchResultItem>.from(initialFileResults);

      final Set<String> existingPaths = initialFileResults
          .where((LauncherSearchResultItem item) => item.isFile)
          .map((LauncherSearchResultItem i) => i.entity?.path ?? '')
          .where((String path) => path.isNotEmpty)
          .toSet();

      for (final LauncherSearchResultItem item in backgroundResults) {
        if (combinedFileResults.length >= maxLauncherMatches) break;
        final String path = item.entity?.path ?? '';
        if (path.isNotEmpty && !existingPaths.contains(path)) {
          combinedFileResults.add(item);
          existingPaths.add(path);
        }
      }

      final List<Window> windowMatches = searchMode == LauncherSearchMode.filesOnly
          ? <Window>[]
          : findWindowMatches(
              context.lowerQuery,
              includeAllOnEmpty: false,
            );
      final List<BookmarkSearchResult> bookmarkMatches = searchMode == LauncherSearchMode.filesOnly
          ? <BookmarkSearchResult>[]
          : findBookmarkMatches(context.lowerQuery);

      final List<LauncherSearchResultItem> results = searchMode == LauncherSearchMode.filesOnly
          ? combinedFileResults
          : composeResults(
              quickActionMatches: quickActionMatches,
              windowMatches: windowMatches,
              fileMatches: combinedFileResults,
              bookmarkMatches: bookmarkMatches,
            );

      context.setResults(results, isSearching: false, resetSelection: false);
    });
  }
}
