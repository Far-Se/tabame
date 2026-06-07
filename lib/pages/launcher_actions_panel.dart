// launcher_actions_panel.dart
//
// The "Actions" panel — triggered with Ctrl+K on any selected launcher result.
//
// ─────────────────────────────────────────────────────────────────────────────
// ARCHITECTURE OVERVIEW
// ─────────────────────────────────────────────────────────────────────────────
//
//  LauncherActionsPanel          ← top-level stateful widget, pushed via Navigator
//  ├── _ActionsHeader            ← shows result identity (icon, name, path)
//  ├── _ActionsList              ← scrollable list of LauncherAction items
//  │   └── _ActionTile           ← single tappable row (icon, label, kbd hint)
//  └── _CliRunSheet              ← modal bottom-sheet for CLI "Run with params"
//
//  LauncherActionsBuilder        ← static factory: given a LauncherSearchResultItem
//                                  returns the correct List<LauncherAction>
//
//  Win32ContextMenuBridge        ← thin wrapper around tabamewin32 shell context menu
//
// ─────────────────────────────────────────────────────────────────────────────
// HOW TO WIRE INTO launcher.dart
// ─────────────────────────────────────────────────────────────────────────────
//
//  1. In _onKeyEvent, add a handler for Ctrl+K *before* the arrow-key block:
//
//       if (event is KeyDownEvent &&
//           event.logicalKey == LogicalKeyboardKey.keyK &&
//           HardwareKeyboard.instance.isControlPressed) {
//         _openActionsForActiveResult();
//         return KeyEventResult.handled;
//       }
//
//  2. Add the helper method to LauncherState:
//
//       void _openActionsForActiveResult() {
//         if (_results.isEmpty) return;
//         final int idx = _activeIndexNotifier.value.clamp(0, _results.length - 1);
//         final LauncherSearchResultItem item = _results[idx];
//         if (item.isShortcut || item.isInfo) return;
//         LauncherActionsPanel.show(context, item);
//       }
//
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:io';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:tabamewin32/tabamewin32.dart';
import 'package:window_manager/window_manager.dart';
// tabamewin32 import removed — shell context menu now uses win32 5.x directly.
// See win32_context_menu_bridge.dart.

