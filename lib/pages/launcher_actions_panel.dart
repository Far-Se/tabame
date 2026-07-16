import 'dart:async';
import 'dart:io';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:tabamewin32/tabamewin32.dart';
// tabamewin32 import removed - shell context menu now uses win32 5.x directly.
// See win32_context_menu_bridge.dart.

import '../models/classes/boxes/quick_menu_box.dart';
import '../models/globals.dart';
import '../models/classes/saved_maps.dart';
import '../models/settings.dart';
import '../models/win32/win32.dart';
import '../models/win32/win_utils.dart';
import '../models/win32/window.dart';
import '../widgets/itzy/quickmenu/button_notion.dart';
import '../widgets/itzy/quickmenu/button_obsidian.dart';
import '../widgets/itzy/quickmenu/button_quickactions.dart';
import '../widgets/itzy/quickmenu/button_steam.dart';
import 'launcher/launcher_design.dart';
import 'launcher/launcher_design_builder.dart';
import 'launcher/launcher_modal_theme.dart';
import 'launcher/result/result_item_bookmark.dart';
import 'launcher/result/result_row.dart';
import 'launcher_search_models.dart';

part 'launcher/services/launcher_actions_service.dart';

class ActionsPanelScaffold extends StatefulWidget {
  const ActionsPanelScaffold({required this.item});
  final LauncherSearchResultItem item;

  @override
  State<ActionsPanelScaffold> createState() => _ActionsPanelScaffoldState();
}

class _ActionsPanelScaffoldState extends State<ActionsPanelScaffold> {
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  int _activeIndex = 0;
  bool _loading = true;
  List<LauncherAction> _actions = <LauncherAction>[];
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchControllerFocus = FocusNode();

  List<LauncherAction> _filteredActions = <LauncherAction>[];
  String _query = '';

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
    unawaited(_loadActions());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchControllerFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _searchControllerFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _filterActions(String query) {
    _query = query.trim().toLowerCase();

    // No filter = show everything
    if (_query.isEmpty) {
      _filteredActions = List<LauncherAction>.from(_actions);

      if (_activeIndex >= _filteredActions.length) {
        _activeIndex = _filteredActions.isEmpty ? 0 : _filteredActions.length - 1;
      }

      setState(() {});
      return;
    }

    final List<LauncherAction> filtered = <LauncherAction>[];

    for (final LauncherAction action in _actions) {
      // Skip separators while searching
      if (action.isSeparator) continue;

      final String label = action.label.toLowerCase();
      final String subtitle = (action.subtitle ?? '').toLowerCase();

      final bool matches = label.contains(_query) || subtitle.contains(_query);

      if (matches) {
        filtered.add(action);
      }
    }

    _filteredActions = filtered;

    if (_activeIndex >= _filteredActions.length) {
      _activeIndex = _filteredActions.isEmpty ? 0 : _filteredActions.length - 1;
    }

    setState(() {});
  }

