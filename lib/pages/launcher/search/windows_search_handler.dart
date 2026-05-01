import 'dart:async';
import '../../../models/window_watcher.dart';
import '../../launcher_search_models.dart';
import 'launcher_search_context.dart';
import 'search_utils.dart';

class WindowsSearchHandler {
  static void handle(LauncherSearchContext context) {
    context.setSearching(true);

    Timer(const Duration(milliseconds: 40), () {
      if (!context.isActiveSearch(context.requestId, context.query)) return;
      final List<LauncherSearchResultItem> results = findWindowMatches(
        context.normalizedQuery.toLowerCase(),
        includeAllOnEmpty: context.normalizedQuery.isEmpty,
      ).map(LauncherSearchResultItem.window).toList();
      results.removeWhere((LauncherSearchResultItem item) => (item.window?.title ?? '') == 'Tabame');
      context.setResults(results, isSearching: true);
    });

    Timer(const Duration(milliseconds: 120), () async {
      if (!context.isActiveSearch(context.requestId, context.query)) return;
      await WindowWatcher.fetchWindows();
      if (!context.isActiveSearch(context.requestId, context.query)) return;
      final List<LauncherSearchResultItem> results = findWindowMatches(
        context.normalizedQuery.toLowerCase(),
        includeAllOnEmpty: context.normalizedQuery.isEmpty,
      ).map(LauncherSearchResultItem.window).toList();
      results.removeWhere((LauncherSearchResultItem item) => (item.window?.title ?? '') == 'Tabame');
      context.setResults(results, isSearching: false);
    });
  }
}
