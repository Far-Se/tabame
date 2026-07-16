import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sqlite3/sqlite3.dart' hide Row;
import 'package:tabamewin32/tabamewin32.dart' show BrowserTab, BrowserTabs, MediaSession;
import 'package:window_manager/window_manager.dart';
import '../models/tray_watcher.dart';
import '../models/util/quickmenu_modal.dart';
import 'launcher_actions_panel.dart';

import '../models/classes/boxes.dart';
import '../models/classes/saved_maps.dart';
import '../models/converter.dart';
import '../models/db/file_index_db.dart';
import '../models/globals.dart';
import '../models/google_translator.dart';
import '../models/settings.dart';
import '../models/util/spotify_controller.dart';
import '../models/util/system_power.dart';
import '../models/win32/keys.dart';
import '../models/win32/win32.dart';
import '../models/win32/win_utils.dart';
import '../models/win32/window.dart';
import '../models/window_watcher.dart';
import '../services/file_indexer.dart';
import '../widgets/itzy/quickmenu/button_currency_converter.dart';
import '../widgets/itzy/quickmenu/button_notion.dart';
import '../widgets/itzy/quickmenu/button_obsidian.dart';
import '../widgets/itzy/quickmenu/button_quickactions.dart';
import '../widgets/itzy/quickmenu/button_steam.dart';
import '../widgets/itzy/quickmenu/button_timers.dart';
import '../widgets/itzy/quickmenu/button_workspaces.dart';
import '../widgets/itzy/quickmenu/button_persistent_reminders.dart';
import 'launcher/result/result_item_app.dart';
import 'launcher/result/result_item_bookmark.dart';
import 'launcher/result/result_item_browser_tab.dart';
import 'launcher/result/result_item_file.dart';
import 'launcher/result/result_item_window.dart';
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

// Constants
// ---------------------------------------------------------------------------

class _ParsedLauncherTimer {
  const _ParsedLauncherTimer({
    required this.minutes,
    required this.message,
  });

  final int minutes;
  final String message;
}

class _MediaCommandAction {
  const _MediaCommandAction({
    required this.id,
    required this.label,
    required this.icon,
    required this.vk,
    required this.aliases,
  });

  final String id;
  final String label;
  final IconData icon;
  final String vk;
  final List<String> aliases;

  bool matches(String query) => aliases.any((String alias) => alias.startsWith(query));
}

class _LauncherFunctionCommand {
  const _LauncherFunctionCommand({
    required this.name,
    required this.description,
    required this.usage,
    required this.icon,
    this.handler,
    this.streamingHandler,
    this.aliases = const <String>[],
    this.debounce = Duration.zero,
  }) : assert(handler != null || streamingHandler != null, 'A command needs a handler or streamingHandler');

  final String name;
  final String description;
  final String usage;
  final IconData icon;
  final List<String> aliases;
  final Duration debounce;

  /// Standard one-shot handler: computes every result, then returns them all at
  /// once. The framework awaits it and calls `setResults` a single time.
  final FutureOr<List<LauncherSearchResultItem>> Function(String input)? handler;

  /// Streaming handler: takes ownership of the search context and pushes
  /// results incrementally via `context.setResults` as they become available
  /// (e.g. one row per network translation). Preferred over [handler] when set.
  final Future<void> Function(String input, LauncherSearchContext context)? streamingHandler;

  bool matchesName(String value) => value == name || aliases.contains(value);

  bool matchesQuery(String query) {
    final String lower = query.toLowerCase();
    return name.contains(lower) ||
        description.toLowerCase().contains(lower) ||
        usage.toLowerCase().contains(lower) ||
        aliases.any((String alias) => alias.contains(lower));
  }
}

class _ParsedTranslateCommand {
  const _ParsedTranslateCommand({
    required this.text,
    required this.from,
    required this.targets,
  });

  final String text;
  final String from;
  final List<String> targets;
}

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

class LauncherState extends State<Launcher> with QuickMenuTriggers {
  static const double _minResultsHeight = 300;
  static const double _maxResultsHeight = 405;

  final LauncherSearchToken _searchToken = LauncherSearchToken();

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
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

  final List<String> _folderBrowsingStack = <String>[];

  List<LauncherSearchResultItem> _results = <LauncherSearchResultItem>[];
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
  Timer? _pluginQueryDebounce;