  Future<void> _loadActions() async {
    final List<LauncherAction> actions = await LauncherActionsBuilder.build(context, widget.item);
    if (!mounted) return;
    setState(() {
      _actions = actions;
      _filteredActions = List<LauncherAction>.from(actions);
      _loading = false;
    });
  }
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape ||
        (event.logicalKey == LogicalKeyboardKey.keyK && HardwareKeyboard.instance.isControlPressed)) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        if (_activeIndex < _filteredActions.length - 1) _activeIndex++;
      });
      _scrollToActive();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        if (_activeIndex > 0) _activeIndex--;
      });
      _scrollToActive();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _execute(_activeIndex);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _scrollToActive() {
    if (!_scrollController.hasClients || _filteredActions.isEmpty) return;

    const double regularItemH = 48.0;
    const double separatorH = 25.0;

    // 1. Calculate the exact top boundary of the active item
    double targetTop = 0.0;
    for (int i = 0; i < _activeIndex; i++) {
      if (_filteredActions[i].isSeparator) {
        targetTop += separatorH;
      } else {
        targetTop += regularItemH;
      }
    }

    // 2. Determine the height of the current active item itself
    final double activeItemH = _filteredActions[_activeIndex].isSeparator ? separatorH : regularItemH;

    // 3. Calculate where the item's middle point sits in the list
    final double itemCenter = targetTop + (activeItemH / 2);

    // 4. Determine the viewport metrics
    final double viewportH = _scrollController.position.viewportDimension;
    final double maxScroll = _scrollController.position.maxScrollExtent;

    // 5. Center the item by subtracting half of the viewport height
    double idealOffset = itemCenter - (viewportH / 2);

    // 6. Clamp the offset so it stays within valid scrollable boundaries
    idealOffset = idealOffset.clamp(0.0, maxScroll);

    // 7. Smoothly glide to the centered target
    _scrollController.animateTo(
      idealOffset,
      duration: const Duration(milliseconds: 50), // Slightly prolonged for a smoother glide effect
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _execute(int index) async {
    if (index < 0 || index >= _filteredActions.length) return;

    final LauncherAction action = _filteredActions[index];

    if (!action.keepPanelOpen) {
      if (mounted) Navigator.of(context).pop();
    }

    await action.onExecute(context);
    if (!kDebugMode) QuickMenuFunctions.hideQuickMenu();
  }

  @override
  Widget build(BuildContext context) {
    final LauncherModalTokens tokens = LauncherModalTokens.of(context);
    final LauncherThemeData launcherTheme = LauncherThemeData(design: tokens.design);
    final OutlineInputBorder searchBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(tokens.controlRadius),
      borderSide: tokens.outlinedControls ? BorderSide(color: tokens.accent.withAlpha(50)) : BorderSide.none,
    );

    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        // Tap outside the card , dismiss
        onTap: () => Navigator.of(context).pop(),
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: GestureDetector(
            // Swallow taps on the card so they don't propagate to the outer tap
            onTap: () {},
            child: Focus(
              focusNode: _focusNode,
              onKeyEvent: _onKey,
              child: LauncherModalFrame(
                tokens: tokens,
                width: 440,
                maxHeight: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _ActionsHeader(item: widget.item, tokens: tokens),
                    Divider(height: 1, thickness: 1, color: tokens.onSurface.withAlpha(20)),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                      child: SizedBox(
                        height: 38,
                        child: Focus(
                          onKeyEvent: (FocusNode node, KeyEvent event) {
                            if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                              return KeyEventResult.ignored;
                            }

                            if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                              setState(() {
                                if (_activeIndex < _filteredActions.length - 1) {
                                  _activeIndex++;
                                }
                              });

                              _scrollToActive();

                              return KeyEventResult.handled;
                            }

                            if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                              setState(() {
                                if (_activeIndex > 0) {
                                  _activeIndex--;
                                }
                              });

                              _scrollToActive();

                              return KeyEventResult.handled;
                            }

                            if (event.logicalKey == LogicalKeyboardKey.enter) {
                              _execute(_activeIndex);
                              return KeyEventResult.handled;
                            }

                            return KeyEventResult.ignored;
                          },
                          child: TextField(
                            controller: _searchController,
                            autofocus: true,
                            focusNode: _searchControllerFocus,
                            onChanged: _filterActions,
                            style: tokens.text(fontSize: Design.baseFontSize + 3, color: tokens.onSurface),
                            decoration: InputDecoration(
                              hintText: 'Search actions...',
                              hintStyle: tokens.text(
                                fontSize: Design.baseFontSize + 3,
                                color: tokens.onSurface.withAlpha(70),
                              ),
                              prefixIcon: Icon(
                                launcherTheme.searchIcon,
                                size: 18,
                                color: launcherTheme.searchIconUsesOnSurface
                                    ? tokens.onSurface.withAlpha(120)
                                    : tokens.accent.withAlpha(200),
                              ),
                              suffixIcon: _query.isEmpty
                                  ? null
                                  : IconButton(
                                      splashRadius: 16,
                                      icon: Icon(Icons.close_rounded, size: 16, color: tokens.onSurface.withAlpha(140)),
                                      onPressed: () {
                                        _searchController.clear();
                                        _filterActions('');
                                      },
                                    ),
                              isDense: true,
                              filled: true,
                              fillColor: tokens.onSurface.withAlpha(10),
                              contentPadding: const EdgeInsets.symmetric(vertical: 0),
                              border: searchBorder,
                              enabledBorder: searchBorder,
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(tokens.controlRadius),
                                borderSide: tokens.outlinedControls
                                    ? BorderSide(color: tokens.accent.withAlpha(120))
                                    : BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_loading)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: tokens.accent),
                          ),
                        ),
                      )
                    else if (_actions.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No actions available',
                          style: tokens.text(fontSize: Design.baseFontSize + 2, color: tokens.dim),
                        ),
                      )
                    else
                      Flexible(
                        child: _ActionsList(
                          actions: _filteredActions,
                          activeIndex: _activeIndex,
                          scrollController: _scrollController,
                          onHover: (int i) => setState(() => _activeIndex = i),
                          onTap: _execute,
                          tokens: tokens,
                        ),
                      ),
                    LauncherModalFooter(
                      tokens: tokens,
                      hints: const <(String, String)>[('↑↓', 'navigate'), ('↵', 'run'), ('Esc', 'close')],
                      trailing: ('Ctrl+K', 'toggle'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Header - shows what item we're acting on
// =============================================================================

class _ActionsHeader extends StatelessWidget {
  const _ActionsHeader({
    required this.item,
    required this.tokens,
  });

  final LauncherSearchResultItem item;
  final LauncherModalTokens tokens;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, String title, String subtitle) = _resolveIdentity();
    return LauncherModalHeader(
      tokens: tokens,
      icon: Icon(icon, size: 18, color: tokens.accent),
      title: title,
      subtitle: subtitle,
      badgeLabel: 'Actions',
    );
  }

  (IconData, String, String) _resolveIdentity() {
    if (item.isFile) {
      final bool isDir = item.entity is Directory;
      return (
        isDir ? Icons.folder_rounded : Icons.insert_drive_file_rounded,
        p.basename(item.entity!.path),
        item.entity!.path,
      );
    }
    if (item.isApp) {
      return (
        Icons.apps_rounded,
        item.appResult!.name,
        item.appResult!.subtitle,
      );
    }
    if (item.isWindow) {
      return (
        Icons.window_rounded,
        item.window!.title,
        item.window!.process.exe,
      );
    }
    if (item.isBookmark) {
      final BookmarkSearchResult bm = item.bookmarkResult!;
      switch (bm.kind) {
        case BookmarkResultKind.cliBook:
          return (Icons.terminal_rounded, bm.cli!.key, bm.cli!.value);
        case BookmarkResultKind.bookmark:
          return (Icons.bookmark_rounded, bm.bookmark!.title, bm.bookmark!.stringToExecute);
        case BookmarkResultKind.appItem:
          return (Icons.apps_rounded, bm.app!.name, bm.app!.path);
      }
    }
    if (item.isNotion) {
      return (Icons.description_outlined, item.notionResult!.title, 'Notion');
    }
    if (item.isObsidian) {
      final ObsidianNote note = item.obsidianResult!;
      return (
        Icons.menu_book_rounded,
        note.name,
        note.folder.isEmpty ? 'Obsidian · vault root' : 'Obsidian · ${note.folder}',
      );
    }
    if (item.quickAction != null) {
      return (Icons.bolt_rounded, item.quickAction!.title, 'Quick Action');
    }
    return (Icons.help_outline_rounded, 'Unknown', '');
  }
}

