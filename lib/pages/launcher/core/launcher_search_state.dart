import 'launcher_query.dart';
import 'launcher_result.dart';

class LauncherSearchState {
  const LauncherSearchState({
    required this.query,
    required this.results,
    required this.isSearching,
  });

  final LauncherQuery query;
  final List<LauncherSearchResultItem> results;
  final bool isSearching;

  LauncherSearchState copyWith({
    LauncherQuery? query,
    List<LauncherSearchResultItem>? results,
    bool? isSearching,
  }) {
    return LauncherSearchState(
      query: query ?? this.query,
      results: results ?? this.results,
      isSearching: isSearching ?? this.isSearching,
    );
  }
}
