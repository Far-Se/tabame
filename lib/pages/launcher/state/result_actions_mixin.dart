part of '../../launcher.dart';

// ignore_for_file: annotate_overrides

// ---------------------------------------------------------------------------
// Result actions and preview bookkeeping
// ---------------------------------------------------------------------------

mixin _ResultActionsMixin on _LauncherStateMembersMixin {
  // ---------------------------------------------------------------------------
  // Submit / open handlers
  // ---------------------------------------------------------------------------
  void _onShortcutPressed(LauncherShortcut shortcut) {
    if (shortcut.opensPluginManager) {
      _openLauncherPanel(context, const PluginManagerPanel());
      return;
    }

    if (_searchMode == LauncherSearchMode.pluginsOnly) {
      _controller.text = shortcut.prefix;
      _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
      unawaited(_handleLauncherWindowAction());
      return;
    }

    _controller.text = shortcut.prefix;
    // _controller.selection = TextSelection.fromPosition(TextPosition(offset: _controller.text.length));
    _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
    _onSearchChanged(_controller.text);
    _focusSearch();
  }

  void _onSubmitted(String query) {
    if (_results.isEmpty || _activeIndexNotifier.value >= _results.length) return;

    final LauncherSearchResultItem result = _results[_activeIndexNotifier.value];
    LauncherResultExecutor(
      onShortcut: _onShortcutPressed,
      onBrowseFolder: _browseFolder,
      onOpenFile: _openFile,
      onOpenApp: _openAppResult,
      onOpenWindow: _openWindow,
      onOpenBrowserTab: _openBrowserTab,
      onOpenBookmark: _openBookmarkResult,
      onOpenNotion: _openNotionResult,
      onOpenObsidian: _openObsidianResult,
      onOpenSteam: _openSteamResult,
      onRunAction: _executeLauncherActionResult,
    ).execute(result);

    _focusSearch();
  }

  void _executeLauncherActionResult(QuickActionMenuEntry action) {
    // Intercept the "Open Folder in Explorer" sentinel action that
    // DesktopSearchHandler pins at the top of browsed-folder results.
    if (action.id.startsWith('desktop_browse_open_explorer:')) {
      final String folderPath = action.id.substring('desktop_browse_open_explorer:'.length);
      _openFolderInExplorer(folderPath);
      return;
    }
    _runQuickAction(action);
  }

  void _openBookmarkResult(BookmarkSearchResult result) {
    switch (result.kind) {
      case BookmarkResultKind.bookmark:
        WinUtils.open(result.bookmark!.stringToExecute, parseParamaters: true);
        QuickMenuFunctions.hideQuickMenu(launcherActivateLastWin: false);
        user.launcherSearchText = '';
      case BookmarkResultKind.cliBook:
        // Copy the CLI command to clipboard.
        Clipboard.setData(ClipboardData(text: result.cli!.value));
        QuickMenuFunctions.hideQuickMenu();
        user.launcherSearchText = '';
      case BookmarkResultKind.appItem:
        WinUtils.open(result.app!.path, arguments: result.app!.arguments);
        QuickMenuFunctions.hideQuickMenu(launcherActivateLastWin: false);
        user.launcherSearchText = '';
    }
  }

  void _openFile(String path, {int? nodeId}) {
    if (nodeId != null) {
      unawaited(_recordFileOpen(nodeId));
    }

    if (path.endsWith('ps1')) {
      final String openPath = 'powershell -ExecutionPolicy Bypass -File "$path"';
      WinUtils.open(openPath, parseParamaters: true);
    } else {
      WinUtils.open(path);
    }
    QuickMenuFunctions.hideQuickMenu(launcherActivateLastWin: false);
    Globals.quickMenuPage = QuickMenuPage.quickMenu;
    user.launcherSearchText = '';
  }

  /// Drills into [folderPath] inside the Launcher (desktop `;` browse mode).
  /// Pushes [folderPath] onto the history stack so "Go back" can pop it.
  void _browseFolder(String folderPath) {
    setState(() {
      _folderBrowsingStack.add(folderPath);
      _folderBrowsingQueryStack.add(LauncherQuery.parse(_controller.text).normalized);
    });
    _onSearchChanged(_controller.text);
    // After results render, skip past the two pinned action items
    // (index 0 = "Open Folder in Explorer", index 1 = "Go Back")
    // and land on the first real folder/file entry.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _results.length >= 3) {
        _activeIndexNotifier.value = 2;
      }
    });
  }

  /// Pops one level off the desktop browsing stack.
  /// If the stack becomes empty we return to the normal desktop search.
  void _goBackDesktopFolder() {
    if (_folderBrowsingStack.isEmpty) return;
    setState(() {
      _folderBrowsingStack.removeLast();
      _folderBrowsingQueryStack.removeLast();
    });
    _onSearchChanged(_controller.text);
    _focusSearch();
  }

  /// Opens [folderPath] in Windows Explorer and hides the launcher.
  void _openFolderInExplorer(String folderPath) {
    WinUtils.open(folderPath);
    QuickMenuFunctions.hideQuickMenu(launcherActivateLastWin: false);
    Globals.quickMenuPage = QuickMenuPage.quickMenu;
    user.launcherSearchText = '';
    _folderBrowsingStack.clear();
    _folderBrowsingQueryStack.clear();
  }

  /// Opens the currently selected result in Windows Explorer if it is a Directory.
  /// Triggered by Ctrl+Enter or Ctrl+O.
  void _openSelectedFolderInExplorer() {
    if (_results.isEmpty) return;
    final int idx = _activeIndexNotifier.value.clamp(0, _results.length - 1);
    final LauncherSearchResultItem item = _results[idx];
    if (item.isFile && item.entity is Directory) {
      _openFolderInExplorer(item.entity!.path);
    }
  }

  void _openAppResult(LauncherAppResult app, {int? nodeId}) {
    if (nodeId != null) {
      unawaited(_recordFileOpen(nodeId));
    }

    final String launchTarget = app.appUserModelId.isNotEmpty
        ? LauncherAppCatalogService.buildLaunchTarget(app.appUserModelId)
        : app.launchTarget;
    if (launchTarget.isEmpty) return;

    WinUtils.open(launchTarget, parseParamaters: false);
    QuickMenuFunctions.hideQuickMenu(launcherActivateLastWin: false);
    Globals.quickMenuPage = QuickMenuPage.quickMenu;
    user.launcherSearchText = '';
  }

  Future<void> _recordFileOpen(int nodeId) async {
    try {
      await FileIndexDb.instance.database;
      FileIndexDb.instance.incrementTimesOpened(nodeId);
    } catch (error, stackTrace) {
      if (_isMalformedFileIndexError(error)) {
        debugPrint('Launcher: File index DB is malformed while opening node $nodeId. Repairing in background...');
        await _repairFileIndexInBackground();
        return;
      }

      debugPrint('Launcher: Failed to increment times_opened for node $nodeId: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  bool _isMalformedFileIndexError(Object error) {
    if (error is! SqliteException) return false;
    return error.toString().toLowerCase().contains('malformed');
  }

  Future<void> _repairFileIndexInBackground() async {
    if (_isRepairingFileIndex) return;
    _isRepairingFileIndex = true;

    try {
      await FileIndexDb.instance.repair();
      await FileIndexer.instance.fullReindex();
      await LauncherAppCatalogService.instance.sync();
      if (mounted) {
        _onSearchChanged(_controller.text);
      }
    } catch (error, stackTrace) {
      debugPrint('Launcher: Failed to repair file index DB: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _isRepairingFileIndex = false;
    }
  }

  Future<void> _openWindow(PlatformWindow window) async {
    await QuickMenuFunctions.hideQuickMenu(launcherActivateLastWin: false);
    await WindowWatcherService.instance.activate(window);
    Globals.quickMenuPage = QuickMenuPage.quickMenu;
    user.launcherSearchText = '';
  }

  Future<void> _openBrowserTab(BrowserTab browserTab) async {
    await QuickMenuFunctions.hideQuickMenu(launcherActivateLastWin: false);
    Win32.activateWindow(browserTab.hWnd);
    await BrowserTabs.focusTab(
      hWnd: browserTab.hWnd,
      index: browserTab.index,
      title: browserTab.title,
    );
    Globals.lastFocusedWinHWND = browserTab.hWnd;
    Globals.quickMenuPage = QuickMenuPage.quickMenu;
    user.launcherSearchText = '';
  }

  void _openNotionResult(NotionResult result) {
    if (result.url.isEmpty) return;
    WinUtils.open(result.url);
    QuickMenuFunctions.hideQuickMenu(launcherActivateLastWin: false);
    Globals.quickMenuPage = QuickMenuPage.quickMenu;
    user.launcherSearchText = '';
  }

  void _openObsidianResult(ObsidianNote result) {
    WinUtils.open(result.obsidianProtocolUri);
    QuickMenuFunctions.hideQuickMenu(launcherActivateLastWin: false);
    Globals.quickMenuPage = QuickMenuPage.quickMenu;
    user.launcherSearchText = '';
  }

  void _openSteamResult(SteamGame result) {
    WinUtils.open(result.launchUri);
    QuickMenuFunctions.hideQuickMenu(launcherActivateLastWin: false);
    Globals.quickMenuPage = QuickMenuPage.quickMenu;
    user.launcherSearchText = '';
  }

  void _syncQuickActionKeys(List<LauncherSearchResultItem> results) {
    final Set<String> activeIds = results
        .where((LauncherSearchResultItem r) => r.quickAction != null)
        .map((LauncherSearchResultItem r) => r.quickAction!.id)
        .toSet();
    _quickActionKeys.removeWhere((String key, _) => !activeIds.contains(key));
    for (final String id in activeIds) {
      _quickActionKeys.putIfAbsent(id, () => GlobalKey()); // add this
    }
  }

  void _syncResultKeys(List<LauncherSearchResultItem> results) {
    final Set<String> activeResultIds = <String>{
      for (int index = 0; index < results.length; index++) _resultKeyId(results[index], index),
    };
    _resultKeys.removeWhere((String key, GlobalKey value) => !activeResultIds.contains(key));
    for (final String id in activeResultIds) {
      _resultKeys.putIfAbsent(id, () => GlobalKey());
    }
  }

  String _resultKeyId(LauncherSearchResultItem result, int index) => '${result.id}#$index';

  Future<PlatformWindowPreview?> _captureWindowPreview(
    PlatformWindow window, {
    bool force = false,
  }) {
    final String identity = window.identity;
    final PlatformWindowPreview? cached = _windowPreviewCache[identity];
    if (!force && cached != null) return Future<PlatformWindowPreview?>.value(cached);

    final Future<PlatformWindowPreview?>? existing = _windowPreviewCaptures[identity];
    if (existing != null) return existing;

    Future<PlatformWindowPreview?> performCapture() async {
      try {
        final PlatformWindowPreview? preview = await WindowWatcherService.instance.capturePreview(window);
        if (preview != null) {
          _windowPreviewCache[identity] = preview;
          if (mounted) _windowPreviewCacheVersion.value++;
          return preview;
        }
      } catch (_) {
        // Keep the last successful frame when a window disappears or refuses a
        // refresh; hover can retry if the HWND remains valid.
      }
      return _windowPreviewCache[identity];
    }

    late final Future<PlatformWindowPreview?> request;
    request = performCapture().whenComplete(() {
      if (identical(_windowPreviewCaptures[identity], request)) {
        _windowPreviewCaptures.remove(identity);
      }
    });
    _windowPreviewCaptures[identity] = request;
    return request;
  }

  void _prefetchWindowPreviews(List<LauncherSearchResultItem> results) {
    if (_windowPreviewPrefetchGeneration != _searchGeneration) {
      _windowPreviewPrefetchGeneration = _searchGeneration;
      _queuedWindowPreviewIds.clear();
      _lastHoveredWindowPreviewId = null;
      _windowPreviewPrefetchRun++;
    }

    final Set<String> activeWindowIds = <String>{
      for (final LauncherSearchResultItem result in results)
        if (result.window != null) result.window!.identity,
    };
    final int cacheSizeBeforePrune = _windowPreviewCache.length;
    _windowPreviewCache
        .removeWhere((String identity, PlatformWindowPreview preview) => !activeWindowIds.contains(identity));
    if (_windowPreviewCache.length != cacheSizeBeforePrune && mounted) {
      _windowPreviewCacheVersion.value++;
    }

    final List<PlatformWindow> pending = <PlatformWindow>[
      for (final LauncherSearchResultItem result in results)
        if (result.window != null && _queuedWindowPreviewIds.add(result.window!.identity)) result.window!,
    ];
    if (pending.isEmpty) return;

    final int run = _windowPreviewPrefetchRun;
    int nextIndex = 0;
    Future<void> worker() async {
      while (mounted && _controller.text == '.' && run == _windowPreviewPrefetchRun) {
        final int index = nextIndex++;
        if (index >= pending.length) return;
        await _captureWindowPreview(pending[index], force: true);
      }
    }

    final int workerCount = math.min(3, pending.length);
    for (int index = 0; index < workerCount; index++) {
      unawaited(worker());
    }
  }

  void _selectWindowResultFromMouse(int index, PlatformWindow window) {
    _selectResultFromMouse(index);
    if (_lastHoveredWindowPreviewId == window.identity) return;
    _lastHoveredWindowPreviewId = window.identity;
    unawaited(_captureWindowPreview(window, force: true));
  }

  void _selectResultFromPointerHover(PointerHoverEvent event, int index) {
    if (event.delta == Offset.zero) return;

    final bool pointerMoved = _lastMousePosition == null || (_lastMousePosition! - event.position).distance > 0.5;
    _lastMousePosition = event.position;
    if (!pointerMoved && !_mouseSelectionEnabled) return;

    _mouseSelectionEnabled = true;
    _selectResultFromMouse(index);
    if (index >= 0 && index < _results.length && _results[index].window == null) {
      _lastHoveredWindowPreviewId = null;
    }
  }

  void _selectResultFromMouse(int index) {
    if (!_mouseSelectionEnabled) return;
    if (index < 0 || index >= _results.length) return;
    if (_activeIndexNotifier.value != index) {
      _activeIndexNotifier.value = index;
    }
    // If keyboard navigation already established a durable selection anchor,
    // a real pointer move becomes the newer user intent for late result frames.
    if (_hasKeyboardNavigatedCurrentQuery) {
      _keyboardSelectedResultId = _results[index].id;
      _keyboardSelectedResultIndex = index;
    }
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

  LauncherSearchResultItem? _previewResultAt(int index) {
    if (index < 0 || index >= _results.length) return null;
    final LauncherSearchResultItem result = _results[index];
    return result.isFile || result.isWindow ? result : null;
  }
}