import '../models/classes/boxes/quick_menu_box.dart';
import '../models/globals.dart';
import '../models/classes/saved_maps.dart';
import '../models/settings.dart';
import '../models/win32/win32.dart';
import '../models/win32/win_utils.dart';
import '../models/win32/window.dart';
import '../widgets/itzy/quickmenu/button_notion.dart';
import '../widgets/itzy/quickmenu/button_quickactions.dart';
import 'launcher/result/result_item_bookmark.dart';
import 'launcher_search_models.dart';

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

    // No filter → show everything
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
  // Inside _ActionsPanelScaffoldState:

  bool _isKeyboardNavigating = false; // <-- Add this flag

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
        _isKeyboardNavigating = true; // <-- Lock out mouse hover
        if (_activeIndex < _filteredActions.length - 1) _activeIndex++;
      });
      _scrollToActive();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _isKeyboardNavigating = true; // <-- Lock out mouse hover
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
    final ThemeData theme = Theme.of(context);
    final Color accent = userSettings.themeColors.accent;
    final Color surface = theme.colorScheme.surface;

    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        // Tap outside the card → dismiss
        onTap: () => Navigator.of(context).pop(),
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: GestureDetector(
            // Swallow taps on the card so they don't propagate to the outer tap
            onTap: () {},
            child: Focus(
              focusNode: _focusNode,
              onKeyEvent: _onKey,
              child: Container(
                width: 440,
                constraints: const BoxConstraints(maxHeight: 520),
                margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: accent.withAlpha(40)),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withAlpha(60),
                      blurRadius: 28,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _ActionsHeader(item: widget.item, accent: accent, theme: theme),
                    const Divider(height: 1, thickness: 1),
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
                              _isKeyboardNavigating = true;
                              setState(() {
                                if (_activeIndex < _filteredActions.length - 1) {
                                  _activeIndex++;
                                }
                              });

                              _scrollToActive();

                              return KeyEventResult.handled;
                            }

                            if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                              _isKeyboardNavigating = true;
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
                            style: theme.textTheme.bodyMedium,
                            decoration: InputDecoration(
                              hintText: 'Search actions...',
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                size: 18,
                                color: theme.colorScheme.onSurface.withAlpha(120),
                              ),
                              suffixIcon: _query.isEmpty
                                  ? null
                                  : IconButton(
                                      splashRadius: 16,
                                      icon: const Icon(Icons.close_rounded, size: 16),
                                      onPressed: () {
                                        _searchController.clear();
                                        _filterActions('');
                                      },
                                    ),
                              isDense: true,
                              filled: true,
                              fillColor: theme.colorScheme.onSurface.withAlpha(10),
                              contentPadding: const EdgeInsets.symmetric(vertical: 0),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    else if (_actions.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No actions available',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withAlpha(120),
                          ),
                        ),
                      )
                    else
                      // Inside ActionsPanelScaffold's build() method:

                      Flexible(
                        child: Material(
                          type: MaterialType.transparency,
                          child: _ActionsList(
                            actions: _filteredActions,
                            activeIndex: _activeIndex,
                            scrollController: _scrollController,
                            // Only allow hover updates if we aren't mid-keyboard-navigation
                            onHover: (int i) {
                              if (!_isKeyboardNavigating) {
                                setState(() => _activeIndex = i);
                              }
                            },
                            onTap: _execute,
                            // Re-enable mouse tracking as soon as the user physically moves their pointer
                            onMouseMove: () {
                              if (_isKeyboardNavigating) {
                                setState(() => _isKeyboardNavigating = false);
                              }
                            },
                            accent: accent,
                            theme: theme,
                          ),
                        ),
                      ),
                    _ActionsPanelFooter(theme: theme, accent: accent),
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

// ─────────────────────────────────────────────────────────────────────────────
// Header — shows what item we're acting on
// ─────────────────────────────────────────────────────────────────────────────

class _ActionsHeader extends StatelessWidget {
  const _ActionsHeader({
    required this.item,
    required this.accent,
    required this.theme,
  });

  final LauncherSearchResultItem item;
  final Color accent;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final Color onSurface = theme.colorScheme.onSurface;
    final (IconData icon, String title, String subtitle) = _resolveIdentity();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: <Widget>[
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (DragStartDetails details) {
              windowManager.startDragging();
            },
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withAlpha(28),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: accent),
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
                    fontWeight: FontWeight.w600,
                    color: onSurface,
                  ),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: onSurface.withAlpha(120),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: accent.withAlpha(20),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.keyboard_rounded, size: 11, color: accent.withAlpha(180)),
                const SizedBox(width: 3),
                Text(
                  'Actions',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: accent.withAlpha(180),
                    fontWeight: FontWeight.w600,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
    if (item.quickAction != null) {
      return (Icons.bolt_rounded, item.quickAction!.title, 'Quick Action');
    }
    return (Icons.help_outline_rounded, 'Unknown', '');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Footer — keyboard hints
// ─────────────────────────────────────────────────────────────────────────────

class _ActionsPanelFooter extends StatelessWidget {
  const _ActionsPanelFooter({required this.theme, required this.accent});
  final ThemeData theme;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final Color onSurface = theme.colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: onSurface.withAlpha(16))),
      ),
      child: Row(
        children: <Widget>[
          _KbdHint(label: '↑↓', caption: 'navigate', onSurface: onSurface),
          const SizedBox(width: 16),
          _KbdHint(label: '↵', caption: 'run', onSurface: onSurface),
          const SizedBox(width: 16),
          _KbdHint(label: 'Esc', caption: 'close', onSurface: onSurface),
          const Spacer(),
          _KbdHint(label: 'Ctrl+K', caption: 'toggle', onSurface: onSurface),
        ],
      ),
    );
  }
}

