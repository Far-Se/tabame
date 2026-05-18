import 'package:flutter/material.dart';
import '../../launcher_search_models.dart';

typedef SetSearchingCallback = void Function(bool searching);
typedef SetResultsCallback = void Function(List<LauncherSearchResultItem> results, {bool isSearching, bool resetSelection});
typedef IsActiveSearchCallback = bool Function(int requestId, String query, {bool trimLeft});

/// A shared mutable token that the owning [State] holds as a field.
///
/// Create one instance in [State.initState] (or lazily) and pass it to every
/// [LauncherSearchContext] constructed during that widget's lifetime.
/// Call [dispose] from [State.dispose] to silently drop all pending callbacks
/// from every in-flight search, regardless of how many contexts were created.
///
/// Usage in LauncherState:
/// ```dart
/// // field:
/// final LauncherSearchToken _searchToken = LauncherSearchToken();
///
/// // in dispose():
/// _searchToken.dispose();
///
/// // in _runSearch():
/// final LauncherSearchContext context = LauncherSearchContext(
///   token: _searchToken,
///   ...
/// );
/// ```
class LauncherSearchToken {
  bool _disposed = false;

  /// Returns true once [dispose] has been called.
  bool get isDisposed => _disposed;

  /// Call this from [State.dispose].  After this point every
  /// [LauncherSearchContext] that holds this token will silently ignore
  /// [setSearching] and [setResults] calls.
  void dispose() => _disposed = true;
}

class LauncherSearchContext {
  final BuildContext buildContext;
  final int requestId;
  final String query;
  final String normalizedQuery;
  final String lowerQuery;
  final LauncherSearchToken _token;
  final SetSearchingCallback _setSearchingRaw;
  final SetResultsCallback _setResultsRaw;
  final IsActiveSearchCallback isActiveSearch;

  LauncherSearchContext({
    required this.buildContext,
    required this.requestId,
    required this.query,
    required this.normalizedQuery,
    required this.lowerQuery,
    required LauncherSearchToken token,
    required SetSearchingCallback setSearching,
    required SetResultsCallback setResults,
    required this.isActiveSearch,
  })  : _token = token,
        _setSearchingRaw = setSearching,
        _setResultsRaw = setResults;

  /// True once the owning [State] has been disposed.
  bool get isDisposed => _token.isDisposed;

  /// Guarded wrapper: silently drops calls after the widget is disposed.
  void setSearching(bool searching) {
    if (_token.isDisposed) return;
    _setSearchingRaw(searching);
  }

  /// Guarded wrapper: silently drops calls after the widget is disposed.
  void setResults(
    List<LauncherSearchResultItem> results, {
    bool isSearching = false,
    bool resetSelection = true,
  }) {
    if (_token.isDisposed) return;
    _setResultsRaw(results, isSearching: isSearching, resetSelection: resetSelection);
  }
}
