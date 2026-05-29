import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:pool/pool.dart';
import 'package:sqlite3/sqlite3.dart' hide Row;
import 'package:tabamewin32/tabamewin32.dart' as native;
import 'package:window_manager/window_manager.dart';
import '../models/tray_watcher.dart';
import 'launcher_actions_panel.dart';

import '../models/classes/boxes.dart';
import '../models/converter.dart';
import '../models/db/file_index_db.dart';
import '../models/globals.dart';
import '../models/google_translator.dart';
import '../models/settings.dart';
import '../models/win32/win32.dart';
import '../models/win32/win_utils.dart';
import '../models/win32/window.dart';
import '../models/window_watcher.dart';
import '../services/file_indexer.dart';
import '../widgets/itzy/quickmenu/button_currency_converter.dart';
import '../widgets/itzy/quickmenu/button_notion.dart';
import '../widgets/itzy/quickmenu/button_quickactions.dart';
import 'launcher/result/result_item_app.dart';
import 'launcher/result/result_item_bookmark.dart';
import 'launcher/result/result_item_file.dart';
import 'launcher/result/result_item_window.dart';
import 'launcher/search/bookmarks_search_handler.dart';
import 'launcher/search/desktop_search_handler.dart';
import 'launcher/search/launcher_search_context.dart';
import 'launcher/search/search_handler.dart';
import 'launcher/search/search_utils.dart';
import 'launcher/search/windows_search_handler.dart';
import 'launcher_search_models.dart';
import 'launcher/launcher_design.dart';
import 'launcher/launcher_design_builder.dart';
import 'launcher/result/results_item_serene.dart';

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

class _LauncherFunctionCommand {
  const _LauncherFunctionCommand({
    required this.name,
    required this.description,
    required this.usage,
    required this.icon,
    required this.handler,
    this.aliases = const <String>[],
    this.debounce = Duration.zero,
  });

  final String name;
  final String description;
  final String usage;
  final IconData icon;
  final List<String> aliases;
  final Duration debounce;
  final FutureOr<List<LauncherSearchResultItem>> Function(String input) handler;

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
  static const String _launcherAppIconPrefix = 'app_';
  static const String _launcherAppsFolderPrefix = r'shell:AppsFolder\';
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
  String? _quickActionSplashId;
  bool _mouseSelectionEnabled = true;
  Offset? _lastMousePosition;
  Timer? _quickActionSplashTimer;
  Timer? _keyRepeatTimer;
  Timer? _launcherFocusRetryTimer;
  LogicalKeyboardKey? _lastPressedKey;
  bool _isRepairingFileIndex = false;
  bool _isSyncingLauncherAppsCatalog = false;
  LauncherDesign _design = LauncherDesign.serene;

