import 'package:flutter/material.dart';
import '../../launcher_search_models.dart';

typedef SetSearchingCallback = void Function(bool searching);
typedef SetResultsCallback = void Function(List<LauncherSearchResultItem> results, {bool isSearching, bool resetSelection});
typedef IsActiveSearchCallback = bool Function(int requestId, String query, {bool trimLeft});

class LauncherSearchContext {
  final BuildContext buildContext;
  final int requestId;
  final String query;
  final String normalizedQuery;
  final String lowerQuery;
  final SetSearchingCallback setSearching;
  final SetResultsCallback setResults;
  final IsActiveSearchCallback isActiveSearch;

  LauncherSearchContext({
    required this.buildContext,
    required this.requestId,
    required this.query,
    required this.normalizedQuery,
    required this.lowerQuery,
    required this.setSearching,
    required this.setResults,
    required this.isActiveSearch,
  });
}
