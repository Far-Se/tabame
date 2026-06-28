import 'package:tabamewin32/tabamewin32.dart' show BrowserTab, BrowserTabs;

import '../../launcher_search_models.dart';
import 'launcher_search_context.dart';

/// Handles the `,` launcher prefix: lists open tabs across Chromium-based
/// browsers (Chrome/Edge/Brave/Opera/...) via UI Automation, filtered by the
/// typed query against the tab title and browser name.
class BrowserTabsSearchHandler {
  static void handle(LauncherSearchContext context) {
    context.setSearching(true);

    Future<void>(() async {
      // Guard before the async gap.
      if (!context.isActiveSearch(context.requestId, context.query)) return;

      final List<BrowserTab> tabs = await BrowserTabs.getTabs();

      // Guard after the async gap: the query may have changed or the widget
      // may have been disposed while enumeration was running.
      if (!context.isActiveSearch(context.requestId, context.query)) {
        context.setSearching(false);
        return;
      }

      final String query = context.normalizedQuery.toLowerCase();
      final List<LauncherSearchResultItem> results = <LauncherSearchResultItem>[];
      for (final BrowserTab tab in tabs) {
        if (query.isEmpty ||
            tab.title.toLowerCase().contains(query) ||
            tab.browser.toLowerCase().contains(query)) {
          results.add(LauncherSearchResultItem.browserTab(tab));
        }
      }

      // setResults is a no-op when isDisposed, so this is safe.
      context.setResults(results, isSearching: false);
    });
  }
}
