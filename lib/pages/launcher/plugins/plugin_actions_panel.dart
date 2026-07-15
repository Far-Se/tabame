import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/settings.dart';
import '../../../widgets/widgets/windows_scroll.dart';
import '../launcher_modal_theme.dart';
import '../result/result_row.dart';
import 'plugin_icons.dart';
import 'plugin_protocol.dart';
import 'plugin_shortcut.dart';

/// A compact Ctrl+K command palette for a plugin: the highlighted item's own
/// actions first, then the frame-level actions (refresh, create, sign out…)
/// under a divider. Picking one invokes [onSelected]; the launcher forwards it
/// to the plugin (item actions with the item's id, frame actions with `""`).
///
/// Mirrors the look and keyboard behaviour of the built-in `ActionsPanelScaffold`
/// but is driven by plugin data rather than [LauncherAction]s.
class PluginActionsPanel extends StatefulWidget {
  const PluginActionsPanel({
    super.key,
    required this.item,
    required this.frameActions,
    required this.onSelected,
  });

  /// The highlighted item; null when the view has no items (detail/form).
  final PluginItem? item;

  /// Frame-level actions, shown after the item's own.
  final List<PluginAction> frameActions;

  final void Function(PluginAction action, {required bool isFrameAction}) onSelected;

  @override
  State<PluginActionsPanel> createState() => _PluginActionsPanelState();
}

class _PluginActionsPanelState extends State<PluginActionsPanel> {
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  int _activeIndex = 0;

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<PluginAction> get _itemActions => widget.item?.actions ?? const <PluginAction>[];

  /// Flat navigation order: item actions, then frame actions.
  List<PluginAction> get _actions => <PluginAction>[..._itemActions, ...widget.frameActions];

  void _execute(int index) {
    final List<PluginAction> actions = _actions;
    if (index < 0 || index >= actions.length) return;
    final bool isFrame = index >= _itemActions.length;
    Navigator.of(context).pop();
    widget.onSelected(actions[index], isFrameAction: isFrame);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.escape ||
        (event.logicalKey == LogicalKeyboardKey.keyK && HardwareKeyboard.instance.isControlPressed)) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() => _activeIndex = (_activeIndex + 1).clamp(0, _actions.length - 1));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() => _activeIndex = (_activeIndex - 1).clamp(0, _actions.length - 1));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _execute(_activeIndex);
      return KeyEventResult.handled;
    }
    // An action's own shortcut also works from inside the palette.
    for (int i = 0; i < _actions.length; i++) {
      final PluginShortcut? shortcut = PluginShortcut.parse(_actions[i].shortcut);
      if (shortcut != null && shortcut.matches(event)) {
        _execute(i);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final LauncherModalTokens tokens = LauncherModalTokens.of(context);
    final List<PluginAction> actions = _actions;
    final int dividerAfter = _itemActions.isNotEmpty && widget.frameActions.isNotEmpty ? _itemActions.length : -1;

    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: Focus(
              focusNode: _focusNode,
              onKeyEvent: _onKey,
              child: LauncherModalFrame(
                tokens: tokens,
                width: 380,
                maxHeight: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    LauncherModalHeader(
                      tokens: tokens,
                      icon: Icon(PluginIcons.resolve(widget.item?.icon), size: 18, color: tokens.accent),
                      title: (widget.item?.title.isNotEmpty ?? false) ? widget.item!.title : 'Actions',
                      badgeLabel: 'Actions',
                    ),
                    Divider(height: 1, thickness: 1, color: tokens.onSurface.withAlpha(20)),
                    if (actions.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No actions available',
                          style: tokens.text(fontSize: Design.baseFontSize + 2, color: tokens.dim),
                        ),
                      )
                    else
                      Flexible(
                        child: WindowsScrollView(
                          controller: _scrollController,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                for (int i = 0; i < actions.length; i++) ...<Widget>[
                                  if (i == dividerAfter)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                      child: Container(height: 1, color: tokens.onSurface.withAlpha(18)),
                                    ),
                                  _PluginActionRow(
                                    action: actions[i],
                                    isSelected: i == _activeIndex,
                                    tokens: tokens,
                                    onTap: () => _execute(i),
                                    onHover: () => setState(() => _activeIndex = i),
                                  ),
                                ],
                              ],
                            ),
                          ),
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

class _PluginActionRow extends StatelessWidget {
  const _PluginActionRow({
    required this.action,
    required this.isSelected,
    required this.tokens,
    required this.onTap,
    required this.onHover,
  });

  final PluginAction action;
  final bool isSelected;
  final LauncherModalTokens tokens;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    // Destructive actions carry a danger tint so deletes read as deletes.
    final Color tint = action.destructive ? const Color(0xFFE5534B) : tokens.accent;
    final PluginShortcut? shortcut = PluginShortcut.parse(action.shortcut);

    // The row shell (icon nest, selection treatment, motion) comes from
    // LauncherResultRow, so plugin actions match the launcher's result rows.
    return LauncherResultRow(
      isSelected: isSelected,
      isRepeating: false,
      accent: tint,
      onSurface: tokens.onSurface,
      onTap: onTap,
      onHover: onHover,
      icon: SizedBox(
        width: 16,
        height: 16,
        child: Icon(PluginIcons.resolve(action.icon), size: 16, color: tint),
      ),
      content: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              action.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tokens.text(
                fontSize: Design.baseFontSize + 1.5,
                fontWeight: FontWeight.w600,
                color: action.destructive
                    ? tint.withAlpha(isSelected ? 255 : 220)
                    : isSelected && tokens.design == LauncherDesign.terminal
                        ? tokens.accent
                        : isSelected
                            ? tokens.onSurface
                            : tokens.onSurface.withAlpha(210),
                height: 1.25,
              ),
            ),
          ),
          if (shortcut != null)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                border: Border.all(color: tokens.onSurface.withAlpha(40)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                shortcut.label,
                style: tokens.text(fontSize: Design.baseFontSize - 1.5, color: tokens.onSurface.withAlpha(130)),
              ),
            ),
        ],
      ),
    );
  }
}

