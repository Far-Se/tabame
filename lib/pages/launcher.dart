// ignore_for_file: annotate_overrides

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;
import 'package:markdown_widget/markdown_widget.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' hide Row;
import '../platform/windows/tabamewin32_api.dart' show BrowserTab, BrowserTabs;
import '../platform/audio_system_service.dart';
import 'package:window_manager/window_manager.dart';
import '../models/tray_watcher.dart';
import '../models/util/quickmenu_modal.dart';
import 'launcher/plugins/plugin_icons.dart';
import 'launcher_actions_panel.dart';

import '../models/classes/boxes.dart';
import '../models/classes/saved_maps.dart';
import '../models/converter.dart';
import '../models/db/file_index_db.dart';
import '../models/globals.dart';
import '../platform/app_paths.dart';
import '../platform/clipboard_service.dart';
import '../models/google_translator.dart';
import '../models/settings.dart';
import '../models/util/theme_colors.dart';
import '../models/util/spotify_controller.dart';
import '../models/util/system_power.dart';
import '../models/win32/keys.dart';
import '../models/win32/win32.dart';
import '../models/win32/win_utils.dart';
import '../platform/platform_models.dart';
import '../platform/window_watcher_service.dart';
import '../services/file_indexer.dart';
import '../widgets/itzy/quickmenu/button_currency_converter.dart';
import '../widgets/itzy/quickmenu/button_notion.dart';
import '../widgets/itzy/quickmenu/button_obsidian.dart';
import '../widgets/itzy/quickmenu/button_quickactions.dart';
import '../widgets/itzy/quickmenu/button_steam.dart';
import '../widgets/itzy/quickmenu/button_timers.dart';
import '../widgets/itzy/quickmenu/button_workspaces.dart';
import '../widgets/itzy/quickmenu/button_persistent_reminders.dart';
import '../widgets/itzy/quickmenu/button_plugin_manager.dart';
import 'launcher/result/result_item_app.dart';
import 'launcher/result/result_item_bookmark.dart';
import 'launcher/result/result_item_browser_tab.dart';
import 'launcher/result/result_item_file.dart';
import 'launcher/result/result_item_window.dart';
import 'launcher/result/result_row.dart';
import 'launcher/search/bookmarks_search_handler.dart';
import 'launcher/search/browser_tabs_search_handler.dart';
import 'launcher/search/desktop_search_handler.dart';
import 'launcher/search/launcher_search_context.dart';
import 'launcher/search/recent_search_handler.dart';
import 'launcher/search/search_handler.dart';
import 'launcher/search/search_utils.dart';
import 'launcher/search/windows_search_handler.dart';
import 'launcher_search_models.dart';
import 'launcher/launcher_design.dart';

import 'launcher/launcher_design_builder.dart';
import 'launcher/core/launcher_result_executor.dart';
import 'launcher/plugins/plugin_actions_panel.dart';
import 'launcher/plugins/plugin_debug_console.dart';
import 'launcher/plugins/plugin_host.dart';
import 'launcher/plugins/plugin_manifest.dart';
import 'launcher/plugins/plugin_protocol.dart';
import 'launcher/plugins/plugin_registry.dart';
import 'launcher/plugins/plugin_shortcut.dart';
import 'launcher/plugins/plugin_view.dart';
import 'launcher/services/launcher_app_catalog_service.dart';
import 'launcher/services/windows_terminal_service.dart';

export 'launcher/result/result_item_bookmark.dart' show BookmarkSearchResult, BookmarkResultKind;
part 'launcher/launcher_helpers.dart';
part 'launcher/state/launcher_theme_mixin.dart';
part 'launcher/widgets/launcher_window_preview_panel.dart';
part 'launcher/widgets/launcher_file_preview_panel.dart';
part 'launcher/widgets/launcher_status_badges.dart';
part 'launcher/state/launcher_state_members_mixin.dart';
part 'launcher/state/plugin_host_mixin.dart';
part 'launcher/state/keyboard_navigation_mixin.dart';
part 'launcher/state/search_mixin.dart';
part 'launcher/state/result_actions_mixin.dart';
part 'launcher/state/result_row_builders_mixin.dart';

typedef LauncherFrameBuilder = Widget Function({
  required Color surface,
  required Color accent,
  required Color onSurface,
  required int resultCount,
  required Widget child,
});

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Launcher widget
// ---------------------------------------------------------------------------

class Launcher extends StatefulWidget {
  const Launcher({super.key});

  @override
  LauncherState createState() => LauncherState();
}