  List<LauncherSearchResultItem> _results = <LauncherSearchResultItem>[];
  bool _isSearching = false;
  bool _canConsumePendingInput = false;
  LauncherSearchMode _searchMode = LauncherSearchMode.mixed;
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
      usage: r'$translate "hello" from en to ro',
      icon: Icons.translate_rounded,
      debounce: const Duration(milliseconds: 550),
      handler: _buildFunctionTranslateResults,
    ),
    _LauncherFunctionCommand(
      name: 'reindex',
      description: 'Reindex launcher files',
      usage: r'$reindex files',
      icon: Icons.manage_search_rounded,
      handler: _buildFunctionReindexResults,
    ),
    // _LauncherFunctionCommand(
    //   name: 'reload',
    //   description: 'Reload Hotkeys',
    //   usage: r'$reload settings',
    //   icon: Icons.manage_search_rounded,
    //   handler: _buildFunctionReloadSettingsResults,
    // ),
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
      caption: 'Bookmarks',
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
  ];
  void _copyItem() {
    if (_results.isEmpty) return;

    final int idx = _activeIndexNotifier.value.clamp(0, _results.length - 1);
    final LauncherSearchResultItem item = _results[idx];

    // Shortcuts and info rows have no meaningful actions.
    if (item.isShortcut || item.isInfo) return;
    if (item.isFile && item.entity != null) {
      final bool isDir = item.entity is Directory;
      isDir ? ClipboardExtension.copyFolder(item.entity!.path) : ClipboardExtension.copyFile(item.entity!.path);
      _infoText = "${isDir ? "Folder" : "File"} Copied";
      _infoIcon = isDir ? Icons.folder_rounded : Icons.file_copy_rounded;
      // final String oldTitle = item.bookmarkResult!.bookmark!.title;
      // item.bookmarkResult!.bookmark!.title = "Copied";
      if (mounted) setState(() {});
      Future<void>.delayed(const Duration(milliseconds: 500), () {
        _infoText = null;
        _infoIcon = null;
        // item.bookmarkResult!.bookmark!.title = oldTitle;
        if (mounted) setState(() {});
      });
      // item.
    }
  }

  void _openActionsForActiveResult() {
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

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      // Escape: go back to quickmenu
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.keyK &&
          HardwareKeyboard.instance.isControlPressed) {
        _openActionsForActiveResult();
        setState(() {});
        return KeyEventResult.handled;
      }
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.keyC &&
          HardwareKeyboard.instance.isControlPressed) {
        _copyItem();
        setState(() {});
        return KeyEventResult.handled;
      }
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
          userSettings.launcherSearchText = '';
          QuickMenuFunctions.refreshQuickMenu();
          Win32.setWindowInvisible(false);
        });
        return KeyEventResult.handled;
      }

      if (event.logicalKey == LogicalKeyboardKey.arrowDown || event.logicalKey == LogicalKeyboardKey.arrowUp) {
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
    final int savedIndex = Boxes.pref.getInt('launcherDesign') ?? 0;
    _design = LauncherDesign.values[savedIndex.clamp(0, LauncherDesign.values.length - 1)];
    _controller.text = userSettings.launcherSearchText;
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
      Future<void>.delayed(const Duration(milliseconds: 4),
          () => _controller.selection = TextSelection.collapsed(offset: _controller.text.length));
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

    userSettings.launcherSearchText = '';
    Globals.quickMenuSearchInputVersion.removeListener(_consumePendingQuickMenuSearchInput);
    FocusManager.instance.removeListener(_onFocusManagerChanged);
    _isRepeatingKey.dispose();

    if (!FileIndexer.instance.isIndexing) {
      FileIndexDb.instance.close();
    }
    Globals.clearQuickMenuSearchInput();

    _searchDebounce?.cancel();
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
      await _syncLauncherAppsCatalog();
    } catch (error, stackTrace) {
      debugPrint('Launcher: Failed to refresh launcher catalogs: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    if (!mounted) return;
    _onSearchChanged(_controller.text);
  }

  Future<void> _syncLauncherAppsCatalog() async {
    if (_isSyncingLauncherAppsCatalog) return;
    _isSyncingLauncherAppsCatalog = true;

    try {
      final Database db = await FileIndexDb.instance.database;
      final Directory iconCacheDirectory = await _ensureLauncherIconCacheDirectory();
      final List<native.AppInfo> apps = _dedupeLauncherApps(await native.AppEnumeration.getAllApps());

      final int rootId = FileIndexDb.instance.findNode(null, FileIndexDb.launcherAppsRootName) ??
          FileIndexDb.instance.insertNode(
            null,
            FileIndexDb.launcherAppsRootName,
            true,
            isSearchable: false,
            entryType: SearchResultEntryType.app,
          );

      final List<SearchResultNode> existingNodes =
          FileIndexDb.instance.getChildNodes(rootId).where((SearchResultNode node) => node.isApp).toList();
      final Map<String, SearchResultNode> existingByAumid = <String, SearchResultNode>{
        for (final SearchResultNode node in existingNodes)
          if ((node.appUserModelId ?? '').isNotEmpty) node.appUserModelId!: node,
      };
      final Map<String, List<SearchResultNode>> existingByStableIdentity = <String, List<SearchResultNode>>{};
      for (final SearchResultNode node in existingNodes) {
        final String stableIdentity = node.stableIdentity ?? '';
        if (stableIdentity.isEmpty) continue;
        existingByStableIdentity.putIfAbsent(stableIdentity, () => <SearchResultNode>[]).add(node);
      }

      final Set<int> matchedNodeIds = <int>{};
      final Set<String> expectedIconFiles = <String>{
        for (final native.AppInfo app in apps) _launcherAppIconFileName(app.appUserModelId),
      };

      db.execute('BEGIN IMMEDIATE TRANSACTION');
      try {
        for (final native.AppInfo app in apps) {
          final String name = app.name.trim().isEmpty ? app.appUserModelId : app.name.trim();
          final String subtitle = app.executable.trim().isNotEmpty ? app.executable.trim() : app.appUserModelId;
          final String stableIdentity = _buildLauncherAppStableIdentity(app);
          final String launchTarget = _buildLauncherAppLaunchTarget(app.appUserModelId);

          SearchResultNode? existingNode = existingByAumid[app.appUserModelId];
          if (existingNode == null && stableIdentity.isNotEmpty) {
            final List<SearchResultNode>? candidates = existingByStableIdentity[stableIdentity];
            while (candidates != null && candidates.isNotEmpty) {
              final SearchResultNode candidate = candidates.removeAt(0);
              if (matchedNodeIds.contains(candidate.id)) continue;
              existingNode = candidate;
              break;
            }
          }

          if (existingNode == null) {
            final int nodeId = FileIndexDb.instance.insertAppNode(
              rootId,
              name: name,
              launchTarget: launchTarget,
              parsingName: app.parsingName,
              appUserModelId: app.appUserModelId,
              subtitle: subtitle,
              stableIdentity: stableIdentity,
            );
            matchedNodeIds.add(nodeId);
            continue;
          }

          matchedNodeIds.add(existingNode.id);
          FileIndexDb.instance.updateAppNode(
            id: existingNode.id,
            parentId: rootId,
            name: name,
            launchTarget: launchTarget,
            parsingName: app.parsingName,
            appUserModelId: app.appUserModelId,
            subtitle: subtitle,
            stableIdentity: stableIdentity,
          );
        }

        for (final SearchResultNode node in existingNodes) {
          if (matchedNodeIds.contains(node.id)) continue;
          FileIndexDb.instance.deleteNode(node.id);
        }

        db.execute('COMMIT');
      } catch (_) {
        db.execute('ROLLBACK');
        rethrow;
      }

      await _cacheMissingLauncherAppIcons(apps, iconCacheDirectory);
      await _removeStaleLauncherAppIcons(iconCacheDirectory, expectedIconFiles);
    } catch (error, stackTrace) {
      debugPrint('Launcher: Failed to sync AppEnumeration catalog: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _isSyncingLauncherAppsCatalog = false;
    }
  }

  List<native.AppInfo> _dedupeLauncherApps(List<native.AppInfo> apps) {
    final Map<String, native.AppInfo> byAumid = <String, native.AppInfo>{};

    for (final native.AppInfo app in apps) {
      final String aumid = app.appUserModelId.trim();
      if (aumid.isEmpty) continue;

      final native.AppInfo? existing = byAumid[aumid];
      if (existing == null ||
          (existing.parsingName.trim().isEmpty && app.parsingName.trim().isNotEmpty) ||
          (existing.executable.trim().isEmpty && app.executable.trim().isNotEmpty)) {
        byAumid[aumid] = app;
      }
    }

    final List<native.AppInfo> deduped = byAumid.values.toList(growable: false);
    deduped.sort((native.AppInfo a, native.AppInfo b) {
      final int byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      if (byName != 0) return byName;
      return a.appUserModelId.toLowerCase().compareTo(b.appUserModelId.toLowerCase());
    });
    return deduped;
  }

  Future<Directory> _ensureLauncherIconCacheDirectory() async {
    final Directory directory = Directory(p.join(WinUtils.getTabameAppDataFolder(), 'cache', 'icon_cache'));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  String _buildLauncherAppLaunchTarget(String appUserModelId) => '$_launcherAppsFolderPrefix$appUserModelId';

  String _buildLauncherAppStableIdentity(native.AppInfo app) {
    final String executableName = app.executable.trim().isNotEmpty
        ? p.basenameWithoutExtension(app.executable.trim())
        : p.basenameWithoutExtension(app.parsingName.trim());

    return <String>[
      _normalizeLauncherAppIdentityPart(app.name),
      _normalizeLauncherAppIdentityPart(executableName),
      _normalizeLauncherAppIdentityPart(app.arguments),
    ].join('|');
  }

  String _normalizeLauncherAppIdentityPart(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _launcherAppIconHash(String appUserModelId) => appUserModelId.hashCode.toString();

  String _launcherAppIconFileName(String appUserModelId) =>
      '$_launcherAppIconPrefix${_launcherAppIconHash(appUserModelId)}.png';

  Future<void> _cacheMissingLauncherAppIcons(List<native.AppInfo> apps, Directory iconCacheDirectory) async {
    final Pool pool = Pool(3);

    await Future.wait(apps.map((native.AppInfo app) async {
      final File iconFile = File(p.join(iconCacheDirectory.path, _launcherAppIconFileName(app.appUserModelId)));
      if (await iconFile.exists()) return;

      await pool.withResource(() => _cacheLauncherAppIcon(app, iconFile));
    }));

    await pool.close();
  }

  Future<void> _cacheLauncherAppIcon(native.AppInfo app, File iconFile) async {
    if (app.parsingName.trim().isEmpty) return;

    try {
      final native.AppIconData? icon = await native.AppEnumeration.getAppIcon(app.parsingName, size: 128);
      if (icon == null || icon.width <= 0 || icon.height <= 0 || icon.pixels.isEmpty) return;

      final ByteData? pngBytes = await _convertLauncherAppIconToPng(icon);
      if (pngBytes == null) return;

      await iconFile.writeAsBytes(pngBytes.buffer.asUint8List(), flush: true);
    } catch (error, stackTrace) {
      debugPrint('Launcher: Failed to cache icon for ${app.appUserModelId}: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<ByteData?> _convertLauncherAppIconToPng(native.AppIconData icon) {
    final Completer<ByteData?> completer = Completer<ByteData?>();

    ui.decodeImageFromPixels(
      icon.pixels,
      icon.width,
      icon.height,
      ui.PixelFormat.bgra8888,
      (ui.Image image) async {
        try {
          final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
          completer.complete(data);
        } catch (error, stackTrace) {
          completer.completeError(error, stackTrace);
        } finally {
          image.dispose();
        }
      },
    );

    return completer.future;
  }

  Future<void> _removeStaleLauncherAppIcons(Directory iconCacheDirectory, Set<String> expectedIconFiles) async {
    if (!await iconCacheDirectory.exists()) return;

    await for (final FileSystemEntity entity in iconCacheDirectory.list()) {
      if (entity is! File) continue;
      final String fileName = p.basename(entity.path);
      if (!fileName.startsWith(_launcherAppIconPrefix) || !fileName.endsWith('.png')) continue;
      if (expectedIconFiles.contains(fileName)) continue;

      try {
        await entity.delete();
      } catch (_) {}
    }
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
    return true;
  }

  void _requestLauncherFocus({bool focusWindow = false}) {
    void requestFocusIfNeeded() {
      if (!_canFocusLauncher) return;
      if (focusWindow) unawaited(windowManager.focus());
      if (!_focusNode.hasPrimaryFocus) {
        _resetSelection();
      }
    }

    requestFocusIfNeeded();
    WidgetsBinding.instance.addPostFrameCallback((_) => requestFocusIfNeeded());
    _launcherFocusRetryTimer?.cancel();
    _launcherFocusRetryTimer = Timer(const Duration(milliseconds: 120), requestFocusIfNeeded);
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
    if (key == LogicalKeyboardKey.arrowDown) {
      _activeIndexNotifier.value = ((_activeIndexNotifier.value + 1) % _results.length).toInt();
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _activeIndexNotifier.value = ((_activeIndexNotifier.value - 1 + _results.length) % _results.length).toInt();
    }
    _scrollToActiveIndex();
  }

  void _scrollToActiveIndex() {
    if (!_scrollController.hasClients || _results.isEmpty) return;
    final int index = _activeIndexNotifier.value;
    if (index < 0 || index >= _results.length) return;

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
  int _searchRequestId = 0;
  // Remove this field entirely:
  // And _startWindowRefreshLoop becomes simply:
  void _startWindowRefreshLoop() {
    _windowRefreshTimer?.cancel();
    _windowRefreshTimer = Timer.periodic(const Duration(milliseconds: 900), (Timer timer) async {
      if (!mounted || Globals.quickMenuPage != QuickMenuPage.launcher) return;

      final bool updated = await WindowWatcher.fetchWindows();
      if (WindowWatcher.list.any((Window e) => e.process.exe.toLowerCase() == "taskmgr.exe")) await Tray.fetchTray();
      if (!mounted || !updated || Globals.quickMenuPage != QuickMenuPage.launcher) return;

      _refreshVisibleWindowResults();
    });
  }

  void _refreshVisibleWindowResults() {
    if (_results.isEmpty) return;

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
    if (pendingLauncherQuickAction.isNotEmpty) {
      _pendingLauncherQuickAction = pendingLauncherQuickAction;
      _pendingLauncherQuickActionAttempt = 0;
    }

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

  // ---------------------------------------------------------------------------
  // Search logic
  // ---------------------------------------------------------------------------

  void _onSearchChanged(String query) {
    userSettings.launcherSearchText = query;
    _scrollResultsToTopForQuery(query);
    _searchDebounce?.cancel();
    final int requestId = ++_searchRequestId;
    setState(() => _searchMode = _getLauncherSearchMode(query));
    final LauncherSearchMode searchMode = _searchMode;
    final String normalizedQuery = _getNormalizedQuery(query);

    if (query.isEmpty || (normalizedQuery.isEmpty && searchMode == LauncherSearchMode.mixed)) {
      _setResults(_launcherShortcuts, isSearching: false);
      return;
    }

    _setSearching(true);
    _searchDebounce = Timer(const Duration(milliseconds: 50), () {
      if (!_isActiveSearch(requestId, query)) return;
      _runSearch(requestId, query, normalizedQuery, searchMode);
    });
  }

  void _runSearch(int requestId, String query, String normalizedQuery, LauncherSearchMode searchMode) {
    if (!_isActiveSearch(requestId, query)) return;

    final LauncherSearchContext context = LauncherSearchContext(
      token: _searchToken,
      buildContext: this.context,
      requestId: requestId,
      query: query,
      normalizedQuery: normalizedQuery,
      lowerQuery: normalizedQuery.toLowerCase(),
      setSearching: _setSearching,
      setResults: _setResults,
      isActiveSearch: _isActiveSearch,
    );

    switch (searchMode) {
      case LauncherSearchMode.windowsOnly:
        WindowsSearchHandler.handle(context);
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
        DesktopSearchHandler.handle(context);
        break;
      case LauncherSearchMode.notionOnly:
        _handleNotionSearch(context);
        break;
      case LauncherSearchMode.timerCommand:
        _handleTimerCommand(context);
        break;
      case LauncherSearchMode.functionCommand:
        _handleFunctionCommand(context);
        break;
      default:
        MixedSearchHandler.handle(context, searchMode);
        break;
    }
  }

  void _handleBookmarkKindSearch(LauncherSearchContext context, BookmarkResultKind kind) {
    final List<LauncherSearchResultItem> results = findBookmarkMatches(
      context.normalizedQuery,
      includeAllOnEmpty: context.normalizedQuery.isEmpty,
      kinds: <BookmarkResultKind>{kind},
    ).map(LauncherSearchResultItem.bookmark).toList();
    context.setResults(results, isSearching: false);
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
        final Color accent = userSettings.themeColors.accentColor;
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
    userSettings.launcherSearchText = '';
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

    if (command.debounce > Duration.zero) {
      await Future<void>.delayed(command.debounce);
      if (!context.isActiveSearch(context.requestId, context.query)) return;
    }

    context.setSearching(true);
    try {
      final List<LauncherSearchResultItem> results = await command.handler(commandInput);
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
    if (await cacheDirectory.exists()) {
      await for (final FileSystemEntity entity in cacheDirectory.list()) {
        await entity.delete(recursive: true);
      }
    }
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
      emptyHelp: r'Format: $c 1+3/5',
      icon: Icons.calculate_rounded,
      parser: Parsers().calculator,
    );
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
          subtitle: r'Format: $cur 1 USD to EUR or $cur 1 USD',
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
      return LauncherSearchResultItem.quickAction(_buildCopyFunctionAction(
        id: '$idPrefix:$value',
        title: value,
        subtitle: result.error.isEmpty ? 'Copy result' : result.error,
        icon: icon,
        value: value,
      ));
    }).toList(growable: false);
  }

  Future<List<LauncherSearchResultItem>> _buildFunctionTranslateResults(String input) async {
    final _ParsedTranslateCommand? parsed = _parseTranslateCommand(input);
    if (parsed == null) {
      return <LauncherSearchResultItem>[
        const LauncherSearchResultItem.info(LauncherInfoResult(
          id: 'function-translate-help',
          title: 'Translate text',
          subtitle: r'Use $translate message or $translate "message" from en to ro',
          icon: Icons.translate_rounded,
        )),
      ];
    }

    final GoogleTranslator translator = GoogleTranslator();
    final List<LauncherSearchResultItem> results = <LauncherSearchResultItem>[];
    try {
      for (final String target in parsed.targets) {
        final GoogleTranslateResponse response = await translator.translate(parsed.text, from: parsed.from, to: target);
        final String targetName = GoogleTranslator.languages[target] ?? target.toUpperCase();
        final String source = response.from.language.iso.isEmpty ? parsed.from : response.from.language.iso;
        results.add(LauncherSearchResultItem.quickAction(_buildCopyFunctionAction(
          id: 'function-translate:$target:${response.text}',
          title: response.text.isEmpty ? 'No translation returned' : response.text,
          subtitle: '$targetName - from $source',
          icon: Icons.translate_rounded,
          value: response.text,
        )));
      }
    } finally {
      translator.close();
    }
    return results;
  }

  _ParsedTranslateCommand? _parseTranslateCommand(String input) {
    String text = input.trim();
    if (text.isEmpty) return null;

    String from = 'auto';
    List<String> targets = _loadTranslatorTargets();
    final RegExpMatch? explicit = RegExp(r'^(.+?)\s+from\s+(.+?)\s+to\s+(.+)$', caseSensitive: false).firstMatch(text);
    if (explicit != null) {
      text = _stripQuotes(explicit.group(1)!.trim());
      final String? parsedFrom = GoogleTranslator.getIsoCode(explicit.group(2)!.trim());
      final String? parsedTo = GoogleTranslator.getIsoCode(explicit.group(3)!.trim());
      if (parsedFrom == null || parsedTo == null) return null;
      from = parsedFrom;
      targets = <String>[parsedTo];
    } else {
      text = _stripQuotes(text);
    }
    if (text.isEmpty || targets.isEmpty) return null;
    return _ParsedTranslateCommand(text: text, from: from, targets: targets);
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
  }) {
    return _buildFunctionAction(
      id: id,
      title: title,
      subtitle: subtitle,
      icon: icon,
      searchTerms: <String>[title, subtitle, value],
      onExecute: () {
        Clipboard.setData(ClipboardData(text: value));
        _finishLauncherFunctionExecution();
      },
    );
  }

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
        final Color accent = userSettings.themeColors.accentColor;
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

    final List<NotionResult> cached = NotionSearchCache.cached(context.normalizedQuery);
    if (cached.isNotEmpty || context.normalizedQuery.isEmpty) {
      context.setResults(cached.map(LauncherSearchResultItem.notion).toList(), isSearching: false);
    }

    if (context.normalizedQuery.isEmpty) return;
    if (NotionSearchCache.apiKey.isEmpty) return;

    context.setSearching(true);
    try {
      final List<NotionResult> results = await NotionSearchCache.search(context.normalizedQuery);
      if (!context.isActiveSearch(context.requestId, context.query)) return;
      context.setResults(results.map(LauncherSearchResultItem.notion).toList(),
          isSearching: false, resetSelection: false);
    } catch (_) {
      if (context.isActiveSearch(context.requestId, context.query)) {
        context.setSearching(false);
      }
    }
  }

  bool _isActiveSearch(int requestId, String query, {bool trimLeft = false}) {
    if (!mounted || requestId != _searchRequestId) return false;
    return trimLeft ? _controller.text.trimLeft() == query : _controller.text == query;
  }

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

    int nextIndex = 0;
    if (!resetSelection && _results.isNotEmpty && _activeIndexNotifier.value < _results.length) {
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
      if (resetSelection) {
        _activeIndexNotifier.value = 0;
      } else {
        _activeIndexNotifier.value = nextIndex;
      }
      if (isSearching != null) {
        _isSearching = isSearching;
      }
    });

    if (resetSelection && _scrollController.hasClients) {
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

    final List<LauncherSearchResultItem> stale = <LauncherSearchResultItem>[];

    for (final LauncherSearchResultItem item in fileItems) {
      final FileSystemEntityType type = await FileSystemEntity.type(item.entity!.path);
      if (type == FileSystemEntityType.notFound) {
        stale.add(item);
      }
    }

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
    if (!mounted || !identical(_results, snapshot)) return;

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

    if (result.isShortcut) {
      _onShortcutPressed(result.shortcut!);
      return;
    }

    if (result.isFile) {
      _openFile(result.entity!.path, nodeId: result.nodeId);
      return;
    }
    if (result.isApp) {
      _openAppResult(result.appResult!, nodeId: result.nodeId);
      return;
    }
    if (result.isWindow) {
      _openWindow(result.window!);
      return;
    }
    if (result.isBookmark) {
      _openBookmarkResult(result.bookmarkResult!);
      return;
    }
    if (result.isNotion) {
      _openNotionResult(result.notionResult!);
      return;
    }

    if (result.quickAction != null) {
      _runQuickAction(result.quickAction!);
    }

    _resetSelection();
  }

  void _openBookmarkResult(BookmarkSearchResult result) {
    switch (result.kind) {
      case BookmarkResultKind.bookmark:
        WinUtils.open(result.bookmark!.stringToExecute, parseParamaters: true);
        QuickMenuFunctions.hideQuickMenu();
        userSettings.launcherSearchText = '';
      case BookmarkResultKind.cliBook:
        // Copy the CLI command to clipboard.
        Clipboard.setData(ClipboardData(text: result.cli!.value));
        QuickMenuFunctions.hideQuickMenu();
        userSettings.launcherSearchText = '';
      case BookmarkResultKind.appItem:
        WinUtils.open(result.app!.path, arguments: result.app!.arguments);
        QuickMenuFunctions.hideQuickMenu();
        userSettings.launcherSearchText = '';
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
    QuickMenuFunctions.hideQuickMenu();
    Globals.quickMenuPage = QuickMenuPage.quickMenu;
    userSettings.launcherSearchText = '';
  }

  void _openAppResult(LauncherAppResult app, {int? nodeId}) {
    if (nodeId != null) {
      unawaited(_recordFileOpen(nodeId));
    }

    final String launchTarget =
        app.appUserModelId.isNotEmpty ? _buildLauncherAppLaunchTarget(app.appUserModelId) : app.launchTarget;
    if (launchTarget.isEmpty) return;

    WinUtils.open(launchTarget, parseParamaters: false);
    QuickMenuFunctions.hideQuickMenu();
    Globals.quickMenuPage = QuickMenuPage.quickMenu;
    userSettings.launcherSearchText = '';
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
      await _syncLauncherAppsCatalog();
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

  void _openWindow(Window window) async {
    await QuickMenuFunctions.hideQuickMenu();
    Win32.activateWindow(window.hWnd);
    Globals.lastFocusedWinHWND = window.hWnd;
    Globals.quickMenuPage = QuickMenuPage.quickMenu;
    userSettings.launcherSearchText = '';
  }

  LauncherSearchMode _getLauncherSearchMode(String query) {
    // final String trimmed = query.trimLeft();
    if (query.startsWith('/')) return LauncherSearchMode.actionsOnly;
    if (query.startsWith(r'$')) return LauncherSearchMode.functionCommand;
    if (query.startsWith('.')) return LauncherSearchMode.windowsOnly;
    if (query.startsWith(';')) return LauncherSearchMode.desktopOnly;
    if (query.startsWith('timer ')) return LauncherSearchMode.timerCommand;
    if (query.startsWith('n ')) return LauncherSearchMode.notionOnly;
    if (query.startsWith('cli ')) return LauncherSearchMode.cliOnly;
    if (query.startsWith('app ')) return LauncherSearchMode.appsOnly;
    if (query.startsWith('b ')) return LauncherSearchMode.bookmarkOnly;
    if (query.startsWith('>') || query.startsWith('?') || query.startsWith(' ')) {
      return LauncherSearchMode.filesOnly;
    }
    if (query.startsWith("'")) return LauncherSearchMode.bookmarksOnly;
    return LauncherSearchMode.mixed;
  }

  String _getNormalizedQuery(String query) {
    // final String trimmed = query.trimLeft();
    if (query.startsWith('timer ')) return query.substring(6).trimLeft();
    if (query.startsWith('cli ')) return query.substring(4).trimLeft();
    if (query.startsWith('app ')) return query.substring(4).trimLeft();
    if (query.startsWith('n ')) return query.substring(2).trimLeft();
    if (query.startsWith('b ')) return query.substring(2).trimLeft();
    if (query.startsWith('/') ||
        query.startsWith('.') ||
        query.startsWith(r'$') ||
        query.startsWith('>') ||
        query.startsWith('?') ||
        query.startsWith(';') ||
        query.startsWith(' ') ||
        query.startsWith("'")) {
      return query.substring(1).trimLeft();
    }
    return query;
  }

  void _openNotionResult(NotionResult result) {
    if (result.url.isEmpty) return;
    WinUtils.open(result.url);
    QuickMenuFunctions.hideQuickMenu();
    Globals.quickMenuPage = QuickMenuPage.quickMenu;
    userSettings.launcherSearchText = '';
  }

  void _syncQuickActionKeys(List<LauncherSearchResultItem> results) {
    final Set<String> activeQuickActionIds = results
        .where((LauncherSearchResultItem result) => result.quickAction != null)
        .map((LauncherSearchResultItem result) => result.quickAction!.id)
        .toSet();
    _quickActionKeys.removeWhere((String key, GlobalKey value) => !activeQuickActionIds.contains(key));
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
    final TextSelection savedSelection = _controller.selection;
    _focusNode.requestFocus();

    Future<void>.delayed(const Duration(milliseconds: 4), () => handlePostFrameCallback(savedSelection));
    WidgetsBinding.instance.addPostFrameCallback((_) => handlePostFrameCallback(savedSelection));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = userSettings.themeColors.accentColor;
    final Color onSurface = theme.colorScheme.onSurface;
    final bool hasInput = _controller.text.trim().isNotEmpty;
    return Theme(
      data: theme.copyWith(
        textTheme: ThemeData.dark().textTheme.apply(fontFamily: userSettings.theme.entryFontFamily),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          _resetSelection();
        },
        onSecondaryTap: () {
          _openActionsForActiveResult();
        },
        child: _design == LauncherDesign.serene
            ? SereneLauncherFrame(
                accent: accent,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // Search bar

                    _design.buildSearchBar(
                      surface: theme.colorScheme.surface,
                      accent: accent,
                      onSurface: onSurface,
                      dragHandle: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onPanStart: (_) => windowManager.startDragging(),
                        child: Icon(
                          Icons.search_rounded,
                          size: _design == LauncherDesign.serene ? 22 : 20,
                          color: _design == LauncherDesign.serene ? onSurface.withAlpha(160) : accent,
                        ),
                      ),
                      textField: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: onSurface,
                          fontSize: _design == LauncherDesign.serene ? 16 : 15,
                          fontWeight: _design == LauncherDesign.serene ? FontWeight.w400 : null,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search applications, files, bookmarks...',
                          hintStyle: TextStyle(color: onSurface.withAlpha(70)),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.only(
                            left: 0,
                            top: 6,
                            bottom: 6,
                            right: _infoText != null ? 120 : 8,
                          ),
                        ),
                        onChanged: _onSearchChanged,
                        onSubmitted: _onSubmitted,
                      ),
                      trailingBadge: _infoText != null ? _buildInfoBadge(accent, onSurface) : null,
                      isSearching: _isSearching,
                    ),
                    // Results area
                    Material(
                      type: MaterialType.transparency,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 260, maxHeight: 320),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            if (!hasInput && _results.isNotEmpty)
                              _design.buildSectionHeader(label: 'Results', accent: accent),
                            if (Boxes.searchFolders.isEmpty &&
                                (_searchMode == LauncherSearchMode.filesOnly ||
                                    _searchMode == LauncherSearchMode.mixed))
                              Expanded(
                                child: Center(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 40),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        Icon(Icons.folder_off_rounded, size: 48, color: accent.withAlpha(40)),
                                        const SizedBox(height: 16),
                                        Text(
                                          'No Search Folders Configured',
                                          textAlign: TextAlign.center,
                                          style: theme.textTheme.titleMedium?.copyWith(
                                            color: onSurface.withAlpha(180),
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Add folders in Settings -> Quickmenu -> Launcher to start searching files.',
                                          textAlign: TextAlign.center,
                                          style: theme.textTheme.bodyMedium?.copyWith(
                                            color: onSurface.withAlpha(100),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
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
                                          return ListView.builder(
                                            controller: _scrollController,
                                            shrinkWrap: true,
                                            itemCount: _results.length,
                                            itemBuilder: (BuildContext context, int index) {
                                              final LauncherSearchResultItem result = _results[index];
                                              final bool isSelected = index == activeIndex;
                                              late final Widget resultWidget;
                                              if (result.isShortcut) {
                                                resultWidget = _buildShortcutResult(context, theme, result.shortcut!,
                                                    index, isSelected, isRepeatingKey);
                                              } else if (result.isFile) {
                                                resultWidget = _buildFileResult(context, theme, result.entity!,
                                                    result.nodeId, index, isSelected, isRepeatingKey);
                                              } else if (result.isApp) {
                                                resultWidget = _buildAppResult(context, theme, result.appResult!,
                                                    result.nodeId, index, isSelected, isRepeatingKey);
                                              } else if (result.isWindow) {
                                                resultWidget = _buildWindowResult(
                                                    context, theme, result.window!, index, isSelected, isRepeatingKey);
                                              } else if (result.isBookmark) {
                                                resultWidget = _buildBookmarkResult(context, theme,
                                                    result.bookmarkResult!, index, isSelected, isRepeatingKey);
                                              } else if (result.isNotion) {
                                                resultWidget = _buildNotionResult(context, theme, result.notionResult!,
                                                    index, isSelected, isRepeatingKey);
                                              } else if (result.isInfo) {
                                                resultWidget = _buildInfoResult(context, theme, result.infoResult!,
                                                    index, isSelected, isRepeatingKey);
                                              } else {
                                                resultWidget = _buildQuickActionResult(context, theme,
                                                    result.quickAction!, index, isSelected, isRepeatingKey);
                                              }
                                              return KeyedSubtree(
                                                key: _resultKeys[_resultKeyId(result, index)],
                                                child: MouseRegion(
                                                  onHover: (PointerHoverEvent event) =>
                                                      _selectResultFromPointerHover(event, index),
                                                  child: Stack(
                                                    alignment: Alignment.centerRight,
                                                    children: <Widget>[
                                                      resultWidget,
                                                    ],
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
                ),
              )
            : Container(
                constraints: const BoxConstraints(minHeight: 360),
                decoration: _design.outerDecoration(surface: theme.colorScheme.surface, accent: accent),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // Search bar

                    _design.buildSearchBar(
                      surface: theme.colorScheme.surface,
                      accent: accent,
                      onSurface: onSurface,
                      dragHandle: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onPanStart: (_) => windowManager.startDragging(),
                        child: Icon(
                          Icons.search_rounded,
                          size: _design == LauncherDesign.serene ? 22 : 20,
                          color: _design == LauncherDesign.serene ? onSurface.withAlpha(160) : accent,
                        ),
                      ),
                      textField: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: onSurface,
                          fontSize: _design == LauncherDesign.serene ? 16 : 15,
                          fontWeight: _design == LauncherDesign.serene ? FontWeight.w400 : null,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search applications, files, bookmarks...',
                          hintStyle: TextStyle(color: onSurface.withAlpha(70)),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.only(
                            left: 0,
                            top: 6,
                            bottom: 6,
                            right: _infoText != null ? 120 : 8,
                          ),
                        ),
                        onChanged: _onSearchChanged,
                        onSubmitted: _onSubmitted,
                      ),
                      trailingBadge: _infoText != null ? _buildInfoBadge(accent, onSurface) : null,
                      isSearching: _isSearching,
                    ),
                    // Results area
                    Material(
                      type: MaterialType.transparency,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 260, maxHeight: 320),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            if (!hasInput && _results.isNotEmpty)
                              _design.buildSectionHeader(label: 'Results', accent: accent),
                            if (Boxes.searchFolders.isEmpty &&
                                (_searchMode == LauncherSearchMode.filesOnly ||
                                    _searchMode == LauncherSearchMode.mixed))
                              Expanded(
                                child: Center(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 40),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        Icon(Icons.folder_off_rounded, size: 48, color: accent.withAlpha(40)),
                                        const SizedBox(height: 16),
                                        Text(
                                          'No Search Folders Configured',
                                          textAlign: TextAlign.center,
                                          style: theme.textTheme.titleMedium?.copyWith(
                                            color: onSurface.withAlpha(180),
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Add folders in Settings -> Quickmenu -> Launcher to start searching files.',
                                          textAlign: TextAlign.center,
                                          style: theme.textTheme.bodyMedium?.copyWith(
                                            color: onSurface.withAlpha(100),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
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
                                          return ListView.builder(
                                            controller: _scrollController,
                                            shrinkWrap: true,
                                            itemCount: _results.length,
                                            itemBuilder: (BuildContext context, int index) {
                                              final LauncherSearchResultItem result = _results[index];
                                              final bool isSelected = index == activeIndex;
                                              late final Widget resultWidget;
                                              if (result.isShortcut) {
                                                resultWidget = _buildShortcutResult(context, theme, result.shortcut!,
                                                    index, isSelected, isRepeatingKey);
                                              } else if (result.isFile) {
                                                resultWidget = _buildFileResult(context, theme, result.entity!,
                                                    result.nodeId, index, isSelected, isRepeatingKey);
                                              } else if (result.isApp) {
                                                resultWidget = _buildAppResult(context, theme, result.appResult!,
                                                    result.nodeId, index, isSelected, isRepeatingKey);
                                              } else if (result.isWindow) {
                                                resultWidget = _buildWindowResult(
                                                    context, theme, result.window!, index, isSelected, isRepeatingKey);
                                              } else if (result.isBookmark) {
                                                resultWidget = _buildBookmarkResult(context, theme,
                                                    result.bookmarkResult!, index, isSelected, isRepeatingKey);
                                              } else if (result.isNotion) {
                                                resultWidget = _buildNotionResult(context, theme, result.notionResult!,
                                                    index, isSelected, isRepeatingKey);
                                              } else if (result.isInfo) {
                                                resultWidget = _buildInfoResult(context, theme, result.infoResult!,
                                                    index, isSelected, isRepeatingKey);
                                              } else {
                                                resultWidget = _buildQuickActionResult(context, theme,
                                                    result.quickAction!, index, isSelected, isRepeatingKey);
                                              }
                                              return KeyedSubtree(
                                                key: _resultKeys[_resultKeyId(result, index)],
                                                child: MouseRegion(
                                                  onHover: (PointerHoverEvent event) =>
                                                      _selectResultFromPointerHover(event, index),
                                                  child: Stack(
                                                    alignment: Alignment.centerRight,
                                                    children: <Widget>[
                                                      resultWidget,
                                                    ],
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
                ),
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
    final Color accent = userSettings.themeColors.accentColor;
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
    final Color accent = userSettings.themeColors.accentColor;
    return _design == LauncherDesign.serene
        ? SereneBookmarkSearchListItem(
            result: result,
            isSelected: isSelected,
            isRepeating: isRepeatingKey,
            accent: accent,
            onSurface: theme.colorScheme.onSurface,
            onTap: () => _openBookmarkResult(result),
            onHover: () => _selectResultFromMouse(index))
        : BookmarkSearchListItem(
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
    final Color accent = userSettings.themeColors.accentColor;
    return _design == LauncherDesign.serene
        ? SereneLauncherFileListItem(
            entity: entity,
            isSelected: isSelected,
            isRepeating: isRepeatingKey,
            accent: accent,
            onSurface: theme.colorScheme.onSurface,
            onTap: () => _openFile(entity.path, nodeId: nodeId),
            onHover: () => _selectResultFromMouse(index))
        : LauncherListItem(
            entity: entity,
            isSelected: isSelected,
            isRepeating: isRepeatingKey,
            accent: accent,
            onSurface: theme.colorScheme.onSurface,
            isInHistory: false, // History removed
            onTap: () => _openFile(entity.path, nodeId: nodeId),
            onHover: () => _selectResultFromMouse(index),
            onRemoveFromHistory: () {}, // No-op
          );
  }

  Widget _buildAppResult(BuildContext context, ThemeData theme, LauncherAppResult app, int? nodeId, int index,
      bool isSelected, bool isRepeatingKey) {
    final Color accent = userSettings.themeColors.accentColor;
    return _design == LauncherDesign.serene
        ? SereneAppListItem(
            app: app,
            isSelected: isSelected,
            isRepeating: isRepeatingKey,
            accent: accent,
            onSurface: theme.colorScheme.onSurface,
            onTap: () => _openAppResult(app, nodeId: nodeId),
            onHover: () => _selectResultFromMouse(index))
        : LauncherAppListItem(
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
    final Color accent = userSettings.themeColors.accentColor;
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

  Widget _buildInfoResult(BuildContext context, ThemeData theme, LauncherInfoResult result, int index, bool isSelected,
      bool isRepeatingKey) {
    final Color accent = userSettings.themeColors.accentColor;
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
    final GlobalKey actionKey = _quickActionKeys.putIfAbsent(quickAction.id, () => GlobalKey());
    final Color accent = userSettings.themeColors.accentColor;
    final bool showSplash = _quickActionSplashId == quickAction.id;

    return MouseRegion(
      onHover: (PointerHoverEvent event) => _selectResultFromPointerHover(event, index),
      child: AnimatedContainer(
        duration: Duration(milliseconds: isRepeatingKey ? 50 : 200),
        curve: isRepeatingKey ? Curves.linear : Curves.easeOutCubic,
        key: ValueKey<String>(quickAction.id),
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
    final Color accent = userSettings.themeColors.accentColor;
    return _design == LauncherDesign.serene
        ? SereneWindowSearchListItem(
            window: window,
            isSelected: isSelected,
            isRepeating: isRepeatingKey,
            accent: accent,
            onSurface: theme.colorScheme.onSurface,
            onTap: () => _openWindow(window),
            onHover: () => _selectResultFromMouse(index))
        : WindowSearchListItem(
            window: window,
            isSelected: isSelected,
            isRepeating: isRepeatingKey,
            accent: accent,
            onSurface: theme.colorScheme.onSurface,
            onTap: () => _openWindow(window),
            onHover: () => _selectResultFromMouse(index),
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