  /// Set when Enter is pressed while a query is still waiting out its debounce:
  /// the visible frame predates what the user typed, so the submit is deferred
  /// until the fresh frame answering the flushed query arrives (see
  /// [_submitPluginItem] / [_onPluginFrame]).
  bool _pluginSubmitPending = false;
  bool _pluginWindowWidened = false;
  Timer? _pluginWidthCollapseTimer;
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
      label: ';',
      caption: 'Desktop Files',
      prefix: ';',
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
    const LauncherSearchResultItem.info(LauncherInfoResult(
      id: 'ctrlKInfo',
      title: 'Ctrl+K',
      subtitle: 'Opens Actions Menu for a specific result',
      icon: Icons.menu_rounded,
    )),
    const LauncherSearchResultItem.info(LauncherInfoResult(
      id: 'ctrlCInfo',
      title: 'Ctrl+C',
      subtitle: 'Copy file/folder. Only for File Search',
      icon: Icons.menu_rounded,
    )),
  ];
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
      if (_copiedFiles.length == 1) {
        final bool isDir = item.entity is Directory;
        isDir ? ClipboardExtension.copyFolder(path) : ClipboardExtension.copyFile(path);
      } else {
        ClipboardExtension.copyMultipleFiles(List<String>.unmodifiable(_copiedFiles));
      }

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

  // ── Plugin runtime ─────────────────────────────────────────────────────────

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
    _pluginToastTimer?.cancel();
    _pluginToastTimer = null;
    if (_activePlugin == null && _pluginFrame == null) return;
    _activePlugin = null;
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
    final bool wasForm = previous?.view == PluginViewType.form;
    // Streaming `detail.append` frames carry only the new chunk — resolve them
    // against the markdown currently on screen before rendering.
    if (frame.detailAppend != null) {
      frame = frame.resolveAppend(previous?.view == PluginViewType.detail ? previous?.detailMarkdown : null);
    }
    // A different item set means a new screen (drill-in) or a fresh search:
    // snap the selection back to the first row so it matches what's shown and
    // arrow keys start from there. Same-id re-renders (e.g. a background badge
    // refresh) keep the cursor where the user left it. A frame carrying
    // `selectId` picks its own highlight instead.
    final bool sameItemSet = previous != null && _sameItemIds(previous.items, frame.items);
    setState(() {
      _pluginFrame = frame;
      _isSearching = frame.loading;
      final int count = frame.items.length;
      final int selectIdIndex =
          frame.selectId == null ? -1 : frame.items.indexWhere((PluginItem item) => item.id == frame.selectId);
      if (selectIdIndex >= 0) {
        _activeIndexNotifier.value = selectIdIndex;
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
        _pluginHost.sendAction(frame.items.first.id, 'default');
      }
    }
    // Leaving a form view: the form's field held focus, hand it back to the
    // search box so typing works again.
    if (wasForm && frame.view != PluginViewType.form) _requestLauncherFocus();
    _applyPluginWindowWidth(frame.wantsWideWindow);
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

  /// Form view submit: forwards the field values to the plugin.
  void _onPluginFormSubmit(Map<String, Object?> values, {String? button}) {
    _pluginHost.sendFormSubmit(values, button: button);
  }

  /// Form view: a `watch: true` field changed (dependent dropdowns).
  void _onPluginFormChange(String fieldId, Map<String, Object?> values) {
    _pluginHost.sendFormChange(fieldId, values);
  }

  /// Form view Escape: back when the frame declared canGoBack, otherwise exit.
  void _onPluginFormCancel() {
    if (_pluginFrame?.canGoBack == true) {
      _pluginHost.sendBack();
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
    final String next = text.isEmpty ? '${plugin.keyword} ' : '${plugin.keyword} $text';
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
      WindowManager.instance.setSize(Size(_pluginPreviewWidth, Globals.launcherSize.height)).then((_) async {
        WinUtils.fixDrawBug();
        Win32.setCenter(useMouse: true);
        if (mounted) setState(() {});
      });
      return;
    }

    // Narrow frame: debounce the collapse. Each keystroke makes the plugin emit
    // an intermediate loading frame (no preview) before the results frame (with
    // preview); collapsing immediately would resize to default and back on every
    // letter, causing jitter. Only shrink once the plugin has stayed narrow.
    if (!_pluginWindowWidened) return;
    _pluginWidthCollapseTimer?.cancel();
    _pluginWidthCollapseTimer = Timer(const Duration(milliseconds: 400), () {
      _pluginWidthCollapseTimer = null;
      if (mounted) _restorePluginWindowWidth();
    });
  }

  void _restorePluginWindowWidth() {
    _pluginWidthCollapseTimer?.cancel();
    _pluginWidthCollapseTimer = null;
    if (!_pluginWindowWidened) return;
    _pluginWindowWidened = false;
    WindowManager.instance.setSize(Size(Boxes.launcherSizeWidth, Globals.launcherSize.height)).then((_) async {
      WinUtils.fixDrawBug();
      Win32.setCenter(useMouse: true);
      if (mounted) setState(() {});
    });
  }

  /// Moves the plugin selection and notifies the script (drives the preview).
  void _setPluginSelection(int index) {
    final PluginRenderFrame? frame = _pluginFrame;
    if (frame == null || index < 0 || index >= frame.items.length) return;
    _activeIndexNotifier.value = index;
    _pluginHost.sendSelect(frame.items[index].id);
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
        _pluginHost.sendSubmitQuery(text);
        return;
      }
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
    final PluginItem item = frame.items[idx];
    // Enter fires "default"; when the item *lists* a default action with a
    // confirm/destructive gate, honor it.
    PluginAction? declared;
    for (final PluginAction action in item.actions) {
      if (action.id == 'default') declared = action;
    }
    _firePluginAction(item.id, declared ?? const PluginAction(id: 'default', title: ''));
  }

  /// Central action dispatch: shows the action's confirm gate (if any), then
  /// forwards it to the plugin. [itemId] is empty for frame-level actions.
  void _firePluginAction(String itemId, PluginAction action) {
    if (action.confirm == null) {
      _pluginHost.sendAction(itemId, action.id);
      return;
    }
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      builder: (_) => PluginConfirmPanel(action: action),
    ).then((bool? confirmed) {
      if (confirmed == true && _activePlugin != null) _pluginHost.sendAction(itemId, action.id);
    });
  }

  void _openPluginActions() {
    final PluginRenderFrame? frame = _pluginFrame;
    if (frame == null) return;
    PluginItem? item;
    if (frame.items.isNotEmpty && frame.view != PluginViewType.detail && frame.view != PluginViewType.form) {
      item = frame.items[_activeIndexNotifier.value.clamp(0, frame.items.length - 1)];
    }
    if ((item?.actions.isEmpty ?? true) && frame.frameActions.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      builder: (_) => PluginActionsPanel(
        item: item,
        frameActions: frame.frameActions,
        onSelected: (PluginAction action, {required bool isFrameAction}) =>
            _firePluginAction(isFrameAction ? '' : (item?.id ?? ''), action),
      ),
    );
  }

  /// Matches a key press against the shortcuts declared by the highlighted
  /// item's actions and the frame's actions; fires the first hit.
  bool _handlePluginShortcut(KeyEvent event) {
    final PluginRenderFrame? frame = _pluginFrame;
    if (frame == null) return false;
    PluginItem? item;
    if (frame.items.isNotEmpty) {
      item = frame.items[_activeIndexNotifier.value.clamp(0, frame.items.length - 1)];
    }
    for (final PluginAction action in item?.actions ?? const <PluginAction>[]) {
      final PluginShortcut? shortcut = PluginShortcut.parse(action.shortcut);
      if (shortcut != null && shortcut.matches(event)) {
        _firePluginAction(item!.id, action);
        return true;
      }
    }
    for (final PluginAction action in frame.frameActions) {
      final PluginShortcut? shortcut = PluginShortcut.parse(action.shortcut);
      if (shortcut != null && shortcut.matches(event)) {
        _firePluginAction('', action);
        return true;
      }
    }
    return false;
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
        if (frame.canGoBack) {
          _pluginHost.sendBack();
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
        _pluginHost.sendTab(id);
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (event is KeyDownEvent) _submitPluginItem();
      return KeyEventResult.handled;
    }

    // Detail (markdown document) view: arrows and page keys scroll the
    // document. Home/End are left alone — they move the caret in the search
    // field.
    if (frame.view == PluginViewType.detail) {
      return _scrollPluginDetail(event.logicalKey, isRepeat: event is KeyRepeatEvent);
    }

    final int count = frame.items.length;
    if (count == 0) return KeyEventResult.ignored;

    final bool isGrid = frame.view == PluginViewType.grid;
    final int cols = isGrid ? frame.gridColumns : 1;
    int index = _activeIndexNotifier.value.clamp(0, count - 1);
    final LogicalKeyboardKey key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowDown) {
      index = isGrid ? (index + cols).clamp(0, count - 1) : (index + 1) % count;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      index = isGrid ? (index - cols < 0 ? index : index - cols) : (index - 1 + count) % count;
    } else if (isGrid && key == LogicalKeyboardKey.arrowRight) {
      index = (index + 1).clamp(0, count - 1);
    } else if (isGrid && key == LogicalKeyboardKey.arrowLeft) {
      index = (index - 1).clamp(0, count - 1);
    } else {
      return KeyEventResult.ignored;
    }

    _setPluginSelection(index);
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
                onTapItem: (int i) {
                  _setPluginSelection(i);
                  _submitPluginItem();
                },
                onHoverItem: _setPluginSelection,
                onFormSubmit: _onPluginFormSubmit,
                onFormCancel: _onPluginFormCancel,
                onFormChange: _onPluginFormChange,
                onLoadMore: _pluginHost.sendLoadMore,
                onEmptyAction: (PluginAction action) => _firePluginAction('', action),
                onOpenActions: _openPluginActions,
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
    if (PluginRegistry.manifests.isEmpty) return _launcherShortcuts;
    return <LauncherSearchResultItem>[
      ..._launcherShortcuts,
      for (final PluginManifest m in PluginRegistry.manifests)
        if (m.enabled)
          LauncherSearchResultItem.shortcut(LauncherShortcut(
            label: m.keyword,
            caption: m.name,
            prefix: '${m.keyword} ',
            icon: Icons.extension_rounded,
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

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      // A running plugin owns navigation/selection/actions.
      if (_activePlugin != null) {
        final KeyEventResult pluginResult = _handlePluginKey(event);
        if (pluginResult != KeyEventResult.ignored) return pluginResult;
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
      // Escape: go back to quickmenu
      if (event.logicalKey == LogicalKeyboardKey.escape) {
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

      if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
          event.logicalKey == LogicalKeyboardKey.arrowUp ||
          event.logicalKey == LogicalKeyboardKey.home ||
          event.logicalKey == LogicalKeyboardKey.end) {
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

  @override
  void initState() {
    super.initState();
    QuickMenuFunctions.addListener(this);
    _design = user.launcherDesign;
    _resultsMaxHeight = (Boxes.pref.getDouble('launcherResultsHeight') ?? _maxResultsHeight)
        .clamp(_minResultsHeight, _maxResultsHeight);
    // Rescan the plugins folder so freshly-dropped plugins are available without
    // an app restart. If a keyword becomes matchable after the scan, re-run the
    // current query so it activates.
    unawaited(PluginRegistry.load().then((_) {
      if (!mounted || _activePlugin != null) return;
      if (PluginRegistry.matchKeyword(_controller.text) != null) _onSearchChanged(_controller.text);
    }));
    _controller.text = user.launcherSearchText;
    // _controller.selection = TextSelection.fromPosition(TextPosition(offset: _controller.text.length));
    _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
    Globals.quickMenuSearchInputVersion.addListener(_consumePendingQuickMenuSearchInput);
    FocusManager.instance.addListener(_onFocusManagerChanged);
    _focusNode.onKeyEvent = _onKeyEvent;

    _focusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Win32.setWindowInvisible(false);
      _canConsumePendingInput = true;
      _startWindowRefreshLoop();
      _consumePendingQuickMenuSearchInput();
      _focusNode.requestFocus();

      unawaited(_refreshLauncherCatalogs());

      _onSearchChanged(_controller.text);
      Future<void>.delayed(const Duration(milliseconds: 5),
          () => _controller.selection = TextSelection.collapsed(offset: _controller.text.length)); // <- This
      // setState(() {});
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
        _resetSelection();
      }
    });
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
    _restorePluginWindowWidth();
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
    _focusNode.dispose();
    _scrollController.dispose();
    _activeIndexNotifier.dispose();
    super.dispose();
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

  @override
  void onQuickActionExecute(String actionName) {
    if (actionName == "page:quickMenu") {
      Globals.quickMenuPage = QuickMenuPage.quickMenu;
      if (mounted) setState(() {});
    }
  }

  @override
  void requestQuickMenuFocus() => _requestLauncherFocus(focusWindow: true);

  bool get _canFocusLauncher {
    if (!mounted) return false;
    if (!QuickMenuFunctions.isQuickMenuVisible) return false;
    if (Globals.quickMenuPage != QuickMenuPage.launcher) return false;
    if (Navigator.of(context).canPop()) return false;
    // A plugin form owns focus while it is shown — the search field must not
    // steal keystrokes back from its inputs.
    if (_activePlugin != null && _pluginFrame?.view == PluginViewType.form) return false;
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
    if (!_focusNode.hasPrimaryFocus) {
      _resetSelection();
    }
  }

  void _requestLauncherFocus({bool focusWindow = false}) {
    requestFocusIfNeeded(focusWindow);
    WidgetsBinding.instance.addPostFrameCallback((_) => requestFocusIfNeeded(focusWindow));
    _launcherFocusRetryTimer?.cancel();
    _launcherFocusRetryTimer = Timer(const Duration(milliseconds: 5), () => requestFocusIfNeeded(focusWindow));
  }

  void _onFocusManagerChanged() {
    if (!_canFocusLauncher || _focusNode.hasPrimaryFocus) return;
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
      _activeIndexNotifier.value = ((_activeIndexNotifier.value + 1) % _results.length).toInt();
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _activeIndexNotifier.value = ((_activeIndexNotifier.value - 1 + _results.length) % _results.length).toInt();
    } else if (key == LogicalKeyboardKey.home) {
      _activeIndexNotifier.value = 0;
    } else if (key == LogicalKeyboardKey.end) {
      _activeIndexNotifier.value = _results.length - 1;
    }
    _scrollToActiveIndex();
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

  Timer? _searchDebounce;
  Timer? _windowRefreshTimer;
  String _lastScrollResetQuery = '';
  DateTime? _lastFolderSyncTime;
  bool _isFolderSyncing = false;
  // Remove this field entirely:
  // And _startWindowRefreshLoop becomes simply:
  void _startWindowRefreshLoop() {
    _windowRefreshTimer?.cancel();
    _windowRefreshTimer = Timer.periodic(const Duration(milliseconds: 900), (Timer timer) async {
      if (!mounted || Globals.quickMenuPage != QuickMenuPage.launcher) return;

      final bool updated = await WindowWatcher.fetchWindows();
      if (WindowWatcher.list.any((Window e) => e.process.exe.toLowerCase() == "taskmgr.exe")) {
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
    final Map<int, Window> latestWindows = <int, Window>{
      for (final Window window in WindowWatcher.list) window.hWnd: window,
    };

    final List<LauncherSearchResultItem> nextResults = <LauncherSearchResultItem>[];

    for (final LauncherSearchResultItem result in _results) {
      final Window? currentWindow = result.window;

      // Not a window item — keep as-is
      if (currentWindow == null) {
        nextResults.add(result);
        continue;
      }

      final Window? latestWindow = latestWindows[currentWindow.hWnd];

      // Window no longer exists — drop it
      if (latestWindow == null) {
        changed = true;
        continue;
      }

      // Window exists but something changed — update it
      if (latestWindow.title != currentWindow.title ||
          latestWindow.process.exe != currentWindow.process.exe ||
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
    if (pending.isEmpty) {
      // A quick action may have been queued without (or after losing) its
      // accompanying search text. Re-run the current search anyway so the
      // pending action still gets its chance to execute once results render.
      if (hasPendingAction) _onSearchChanged(_controller.text);
      return;
    }

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

  // ---------------------------------------------------------------------------
  // Search logic
  // ---------------------------------------------------------------------------

  int _searchGeneration = 0;

  /// The query text that produced the currently displayed [_results].
  /// Selection is only carried over between result sets of the same query —
  /// results for a different query always start at the first row.
  String? _resultsQuery;

  void _onSearchChanged(String query) {
    user.launcherSearchText = query;

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

  /// Matches the bare-word currency shorthand `100 usd to eur`, which is treated
  /// exactly like `$cur 100 usd to eur`. Requires an amount, a 3-letter source
  /// currency, a `to`/`in`/`into` connector, and a 3-letter target currency so it
  /// doesn't hijack ordinary searches.
  static final RegExp _currencyShorthandPattern = RegExp(
    r'^\d+(?:[.,]\d+)?\s+[a-z]{3}\s+(?:to|in|into)\s+[a-z]{3}$',
    caseSensitive: false,
  );

  bool _isCurrencyShorthand(String query) => _currencyShorthandPattern.hasMatch(query.trim());

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

  /// A bare arithmetic expression made up only of digits, whitespace and the
  /// arithmetic characters `. ( ) + - * / ^ %`.
  static final RegExp _mathShorthandPattern = RegExp(r'^[\d\s.()+\-*/^%]+$');

  /// At least one binary operator, so plain numbers (`100`, `3.14`) stay ordinary
  /// searches and only genuine expressions (`12*3`, `(2+3)/5`) are calculated.
  static final RegExp _mathOperatorPattern = RegExp(r'[+\-*/^%]');

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

  /// Matches a math expression followed by a currency conversion, e.g.
  /// `30 + (3.79*3) usd to ron`. The expression part is restricted to
  /// arithmetic-safe characters so it doesn't hijack ordinary searches.
  static final RegExp _mathCurrencyShorthandPattern = RegExp(
    r'^([\d\s.()+\-*/^%]+?)\s+([a-z]{3,4})\s+(?:to|in|into)\s+([a-z]{3,4})$',
    caseSensitive: false,
  );

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
    _resetSelection();
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

    context.setResults(<LauncherSearchResultItem>[
      ...bookmarkResults,
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
      final bool hasWindow = WindowWatcher.list.any((Window w) => w.process.exe == ctl.exe) ||
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

  Future<void> _handleSpotifyCommand(LauncherSearchContext context) async {
    context.setSearching(true);

    final MediaSession? session = await SpotifyController.fetchSession();
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

  QuickActionMenuEntry _buildSpotifyNowPlaying(MediaSession session) {
    final ImageProvider? art = session.thumbnailImage;
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

  void _executeSpotifyCommand(MediaSession session, String command) {
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
      _setResults(_launcherShortcuts, isSearching: false);
      _resetSelection();
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
        _resetSelection();
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
          subtitle: '${WinUtils.getTabameAppDataFolder()}\\cache\\icon_cache'.lastChars(35),
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
          subtitle: '${WinUtils.getTabameAppDataFolder()}\\cache\\icon_cache\\file_formats'.lastChars(35),
          icon: Icons.cleaning_services_rounded,
          searchTerms: const <String>['clear', 'cache', 'icon', 'ext'],
          onExecute: () => unawaited(_clearCacheFolder('icon_cache\\file_formats')),
        )),
      ];
    } else if (input.trim().toLowerCase() == 'authlogo') {
      return <LauncherSearchResultItem>[
        LauncherSearchResultItem.quickAction(_buildFunctionAction(
          id: 'function-clear-authlogo-cache',
          title: 'Clear authlogo cache',
          subtitle: '${WinUtils.getTabameAppDataFolder()}\\cache\\authenticator logos'.lastChars(35),
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
          subtitle: '${WinUtils.getTabameAppDataFolder()}\\cache'.lastChars(35),
          icon: Icons.cleaning_services_rounded,
          searchTerms: const <String>['clear', 'cache'],
          onExecute: () => unawaited(_clearCacheFolder("")),
        )),
      ];
    }
    return <LauncherSearchResultItem>[];
  }

  Future<void> _clearCacheFolder(String folder) async {
    final Directory cacheDirectory = Directory('${WinUtils.getTabameAppDataFolder()}\\cache\\$folder');
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
      Boxes.pref.setInt('launcherDesign', design.index);
      user.launcherDesign = design;
      setState(() => _design = design);
      _onSearchChanged(_controller.text);
      // Focus is still present right now, but the debounce (180 ms) + async
      // result rebuild will often steal it.  Re-request after everything settles.
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _focusNode.requestFocus();
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
          subtitle: r'$cur 1 USD to EUR  •  Tip: just type 100 USD to EUR (no $cur needed)',
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

  /// Strips a leading `x = ` variable-assignment prefix (as produced by the
  /// calculator parser for each `|`-separated expression) so only the numeric
  /// result gets copied to the clipboard.
  static final RegExp _mathAssignmentPrefix = RegExp(r'^[a-zA-Z]\w*\s*=\s*');

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
    final bool keepSelection = !resetSelection && _resultsQuery == _controller.text;
    _resultsQuery = _controller.text;

    int nextIndex = 0;
    if (keepSelection && _results.isNotEmpty && _activeIndexNotifier.value < _results.length) {
      final String activeId = _results[_activeIndexNotifier.value].id;
      final int foundIndex = results.indexWhere((LauncherSearchResultItem r) => r.id == activeId);
      if (foundIndex != -1) {
        nextIndex = foundIndex;
      } else {
        nextIndex = _activeIndexNotifier.value.clamp(0, (results.length - 1).clamp(0, 999999)).toInt();
      }
    }

    setState(() {
      _results = results;
      _activeIndexNotifier.value = keepSelection ? nextIndex : 0;
      if (isSearching != null) {
        _isSearching = isSearching;
      }
    });

    if (!keepSelection && _scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }

    _maybeExecutePendingLauncherQuickAction();
    unawaited(_pruneStaleFileResults(results));
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

  // ---------------------------------------------------------------------------
  // Submit / open handlers
  // ---------------------------------------------------------------------------

  void _onShortcutPressed(LauncherShortcut shortcut) {
    _controller.text = shortcut.prefix;
    // _controller.selection = TextSelection.fromPosition(TextPosition(offset: _controller.text.length));
    _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
    _onSearchChanged(_controller.text);
    _resetSelection();
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

    _resetSelection();
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
    setState(() => _folderBrowsingStack.add(folderPath));
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
    setState(() => _folderBrowsingStack.removeLast());
    _onSearchChanged(_controller.text);
    _resetSelection();
  }

  /// Opens [folderPath] in Windows Explorer and hides the launcher.
  void _openFolderInExplorer(String folderPath) {
    WinUtils.open(folderPath);
    QuickMenuFunctions.hideQuickMenu(launcherActivateLastWin: false);
    Globals.quickMenuPage = QuickMenuPage.quickMenu;
    user.launcherSearchText = '';
    _folderBrowsingStack.clear();
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

  Future<void> _openWindow(Window window) async {
    await QuickMenuFunctions.hideQuickMenu(launcherActivateLastWin: false);
    Win32.activateWindow(window.hWnd);
    Globals.lastFocusedWinHWND = window.hWnd;
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

  void _selectResultFromPointerHover(PointerHoverEvent event, int index) {
    if (event.delta == Offset.zero) return;

    final bool pointerMoved = _lastMousePosition == null || (_lastMousePosition! - event.position).distance > 0.5;
    _lastMousePosition = event.position;
    if (!pointerMoved && !_mouseSelectionEnabled) return;

    _mouseSelectionEnabled = true;
    _selectResultFromMouse(index);
  }

  void _selectResultFromMouse(int index) {
    if (!_mouseSelectionEnabled) return;
    if (index < 0 || index >= _results.length) return;
    if (_activeIndexNotifier.value != index) {
      _activeIndexNotifier.value = index;
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

  void handlePostFrameCallback(TextSelection savedSelection) {
    if (savedSelection.isValid) {
      _controller.selection = savedSelection;
    } else {
      // Fallback: collapse to end if previous selection was invalid
      final int len = _controller.text.length;
      _controller.selection = TextSelection.collapsed(offset: len);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  void _resetSelection() {
    // final TextSelection savedSelection = _controller.selection;
    _focusNode.requestFocus();

    Future<void>.delayed(const Duration(milliseconds: 4), () {
      if (mounted) handlePostFrameCallback(TextSelection.collapsed(offset: _controller.text.length));
    });
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) handlePostFrameCallback(TextSelection.collapsed(offset: _controller.text.length));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData baseTheme = Theme.of(context);
    final bool isDark = baseTheme.brightness == Brightness.dark;
    final bool isTerminal = _design == LauncherDesign.terminal;
    final bool isZen = _design == LauncherDesign.zen;
    final bool isGlass = _design == LauncherDesign.glass;
    final bool isBlueprint = _design == LauncherDesign.blueprint;
    final bool isTransit = _design == LauncherDesign.transit;
    final bool isFluent = _design == LauncherDesign.fluent;
    final bool isManifesto = _design == LauncherDesign.manifesto;
    final bool isOrbit = _design == LauncherDesign.orbit;
    // Terminal, Zen, Blueprint, Transit and Fluent force their own palette +
    // text theme. Every result builder reads its colors from this theme, so
    // they all inherit the look without per-builder branching. Terminal,
    // Transit and Fluent keep the user accent (phosphor / line color / Windows
    // accent); Zen replaces it with a calm moss, Blueprint with drafting ink.
    // Glass keeps the theme colors (its glass picks them up) and only forces
    // Inter for the iOS feel.
    final Color accent = isZen
        ? ZenTokens.accent(isDark)
        : isBlueprint
            ? BlueprintTokens.accent(isDark)
            : isManifesto
                ? ManifestoTokens.accent(isDark)
                : Design.accent;
    final ThemeData theme = isTerminal
        ? baseTheme.copyWith(
            colorScheme: baseTheme.colorScheme.copyWith(
              surface: TerminalTokens.bg(isDark),
              onSurface: TerminalTokens.fg(isDark),
            ),
            highlightColor: accent.withAlpha(38),
            textTheme: GoogleFonts.jetBrainsMonoTextTheme(baseTheme.textTheme)
                .apply(bodyColor: TerminalTokens.fg(isDark), displayColor: TerminalTokens.fg(isDark)),
          )
        : isZen
            ? baseTheme.copyWith(
                colorScheme: baseTheme.colorScheme.copyWith(
                  surface: ZenTokens.bg(isDark),
                  onSurface: ZenTokens.fg(isDark),
                ),
                highlightColor: accent.withAlpha(isDark ? 42 : 30),
                textTheme: GoogleFonts.quicksandTextTheme(baseTheme.textTheme)
                    .apply(bodyColor: ZenTokens.fg(isDark), displayColor: ZenTokens.fg(isDark)),
              )
            : isBlueprint
                ? baseTheme.copyWith(
                    colorScheme: baseTheme.colorScheme.copyWith(
                      surface: BlueprintTokens.bg(isDark),
                      onSurface: BlueprintTokens.fg(isDark),
                    ),
                    highlightColor: accent.withAlpha(34),
                    textTheme: GoogleFonts.chakraPetchTextTheme(baseTheme.textTheme)
                        .apply(bodyColor: BlueprintTokens.fg(isDark), displayColor: BlueprintTokens.fg(isDark)),
                  )
                : isTransit
                    ? baseTheme.copyWith(
                        colorScheme: baseTheme.colorScheme.copyWith(
                          surface: TransitTokens.bg(isDark),
                          onSurface: TransitTokens.fg(isDark),
                        ),
                        highlightColor: accent.withAlpha(30),
                        textTheme: GoogleFonts.overpassTextTheme(baseTheme.textTheme)
                            .apply(bodyColor: TransitTokens.fg(isDark), displayColor: TransitTokens.fg(isDark)),
                      )
                    : isFluent
                        ? baseTheme.copyWith(
                            colorScheme: baseTheme.colorScheme.copyWith(
                              surface: FluentTokens.bg(isDark),
                              onSurface: FluentTokens.fg(isDark),
                            ),
                            highlightColor: accent.withAlpha(28),
                            textTheme: baseTheme.textTheme.apply(
                              fontFamily: 'Segoe UI Variable Text',
                              fontFamilyFallback: const <String>['Segoe UI'],
                              bodyColor: FluentTokens.fg(isDark),
                              displayColor: FluentTokens.fg(isDark),
                            ),
                          )
                        : isManifesto
                            ? baseTheme.copyWith(
                                colorScheme: baseTheme.colorScheme.copyWith(
                                  surface: ManifestoTokens.bg(isDark),
                                  onSurface: ManifestoTokens.fg(isDark),
                                ),
                                highlightColor: accent.withAlpha(32),
                                textTheme: baseTheme.textTheme.apply(
                                  fontFamily: 'Segoe UI Variable Text',
                                  fontFamilyFallback: const <String>['Segoe UI'],
                                  bodyColor: ManifestoTokens.fg(isDark),
                                  displayColor: ManifestoTokens.fg(isDark),
                                ),
                              )
                            : isOrbit
                                ? baseTheme.copyWith(
                                    colorScheme: baseTheme.colorScheme.copyWith(
                                      surface: OrbitTokens.bg(isDark),
                                      onSurface: OrbitTokens.fg(isDark),
                                    ),
                                    highlightColor: accent.withAlpha(30),
                                    textTheme: GoogleFonts.spaceGroteskTextTheme(baseTheme.textTheme)
                                        .apply(bodyColor: OrbitTokens.fg(isDark), displayColor: OrbitTokens.fg(isDark)),
                                  )
                                : isGlass
                                    ? baseTheme.copyWith(textTheme: GoogleFonts.interTextTheme(baseTheme.textTheme))
                                    : baseTheme;
    final Color onSurface = theme.colorScheme.onSurface;
    final bool hasInput = _controller.text.trim().isNotEmpty;
    final LauncherThemeData launcherTheme = LauncherThemeData(design: _design);

    // Build the shared inner content once — no per-design duplication.
    final Widget layoutContent = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // ── Search bar ──────────────────────────────────────────────────────
        _design.buildSearchBar(
          surface: theme.colorScheme.surface,
          accent: accent,
          onSurface: onSurface,
          dragHandle: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (_) => windowManager.startDragging(),
            child: Icon(
              // Token-driven: no inline ternary on _design.
              launcherTheme.searchIcon,
              size: launcherTheme.searchIconSize,
              color: launcherTheme.searchIconUsesOnSurface ? onSurface.withAlpha(160) : accent,
            ),
          ),
          textField: TextField(
            controller: _controller,
            focusNode: _focusNode,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: onSurface,
              fontSize: launcherTheme.searchFontSize,
              fontWeight: launcherTheme.searchFontWeight,
            ),
            decoration: InputDecoration(
              hintText: (_activePlugin != null ? _pluginFrame?.placeholder : null) ??
                  'Search applications, files, bookmarks...',
              hintStyle: TextStyle(color: onSurface.withAlpha(70)),
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
        ),

        // ── Results area ────────────────────────────────────────────────────
        Material(
          type: MaterialType.transparency,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: 260, maxHeight: _resultsMaxHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (_activePlugin == null && !hasInput && _results.isNotEmpty)
                  _buildResultsHeaderWithBadges(accent, onSurface),
                if (_activePlugin != null)
                  Expanded(child: _buildPluginBody())
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
                              return ListView.builder(
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
                                    resultWidget = _buildFileResult(context, theme, result.entity!, result.nodeId,
                                        index, isSelected, isRepeatingKey);
                                  } else if (result.isApp) {
                                    resultWidget = _buildAppResult(context, theme, result.appResult!, result.nodeId,
                                        index, isSelected, isRepeatingKey);
                                  } else if (result.isWindow) {
                                    resultWidget = _buildWindowResult(
                                        context, theme, result.window!, index, isSelected, isRepeatingKey);
                                  } else if (result.isBrowserTab) {
                                    resultWidget = _buildBrowserTabResult(
                                        context, theme, result.browserTab!, index, isSelected, isRepeatingKey);
                                  } else if (result.isBookmark) {
                                    resultWidget = _buildBookmarkResult(
                                        context, theme, result.bookmarkResult!, index, isSelected, isRepeatingKey);
                                  } else if (result.isNotion) {
                                    resultWidget = _buildNotionResult(
                                        context, theme, result.notionResult!, index, isSelected, isRepeatingKey);
                                  } else if (result.isObsidian) {
                                    resultWidget = _buildObsidianResult(
                                        context, theme, result.obsidianResult!, index, isSelected, isRepeatingKey);
                                  } else if (result.isSteam) {
                                    resultWidget = _buildSteamResult(
                                        context, theme, result.steamResult!, index, isSelected, isRepeatingKey);
                                  } else if (result.isInfo) {
                                    resultWidget = _buildInfoResult(
                                        context, theme, result.infoResult!, index, isSelected, isRepeatingKey);
                                  } else {
                                    resultWidget = _buildQuickActionResult(
                                        context, theme, result.quickAction!, index, isSelected, isRepeatingKey);
                                  }
                                  return KeyedSubtree(
                                    key: _resultKeys[_resultKeyId(result, index)],
                                    child: MouseRegion(
                                      onHover: (PointerHoverEvent event) => _selectResultFromPointerHover(event, index),
                                      child: Stack(
                                        alignment: Alignment.centerRight,
                                        children: <Widget>[resultWidget],
                                      ),
                                    ),
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
      ],
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
    final Widget frame = switch (_design) {
      LauncherDesign.serene => SereneLauncherFrame(
          accent: accent,
          child: innerContent,
        ),
      LauncherDesign.classic => ClassicLauncherFrame(
          surface: theme.colorScheme.surface,
          accent: accent,
          child: innerContent,
        ),
      LauncherDesign.command => CommandLauncherFrame(
          surface: theme.colorScheme.surface,
          accent: accent,
          onSurface: onSurface,
          resultCount: _results.length,
          child: innerContent,
        ),
      LauncherDesign.terminal => TerminalLauncherFrame(
          surface: theme.colorScheme.surface,
          accent: accent,
          onSurface: onSurface,
          resultCount: _results.length,
          child: innerContent,
        ),
      LauncherDesign.zen => ZenLauncherFrame(
          surface: theme.colorScheme.surface,
          accent: accent,
          onSurface: onSurface,
          resultCount: _results.length,
          child: innerContent,
        ),
      LauncherDesign.glass => GlassLauncherFrame(
          surface: theme.colorScheme.surface,
          accent: accent,
          onSurface: onSurface,
          child: innerContent,
        ),
      LauncherDesign.blueprint => BlueprintLauncherFrame(
          surface: theme.colorScheme.surface,
          accent: accent,
          onSurface: onSurface,
          resultCount: _results.length,
          child: innerContent,
        ),
      LauncherDesign.transit => TransitLauncherFrame(
          surface: theme.colorScheme.surface,
          accent: accent,
          onSurface: onSurface,
          resultCount: _results.length,
          child: innerContent,
        ),
      LauncherDesign.fluent => FluentLauncherFrame(
          surface: theme.colorScheme.surface,
          accent: accent,
          onSurface: onSurface,
          resultCount: _results.length,
          child: innerContent,
        ),
      LauncherDesign.manifesto => ManifestoLauncherFrame(
          surface: theme.colorScheme.surface,
          accent: accent,
          onSurface: onSurface,
          resultCount: _results.length,
          child: innerContent,
        ),
      LauncherDesign.orbit => OrbitLauncherFrame(
          surface: theme.colorScheme.surface,
          accent: accent,
          onSurface: onSurface,
          resultCount: _results.length,
          child: innerContent,
        ),
    };

    return Theme(
      data: (isTerminal || isZen || isGlass || isBlueprint || isTransit || isFluent || isManifesto || isOrbit)
          ? theme
          : theme.copyWith(
              textTheme: GoogleFonts.getTextTheme(Design.entryFontFamily),
            ),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _resetSelection,
        onSecondaryTap: _openActionsForActiveResult,
        child: frame,
      ),
    );
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
          final double nextHeight =
              (_resultsMaxHeight + details.delta.dy).clamp(_minResultsHeight, _maxResultsHeight).toDouble();
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
    return Row(
      children: <Widget>[
        Expanded(child: _design.buildSectionHeader(label: 'Results', accent: accent)),
        _LauncherStatusBadges(
          accent: accent,
          onSurface: onSurface,
          onOpenTimers: () => _openLauncherPanel(context, const TimersWidget()),
          onOpenReminders: () => _openLauncherPanel(context, const RemindersPanel()),
        ),
      ],
    );
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
  // ---------------------------------------------------------------------------
  // Item builders (delegate to split widget files)
  // ---------------------------------------------------------------------------

  Widget _buildShortcutResult(BuildContext context, ThemeData theme, LauncherShortcut shortcut, int index,
      bool isSelected, bool isRepeatingKey) {
    final Color accent = Design.accent;
    final Color onSurface = theme.colorScheme.onSurface;

    return MouseRegion(
      onHover: (PointerHoverEvent event) => _selectResultFromPointerHover(event, index),
      child: GestureDetector(
        onTap: () => _onShortcutPressed(shortcut),
        child: AnimatedContainer(
          duration: Duration(milliseconds: isRepeatingKey ? 50 : 200),
          curve: isRepeatingKey ? Curves.linear : Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? theme.highlightColor : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: accent.withAlpha(isSelected ? 40 : 20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(shortcut.icon, size: 18, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      shortcut.caption,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Press ${!shortcut.label.startsWith('>') && shortcut.label.length > 1 ? "'${shortcut.label}'" : shortcut.label} to search',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: onSurface.withAlpha(140),
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected) Icon(Icons.keyboard_return_rounded, size: 14, color: onSurface.withAlpha(100)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBookmarkResult(BuildContext context, ThemeData theme, BookmarkSearchResult result, int index,
      bool isSelected, bool isRepeatingKey) {
    final Color accent = Design.accent;
    return BookmarkSearchListItem(
      result: result,
      isSelected: isSelected,
      isRepeating: isRepeatingKey,
      accent: accent,
      onSurface: theme.colorScheme.onSurface,
      onTap: () => _openBookmarkResult(result),
      onHover: () => _selectResultFromMouse(index),
    );
  }

  Widget _buildFileResult(BuildContext context, ThemeData theme, FileSystemEntity entity, int? nodeId, int index,
      bool isSelected, bool isRepeatingKey) {
    final Color accent = Design.accent;
    final VoidCallback onTap = (_searchMode == LauncherSearchMode.desktopOnly && entity is Directory)
        ? () => _browseFolder(entity.path)
        : () => _openFile(entity.path, nodeId: nodeId);

    // Read the active design from the nearest LauncherTheme instead of _design.
    return LauncherListItem(
      entity: entity,
      isSelected: isSelected,
      isRepeating: isRepeatingKey,
      accent: accent,
      onSurface: theme.colorScheme.onSurface,
      isInHistory: false,
      onTap: onTap,
      onHover: () => _selectResultFromMouse(index),
      onRemoveFromHistory: () {},
    );
  }

  Widget _buildAppResult(BuildContext context, ThemeData theme, LauncherAppResult app, int? nodeId, int index,
      bool isSelected, bool isRepeatingKey) {
    final Color accent = Design.accent;
    return LauncherAppListItem(
      app: app,
      isSelected: isSelected,
      isRepeating: isRepeatingKey,
      accent: accent,
      onSurface: theme.colorScheme.onSurface,
      onTap: () => _openAppResult(app, nodeId: nodeId),
      onHover: () => _selectResultFromMouse(index),
    );
  }

  Widget _buildNotionResult(
      BuildContext context, ThemeData theme, NotionResult result, int index, bool isSelected, bool isRepeatingKey) {
    final Color accent = Design.accent;
    final Color onSurface = theme.colorScheme.onSurface;

    return MouseRegion(
      onHover: (PointerHoverEvent event) => _selectResultFromPointerHover(event, index),
      child: GestureDetector(
        onTap: () => _openNotionResult(result),
        child: AnimatedContainer(
          duration: Duration(milliseconds: isRepeatingKey ? 50 : 200),
          curve: isRepeatingKey ? Curves.linear : Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? theme.highlightColor : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withAlpha(isSelected ? 40 : 20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: result.emojiIcon != null
                    ? Text(result.emojiIcon!, style: const TextStyle(fontSize: 16))
                    : Icon(Icons.description_outlined, size: 18, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      result.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'NOTION ${result.objectType.toUpperCase()}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: onSurface.withAlpha(140),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.open_in_new_rounded, size: 14, color: onSurface.withAlpha(100)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildObsidianResult(
      BuildContext context, ThemeData theme, ObsidianNote result, int index, bool isSelected, bool isRepeatingKey) {
    final Color accent = Design.accent;
    final Color onSurface = theme.colorScheme.onSurface;

    return MouseRegion(
      onHover: (PointerHoverEvent event) => _selectResultFromPointerHover(event, index),
      child: GestureDetector(
        onTap: () => _openObsidianResult(result),
        child: AnimatedContainer(
          duration: Duration(milliseconds: isRepeatingKey ? 50 : 200),
          curve: isRepeatingKey ? Curves.linear : Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? theme.highlightColor : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withAlpha(isSelected ? 40 : 20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.menu_book_rounded, size: 18, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      result.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'OBSIDIAN · ${result.folder.isEmpty ? "VAULT ROOT" : result.folder.toUpperCase()}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: onSurface.withAlpha(140),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.open_in_new_rounded, size: 14, color: onSurface.withAlpha(100)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSteamResult(
      BuildContext context, ThemeData theme, SteamGame result, int index, bool isSelected, bool isRepeatingKey) {
    final Color accent = Design.accent;
    final Color onSurface = theme.colorScheme.onSurface;

    Widget leading;
    if (result.coverPath != null) {
      leading = ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(
          File(result.coverPath!),
          width: 26,
          height: 34,
          fit: BoxFit.cover,
          cacheWidth: 78,
          gaplessPlayback: true,
          errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) =>
              Icon(Icons.sports_esports_rounded, size: 18, color: accent),
        ),
      );
    } else {
      leading = Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: accent.withAlpha(isSelected ? 40 : 20),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.sports_esports_rounded, size: 18, color: accent),
      );
    }

    return MouseRegion(
      onHover: (PointerHoverEvent event) => _selectResultFromPointerHover(event, index),
      child: GestureDetector(
        onTap: () => _openSteamResult(result),
        child: AnimatedContainer(
          duration: Duration(milliseconds: isRepeatingKey ? 50 : 200),
          curve: isRepeatingKey ? Curves.linear : Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? theme.highlightColor : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: <Widget>[
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      result.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      result.sizeLabel.isEmpty ? 'STEAM' : 'STEAM · ${result.sizeLabel}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: onSurface.withAlpha(140),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.play_arrow_rounded, size: 16, color: accent.withAlpha(180)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoResult(BuildContext context, ThemeData theme, LauncherInfoResult result, int index, bool isSelected,
      bool isRepeatingKey) {
    final Color accent = Design.accent;
    final Color onSurface = theme.colorScheme.onSurface;

    return MouseRegion(
      onHover: (PointerHoverEvent event) => _selectResultFromPointerHover(event, index),
      child: AnimatedContainer(
        duration: Duration(milliseconds: isRepeatingKey ? 50 : 200),
        curve: isRepeatingKey ? Curves.linear : Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? theme.highlightColor : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withAlpha(isSelected ? 40 : 20),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(result.icon, size: 18, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    result.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    result.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: onSurface.withAlpha(140),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionResult(BuildContext context, ThemeData theme, QuickActionMenuEntry quickAction, int index,
      bool isSelected, bool isRepeatingKey) {
    // final GlobalKey actionKey = _quickActionKeys.putIfAbsent(quickAction.id, () => GlobalKey());
    final GlobalKey? actionKey = _quickActionKeys[quickAction.id];
    final Color accent = Design.accent;
    final bool showSplash = _quickActionSplashId == quickAction.id;

    return MouseRegion(
      onHover: (PointerHoverEvent event) => _selectResultFromPointerHover(event, index),
      child: AnimatedContainer(
        duration: Duration(milliseconds: isRepeatingKey ? 50 : 200),
        curve: isRepeatingKey ? Curves.linear : Curves.easeOutCubic,
        key: ValueKey<String>(quickAction.id),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.all(0),
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: showSplash
              ? accent.withAlpha(90)
              : isSelected
                  ? theme.highlightColor
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: KeyedSubtree(
          key: actionKey,
          child: quickAction.builder(context),
        ),
      ),
    );
  }

  Widget _buildWindowResult(
      BuildContext context, ThemeData theme, Window window, int index, bool isSelected, bool isRepeatingKey) {
    final Color accent = Design.accent;
    return WindowSearchListItem(
      window: window,
      isSelected: isSelected,
      isRepeating: isRepeatingKey,
      accent: accent,
      onSurface: theme.colorScheme.onSurface,
      onTap: () => _openWindow(window),
      onHover: () => _selectResultFromMouse(index),
    );
  }

  Widget _buildBrowserTabResult(
      BuildContext context, ThemeData theme, BrowserTab browserTab, int index, bool isSelected, bool isRepeatingKey) {
    final Color accent = Design.accent;
    return BrowserTabSearchListItem(
      browserTab: browserTab,
      isSelected: isSelected,
      isRepeating: isRepeatingKey,
      accent: accent,
      onSurface: theme.colorScheme.onSurface,
      onTap: () => _openBrowserTab(browserTab),
      onHover: () => _selectResultFromMouse(index),
    );
  }
}

class _LauncherStatusBadges extends StatefulWidget {
  const _LauncherStatusBadges({
    required this.accent,
    required this.onSurface,
    required this.onOpenTimers,
    required this.onOpenReminders,
  });

  final Color accent;
  final Color onSurface;
  final VoidCallback onOpenTimers;
  final VoidCallback onOpenReminders;

  @override
  State<_LauncherStatusBadges> createState() => _LauncherStatusBadgesState();
}

class _LauncherStatusBadgesState extends State<_LauncherStatusBadges> {
  Timer? _ticker;
  String _timerLabel = '';

  @override
  void initState() {
    super.initState();
    Boxes().loadLatestQuickTimers();
    _updateTimerLabel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _updateTimerLabel();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _updateTimerLabel() {
    if (Boxes.quickTimers.isEmpty) {
      if (_timerLabel.isNotEmpty) setState(() => _timerLabel = '');
      return;
    }
    Duration diff = Boxes.quickTimers[0].endTime.difference(DateTime.now());
    for (final QuickTimer t in Boxes.quickTimers) {
      final Duration d = t.endTime.difference(DateTime.now());
      if (d < diff) diff = d;
    }
    // A timer that has just elapsed yields a negative remaining duration until
    // it is cleared; clamp so the badge never shows "-5s" / negative minutes.
    if (diff.isNegative) diff = Duration.zero;
    final String label = diff.inMinutes != 0
        ? "${diff.inSeconds % 60 < 30 ? diff.inMinutes % 60 : (diff.inMinutes % 60) + 1}m"
        : "${diff.inSeconds % 60}s";
    if (label != _timerLabel) setState(() => _timerLabel = label);
  }

  @override
  Widget build(BuildContext context) {
    final bool hasTimers = Boxes.quickTimers.isNotEmpty;
    final bool hasReminders = user.persistentReminders.isNotEmpty;
    if (!hasTimers && !hasReminders) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (hasTimers)
            _StatusChip(
              accent: Design.accent,
              icon: Icons.timer_outlined,
              label: _timerLabel,
              tooltip: 'Timers (Alt+T)',
              onTap: widget.onOpenTimers,
            ),
          if (hasTimers && hasReminders) const SizedBox(width: 6),
          if (hasReminders)
            _StatusChip(
              accent: Design.accent,
              icon: Icons.warning_rounded,
              label: '${user.persistentReminders.length}',
              tooltip: 'Reminders (Alt+R)',
              onTap: widget.onOpenReminders,
            ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatefulWidget {
  const _StatusChip({
    required this.accent,
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  final Color accent;
  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onTap;

  @override
  State<_StatusChip> createState() => _StatusChipState();
}

class _StatusChipState extends State<_StatusChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: _hovered ? widget.accent.withAlpha(45) : widget.accent.withAlpha(22),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: widget.accent.withAlpha(_hovered ? 100 : 50),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(widget.icon, size: 10, color: widget.accent.withAlpha(210)),
                if (widget.label.isNotEmpty) ...<Widget>[
                  const SizedBox(width: 3),
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: widget.accent.withAlpha(210),
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionsHintBadge extends StatefulWidget {
  const _ActionsHintBadge({
    required this.accent,
    required this.onSurface,
    required this.onTap,
  });

  final Color accent;
  final Color onSurface;
  final VoidCallback onTap;

  @override
  State<_ActionsHintBadge> createState() => _ActionsHintBadgeState();
}

class _ActionsHintBadgeState extends State<_ActionsHintBadge> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: _hovered ? widget.accent.withAlpha(40) : widget.accent.withAlpha(18),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: widget.accent.withAlpha(_hovered ? 80 : 40),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.bolt_rounded,
                size: 10,
                color: widget.accent.withAlpha(200),
              ),
              const SizedBox(width: 3),
              Text(
                'Ctrl+K',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: widget.accent.withAlpha(200),
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