class LauncherState extends State<Launcher>
    with
        QuickMenuTriggers,
        SingleTickerProviderStateMixin,
        _LauncherStateMembersMixin,
        _LauncherThemeMixin,
        _PluginHostMixin,
        _KeyboardNavigationMixin,
        _SearchMixin,
        _ResultActionsMixin,
        _ResultRowBuildersMixin {
  static const double _minResultsHeight = 300;
  static const double _maxResultsHeight = 454;
  static const double _designResultExtent = 52;
  static const double _minPreviewAppWidth = 500;
  static const double _minPreviewPanelWidth = 180;
  static const double _minResultsPanelWidth = 180;
  static const double _previewResizeHandleWidth = 8;
  static const String _filePreviewVisiblePreferenceKey = 'launcherFilePreviewVisible';
  static const String _previewWidthPercentPreferenceKey = 'launcherPreviewWidthPercent';

  final LauncherSearchToken _searchToken = LauncherSearchToken();

  final TextEditingController _controller = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'Launcher search');
  final FocusNode _resultsFocusNode = FocusNode(debugLabel: 'Launcher results');
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _resultsViewportKey = GlobalKey();
  final GlobalKey _pluginsSectionHeaderKey = GlobalKey();
  final ValueNotifier<int> _activeIndexNotifier = ValueNotifier<int>(0);
  final ValueNotifier<bool> _isRepeatingKey = ValueNotifier<bool>(false);
  final Map<String, GlobalKey> _quickActionKeys = <String, GlobalKey>{};
  final Map<String, GlobalKey> _resultKeys = <String, GlobalKey>{};
  String? _infoText;
  IconData? _infoIcon;
  Timer? _infoTimer;
  String? _quickActionSplashId;
  bool _mouseSelectionEnabled = true;
  Offset? _lastMousePosition;
  Timer? _quickActionSplashTimer;
  Timer? _keyRepeatTimer;
  Timer? _launcherFocusRetryTimer;
  LogicalKeyboardKey? _lastPressedKey;
  bool _isRepairingFileIndex = false;
  final List<String> _copiedFiles = <String>[];
  LauncherDesign _design = LauncherDesign.serene;
  double _resultsMaxHeight = _maxResultsHeight;
  bool _isResizeHandleHovered = false;
  bool _isResizingResults = false;
  bool _isFilePreviewVisible = true;
  double? _previewWidthPercent;
  bool _isPluginsSectionActive = false;
  bool _resultsSectionHeaderUpdateScheduled = false;
  double? _pluginsSectionStartOffset;
  Object? _pluginsSectionResultsIdentity;

  final Map<String, PlatformWindowPreview> _windowPreviewCache = <String, PlatformWindowPreview>{};
  final Map<String, Future<PlatformWindowPreview?>> _windowPreviewCaptures = <String, Future<PlatformWindowPreview?>>{};
  final ValueNotifier<int> _windowPreviewCacheVersion = ValueNotifier<int>(0);
  final Set<String> _queuedWindowPreviewIds = <String>{};
  int _windowPreviewPrefetchGeneration = -1;
  int _windowPreviewPrefetchRun = 0;
  String? _lastHoveredWindowPreviewId;

  final List<String> _folderBrowsingStack = <String>[];
  final List<String> _folderBrowsingQueryStack = <String>[];

  List<LauncherSearchResultItem> _results = <LauncherSearchResultItem>[];
  String? _keyboardSelectedResultId;
  int _keyboardSelectedResultIndex = 0;
  bool _isSearching = false;
  bool _canConsumePendingInput = false;
  LauncherSearchMode _searchMode = LauncherSearchMode.mixed;

  // ── Plugin runtime ─────────────────────────────────────────────────────────
  // When a plugin keyword is active, the launcher hands its results area over to
  // an external script: `_pluginFrame` holds the latest JSON-described UI and
  // `_activePlugin` the running manifest. `_results` is empty in this mode.
  late final LauncherPluginHost _pluginHost = LauncherPluginHost(onFrame: _onPluginFrame, onCommand: _onPluginCommand);
  PluginManifest? _activePlugin;
  PluginRenderFrame? _pluginFrame;
  final Map<String, Set<String>> _pluginSelectedIdsByScope = <String, Set<String>>{};
  final Map<String, String> _pluginPageSelectionIds = <String, String>{};
  final List<String> _pluginPageHistory = <String>[];
  String? _pluginKeyboardSelectedItemId;
  int _pluginKeyboardSelectedIndex = 0;
  Timer? _pluginQueryDebounce;

  /// Set when Enter is pressed while a query is still waiting out its debounce:
  /// the visible frame predates what the user typed, so the submit is deferred
  /// until the fresh frame answering the flushed query arrives (see
  /// [_submitPluginItem] / [_onPluginFrame]).
  bool _pluginSubmitPending = false;
  bool _pluginWindowWidened = false;
  Timer? _pluginWidthCollapseTimer;
  late final AnimationController _pluginWindowTransitionController;
  double _pluginWindowOpacity = 1;
  int _pluginWindowTransitionVersion = 0;
  String? _pluginToast;
  Timer? _pluginToastTimer;

  /// Toast styling from the `toast` command: `success` (default), `error`,
  /// `info`, or `progress` (which pins the toast until a later update or a
  /// determinate `progress` value; re-sending the same `id` replaces it).
  String _pluginToastStyle = 'success';
  double? _pluginToastProgress;

  /// `inputMode: "submit"`: the last query text sent via `submitQuery`, so a
  /// second Enter on unchanged text activates the selected item instead of
  /// re-submitting.
  String? _pluginLastSubmittedQuery;

  /// Scrolls the detail (markdown document) view from arrow/page keys.
  final ScrollController _pluginDetailScroll = ScrollController();
  String? _pendingLauncherQuickAction;
  int _pendingLauncherQuickActionAttempt = 0;

  late final List<_LauncherFunctionCommand> _functionCommands = <_LauncherFunctionCommand>[
    _LauncherFunctionCommand(
      name: 'timer',
      description: 'Create a quick timer',
      usage: r'$timer 1 stretch',
      icon: Icons.timer_outlined,
      handler: _buildFunctionTimerResults,
    ),
    _LauncherFunctionCommand(
      name: 'clear',
      description: 'Clear cache folders',
      usage: r'$clear cache',
      icon: Icons.cleaning_services_rounded,
      handler: _buildFunctionClearResults,
    ),
    _LauncherFunctionCommand(
      name: 'translate',
      description: 'Translate text',
      usage: r'$t hello  •  $t hello from en  •  $t hello from en to ro',
      icon: Icons.translate_rounded,
      debounce: const Duration(milliseconds: 350),
      aliases: <String>['t'],
      streamingHandler: _streamFunctionTranslateResults,
    ),
    _LauncherFunctionCommand(
      name: 'reindex',
      description: 'Reindex launcher files',
      usage: r'$reindex files',
      icon: Icons.manage_search_rounded,
      handler: _buildFunctionReindexResults,
    ),
    _LauncherFunctionCommand(
      name: 'unit',
      description: 'Convert units',
      usage: r'$unit 10 km to mi',
      icon: Icons.straighten_rounded,
      handler: _buildFunctionUnitResults,
    ),
    _LauncherFunctionCommand(
      name: 'cur',
      description: 'Convert currency',
      usage: r'$cur 1 USD to EUR',
      icon: Icons.currency_exchange_rounded,
      aliases: <String>['currency'],
      handler: _buildFunctionCurrencyResults,
    ),
    _LauncherFunctionCommand(
      name: 'c',
      description: 'Calculate expression',
      usage: r'$c 1+3/5',
      icon: Icons.calculate_rounded,
      aliases: <String>['calc'],
      handler: _buildFunctionCalculatorResults,
    ),
    _LauncherFunctionCommand(
      name: 'design',
      description: 'Change launcher design',
      usage: r'$design serene',
      icon: Icons.palette_outlined,
      handler: _buildFunctionDesignResults,
    ),
    _LauncherFunctionCommand(
      name: 'sys',
      description: 'System power actions',
      usage: r'$sys shutdown',
      icon: Icons.power_settings_new_rounded,
      aliases: <String>['system', 'power'],
      handler: _buildFunctionSystemResults,
    ),
  ];

  late final List<LauncherSearchResultItem> _launcherShortcuts = <LauncherSearchResultItem>[
    const LauncherSearchResultItem.shortcut(LauncherShortcut(
      label: '/',
      caption: 'Quick Action',
      prefix: '/',
      icon: Icons.bolt_rounded,
    )),
    const LauncherSearchResultItem.shortcut(LauncherShortcut(
      label: '.',
      caption: 'Window Search',
      prefix: '.',
      icon: Icons.window_rounded,
    )),
    const LauncherSearchResultItem.shortcut(LauncherShortcut(
      label: ',',
      caption: 'Browser Tabs',
      prefix: ',',
      icon: Icons.tab_rounded,
    )),
    const LauncherSearchResultItem.shortcut(LauncherShortcut(
      label: "> or ? or space",
      caption: 'File Search',
      prefix: ">",
      icon: Icons.search_rounded,
    )),
    const LauncherSearchResultItem.shortcut(LauncherShortcut(
      label: "'",
      caption: 'Bookmarks / CLI / Apps',
      prefix: "'",
      icon: Icons.bookmark_rounded,
    )),
    const LauncherSearchResultItem.shortcut(LauncherShortcut(
      label: 'b ',
      caption: 'Bookmarks  ·  "b add <url>" to save',
      prefix: 'b ',
      icon: Icons.bookmark_rounded,
    )),
    const LauncherSearchResultItem.shortcut(LauncherShortcut(
      label: 'cli ',
      caption: 'CLI Commands',
      prefix: 'cli ',
      icon: Icons.terminal_rounded,
    )),
    const LauncherSearchResultItem.shortcut(LauncherShortcut(
      label: 'app ',
      caption: 'Apps',
      prefix: 'app ',
      icon: Icons.apps_rounded,
    )),
    const LauncherSearchResultItem.shortcut(LauncherShortcut(
      label: 'd ',
      caption: 'Desktop Files',
      prefix: 'd ',
      icon: Icons.desktop_windows_rounded,
    )),
    const LauncherSearchResultItem.shortcut(LauncherShortcut(
      label: 'n ',
      caption: 'Notion',
      prefix: 'n ',
      icon: Icons.description_rounded,
    )),
    const LauncherSearchResultItem.shortcut(LauncherShortcut(
      label: 'o ',
      caption: 'Obsidian',
      prefix: 'o ',
      icon: Icons.menu_book_rounded,
    )),
    const LauncherSearchResultItem.shortcut(LauncherShortcut(
      label: 'r ',
      caption: 'Recent Files',
      prefix: 'r ',
      icon: Icons.history_rounded,
    )),
    const LauncherSearchResultItem.shortcut(LauncherShortcut(
      label: 's ',
      caption: 'Steam Games',
      prefix: 's ',
      icon: Icons.sports_esports_rounded,
    )),
    const LauncherSearchResultItem.shortcut(LauncherShortcut(
      label: 't ',
      caption: 'Terminal Profiles',
      prefix: 't ',
      icon: Icons.terminal_rounded,
    )),
    const LauncherSearchResultItem.shortcut(LauncherShortcut(
      label: 'm or m[1-5]',
      caption: 'Media Control',
      prefix: 'm ',
      icon: Icons.music_note,
    )),
    const LauncherSearchResultItem.shortcut(LauncherShortcut(
      label: 'sp ',
      caption: 'Spotify',
      prefix: 'sp ',
      icon: Icons.music_note_rounded,
    )),
    const LauncherSearchResultItem.shortcut(LauncherShortcut(
      label: 'ws ',
      caption: 'Workspaces',
      prefix: 'ws ',
      icon: Icons.dashboard_customize_rounded,
    )),
    const LauncherSearchResultItem.shortcut(LauncherShortcut(
      label: r'$',
      caption: 'Functions',
      prefix: r'$',
      icon: Icons.functions_rounded,
    )),
    // const LauncherSearchResultItem.info(LauncherInfoResult(
    //   id: 'ctrlKInfo',
    //   title: 'Ctrl+K',
    //   subtitle: 'Opens Actions Menu for a specific result',
    //   icon: Icons.menu_rounded,
    // )),
    const LauncherSearchResultItem.info(LauncherInfoResult(
      id: 'ctrlCInfo',
      title: 'Ctrl+C',
      subtitle: 'Ctrl+K: Opens Actions Menu for a specific result Ctrl+C: Copy file/folder. Only for File Search',
      icon: Icons.menu_rounded,
    )),
    const LauncherSearchResultItem.shortcut(LauncherShortcut(
      label: '!',
      caption: 'Plugin Standalone Launcher',
      prefix: '!',
      icon: Icons.extension_rounded,
    )),
    const LauncherSearchResultItem.shortcut(LauncherShortcut(
      label: 'plugins',
      caption: 'Plugin Settings',
      prefix: '',
      icon: Icons.extension_outlined,
      opensPluginManager: true,
    )),
  ];

  // ignore: prefer_final_fields
  bool _launcherAnimatedOnce = false;

  @override
  void initState() {
    super.initState();
    _pluginWindowTransitionController = AnimationController(vsync: this);
    _scrollController.addListener(_updateResultsSectionHeader);
    QuickMenuFunctions.addListener(this);
    _design = user.launcherDesign;
    _isFilePreviewVisible = Boxes.pref.getBool(_filePreviewVisiblePreferenceKey) ?? true;
    _previewWidthPercent = Boxes.pref.getDouble(_previewWidthPercentPreferenceKey)?.clamp(0.0, 100.0).toDouble();
    _resultsMaxHeight = (Boxes.pref.getDouble('launcherResultsHeight') ?? _maxResultsHeight)
        .clamp(_minResultsHeight, _maxResultsHeight);
    // Rescan the plugins folder so freshly-dropped plugins are available without
    // an app restart. If a keyword becomes matchable after the scan, re-run the
    // current query so it activates.
    unawaited(PluginRegistry.load().then((_) {
      if (!mounted || _activePlugin != null) return;
      final String query = _controller.text;
      if (PluginRegistry.matchKeyword(query) != null ||
          _pluginKeywordSuggestions(query) != null ||
          LauncherQuery.parse(query).mode == LauncherSearchMode.pluginsOnly) {
        _onSearchChanged(query);
      }
    }));
    // if (Globals.isStandaloneLauncher == true) {
    //   Future<void>.delayed(const Duration(milliseconds: 300), () {
    //     _controller.text = user.launcherSearchText;
    //     setState(() {});
    //   });
    // } else {
    _controller.text = user.launcherSearchText;
    // }
    // _controller.selection = TextSelection.fromPosition(TextPosition(offset: _controller.text.length));
    _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
    Globals.quickMenuSearchInputVersion.addListener(_consumePendingQuickMenuSearchInput);
    FocusManager.instance.addListener(_onFocusManagerChanged);
    _searchFocusNode.onKeyEvent = _onKeyEvent;
    _resultsFocusNode.onKeyEvent = _onKeyEvent;

    _searchFocusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Win32.setWindowInvisible(false);
      _canConsumePendingInput = true;
      _startWindowRefreshLoop();
      _consumePendingQuickMenuSearchInput();
      _searchFocusNode.requestFocus();

      unawaited(_refreshLauncherCatalogs());

      _onSearchChanged(_controller.text);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final RenderBox box = context.findRenderObject() as RenderBox;
      Globals.launcherCurrentSize = box.size;
    });
    // Re-request focus after the window activation delay settles (the OS
    // Win32.activateWindow call in onQuickMenuShown fires ~100 ms after show).
    Future<void>.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        windowManager.focus();
        _focusSearch();
      }
    });
  }

  @override
  Future<void> onQuickMenuSwitchedPage(QuickMenuPage newType, QuickMenuPage oldType, bool visible) async {
    if (oldType == QuickMenuPage.launcher && newType != QuickMenuPage.launcher) {
      _deactivatePlugin();
    }
  }

  @override
  Future<void> onQuickMenuToggled(bool visible, QuickMenuPage type) async {
    if (!visible) _deactivatePlugin();
  }

  @override
  void dispose() {
    Globals.quickMenuPage = QuickMenuPage.quickMenu;
    QuickMenuFunctions.removeListener(this);
    _searchToken.dispose();
    _pluginQueryDebounce?.cancel();
    _pluginToastTimer?.cancel();
    _pluginDetailScroll.dispose();
    _pluginHost.dispose();
    // The host owns the process shutdown. Clear launcher-owned state here
    // without calling _exitPlugin after the controller has been disposed.
    _activePlugin = null;
    _pluginFrame = null;
    _pluginSelectedIdsByScope.clear();
    _pluginPageSelectionIds.clear();
    _pluginPageHistory.clear();
    Globals.isLauncherPluginActive = false;
    _pluginWindowTransitionVersion++;
    _pluginWindowTransitionController.stop();
    _restorePluginWindowWidth(animate: false);
    unawaited(WindowManager.instance.setOpacity(1));
    _pluginWindowTransitionController.dispose();
    _resultKeys.clear();
    _quickActionKeys.clear();

    user.launcherSearchText = '';
    Globals.quickMenuSearchInputVersion.removeListener(_consumePendingQuickMenuSearchInput);
    FocusManager.instance.removeListener(_onFocusManagerChanged);
    _isRepeatingKey.dispose();

    if (!FileIndexer.instance.isIndexing) {
      // Only close if we are certain no background work is running.
      // FileIndexDb will reopen automatically on next access if needed.
      FileIndexDb.instance.close();
    }
    // If indexing is still in progress, leave the DB open; it will be
    // closed the next time the launcher disposes while idle.
    Globals.clearQuickMenuSearchInput();

    _searchDebounce?.cancel();
    _infoTimer?.cancel();
    _pluginWidthCollapseTimer?.cancel();
    _quickActionSplashTimer?.cancel();
    _keyRepeatTimer?.cancel();
    _windowRefreshTimer?.cancel();
    _launcherFocusRetryTimer?.cancel();
    _controller.dispose();
    _searchFocusNode.dispose();
    _resultsFocusNode.dispose();
    _scrollController.removeListener(_updateResultsSectionHeader);
    _scrollController.dispose();
    _activeIndexNotifier.dispose();
    _windowPreviewCacheVersion.dispose();
    super.dispose();
  }

  @override
  void onQuickActionExecute(String actionName) {
    if (actionName == "page:quickMenu") {
      Globals.quickMenuPage = QuickMenuPage.quickMenu;
      if (mounted) setState(() {});
    }
  }

  @override
  Future<void> refreshQuickMenu() async {
    if (!mounted) return;
    setState(() => _design = user.launcherDesign);
  }

  @override
  void requestQuickMenuFocus() {
    _requestLauncherFocus(focusWindow: true);
    if (_activePlugin != null) _pluginHost.sendFocus();
  }

  bool get _pluginOwnsFormFocus {
    final PluginRenderFrame? frame = _pluginFrame;
    if (_activePlugin == null || frame == null) return false;
    return frame.view == PluginViewType.form ||
        (frame.view == PluginViewType.dashboard &&
            frame.dashboardPanels.any((PluginDashboardPanel panel) => panel.frame.view == PluginViewType.form));
  }

  bool get _canFocusLauncher {
    if (!mounted) return false;
    if (!QuickMenuFunctions.isQuickMenuVisible) return false;
    if (Globals.quickMenuPage != QuickMenuPage.launcher) return false;
    if (Navigator.of(context).canPop()) return false;
    // A plugin form owns focus while it is shown — the search field must not
    // steal keystrokes back from its inputs.
    if (_pluginOwnsFormFocus) return false;
    // Plugin markdown (detail view or the split preview pane) is wrapped in a
    // SelectionArea so users can select/copy text with the mouse. That widget
    // grabs focus on tap-drag; auto-reclaiming focus for the search field
    // would yank it away mid-selection and break Ctrl+C.
    if (_activePlugin != null && (_pluginFrame?.view == PluginViewType.detail || (_pluginFrame?.hasPreview ?? false))) {
      return false;
    }
    return true;
  }

  void requestFocusIfNeeded(bool focusWindow) {
    if (!_canFocusLauncher) return;
    if (focusWindow) unawaited(windowManager.focus());
    if (!_searchFocusNode.hasPrimaryFocus && !_resultsFocusNode.hasPrimaryFocus) {
      _focusSearch();
    }
  }

  Timer? _searchDebounce;
  Timer? _windowRefreshTimer;
  String _lastScrollResetQuery = '';
  DateTime? _lastFolderSyncTime;
  bool _isFolderSyncing = false;

  // ---------------------------------------------------------------------------
  // Search logic
  // ---------------------------------------------------------------------------

  int _searchGeneration = 0;

  bool _hasKeyboardNavigatedCurrentQuery = false;
  String _keyboardNavigationQuery = '';

  /// The query text that produced the currently displayed [_results].
  /// Selection is only carried over between result sets of the same query —
  /// results for a different query always start at the first row.
  String? _resultsQuery;

  /// A bare arithmetic expression made up only of digits, whitespace and the
  /// arithmetic characters `. ( ) + - * / ^ %`.
  static final RegExp _mathShorthandPattern = RegExp(r'^[\d\s.()+\-*/^%]+$');

  /// At least one binary operator, so plain numbers (`100`, `3.14`) stay ordinary
  /// searches and only genuine expressions (`12*3`, `(2+3)/5`) are calculated.
  static final RegExp _mathOperatorPattern = RegExp(r'[+\-*/^%]');

  /// Matches a math expression followed by a currency conversion, e.g.
  /// `30 + (3.79*3) usd to ron`. The expression part is restricted to
  /// arithmetic-safe characters so it doesn't hijack ordinary searches.
  static final RegExp _mathCurrencyShorthandPattern = RegExp(
    r'^([\d\s.()+\-*/^%]+?)\s+([a-z]{3,4})\s+(?:to|in|into)\s+([a-z]{3,4})$',
    caseSensitive: false,
  );

  /// Matches the `m ` / `m1 ` .. `m5 ` media command prefix. With no digit the
  /// command controls global media (media keys); with a digit it targets
  /// `Boxes.appAudioControls[digit - 1]`.
  static final RegExp _mediaCommandPrefixPattern = RegExp(r'^m([1-5])? ');

  static const List<_MediaCommandAction> _mediaCommandActions = <_MediaCommandAction>[
    _MediaCommandAction(
      id: 'stop',
      label: 'Stop',
      icon: Icons.stop_rounded,
      vk: VK.MEDIA_STOP,
      aliases: <String>['s', 'stop'],
    ),
    _MediaCommandAction(
      id: 'playPause',
      label: 'Play / Pause',
      icon: Icons.play_arrow_rounded,
      vk: VK.MEDIA_PLAY_PAUSE,
      aliases: <String>['p', 'play', 'pause'],
    ),
    _MediaCommandAction(
      id: 'next',
      label: 'Next',
      icon: Icons.skip_next_rounded,
      vk: VK.MEDIA_NEXT_TRACK,
      aliases: <String>['n', 'next'],
    ),
    _MediaCommandAction(
      id: 'previous',
      label: 'Previous',
      icon: Icons.skip_previous_rounded,
      vk: VK.MEDIA_PREV_TRACK,
      aliases: <String>['pr', 'prev', 'previous'],
    ),
  ];

  // ── Spotify ("sp ") ────────────────────────────────────────────────────────
  // Drives the Spotify desktop app through SMTC via [SpotifyController]. Shows a
  // now-playing hero row (Enter toggles play/pause) plus transport controls
  // filtered by the text after `sp `.

  static const List<({String id, String label, IconData icon, String command, List<String> aliases})>
      _spotifyControlActions = <({String id, String label, IconData icon, String command, List<String> aliases})>[
    (
      id: 'playPause',
      label: 'Play / Pause',
      icon: Icons.play_arrow_rounded,
      command: SpotifyController.cmdTogglePlayPause,
      aliases: <String>['p', 'play', 'pause', 'toggle'],
    ),
    (
      id: 'next',
      label: 'Next Track',
      icon: Icons.skip_next_rounded,
      command: SpotifyController.cmdNext,
      aliases: <String>['n', 'next', 'skip', 'forward'],
    ),
    (
      id: 'previous',
      label: 'Previous Track',
      icon: Icons.skip_previous_rounded,
      command: SpotifyController.cmdPrevious,
      aliases: <String>['pr', 'prev', 'previous', 'back'],
    ),
  ];

  /// Strips a leading `x = ` variable-assignment prefix (as produced by the
  /// calculator parser for each `|`-separated expression) so only the numeric
  /// result gets copied to the clipboard.
  static final RegExp _mathAssignmentPrefix = RegExp(r'^[a-zA-Z]\w*\s*=\s*');

  @override
  Widget build(BuildContext context) {
    final ThemeData appTheme = Theme.of(context);
    final ThemeData baseTheme = appTheme.copyWith(
      colorScheme: appTheme.colorScheme.copyWith(
        surface: Design.background,
        onSurface: Design.text,
        primary: Design.accent,
      ),
      highlightColor: Design.accent.withAlpha(30),
    );
    final bool isDark = baseTheme.brightness == Brightness.dark;
    final bool isTerminal = _design == LauncherDesign.terminal;
    final bool isTerminal2 = _design == LauncherDesign.terminal2;
    final bool isZen = _design == LauncherDesign.zen;
    final bool isGlass = _design == LauncherDesign.glass;
    final bool isBlueprint = _design == LauncherDesign.blueprint;
    final bool isTransit = _design == LauncherDesign.transit;
    final bool isFluent = _design == LauncherDesign.fluent;
    final bool isManifesto = _design == LauncherDesign.manifesto;
    final bool isOrbit = _design == LauncherDesign.orbit;
    final bool isAnime = _design == LauncherDesign.anime;
    final bool isWindowsXp = _design == LauncherDesign.windowsXp;
    final bool isWindows98 = _design == LauncherDesign.windows98;
    final bool isNotion = _design == LauncherDesign.notion;
    final bool isSwitchboard = _design == LauncherDesign.switchboard;
    final bool isRelay = _design == LauncherDesign.relay;
    final bool isRaycast = _design == LauncherDesign.newCast;
    // Terminal, Zen, Blueprint, Transit and Fluent force their own palette +
    // text theme. Every result builder reads its colors from this theme, so
    // they all inherit the look without per-builder branching. Terminal,
    // Transit and Fluent keep the user accent (phosphor / line color / Windows
    // accent); Zen replaces it with a calm moss, Blueprint with drafting ink.
    // Glass keeps the theme colors (its glass picks them up) and only forces
    // Inter for the iOS feel.
    final Color accent = switch (true) {
      _ when isZen => ZenTokens.accent(isDark),
      _ when isBlueprint => BlueprintTokens.accent(isDark),
      _ when isManifesto => ManifestoTokens.accent(isDark),
      _ when isWindowsXp => WindowsXpTokens.selection,
      _ when isWindows98 => Windows98Tokens.selection,
      _ when isNotion => NotionTokens.blue(isDark),
      _ => Design.accent,
    };
    final ThemeData designTheme = _buildDesignTheme(
      baseTheme: baseTheme,
      isDark: isDark,
      accent: accent,
    );
    final ThemeData theme =
        Design.useCustomFont ? designTheme.copyWith(textTheme: launcherTextTheme(designTheme.textTheme)) : designTheme;
    final Color onSurface = theme.colorScheme.onSurface;
    final bool hasInput = _controller.text.trim().isNotEmpty;
    final LauncherThemeData launcherTheme = LauncherThemeData(design: _design);

    // Build the shared inner content once — no per-design duplication.
    final Widget searchContent = _design.buildSearchBar(
      surface: theme.colorScheme.surface,
      accent: accent,
      onSurface: onSurface,
      dragHandle: MouseRegion(
        cursor: user.useCustomCursor ? Globals.customCursor ?? SystemMouseCursors.move : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanStart: (_) => windowManager.startDragging(),
          child: Icon(
            // Token-driven: no inline ternary on _design.
            launcherTheme.searchIcon,
            size: launcherTheme.searchIconSize,
            color: launcherTheme.searchIconUsesOnSurface ? onSurface.withAlpha(160) : accent,
          ),
        ),
      ),
      textField: TextField(
        controller: _controller,
        focusNode: _searchFocusNode,
        selectAllOnFocus: false,
        cursorColor: isTerminal2 ? accent : null,
        cursorWidth: isTerminal2 ? 7 : 2,
        cursorHeight: isTerminal2 ? 18 : null,
        cursorRadius: isTerminal2 ? Radius.zero : const Radius.circular(2),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: onSurface,
          fontSize: launcherTheme.searchFontSize,
          fontWeight: launcherTheme.searchFontWeight,
        ),
        decoration: InputDecoration(
          hintText: (_activePlugin != null ? _pluginFrame?.placeholder : null) ??
              launcherTheme.searchHint ??
              (isTerminal2 ? 'type a command or search the system...' : 'Search applications, files, bookmarks...'),
          hintStyle: TextStyle(color: isRaycast ? RaycastTokens.muted(isDark) : onSurface.withAlpha(70)),
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.only(
            left: 0,
            top: 6,
            bottom: 6,
            right: (_infoText != null || _copiedFiles.isNotEmpty) ? 120 : 8,
          ),
        ),
        onChanged: _onSearchChanged,
        onSubmitted: _onSubmitted,
      ),
      trailingBadge: _buildTrailingBadge(accent, onSurface),
      isSearching: _isSearching,
    );
    final ({int height, int width}) size = Win32.getSize();
    final Widget resultsContent = Focus(
      focusNode: _resultsFocusNode,
      skipTraversal: true,
      child: Material(
        type: MaterialType.transparency,
        child: ConstrainedBox(
          constraints:
              BoxConstraints(minHeight: 260, maxHeight: math.min(_resultsMaxHeight - 27, size.height.toDouble() - 27)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (_activePlugin == null && !hasInput && _results.isNotEmpty)
                _buildResultsHeaderWithBadges(accent, onSurface),
              if (_activePlugin != null)
                Expanded(child: _buildPluginBody())
              else if (_results.isEmpty && isSwitchboard)
                Expanded(
                  child: SwitchboardEmptyState(
                    isSearching: _isSearching,
                    hasQuery: hasInput,
                    accent: accent,
                  ),
                )
              else if (_results.isEmpty && isRelay)
                Expanded(
                  child: RelayEmptyState(
                    isSearching: _isSearching,
                    hasQuery: hasInput,
                    accent: accent,
                  ),
                )
              else
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: ValueListenableBuilder<int>(
                      valueListenable: _activeIndexNotifier,
                      builder: (BuildContext context, int activeIndex, Widget? child) {
                        return ValueListenableBuilder<bool>(
                          valueListenable: _isRepeatingKey,
                          builder: (BuildContext context, bool isRepeatingKey, Widget? child) {
                            final LauncherSearchResultItem? previewResult = _previewResultAt(activeIndex);
                            final FileSystemEntity? previewEntity = previewResult?.entity;
                            final PlatformWindow? previewWindow = previewResult?.window;
                            return LayoutBuilder(
                              builder: (BuildContext context, BoxConstraints constraints) {
                                final bool showPreview = _isFilePreviewVisible &&
                                    previewResult != null &&
                                    MediaQuery.sizeOf(context).width >= _minPreviewAppWidth;
                                final double appWidth = MediaQuery.sizeOf(context).width > 0
                                    ? MediaQuery.sizeOf(context).width
                                    : constraints.maxWidth;
                                final double maxPreviewWidth =
                                    (constraints.maxWidth - _minResultsPanelWidth - _previewResizeHandleWidth)
                                        .clamp(0, constraints.maxWidth)
                                        .toDouble();
                                final double minPreviewWidth =
                                    _minPreviewPanelWidth.clamp(0, maxPreviewWidth).toDouble();
                                final double preferredPreviewWidth = _previewWidthPercent == null
                                    ? constraints.maxWidth * 0.40
                                    : appWidth * _previewWidthPercent! / 100;
                                final double previewWidth =
                                    preferredPreviewWidth.clamp(minPreviewWidth, maxPreviewWidth).toDouble();
                                return Stack(
                                  children: <Widget>[
                                    Positioned.fill(
                                      child: Padding(
                                        key: _resultsViewportKey,
                                        padding: EdgeInsets.only(
                                          right: showPreview ? previewWidth + _previewResizeHandleWidth : 0,
                                        ),
                                        child: ListView.builder(
                                          controller: _scrollController,
                                          shrinkWrap: true,
                                          itemCount: _results.length,
                                          itemBuilder: (BuildContext context, int index) {
                                            final LauncherSearchResultItem result = _results[index];
                                            final bool isSelected = index == activeIndex;
                                            late final Widget resultWidget;
                                            if (result.isShortcut) {
                                              resultWidget = _buildShortcutResult(
                                                  context, theme, result.shortcut!, index, isSelected, isRepeatingKey);
                                            } else if (result.isFile) {
                                              resultWidget = _buildFileResult(context, theme, result.entity!,
                                                  result.nodeId, index, isSelected, isRepeatingKey);
                                            } else if (result.isApp) {
                                              resultWidget = _buildAppResult(context, theme, result.appResult!,
                                                  result.nodeId, index, isSelected, isRepeatingKey);
                                            } else if (result.isWindow) {
                                              resultWidget = _buildWindowResult(
                                                  context, theme, result.window!, index, isSelected, isRepeatingKey);
                                            } else if (result.isBrowserTab) {
                                              resultWidget = _buildBrowserTabResult(context, theme, result.browserTab!,
                                                  index, isSelected, isRepeatingKey);
                                            } else if (result.isBookmark) {
                                              resultWidget = _buildBookmarkResult(context, theme,
                                                  result.bookmarkResult!, index, isSelected, isRepeatingKey);
                                            } else if (result.isNotion) {
                                              resultWidget = _buildNotionResult(context, theme, result.notionResult!,
                                                  index, isSelected, isRepeatingKey);
                                            } else if (result.isObsidian) {
                                              resultWidget = _buildObsidianResult(context, theme,
                                                  result.obsidianResult!, index, isSelected, isRepeatingKey);
                                            } else if (result.isSteam) {
                                              resultWidget = _buildSteamResult(context, theme, result.steamResult!,
                                                  index, isSelected, isRepeatingKey);
                                            } else if (result.isInfo) {
                                              resultWidget = _buildInfoResult(context, theme, result.infoResult!, index,
                                                  isSelected, isRepeatingKey);
                                            } else {
                                              resultWidget = _buildQuickActionResult(context, theme,
                                                  result.quickAction!, index, isSelected, isRepeatingKey);
                                            }
                                            final Widget resultWithDivider = result.shortcut?.showDividerBefore == true
                                                ? Column(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: <Widget>[
                                                      // if (_design == LauncherDesign.newCast)
                                                      Padding(
                                                        key: _pluginsSectionHeaderKey,
                                                        padding: EdgeInsets.zero,
                                                        child: _design.buildSectionHeader(
                                                          label: 'Plugins',
                                                          accent: accent,
                                                        ),
                                                      ),
                                                      Divider(
                                                        height: 17,
                                                        thickness: 1,
                                                        indent: 12,
                                                        endIndent: 12,
                                                        color: theme.colorScheme.outlineVariant.withAlpha(150),
                                                      ),
                                                      resultWidget,
                                                    ],
                                                  )
                                                : resultWidget;
                                            return KeyedSubtree(
                                              key: _resultKeys[_resultKeyId(result, index)],
                                              child: LauncherRaycastResultIndex(
                                                index: index,
                                                child: MouseRegion(
                                                  onHover: (PointerHoverEvent event) =>
                                                      _selectResultFromPointerHover(event, index),
                                                  child: Stack(
                                                    alignment: Alignment.centerRight,
                                                    children: <Widget>[resultWithDivider],
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                    if (showPreview)
                                      Positioned(
                                        top: 0,
                                        right: 0,
                                        bottom: 0,
                                        width: previewWidth,
                                        child: previewEntity != null
                                            ? _LauncherFilePreviewPanel(
                                                key: ValueKey<String>(previewEntity.path),
                                                entity: previewEntity,
                                                design: _design,
                                                accent: accent,
                                                onSurface: onSurface,
                                              )
                                            : ValueListenableBuilder<int>(
                                                valueListenable: _windowPreviewCacheVersion,
                                                builder: (BuildContext context, int version, Widget? child) {
                                                  final PlatformWindow window = previewWindow!;
                                                  return _LauncherWindowPreviewPanel(
                                                    key: ValueKey<String>(window.identity),
                                                    window: window,
                                                    preview: _windowPreviewCache[window.identity],
                                                    onPreviewNeeded: () => _captureWindowPreview(window),
                                                    design: _design,
                                                    accent: accent,
                                                    onSurface: onSurface,
                                                  );
                                                },
                                              ),
                                      ),
                                    if (showPreview)
                                      Positioned(
                                        top: 0,
                                        right: previewWidth,
                                        bottom: 0,
                                        width: _previewResizeHandleWidth,
                                        child: MouseRegion(
                                          cursor: SystemMouseCursors.resizeLeftRight,
                                          child: GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onHorizontalDragUpdate: (DragUpdateDetails details) {
                                              final double resizedWidth = (previewWidth - details.delta.dx)
                                                  .clamp(minPreviewWidth, maxPreviewWidth)
                                                  .toDouble();
                                              setState(() => _previewWidthPercent = resizedWidth / appWidth * 100);
                                            },
                                            onHorizontalDragEnd: (_) => _persistPreviewWidthPercent(),
                                            onHorizontalDragCancel: _persistPreviewWidthPercent,
                                            child: Center(
                                              child: Container(
                                                width: 1,
                                                color: accent.withAlpha(45),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            );
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
    final Widget layoutContent = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[searchContent, resultsContent],
    );
    final Widget innerContent = Stack(
      children: <Widget>[
        layoutContent,
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _buildHeightResizeHandle(accent, onSurface),
        ),
      ],
    );

    // ── Outer frame: chosen once, wraps the shared content ──────────────────
    // Each frame widget also injects a LauncherTheme so descendants can
    // read the active design without a parameter chain.
    final Color surface = theme.colorScheme.surface;
    final int resultCount = _results.length;
    final LauncherFrameBuilder frameBuilder = switch (_design) {
      LauncherDesign.serene => SereneLauncherFrame.new,
      LauncherDesign.classic => ClassicLauncherFrame.new,
      LauncherDesign.command => CommandLauncherFrame.new,
      LauncherDesign.terminal => TerminalLauncherFrame.new,
      LauncherDesign.zen => ZenLauncherFrame.new,
      LauncherDesign.glass => GlassLauncherFrame.new,
      LauncherDesign.blueprint => BlueprintLauncherFrame.new,
      LauncherDesign.transit => TransitLauncherFrame.new,
      LauncherDesign.fluent => FluentLauncherFrame.new,
      LauncherDesign.manifesto => ManifestoLauncherFrame.new,
      LauncherDesign.orbit => OrbitLauncherFrame.new,
      LauncherDesign.anime => AnimeLauncherFrame.new,
      LauncherDesign.tech => TechLauncherFrame.new,
      LauncherDesign.vector => VectorLauncherFrame.new,
      LauncherDesign.outrun => Outrun2LauncherFrame.new,
      LauncherDesign.matrix => ({
          required Color surface,
          required Color accent,
          required Color onSurface,
          required int resultCount,
          required Widget child,
        }) =>
            MatrixLauncherFrame(
                surface: surface,
                accent: accent,
                onSurface: onSurface,
                resultCount: resultCount,
                searchChild: searchContent,
                resultsChild: Stack(
                  children: <Widget>[
                    resultsContent,
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _buildHeightResizeHandle(accent, onSurface),
                    ),
                  ],
                )),
      LauncherDesign.steam => SteamLauncherFrame.new,
      LauncherDesign.cyber => CyberLauncherFrame.new,
      LauncherDesign.manga => MangaLauncherFrame.new,
      LauncherDesign.windowsXp => WindowsXpLauncherFrame.new,
      LauncherDesign.windows98 => Windows98LauncherFrame.new,
      LauncherDesign.notion => NotionLauncherFrame.new,
      LauncherDesign.switchboard => SwitchboardLauncherFrame.new,
      LauncherDesign.relay => RelayLauncherFrame.new,
      LauncherDesign.newCast => RaycastLauncherFrame.new,
      LauncherDesign.terminal2 => Terminal2LauncherFrame.new,
    };

    final Widget frame = frameBuilder(
      surface: surface,
      accent: accent,
      onSurface: onSurface,
      resultCount: resultCount,
      child: innerContent,
    );

    final bool usesDesignFont = isTerminal ||
        isTerminal2 ||
        isZen ||
        isGlass ||
        isBlueprint ||
        isTransit ||
        isFluent ||
        isManifesto ||
        isOrbit ||
        isAnime ||
        isWindowsXp ||
        isWindows98 ||
        isNotion ||
        isSwitchboard ||
        isRelay ||
        isRaycast;
    final ThemeData launcherThemeData = !Design.useCustomFont || usesDesignFont
        ? theme
        : theme.copyWith(
            textTheme: GoogleFonts.getTextTheme(Design.entryFontFamily, theme.textTheme),
          );

    final Widget appearanceFrame = _buildLauncherAppearanceFrame(frame);

    return Theme(
      data: launcherThemeData,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTap: _openActionsForActiveResult,
        child: appearanceFrame,
      ),
    );
  }

  Widget _buildLauncherAppearanceFrame(Widget frame) {
    final List<double> points = Design.panelOpacityPoints;
    final List<(double, double)> opacityStops = <(double, double)>[];
    for (int index = 0; index + 1 < points.length; index += 2) {
      opacityStops.add((
        points[index].clamp(0.0, 1.0).toDouble(),
        points[index + 1].clamp(0.0, 1.0).toDouble(),
      ));
    }
    if (opacityStops.length < 2) {
      opacityStops
        ..clear()
        ..addAll(<(double, double)>[(0.0, 1.0), (1.0, 1.0)]);
    }
    opacityStops.sort(((double, double) left, (double, double) right) => left.$1.compareTo(right.$1));
    if (opacityStops.every(((double, double) point) => point.$2 >= 0.999)) {
      return frame;
    }

    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (Rect bounds) => LinearGradient(
        begin: panelAlignmentMap[Design.panelOpacityBegin] ?? Alignment.topCenter,
        end: panelAlignmentMap[Design.panelOpacityEnd] ?? Alignment.bottomCenter,
        colors: opacityStops
            .map(((double, double) point) => Colors.white.withValues(alpha: point.$2))
            .toList(growable: false),
        stops: opacityStops.map(((double, double) point) => point.$1).toList(growable: false),
      ).createShader(bounds),
      child: frame,
    );
  }

  void _persistPreviewWidthPercent() {
    final double? percent = _previewWidthPercent;
    if (percent == null) return;
    unawaited(Boxes.updateSettings(_previewWidthPercentPreferenceKey, percent));
  }

  Widget _buildHeightResizeHandle(Color accent, Color onSurface) {
    final bool isVisible = _isResizeHandleHovered || _isResizingResults;
    final bool disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown,
      onEnter: (_) {
        if (!_isResizeHandleHovered) setState(() => _isResizeHandleHovered = true);
      },
      onExit: (_) {
        if (_isResizeHandleHovered) setState(() => _isResizeHandleHovered = false);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: (_) {
          if (!_isResizingResults) setState(() => _isResizingResults = true);
        },
        onVerticalDragEnd: (_) {
          if (_isResizingResults) setState(() => _isResizingResults = false);
          unawaited(Boxes.updateSettings('launcherResultsHeight', _resultsMaxHeight));
        },
        onVerticalDragCancel: () {
          if (_isResizingResults) setState(() => _isResizingResults = false);
          unawaited(Boxes.updateSettings('launcherResultsHeight', _resultsMaxHeight));
        },
        onVerticalDragUpdate: (DragUpdateDetails details) {
          // final Size size = await windowManager.getSize();
          final ({int height, int width}) size = Win32.getSize();
          final double nextHeight =
              (_resultsMaxHeight + details.delta.dy).clamp(_minResultsHeight, size.height - 150).toDouble();

          if (nextHeight == _resultsMaxHeight) return;

          setState(() => _resultsMaxHeight = nextHeight);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final RenderObject? renderObject = context.findRenderObject();
            if (renderObject is RenderBox) Globals.launcherCurrentSize = renderObject.size;
          });
        },
        child: SizedBox(
          height: 16,
          child: Center(
            child: AnimatedOpacity(
              opacity: isVisible ? 1 : 0,
              duration: disableAnimations ? Duration.zero : Duration(milliseconds: isVisible ? 140 : 90),
              curve: Curves.easeOutQuart,
              child: Container(
                width: 64,
                height: 3,
                decoration: BoxDecoration(
                  color: Color.alphaBlend(accent.withAlpha(80), onSurface.withAlpha(35)),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Returns the badge shown in the search bar trailing area.
  /// Priority: info badge (transient) > copied files bubble (persistent).
  Widget _buildResultsHeaderWithBadges(Color accent, Color onSurface) {
    _scheduleResultsSectionHeaderUpdate();
    final bool hasPluginsSection = _results.any(
      (LauncherSearchResultItem result) => result.shortcut?.showDividerBefore == true,
    );
    return Row(
      children: <Widget>[
        Expanded(
          child: _design.buildSectionHeader(
            label: hasPluginsSection && _isPluginsSectionActive ? 'Plugins' : 'Results',
            accent: accent,
          ),
        ),
        _LauncherStatusBadges(
          accent: accent,
          onSurface: onSurface,
          onOpenTimers: () => _openLauncherPanel(context, const TimersWidget()),
          onOpenReminders: () => _openLauncherPanel(context, const RemindersPanel()),
        ),
      ],
    );
  }

  void _scheduleResultsSectionHeaderUpdate() {
    if (_resultsSectionHeaderUpdateScheduled) return;
    _resultsSectionHeaderUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resultsSectionHeaderUpdateScheduled = false;
      _updateResultsSectionHeader();
    });
  }

  void _updateResultsSectionHeader() {
    if (!mounted) return;

    final bool hasPluginsSection = _results.any(
      (LauncherSearchResultItem result) => result.shortcut?.showDividerBefore == true,
    );
    if (!hasPluginsSection) {
      _pluginsSectionResultsIdentity = _results;
      _pluginsSectionStartOffset = null;
      if (_isPluginsSectionActive) setState(() => _isPluginsSectionActive = false);
      return;
    }

    if (!identical(_pluginsSectionResultsIdentity, _results)) {
      _pluginsSectionResultsIdentity = _results;
      _pluginsSectionStartOffset = null;
      if (_isPluginsSectionActive) {
        setState(() => _isPluginsSectionActive = false);
        return;
      }
    }

    final RenderObject? headerObject = _pluginsSectionHeaderKey.currentContext?.findRenderObject();
    final RenderObject? viewportObject = _resultsViewportKey.currentContext?.findRenderObject();
    if (headerObject is RenderBox &&
        viewportObject is RenderBox &&
        headerObject.hasSize &&
        viewportObject.hasSize &&
        _scrollController.hasClients) {
      final double headerTop = headerObject.localToGlobal(Offset.zero).dy;
      final double viewportTop = viewportObject.localToGlobal(Offset.zero).dy;
      _pluginsSectionStartOffset = _scrollController.offset + headerTop - viewportTop;
    }

    final double? sectionStartOffset = _pluginsSectionStartOffset;
    if (sectionStartOffset == null || !_scrollController.hasClients) return;

    // The section becomes active when its heading reaches the top of the
    // scrolling viewport, which is the point at which the fixed heading is
    // representing the Plugins section rather than the preceding results.
    final bool isPluginsSectionActive = _scrollController.offset >= sectionStartOffset - 0.5;
    if (isPluginsSectionActive == _isPluginsSectionActive) return;
    setState(() => _isPluginsSectionActive = isPluginsSectionActive);
  }

  Widget? _buildTrailingBadge(Color accent, Color onSurface) {
    if (_infoText != null) return _buildInfoBadge(accent, onSurface);
    if (_copiedFiles.isNotEmpty) return _buildCopiedFilesBubble(accent, onSurface);
    return null;
  }

  Widget _buildCopiedFilesBubble(Color accent, Color onSurface) {
    return GestureDetector(
      onTap: _clearCopiedFiles,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: accent.withAlpha(35),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: accent.withAlpha(70)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.file_copy_rounded,
              size: 14,
              color: accent,
            ),
            const SizedBox(width: 5),
            Text(
              '${_copiedFiles.length}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.close_rounded,
              size: 12,
              color: onSurface.withAlpha(160),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoBadge(Color accent, Color onSurface) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withAlpha(35),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accent.withAlpha(70)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            _infoIcon ?? Icons.check_circle_outline_rounded,
            size: 14,
            color: accent,
          ),
          const SizedBox(width: 6),
          Text(
            _infoText!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
          ),
        ],
      ),
    );
  }
}
