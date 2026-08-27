part of '../../launcher.dart';

// ignore_for_file: annotate_overrides

// ---------------------------------------------------------------------------
// Plugin host and plugin-owned launcher behavior
// ---------------------------------------------------------------------------

mixin _PluginHostMixin on _LauncherStateMembersMixin {
  PluginAction get _launcherWindowAction => PluginAction(
        id: '__launcher_window__',
        title: Globals.isStandaloneLauncher ? 'Close current Window' : 'Open In External Window',
        icon: Globals.isStandaloneLauncher ? 'close' : 'open',
        shortcut: 'ctrl+shift+e',
      );

  void _copyItem() {
    if (_results.isEmpty) return;

    final int idx = _activeIndexNotifier.value.clamp(0, _results.length - 1);
    final LauncherSearchResultItem item = _results[idx];

    // Shortcuts and info rows have no meaningful actions.
    if (item.isShortcut || item.isInfo) return;
    if (item.isFile && item.entity != null) {
      final String path = item.entity!.path;

      // Add to the multi-copy queue if not already present.
      if (!_copiedFiles.contains(path)) {
        _copiedFiles.add(path);
      }

      // Commit all queued files to the clipboard immediately.
      unawaited(ClipboardService.instance.writeFiles(List<String>.unmodifiable(_copiedFiles)));

      if (mounted) setState(() {});
    }
  }

  void _clearCopiedFiles() {
    if (_copiedFiles.isEmpty) return;
    _copiedFiles.clear();
    if (mounted) setState(() {});
  }

  void _openActionsForActiveResult() {
    if (_activePlugin != null) {
      _openPluginActions();
      return;
    }
    if (_results.isEmpty) return;

    final int idx = _activeIndexNotifier.value.clamp(0, _results.length - 1);
    final LauncherSearchResultItem item = _results[idx];

    // Shortcuts and info rows have no meaningful actions.
    if (item.isShortcut || item.isInfo) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      builder: (_) => ActionsPanelScaffold(item: item),
    );
  }

  /// Wider launcher window used while a plugin shows a split preview pane.
  double get _pluginPreviewWidth => Boxes.launcherSizeWidth > 1080 ? Boxes.launcherSizeWidth : 1080;

  /// Enters (or updates) a plugin's live mode for [query]. Starts the process on
  /// first entry, otherwise just forwards the new query text.
  void _routeToPlugin(PluginManifest plugin, String query) {
    _searchDebounce?.cancel();
    _pluginQueryDebounce?.cancel();
    final String pluginQuery = PluginRegistry.queryAfterKeyword(query, plugin);
    final bool switching = _activePlugin?.id != plugin.id;
    _activePlugin = plugin;
    Globals.isLauncherPluginActive = true;

    if (switching) {
      _pluginSubmitPending = false;
      _pluginKeyboardSelectedItemId = null;
      _pluginKeyboardSelectedIndex = 0;
      _pluginSelectedIdsByScope.clear();
      _pluginPageSelectionIds.clear();
      _pluginPageHistory.clear();
      setState(() {
        _searchMode = LauncherSearchMode.mixed;
        _isSearching = true;
        _results = const <LauncherSearchResultItem>[];
        _pluginFrame = null;
        _activeIndexNotifier.value = 0;
      });
      unawaited(_pluginHost.activate(plugin, initialQuery: pluginQuery));
    } else if (_pluginFrame?.submitInput == true) {
      // `inputMode: "submit"`: keystrokes stay local; the query only reaches
      // the plugin when the user presses Enter (see _submitPluginItem).
    } else {
      // Debounce keystrokes before hitting the plugin process — plugins that
      // call a rate-limited external API on every query can get blocked if we
      // forward every keystroke immediately.
      _pluginQueryDebounce = Timer(const Duration(milliseconds: 300), () {
        if (!mounted || _activePlugin?.id != plugin.id) return;
        _pluginHost.sendQuery(pluginQuery);
      });
    }
  }

  /// Leaves plugin mode: stops the process and restores the normal layout.
  void _deactivatePlugin() {
    _pluginQueryDebounce?.cancel();
    _pluginSubmitPending = false;
    _pluginLastSubmittedQuery = null;
    _pluginKeyboardSelectedItemId = null;
    _pluginKeyboardSelectedIndex = 0;
    _pluginToastTimer?.cancel();
    _pluginToastTimer = null;
    if (_activePlugin == null && _pluginFrame == null) return;
    _activePlugin = null;
    _pluginSelectedIdsByScope.clear();
    _pluginPageSelectionIds.clear();
    _pluginPageHistory.clear();
    Globals.isLauncherPluginActive = false;
    unawaited(_pluginHost.deactivate());
    _restorePluginWindowWidth();
    if (mounted) {
      setState(() {
        _pluginFrame = null;
        _pluginToast = null;
        _pluginToastProgress = null;
      });
    }
  }

  /// Exits the plugin and clears the search back to the launcher home.
  void _exitPlugin() {
    _deactivatePlugin();
    _controller.text = '';
    _controller.selection = const TextSelection.collapsed(offset: 0);
    _onSearchChanged('');
  }

  /// Applies a render frame pushed by the plugin process.
  void _onPluginFrame(PluginRenderFrame frame) {
    if (!mounted || _activePlugin == null) return;
    final PluginRenderFrame? previous = _pluginFrame;
    final bool wasForm = previous?.view == PluginViewType.form ||
        (previous?.view == PluginViewType.dashboard &&
            previous!.dashboardPanels.any((PluginDashboardPanel panel) => panel.frame.view == PluginViewType.form));
    // Streaming `detail.append` frames carry only the new chunk — resolve them
    // against the markdown currently on screen before rendering.
    if (frame.detailAppend != null) {
      frame = frame.resolveAppend(previous?.view == PluginViewType.detail ? previous?.detailMarkdown : null);
    }
    if (previous?.page != null && previous!.items.isNotEmpty) {
      final int oldIndex = _activeIndexNotifier.value.clamp(0, previous.items.length - 1);
      _pluginPageSelectionIds[previous.page!.id] = previous.items[oldIndex].id;
    }
    _updatePluginPageHistory(previous, frame);
    // A different item set means a new screen (drill-in) or a fresh search:
    // snap the selection back to the first row so it matches what's shown and
    // arrow keys start from there. Same-id re-renders (e.g. a background badge
    // refresh) keep the cursor where the user left it. Pagination is also a
    // same-screen update: preserve the current item when the new frame contains
    // the previous list followed by another page. A frame carrying `selectId`
    // picks its own highlight instead.
    final bool samePage = previous != null && previous.page?.id == frame.page?.id;
    final bool sameItemSet = previous != null && samePage && _sameItemIds(previous.items, frame.items);
    final bool appendedItems = previous != null && samePage && _isPluginItemListAppend(previous.items, frame.items);
    final int previousSelectedIndex = previous == null || previous.items.isEmpty
        ? -1
        : _activeIndexNotifier.value.clamp(0, previous.items.length - 1);
    final int appendedSelectionIndex = appendedItems
        ? frame.items.indexWhere((PluginItem item) => item.id == previous.items[previousSelectedIndex].id)
        : -1;
    final bool keepKeyboardSelection =
        samePage && _hasKeyboardNavigatedCurrentQuery && _pluginKeyboardSelectedItemId != null;
    setState(() {
      _pluginFrame = frame;
      _prunePluginSelections(frame);
      _isSearching = frame.loading;
      final int count = frame.items.length;
      final int selectIdIndex =
          frame.selectId == null ? -1 : frame.items.indexWhere((PluginItem item) => item.id == frame.selectId);
      final String? restoredId = frame.page == null ? null : _pluginPageSelectionIds[frame.page!.id];
      final int restoredIndex =
          restoredId == null ? -1 : frame.items.indexWhere((PluginItem item) => item.id == restoredId);
      final int keyboardSelectedIndex = !keepKeyboardSelection
          ? -1
          : frame.items.indexWhere((PluginItem item) => item.id == _pluginKeyboardSelectedItemId);
      // A frame may be the delayed response to an earlier `select` event. Keep
      // the newer keyboard choice when that item still exists; otherwise an
      // explicit plugin selection is allowed to drive a genuinely new screen.
      if (keyboardSelectedIndex >= 0) {
        _activeIndexNotifier.value = keyboardSelectedIndex;
        _pluginKeyboardSelectedIndex = keyboardSelectedIndex;
      } else if (selectIdIndex >= 0) {
        _activeIndexNotifier.value = selectIdIndex;
      } else if (restoredIndex >= 0) {
        _activeIndexNotifier.value = restoredIndex;
      } else if (appendedSelectionIndex >= 0) {
        _activeIndexNotifier.value = appendedSelectionIndex;
      } else if (keepKeyboardSelection && count > 0) {
        _activeIndexNotifier.value = _pluginKeyboardSelectedIndex.clamp(0, count - 1);
        _pluginKeyboardSelectedIndex = _activeIndexNotifier.value;
      } else if (count == 0 || !sameItemSet) {
        _activeIndexNotifier.value = 0;
      } else if (_activeIndexNotifier.value >= count) {
        _activeIndexNotifier.value = count - 1;
      }
    });
    // An Enter press was deferred until this query's frame arrived. Fire the
    // first result now — ignoring transient loading frames the plugin emits
    // before its real results, and never auto-submitting a form.
    if (_pluginSubmitPending && !frame.loading && frame.view != PluginViewType.form) {
      _pluginSubmitPending = false;
      if (frame.items.isNotEmpty) {
        _activeIndexNotifier.value = 0;
        _pluginHost.sendAction(frame.items.first.id, 'default', scope: frame.scope());
      }
    }
    // Leaving a form view: the form's field held focus, hand it back to the
    // search box so typing works again.
    final bool isForm = frame.view == PluginViewType.form ||
        (frame.view == PluginViewType.dashboard &&
            frame.dashboardPanels.any((PluginDashboardPanel panel) => panel.frame.view == PluginViewType.form));
    if (wasForm && !isForm) _requestLauncherFocus();
    _applyPluginWindowWidth(frame.wantsWideWindow);
  }

  /// Whether [next] is the previous list followed by one or more new pages.
  /// Pagination frames are full snapshots, so preserving the selected item here
  /// prevents the list from being mistaken for a fresh search.
  bool _isPluginItemListAppend(List<PluginItem> previous, List<PluginItem> next) {
    if (previous.isEmpty || next.length <= previous.length) return false;
    for (int i = 0; i < previous.length; i++) {
      if (previous[i].id != next[i].id) return false;
    }
    return true;
  }

  /// Whether two plugin item lists carry the same ids in the same order — the
  /// signal for "same list, just re-rendered" versus "a new list to show".
  bool _sameItemIds(List<PluginItem> a, List<PluginItem> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  void _updatePluginPageHistory(PluginRenderFrame? previous, PluginRenderFrame next) {
    final String? pageId = next.page?.id;
    if (pageId == null) return;
    if (_pluginPageHistory.isEmpty) {
      _pluginPageHistory.add(pageId);
      return;
    }
    if (_pluginPageHistory.last == pageId) return;
    final int existing = _pluginPageHistory.lastIndexOf(pageId);
    if (existing >= 0) {
      _pluginPageHistory.removeRange(existing + 1, _pluginPageHistory.length);
      return;
    }
    if (next.page!.history == 'replace') {
      _pluginPageHistory[_pluginPageHistory.length - 1] = pageId;
    } else if (next.page!.history == 'push' || previous?.page == null) {
      _pluginPageHistory.add(pageId);
    }
  }

  PluginEventScope get _topPluginScope => _pluginFrame?.scope() ?? const PluginEventScope();

  bool get _pluginCanGoBack => (_pluginFrame?.canGoBack ?? false) || _pluginPageHistory.length > 1;

  Set<String> _selectedIdsFor(PluginEventScope scope) =>
      _pluginSelectedIdsByScope.putIfAbsent(scope.key, () => <String>{});

  PluginRenderFrame? _frameForScope(PluginEventScope scope) {
    final PluginRenderFrame? frame = _pluginFrame;
    if (frame == null || scope.panelId == null) return frame;
    for (final PluginDashboardPanel panel in frame.dashboardPanels) {
      if (panel.id == scope.panelId) return panel.frame;
    }
    return frame;
  }

  void _prunePluginSelections(PluginRenderFrame frame) {
    final List<(PluginEventScope, PluginRenderFrame)> scopes = <(PluginEventScope, PluginRenderFrame)>[
      (frame.scope(), frame)
    ];
    for (final PluginDashboardPanel panel in frame.dashboardPanels) {
      scopes.add((
        PluginEventScope(pageId: frame.page?.id, panelId: panel.id, elementId: panel.frame.elementId),
        panel.frame,
      ));
    }
    final Set<String> liveKeys = scopes.map(((PluginEventScope, PluginRenderFrame) entry) => entry.$1.key).toSet();
    _pluginSelectedIdsByScope.removeWhere((String key, Set<String> value) => !liveKeys.contains(key));
    for (final (PluginEventScope scope, PluginRenderFrame scopedFrame) in scopes) {
      final Set<String> selected = _selectedIdsFor(scope);
      if (!scopedFrame.multiSelect) selected.clear();
      selected.removeWhere((String id) => !scopedFrame.items.any((PluginItem item) => item.id == id));
    }
  }

  void _sendPluginBack() {
    final String? from = _pluginFrame?.page?.id;
    final String? to = _pluginPageHistory.length > 1 ? _pluginPageHistory[_pluginPageHistory.length - 2] : null;
    _pluginHost.sendBack(fromPageId: from, toPageId: to, scope: _topPluginScope);
  }

  /// Form view submit: forwards the field values to the plugin.
  void _onPluginFormSubmit(PluginEventScope scope, Map<String, Object?> values, {String? button}) {
    _pluginHost.sendFormSubmit(values, button: button, scope: scope);
  }

  /// Form view: a `watch: true` field changed (dependent dropdowns).
  void _onPluginFormChange(PluginEventScope scope, String fieldId, Map<String, Object?> values) {
    _pluginHost.sendFormChange(fieldId, values, scope: scope);
  }

  /// Form view Escape: back when the frame declared canGoBack, otherwise exit.
  void _onPluginFormCancel(PluginEventScope scope) {
    if (_pluginCanGoBack) {
      _sendPluginBack();
      return;
    }
    _exitPlugin();
    _requestLauncherFocus();
  }

  /// Executes a `{"type":"command"}` side effect emitted by the plugin, so
  /// scripts don't have to shell out to `clip`/`start` themselves.
  void _onPluginCommand(PluginCommand command) {
    if (!mounted || _activePlugin == null) return;
    switch (command.name) {
      case 'copy':
        Clipboard.setData(ClipboardData(text: command.text ?? ''));
        _showPluginToast('Copied to clipboard');
        break;
      case 'paste':
        unawaited(_pastePluginText(command.text ?? ''));
        break;
      case 'open':
        final String target = command.url?.trim() ?? '';
        if (target.isNotEmpty) WinUtils.open(target);
        break;
      case 'hide':
        // Deactivate before hiding so a plugin that requested background work
        // receives `close` and its detached completion notifications remain
        // supervised by the host.
        _deactivatePlugin();
        unawaited(QuickMenuFunctions.hideQuickMenu());
        break;
      case 'toast':
        final Object? style = command.data['style'];
        final Object? progress = command.data['progress'];
        _showPluginToast(
          command.text ?? '',
          style: style is String ? style : 'success',
          progress: progress is num ? progress.toDouble().clamp(0.0, 1.0) : null,
        );
        break;
      case 'setquery':
        _setPluginQuery(command.text ?? '');
        break;
    }
  }

  /// `setQuery` command: rewrites the search field's post-keyword text
  /// (autocomplete, drill-down) while keeping the plugin active.
  void _setPluginQuery(String text) {
    final PluginManifest? plugin = _activePlugin;
    if (plugin == null) return;
    final String launchKeyword = PluginRegistry.launchKeyword(plugin);
    final String next = text.isEmpty ? launchKeyword : '$launchKeyword $text';
    if (_controller.text == next) return;
    _controller.text = next;
    _controller.selection = TextSelection.collapsed(offset: next.length);
    _onSearchChanged(next);
  }

  /// Shows a transient confirmation chip over the plugin results area.
  /// `progress`-style toasts stay pinned (updated in place by later `toast`
  /// commands) until a non-progress style arrives or the plugin exits.
  void _showPluginToast(String message, {String style = 'success', double? progress}) {
    if (message.trim().isEmpty) return;
    _pluginToastTimer?.cancel();
    _pluginToastTimer = null;
    setState(() {
      _pluginToast = message.trim();
      _pluginToastStyle = style;
      _pluginToastProgress = progress;
    });
    if (style == 'progress') return; // Pinned until updated.
    _pluginToastTimer = Timer(const Duration(milliseconds: 1800), () {
      _pluginToastTimer = null;
      if (mounted) setState(() => _pluginToast = null);
    });
  }

  /// Puts [text] on the clipboard, hides the launcher (which re-activates the
  /// previously focused window), then sends Ctrl+V — the emoji picker's flow.
  Future<void> _pastePluginText(String text) async {
    if (text.isEmpty) return;
    // `paste` is also a launcher-closing command. Use the same lifecycle path
    // as `hide`, rather than leaving a live plugin attached to a hidden window.
    _deactivatePlugin();
    await Clipboard.setData(ClipboardData(text: text));
    await QuickMenuFunctions.hideQuickMenu();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    WinKeys.send("{#CONTROL}V{|}");
  }

  void _applyPluginWindowWidth(bool wide) {
    if (wide) {
      // A wide frame arrived: cancel any pending collapse so a transient narrow
      // frame (loading / detail) that's immediately followed by a wide one never
      // shrinks the window.
      _pluginWidthCollapseTimer?.cancel();
      _pluginWidthCollapseTimer = null;
      if (_pluginWindowWidened) return;
      _pluginWindowWidened = true;
      unawaited(_animatePluginWindowWidth(_pluginPreviewWidth));
      return;
    }

    // Narrow frame: debounce the collapse. Each keystroke makes the plugin emit
    // an intermediate loading frame (no preview) before the results frame (with
    // preview); collapsing immediately would resize to default and back on every
    // letter, causing jitter. Only shrink once the plugin has stayed narrow.
    if (!_pluginWindowWidened) return;
    _pluginWidthCollapseTimer?.cancel();
    _pluginWidthCollapseTimer = Timer(const Duration(milliseconds: 300), () {
      _pluginWidthCollapseTimer = null;
      if (mounted) _restorePluginWindowWidth();
    });
  }

  void _restorePluginWindowWidth({bool animate = true}) {
    _pluginWidthCollapseTimer?.cancel();
    _pluginWidthCollapseTimer = null;
    if (!_pluginWindowWidened) return;
    _pluginWindowWidened = false;
    if (!animate) {
      unawaited(_setPluginWindowWidth(Boxes.launcherSizeWidth, finalize: true));
      return;
    }
    unawaited(_animatePluginWindowWidth(Boxes.launcherSizeWidth));
  }

  /// Hides the native resize behind a short fade so the launcher changes modes
  /// without the window's edges visibly stretching across the screen.
  Future<void> _animatePluginWindowWidth(double targetWidth) async {
    final int transitionVersion = ++_pluginWindowTransitionVersion;
    final bool reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _pluginWindowTransitionController.stop();

    if (reduceMotion || (!_launcherAnimatedOnce && Globals.isStandaloneLauncher)) {
      _pluginWindowOpacity = 1;
      await WindowManager.instance.setOpacity(1);
      await _setPluginWindowWidth(targetWidth, finalize: true);
      if (Globals.isStandaloneLauncher) {
        _launcherAnimatedOnce = true;
        WinUtils.fixDrawBug();
        Win32.setCenter(useMouse: true);
        Win32.setWindowInvisible(false);
      }
      return;
    }

    final bool fadedOut = await _fadePluginWindowTo(0, transitionVersion, curve: Curves.easeInCubic);
    if (!fadedOut) return;

    await _setPluginWindowWidth(targetWidth);
    if (!mounted || transitionVersion != _pluginWindowTransitionVersion) return;

    WinUtils.fixDrawBug();
    final bool fadedIn = await _fadePluginWindowTo(1, transitionVersion, curve: Curves.easeOutCubic);
    if (!fadedIn) return;
    if (mounted && transitionVersion == _pluginWindowTransitionVersion) setState(() {});
  }

  Future<bool> _fadePluginWindowTo(double targetOpacity, int transitionVersion, {required Curve curve}) async {
    final double startOpacity = _pluginWindowOpacity;
    if ((startOpacity - targetOpacity).abs() < 0.01) {
      return mounted && transitionVersion == _pluginWindowTransitionVersion;
    }

    final Animation<double> opacity = Tween<double>(begin: startOpacity, end: targetOpacity).animate(
      CurvedAnimation(parent: _pluginWindowTransitionController, curve: curve),
    );
    void onTick() {
      _pluginWindowOpacity = opacity.value;
      unawaited(WindowManager.instance.setOpacity(_pluginWindowOpacity));
    }

    _pluginWindowTransitionController
      ..duration = const Duration(milliseconds: 120)
      ..addListener(onTick);
    try {
      await _pluginWindowTransitionController.forward(from: 0).orCancel;
    } on TickerCanceled {
      // A newer plugin frame superseded this transition.
    } finally {
      _pluginWindowTransitionController.removeListener(onTick);
    }
    if (!mounted || transitionVersion != _pluginWindowTransitionVersion) return false;
    _pluginWindowOpacity = targetOpacity;
    await WindowManager.instance.setOpacity(targetOpacity);
    return mounted && transitionVersion == _pluginWindowTransitionVersion;
  }

  Future<void> _setPluginWindowWidth(double width, {bool finalize = false}) async {
    await WindowManager.instance.setSize(Size(width, Globals.launcherSize.height));
    if (!mounted) return;
    Win32.setCenter(useMouse: true);
    if (!finalize) return;
    WinUtils.fixDrawBug();
  }

  /// Moves the plugin selection and notifies the script (drives the preview).
  void _setPluginSelection(int index, {bool fromKeyboard = false}) {
    final PluginRenderFrame? frame = _pluginFrame;
    if (frame == null || index < 0 || index >= frame.items.length) return;
    _activeIndexNotifier.value = index;
    if (fromKeyboard) {
      _hasKeyboardNavigatedCurrentQuery = true;
      _pluginKeyboardSelectedItemId = frame.items[index].id;
      _pluginKeyboardSelectedIndex = index;
    } else if (_hasKeyboardNavigatedCurrentQuery) {
      // A real hover after keyboard navigation is newer user intent. Keep the
      // durable anchor in sync so the next async plugin frame does not jump
      // back to the row that was selected before the pointer moved.
      _pluginKeyboardSelectedItemId = frame.items[index].id;
      _pluginKeyboardSelectedIndex = index;
    }
    if (frame.page != null) _pluginPageSelectionIds[frame.page!.id] = frame.items[index].id;
    _pluginHost.sendSelect(frame.items[index].id, scope: frame.scope());
  }

  /// Fires the default action for the selected plugin item (Enter / tap).
  void _submitPluginItem() {
    final PluginManifest? plugin = _activePlugin;
    // `inputMode: "submit"` — Enter delivers the query text (chat-style) when
    // it changed since the last submit; unchanged text falls through to the
    // selected item's default action so arrows+Enter still work.
    if (_pluginFrame?.submitInput == true && plugin != null) {
      final String text = PluginRegistry.queryAfterKeyword(_controller.text, plugin);
      if (text.trim().isNotEmpty && text != _pluginLastSubmittedQuery) {
        _pluginLastSubmittedQuery = text;
        _pluginHost.sendSubmitQuery(text, scope: _topPluginScope);
        // A submit-mode frame is a chat-style composer. Reset it immediately
        // so the next Enter sends a new message instead of an item action.
        final String launchKeyword = PluginRegistry.launchKeyword(plugin);
        _controller.value = TextEditingValue(
          text: '$launchKeyword ',
          selection: TextSelection.collapsed(offset: launchKeyword.length + 1),
        );
        _pluginLastSubmittedQuery = null;
        return;
      }
    }
    // In a bulk-selection frame, Enter has the same intent as clicking the
    // checkbox: mark/unmark the highlighted row. Batch work remains available
    // through the frame's Ctrl+K actions.
    final PluginRenderFrame? selectionFrame = _pluginFrame;
    if (selectionFrame?.multiSelect == true && selectionFrame!.items.isNotEmpty) {
      final int index = _activeIndexNotifier.value.clamp(0, selectionFrame.items.length - 1);
      _togglePluginSelection(selectionFrame.scope(), selectionFrame.items[index].id);
      return;
    }
    // A query keystroke is still waiting out its debounce: the visible frame
    // predates what the user typed, so submitting now would fire the stale
    // (unfiltered) list's item. Flush the query and defer the submit until the
    // frame answering it arrives.
    if ((_pluginQueryDebounce?.isActive ?? false) && plugin != null) {
      _pluginQueryDebounce!.cancel();
      _pluginSubmitPending = true;
      _pluginHost.sendQuery(PluginRegistry.queryAfterKeyword(_controller.text, plugin));
      return;
    }
    final PluginRenderFrame? frame = _pluginFrame;
    if (frame == null || frame.items.isEmpty) return;
    final int idx = _activeIndexNotifier.value.clamp(0, frame.items.length - 1);
    _submitPluginItemAction(frame.items[idx], scope: frame.scope());
  }

  void _submitPluginItemAction(PluginItem item, {required PluginEventScope scope}) {
    // Enter fires "default"; when the item *lists* a default action with a
    // confirm/destructive gate, honor it.
    PluginAction? declared;
    for (final PluginAction action in item.actions) {
      if (action.id == 'default') declared = action;
    }
    _firePluginAction(scope, item.id, declared ?? const PluginAction(id: 'default', title: ''));
  }

  /// Central action dispatch: shows the action's confirm gate (if any), then
  /// forwards it to the plugin. [itemId] is empty for frame-level actions.
  Future<void> _firePluginAction(PluginEventScope scope, String itemId, PluginAction action) async {
    Map<String, Object?>? parameters;
    if (action.parameters.isNotEmpty) {
      parameters = await showModalBottomSheet<Map<String, Object?>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.transparent,
        builder: (_) => PluginActionParametersPanel(action: action),
      );
      if (parameters == null || _activePlugin == null) return;
    }
    final PluginRenderFrame? scopedFrame = _frameForScope(scope);
    final Set<String> selectedIds = _selectedIdsFor(scope);
    final List<String> ids = scopedFrame?.multiSelect == true && selectedIds.isNotEmpty
        ? selectedIds.toList(growable: false)
        : const <String>[];
    if (action.confirm == null) {
      _pluginHost.sendAction(itemId, action.id, ids: ids, parameters: parameters, scope: scope);
      return;
    }
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      builder: (_) => PluginConfirmPanel(action: action),
    ).then((bool? confirmed) {
      if (confirmed == true && _activePlugin != null) {
        _pluginHost.sendAction(itemId, action.id, ids: ids, parameters: parameters, scope: scope);
      }
    });
  }

  void _togglePluginSelection(PluginEventScope scope, String id) {
    final PluginRenderFrame? frame = _frameForScope(scope);
    if (frame?.multiSelect != true) return;
    final Set<String> selectedIds = _selectedIdsFor(scope);
    setState(() {
      if (selectedIds.contains(id)) {
        selectedIds.remove(id);
      } else if (frame!.multiSelectMax == null || selectedIds.length < frame.multiSelectMax!) {
        selectedIds.add(id);
      }
    });
  }

  void _openPluginActions() {
    final PluginRenderFrame? frame = _pluginFrame;
    if (frame == null) return;
    final PluginManifest? plugin = _activePlugin;
    final File? readme = plugin == null ? null : File('${plugin.directory}${Platform.pathSeparator}README.md');
    final bool hasReadme = readme?.existsSync() ?? false;
    PluginItem? item;
    if (frame.items.isNotEmpty &&
        frame.view != PluginViewType.detail &&
        frame.view != PluginViewType.chat &&
        frame.view != PluginViewType.form) {
      item = frame.items[_activeIndexNotifier.value.clamp(0, frame.items.length - 1)];
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      builder: (_) => PluginActionsPanel(
        item: item,
        frameActions: frame.frameActions,
        launcherWindowAction: _launcherWindowAction,
        onLauncherWindowSelected: _handleLauncherWindowAction,
        onSelected: (PluginAction action, {required bool isFrameAction}) =>
            _firePluginAction(frame.scope(), isFrameAction ? '' : (item?.id ?? ''), action),
        readmeAction:
            hasReadme ? const PluginAction(id: '__readme__', title: 'Read README.md', icon: 'description') : null,
        onReadmeSelected: hasReadme ? () => _openPluginReadme(plugin!, readme!) : null,
      ),
    );
  }

  /// Matches a key press against the shortcuts declared by the highlighted
  /// item's actions and the frame's actions; fires the first hit.
  Future<void> _openPluginReadme(PluginManifest plugin, File readme) async {
    try {
      final String markdown = await readme.readAsString();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.transparent,
        builder: (_) => PluginReadmePanel(pluginName: plugin.name, markdown: markdown),
      );
    } catch (_) {
      _showPluginToast('Could not read README.md', style: 'error');
    }
  }

  bool _handlePluginShortcut(KeyEvent event) {
    final PluginRenderFrame? frame = _pluginFrame;
    if (frame == null) return false;
    final PluginShortcut? launcherWindowShortcut = PluginShortcut.parse(_launcherWindowAction.shortcut);
    if (launcherWindowShortcut != null && launcherWindowShortcut.matches(event)) {
      unawaited(_handleLauncherWindowAction());
      return true;
    }
    PluginItem? item;
    if (frame.items.isNotEmpty) {
      item = frame.items[_activeIndexNotifier.value.clamp(0, frame.items.length - 1)];
    }
    for (final PluginAction action in item?.actions ?? const <PluginAction>[]) {
      final PluginShortcut? shortcut = PluginShortcut.parse(action.shortcut);
      if (shortcut != null && shortcut.matches(event)) {
        _firePluginAction(frame.scope(), item!.id, action);
        return true;
      }
    }
    for (final PluginAction action in frame.frameActions) {
      final PluginShortcut? shortcut = PluginShortcut.parse(action.shortcut);
      if (shortcut != null && shortcut.matches(event)) {
        _firePluginAction(frame.scope(), '', action);
        return true;
      }
    }
    for (final PluginAction action in frame.floatingActions) {
      final PluginShortcut? shortcut = PluginShortcut.parse(action.shortcut);
      if (shortcut != null && shortcut.matches(event)) {
        _firePluginAction(frame.scope(), '', action);
        return true;
      }
    }
    return false;
  }

  Future<void> _handleLauncherWindowAction() async {
    if (Globals.isStandaloneLauncher) {
      await windowManager.close();
      return;
    }
    try {
      await Process.start(
        Platform.resolvedExecutable,
        <String>['-launcher', _controller.text],
        mode: ProcessStartMode.detached,
        runInShell: false,
      );
      QuickMenuFunctions.hideQuickMenu();
    } catch (_) {
      _showPluginToast('Could not open external launcher', style: 'error');
    }
  }

  /// Handles key events while a plugin owns the launcher. Returns
  /// [KeyEventResult.ignored] to let the normal handler run.
  KeyEventResult _handlePluginKey(KeyEvent event) {
    final PluginRenderFrame? frame = _pluginFrame;
    if (frame == null) {
      // Process launched but no frame yet — still swallow Escape so it exits.
      if (event.logicalKey == LogicalKeyboardKey.escape && event is KeyDownEvent) {
        _exitPlugin();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // if (event is KeyDownEvent &&
    //     event.logicalKey == LogicalKeyboardKey.keyK &&
    //     HardwareKeyboard.instance.isControlPressed) {

    if (event is KeyDownEvent &&
        ((event.logicalKey == LogicalKeyboardKey.keyK && HardwareKeyboard.instance.isControlPressed) ||
            event.logicalKey == LogicalKeyboardKey.tab)) {
      _openPluginActions();
      return KeyEventResult.handled;
    }
    // Plugin-declared action shortcuts (item's, then frame's).
    if (event is KeyDownEvent && _handlePluginShortcut(event)) return KeyEventResult.handled;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      // A frame that declared canGoBack owns Escape: the plugin renders its
      // previous screen. Root frames exit the plugin as usual.
      if (event is KeyDownEvent) {
        if (_pluginCanGoBack) {
          _sendPluginBack();
        } else {
          _exitPlugin();
        }
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      // Forward Tab with the highlighted item so plugins can autocomplete
      // (typically answered with a setQuery command). Swallowing it also stops
      // focus traversal from leaving the search field.
      if (event is KeyDownEvent) {
        final int count = frame.items.length;
        final String id = count == 0 ? '' : frame.items[_activeIndexNotifier.value.clamp(0, count - 1)].id;
        _pluginHost.sendTab(id, scope: frame.scope());
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (event is KeyDownEvent) _submitPluginItem();
      return KeyEventResult.handled;
    }

    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.space &&
        HardwareKeyboard.instance.isControlPressed &&
        frame.multiSelect &&
        frame.items.isNotEmpty) {
      _togglePluginSelection(
          frame.scope(), frame.items[_activeIndexNotifier.value.clamp(0, frame.items.length - 1)].id);
      return KeyEventResult.handled;
    }

    // Detail (markdown document) view: arrows and page keys scroll the
    // document. Home/End are left alone — they move the caret in the search
    // field.
    if (frame.view == PluginViewType.detail || frame.view == PluginViewType.chat) {
      return _scrollPluginDetail(event.logicalKey, isRepeat: event is KeyRepeatEvent);
    }

    final int count = frame.items.length;
    if (count == 0) return KeyEventResult.ignored;

    final bool isGrid = frame.view == PluginViewType.grid || frame.view == PluginViewType.gallery;
    final int cols = frame.view == PluginViewType.gallery
        ? frame.galleryColumns
        : isGrid
            ? frame.gridColumns
            : 1;
    int index = _activeIndexNotifier.value.clamp(0, count - 1);
    final LogicalKeyboardKey key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowDown) {
      index = isGrid ? (index + cols).clamp(0, count - 1) : (index + 1).clamp(0, count - 1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      if ((!isGrid && index == 0) || (isGrid && index < cols)) {
        _focusSearch();
        return KeyEventResult.handled;
      }
      index = isGrid ? index - cols : index - 1;
    } else if (isGrid && key == LogicalKeyboardKey.arrowRight) {
      index = (index + 1).clamp(0, count - 1);
    } else if (isGrid && key == LogicalKeyboardKey.arrowLeft) {
      index = (index - 1).clamp(0, count - 1);
    } else if (key == LogicalKeyboardKey.home) {
      index = 0;
    } else if (key == LogicalKeyboardKey.end) {
      index = count - 1;
    } else {
      return KeyEventResult.ignored;
    }

    _setPluginSelection(index, fromKeyboard: true);
    return KeyEventResult.handled;
  }

  /// Scrolls the plugin detail document for arrow/page keys. Key repeats jump
  /// instead of animating so held keys don't lag behind.
  KeyEventResult _scrollPluginDetail(LogicalKeyboardKey key, {required bool isRepeat}) {
    if (!_pluginDetailScroll.hasClients) return KeyEventResult.ignored;
    final ScrollPosition position = _pluginDetailScroll.position;
    final double page = position.viewportDimension * 0.85;
    final double delta;
    if (key == LogicalKeyboardKey.arrowDown) {
      delta = 60;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      delta = -60;
    } else if (key == LogicalKeyboardKey.pageDown) {
      delta = page;
    } else if (key == LogicalKeyboardKey.pageUp) {
      delta = -page;
    } else {
      return KeyEventResult.ignored;
    }
    final double target = (position.pixels + delta).clamp(0.0, position.maxScrollExtent);
    if (isRepeat) {
      _pluginDetailScroll.jumpTo(target);
    } else {
      _pluginDetailScroll.animateTo(target, duration: const Duration(milliseconds: 110), curve: Curves.easeOutCubic);
    }
    return KeyEventResult.handled;
  }

  Widget _buildPluginBody() {
    final PluginRenderFrame? frame = _pluginFrame;
    final Widget body;
    if (frame == null) {
      body = const Center(
        child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    } else {
      body = ValueListenableBuilder<int>(
        valueListenable: _activeIndexNotifier,
        builder: (BuildContext context, int activeIndex, Widget? _) {
          return ValueListenableBuilder<bool>(
            valueListenable: _isRepeatingKey,
            builder: (BuildContext context, bool isRepeating, Widget? __) {
              return PluginView(
                frame: frame,
                activeIndex: activeIndex,
                isRepeating: isRepeating,
                onTapItem: (PluginEventScope scope, PluginRenderFrame sourceFrame, int i) {
                  final PluginItem item = sourceFrame.items[i];
                  if (identical(sourceFrame, frame)) {
                    _setPluginSelection(i);
                    _submitPluginItem();
                  } else {
                    _submitPluginItemAction(item, scope: scope);
                  }
                },
                onHoverItem: (PluginEventScope scope, PluginRenderFrame sourceFrame, int i) {
                  if (identical(sourceFrame, frame)) {
                    _setPluginSelection(i);
                  } else {
                    _pluginHost.sendSelect(sourceFrame.items[i].id, scope: scope);
                  }
                },
                onFormSubmit: _onPluginFormSubmit,
                onFormCancel: _onPluginFormCancel,
                onFormChange: _onPluginFormChange,
                onFormValidate: (PluginEventScope scope, String fieldId, Map<String, Object?> values) =>
                    _pluginHost.sendFormValidate(fieldId, values, scope: scope),
                onLoadMore: (PluginEventScope scope) => _pluginHost.sendLoadMore(scope: scope),
                onEmptyAction: (PluginEventScope scope, PluginAction action) => _firePluginAction(scope, '', action),
                onMetadataAction: _firePluginAction,
                onFloatingAction: (PluginEventScope scope, PluginAction action) => _firePluginAction(scope, '', action),
                selectedIdsFor: _selectedIdsFor,
                onToggleSelection: _togglePluginSelection,
                onToggleTree: (PluginEventScope scope, String id, bool expanded) =>
                    _pluginHost.sendToggle(id, expanded, scope: scope),
                onChartSelect: (PluginEventScope scope, String seriesId, int index, double value) =>
                    _pluginHost.sendChartSelect(seriesId, index, value, scope: scope),
                onChartRangeSelect: (PluginEventScope scope, int startIndex, int endIndex) =>
                    _pluginHost.sendChartRangeSelect(startIndex, endIndex, scope: scope),
                onToolbarChange: (
                  PluginEventScope scope,
                  String id, {
                  String? value,
                  List<String>? values,
                  String? direction,
                }) =>
                    _pluginHost.sendToolbarChange(
                  id,
                  value: value,
                  values: values,
                  direction: direction,
                  scope: scope,
                ),
                onTableSort: (PluginEventScope scope, String columnId, String direction) =>
                    _pluginHost.sendTableSort(columnId, direction, scope: scope),
                onInlineEdit: (PluginEventScope scope, String itemId, String field, Object? value) =>
                    _pluginHost.sendEdit(itemId, field, value, scope: scope),
                onDropFiles: (PluginEventScope scope, String dropZoneId, List<String> paths) =>
                    _pluginHost.sendDrop(dropZoneId, paths, scope: scope),
                onCancelOperation: (PluginEventScope scope, String id) => _pluginHost.sendCancel(id, scope: scope),
                onNavigate: (String targetPageId) => _pluginHost.sendNavigate(targetPageId, scope: frame.scope()),
                onNavigateBack: _sendPluginBack,
                canNavigateBack: _pluginCanGoBack,
                onKanbanMove: (PluginEventScope scope, String id, String columnId, int index) =>
                    _pluginHost.sendKanbanMove(id, columnId, index, scope: scope),
                onCalendarNavigate: (PluginEventScope scope, String date, String mode) =>
                    _pluginHost.sendCalendarNavigate(date, mode, scope: scope),
                onOpenActions: _openPluginActions,
                onMarkdownKeyEvent: _handlePluginKey,
                onItemNavigation: _requestPluginNavigationFocus,
                detailScrollController: _pluginDetailScroll,
              );
            },
          );
        },
      );
    }
    return Column(
      children: <Widget>[
        Expanded(
          child: Stack(
            children: <Widget>[
              Positioned.fill(child: body),
              if (_pluginToast != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 10,
                  child: Center(child: _buildPluginToast(_pluginToast!)),
                ),
            ],
          ),
        ),
        if (_activePlugin?.dev == true) PluginDebugConsole(log: _pluginHost.debugLog, pluginId: _activePlugin!.id),
      ],
    );
  }

  Widget _buildPluginToast(String message) {
    // Icon/tint per `toast` style; `progress` shows a spinner (indeterminate)
    // or a determinate ring, and stays pinned until updated.
    final (IconData, Color) look = switch (_pluginToastStyle) {
      'error' => (Icons.error_rounded, const Color(0xFFE5534B)),
      'info' => (Icons.info_rounded, Design.accent),
      'progress' => (Icons.hourglass_top_rounded, Design.accent),
      _ => (Icons.check_circle_rounded, Design.accent),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withAlpha(240),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: look.$2.withAlpha(70)),
        boxShadow: <BoxShadow>[
          BoxShadow(color: Colors.black.withAlpha(50), blurRadius: 14, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (_pluginToastStyle == 'progress')
            SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(strokeWidth: 2, value: _pluginToastProgress, color: look.$2),
            )
          else
            Icon(look.$1, size: 14, color: look.$2),
          const SizedBox(width: 6),
          Text(
            message,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Design.text),
          ),
        ],
      ),
    );
  }

  /// Launcher home shortcuts plus a discovery hint per installed plugin.
  List<LauncherSearchResultItem> _shortcutResults() {
    final List<LauncherSearchResultItem> availableShortcuts = WindowWatcherService.instance.isAvailable
        ? _launcherShortcuts
        : _launcherShortcuts
            .where((LauncherSearchResultItem item) => item.shortcut?.prefix != '.')
            .toList(growable: false);
    final List<PluginManifest> enabledPlugins =
        PluginRegistry.manifests.where((PluginManifest manifest) => manifest.enabled).toList(growable: false);
    if (enabledPlugins.isEmpty) return availableShortcuts;
    enabledPlugins.sort((PluginManifest a, PluginManifest b) => a.name.compareTo(b.name));
    return <LauncherSearchResultItem>[
      ...availableShortcuts,
      for (final (int index, PluginManifest plugin) in enabledPlugins.indexed)
        LauncherSearchResultItem.shortcut(LauncherShortcut(
          label: PluginRegistry.launchKeyword(plugin),
          caption: plugin.name,
          prefix: PluginRegistry.launchPrefix(plugin),
          icon: PluginIcons.resolve(plugin.icon),
          showDividerBefore: index == 0,
        )),
    ];
  }

  /// Suggests enabled plugins while the user is typing their effective
  /// keyword, e.g. `;weat` resolves to the `;weather ` launcher prefix.
  /// Returning null means the query is not using the configured plugin
  /// shortcut; an empty list means it is, but no plugin matches yet.
  List<LauncherSearchResultItem>? _pluginKeywordSuggestions(String query) {
    final String shortcut = PluginRegistry.shortcut;
    if (shortcut.isEmpty) return null;

    final String lowerQuery = query.toLowerCase();
    if (!lowerQuery.startsWith(shortcut.toLowerCase())) return null;

    final String typedKeyword = query.substring(shortcut.length);
    if (typedKeyword.contains(RegExp(r'\s'))) return null;

    final List<PluginManifest> matches = PluginRegistry.manifests
        .where(
          (PluginManifest plugin) =>
              plugin.enabled && PluginRegistry.launchKeyword(plugin).toLowerCase().startsWith(lowerQuery),
        )
        .toList()
      ..sort((PluginManifest a, PluginManifest b) {
        final int byKeyword =
            PluginRegistry.launchKeyword(a).toLowerCase().compareTo(PluginRegistry.launchKeyword(b).toLowerCase());
        if (byKeyword != 0) return byKeyword;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    return <LauncherSearchResultItem>[
      for (final PluginManifest plugin in matches)
        LauncherSearchResultItem.shortcut(LauncherShortcut(
          label: PluginRegistry.launchKeyword(plugin),
          caption: plugin.name,
          prefix: PluginRegistry.launchPrefix(plugin),
          icon: PluginIcons.resolve(plugin.icon),
        )),
    ];
  }

  void _openLauncherPanel(BuildContext context, Widget child) {
    showQuickMenuModal(
      context: context,
      // isScrollControlled: true,
      // backgroundColor: Colors.transparent,
      // barrierColor: Colors.transparent,
      child: child,
      heightFactor: 0.9,
      backdropFilter: true,
    );
  }
}
