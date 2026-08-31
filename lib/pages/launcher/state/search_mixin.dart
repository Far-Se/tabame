part of '../../launcher.dart';

// ignore_for_file: annotate_overrides

// ---------------------------------------------------------------------------
// Search and command handling
// ---------------------------------------------------------------------------

mixin _SearchMixin on _LauncherStateMembersMixin {
  static RegExp get _mathShorthandPattern => LauncherState._mathShorthandPattern;
  static RegExp get _mathOperatorPattern => LauncherState._mathOperatorPattern;
  static RegExp get _mathCurrencyShorthandPattern => LauncherState._mathCurrencyShorthandPattern;
  static RegExp get _mediaCommandPrefixPattern => LauncherState._mediaCommandPrefixPattern;
  static List<_MediaCommandAction> get _mediaCommandActions => LauncherState._mediaCommandActions;
  static List<({String id, String label, IconData icon, String command, List<String> aliases})>
      get _spotifyControlActions => LauncherState._spotifyControlActions;
  static RegExp get _mathAssignmentPrefix => LauncherState._mathAssignmentPrefix;

  /// Keeps the user's arrow-key target independently of the visible list.
  /// Async search phases can temporarily publish an empty or shorter list; if
  /// selection lived only in [_activeIndexNotifier], that intermediate frame
  /// would collapse it to zero and the later complete frame could not recover.
  void _rememberKeyboardResultSelection() {
    if (_results.isEmpty) return;
    final int index = _activeIndexNotifier.value.clamp(0, _results.length - 1);
    _hasKeyboardNavigatedCurrentQuery = true;
    _keyboardSelectedResultId = _results[index].id;
    _keyboardSelectedResultIndex = index;
  }

  void _onSearchChanged(String query) {
    user.launcherSearchText = query;

    if (query != _keyboardNavigationQuery) {
      _keyboardNavigationQuery = query;
      _hasKeyboardNavigatedCurrentQuery = false;
      _keyboardSelectedResultId = null;
      _keyboardSelectedResultIndex = 0;
      _pluginKeyboardSelectedItemId = null;
      _pluginKeyboardSelectedIndex = 0;
    }

    // Plugin routing takes precedence: a keyword owns the launcher until the
    // query leaves it. Leaving the keyword tears the plugin down.
    final PluginManifest? plugin = PluginRegistry.matchKeyword(query);
    if (plugin != null) {
      _routeToPlugin(plugin, query);
      return;
    }
    if (_activePlugin != null) _deactivatePlugin();

    _scrollResultsToTopForQuery(query);
    _searchDebounce?.cancel();

    final List<LauncherSearchResultItem>? pluginSuggestions = _pluginKeywordSuggestions(query);
    if (pluginSuggestions != null) {
      _folderBrowsingStack.clear();
      _folderBrowsingQueryStack.clear();
      ++_searchGeneration;
      setState(() {
        _searchMode = LauncherSearchMode.mixed;
        _isSearching = false;
      });
      _setResults(pluginSuggestions, isSearching: false);
      return;
    }

    final LauncherQuery launcherQuery = LauncherQuery.parse(query);
    final LauncherSearchMode searchMode = launcherQuery.mode;
    final String normalizedQuery = launcherQuery.normalized;

    // Folder browsing is supported in desktop, files-only and mixed modes (see
    // isFileBrowsingMode in _runSearch). Only drop the browsing stack when the
    // query switches to a mode that can't browse — otherwise drilling into a
    // folder from file/mixed search would clear the stack before the contents
    // could be listed.
    final bool isFileBrowsingMode = searchMode == LauncherSearchMode.desktopOnly ||
        searchMode == LauncherSearchMode.filesOnly ||
        searchMode == LauncherSearchMode.mixed;
    if (!isFileBrowsingMode && _folderBrowsingStack.isNotEmpty) {
      _folderBrowsingStack.clear();
      _folderBrowsingQueryStack.clear();
    }

    final int gen = ++_searchGeneration;

    final bool isBrowsingFolder = isFileBrowsingMode && _folderBrowsingStack.isNotEmpty;
    if (!isBrowsingFolder && (query.isEmpty || (normalizedQuery.isEmpty && searchMode == LauncherSearchMode.mixed))) {
      setState(() {
        _searchMode = searchMode;
        _isSearching = false;
      });
      _setResults(_shortcutResults(), isSearching: false);
      return;
    }
    final Duration debounce = _debounceForMode(searchMode, normalizedQuery);

    setState(() {
      _searchMode = searchMode;
      _isSearching = true;
    });

    _searchDebounce = Timer(debounce, () {
      if (!mounted || gen != _searchGeneration) return;
      _runSearch(gen, query, normalizedQuery, searchMode);
    });
  }

  Duration _debounceForMode(LauncherSearchMode mode, String normalizedQuery) {
    if (mode == LauncherSearchMode.functionCommand) {
      final String cmd = normalizedQuery.trimLeft().split(RegExp(r'\s+')).first.toLowerCase();
      final _LauncherFunctionCommand? command = _findFunctionCommand(cmd);
      if (command != null && command.debounce > Duration.zero) {
        return command.debounce;
      }
    }
    return const Duration(milliseconds: 100);
  }

  bool _isActiveSearch(int gen) => mounted && gen == _searchGeneration;

  void _runSearch(int requestId, String query, String normalizedQuery, LauncherSearchMode searchMode) {
    if (!_isActiveSearch(requestId)) return;

    final bool isFileBrowsingMode = searchMode == LauncherSearchMode.desktopOnly ||
        searchMode == LauncherSearchMode.filesOnly ||
        searchMode == LauncherSearchMode.mixed;

    if (isFileBrowsingMode && normalizedQuery.isNotEmpty) {
      _syncChangedFoldersAndRefresh(query, normalizedQuery, searchMode);
    }
    final LauncherSearchContext context = LauncherSearchContext(
      token: _searchToken,
      buildContext: this.context,
      requestId: requestId,
      query: query,
      normalizedQuery: normalizedQuery,
      lowerQuery: normalizedQuery.toLowerCase(),
      setSearching: _setSearching,
      setResults: _setResults,
      isActiveSearch: (int requestId, String query, {bool trimLeft = false}) => _isActiveSearch(requestId),
      browsingPath: isFileBrowsingMode && _folderBrowsingStack.isNotEmpty ? _folderBrowsingStack.last : null,
      browsingQuery: isFileBrowsingMode && _folderBrowsingQueryStack.isNotEmpty ? _folderBrowsingQueryStack.last : null,
      canGoBack: isFileBrowsingMode && _folderBrowsingStack.isNotEmpty,
      onBrowseFolder: isFileBrowsingMode ? _browseFolder : null,
      onOpenFolderInExplorer: isFileBrowsingMode ? _openFolderInExplorer : null,
      onGoBack: isFileBrowsingMode && _folderBrowsingStack.isNotEmpty ? _goBackDesktopFolder : null,
    );

    switch (searchMode) {
      case LauncherSearchMode.windowsOnly:
        WindowsSearchHandler.handle(context);
        break;
      case LauncherSearchMode.browserTabsOnly:
        BrowserTabsSearchHandler.handle(context);
        break;
      case LauncherSearchMode.bookmarksOnly:
        BookmarksSearchHandler.handle(context);
        break;
      case LauncherSearchMode.bookmarkOnly:
        _handleBookmarkKindSearch(context, BookmarkResultKind.bookmark);
        break;
      case LauncherSearchMode.cliOnly:
        _handleBookmarkKindSearch(context, BookmarkResultKind.cliBook);
        break;
      case LauncherSearchMode.appsOnly:
        _handleAppSearch(context);
        break;
      case LauncherSearchMode.desktopOnly:
        FolderSearchHandler.handle(context);
        break;
      case LauncherSearchMode.recentOnly:
        RecentSearchHandler.handle(context);
        break;
      case LauncherSearchMode.notionOnly:
        _handleNotionSearch(context);
        break;
      case LauncherSearchMode.obsidianOnly:
        _handleObsidianSearch(context);
        break;
      case LauncherSearchMode.steamOnly:
        _handleSteamSearch(context);
        break;
      case LauncherSearchMode.terminalOnly:
        _handleTerminalSearch(context);
        break;
      case LauncherSearchMode.workspacesOnly:
        _handleWorkspacesSearch(context);
        break;
      case LauncherSearchMode.timerCommand:
        _handleTimerCommand(context);
        break;
      case LauncherSearchMode.functionCommand:
        _handleFunctionCommand(context);
        break;
      case LauncherSearchMode.pluginsOnly:
        _handlePluginListSearch(context);
        break;
      case LauncherSearchMode.mediaCommand:
        _handleMediaCommand(context);
        break;
      case LauncherSearchMode.spotifyCommand:
        _handleSpotifyCommand(context);
        break;
      default:
        if (searchMode == LauncherSearchMode.mixed && _isMathCurrencyShorthand(context.normalizedQuery)) {
          _handleMathCurrencyShorthand(context);
          break;
        }
        if (searchMode == LauncherSearchMode.mixed && _isCurrencyShorthand(context.normalizedQuery)) {
          _handleCurrencyShorthand(context);
          break;
        }
        if (searchMode == LauncherSearchMode.mixed && _isMathShorthand(context.normalizedQuery)) {
          _handleMathShorthand(context);
          break;
        }
        MixedSearchHandler.handle(context, searchMode);
        break;
    }
  }

  /// Lists enabled plugins for the `!` launcher shortcut. The configured
  /// plugin prefix is included so selecting a row hands the effective keyword
  /// to a standalone launcher process.
  void _handlePluginListSearch(LauncherSearchContext context) {
    final String filter = context.normalizedQuery.trim().toLowerCase();
    final List<PluginManifest> plugins = PluginRegistry.manifests.where((PluginManifest plugin) {
      if (!plugin.enabled) return false;
      if (filter.isEmpty) return true;
      return plugin.name.toLowerCase().contains(filter) ||
          plugin.keyword.toLowerCase().contains(filter) ||
          plugin.description.toLowerCase().contains(filter);
    }).toList()
      ..sort((PluginManifest a, PluginManifest b) => a.name.compareTo(b.name));

    if (plugins.isEmpty) {
      context.setResults(<LauncherSearchResultItem>[
        LauncherSearchResultItem.info(LauncherInfoResult(
          id: filter.isEmpty ? 'plugins-empty' : 'plugins-no-match:$filter',
          title: filter.isEmpty ? 'No enabled plugins found' : 'No plugins match "$filter"',
          subtitle:
              filter.isEmpty ? 'Install or enable a plugin to launch it here' : 'Try another plugin name or keyword',
          icon: Icons.extension_off_outlined,
        )),
      ], isSearching: false);
      return;
    }

    context.setResults(
      <LauncherSearchResultItem>[
        for (final PluginManifest plugin in plugins)
          LauncherSearchResultItem.shortcut(LauncherShortcut(
            label: PluginRegistry.launchKeyword(plugin),
            caption: plugin.name,
            prefix: PluginRegistry.launchKeyword(plugin),
            icon: PluginIcons.resolve(plugin.icon),
          )),
      ],
      isSearching: false,
    );
  }

  bool _isCurrencyShorthand(String query) => CurrencyConverterService.looksLikeConversionInput(query);

  /// Routes a bare-word currency shorthand query through the same handler as the
  /// `$cur` function command.
  Future<void> _handleCurrencyShorthand(LauncherSearchContext context) async {
    context.setSearching(true);
    try {
      final List<LauncherSearchResultItem> results =
          await _buildFunctionCurrencyResults(context.normalizedQuery.trim());
      if (!context.isActiveSearch(context.requestId, context.query)) return;
      context.setResults(results, isSearching: false);
    } catch (error) {
      if (!context.isActiveSearch(context.requestId, context.query)) return;
      context.setResults(<LauncherSearchResultItem>[
        LauncherSearchResultItem.info(LauncherInfoResult(
          id: 'currency-shorthand-error:$error',
          title: 'Currency conversion failed',
          subtitle: error.toString(),
          icon: Icons.error_outline_rounded,
        )),
      ], isSearching: false);
    }
  }

  /// Detects a bare-word math expression such as `12*3+4`, treated exactly like
  /// `$c 12*3+4`. Restricted to pure arithmetic so it doesn't hijack ordinary
  /// searches; expressions with variables/functions still need the `$c` command.
  bool _isMathShorthand(String query) {
    final String trimmed = query.trim();
    if (trimmed.isEmpty) return false;
    if (!_mathShorthandPattern.hasMatch(trimmed)) return false;
    if (!RegExp(r'\d').hasMatch(trimmed)) return false;
    return _mathOperatorPattern.hasMatch(trimmed);
  }

  /// Routes a bare-word math expression through the same handler as the `$c`
  /// function command.
  Future<void> _handleMathShorthand(LauncherSearchContext context) async {
    context.setSearching(true);
    try {
      final List<LauncherSearchResultItem> results =
          await _buildFunctionCalculatorResults(context.normalizedQuery.trim());
      if (!context.isActiveSearch(context.requestId, context.query)) return;
      context.setResults(results, isSearching: false);
    } catch (error) {
      if (!context.isActiveSearch(context.requestId, context.query)) return;
      context.setResults(<LauncherSearchResultItem>[
        LauncherSearchResultItem.info(LauncherInfoResult(
          id: 'math-shorthand-error:$error',
          title: 'Calculation failed',
          subtitle: error.toString(),
          icon: Icons.error_outline_rounded,
        )),
      ], isSearching: false);
    }
  }

  /// Detects a math expression with a trailing currency conversion, e.g.
  /// `30 + (3.79*3) usd to ron`, treated as: compute the expression, then
  /// convert the result via the same handler as `$cur`.
  bool _isMathCurrencyShorthand(String query) {
    final String trimmed = query.trim();
    if (trimmed.isEmpty) return false;
    final RegExpMatch? match = _mathCurrencyShorthandPattern.firstMatch(trimmed);
    if (match == null) return false;
    final String expr = match.group(1)!.trim();
    if (!RegExp(r'\d').hasMatch(expr)) return false;
    return _mathOperatorPattern.hasMatch(expr);
  }

  /// Evaluates the arithmetic prefix of a `<expr> <CUR> to <CUR>` query, then
  /// routes the numeric result through the currency conversion handler.
  Future<void> _handleMathCurrencyShorthand(LauncherSearchContext context) async {
    context.setSearching(true);
    final String trimmed = context.normalizedQuery.trim();
    final RegExpMatch? match = _mathCurrencyShorthandPattern.firstMatch(trimmed);
    if (match == null) {
      context.setResults(const <LauncherSearchResultItem>[], isSearching: false);
      return;
    }
    final String expr = match.group(1)!.trim();
    final String fromCurrency = match.group(2)!;
    final String toCurrency = match.group(3)!;
    try {
      final ParserResult mathResult = await Parsers().calculator(expr);
      if (!context.isActiveSearch(context.requestId, context.query)) return;
      if (mathResult.results.isEmpty) {
        context.setResults(<LauncherSearchResultItem>[
          LauncherSearchResultItem.info(LauncherInfoResult(
            id: 'math-currency-shorthand-empty',
            title: mathResult.error.isEmpty ? 'No result' : mathResult.error,
            subtitle: r'ex: 30 + (3.79*3) usd to ron',
            icon: Icons.error_outline_rounded,
          )),
        ], isSearching: false);
        return;
      }
      final String amount = _stripMathAssignmentPrefix(mathResult.results.last);
      final List<LauncherSearchResultItem> results =
          await _buildFunctionCurrencyResults('$amount $fromCurrency to $toCurrency');
      if (!context.isActiveSearch(context.requestId, context.query)) return;
      context.setResults(results, isSearching: false);
    } catch (error) {
      if (!context.isActiveSearch(context.requestId, context.query)) return;
      context.setResults(<LauncherSearchResultItem>[
        LauncherSearchResultItem.info(LauncherInfoResult(
          id: 'math-currency-shorthand-error:$error',
          title: 'Conversion failed',
          subtitle: error.toString(),
          icon: Icons.error_outline_rounded,
        )),
      ], isSearching: false);
    }
  }

  /// Checks for changed watched folders and re-indexes them in the background.
  /// If any folders changed, re-triggers the current search so results reflect
  /// the updated index. Uses a cooldown to avoid hammering the filesystem on
  /// every keystroke.
  Future<void> _syncChangedFoldersAndRefresh(
    String query,
    String normalizedQuery,
    LauncherSearchMode searchMode,
  ) async {
    // Only one sync at a time, and no more than once every 5 seconds.
    if (_isFolderSyncing || FileIndexer.instance.isIndexing) return;
    final DateTime now = DateTime.now();
    if (_lastFolderSyncTime != null && now.difference(_lastFolderSyncTime!) < const Duration(seconds: 5)) {
      return;
    }

    _isFolderSyncing = true;
    _lastFolderSyncTime = now;

    try {
      final List<String> changedFolders = await FolderWatch.getChangedFolders();
      if (changedFolders.isEmpty) return;

      // Re-index every changed root folder.
      final List<SearchFolder> allRoots = Boxes.searchFolders;
      for (final SearchFolder config in allRoots) {
        if (changedFolders.any((String changed) => config.path == changed || changed.startsWith(config.path))) {
          await FileIndexer.instance.syncFolder(config);
        }
      }

      // If the user is still searching the same query, re-run it against the
      // freshly updated index.
      if (!mounted) return;
      final String currentQuery = _controller.text;
      if (currentQuery == query) {
        // Re-run as the *current* generation so the in-handler guards
        // (_isActiveSearch compares against _searchGeneration) actually pass.
        _runSearch(_searchGeneration, query, normalizedQuery, searchMode);
      }
    } catch (e) {
      debugPrint('Launcher: background folder sync failed: $e');
    } finally {
      _isFolderSyncing = false;
    }
  }

  void _handleBookmarkKindSearch(LauncherSearchContext context, BookmarkResultKind kind) {
    // "b add <target>" saves a new bookmark: it lists every category so the user
    // can pick where the target lands (arrows/click). See _handleBookmarkAddCommand.
    if (kind == BookmarkResultKind.bookmark) {
      final String? addTarget = _parseBookmarkAddTarget(context.normalizedQuery);
      if (addTarget != null) {
        _handleBookmarkAddCommand(context, addTarget);
        return;
      }
    }

    final List<LauncherSearchResultItem> results = findBookmarkMatches(
      context.normalizedQuery,
      includeAllOnEmpty: context.normalizedQuery.isEmpty,
      kinds: <BookmarkResultKind>{kind},
    ).map(LauncherSearchResultItem.bookmark).toList();
    context.setResults(results, isSearching: false);
  }

  /// Recognises the `add` sub-command of bookmark search (`b add <target>`).
  /// Returns the (possibly empty) target to save, or null when the query isn't
  /// an add command so normal bookmark search runs.
  String? _parseBookmarkAddTarget(String normalizedQuery) {
    final String trimmed = normalizedQuery.trimRight();
    final String lower = trimmed.toLowerCase();
    if (lower == 'add') return '';
    if (lower.startsWith('add ')) return trimmed.substring(4).trim();
    return null;
  }

  /// Builds the category picker for `b add <target>`: one row per bookmark
  /// category, each of which saves [target] into that category when chosen.
  void _handleBookmarkAddCommand(LauncherSearchContext context, String target) {
    final List<BookmarkGroup> groups = Boxes().bookmarks;
    final List<LauncherSearchResultItem> results = <LauncherSearchResultItem>[];

    if (target.isEmpty) {
      results.add(const LauncherSearchResultItem.info(LauncherInfoResult(
        id: 'bookmark-add-hint',
        title: 'Type what to save',
        subtitle: "b add https://example.com  —  then pick a category",
        icon: Icons.add_link_rounded,
      )));
    } else {
      results.add(LauncherSearchResultItem.info(LauncherInfoResult(
        id: 'bookmark-add-target',
        title: 'Add "$target"',
        subtitle: 'Choose a category below',
        icon: Icons.add_link_rounded,
      )));
    }

    // Index of the first category row: the leading info header sits above it.
    final int firstCategoryIndex = results.length;

    if (groups.isEmpty) {
      results.add(const LauncherSearchResultItem.info(LauncherInfoResult(
        id: 'bookmark-add-empty',
        title: 'No bookmark categories yet',
        subtitle: 'Create one from the Bookmarks panel first',
        icon: Icons.folder_off_rounded,
      )));
    } else {
      for (int i = 0; i < groups.length; i++) {
        results.add(_buildBookmarkAddCategoryRow(groups[i], target));
      }
    }

    context.setResults(results, isSearching: false);
    // Skip past the info header so a category is highlighted and Enter saves
    // straight away.
    if (groups.isNotEmpty && firstCategoryIndex < results.length) {
      _activeIndexNotifier.value = firstCategoryIndex;
    }
  }

  /// A single category row in the `b add` picker. Selecting it saves [target]
  /// into [group].
  LauncherSearchResultItem _buildBookmarkAddCategoryRow(BookmarkGroup group, String target) {
    void execute() => unawaited(_addBookmarkToCategory(group.title, target));

    final String emoji = group.emoji.isNotEmpty ? group.emoji : '📁';
    final int count = group.bookmarks.length;
    final String name = '$emoji  ${group.title.isEmpty ? 'Untitled' : group.title}  ·  $count';

    return LauncherSearchResultItem.quickAction(
      QuickActionMenuEntry(
        id: 'bookmark_add_category:${group.title}',
        title: 'Add to ${group.title}',
        searchTerms: <String>['add', 'bookmark', group.title],
        allowRenderedFallbackExecute: true,
        onExecute: execute,
        builder: (BuildContext ctx) {
          final ThemeData theme = Theme.of(ctx);
          return QuickActionListItem(
            name: name,
            accent: theme.colorScheme.primary,
            onSurface: theme.colorScheme.onSurface,
            leading: SizedBox(
              width: 18,
              child: Icon(Icons.create_new_folder_rounded, size: 14, color: theme.colorScheme.primary),
            ),
            onTap: execute,
          );
        },
      ),
    );
  }

  /// Persists a new bookmark holding [rawTarget] under the category titled
  /// [categoryTitle]. Websites get "Prefer Input Icons" so their favicon shows.
  Future<void> _addBookmarkToCategory(String categoryTitle, String rawTarget) async {
    final String target = rawTarget.trim();
    if (target.isEmpty) {
      _flashLauncherInfo('Type what to save first', icon: Icons.info_outline_rounded);
      return;
    }

    // Re-read the persisted groups so we serialize the whole, current list back
    // (the settings file is a single whole-file store — see boxes_base).
    final List<BookmarkGroup> groups = Boxes().bookmarks;
    final int index = groups.indexWhere((BookmarkGroup g) => g.title == categoryTitle);
    if (index == -1) {
      _flashLauncherInfo('Category no longer exists', icon: Icons.error_outline_rounded);
      return;
    }

    final bool isWebsite = _looksLikeWebsite(target);
    groups[index].bookmarks.add(BookmarkInfo(
          emoji: isWebsite ? '🌐' : '🔖',
          title: _deriveBookmarkTitle(target, isWebsite),
          stringToExecute: target,
          preferInputIcon: isWebsite,
        ));

    await Boxes.updateSettings('projects', jsonEncode(groups));
    if (!mounted) return;

    _flashLauncherInfo('Saved to ${groups[index].title}');
    // Clear the query back to the launcher home so the picker dismisses.
    _controller.text = '';
    _controller.selection = const TextSelection.collapsed(offset: 0);
    _onSearchChanged('');
    _focusSearch();
  }

  /// Heuristic for "this target is a web address" (drives favicon icons).
  bool _looksLikeWebsite(String target) {
    final String t = target.trim().toLowerCase();
    if (t.startsWith('http://') || t.startsWith('https://') || t.startsWith('www.')) return true;
    // Local paths / files are not websites.
    if (t.contains('\\') || t.contains(':/') || t.startsWith('/') || t.contains(' ')) return false;
    // domain-like: name.tld optionally followed by a path.
    return RegExp(r'^[a-z0-9.-]+\.[a-z]{2,}(/.*)?$').hasMatch(t);
  }

  /// Picks a readable title for the saved bookmark: the host for a website,
  /// otherwise the last path segment.
  String _deriveBookmarkTitle(String target, bool isWebsite) {
    if (isWebsite) {
      try {
        final Uri uri = Uri.parse(target.contains('://') ? target : 'https://$target');
        String host = uri.host;
        if (host.startsWith('www.')) host = host.substring(4);
        if (host.isNotEmpty) return host;
      } catch (_) {}
    }
    final List<String> segments =
        target.replaceAll('\\', '/').split('/').where((String s) => s.trim().isNotEmpty).toList();
    return segments.isEmpty ? target : segments.last;
  }

  /// Shows a transient confirmation chip in the launcher's search bar.
  void _flashLauncherInfo(String text, {IconData icon = Icons.check_circle_outline_rounded}) {
    _infoTimer?.cancel();
    setState(() {
      _infoText = text;
      _infoIcon = icon;
    });
    _infoTimer = Timer(const Duration(milliseconds: 2200), () {
      _infoTimer = null;
      if (mounted) {
        setState(() {
          _infoText = null;
          _infoIcon = null;
        });
      }
    });
  }

  void _handleAppSearch(LauncherSearchContext context) {
    final List<LauncherSearchResultItem> bookmarkResults = findBookmarkMatches(
      context.normalizedQuery,
      includeAllOnEmpty: context.normalizedQuery.isEmpty,
      kinds: const <BookmarkResultKind>{BookmarkResultKind.appItem},
    ).map(LauncherSearchResultItem.bookmark).toList();

    List<SearchResultNode> appNodes;
    if (context.normalizedQuery.isEmpty) {
      appNodes = FileIndexDb.instance.getTopOpened(
        limit: maxLauncherMatches,
        entryTypes: const <SearchResultEntryType>{SearchResultEntryType.app},
      ).toList();

      if (appNodes.length < maxLauncherMatches) {
        final int? rootId = FileIndexDb.instance.findNode(null, FileIndexDb.launcherAppsRootName);
        if (rootId != null) {
          final Set<String> existingAumids = appNodes
              .map((SearchResultNode node) => node.appUserModelId ?? '')
              .where((String appUserModelId) => appUserModelId.isNotEmpty)
              .toSet();

          for (final SearchResultNode node in FileIndexDb.instance.getChildNodes(rootId)) {
            final String appUserModelId = node.appUserModelId ?? '';
            if (!node.isApp || appUserModelId.isEmpty || existingAumids.contains(appUserModelId)) continue;
            appNodes.add(node);
            existingAumids.add(appUserModelId);
            if (appNodes.length >= maxLauncherMatches) break;
          }
        }
      }
    } else {
      appNodes = FileIndexDb.instance.search(
        context.normalizedQuery,
        limit: maxLauncherMatches,
        entryTypes: const <SearchResultEntryType>{SearchResultEntryType.app},
      );
    }

    final List<LauncherSearchResultItem> appResults = deserializeSearchMatches(appNodes);
    context.setResults(<LauncherSearchResultItem>[
      ...bookmarkResults,
      ...appResults,
    ], isSearching: false);
  }

  void _handleTimerCommand(LauncherSearchContext context) {
    final _ParsedLauncherTimer? timer = _parseTimerCommand(context.query);
    if (timer == null) {
      context.setResults(<LauncherSearchResultItem>[
        const LauncherSearchResultItem.info(LauncherInfoResult(
          id: 'timer-help',
          title: 'Create a timer',
          subtitle: 'Type timer {minute} {message}',
          icon: Icons.timer_outlined,
        )),
      ], isSearching: false);
      return;
    }

    context.setResults(<LauncherSearchResultItem>[
      LauncherSearchResultItem.quickAction(_buildTimerQuickAction(timer)),
    ], isSearching: false);
  }

  _ParsedLauncherTimer? _parseTimerCommand(String query) {
    final RegExpMatch? match = RegExp(r'^timer\s+(\d+)\s+(.+)$', caseSensitive: false).firstMatch(query.trim());
    if (match == null) return null;

    final int? minutes = int.tryParse(match.group(1)!);
    final String message = match.group(2)!.trim();
    if (minutes == null || minutes <= 0 || message.isEmpty) return null;
    return _ParsedLauncherTimer(minutes: minutes, message: message);
  }

  QuickActionMenuEntry _buildTimerQuickAction(_ParsedLauncherTimer timer) {
    return QuickActionMenuEntry(
      id: 'timer:${timer.minutes}:${timer.message}',
      title: 'Create ${timer.minutes} minute timer',
      searchTerms: <String>['timer', timer.message],
      onExecute: () => _createLauncherTimer(timer),
      builder: (BuildContext context) {
        final ThemeData theme = Theme.of(context);
        final Color accent = Design.accent;
        final Color onSurface = theme.colorScheme.onSurface;
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _createLauncherTimer(timer),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: <Widget>[
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withAlpha(24),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.timer_outlined, size: 18, color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Create ${timer.minutes} minute timer',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        timer.message,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: onSurface.withAlpha(140),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.keyboard_return_rounded, size: 14, color: onSurface.withAlpha(100)),
              ],
            ),
          ),
        );
      },
    );
  }

  void _handleMediaCommand(LauncherSearchContext context) {
    final RegExpMatch? prefixMatch = _mediaCommandPrefixPattern.firstMatch(context.query);
    final int? audioIndex = prefixMatch?.group(1) != null ? int.parse(prefixMatch!.group(1)!) - 1 : null;
    final String input = context.normalizedQuery.trim().toLowerCase();

    final List<_MediaCommandAction> matches = input.isEmpty
        ? _mediaCommandActions
        : _mediaCommandActions.where((_MediaCommandAction action) => action.matches(input)).toList();

    if (matches.isEmpty) {
      context.setResults(<LauncherSearchResultItem>[
        const LauncherSearchResultItem.info(LauncherInfoResult(
          id: 'media-no-match',
          title: 'No media command found',
          subtitle: 'Try stop, play/pause, next, or previous',
          icon: Icons.music_note_rounded,
        )),
      ], isSearching: false);
      return;
    }

    context.setResults(
      matches
          .map((_MediaCommandAction action) => LauncherSearchResultItem.quickAction(
                _buildMediaCommandAction(action, audioIndex),
              ))
          .toList(growable: false),
      isSearching: false,
    );
  }

  QuickActionMenuEntry _buildMediaCommandAction(_MediaCommandAction action, int? audioIndex) {
    final String subtitle = audioIndex != null && audioIndex < Boxes.appAudioControls.length
        ? Boxes.appAudioControls[audioIndex].name
        : 'Global media control';
    return _buildFunctionAction(
      id: 'media:${action.id}:${audioIndex ?? 'global'}',
      title: action.label,
      subtitle: subtitle,
      icon: action.icon,
      searchTerms: <String>[action.label, ...action.aliases],
      onExecute: () => _executeMediaCommand(action, audioIndex),
    );
  }

  void _executeMediaCommand(_MediaCommandAction action, int? audioIndex) {
    if (audioIndex != null && audioIndex >= 0 && audioIndex < Boxes.appAudioControls.length) {
      final AppAudioControl ctl = Boxes.appAudioControls[audioIndex];
      final bool hasWindow = WindowWatcherService.instance.containsExecutable(ctl.exe) ||
          TrayWatcher.trayList.any((TrayBarInfo t) => t.processExe == ctl.exe);
      final String? appHotkey = switch (action.id) {
        'next' => ctl.hotkeyNext,
        'previous' => ctl.hotkeyPrev,
        'playPause' => ctl.hotkeyPause,
        _ => null,
      };
      if (hasWindow && appHotkey != null && appHotkey.isNotEmpty) {
        WinKeys.send(appHotkey);
        _finishLauncherFunctionExecution();
        return;
      }
    }
    WinKeys.single(action.vk, KeySentMode.normal);
    _finishLauncherFunctionExecution();
  }

  Future<void> _handleSpotifyCommand(LauncherSearchContext context) async {
    context.setSearching(true);

    final PlatformMediaSession? session = await SpotifyController.fetchSession();
    if (!context.isActiveSearch(context.requestId, context.query)) return;

    if (session == null) {
      context.setResults(<LauncherSearchResultItem>[
        LauncherSearchResultItem.quickAction(_buildFunctionAction(
          id: 'spotify:launch',
          title: 'Open Spotify',
          subtitle: "Spotify isn't running — launch it",
          icon: Icons.launch_rounded,
          searchTerms: <String>['spotify', 'open', 'launch'],
          onExecute: () {
            SpotifyController.launchApp();
            _finishLauncherFunctionExecution();
          },
        )),
      ], isSearching: false);
      return;
    }

    final String input = context.normalizedQuery.trim().toLowerCase();
    final List<({String id, String label, IconData icon, String command, List<String> aliases})> matches = input.isEmpty
        ? _spotifyControlActions
        : _spotifyControlActions
            .where((({String id, String label, IconData icon, String command, List<String> aliases}) a) =>
                a.aliases.any((String alias) => alias.startsWith(input)))
            .toList(growable: false);

    final List<LauncherSearchResultItem> results = <LauncherSearchResultItem>[
      // Now-playing hero row is always shown; Enter on it toggles play/pause.
      if (input.isEmpty) LauncherSearchResultItem.quickAction(_buildSpotifyNowPlaying(session)),
      for (final ({String id, String label, IconData icon, String command, List<String> aliases}) action in matches)
        LauncherSearchResultItem.quickAction(_buildFunctionAction(
          id: 'spotify:${action.id}',
          title: action.label,
          subtitle: '${session.title} — ${session.artist}',
          icon: action.icon,
          searchTerms: <String>[action.label, ...action.aliases],
          onExecute: () => _executeSpotifyCommand(session, action.command),
        )),
    ];

    if (results.isEmpty) {
      context.setResults(<LauncherSearchResultItem>[
        const LauncherSearchResultItem.info(LauncherInfoResult(
          id: 'spotify-no-match',
          title: 'No Spotify command found',
          subtitle: 'Try play/pause, next, or previous',
          icon: Icons.music_note_rounded,
        )),
      ], isSearching: false);
      return;
    }

    context.setResults(results, isSearching: false);
  }

  QuickActionMenuEntry _buildSpotifyNowPlaying(PlatformMediaSession session) {
    final ImageProvider? art = session.artworkBytes == null ? null : MemoryImage(session.artworkBytes!);
    return QuickActionMenuEntry(
      id: 'spotify:nowPlaying',
      title: session.title,
      searchTerms: <String>[session.title, session.artist, 'spotify', 'now playing'],
      onExecute: () => _executeSpotifyCommand(session, SpotifyController.cmdTogglePlayPause),
      builder: (BuildContext context) {
        final ThemeData theme = Theme.of(context);
        final Color accent = Design.accent;
        final Color onSurface = theme.colorScheme.onSurface;
        final String title = session.title.isEmpty ? 'Spotify' : session.title;
        final String artist = session.artist.isEmpty ? 'Unknown artist' : session.artist;
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _executeSpotifyCommand(session, SpotifyController.cmdTogglePlayPause),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: art != null
                        ? Image(image: art, fit: BoxFit.cover)
                        : Container(
                            color: accent.withAlpha(24),
                            child: Icon(Icons.music_note_rounded, size: 20, color: accent),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: onSurface.withAlpha(140),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  session.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 20,
                  color: accent,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _executeSpotifyCommand(PlatformMediaSession session, String command) {
    unawaited(SpotifyController.command(session, command));
    _finishLauncherFunctionExecution();
  }

  void _createLauncherTimer(_ParsedLauncherTimer timer) {
    Boxes().addQuickTimer(timer.message, timer.minutes, 1);
    // final SavedQuickTimers savedTimer = SavedQuickTimers()
    //   ..name = timer.message
    //   ..minutes = timer.minutes
    //   ..type = 1;
    // Boxes.lastQuickTimers.add(savedTimer);
    // Boxes.lastQuickTimers.sort((SavedQuickTimers a, SavedQuickTimers b) => a.minutes - b.minutes);
    // if (Boxes.lastQuickTimers.length > 20) {
    //   Boxes.lastQuickTimers.removeRange(0, Boxes.lastQuickTimers.length - 20);
    // }
    // Boxes().saveLatestQuickTimers();
    _finishLauncherFunctionExecution();
  }

  void _finishLauncherFunctionExecution() {
    user.launcherSearchText = '';
    Globals.quickMenuPage = QuickMenuPage.quickMenu;

    if (mounted) {
      _controller.clear();
      _setResults(_shortcutResults(), isSearching: false);
      _focusSearch();
    }

    if (kReleaseMode) {
      QuickMenuFunctions.hideQuickMenu();
    }
  }

  Future<void> _handleFunctionCommand(LauncherSearchContext context) async {
    final String input = context.normalizedQuery.trimLeft();
    if (input.isEmpty) {
      context.setResults(_buildFunctionSuggestions(''), isSearching: false);
      return;
    }

    final List<String> parts = input.split(RegExp(r'\s+'));
    final String commandName = parts.first.toLowerCase();
    final String commandInput =
        input.length == commandName.length ? '' : input.substring(commandName.length).trimLeft();
    final _LauncherFunctionCommand? command = _findFunctionCommand(commandName);

    if (command == null) {
      context.setResults(_buildFunctionSuggestions(input), isSearching: false);
      return;
    }

    // NOTE: command.debounce is already applied by _debounceForMode before
    // _runSearch fires, so we must NOT delay again here (that doubled latency).
    context.setSearching(true);
    try {
      // Streaming handlers own the context and push results incrementally.
      if (command.streamingHandler != null) {
        await command.streamingHandler!(commandInput, context);
        return;
      }
      final List<LauncherSearchResultItem> results = await command.handler!(commandInput);
      if (!context.isActiveSearch(context.requestId, context.query)) return;
      context.setResults(results, isSearching: false);
    } catch (error) {
      if (!context.isActiveSearch(context.requestId, context.query)) return;
      context.setResults(<LauncherSearchResultItem>[
        LauncherSearchResultItem.info(LauncherInfoResult(
          id: 'function-error:${command.name}:$error',
          title: '${command.name} failed',
          subtitle: error.toString(),
          icon: Icons.error_outline_rounded,
        )),
      ], isSearching: false);
    }
  }

  _LauncherFunctionCommand? _findFunctionCommand(String name) {
    for (final _LauncherFunctionCommand command in _functionCommands) {
      if (command.matchesName(name)) return command;
    }
    return null;
  }

  List<LauncherSearchResultItem> _buildFunctionSuggestions(String query) {
    final String normalized = query.toLowerCase().replaceFirst(RegExp(r'^\$'), '').trim();
    final List<_LauncherFunctionCommand> matches = normalized.isEmpty
        ? _functionCommands
        : _functionCommands.where((_LauncherFunctionCommand command) => command.matchesQuery(normalized)).toList();
    if (matches.isEmpty) {
      return <LauncherSearchResultItem>[
        const LauncherSearchResultItem.info(LauncherInfoResult(
          id: 'function-no-match',
          title: 'No function found',
          subtitle: r'Try $timer, $translate, $unit, $cur, or $c',
          icon: Icons.functions_rounded,
        )),
      ];
    }
    return matches.map((_LauncherFunctionCommand command) {
      return LauncherSearchResultItem.quickAction(_buildFunctionSuggestionAction(command));
    }).toList(growable: false);
  }

  QuickActionMenuEntry _buildFunctionSuggestionAction(_LauncherFunctionCommand command) {
    return _buildFunctionAction(
      id: 'function-help:${command.name}',
      title: command.name,
      subtitle: '${command.description} - ${command.usage}',
      icon: command.icon,
      searchTerms: <String>[command.name, command.description, command.usage, ...command.aliases],
      onExecute: () {
        _controller.text = '\$${command.name} ';
        // _controller.selection = TextSelection.fromPosition(TextPosition(offset: _controller.text.length));
        _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
        _onSearchChanged(_controller.text);
        _focusSearch();
      },
    );
  }

  Future<List<LauncherSearchResultItem>> _buildFunctionTimerResults(String input) async {
    final _ParsedLauncherTimer? timer = _parseFunctionTimerCommand(input);
    if (timer == null) {
      return <LauncherSearchResultItem>[
        const LauncherSearchResultItem.info(LauncherInfoResult(
          id: 'function-timer-help',
          title: r'Type $timer {minutes} {message}',
          subtitle: r'Example: $timer 1 stretch',
          icon: Icons.timer_outlined,
        )),
      ];
    }
    return <LauncherSearchResultItem>[LauncherSearchResultItem.quickAction(_buildTimerQuickAction(timer))];
  }

  _ParsedLauncherTimer? _parseFunctionTimerCommand(String input) {
    final RegExpMatch? match = RegExp(r'^(\d+)\s+(.+)$', caseSensitive: false).firstMatch(input.trim());
    if (match == null) return null;
    final int? minutes = int.tryParse(match.group(1)!);
    final String message = match.group(2)!.trim();
    if (minutes == null || minutes <= 0 || message.isEmpty) return null;
    return _ParsedLauncherTimer(minutes: minutes, message: message);
  }

  Future<List<LauncherSearchResultItem>> _buildFunctionClearResults(String input) async {
    if (input.trim().isEmpty) {
      return <LauncherSearchResultItem>[
        const LauncherSearchResultItem.info(LauncherInfoResult(
          id: 'function-clear-help-icon',
          title: r'$clear icon',
          subtitle: 'Removes Icon Cache',
          icon: Icons.cleaning_services_rounded,
        )),
        const LauncherSearchResultItem.info(LauncherInfoResult(
          id: 'function-clear-help-icon-extension',
          title: r'$clear iconext',
          subtitle: 'Removes Icon Cache for Extensions only',
          icon: Icons.cleaning_services_rounded,
        )),
        const LauncherSearchResultItem.info(LauncherInfoResult(
          id: 'function-clear-help-auth-logo',
          title: r'$clear authlogo',
          subtitle: 'Removes Authenticator Logos Cache',
          icon: Icons.cleaning_services_rounded,
        )),
        const LauncherSearchResultItem.info(LauncherInfoResult(
          id: 'function-clear-help',
          title: r'$clear all',
          subtitle: 'Removes all cache folder',
          icon: Icons.cleaning_services_rounded,
        )),
      ];
    }
    if (input.trim().toLowerCase() == 'icon') {
      return <LauncherSearchResultItem>[
        LauncherSearchResultItem.quickAction(_buildFunctionAction(
          id: 'function-clear-icon-cache',
          title: 'Clear icon cache',
          subtitle: AppPaths.cachePath('icon_cache').lastChars(35),
          icon: Icons.cleaning_services_rounded,
          searchTerms: const <String>['clear', 'cache', 'icon'],
          onExecute: () => unawaited(_clearCacheFolder('icon_cache')),
        )),
      ];
    }
    if (input.trim().toLowerCase() == 'iconext') {
      return <LauncherSearchResultItem>[
        LauncherSearchResultItem.quickAction(_buildFunctionAction(
          id: 'function-clear-help-icon-extension',
          title: 'Removes Icon Cache for Extensions only',
          subtitle: AppPaths.cachePath(p.join('icon_cache', 'file_formats')).lastChars(35),
          icon: Icons.cleaning_services_rounded,
          searchTerms: const <String>['clear', 'cache', 'icon', 'ext'],
          onExecute: () => unawaited(_clearCacheFolder(p.join('icon_cache', 'file_formats'))),
        )),
      ];
    } else if (input.trim().toLowerCase() == 'authlogo') {
      return <LauncherSearchResultItem>[
        LauncherSearchResultItem.quickAction(_buildFunctionAction(
          id: 'function-clear-authlogo-cache',
          title: 'Clear authlogo cache',
          subtitle: AppPaths.cachePath('authenticator logos').lastChars(35),
          icon: Icons.cleaning_services_rounded,
          searchTerms: const <String>['clear', 'cache', 'icon'],
          onExecute: () => unawaited(_clearCacheFolder('authenticator logos')),
        )),
      ];
    } else if (input.trim().toLowerCase() == 'all') {
      return <LauncherSearchResultItem>[
        LauncherSearchResultItem.quickAction(_buildFunctionAction(
          id: 'function-clear-all',
          title: 'Clear all cache folder',
          subtitle: AppPaths.cachePath('').lastChars(35),
          icon: Icons.cleaning_services_rounded,
          searchTerms: const <String>['clear', 'cache'],
          onExecute: () => unawaited(_clearCacheFolder("")),
        )),
      ];
    }
    return <LauncherSearchResultItem>[];
  }

  Future<void> _clearCacheFolder(String folder) async {
    final Directory cacheDirectory = Directory(AppPaths.cachePath(folder, forWrite: true));
    if (cacheDirectory.existsSync()) {
      cacheDirectory.deleteSync(recursive: true);
      cacheDirectory.createSync();
    }
    // if (await cacheDirectory.exists()) {
    //   await for (final FileSystemEntity entity in cacheDirectory.list()) {
    //     await entity.delete(recursive: true);
    //   }
    // }
    _finishLauncherFunctionExecution();
  }

  // ignore: unused_element
  Future<List<LauncherSearchResultItem>> _buildFunctionReloadSettingsResults(String input) async {
    if (input.trim().toLowerCase() != 'settings') {
      return <LauncherSearchResultItem>[
        const LauncherSearchResultItem.info(LauncherInfoResult(
          id: 'function-reload-help',
          title: r'Type $reload settings',
          subtitle: 'This command needs the full target before it can run.',
          icon: Icons.keyboard_outlined,
        )),
      ];
    }
    return <LauncherSearchResultItem>[
      LauncherSearchResultItem.quickAction(_buildFunctionAction(
        id: 'function-reload-settings',
        title: 'Reload settings',
        icon: Icons.keyboard_outlined,
        subtitle: '',
        searchTerms: const <String>['reload', 'settings'],
        onExecute: () {
          Boxes.reloadSettings();
        },
      )),
    ];
  }

  Future<List<LauncherSearchResultItem>> _buildFunctionReindexResults(String input) async {
    if (input.trim().toLowerCase() != 'files') {
      return <LauncherSearchResultItem>[
        const LauncherSearchResultItem.info(LauncherInfoResult(
          id: 'function-reindex-help',
          title: r'Type $reindex files',
          subtitle: 'This command needs the full target before it can run.',
          icon: Icons.manage_search_rounded,
        )),
      ];
    }
    return <LauncherSearchResultItem>[
      LauncherSearchResultItem.quickAction(_buildFunctionAction(
        id: 'function-reindex-files',
        title: 'Reindex all launcher files',
        subtitle: '${Boxes.searchFolders.length} search source${Boxes.searchFolders.length == 1 ? '' : 's'} configured',
        icon: Icons.manage_search_rounded,
        searchTerms: const <String>['reindex', 'files'],
        onExecute: () {
          FileIndexer.instance.fullReindex();
          _finishLauncherFunctionExecution();
        },
      )),
    ];
  }

  Future<List<LauncherSearchResultItem>> _buildFunctionCalculatorResults(String input) async {
    return _buildParserFunctionResults(
      idPrefix: 'function-calc',
      input: input,
      emptyHelp: r'$c 1+3/5  •  Tip: just type 1+3/5 (no $c needed)',
      icon: Icons.calculate_rounded,
      parser: Parsers().calculator,
      stripAssignmentPrefix: true,
      closeAfterCopy: false,
    );
  }

  Future<List<LauncherSearchResultItem>> _buildFunctionDesignResults(String input) async {
    final String trimmed = input.trim().toLowerCase();

    LauncherDesign? findDesign(String name) {
      for (final LauncherDesign d in LauncherDesign.values) {
        if (d.name.toLowerCase() == name) return d;
      }
      return null;
    }

    void applyDesign(LauncherDesign design) {
      unawaited(Boxes.switchLauncherDesign(design));
      setState(() => _design = design);
      _onSearchChanged(_controller.text);
      // The new design replaces the search field. Restore focus after that
      // field has attached, then retry after the search debounce/rebuild.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _requestLauncherFocus();
      });
      Future<void>.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _requestLauncherFocus();
        }
      });
    }

    if (trimmed.isNotEmpty) {
      final LauncherDesign? matched = findDesign(trimmed);
      if (matched != null) {
        return <LauncherSearchResultItem>[
          LauncherSearchResultItem.quickAction(_buildFunctionAction(
            id: 'function-design-apply:${matched.name}',
            title: 'Switch to ${matched.name[0].toUpperCase()}${matched.name.substring(1)} design',
            subtitle: matched == _design ? 'Currently active' : 'Launcher design',
            icon: Icons.palette_outlined,
            searchTerms: <String>['design', matched.name],
            onExecute: () => applyDesign(matched),
          )),
        ];
      }
    }

    return LauncherDesign.values.map((LauncherDesign d) {
      final bool isActive = d == _design;
      return LauncherSearchResultItem.quickAction(_buildFunctionAction(
        id: 'function-design:${d.name}',
        title: '${d.name[0].toUpperCase()}${d.name.substring(1)}',
        subtitle: isActive ? 'Currently active' : 'Switch to this design',
        icon: isActive ? Icons.check_circle_outline_rounded : Icons.palette_outlined,
        searchTerms: <String>['design', d.name],
        onExecute: () => applyDesign(d),
      ));
    }).toList(growable: false);
  }

  Future<List<LauncherSearchResultItem>> _buildFunctionSystemResults(String input) async {
    final String trimmed = input.trim().toLowerCase();

    final SystemPowerAction? exact = trimmed.isEmpty ? null : SystemPowerAction.byToken(trimmed);
    final List<SystemPowerAction> matches = exact != null
        ? <SystemPowerAction>[exact]
        : trimmed.isEmpty
            ? SystemPowerAction.all
            : SystemPowerAction.all.where((SystemPowerAction a) => a.matchesQuery(trimmed)).toList();

    if (matches.isEmpty) {
      return <LauncherSearchResultItem>[
        const LauncherSearchResultItem.info(LauncherInfoResult(
          id: 'function-sys-help',
          title: 'No system action found',
          subtitle: r'Try $sys shutdown, restart, logoff, lock, sleep or hibernate',
          icon: Icons.power_settings_new_rounded,
        )),
      ];
    }

    return matches.map((SystemPowerAction action) {
      return LauncherSearchResultItem.quickAction(_buildFunctionAction(
        id: 'function-sys:${action.id}',
        title: action.label,
        subtitle: action.description,
        icon: action.icon,
        searchTerms: <String>['sys', action.id, action.label, ...action.aliases],
        onExecute: () {
          action.execute();
          _finishLauncherFunctionExecution();
        },
      ));
    }).toList(growable: false);
  }

  Future<List<LauncherSearchResultItem>> _buildFunctionUnitResults(String input) async {
    return _buildParserFunctionResults(
      idPrefix: 'function-unit',
      input: input,
      emptyHelp: r'Format: $unit 10 km to mi',
      icon: Icons.straighten_rounded,
      parser: Parsers().unit,
    );
  }

  Future<List<LauncherSearchResultItem>> _buildFunctionCurrencyResults(String input) async {
    if (input.trim().isEmpty) {
      return <LauncherSearchResultItem>[
        const LauncherSearchResultItem.info(LauncherInfoResult(
          id: 'function-currency-help',
          title: 'Convert currency',
          subtitle: r'$cur 1 USD to EUR  •  Tip: just type 100 USD to EUR or £100 to €',
          icon: Icons.currency_exchange_rounded,
        )),
      ];
    }

    final String target = Boxes.pref.getString(CurrencyConverterService.toKey) ?? 'eur';
    final CurrencyConversionResult result = await CurrencyConverterService().convert(
      input.trim(),
      defaultTargetCurrency: target,
    );

    return <LauncherSearchResultItem>[
      LauncherSearchResultItem.quickAction(_buildCopyFunctionAction(
        id: 'function-currency:${result.fromCurrency}:${result.toCurrency}:${result.convertedAmount}',
        title: result.convertedLabel,
        subtitle: '${result.fromCurrency.toUpperCase()} (${result.fromName}) to '
            '${result.toCurrency.toUpperCase()} (${result.toName})',
        icon: Icons.currency_exchange_rounded,
        value: result.convertedLabel,
      )),
      LauncherSearchResultItem.quickAction(_buildCopyFunctionAction(
        id: 'function-currency-rate:${result.fromCurrency}:${result.toCurrency}:${result.rate}',
        title: result.rateLabel,
        subtitle: 'Copy exchange rate',
        icon: Icons.currency_exchange_rounded,
        value: result.rateLabel,
      )),
    ];
  }

  Future<List<LauncherSearchResultItem>> _buildParserFunctionResults({
    required String idPrefix,
    required String input,
    required String emptyHelp,
    required IconData icon,
    required Future<ParserResult> Function(String input) parser,
    bool stripAssignmentPrefix = false,
    bool closeAfterCopy = true,
  }) async {
    if (input.trim().isEmpty) {
      return <LauncherSearchResultItem>[
        LauncherSearchResultItem.info(LauncherInfoResult(
          id: '$idPrefix-help',
          title: 'Function format',
          subtitle: emptyHelp,
          icon: icon,
        )),
      ];
    }
    final ParserResult result = await parser(input.trim());
    if (result.results.isEmpty) {
      return <LauncherSearchResultItem>[
        LauncherSearchResultItem.info(LauncherInfoResult(
          id: '$idPrefix-empty',
          title: result.error.isEmpty ? 'No result' : result.error,
          subtitle: emptyHelp,
          icon: icon,
        )),
      ];
    }
    return result.results.take(12).map((String value) {
      final String copyValue = stripAssignmentPrefix ? _stripMathAssignmentPrefix(value) : value;
      return LauncherSearchResultItem.quickAction(_buildCopyFunctionAction(
        id: '$idPrefix:$value',
        title: value,
        subtitle: result.error.isEmpty ? 'Copy result' : result.error,
        icon: icon,
        value: copyValue,
        closeAfterExecute: closeAfterCopy,
      ));
    }).toList(growable: false);
  }

  /// Streaming translate: emits each translation the moment it returns instead
  /// of waiting for the whole batch, so results appear one-by-one.
  Future<void> _streamFunctionTranslateResults(String input, LauncherSearchContext context) async {
    final _ParsedTranslateCommand? parsed = _parseTranslateCommand(input);
    if (parsed == null) {
      context.setResults(const <LauncherSearchResultItem>[
        LauncherSearchResultItem.info(LauncherInfoResult(
          id: 'function-translate-help',
          title: 'Translate text',
          subtitle: r'$t hello (saved langs) • $t hello from en • $t hello from en to ro',
          icon: Icons.translate_rounded,
        )),
      ], isSearching: false);
      return;
    }

    // Skip translating into the explicit source language (no-op identity).
    final List<String> targets =
        parsed.targets.where((String target) => parsed.from == 'auto' || target != parsed.from).toList(growable: false);
    if (targets.isEmpty) {
      context.setResults(const <LauncherSearchResultItem>[], isSearching: false);
      return;
    }

    final GoogleTranslator translator = GoogleTranslator();
    final List<LauncherSearchResultItem> results = <LauncherSearchResultItem>[];
    try {
      for (int i = 0; i < targets.length; i++) {
        final String target = targets[i];
        final GoogleTranslateResponse response = await translator.translate(parsed.text, from: parsed.from, to: target);
        // Bail out if the query moved on while this request was in flight.
        if (!context.isActiveSearch(context.requestId, context.query)) return;
        final String targetName = GoogleTranslator.languages[target] ?? target.toUpperCase();
        final String source = response.from.language.iso.isEmpty ? parsed.from : response.from.language.iso;
        results.add(LauncherSearchResultItem.quickAction(_buildCopyFunctionAction(
          id: 'function-translate:$target:${response.text}',
          title: response.text.isEmpty ? 'No translation returned' : response.text,
          subtitle: '$targetName - from $source',
          icon: Icons.translate_rounded,
          value: response.text,
        )));
        final bool isLast = i == targets.length - 1;
        // Keep the spinner up until the last translation lands; only reset the
        // selection on the first emit so the user's arrow-key position survives.
        context.setResults(
          List<LauncherSearchResultItem>.of(results),
          isSearching: !isLast,
          resetSelection: results.length == 1,
        );
      }
    } finally {
      translator.close();
    }
  }

  _ParsedTranslateCommand? _parseTranslateCommand(String input) {
    final String raw = input.trim();
    if (raw.isEmpty) return null;

    // Defaults come from the Translator panel's saved settings: source language
    // (translatorFromLanguage) and the saved target languages.
    String from = _loadTranslatorFrom();
    List<String> targets = _loadTranslatorTargets();
    String text = raw;

    final RegExpMatch? explicit = RegExp(r'^(.+?)\s+from\s+(.+?)\s+to\s+(.+)$', caseSensitive: false).firstMatch(raw);
    final RegExpMatch? fromOnly = RegExp(r'^(.+?)\s+from\s+(.+)$', caseSensitive: false).firstMatch(raw);

    if (explicit != null) {
      // "<text> from <X> to <Y>" — explicit source and single target.
      final String? parsedFrom = GoogleTranslator.getIsoCode(explicit.group(2)!.trim());
      final String? parsedTo = GoogleTranslator.getIsoCode(explicit.group(3)!.trim());
      if (parsedFrom != null && parsedTo != null) {
        text = _stripQuotes(explicit.group(1)!.trim());
        from = parsedFrom;
        targets = <String>[parsedTo];
      } else {
        text = _stripQuotes(raw);
      }
    } else if (fromOnly != null) {
      // "<text> from <X>" — explicit source, translate to every saved target.
      final String? parsedFrom = GoogleTranslator.getIsoCode(fromOnly.group(2)!.trim());
      if (parsedFrom != null) {
        text = _stripQuotes(fromOnly.group(1)!.trim());
        from = parsedFrom;
      } else {
        text = _stripQuotes(raw);
      }
    } else {
      text = _stripQuotes(raw);
    }

    if (text.isEmpty || targets.isEmpty) return null;
    return _ParsedTranslateCommand(text: text, from: from, targets: targets);
  }

  /// Loads the source language saved by the Translator panel
  /// (`translatorFromLanguage`), falling back to auto-detect.
  String _loadTranslatorFrom() {
    final String? saved = Boxes.pref.getString('translatorFromLanguage');
    if (saved == null || saved == 'auto') return 'auto';
    return GoogleTranslator.languages.containsKey(saved) ? saved : 'auto';
  }

  List<String> _loadTranslatorTargets() {
    final List<String> saved = Boxes.pref.getStringList('translatorTargetLanguages') ?? <String>['en', 'ro'];
    final List<String> valid = saved
        .map(GoogleTranslator.getIsoCode)
        .whereType<String>()
        .where((String code) => code != 'auto')
        .toSet()
        .toList(growable: false);
    return valid.isEmpty ? <String>['en', 'ro'] : valid;
  }

  String _stripQuotes(String value) {
    if (value.length >= 2) {
      final bool doubleQuoted = value.startsWith('"') && value.endsWith('"');
      final bool singleQuoted = value.startsWith("'") && value.endsWith("'");
      if (doubleQuoted || singleQuoted) return value.substring(1, value.length - 1);
    }
    return value;
  }

  QuickActionMenuEntry _buildCopyFunctionAction({
    required String id,
    required String title,
    required String subtitle,
    required IconData icon,
    required String value,
    bool closeAfterExecute = true,
  }) {
    return _buildFunctionAction(
      id: id,
      title: title,
      subtitle: subtitle,
      icon: icon,
      searchTerms: <String>[title, subtitle, value],
      onExecute: () {
        Clipboard.setData(ClipboardData(text: value));
        if (closeAfterExecute) _finishLauncherFunctionExecution();
      },
    );
  }

  String _stripMathAssignmentPrefix(String value) => value.replaceFirst(_mathAssignmentPrefix, '');

  QuickActionMenuEntry _buildFunctionAction({
    required String id,
    required String title,
    required String subtitle,
    required IconData icon,
    required List<String> searchTerms,
    required VoidCallback onExecute,
  }) {
    return QuickActionMenuEntry(
      id: id,
      title: title,
      searchTerms: searchTerms,
      onExecute: onExecute,
      builder: (BuildContext context) {
        final ThemeData theme = Theme.of(context);
        final Color accent = Design.accent;
        final Color onSurface = theme.colorScheme.onSurface;
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onExecute,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: <Widget>[
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withAlpha(24),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 18, color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: onSurface.withAlpha(140),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.keyboard_return_rounded, size: 14, color: onSurface.withAlpha(100)),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleNotionSearch(LauncherSearchContext context) async {
    await NotionSearchCache.load();
    if (!context.isActiveSearch(context.requestId, context.query)) return;
    final List<NotionResult> cached = NotionSearchCache.cachedSearch(context.normalizedQuery);
    if (cached.isNotEmpty || context.normalizedQuery.isEmpty) {
      context.setResults(cached.map(LauncherSearchResultItem.notion).toList(), isSearching: false);
    }
    if (context.normalizedQuery.isEmpty) return;
    if (NotionSearchCache.apiKey.isEmpty) return;
    context.setSearching(true);
    try {
      final List<NotionResult> results = await NotionSearchCache.search(context.normalizedQuery);
      if (!context.isActiveSearch(context.requestId, context.query)) return;
      final Map<String, NotionResult> freshMap = <String, NotionResult>{
        for (final NotionResult r in results) r.id: r,
      };
      final List<NotionResult> merged = <NotionResult>[
        for (final NotionResult r in cached) freshMap[r.id] ?? r,
        for (final NotionResult r in results)
          if (!cached.any((NotionResult c) => c.id == r.id)) r,
      ];
      context.setResults(merged.map(LauncherSearchResultItem.notion).toList(),
          isSearching: false, resetSelection: false);
    } catch (_) {
      if (context.isActiveSearch(context.requestId, context.query)) {
        context.setSearching(false);
      }
    }
  }

  Future<void> _handleObsidianSearch(LauncherSearchContext context) async {
    try {
      final List<ObsidianNote> notes = await ObsidianVaultService.scan();
      if (!context.isActiveSearch(context.requestId, context.query)) return;
      final List<ObsidianNote> filtered = ObsidianVaultService.filter(notes, context.normalizedQuery);
      context.setResults(filtered.map(LauncherSearchResultItem.obsidian).toList(), isSearching: false);
    } catch (_) {
      if (context.isActiveSearch(context.requestId, context.query)) {
        context.setResults(<LauncherSearchResultItem>[], isSearching: false);
      }
    }
  }

  Future<void> _handleSteamSearch(LauncherSearchContext context) async {
    try {
      final List<SteamGame> games = await SteamLibraryService.scan();
      if (!context.isActiveSearch(context.requestId, context.query)) return;
      final List<SteamGame> filtered = SteamLibraryService.filter(games, context.normalizedQuery);
      context.setResults(filtered.map(LauncherSearchResultItem.steam).toList(), isSearching: false);
    } catch (_) {
      if (context.isActiveSearch(context.requestId, context.query)) {
        context.setResults(<LauncherSearchResultItem>[], isSearching: false);
      }
    }
  }

  Future<void> _handleTerminalSearch(LauncherSearchContext context) async {
    try {
      final List<TerminalProfile> profiles = await WindowsTerminalService.scan();
      if (!context.isActiveSearch(context.requestId, context.query)) return;

      if (profiles.isEmpty) {
        context.setResults(<LauncherSearchResultItem>[
          const LauncherSearchResultItem.info(LauncherInfoResult(
            id: 'terminal-none',
            title: 'No Windows Terminal profiles found',
            subtitle: 'Install Windows Terminal or check its settings.json',
            icon: Icons.terminal_rounded,
          )),
        ], isSearching: false);
        return;
      }

      final List<TerminalProfile> filtered = WindowsTerminalService.filter(profiles, context.normalizedQuery);
      final List<LauncherSearchResultItem> results = filtered
          .map((TerminalProfile profile) => LauncherSearchResultItem.quickAction(_buildTerminalQuickAction(profile)))
          .toList(growable: false);
      context.setResults(results, isSearching: false);
    } catch (_) {
      if (context.isActiveSearch(context.requestId, context.query)) {
        context.setResults(<LauncherSearchResultItem>[], isSearching: false);
      }
    }
  }

  void _handleWorkspacesSearch(LauncherSearchContext context) {
    final List<Workspace> workspaces = Boxes.workspaces;
    if (workspaces.isEmpty) {
      context.setResults(<LauncherSearchResultItem>[
        const LauncherSearchResultItem.info(LauncherInfoResult(
          id: 'workspaces-none',
          title: 'No Workspaces Created',
          subtitle: 'Create them in QuickMenu Settings',
          icon: Icons.dashboard_customize_rounded,
        )),
      ], isSearching: false);
      return;
    }

    final String query = context.normalizedQuery.toLowerCase();
    final List<Workspace> filtered =
        query.isEmpty ? workspaces : workspaces.where((Workspace w) => w.name.toLowerCase().contains(query)).toList();

    final List<LauncherSearchResultItem> results = filtered
        .map((Workspace workspace) => LauncherSearchResultItem.quickAction(_buildWorkspaceQuickAction(workspace)))
        .toList(growable: false);
    context.setResults(results, isSearching: false);
  }

  QuickActionMenuEntry _buildWorkspaceQuickAction(Workspace workspace) {
    return _buildFunctionAction(
      id: 'workspace:${workspace.id}',
      title: workspace.name,
      subtitle: '${workspace.areas.length} App${workspace.areas.length == 1 ? '' : 's'}',
      icon: Icons.dashboard_customize_rounded,
      searchTerms: <String>['workspace', 'ws', workspace.name],
      onExecute: () => _launchWorkspaceFromLauncher(workspace),
    );
  }

  void _launchWorkspaceFromLauncher(Workspace workspace) {
    unawaited(WorkspaceRunner.run(workspace));
    _finishLauncherFunctionExecution();
  }

  QuickActionMenuEntry _buildTerminalQuickAction(TerminalProfile profile) {
    final String? commandline = profile.commandline?.trim();
    return _buildFunctionAction(
      id: 'terminal:${profile.guid.isNotEmpty ? profile.guid : profile.name}',
      title: profile.name,
      subtitle: commandline != null && commandline.isNotEmpty ? commandline : 'Open in Windows Terminal',
      icon: Icons.terminal_rounded,
      searchTerms: <String>['terminal', 'wt', profile.name],
      onExecute: () => _launchTerminalProfile(profile),
    );
  }

  void _launchTerminalProfile(TerminalProfile profile) {
    WinUtils.open('wt.exe', arguments: profile.launchArguments, parseParamaters: false);
    _finishLauncherFunctionExecution();
  }

  // bool _isActiveSearch(int requestId, String query, {bool trimLeft = false}) {
  //   if (!mounted || requestId != _searchRequestId) return false;
  //   return trimLeft ? _controller.text.trimLeft() == query : _controller.text == query;
  // }
  void _setSearching(bool value) {
    if (!mounted || _isSearching == value) return;
    setState(() => _isSearching = value);
  }

  void _scrollResultsToTopForQuery(String query) {
    if (query == _lastScrollResetQuery) return;
    _lastScrollResetQuery = query;
    _mouseSelectionEnabled = false;
    if (_activeIndexNotifier.value != 0) {
      _activeIndexNotifier.value = 0;
    }
    if (!_scrollController.hasClients || _scrollController.offset <= 0) return;
    _scrollController.jumpTo(0);
  }

  void _setResults(
    List<LauncherSearchResultItem> results, {
    bool resetSelection = true,
    bool? isSearching,
  }) {
    if (!mounted) return;

    _syncQuickActionKeys(results);
    _syncResultKeys(results);
    _mouseSelectionEnabled = false;

    // `resetSelection: false` keeps the highlighted item across background
    // refreshes of the *same* query (phase-2 merges, catalog-sync re-runs,
    // window refresh, pruning). When the displayed results belong to a
    // different query, the carried-over id would re-select a stale item at a
    // random position — force a reset then. Keyed on the query text (not the
    // search generation) because same-text re-runs bump the generation.
    final bool keepSelection =
        _resultsQuery == _controller.text && (!resetSelection || _hasKeyboardNavigatedCurrentQuery);
    _resultsQuery = _controller.text;

    final int activeDesignIndex = _activeDesignResultIndex(results);
    int nextIndex = activeDesignIndex < 0 ? 0 : activeDesignIndex;
    final bool hasKeyboardAnchor = _hasKeyboardNavigatedCurrentQuery && _keyboardSelectedResultId != null;
    final bool hasVisibleSelection = _results.isNotEmpty && _activeIndexNotifier.value < _results.length;
    if (keepSelection && (hasKeyboardAnchor || hasVisibleSelection)) {
      final String activeId = hasKeyboardAnchor ? _keyboardSelectedResultId! : _results[_activeIndexNotifier.value].id;
      final int foundIndex = results.indexWhere((LauncherSearchResultItem r) => r.id == activeId);
      if (foundIndex != -1) {
        nextIndex = foundIndex;
        if (hasKeyboardAnchor) _keyboardSelectedResultIndex = foundIndex;
      } else {
        final int fallbackIndex = hasKeyboardAnchor ? _keyboardSelectedResultIndex : _activeIndexNotifier.value;
        nextIndex = fallbackIndex.clamp(0, (results.length - 1).clamp(0, 999999)).toInt();
      }
    }

    setState(() {
      _results = results;
      _activeIndexNotifier.value = activeDesignIndex >= 0 || keepSelection ? nextIndex : 0;
      if (isSearching != null) {
        _isSearching = isSearching;
      }
    });

    if (activeDesignIndex >= 0) {
      _scrollResultToCenter(activeDesignIndex);
    } else if (!keepSelection && _scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }

    if (_controller.text == '.') {
      _prefetchWindowPreviews(results);
    }

    _maybeExecutePendingLauncherQuickAction();
    unawaited(_pruneStaleFileResults(results));
  }

  int _activeDesignResultIndex(List<LauncherSearchResultItem> results) {
    if (results.length != LauncherDesign.values.length ||
        results
            .any((LauncherSearchResultItem result) => result.quickAction?.id.startsWith('function-design:') != true)) {
      return -1;
    }
    return results
        .indexWhere((LauncherSearchResultItem result) => result.quickAction?.id == 'function-design:${_design.name}');
  }

  /// Checks file/folder results for existence after they are displayed.
  /// Runs fully async without blocking — stale entries are removed from both
  /// the DB and the visible results list.
  Future<void> _pruneStaleFileResults(List<LauncherSearchResultItem> snapshot) async {
    // Collect only items that represent real filesystem paths.
    final List<LauncherSearchResultItem> fileItems =
        snapshot.where((LauncherSearchResultItem r) => r.isFile && r.entity != null).toList();
    if (fileItems.isEmpty) return;

    // Stat every candidate in parallel instead of serially on the UI isolate,
    // so a slow/network path can't stall the whole prune one entry at a time.
    final List<FileSystemEntityType> types = await Future.wait(
      fileItems.map((LauncherSearchResultItem item) => FileSystemEntity.type(item.entity!.path)),
    );

    final List<LauncherSearchResultItem> stale = <LauncherSearchResultItem>[
      for (int i = 0; i < fileItems.length; i++)
        if (types[i] == FileSystemEntityType.notFound) fileItems[i],
    ];

    if (stale.isEmpty) return;
    if (!mounted) return;

    // Remove stale entries from the database.
    for (final LauncherSearchResultItem item in stale) {
      final int? nodeId = item.nodeId;
      if (nodeId == null) continue;
      try {
        FileIndexDb.instance.deleteNode(nodeId);
      } catch (error) {
        debugPrint('Launcher: Failed to delete stale node $nodeId from DB: $error');
      }
    }

    // Update the visible results only if the list has not already changed.
    if (!mounted) return;
    if (!identical(_results, snapshot)) return;

    final Set<String> staleIds = stale.map((LauncherSearchResultItem r) => r.id).toSet();
    final List<LauncherSearchResultItem> pruned =
        _results.where((LauncherSearchResultItem r) => !staleIds.contains(r.id)).toList();

    if (pruned.length == _results.length) return;
    _setResults(pruned, resetSelection: false);
  }

  void _maybeExecutePendingLauncherQuickAction() {
    final String? pendingAction = _pendingLauncherQuickAction;
    if (pendingAction == null || pendingAction.isEmpty || _isSearching || _results.isEmpty) return;
    if (_searchMode != LauncherSearchMode.actionsOnly) return;
    if (_controller.text.trim() != '/$pendingAction') return;
    if (_results.first.isInfo || _results.first.quickAction == null) {
      _pendingLauncherQuickAction = null;
      _pendingLauncherQuickActionAttempt = 0;
      return;
    }

    final String firstResultKey = _resultKeyId(_results.first, 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _results.isEmpty) return;
      if (_pendingLauncherQuickAction != pendingAction) return;
      if (_controller.text.trim() != '/$pendingAction') return;

      final BuildContext? itemContext = _resultKeys[firstResultKey]?.currentContext;
      if (itemContext == null) {
        if (_pendingLauncherQuickActionAttempt >= 12) {
          _pendingLauncherQuickAction = null;
          _pendingLauncherQuickActionAttempt = 0;
          return;
        }
        _pendingLauncherQuickActionAttempt++;
        _maybeExecutePendingLauncherQuickAction();
        return;
      }

      _pendingLauncherQuickAction = null;
      _pendingLauncherQuickActionAttempt = 0;
      _activeIndexNotifier.value = 0;
      _runQuickAction(_results.first.quickAction!);
    });
  }
}
