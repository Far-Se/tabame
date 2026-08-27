part of '../../launcher.dart';

// ignore_for_file: annotate_overrides

// ---------------------------------------------------------------------------
// Keyboard, focus, and result-list navigation
// ---------------------------------------------------------------------------

mixin _KeyboardNavigationMixin on _LauncherStateMembersMixin {
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    // The results focus node also wraps plugin content. When one of its
    // descendants (for example, a plugin form field) owns primary focus, let
    // that control handle the key instead of redirecting input to the search.
    if (node == _resultsFocusNode && !node.hasPrimaryFocus) {
      return KeyEventResult.ignored;
    }

    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.keyP &&
          HardwareKeyboard.instance.isControlPressed &&
          _activePlugin == null) {
        final bool nextVisibility = !_isFilePreviewVisible;
        setState(() => _isFilePreviewVisible = nextVisibility);
        unawaited(Boxes.pref.setBool(LauncherState._filePreviewVisiblePreferenceKey, nextVisibility));
        return KeyEventResult.handled;
      }

      // A running plugin owns navigation/selection/actions.
      if (_activePlugin != null) {
        final PluginViewType? pluginView = _pluginFrame?.view;
        if (node == _searchFocusNode &&
            _pluginFrame?.items.isNotEmpty == true &&
            pluginView != PluginViewType.detail &&
            pluginView != PluginViewType.chat &&
            pluginView != PluginViewType.form &&
            (event.logicalKey == LogicalKeyboardKey.arrowDown || event.logicalKey == LogicalKeyboardKey.arrowUp)) {
          if (event is KeyDownEvent) _enterPluginResultBrowsing(event.logicalKey);
          return KeyEventResult.handled;
        }
        final KeyEventResult pluginResult = _handlePluginKey(event);
        if (pluginResult != KeyEventResult.ignored) return pluginResult;
      }
      if (_handleRaycastShortcutKey(node, event)) return KeyEventResult.handled;
      if (node == _resultsFocusNode) {
        final KeyEventResult editingResult = _handleResultEditingKey(event);
        if (editingResult != KeyEventResult.ignored) return editingResult;
      }
      if (event is KeyDownEvent &&
          ((event.logicalKey == LogicalKeyboardKey.keyK && HardwareKeyboard.instance.isControlPressed) ||
              event.logicalKey == LogicalKeyboardKey.tab)) {
        _openActionsForActiveResult();
        setState(() {});
        return KeyEventResult.handled;
      }
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.keyC &&
          HardwareKeyboard.instance.isControlPressed) {
        if (_activePlugin != null) return KeyEventResult.ignored;
        _copyItem();
        setState(() {});
        return KeyEventResult.handled;
      }
      // Ctrl+Enter or Ctrl+O: open the selected folder in Explorer.
      if (event is KeyDownEvent &&
          (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter ||
              event.logicalKey == LogicalKeyboardKey.keyO) &&
          HardwareKeyboard.instance.isControlPressed) {
        _openSelectedFolderInExplorer();
        return KeyEventResult.handled;
      }
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.keyT &&
          HardwareKeyboard.instance.isAltPressed) {
        if (Boxes.quickTimers.isNotEmpty) {
          _openLauncherPanel(context, const TimersWidget());
        }
        return KeyEventResult.handled;
      }
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.keyR &&
          HardwareKeyboard.instance.isAltPressed) {
        if (user.persistentReminders.isNotEmpty) {
          _openLauncherPanel(context, const RemindersPanel());
        }
        return KeyEventResult.handled;
      }
      // Handle launcher submission here instead of relying on TextField's
      // submit action. A design change rebuilds the TextField, which can leave
      // its submit action detached even though this focus node still receives
      // navigation keys.
      if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
        if (event is KeyDownEvent) _onSubmitted(_controller.text);
        return KeyEventResult.handled;
      }
      // Escape: go back to quickmenu
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        if (node == _resultsFocusNode) {
          if (event is KeyDownEvent) _focusSearch();
          return KeyEventResult.handled;
        }
        if (kReleaseMode) {
          QuickMenuFunctions.hideQuickMenu();
          Win32.activateWindow(Globals.lastFocusedWinHWND);
          return KeyEventResult.handled;
        }
        Win32.setWindowInvisible(true);
        Timer(const Duration(milliseconds: 100), () {
          WindowManager.instance.setSize(Size(Boxes.quickMenuWidth, Globals.quickMenuSize.height));
          Globals.quickMenuPage = QuickMenuPage.quickMenu;
          user.launcherSearchText = '';
          QuickMenuFunctions.refreshQuickMenu();
          Win32.setWindowInvisible(false);
        });
        return KeyEventResult.handled;
      }

      final bool isVerticalArrow =
          event.logicalKey == LogicalKeyboardKey.arrowDown || event.logicalKey == LogicalKeyboardKey.arrowUp;
      final bool isResultNavigationKey = isVerticalArrow ||
          (node == _resultsFocusNode &&
              (event.logicalKey == LogicalKeyboardKey.home || event.logicalKey == LogicalKeyboardKey.end));
      if (isResultNavigationKey) {
        if (node == _searchFocusNode) {
          if (event is KeyDownEvent) _enterResultBrowsing(event.logicalKey);
          return KeyEventResult.handled;
        }
        if (_lastPressedKey == event.logicalKey) return KeyEventResult.handled;
        _lastPressedKey = event.logicalKey;

        _handleKeyStep(event.logicalKey, initial: true);

        _keyRepeatTimer?.cancel();
        _keyRepeatTimer = Timer(const Duration(milliseconds: 350), () {
          _isRepeatingKey.value = true;
          _keyRepeatTimer = Timer.periodic(const Duration(milliseconds: 100), (Timer timer) {
            if (_lastPressedKey == null) {
              timer.cancel();
              _isRepeatingKey.value = false;
              return;
            }
            _handleKeyStep(_lastPressedKey!);
          });
        });
        return KeyEventResult.handled;
      }
    } else if (event is KeyUpEvent) {
      if (event.logicalKey == _lastPressedKey) {
        _lastPressedKey = null;
        _isRepeatingKey.value = false;
        _keyRepeatTimer?.cancel();
      }
    }
    return KeyEventResult.ignored;
  }

  /// Lets result browsing remain a real focus mode without making the user
  /// explicitly return to the search box before typing. Printable input and
  /// destructive editing keys move focus back and update the query in-place.
  KeyEventResult _handleResultEditingKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;

    final LogicalKeyboardKey key = event.logicalKey;
    final HardwareKeyboard keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed && key == LogicalKeyboardKey.keyA) {
      _focusSearch();
      _controller.selection = TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
      return KeyEventResult.handled;
    }
    if (keyboard.isControlPressed && key == LogicalKeyboardKey.keyV) {
      _focusSearch();
      unawaited(_pasteIntoSearch());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace) {
      _deleteFromSearch(backwards: true);
      _focusSearch();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete) {
      _deleteFromSearch(backwards: false);
      _focusSearch();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) {
      _focusSearch();
      return KeyEventResult.handled;
    }

    final String? character = event.character;
    final bool isPrintable =
        character != null && character.isNotEmpty && character.runes.every((int rune) => rune >= 0x20 && rune != 0x7F);
    final bool isCommandChord = keyboard.isMetaPressed || (keyboard.isControlPressed && !keyboard.isAltPressed);
    if (!isPrintable || isCommandChord) return KeyEventResult.ignored;

    _replaceSearchSelection(character);
    _focusSearch();
    return KeyEventResult.handled;
  }

  void _enterResultBrowsing(LogicalKeyboardKey key) {
    if (_results.isEmpty) return;
    _resultsFocusNode.requestFocus();
    final int current = _activeIndexNotifier.value.clamp(0, _results.length - 1);
    _activeIndexNotifier.value = key == LogicalKeyboardKey.arrowUp
        ? (current - 1 + _results.length) % _results.length
        : (current + 1) % _results.length;
    _rememberKeyboardResultSelection();
    _scrollToActiveIndex();
  }

  void _enterPluginResultBrowsing(LogicalKeyboardKey key) {
    final List<PluginItem> items = _pluginFrame?.items ?? const <PluginItem>[];
    if (items.isEmpty) return;
    _resultsFocusNode.requestFocus();
    final int current = _activeIndexNotifier.value.clamp(0, items.length - 1);
    _setPluginSelection(
      key == LogicalKeyboardKey.arrowUp ? (current - 1 + items.length) % items.length : (current + 1) % items.length,
      fromKeyboard: true,
    );
  }

  Future<void> _pasteIntoSearch() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted || data?.text == null) return;
    _replaceSearchSelection(data!.text!);
  }

  void _replaceSearchSelection(String replacement) {
    final TextSelection selection = _validSearchSelection();
    final String text = _controller.text;
    final String nextText = text.replaceRange(selection.start, selection.end, replacement);
    final int caret = selection.start + replacement.length;
    _controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: caret),
    );
    _onSearchChanged(nextText);
  }

  void _deleteFromSearch({required bool backwards}) {
    final TextSelection selection = _validSearchSelection();
    final String text = _controller.text;
    int start = selection.start;
    int end = selection.end;

    if (selection.isCollapsed) {
      if (backwards) {
        if (start == 0) return;
        start -= text.substring(0, start).characters.last.length;
      } else {
        if (end == text.length) return;
        end += text.substring(end).characters.first.length;
      }
    }

    final String nextText = text.replaceRange(start, end, '');
    _controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: start),
    );
    _onSearchChanged(nextText);
  }

  TextSelection _validSearchSelection() {
    final TextSelection selection = _controller.selection;
    if (selection.isValid && selection.start <= _controller.text.length && selection.end <= _controller.text.length) {
      return selection;
    }
    return TextSelection.collapsed(offset: _controller.text.length);
  }

  Future<void> _refreshLauncherCatalogs() async {
    try {
      await FileIndexer.instance.sync();
      await LauncherAppCatalogService.instance.sync();
    } catch (error, stackTrace) {
      debugPrint('Launcher: Failed to refresh launcher catalogs: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    if (!mounted) return;
    _onSearchChanged(_controller.text);
  }

  void _requestLauncherFocus({bool focusWindow = false}) {
    requestFocusIfNeeded(focusWindow);
    WidgetsBinding.instance.addPostFrameCallback((_) => requestFocusIfNeeded(focusWindow));
    _launcherFocusRetryTimer?.cancel();
    _launcherFocusRetryTimer = Timer(const Duration(milliseconds: 5), () => requestFocusIfNeeded(focusWindow));
  }

  /// Opening a plugin item is distinct from selecting markdown in its detail
  /// view: item navigation must restore the launcher's keyboard shortcuts.
  void _requestPluginNavigationFocus() {
    if (!mounted || _activePlugin == null || _pluginOwnsFormFocus) return;
    void restore() {
      if (mounted && _activePlugin != null && !_pluginOwnsFormFocus) {
        _resultsFocusNode.requestFocus();
      }
    }

    restore();
    WidgetsBinding.instance.addPostFrameCallback((_) => restore());
    _launcherFocusRetryTimer?.cancel();
    _launcherFocusRetryTimer = Timer(const Duration(milliseconds: 5), restore);
  }

  void _onFocusManagerChanged() {
    if (!_canFocusLauncher || _searchFocusNode.hasPrimaryFocus || _resultsFocusNode.hasPrimaryFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _requestLauncherFocus();
    });
  }

  // ignore: unused_element
  void _flashQuickActionResult(String id) {
    _quickActionSplashTimer?.cancel();
    setState(() => _quickActionSplashId = id);
    _quickActionSplashTimer = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      setState(() => _quickActionSplashId = null);
    });
  }

  void _handleKeyStep(LogicalKeyboardKey key, {bool initial = false}) {
    if (_results.isEmpty) return;
    if (key == LogicalKeyboardKey.arrowDown) {
      _activeIndexNotifier.value = (_activeIndexNotifier.value + 1).clamp(0, _results.length - 1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      if (_activeIndexNotifier.value == 0) {
        _rememberKeyboardResultSelection();
        _focusSearch();
        return;
      }
      _activeIndexNotifier.value = (_activeIndexNotifier.value - 1).clamp(0, _results.length - 1);
    } else if (key == LogicalKeyboardKey.home) {
      _activeIndexNotifier.value = 0;
    } else if (key == LogicalKeyboardKey.end) {
      _activeIndexNotifier.value = _results.length - 1;
    }
    _rememberKeyboardResultSelection();
    _scrollToActiveIndex();
  }

  bool _handleRaycastShortcutKey(FocusNode node, KeyEvent event) {
    if (_design != LauncherDesign.newCast || _activePlugin != null || event is! KeyDownEvent) return false;

    final HardwareKeyboard keyboard = HardwareKeyboard.instance;
    final bool hasModifier = keyboard.isControlPressed || keyboard.isMetaPressed;
    // Plain number keys remain available for search input. Once the user is
    // browsing results, they can jump directly without a modifier; from the
    // search field the familiar command/control chord is required.
    if (!hasModifier && node != _resultsFocusNode) return false;

    final LogicalKeyboardKey key = event.logicalKey;
    final int? shortcutIndex = switch (key) {
      LogicalKeyboardKey.digit1 || LogicalKeyboardKey.numpad1 => 0,
      LogicalKeyboardKey.digit2 || LogicalKeyboardKey.numpad2 => 1,
      LogicalKeyboardKey.digit3 || LogicalKeyboardKey.numpad3 => 2,
      LogicalKeyboardKey.digit4 || LogicalKeyboardKey.numpad4 => 3,
      LogicalKeyboardKey.digit5 || LogicalKeyboardKey.numpad5 => 4,
      LogicalKeyboardKey.digit6 || LogicalKeyboardKey.numpad6 => 5,
      LogicalKeyboardKey.digit7 || LogicalKeyboardKey.numpad7 => 6,
      LogicalKeyboardKey.digit8 || LogicalKeyboardKey.numpad8 => 7,
      _ => null,
    };
    if (shortcutIndex == null || shortcutIndex >= _results.length) return false;

    _resultsFocusNode.requestFocus();
    _activeIndexNotifier.value = shortcutIndex;
    _rememberKeyboardResultSelection();
    _scrollToActiveIndex();
    return true;
  }

  void _scrollToActiveIndex() {
    if (!_scrollController.hasClients || _results.isEmpty) return;
    final int index = _activeIndexNotifier.value;
    if (index < 0 || index >= _results.length) return;

    if (index == _results.length - 1) {
      _moveResultListTo(_scrollController.position.maxScrollExtent, animated: !_isRepeatingKey.value);
      return;
    }
    if (index == 0) {
      _moveResultListTo(0, animated: !_isRepeatingKey.value);
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients || _results.isEmpty) return;
      if (index != _activeIndexNotifier.value || index >= _results.length) return;

      final GlobalKey? itemKey = _resultKeys[_resultKeyId(_results[index], index)];
      final BuildContext? itemContext = itemKey?.currentContext;
      if (itemContext == null) {
        _scrollToActiveIndexFallback(index);
        return;
      }

      final RenderObject? itemRenderObject = itemContext.findRenderObject();
      final RenderObject? listRenderObject = _scrollController.position.context.storageContext.findRenderObject();
      if (itemRenderObject is! RenderBox || listRenderObject is! RenderBox) {
        _scrollToActiveIndexFallback(index);
        return;
      }

      final double itemTop =
          itemRenderObject.localToGlobal(Offset.zero).dy - listRenderObject.localToGlobal(Offset.zero).dy;
      final double itemBottom = itemTop + itemRenderObject.size.height;
      final double viewportHeight = _scrollController.position.viewportDimension;
      const double edgePadding = 6.0;

      double? nextOffset;
      if (itemTop < edgePadding) {
        nextOffset = _scrollController.offset + itemTop - edgePadding;
      } else if (itemBottom > viewportHeight - edgePadding) {
        nextOffset = _scrollController.offset + itemBottom - viewportHeight + edgePadding;
      }

      if (nextOffset == null) return;
      _moveResultListTo(nextOffset, animated: !_isRepeatingKey.value);
    });
  }

  void _scrollToActiveIndexFallback(int index) {
    if (!_scrollController.hasClients) return;

    const double estimatedItemHeight = 49.0;
    final double viewportHeight = _scrollController.position.viewportDimension;
    final double itemTop = index * estimatedItemHeight;
    final double itemBottom = itemTop + estimatedItemHeight;
    final double viewTop = _scrollController.offset;
    final double viewBottom = viewTop + viewportHeight;

    double? nextOffset;
    if (itemTop < viewTop) {
      nextOffset = itemTop;
    } else if (itemBottom > viewBottom) {
      nextOffset = itemBottom - viewportHeight;
    }

    if (nextOffset != null) {
      _moveResultListTo(nextOffset, animated: !_isRepeatingKey.value);
    }
  }

  void _scrollResultToCenter(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients || index < 0 || index >= _results.length) return;
      if (_centerRenderedResult(index)) return;

      // ListView.builder may not have built a distant design yet. Design rows
      // have a fixed extent, so move it into the cache first and refine the
      // alignment from its RenderBox on the following frame.
      _moveResultListTo(index * LauncherState._designResultExtent, animated: false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients || index < 0 || index >= _results.length) return;
        _centerRenderedResult(index);
      });
    });
  }

  bool _centerRenderedResult(int index) {
    final GlobalKey? itemKey = _resultKeys[_resultKeyId(_results[index], index)];
    final BuildContext? itemContext = itemKey?.currentContext;
    if (itemContext == null) return false;

    final RenderObject? itemRenderObject = itemContext.findRenderObject();
    final RenderObject? listRenderObject = _scrollController.position.context.storageContext.findRenderObject();
    if (itemRenderObject is! RenderBox || listRenderObject is! RenderBox) return false;

    final double itemTop =
        itemRenderObject.localToGlobal(Offset.zero).dy - listRenderObject.localToGlobal(Offset.zero).dy;
    final double itemCenter = itemTop + itemRenderObject.size.height / 2;
    final double targetOffset =
        _scrollController.offset + itemCenter - _scrollController.position.viewportDimension / 2;
    _moveResultListTo(targetOffset, animated: true);
    return true;
  }

  void _moveResultListTo(double offset, {required bool animated}) {
    final double clampedOffset = offset.clamp(0.0, _scrollController.position.maxScrollExtent);
    if ((clampedOffset - _scrollController.offset).abs() < 0.5) return;

    if (!animated) {
      _scrollController.jumpTo(clampedOffset);
      return;
    }

    _scrollController.animateTo(
      clampedOffset,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
    );
  }

  // Remove this field entirely:
  // And _startWindowRefreshLoop becomes simply:
  void _startWindowRefreshLoop() {
    _windowRefreshTimer?.cancel();
    _windowRefreshTimer = Timer.periodic(const Duration(milliseconds: 900), (Timer timer) async {
      if (!mounted || Globals.quickMenuPage != QuickMenuPage.launcher) return;

      final WindowWatcherService watcher = WindowWatcherService.instance;
      final bool updated = await watcher.refresh();
      if (watcher.containsExecutable('taskmgr.exe')) {
        await TrayWatcher.fetchTray();
      }
      if (!mounted || !updated || Globals.quickMenuPage != QuickMenuPage.launcher) return;

      _refreshVisibleWindowResults();
    });
  }

  void _refreshVisibleWindowResults() {
    if (_results.isEmpty) return;
    // A new query is in flight: the rows on screen belong to the previous
    // query and are about to be replaced — patching them now would stamp them
    // with the current query text (see _setResults) and let the stale
    // selection be carried over into the new results.
    if (_isSearching) return;

    bool changed = false;
    final Map<PlatformWindow, PlatformWindow> latestWindows = <PlatformWindow, PlatformWindow>{
      for (final PlatformWindow window in WindowWatcherService.instance.windows) window: window,
    };

    final List<LauncherSearchResultItem> nextResults = <LauncherSearchResultItem>[];

    for (final LauncherSearchResultItem result in _results) {
      final PlatformWindow? currentWindow = result.window;

      // Not a window item — keep as-is
      if (currentWindow == null) {
        nextResults.add(result);
        continue;
      }

      final PlatformWindow? latestWindow = latestWindows[currentWindow];

      // Window no longer exists — drop it
      if (latestWindow == null) {
        changed = true;
        continue;
      }

      // Window exists but something changed — update it
      if (latestWindow.title != currentWindow.title ||
          latestWindow.executable != currentWindow.executable ||
          latestWindow.isPinned != currentWindow.isPinned ||
          latestWindow.helpText != currentWindow.helpText) {
        changed = true;
        nextResults.add(LauncherSearchResultItem.window(latestWindow));
        continue;
      }

      // Unchanged — keep as-is
      nextResults.add(result);
    }

    if (!changed || !mounted) return;
    _setResults(nextResults, resetSelection: false);
  }

  void _consumePendingQuickMenuSearchInput() {
    if (!_canConsumePendingInput) return;

    final String pendingLauncherQuickAction = Globals.takeLauncherQuickAction();
    final bool hasPendingAction = pendingLauncherQuickAction.isNotEmpty;
    if (hasPendingAction) {
      _pendingLauncherQuickAction = pendingLauncherQuickAction;
      _pendingLauncherQuickActionAttempt = 0;
    }

    final String pending = Globals.takeQuickMenuSearchInput();
    final bool replaceExisting = Globals.takeQuickMenuSearchInputReplacement();
    if (pending.isEmpty) {
      // A quick action may have been queued without (or after losing) its
      // accompanying search text. Re-run the current search anyway so the
      // pending action still gets its chance to execute once results render.
      if (hasPendingAction) _onSearchChanged(_controller.text);
      return;
    }

    final TextEditingValue currentValue = _controller.value;
    if (replaceExisting) {
      _controller.value = currentValue.copyWith(
        text: pending,
        selection: TextSelection.collapsed(offset: pending.length),
        composing: TextRange.empty,
      );
      _onSearchChanged(pending);
      return;
    }
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

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  void _focusSearch() {
    if (!mounted) return;
    final TextSelection selection = _validSearchSelection();
    _searchFocusNode.requestFocus();
    _controller.selection = selection;
  }
}