class _KbdHint extends StatelessWidget {
  const _KbdHint({
    required this.label,
    required this.caption,
    required this.onSurface,
  });
  final String label;
  final String caption;
  final Color onSurface;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: onSurface.withAlpha(14),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: onSurface.withAlpha(28)),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: onSurface.withAlpha(160),
              fontFamily: 'monospace',
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          caption,
          style: TextStyle(fontSize: 10, color: onSurface.withAlpha(80)),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Actions list
// ─────────────────────────────────────────────────────────────────────────────
// Update your _ActionsList widget to look like this:

class _ActionsList extends StatelessWidget {
  const _ActionsList({
    required this.actions,
    required this.activeIndex,
    required this.scrollController,
    required this.onHover,
    required this.onTap,
    required this.accent,
    required this.theme,
    required this.onMouseMove, // <-- Add this callback
  });

  final List<LauncherAction> actions;
  final int activeIndex;
  final ScrollController scrollController;
  final ValueChanged<int> onHover;
  final ValueChanged<int> onTap;
  final VoidCallback onMouseMove; // <-- Add this callback
  final Color accent;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      // Triggers ONLY when the physical mouse moves over this region
      onHover: (_) => onMouseMove(),
      child: ListView.builder(
        controller: scrollController,
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: actions.length,
        itemBuilder: (BuildContext ctx, int i) {
          final LauncherAction action = actions[i];
          final bool isActive = i == activeIndex;

          if (action.isSeparator) {
            // ... (keep separator code exactly as it is)
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: <Widget>[
                  Expanded(child: Divider(height: 1, color: theme.colorScheme.onSurface.withAlpha(20))),
                  if (action.label.isNotEmpty) ...<Widget>[
                    const SizedBox(width: 8),
                    Text(
                      action.label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface.withAlpha(60),
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Divider(height: 1, color: theme.colorScheme.onSurface.withAlpha(20))),
                  ],
                ],
              ),
            );
          }

