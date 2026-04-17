import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../models/classes/boxes.dart';
import '../models/globals.dart';
import '../models/settings.dart';
import '../models/win32/mixed.dart';
import '../models/win32/window.dart';
import '../models/win32/win32.dart';
import '../models/window_watcher.dart';
import '../widgets/itzy/quickmenu/button_quickactions.dart';

enum _SearchMode {
  mixed,
  actionsOnly,
  filesOnly,
  windowsOnly,
}

class _SearchResultItem {
  const _SearchResultItem.file(this.entity)
      : quickAction = null,
        window = null;

  const _SearchResultItem.quickAction(this.quickAction)
      : entity = null,
        window = null;

  const _SearchResultItem.window(this.window)
      : entity = null,
        quickAction = null;

  final FileSystemEntity? entity;
  final QuickActionMenuEntry? quickAction;
  final Window? window;

  bool get isFile => entity != null;
  bool get isWindow => window != null;

  String get id => isFile
      ? 'file:${entity!.path}'
      : isWindow
          ? 'window:${window!.hWnd}'
          : 'quick:${quickAction!.id}';
}

class FileSearch extends StatefulWidget {
  const FileSearch({super.key});

  @override
  FileSearchState createState() => FileSearchState();
}

class FileSearchState extends State<FileSearch> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _pageFocusNode = FocusNode();
  final FocusNode _focusNode = FocusNode();
  final ValueNotifier<int> _activeIndexNotifier = ValueNotifier<int>(0);
  final Map<String, GlobalKey> _quickActionKeys = <String, GlobalKey>{};
  String? _quickActionSplashId;
  Timer? _quickActionSplashTimer;

  List<_SearchResultItem> _results = <_SearchResultItem>[];
  List<SearchHistory> _history = <SearchHistory>[];
  bool _isSearching = false;
  bool _canConsumePendingInput = false;

  bool get _hasSearchFolders => Boxes.searchFolders.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _controller.text = globalSettings.textFileSearch;
    _controller.selection = TextSelection.fromPosition(TextPosition(offset: _controller.text.length));
    Globals.quickMenuSearchInputVersion.addListener(_consumePendingQuickMenuSearchInput);
    if (mounted) setState(() {});
    _focusNode.onKeyEvent = (FocusNode node, KeyEvent event) {
      if (event is KeyDownEvent) {
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          if (_triggerMediaResult(previous: true)) {
            return KeyEventResult.handled;
          }
        } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          if (_triggerMediaResult(previous: false)) {
            return KeyEventResult.handled;
          }
        } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          if (_activeIndexNotifier.value < _results.length - 1) {
            _activeIndexNotifier.value++;
            return KeyEventResult.handled;
          }
        } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          if (_activeIndexNotifier.value > 0) {
            _activeIndexNotifier.value--;
            return KeyEventResult.handled;
          }
        }
      }
      return KeyEventResult.ignored;
    };

    _focusNode.requestFocus();
    _history = Boxes.searchHistory;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _canConsumePendingInput = true;
        _startWindowRefreshLoop();
        _consumePendingQuickMenuSearchInput();
        _pageFocusNode.requestFocus();
        _focusNode.requestFocus();
        _onSearchChanged(_controller.text);
      }
    });
  }

  bool _triggerMediaResult({required bool previous}) {
    if (_results.isEmpty) return false;
    if (_activeIndexNotifier.value >= _results.length) return false;
    final _SearchResultItem firstResult = _results[_activeIndexNotifier.value];
    final QuickActionMenuEntry? quickAction = firstResult.quickAction;
    if (quickAction == null) return false;

    if (quickAction.id.startsWith('app-audio-')) {
      final int? index = int.tryParse(quickAction.id.replaceFirst('app-audio-', ''));
      if (index == null) return false;
      _flashQuickActionResult(quickAction.id);
      if (previous) {
        handleAppAudioPrevious(index);
      } else {
        handleAppAudioNext(index);
      }
      return true;
    }

    final String title = quickAction.title.toLowerCase();
    final bool isSpotify = title.contains('spotify') ||
        quickAction.searchTerms.any((String term) => term.toLowerCase().contains('spotify'));
    if (!isSpotify) return false;

    _flashQuickActionResult(quickAction.id);
    sendSpotifyMediaCommand(previous ? AppCommand.mediaPrevioustrack : AppCommand.mediaNexttrack);
    return true;
  }

  void _flashQuickActionResult(String id) {
    _quickActionSplashTimer?.cancel();
    setState(() => _quickActionSplashId = id);
    _quickActionSplashTimer = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      setState(() => _quickActionSplashId = null);
    });
  }

  @override
  void dispose() {
    Globals.quickMenuPage = QuickMenuPage.quickMenu;
    globalSettings.textFileSearch = "";
    Globals.quickMenuSearchInputVersion.removeListener(_consumePendingQuickMenuSearchInput);
    Globals.clearQuickMenuSearchInput();

    _searchDebounce?.cancel();
    _historyDebounce?.cancel();
    _quickActionSplashTimer?.cancel();
    _windowRefreshTimer?.cancel();
    _controller.dispose();
    _pageFocusNode.dispose();
    _focusNode.dispose();
    _activeIndexNotifier.dispose();
    super.dispose();
  }

  Timer? _searchDebounce;
  Timer? _historyDebounce;
  Timer? _windowRefreshTimer;
  String _lastWindowSnapshot = '';

  String _buildWindowSnapshot() {
    return WindowWatcher.list
        .map((Window window) => '${window.hWnd}|${window.title}|${window.process.exe}|${window.isPinned}')
        .join('||');
  }

  void _startWindowRefreshLoop() {
    _windowRefreshTimer?.cancel();
    _lastWindowSnapshot = _buildWindowSnapshot();
    _windowRefreshTimer = Timer.periodic(const Duration(milliseconds: 900), (Timer timer) async {
      if (!mounted || Globals.quickMenuPage != QuickMenuPage.fileSearch) return;

      final bool updated = await WindowWatcher.fetchWindows();
      if (!mounted || !updated || Globals.quickMenuPage != QuickMenuPage.fileSearch) return;

      final String nextSnapshot = _buildWindowSnapshot();
      if (nextSnapshot == _lastWindowSnapshot) return;
      _lastWindowSnapshot = nextSnapshot;

      _refreshVisibleWindowResults();
    });
  }

  void _refreshVisibleWindowResults() {
    if (_results.isEmpty) return;

    bool changed = false;
    final Map<int, Window> latestWindows = <int, Window>{
      for (final Window window in WindowWatcher.list) window.hWnd: window,
    };

    final List<_SearchResultItem> nextResults = _results.map((_SearchResultItem result) {
      final Window? currentWindow = result.window;
      if (currentWindow == null) return result;

      final Window? latestWindow = latestWindows[currentWindow.hWnd];
      if (latestWindow == null) return result;

      if (latestWindow.title != currentWindow.title ||
          latestWindow.process.exe != currentWindow.process.exe ||
          latestWindow.isPinned != currentWindow.isPinned) {
        changed = true;
        return _SearchResultItem.window(latestWindow);
      }

      return result;
    }).toList(growable: false);

    if (!changed || !mounted) return;
    setState(() {
      _results = nextResults;
    });
  }

  void _consumePendingQuickMenuSearchInput() {
    if (!_canConsumePendingInput) return;

    final String pending = Globals.takeQuickMenuSearchInput();
    if (pending.isEmpty) return;

    final TextEditingValue currentValue = _controller.value;
    final TextSelection selection = currentValue.selection.isValid
        ? currentValue.selection
        : TextSelection.collapsed(offset: currentValue.text.length);
    final int start = selection.start < 0 ? currentValue.text.length : selection.start;
    final int end = selection.end < 0 ? start : selection.end;
    final String nextText = currentValue.text.replaceRange(start, end, pending);
    final int caretOffset = start + pending.length;

    _controller.value = currentValue.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(offset: caretOffset),
      composing: TextRange.empty,
    );
    _onSearchChanged(nextText);
  }

  Future<void> _onSearchChanged(String query) async {
    globalSettings.textFileSearch = query;
    _searchDebounce?.cancel();
    _historyDebounce?.cancel();

    final _SearchMode searchMode = _getSearchMode(query);
    final String normalizedQuery = _getNormalizedQuery(query);

    if (query.isEmpty || (normalizedQuery.isEmpty && searchMode == _SearchMode.mixed)) {
      if (mounted) {
        setState(() {
          _results = <_SearchResultItem>[];
          _isSearching = false;
        });
      }
      return;
    }

    if (searchMode == _SearchMode.windowsOnly) {
      if (mounted) {
        setState(() => _isSearching = true);
      }

      _historyDebounce = Timer(const Duration(milliseconds: 40), () {
        if (!mounted) return;
        final List<_SearchResultItem> results = _findWindowMatches(
          normalizedQuery.toLowerCase(),
          includeAllOnEmpty: normalizedQuery.isEmpty,
        ).map(_SearchResultItem.window).toList();
        results.removeWhere((_SearchResultItem item) => (item.window?.title ?? "") == "Tabame");
        _syncQuickActionKeys(results);
        setState(() {
          _results = results;
          _activeIndexNotifier.value = 0;
          _isSearching = false;
        });
      });

      _searchDebounce = Timer(const Duration(milliseconds: 120), () async {
        if (!mounted) return;
        await WindowWatcher.fetchWindows();
        if (!mounted || _controller.text != query) return;
        final List<_SearchResultItem> results = _findWindowMatches(
          normalizedQuery.toLowerCase(),
          includeAllOnEmpty: normalizedQuery.isEmpty,
        ).map(_SearchResultItem.window).toList();
        results.removeWhere((_SearchResultItem item) => (item.window?.title ?? "") == "Tabame");
        _syncQuickActionKeys(results);
        setState(() {
          _results = results;
          _activeIndexNotifier.value = 0;
          _isSearching = false;
        });
      });
      return;
    }

    final String lowerQuery = normalizedQuery.toLowerCase();
    final List<QuickActionMenuEntry> quickActionMatches = searchMode == _SearchMode.filesOnly
        ? <QuickActionMenuEntry>[]
        : _findQuickActionMatches(
            lowerQuery,
            includeAllOnEmpty: searchMode == _SearchMode.actionsOnly,
          );
    _historyDebounce = Timer(const Duration(milliseconds: 50), () {
      if (!mounted) return;

      if (searchMode == _SearchMode.actionsOnly) {
        final List<_SearchResultItem> results = quickActionMatches.map(_SearchResultItem.quickAction).toList();
        _syncQuickActionKeys(results);
        setState(() {
          _results = results;
          _activeIndexNotifier.value = 0;
          _isSearching = false;
        });
        return;
      }

      final bool showAllHistory = searchMode == _SearchMode.filesOnly ? normalizedQuery.isEmpty : query == " ";
      final List<FileSystemEntity> historyMatches = _findHistoryMatches(
        lowerQuery,
        showAllHistory: showAllHistory,
      );
      final List<Window> windowMatches = searchMode == _SearchMode.filesOnly
          ? <Window>[]
          : _findWindowMatches(
              lowerQuery,
              includeAllOnEmpty: false,
            );
      if (showAllHistory) {
        final List<_SearchResultItem> results = historyMatches.map(_SearchResultItem.file).toList();
        _syncQuickActionKeys(results);
        setState(() {
          _results = results;
          _activeIndexNotifier.value = 0;
          _isSearching = false;
        });
      } else if (_controller.text.trimLeft() == query) {
        final List<_SearchResultItem> results = searchMode == _SearchMode.filesOnly
            ? historyMatches.map(_SearchResultItem.file).toList()
            : _composeResults(
                historyMatches: historyMatches,
                quickActionMatches: quickActionMatches,
                windowMatches: windowMatches,
                fileMatches: historyMatches,
              );
        _syncQuickActionKeys(results);
        setState(() {
          _results = results;
          _activeIndexNotifier.value = 0;
          _isSearching = searchMode != _SearchMode.actionsOnly && _hasSearchFolders;
        });
      }
    });

    if (searchMode == _SearchMode.actionsOnly ||
        !_hasSearchFolders ||
        normalizedQuery.isEmpty ||
        (searchMode == _SearchMode.mixed && query == " ")) {
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;

      final List<FileSystemEntity> historyMatches = _findHistoryMatches(lowerQuery);
      final List<Window> windowMatches = searchMode == _SearchMode.filesOnly
          ? <Window>[]
          : _findWindowMatches(
              lowerQuery,
              includeAllOnEmpty: false,
            );
      final Set<String> matchedPaths = historyMatches.map((FileSystemEntity e) => e.path).toSet();
      final List<FileSystemEntity> matches = List<FileSystemEntity>.from(historyMatches);

      try {
        await Future.wait(Boxes.searchFolders.map((SearchFolder config) async {
          final Directory dir = Directory(config.path);
          if (!dir.existsSync()) return;

          try {
            final Stream<FileSystemEntity> listStream = config.maxDepth == null
                ? dir.list(recursive: true, followLinks: false).handleError((dynamic e) => null)
                : _listWithDepth(dir, config.maxDepth!);

            await for (FileSystemEntity entity in listStream) {
              if (!mounted || _controller.text != query) return;

              final String path = entity.path;
              final bool isDir = entity is Directory;
              final String name = path.split(Platform.pathSeparator).last.toLowerCase();

              if (isDir && !config.includeFolders) continue;
              if (!isDir && !config.includeFiles) continue;
              if (!isDir && config.allowedExtensions.isNotEmpty) {
                final String ext = '.${path.split('.').last.toLowerCase()}';
                if (!config.allowedExtensions.contains(ext)) continue;
              }

              if (name.contains(lowerQuery)) {
                if (matchedPaths.contains(entity.path)) continue;
                matches.add(entity);

                matches.sort((FileSystemEntity a, FileSystemEntity b) {
                  final String pathA = a.path;
                  final String pathB = b.path;

                  final bool inHistoryA = matchedPaths.contains(pathA);
                  final bool inHistoryB = matchedPaths.contains(pathB);

                  if (inHistoryA != inHistoryB) return inHistoryA ? -1 : 1;

                  if (inHistoryA && inHistoryB) {
                    final SearchHistory histA = _history.firstWhere((SearchHistory h) => h.path == pathA);
                    final SearchHistory histB = _history.firstWhere((SearchHistory h) => h.path == pathB);
                    return histB.timesOpened.compareTo(histA.timesOpened);
                  }

                  final String nameA = pathA.split(Platform.pathSeparator).last.toLowerCase();
                  final String nameB = pathB.split(Platform.pathSeparator).last.toLowerCase();

                  final String cleanA = nameA.contains('.') ? nameA.substring(0, nameA.lastIndexOf('.')) : nameA;
                  final String cleanB = nameB.contains('.') ? nameB.substring(0, nameB.lastIndexOf('.')) : nameB;

                  final bool isExactA = cleanA == lowerQuery;
                  final bool isExactB = cleanB == lowerQuery;
                  if (isExactA != isExactB) return isExactA ? -1 : 1;

                  final bool isPrefixA = cleanA.startsWith(lowerQuery);
                  final bool isPrefixB = cleanB.startsWith(lowerQuery);
                  if (isPrefixA != isPrefixB) return isPrefixA ? -1 : 1;

                  int getPriority(FileSystemEntity e, String n) {
                    if (e is Directory) return 3;
                    if (n.endsWith('.exe')) return 0;
                    if (n.endsWith('.lnk')) return 1;
                    return 2;
                  }

                  final int priorityA = getPriority(a, nameA);
                  final int priorityB = getPriority(b, nameB);
                  if (priorityA != priorityB) return priorityA.compareTo(priorityB);

                  return nameA.length.compareTo(nameB.length);
                });

                if (matches.length <= 10 || matches.length % 5 == 0) {
                  if (mounted && _controller.text.trimLeft() == query) {
                    final List<_SearchResultItem> results = searchMode == _SearchMode.filesOnly
                        ? matches.map(_SearchResultItem.file).toList()
                        : _composeResults(
                            historyMatches: historyMatches,
                            quickActionMatches: quickActionMatches,
                            windowMatches: windowMatches,
                            fileMatches: matches,
                          );
                    _syncQuickActionKeys(results);
                    setState(() => _results = results);
                  }
                }
              }
              if (matches.length > 6) break;
            }
          } catch (_) {}
        }));
      } catch (_) {}

      if (mounted && _controller.text.trimLeft() == query) {
        final List<_SearchResultItem> results = searchMode == _SearchMode.filesOnly
            ? matches.map(_SearchResultItem.file).toList()
            : _composeResults(
                historyMatches: historyMatches,
                quickActionMatches: quickActionMatches,
                windowMatches: windowMatches,
                fileMatches: matches,
              );
        _syncQuickActionKeys(results);
        setState(() {
          _results = results;
          _isSearching = false;
        });
      }
    });
  }

  List<FileSystemEntity> _findHistoryMatches(String lowerQuery, {bool showAllHistory = false}) {
    final List<FileSystemEntity> historyMatches = <FileSystemEntity>[];
    for (SearchHistory item in _history) {
      if (showAllHistory ||
          item.filename.toLowerCase().contains(lowerQuery) ||
          item.path.toLowerCase().contains(lowerQuery)) {
        historyMatches.add(item.isDirectory ? Directory(item.path) : File(item.path));
      }
    }

    historyMatches.sort((FileSystemEntity a, FileSystemEntity b) {
      final SearchHistory histA = _history.firstWhere((SearchHistory h) => h.path == a.path);
      final SearchHistory histB = _history.firstWhere((SearchHistory h) => h.path == b.path);
      return histB.timesOpened.compareTo(histA.timesOpened);
    });

    return historyMatches;
  }

  void _onSubmitted(String query) {
    if (_results.isEmpty || _activeIndexNotifier.value >= _results.length) return;

    final _SearchResultItem result = _results[_activeIndexNotifier.value];
    if (result.isFile) {
      _openFile(result.entity!.path);
      return;
    }
    if (result.isWindow) {
      _openWindow(result.window!);
      return;
    }

    if (result.quickAction != null) {
      _runQuickAction(result.quickAction!);
    }
  }

  void _openFile(String path) {
    final String filename = path.split(Platform.pathSeparator).last;
    final bool isDir = Directory(path).existsSync();
    final List<SearchHistory> updatedHistory = List<SearchHistory>.from(Boxes.searchHistory);
    final int existingIndex = updatedHistory.indexWhere((SearchHistory h) => h.path == path);

    if (existingIndex != -1) {
      updatedHistory[existingIndex].timesOpened++;
    } else {
      updatedHistory.add(SearchHistory(filename: filename, path: path, isDirectory: isDir));
    }

    updatedHistory.sort((SearchHistory a, SearchHistory b) => b.timesOpened.compareTo(a.timesOpened));
    if (updatedHistory.length > 100) {
      updatedHistory.removeRange(100, updatedHistory.length);
    }

    Boxes.searchHistory = updatedHistory;
    _history = updatedHistory;
    if (path.endsWith('ps1')) {
      path = "powershell -ExecutionPolicy Bypass -File \"$path\"";
      WinUtils.open(path, parseParamaters: true);
    } else {
      WinUtils.open(path);
    }
    QuickMenuFunctions.toggleQuickMenu(visible: false);
    Globals.quickMenuPage = QuickMenuPage.quickMenu;
    globalSettings.textFileSearch = "";
    Globals.quickMenuPage = QuickMenuPage.quickMenu;
    if (mounted) setState(() {});
  }

  void _removeFromHistory(String path) {
    final List<SearchHistory> updatedHistory = List<SearchHistory>.from(Boxes.searchHistory);
    updatedHistory.removeWhere((SearchHistory h) => h.path == path);
    Boxes.searchHistory = updatedHistory;
    _history = updatedHistory;
    _onSearchChanged(_controller.text);
  }

  List<Window> _findWindowMatches(
    String query, {
    bool includeAllOnEmpty = false,
  }) {
    final List<Window> windows = List<Window>.from(WindowWatcher.list);
    if (query.isEmpty) {
      if (!includeAllOnEmpty) return <Window>[];
      return windows;
    }

    final List<Window> matches = windows.where((Window window) {
      final String title = window.title.toLowerCase();
      final String exe = window.process.exe.toLowerCase();
      final String path = window.process.exePath.toLowerCase();
      return title.contains(query) || exe.contains(query) || path.contains(query);
    }).toList();

    matches.sort((Window a, Window b) {
      final int rank = _windowMatchRank(a, query).compareTo(_windowMatchRank(b, query));
      if (rank != 0) return rank;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return matches;
  }

  int _windowMatchRank(Window window, String query) {
    final String title = window.title.toLowerCase();
    final String exe = window.process.exe.toLowerCase().replaceFirst('.exe', '');

    if (title == query || exe == query) return 0;
    if (title.startsWith(query) || exe.startsWith(query)) return 1;
    return 2;
  }

  void _openWindow(Window window) {
    if (window.process.exe == "Taskmgr.exe" && !WinUtils.isAdministrator()) {
      Win32.activateWindow(window.hWnd);
    } else {
      Win32.activateWindow(window.hWnd);
    }
    QuickMenuFunctions.toggleQuickMenu(visible: false);
    Globals.lastFocusedWinHWND = window.hWnd;
    Globals.quickMenuPage = QuickMenuPage.quickMenu;
    globalSettings.textFileSearch = "";
    if (mounted) setState(() {});
  }

  List<QuickActionMenuEntry> _findQuickActionMatches(
    String query, {
    bool includeAllOnEmpty = false,
  }) {
    if ((query.isEmpty || query == " ")) {
      if (!includeAllOnEmpty) return <QuickActionMenuEntry>[];
      return buildQuickActionMenuEntries(
        context,
        onStateChanged: () {
          if (mounted) {
            setState(() {});
          }
        },
      );
    }

    final List<QuickActionMenuEntry> matches = buildQuickActionMenuEntries(
      context,
      onStateChanged: () {
        if (mounted) {
          setState(() {});
        }
      },
    ).where((QuickActionMenuEntry entry) => entry.matches(query)).toList();

    matches.sort((QuickActionMenuEntry a, QuickActionMenuEntry b) {
      final int rank = _quickActionMatchRank(a, query).compareTo(_quickActionMatchRank(b, query));
      if (rank != 0) return rank;

      final int length = a.title.length.compareTo(b.title.length);
      if (length != 0) return length;

      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

    return matches.take(5).toList();
  }

  _SearchMode _getSearchMode(String query) {
    final String trimmed = query.trimLeft();
    if (trimmed.startsWith('/')) return _SearchMode.actionsOnly;
    if (trimmed.startsWith('.')) return _SearchMode.windowsOnly;
    if (trimmed.startsWith('>') || trimmed.startsWith('?')) return _SearchMode.filesOnly;
    return _SearchMode.mixed;
  }

  String _getNormalizedQuery(String query) {
    final String trimmed = query.trimLeft();
    if (trimmed.startsWith('/') || trimmed.startsWith('.') || trimmed.startsWith('>') || trimmed.startsWith('?')) {
      return trimmed.substring(1).trimLeft();
    }
    return trimmed;
  }

  int _quickActionMatchRank(QuickActionMenuEntry entry, String query) {
    final String normalizedQuery = query.toLowerCase();
    final String title = entry.title.toLowerCase();
    final List<String> normalizedTerms = entry.searchTerms.map((String term) => term.toLowerCase()).toList();

    if (title == normalizedQuery) return 0;
    if (normalizedTerms.any((String term) => term == normalizedQuery)) return 1;
    if (title.startsWith(normalizedQuery)) return 2;
    if (normalizedTerms.any((String term) => term.startsWith(normalizedQuery))) return 3;
    return 4;
  }

  List<_SearchResultItem> _composeResults({
    required List<FileSystemEntity> historyMatches,
    required List<QuickActionMenuEntry> quickActionMatches,
    required List<Window> windowMatches,
    required List<FileSystemEntity> fileMatches,
  }) {
    return <_SearchResultItem>[
      ...historyMatches.map(_SearchResultItem.file),
      ...quickActionMatches.map(_SearchResultItem.quickAction),
      ...windowMatches.map(_SearchResultItem.window),
      ...fileMatches.skip(historyMatches.length).map(_SearchResultItem.file),
    ];
  }

  void _syncQuickActionKeys(List<_SearchResultItem> results) {
    final Set<String> activeQuickActionIds = results
        .where((_SearchResultItem result) => result.quickAction != null)
        .map((_SearchResultItem result) => result.quickAction!.id)
        .toSet();
    _quickActionKeys.removeWhere((String key, GlobalKey value) => !activeQuickActionIds.contains(key));
  }

  void _runQuickAction(QuickActionMenuEntry entry) {
    if (entry.onExecute != null) {
      entry.onExecute!.call();
      return;
    }

    if (!entry.allowRenderedFallbackExecute) return;
    final GlobalKey? actionKey = _quickActionKeys[entry.id];
    if (actionKey == null) return;
    triggerFirstTappableDescendant(actionKey.currentContext);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = Color(globalSettings.themeColors.accentColor);
    final Color onSurface = theme.colorScheme.onSurface;
    final _SearchMode searchMode = _getSearchMode(_controller.text);
    final bool hasInput = _controller.text.trim().isNotEmpty;
    return Focus(
      focusNode: _pageFocusNode,
      autofocus: true,
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
          Globals.quickMenuPage = QuickMenuPage.quickMenu;
          globalSettings.textFileSearch = "";
          setState(() {});
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => _pageFocusNode.requestFocus(),
        child: Container(
          constraints: const BoxConstraints(minHeight: 360),
          // padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                theme.colorScheme.surface.withAlpha(245),
                Color.alphaBlend(accent.withAlpha(24), theme.colorScheme.surface),
                Color.alphaBlend(accent.withAlpha(10), theme.colorScheme.surface),
              ],
            ),
            border: Border.all(color: accent.withAlpha(28)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withAlpha(18),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withAlpha(210),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: accent.withAlpha(32)),
                ),
                child: Row(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(top: 2.0),
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onPanStart: (DragStartDetails details) {
                          windowManager.startDragging();
                        },
                        child: Icon(Icons.search_rounded, size: 20, color: accent),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          TextField(
                            controller: _controller,
                            focusNode: _focusNode,
                            autofocus: true,
                            onTapOutside: (_) => _pageFocusNode.requestFocus(),
                            // Keep keyboard focus on the search field after Enter.
                            // The default editing-complete behavior can unfocus the
                            // field on desktop, which breaks repeated Enter presses.
                            onEditingComplete: () {},

                            decoration: InputDecoration(
                              hintText: 'Search files and quick actions...',
                              hintStyle: theme.textTheme.bodyLarge?.copyWith(
                                color: onSurface.withAlpha(105),
                                fontWeight: FontWeight.w400,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.only(top: 2),
                            ),
                            onChanged: _onSearchChanged,
                            onSubmitted: (String value) => _onSubmitted(value),
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_isSearching)
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: accent.withAlpha(180),
                        ),
                      ),
                  ],
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 260, maxHeight: 320),
                child: !hasInput
                    ? _buildEmptySearchState(theme, accent)
                    : !_hasSearchFolders &&
                            _results.isEmpty &&
                            (searchMode == _SearchMode.mixed || searchMode == _SearchMode.filesOnly)
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(10)
                                  .add(const EdgeInsets.symmetric(horizontal: 16, vertical: 24)),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Icon(
                                    Icons.folder_off_outlined,
                                    size: 36,
                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No search folders added yet',
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Go to Settings and add one or more folders to enable file search. Quick actions can still appear here when they match.',
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: ValueListenableBuilder<int>(
                              valueListenable: _activeIndexNotifier,
                              builder: (BuildContext context, int activeIndex, Widget? child) {
                                return ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: _results.length,
                                  itemBuilder: (BuildContext context, int index) {
                                    final _SearchResultItem result = _results[index];
                                    final bool isSelected = index == activeIndex;
                                    if (result.isFile) {
                                      return _buildFileResult(context, theme, result.entity!, index, isSelected);
                                    }
                                    if (result.isWindow) {
                                      return _buildWindowResult(context, theme, result.window!, index, isSelected);
                                    }
                                    return _buildQuickActionResult(
                                        context, theme, result.quickAction!, index, isSelected);
                                  },
                                );
                              },
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptySearchState(ThemeData theme, Color accent) {
    final Color onSurface = theme.colorScheme.onSurface;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 44),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: accent.withAlpha(14),
                      borderRadius: BorderRadius.circular(16),
                      // border: Border.all(color: accent.withAlpha(38)),
                    ),
                    child: Icon(Icons.travel_explore_rounded, color: accent, size: 26),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'You can search by category',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: onSurface,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: <Widget>[
                      _buildSearchHintChip(
                        label: '/timers',
                        caption: 'quick action',
                        accent: accent,
                        onSurface: onSurface,
                      ),
                      _buildSearchHintChip(
                        label: '?brave',
                        caption: 'file search (or >)',
                        accent: accent,
                        onSurface: onSurface,
                      ),
                      _buildSearchHintChip(
                        label: '.discord',
                        caption: 'window search',
                        accent: accent,
                        onSurface: onSurface,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSearchHintChip({
    required String label,
    required String caption,
    required Color accent,
    required Color onSurface,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: RichText(
        text: TextSpan(
          children: <InlineSpan>[
            TextSpan(
              text: '$label  ',
              style: TextStyle(
                color: onSurface,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: caption,
              style: TextStyle(
                color: onSurface.withAlpha(145),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileResult(BuildContext context, ThemeData theme, FileSystemEntity entity, int index, bool isSelected) {
    final Color accent = Color(globalSettings.themeColors.accentColor);

    return _FileSearchListItem(
      entity: entity,
      isSelected: isSelected,
      accent: accent,
      onSurface: theme.colorScheme.onSurface,
      isInHistory: _history.any((SearchHistory h) => h.path == entity.path),
      onTap: () => _openFile(entity.path),
      onHover: () => _activeIndexNotifier.value = index,
      onRemoveFromHistory: () => _removeFromHistory(entity.path),
    );
  }

  Widget _buildQuickActionResult(
      BuildContext context, ThemeData theme, QuickActionMenuEntry quickAction, int index, bool isSelected) {
    final GlobalKey actionKey = _quickActionKeys.putIfAbsent(quickAction.id, () => GlobalKey());
    final Color accent = Color(globalSettings.themeColors.accentColor);
    final bool showSplash = _quickActionSplashId == quickAction.id;

    return MouseRegion(
      onHover: (PointerHoverEvent event) {
        if (event.delta != Offset.zero) {
          _activeIndexNotifier.value = index;
        }
      },
      child: Container(
        key: ValueKey<String>(quickAction.id),
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: showSplash
              ? accent.withAlpha(90)
              : isSelected
                  ? theme.highlightColor
                  : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: KeyedSubtree(
          key: actionKey,
          child: quickAction.builder(context),
        ),
      ),
    );
  }

  Widget _buildWindowResult(BuildContext context, ThemeData theme, Window window, int index, bool isSelected) {
    final Color accent = Color(globalSettings.themeColors.accentColor);
    return _WindowSearchListItem(
      window: window,
      isSelected: isSelected,
      accent: accent,
      onSurface: theme.colorScheme.onSurface,
      onTap: () => _openWindow(window),
      onHover: () => _activeIndexNotifier.value = index,
    );
  }

  Stream<FileSystemEntity> _listWithDepth(Directory dir, int maxDepth, {int currentDepth = 0}) async* {
    if (currentDepth > maxDepth) return;

    Stream<FileSystemEntity> stream;
    try {
      stream = dir.list(recursive: false, followLinks: false);
    } catch (e) {
      return;
    }

    await for (FileSystemEntity entity in stream.handleError((Object e) => null)) {
      yield entity;
      if (entity is Directory && currentDepth < maxDepth) {
        yield* _listWithDepth(entity, maxDepth, currentDepth: currentDepth + 1);
      }
    }
  }
}

class _FileIcon extends StatefulWidget {
  final String path;
  final bool isDirectory;

  const _FileIcon({required this.path, required this.isDirectory});

  @override
  State<_FileIcon> createState() => _FileIconState();
}

class _FileIconState extends State<_FileIcon> {
  static final Map<String, Uint8List?> _iconCache = <String, Uint8List?>{};

  @override
  Widget build(BuildContext context) {
    if (_iconCache.containsKey(widget.path)) {
      return _buildIcon(_iconCache[widget.path]);
    }

    final Uint8List? bytes = WinUtils.extractIcon(widget.path);
    _iconCache[widget.path] = bytes;
    return _buildIcon(bytes);
  }

  Widget _buildIcon(Uint8List? bytes) {
    if (bytes != null && bytes.isNotEmpty) {
      return Image.memory(
        bytes,
        width: 20,
        height: 20,
        errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) {
          return const Icon(Icons.insert_drive_file, size: 20);
        },
      );
    }
    return const Icon(Icons.insert_drive_file, size: 20);
  }
}

class _FileSearchListItem extends StatefulWidget {
  const _FileSearchListItem({
    required this.entity,
    required this.isSelected,
    required this.accent,
    required this.onSurface,
    required this.isInHistory,
    required this.onTap,
    required this.onHover,
    required this.onRemoveFromHistory,
  });

  final FileSystemEntity entity;
  final bool isSelected;
  final Color accent;
  final Color onSurface;
  final bool isInHistory;
  final VoidCallback onTap;
  final VoidCallback onHover;
  final VoidCallback onRemoveFromHistory;

  @override
  State<_FileSearchListItem> createState() => _FileSearchListItemState();
}

class _FileSearchListItemState extends State<_FileSearchListItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final String name = widget.entity.path.split(Platform.pathSeparator).last;
    final bool isDirectory = widget.entity is Directory;
    final bool highlighted = _hovered || widget.isSelected;

    return MouseRegion(
      onHover: (PointerHoverEvent event) {
        if (event.delta != Offset.zero) {
          setState(() => _hovered = true);
          widget.onHover();
        }
      },
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: highlighted ? widget.accent.withAlpha(60) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: <Widget>[
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: highlighted ? 2.5 : 0,
                  height: 22,
                  margin: EdgeInsets.only(right: highlighted ? 7 : 0),
                  decoration: BoxDecoration(
                    color: widget.accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                _FileIcon(path: widget.entity.path, isDirectory: isDirectory),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        name.replaceFirst('.lnk', ''),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: highlighted ? widget.onSurface : widget.onSurface.withAlpha(200),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.entity.path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: highlighted ? widget.onSurface.withAlpha(170) : widget.onSurface.withAlpha(130),
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.isInHistory)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        overlayColor: WidgetStateProperty.resolveWith<Color?>(
                          (Set<WidgetState> states) {
                            if (states.contains(WidgetState.pressed)) {
                              return widget.accent.withAlpha(30);
                            }
                            if (states.contains(WidgetState.hovered) || states.contains(WidgetState.focused)) {
                              return widget.accent.withAlpha(18);
                            }
                            return Colors.transparent;
                          },
                        ),
                        onTap: widget.onRemoveFromHistory,
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: Icon(
                            Icons.close,
                            size: 16,
                            color: widget.onSurface.withAlpha(highlighted ? 185 : 120),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WindowSearchListItem extends StatefulWidget {
  const _WindowSearchListItem({
    required this.window,
    required this.isSelected,
    required this.accent,
    required this.onSurface,
    required this.onTap,
    required this.onHover,
  });

  final Window window;
  final bool isSelected;
  final Color accent;
  final Color onSurface;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  State<_WindowSearchListItem> createState() => _WindowSearchListItemState();
}

class _WindowSearchListItemState extends State<_WindowSearchListItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bool highlighted = _hovered || widget.isSelected;
    final Uint8List? iconBytes = WindowWatcher.icons[widget.window.hWnd];
    final String processName = widget.window.process.exe.replaceFirst('.exe', '');

    return MouseRegion(
      onHover: (PointerHoverEvent event) {
        if (event.delta != Offset.zero) {
          setState(() => _hovered = true);
          widget.onHover();
        }
      },
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: highlighted ? widget.accent.withAlpha(60) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: <Widget>[
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: highlighted ? 2.5 : 0,
                  height: 22,
                  margin: EdgeInsets.only(right: highlighted ? 7 : 0),
                  decoration: BoxDecoration(
                    color: widget.accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                SizedBox(
                  width: 20,
                  height: 20,
                  child: iconBytes != null && iconBytes.isNotEmpty
                      ? Image.memory(
                          iconBytes,
                          width: 20,
                          height: 20,
                          gaplessPlayback: true,
                          errorBuilder: (_, __, ___) => const Icon(Icons.web_asset_sharp, size: 18),
                        )
                      : const Icon(Icons.web_asset_sharp, size: 18),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        widget.window.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: highlighted ? widget.onSurface : widget.onSurface.withAlpha(200),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        processName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: highlighted ? widget.onSurface.withAlpha(170) : widget.onSurface.withAlpha(130),
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.window.isPinned)
                  Icon(
                    Icons.bookmark_rounded,
                    size: 14,
                    color: widget.onSurface.withAlpha(highlighted ? 180 : 130),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
