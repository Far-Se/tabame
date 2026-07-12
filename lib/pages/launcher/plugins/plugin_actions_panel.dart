import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/settings.dart';
import '../../../widgets/widgets/windows_scroll.dart';
import '../launcher_modal_theme.dart';
import '../result/result_row.dart';
import 'plugin_icons.dart';
import 'plugin_protocol.dart';

/// A compact Ctrl+K command palette for a single plugin item. The available
/// actions come straight from the item's `actions` JSON; picking one invokes
/// [onSelected] with the action id (which the launcher forwards to the plugin).
///
/// Mirrors the look and keyboard behaviour of the built-in `ActionsPanelScaffold`
/// but is driven by plugin data rather than [LauncherAction]s.
class PluginActionsPanel extends StatefulWidget {
  const PluginActionsPanel({
    super.key,
    required this.item,
    required this.onSelected,
  });

  final PluginItem item;
  final void Function(String actionId) onSelected;

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

  List<PluginAction> get _actions => widget.item.actions;

  void _execute(int index) {
    if (index < 0 || index >= _actions.length) return;
    final String id = _actions[index].id;
    Navigator.of(context).pop();
    widget.onSelected(id);
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
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final LauncherModalTokens tokens = LauncherModalTokens.of(context);

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
                      icon: Icon(PluginIcons.resolve(widget.item.icon), size: 18, color: tokens.accent),
                      title: widget.item.title.isEmpty ? 'Actions' : widget.item.title,
                      badgeLabel: 'Actions',
                    ),
                    Divider(height: 1, thickness: 1, color: tokens.onSurface.withAlpha(20)),
                    if (_actions.isEmpty)
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
                                for (int i = 0; i < _actions.length; i++)
                                  _PluginActionRow(
                                    action: _actions[i],
                                    isSelected: i == _activeIndex,
                                    tokens: tokens,
                                    onTap: () => _execute(i),
                                    onHover: () => setState(() => _activeIndex = i),
                                  ),
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
    // The row shell (icon nest, selection treatment, motion) comes from
    // LauncherResultRow, so plugin actions match the launcher's result rows.
    return LauncherResultRow(
      isSelected: isSelected,
      isRepeating: false,
      accent: tokens.accent,
      onSurface: tokens.onSurface,
      onTap: onTap,
      onHover: onHover,
      icon: SizedBox(
        width: 16,
        height: 16,
        child: Icon(PluginIcons.resolve(action.icon), size: 16, color: tokens.accent),
      ),
      content: Text(
        action.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: tokens.text(
          fontSize: Design.baseFontSize + 1.5,
          fontWeight: FontWeight.w600,
          color: isSelected && tokens.design == LauncherDesign.terminal
              ? tokens.accent
              : isSelected
                  ? tokens.onSurface
                  : tokens.onSurface.withAlpha(210),
          height: 1.25,
        ),
      ),
    );
  }
}