          return _ActionTile(
            action: action,
            isActive: isActive,
            accent: accent,
            theme: theme,
            onHover: () => onHover(i),
            onTap: () => onTap(i),
          );
        },
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.action,
    required this.isActive,
    required this.accent,
    required this.theme,
    required this.onHover,
    required this.onTap,
  });

  final LauncherAction action;
  final bool isActive;
  final Color accent;
  final ThemeData theme;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color onSurface = theme.colorScheme.onSurface;
    final Color tileColor = isActive ? theme.highlightColor : Colors.transparent;
    final Color iconColor = action.isDestructive ? Colors.redAccent : accent;

    return MouseRegion(
      onEnter: (_) => onHover(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: tileColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: <Widget>[
                // Icon or image
                SizedBox(
                  width: 16,
                  height: 16,
                  child: action.iconImage != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.memory(action.iconImage!, fit: BoxFit.cover),
                        )
                      : Icon(action.icon ?? Icons.play_arrow_rounded, size: 16, color: iconColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        action.label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: action.isDestructive ? Colors.redAccent : onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (action.subtitle != null && action.subtitle!.isNotEmpty)
                        Text(
                          action.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: onSurface.withAlpha(100),
                          ),
                        ),
                    ],
                  ),
                ),
                if (action.kbdHint != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: onSurface.withAlpha(12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      action.kbdHint!,
                      style: TextStyle(
                        fontSize: 10,
                        color: onSurface.withAlpha(100),
                        fontFamily: 'monospace',
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

// ─────────────────────────────────────────────────────────────────────────────
// LauncherAction data class
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// CLI run-sheet (shown inside the panel, panel stays open)
// ─────────────────────────────────────────────────────────────────────────────

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
    final Color accent = userSettings.themeColors.accent;
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
                  fontSize: 12,
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
                    hintStyle: TextStyle(fontSize: 12, color: onSurface.withAlpha(80)),
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
                          fontSize: 12,
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

// ─────────────────────────────────────────────────────────────────────────────
// LauncherActionsBuilder — the factory
// ─────────────────────────────────────────────────────────────────────────────

class LauncherActionsBuilder {
  static Future<List<LauncherAction>> build(
    BuildContext context,
    LauncherSearchResultItem item,
  ) async {
    if (item.isFile) {
      final bool isDir = item.entity is Directory;
      return isDir ? _buildFolderActions(item.entity!.path) : _buildFileActions(item.entity!.path);
    }
    if (item.isApp) return _buildAppActions(item.appResult!);
    if (item.isWindow) return _buildWindowActions(item.window!);
    if (item.isBookmark) return _buildBookmarkActions(context, item.bookmarkResult!);
    if (item.isNotion) return _buildNotionActions(item.notionResult!);
    if (item.quickAction != null) return _buildQuickActionActions(context, item.quickAction!);
    return <LauncherAction>[];
  }

  // ── Files ──────────────────────────────────────────────────────────────────

  static IconData _iconForVerb(String verb) {
    switch (verb.toLowerCase()) {
      case 'open':
        return Icons.open_in_new_rounded;
      case 'edit':
        return Icons.edit_rounded;
      case 'print':
        return Icons.print_rounded;
      case 'delete':
        return Icons.delete_outline_rounded;
      case 'rename':
        return Icons.drive_file_rename_outline_rounded;
      case 'properties':
        return Icons.info_outline_rounded;
      case 'cut':
        return Icons.content_cut_rounded;
      case 'copy':
        return Icons.content_copy_rounded;
      case 'paste':
        return Icons.content_paste_rounded;
      case 'runas':
        return Icons.shield_outlined;
      default:
        return Icons.arrow_forward_ios_rounded;
    }
  }

  static Future<List<LauncherAction>> _buildFileActions(String path) async {
    final List<LauncherAction> actions = <LauncherAction>[
      // ── Built-in primary actions ──
      LauncherAction(
        label: 'Open',
        icon: Icons.open_in_new_rounded,
        kbdHint: '↵',
        onExecute: (_) {
          WinUtils.open(path);
          _closeLauncher();
        },
      ),
      LauncherAction(
        label: 'Run as Administrator',
        icon: Icons.shield_outlined,
        subtitle: 'Elevated privileges',
        onExecute: (_) {
          WinUtils.runAsAdmin(path);
          _closeLauncher();
        },
      ),
      LauncherAction(
        label: 'Run with Parameters…',
        icon: Icons.tune_rounded,
        subtitle: 'Specify arguments before launching',
        keepPanelOpen: true,
        onExecute: (BuildContext ctx) async {
          final TextEditingController controller = TextEditingController();
          final String? args = await showDialog<String>(
            context: ctx,
            builder: (_) => _ParametersDialog(
              title: 'Run "${p.basename(path)}" with parameters',
              controller: controller,
            ),
          );
          controller.dispose();
          if (args == null) return;
          WinUtils.open(path, arguments: args);
          _closeLauncher();
        },
      ),
      LauncherAction(
        label: 'Open Containing Folder',
        icon: Icons.folder_open_rounded,
        onExecute: (_) {
          WinUtils.open('explorer.exe', arguments: '/select,"$path"', parseParamaters: true);
        },
      ),
      LauncherAction(
        label: 'Copy Path',
        icon: Icons.content_copy_rounded,
        onExecute: (_) => Clipboard.setData(ClipboardData(text: path)),
      ),
      LauncherAction(
        label: 'Copy File',
        icon: Icons.content_paste_go_outlined,
        onExecute: (_) => ClipboardExtension.copyFile(path),
      ),
      LauncherAction(
        label: 'Copy Filename',
        icon: Icons.title_rounded,
        subtitle: p.basename(path),
        onExecute: (_) => Clipboard.setData(ClipboardData(text: p.basename(path))),
      ),
      const LauncherAction.separator(label: 'Shell'),
    ];

    // ── Shell context-menu items ──
    final List<ShellMenuItem> shellActions = await ShellContextMenu.getMenuItems(path);
    final List<LauncherAction> newList = <LauncherAction>[];
    for (final ShellMenuItem action in shellActions) {
      if (<String>["Cut", "Copy"].contains(action.verb)) continue;
      newList.add(LauncherAction(
        label: action.label,
        icon: action.iconBytes == null ? _iconForVerb(action.label) : null,
        iconImage: action.iconBytes,
        onExecute: (_) => Win32.invokeShellMenuItem(path, Win32.hWnd, verb: action.verb, id: action.id),
      ));
    }
    actions.addAll(newList);

    if (shellActions.isEmpty) {
      // Graceful fallback when native bridge isn't available
      actions.addAll(<LauncherAction>[
        LauncherAction(
          label: 'Open with…',
          icon: Icons.open_with_rounded,
          onExecute: (_) {
            WinUtils.open('shell:AppsFolder', arguments: '', parseParamaters: false);
            // The standard "Open With" dialog via openwith.exe
            WinUtils.open('openwith.exe', arguments: '"$path"', parseParamaters: true);
          },
        ),
        LauncherAction(
          label: 'Show Properties',
          icon: Icons.info_outline_rounded,
          onExecute: (_) {
            WinUtils.open('properties', arguments: path, parseParamaters: true);
          },
        ),
      ]);
    }

    return actions;
  }

  // ── Folders ────────────────────────────────────────────────────────────────

  static Future<List<LauncherAction>> _buildFolderActions(String path) async {
    final List<LauncherAction> actions = <LauncherAction>[
      LauncherAction(
        label: 'Open in Explorer',
        icon: Icons.folder_open_rounded,
        kbdHint: '↵',
        onExecute: (_) {
          WinUtils.open(path);
          _closeLauncher();
        },
      ),
      LauncherAction(
        label: 'Open Terminal Here',
        icon: Icons.terminal_rounded,
        subtitle: 'Windows Terminal / PowerShell',
        onExecute: (_) {
          // Try wt.exe (Windows Terminal), fall back to PowerShell
          try {
            WinUtils.open('wt.exe', arguments: '-d "$path"', parseParamaters: true);
          } catch (_) {
            WinUtils.runPowerShellDetachedVisible('', workingDirectory: path, keepOpen: true);
          }
          _closeLauncher();
        },
      ),
      LauncherAction(
        label: 'Open CMD Here',
        icon: Icons.code_rounded,
        onExecute: (_) {
          WinUtils.open('cmd.exe', arguments: '/k cd /d "$path"', parseParamaters: true);
          _closeLauncher();
        },
      ),
      LauncherAction(
        label: 'Open PowerShell Here',
        icon: Icons.terminal_rounded,
        onExecute: (_) {
          WinUtils.open(
            'powershell.exe',
            arguments: '-NoExit -Command "Set-Location \'$path\'"',
            parseParamaters: true,
          );
          _closeLauncher();
        },
      ),
      LauncherAction(
        label: 'Copy Path',
        icon: Icons.content_copy_rounded,
        onExecute: (_) => Clipboard.setData(ClipboardData(text: path)),
      ),
      LauncherAction(
        label: 'Copy Folder',
        icon: Icons.content_paste_go_outlined,
        onExecute: (_) => ClipboardExtension.copyFolder(path),
      ),
      LauncherAction(
        label: 'Copy Folder Name',
        icon: Icons.title_rounded,
        subtitle: p.basename(path),
        onExecute: (_) => Clipboard.setData(ClipboardData(text: p.basename(path))),
      ),
      const LauncherAction.separator(label: 'Shell'),
    ];

    // ── Shell context-menu items ──
    // final List<LauncherAction> shellActions = await Win32ContextMenuBridge.getActionsForPath(path);
    // actions.addAll(shellActions);

    final List<ShellMenuItem> shellActions = await ShellContextMenu.getMenuItems(path);
    final List<LauncherAction> newList = <LauncherAction>[];
    for (final ShellMenuItem action in shellActions) {
      if (<String>["Cut", "Copy"].contains(action.label)) continue;
      newList.add(LauncherAction(
        label: action.label,
        icon: action.iconBytes == null ? _iconForVerb(action.label) : null,
        iconImage: action.iconBytes,
        onExecute: (_) => Win32.invokeShellMenuItem(path, Win32.hWnd, verb: action.verb, id: action.id),
      ));
    }
    actions.addAll(newList);
    if (shellActions.isEmpty) {
      actions.addAll(<LauncherAction>[
        LauncherAction(
          label: 'Show Properties',
          icon: Icons.info_outline_rounded,
          onExecute: (_) {
            WinUtils.open('properties', arguments: path, parseParamaters: true);
          },
        ),
      ]);
    }

    return actions;
  }

  // ── Apps ───────────────────────────────────────────────────────────────────

  static List<LauncherAction> _buildAppActions(LauncherAppResult app) {
    return <LauncherAction>[
      LauncherAction(
        label: 'Launch',
        icon: Icons.launch_rounded,
        kbdHint: '↵',
        onExecute: (_) {
          final String target = app.launchTarget;
          if (target.isNotEmpty) WinUtils.open(target, parseParamaters: false);
          _closeLauncher();
        },
      ),
      LauncherAction(
        label: 'Launch as Administrator',
        icon: Icons.shield_outlined,
        subtitle: 'Elevated privileges',
        onExecute: (_) {
          final String target = app.launchTarget;
          if (target.isNotEmpty) WinUtils.runAsAdmin(target);
          _closeLauncher();
        },
      ),
      LauncherAction(
        label: 'Copy App ID',
        icon: Icons.content_copy_rounded,
        subtitle: app.appUserModelId,
        onExecute: (_) => Clipboard.setData(ClipboardData(text: app.appUserModelId)),
      ),
      if (app.subtitle.isNotEmpty)
        LauncherAction(
          label: 'Copy Executable Path',
          icon: Icons.content_copy_rounded,
          subtitle: app.subtitle,
          onExecute: (_) => Clipboard.setData(ClipboardData(text: app.subtitle)),
        ),
    ];
  }

  // ── Windows ────────────────────────────────────────────────────────────────

  static List<LauncherAction> _buildWindowActions(Window window) {
    return <LauncherAction>[
      LauncherAction(
        label: 'Focus Window',
        icon: Icons.open_in_full_rounded,
        kbdHint: '↵',
        onExecute: (_) {
          Win32Window.activateWindow(window.hWnd);
          _closeLauncher();
        },
      ),
      LauncherAction(
        label: 'Minimize',
        icon: Icons.minimize_rounded,
        onExecute: (_) {
          Win32Window.minimizeWindow(window.hWnd);
        },
      ),
      LauncherAction(
        label: 'Maximize / Restore',
        icon: Icons.crop_square_rounded,
        onExecute: (_) {
          Win32Window.maximizeOrRestoreWindow(window.hWnd);
        },
      ),
      LauncherAction(
        label: 'Close Window',
        icon: Icons.close_rounded,
        isDestructive: true,
        onExecute: (_) {
          Win32Window.closeWindow(window.hWnd);
        },
      ),
      LauncherAction(
        label: 'Copy Window Title',
        icon: Icons.content_copy_rounded,
        subtitle: window.title,
        onExecute: (_) => Clipboard.setData(ClipboardData(text: window.title)),
      ),
      LauncherAction(
        label: 'Copy Process Name',
        icon: Icons.content_copy_rounded,
        subtitle: window.process.exe,
        onExecute: (_) => Clipboard.setData(ClipboardData(text: window.process.exe)),
      ),
      if (window.process.exePath.isNotEmpty)
        LauncherAction(
          label: 'Open Executable Location',
          icon: Icons.folder_open_rounded,
          subtitle: window.process.exePath,
          onExecute: (_) {
            WinUtils.open(
              'explorer.exe',
              arguments: '/select,"${window.process.exePath}"',
              parseParamaters: true,
            );
          },
        ),
    ];
  }

  // ── Bookmarks ──────────────────────────────────────────────────────────────

  static Future<List<LauncherAction>> _buildBookmarkActions(
    BuildContext context,
    BookmarkSearchResult result,
  ) async {
    switch (result.kind) {
      case BookmarkResultKind.bookmark:
        return <LauncherAction>[
          LauncherAction(
            label: 'Open',
            icon: Icons.open_in_new_rounded,
            kbdHint: '↵',
            onExecute: (_) {
              WinUtils.open(result.bookmark!.stringToExecute, parseParamaters: true);
              _closeLauncher();
            },
          ),
          LauncherAction(
            label: 'Copy URL / Path',
            icon: Icons.content_copy_rounded,
            subtitle: result.bookmark!.stringToExecute,
            onExecute: (_) => Clipboard.setData(ClipboardData(text: result.bookmark!.stringToExecute)),
          ),
          LauncherAction(
            label: 'Copy Title',
            icon: Icons.title_rounded,
            subtitle: result.bookmark!.title,
            onExecute: (_) => Clipboard.setData(ClipboardData(text: result.bookmark!.title)),
          ),
        ];

      case BookmarkResultKind.cliBook:
        return _buildCliActions(context, result.cli!);

      case BookmarkResultKind.appItem:
        return <LauncherAction>[
          LauncherAction(
            label: 'Launch',
            icon: Icons.launch_rounded,
            kbdHint: '↵',
            onExecute: (_) {
              WinUtils.open(result.app!.path, arguments: result.app!.arguments);
              _closeLauncher();
            },
          ),
          LauncherAction(
            label: 'Launch as Administrator',
            icon: Icons.shield_outlined,
            onExecute: (_) {
              WinUtils.runAsAdmin(result.app!.path, arguments: result.app!.arguments);
              _closeLauncher();
            },
          ),
          LauncherAction(
            label: 'Copy Path',
            icon: Icons.content_copy_rounded,
            subtitle: result.app!.path,
            onExecute: (_) => Clipboard.setData(ClipboardData(text: result.app!.path)),
          ),
        ];
    }
  }

  // ── CLI ────────────────────────────────────────────────────────────────────

  static List<LauncherAction> _buildCliActions(
    BuildContext context,
    CliBookItem cli,
  ) {
    return <LauncherAction>[
      LauncherAction(
        label: 'Copy Command',
        icon: Icons.content_copy_rounded,
        kbdHint: '↵',
        subtitle: cli.value,
        onExecute: (_) {
          Clipboard.setData(ClipboardData(text: cli.value));
          _closeLauncher();
        },
      ),
      LauncherAction(
        label: 'Run in PowerShell',
        icon: Icons.play_arrow_rounded,
        subtitle: 'Opens a visible PowerShell window',
        onExecute: (_) {
          WinUtils.runPowerShellDetachedVisible(cli.value, keepOpen: true);
          _closeLauncher();
        },
      ),
      LauncherAction(
        label: 'Run with Parameters…',
        icon: Icons.tune_rounded,
        subtitle: 'Fill variables & pick working directory',
        keepPanelOpen: true,
        onExecute: (BuildContext ctx) {
          showModalBottomSheet<void>(
            context: ctx,
            barrierColor: Colors.transparent,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => _CliRunSheet(cliItem: cli),
          );
        },
      ),
      LauncherAction(
        label: 'Run in Specific Folder…',
        icon: Icons.folder_special_rounded,
        subtitle: 'Pick a working directory then run',
        onExecute: (_) async {
          _closeLauncher();

          // final DirectoryPicker picker = DirectoryPicker()..title = 'Select Working Directory';
          // final Directory? dir = picker.getDirectory();
          // if (dir == null || dir.path.isEmpty) return;
          // if (mounted) setState(() => _workingDirectory = dir.path);
          ///
          final DirectoryPicker picker = DirectoryPicker()..title = 'Select Working Directory';
          final Directory? dir = picker.getDirectory();
          if (dir == null || dir.path.isEmpty) return;
          WinUtils.runPowerShellDetachedVisible(
            cli.value,
            workingDirectory: dir.path,
            keepOpen: true,
          );
        },
      ),
    ];
  }

  // ── Notion ─────────────────────────────────────────────────────────────────

  static List<LauncherAction> _buildNotionActions(NotionResult result) {
    return <LauncherAction>[
      LauncherAction(
        label: 'Open in Browser',
        icon: Icons.open_in_new_rounded,
        kbdHint: '↵',
        onExecute: (_) {
          if (result.url.isNotEmpty) WinUtils.open(result.url);
          _closeLauncher();
        },
      ),
      LauncherAction(
        label: 'Copy URL',
        icon: Icons.content_copy_rounded,
        subtitle: result.url,
        onExecute: (_) => Clipboard.setData(ClipboardData(text: result.url)),
      ),
      LauncherAction(
        label: 'Copy Title',
        icon: Icons.title_rounded,
        subtitle: result.title,
        onExecute: (_) => Clipboard.setData(ClipboardData(text: result.title)),
      ),
    ];
  }

  // ── Quick Actions ──────────────────────────────────────────────────────────

  static List<LauncherAction> _buildQuickActionActions(
    BuildContext context,
    QuickActionMenuEntry entry,
  ) {
    return <LauncherAction>[
      LauncherAction(
        label: 'Execute "${entry.title}"',
        icon: Icons.bolt_rounded,
        kbdHint: '↵',
        onExecute: (_) {
          if (entry.onExecute != null) entry.onExecute!();
        },
      ),
      LauncherAction(
        label: 'Copy Name',
        icon: Icons.content_copy_rounded,
        subtitle: entry.title,
        onExecute: (_) => Clipboard.setData(ClipboardData(text: entry.title)),
      ),
    ];
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static void _closeLauncher() {
    // Mirrors the pattern used throughout launcher.dart.
    QuickMenuFunctions.hideQuickMenu();
    Globals.quickMenuPage = QuickMenuPage.quickMenu;
    userSettings.launcherSearchText = '';
  }
}

class Win32Window {
  static void activateWindow(int hWnd) => Win32.activateWindow(hWnd);

  static void minimizeWindow(int hWnd) {
    // ShowWindow(hWnd, SW_MINIMIZE) — Win32 exposes this via win32 package.
    // Use the same WinUtils helper pattern as the rest of the app.
    try {
      WinUtils.minimizeWindow(hWnd);
    } catch (_) {
      // Fallback: just activate so the user sees *something* happened.
      Win32.activateWindow(hWnd);
    }
  }

  static void maximizeOrRestoreWindow(int hWnd) {
    try {
      WinUtils.maximizeOrRestoreWindow(hWnd);
    } catch (_) {}
  }

  static void closeWindow(int hWnd) {
    try {
      Win32.closeWindow(hWnd);
    } catch (_) {}
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ParametersDialog — simple "run with args" input dialog
// ─────────────────────────────────────────────────────────────────────────────

class _ParametersDialog extends StatelessWidget {
  const _ParametersDialog({
    required this.title,
    required this.controller,
  });

  final String title;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final Color accent = userSettings.themeColors.accent;

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