// =============================================================================
// Actions list
// =============================================================================

class _ActionsList extends StatelessWidget {
  const _ActionsList({
    required this.actions,
    required this.activeIndex,
    required this.scrollController,
    required this.onHover,
    required this.onTap,
    required this.tokens,
  });

  final List<LauncherAction> actions;
  final int activeIndex;
  final ScrollController scrollController;
  final ValueChanged<int> onHover;
  final ValueChanged<int> onTap;
  final LauncherModalTokens tokens;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollController,
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: actions.length,
      itemBuilder: (BuildContext ctx, int i) {
        final LauncherAction action = actions[i];

        if (action.isSeparator) {
          // Labeled separators speak in the active design's section-header
          // voice (dimension lines on Blueprint, `::` rules on Terminal, …).
          if (action.label.isNotEmpty) {
            return tokens.design.buildSectionHeader(label: action.label, accent: tokens.accent);
          }
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Container(height: 1, color: tokens.onSurface.withAlpha(20)),
          );
        }

        return _ActionTile(
          action: action,
          isActive: i == activeIndex,
          tokens: tokens,
          onHover: () => onHover(i),
          onTap: () => onTap(i),
        );
      },
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.action,
    required this.isActive,
    required this.tokens,
    required this.onHover,
    required this.onTap,
  });

  final LauncherAction action;
  final bool isActive;
  final LauncherModalTokens tokens;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool destructive = action.isDestructive;
    final Widget icon = SizedBox(
      width: 16,
      height: 16,
      child: action.iconImage != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.memory(action.iconImage!, fit: BoxFit.cover),
            )
          : Icon(
              action.icon ?? Icons.play_arrow_rounded,
              size: 16,
              color: destructive ? Colors.redAccent : tokens.accent,
            ),
    );

    final Widget? kbdBadge = action.kbdHint == null
        ? null
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: tokens.onSurface.withAlpha(12),
              borderRadius: BorderRadius.circular(tokens.design == LauncherDesign.blueprint ? 2 : 4),
              border: tokens.outlinedControls ? Border.all(color: tokens.accent.withAlpha(60)) : null,
            ),
            child: Text(
              action.kbdHint!,
              style: tokens.text(fontSize: Design.baseFontSize, color: tokens.onSurface.withAlpha(120)),
            ),
          );

    final bool hasSubtitle = action.subtitle != null && action.subtitle!.isNotEmpty;
    final Color titleColor = destructive
        ? Colors.redAccent
        : isActive && (tokens.design == LauncherDesign.terminal || tokens.design == LauncherDesign.orbit)
            ? tokens.accent
            : isActive
                ? tokens.onSurface
                : tokens.onSurface.withAlpha(220);

    // The row shell (icon nest, selection treatment, motion) comes from
    // LauncherResultRow, so the tile matches the launcher's result rows; only
    // the text column is custom so subtitle-less and destructive actions
    // render correctly.
    return LauncherResultRow(
      isSelected: isActive,
      isRepeating: false,
      accent: tokens.accent,
      onSurface: tokens.onSurface,
      onTap: onTap,
      onHover: onHover,
      icon: icon,
      badge: kbdBadge,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            action.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tokens.text(
              fontSize: Design.baseFontSize + 1.5,
              fontWeight: FontWeight.w600,
              color: titleColor,
              height: 1.25,
            ),
          ),
          if (hasSubtitle)
            Text(
              action.subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tokens.text(
                fontSize: Design.baseFontSize - 0.5,
                color: destructive
                    ? Colors.redAccent.withAlpha(150)
                    : isActive
                        ? tokens.onSurface.withAlpha(160)
                        : tokens.dim,
                height: 1.2,
              ),
            ),
        ],
      ),
    );
  }
}