/// A small confirmation modal for actions that declared `"confirm"`. Pops with
/// `true` when the user accepts (Enter / the CTA), `false` otherwise.
class PluginConfirmPanel extends StatefulWidget {
  const PluginConfirmPanel({super.key, required this.action});

  final PluginAction action;

  @override
  State<PluginConfirmPanel> createState() => _PluginConfirmPanelState();
}

class _PluginConfirmPanelState extends State<PluginConfirmPanel> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop(false);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      Navigator.of(context).pop(true);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final LauncherModalTokens tokens = LauncherModalTokens.of(context);
    final PluginConfirm confirm = widget.action.confirm ??
        const PluginConfirm(title: 'Are you sure?', message: '', confirmLabel: 'Confirm');
    final Color tint = widget.action.destructive ? const Color(0xFFE5534B) : tokens.accent;

    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop(false),
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: Focus(
              focusNode: _focusNode,
              onKeyEvent: _onKey,
              child: LauncherModalFrame(
                tokens: tokens,
                width: 340,
                maxHeight: 260,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    LauncherModalHeader(
                      tokens: tokens,
                      icon: Icon(PluginIcons.resolve(widget.action.icon ?? 'warning'), size: 18, color: tint),
                      title: confirm.title,
                      badgeLabel: 'Confirm',
                    ),
                    Divider(height: 1, thickness: 1, color: tokens.onSurface.withAlpha(20)),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          if (confirm.message.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                confirm.message,
                                style: tokens.text(
                                    fontSize: Design.baseFontSize + 1.5,
                                    color: tokens.onSurface.withAlpha(200),
                                    height: 1.4),
                              ),
                            ),
                          Row(
                            children: <Widget>[
                              _ConfirmButton(
                                label: confirm.confirmLabel,
                                color: tint,
                                filled: true,
                                onTap: () => Navigator.of(context).pop(true),
                              ),
                              const SizedBox(width: 8),
                              _ConfirmButton(
                                label: 'Cancel',
                                color: tokens.onSurface,
                                filled: false,
                                onTap: () => Navigator.of(context).pop(false),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    LauncherModalFooter(
                      tokens: tokens,
                      hints: const <(String, String)>[('↵', 'confirm'), ('Esc', 'cancel')],
                      trailing: null,
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

class _ConfirmButton extends StatelessWidget {
  const _ConfirmButton({required this.label, required this.color, required this.filled, required this.onTap});

  final String label;
  final Color color;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: filled ? color.withAlpha(36) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withAlpha(filled ? 150 : 50)),
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color.withAlpha(235)),
          ),
        ),
      ),
    );
  }
}
