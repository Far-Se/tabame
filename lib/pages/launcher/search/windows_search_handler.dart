import 'dart:async';

import 'package:flutter/material.dart';

import '../../../platform/window_watcher_service.dart';
import '../../launcher_search_models.dart';
import 'launcher_search_context.dart';
import 'search_utils.dart';

class WindowsSearchHandler {
  static void handle(LauncherSearchContext context) {
    final WindowWatcherService watcher = WindowWatcherService.instance;
    if (!watcher.isAvailable) {
      context.setResults(<LauncherSearchResultItem>[
        LauncherSearchResultItem.info(
          LauncherInfoResult(
            id: 'window-search-unavailable',
            title: 'Window search unavailable',
            subtitle: watcher.unavailableReason,
            icon: Icons.window_rounded,
          ),
        ),
      ], isSearching: false);
      return;
    }

    context.setSearching(true);

    Timer(const Duration(milliseconds: 40), () {
      if (!context.isActiveSearch(context.requestId, context.query)) return;
      final List<LauncherSearchResultItem> results = findWindowMatches(
        context.normalizedQuery.toLowerCase(),
        includeAllOnEmpty: context.normalizedQuery.isEmpty,
      ).map(LauncherSearchResultItem.window).toList();
      results.removeWhere((LauncherSearchResultItem item) => (item.window?.title ?? '') == 'Tabame');
      // setResults is a no-op when isDisposed, so this is safe.
      context.setResults(results, isSearching: true);
    });

    Timer(const Duration(milliseconds: 120), () async {
      // Guard before the async gap.
      if (!context.isActiveSearch(context.requestId, context.query)) return;

      await watcher.refresh();

      // Guard after the async gap: the query may have changed or the widget
      // may have been disposed while fetchWindows was running.
      if (!context.isActiveSearch(context.requestId, context.query)) {
        // setSearching is a no-op when isDisposed.
        context.setSearching(false);
        return;
      }

      final List<LauncherSearchResultItem> results = findWindowMatches(
        context.normalizedQuery.toLowerCase(),
        includeAllOnEmpty: context.normalizedQuery.isEmpty,
      ).map(LauncherSearchResultItem.window).toList();
      results.removeWhere((LauncherSearchResultItem item) => (item.window?.title ?? '') == 'Tabame');
      context.setResults(results, isSearching: false);
    });
  }
}