// =============================================================================
// LauncherAction data class
// =============================================================================

typedef LauncherActionCallback = FutureOr<void> Function(BuildContext context);

class LauncherAction {
  const LauncherAction({
    required this.label,
    required this.onExecute,
    this.icon,
    this.iconImage,
    this.subtitle,
    this.kbdHint,
    this.isDestructive = false,
    this.keepPanelOpen = false,
  }) : isSeparator = false;

  const LauncherAction.separator({this.label = ''})
      : icon = null,
        iconImage = null,
        subtitle = null,
        kbdHint = null,
        isDestructive = false,
        keepPanelOpen = false,
        isSeparator = true,
        onExecute = _noop;

  static FutureOr<void> _noop(BuildContext context) {}

  final String label;
  final IconData? icon;
  final Uint8List? iconImage;
  final String? subtitle;
  final String? kbdHint;
  final bool isDestructive;
  final bool keepPanelOpen;
  final bool isSeparator;
  final LauncherActionCallback onExecute;
}

// =============================================================================
// CLI run-sheet (shown inside the panel, panel stays open)
// =============================================================================

class _CliRunSheet extends StatefulWidget {
  const _CliRunSheet({required this.cliItem});
  final CliBookItem cliItem;

  @override
  State<_CliRunSheet> createState() => _CliRunSheetState();
}

class _CliRunSheetState extends State<_CliRunSheet> {
  final Map<String, TextEditingController> _varControllers = <String, TextEditingController>{};
  late List<String> _variables;
  String _workingDirectory = '';

