import 'dart:async';
import '../../launcher_search_models.dart';
import 'launcher_search_context.dart';
import 'search_utils.dart';

class BookmarksSearchHandler {
  static void handle(LauncherSearchContext context) {
    context.setSearching(true);
    Timer(const Duration(milliseconds: 40), () {
      if (!context.isActiveSearch(context.requestId, context.query)) return;
      final List<LauncherSearchResultItem> results = findBookmarkMatches(
        context.normalizedQuery,
        includeAllOnEmpty: context.normalizedQuery.isEmpty,
      ).map(LauncherSearchResultItem.bookmark).toList();
      context.setResults(results, isSearching: false);
    });
  }
}