  @override
  void initState() {
    super.initState();
    _variables = _extractVars(widget.cliItem.value);
    for (final String v in _variables) {
      _varControllers[v] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final TextEditingController c in _varControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  static List<String> _extractVars(String cmd) {
    final Set<String> seen = <String>{};
    final List<String> result = <String>[];
    for (final RegExpMatch m in RegExp(r'\$\{([^}]+)\}').allMatches(cmd)) {
      final String v = (m.group(1) ?? '').trim();
      if (v.isNotEmpty && seen.add(v)) result.add(v);
    }
    return result;
  }

  String _resolve() => widget.cliItem.value.replaceAllMapped(
        RegExp(r'\$\{([^}]+)\}'),
        (Match m) {
          final String v = (m.group(1) ?? '').trim();
          return _varControllers[v]?.text ?? v;
        },
      );

  Future<void> _pickFolder() async {
    final DirectoryPicker picker = DirectoryPicker()..title = 'Select Working Directory';
    final Directory? dir = picker.getDirectory();
    if (dir == null || dir.path.isEmpty) return;
    if (mounted) setState(() => _workingDirectory = dir.path);
  }

  void _run() {
    final String cmd = _resolve();
    if (cmd.trim().isEmpty) return;
    WinUtils.runPowerShellDetachedVisible(
      cmd,
      workingDirectory: _workingDirectory.isNotEmpty ? _workingDirectory : null,
      keepOpen: true,
    );
    Navigator.of(context).pop(); // close sheet
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: _resolve()));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = Design.accent;
    final Color onSurface = theme.colorScheme.onSurface;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Command preview
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: accent.withAlpha(12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                widget.cliItem.value,
                style: TextStyle(
                  fontSize: Design.baseFontSize + 2,
                  fontFamily: 'monospace',
                  color: onSurface.withAlpha(200),
                ),
              ),
            ),
            // Variable fields
            if (_variables.isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              Text('Parameters', style: theme.textTheme.labelSmall?.copyWith(color: onSurface.withAlpha(120))),
              const SizedBox(height: 8),
              for (final String v in _variables) ...<Widget>[
                Text(v, style: theme.textTheme.bodySmall?.copyWith(color: onSurface.withAlpha(140))),
                const SizedBox(height: 4),
                TextField(
                  controller: _varControllers[v],
                  style: TextStyle(fontSize: 13, color: onSurface),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Value for \$$v',
                    hintStyle: TextStyle(fontSize: Design.baseFontSize + 2, color: onSurface.withAlpha(80)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: onSurface.withAlpha(40)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
            // Working directory
            const SizedBox(height: 4),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _pickFolder,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: onSurface.withAlpha(28)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.folder_open_rounded, size: 15, color: accent.withAlpha(160)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _workingDirectory.isEmpty ? 'Working directory (optional)' : _workingDirectory,
                        style: TextStyle(
                          fontSize: Design.baseFontSize + 2,
                          color: _workingDirectory.isEmpty ? onSurface.withAlpha(80) : onSurface.withAlpha(200),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_workingDirectory.isNotEmpty)
                      InkWell(
                        onTap: () => setState(() => _workingDirectory = ''),
                        child: Icon(Icons.close_rounded, size: 14, color: onSurface.withAlpha(100)),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Action buttons
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.content_copy_rounded, size: 14),
                    label: const Text('Copy'),
                    onPressed: _copyToClipboard,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.play_arrow_rounded, size: 14),
                    label: const Text('Run'),
                    onPressed: _run,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// LauncherActionsBuilder - the factory
// =============================================================================

class _ParametersDialog extends StatelessWidget {
  const _ParametersDialog({
    required this.title,
    required this.controller,
  });

  final String title;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final Color accent = Design.accent;

    return AlertDialog(
      backgroundColor: Colors.transparent,
      title: Text(title, style: const TextStyle(fontSize: 14)),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
        decoration: InputDecoration(
          hintText: '--flag value',
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: accent.withAlpha(80)),
          ),
        ),
        onSubmitted: (String v) => Navigator.of(context).pop(v),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop<String>(null),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop<String>(controller.text),
          style: ElevatedButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.white,
          ),
          child: const Text('Run'),
        ),
      ],
    );
  }
}

class _AppendNoteDialog extends StatelessWidget {
  const _AppendNoteDialog({
    required this.title,
    required this.controller,
  });

  final String title;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final Color accent = Design.accent;

    return AlertDialog(
      backgroundColor: Colors.transparent,
      title: Text(title, style: const TextStyle(fontSize: 14)),
      content: SizedBox(
        width: 360,
        child: TextField(
          controller: controller,
          autofocus: true,
          minLines: 4,
          maxLines: 10,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Text to add to the end of the note...',
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: accent.withAlpha(80)),
            ),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop<String>(null),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop<String>(controller.text),
          style: ElevatedButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.white,
          ),
          child: const Text('Append'),
        ),
      ],
    );
  }
}
