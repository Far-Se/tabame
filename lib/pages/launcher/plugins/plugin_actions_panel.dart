import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/settings.dart';
import '../../../widgets/widgets/windows_scroll.dart';
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
    final ThemeData theme = Theme.of(context);
    final Color accent = Design.accent;
    final Color surface = theme.colorScheme.surface;

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
              child: Container(
                width: 380,
                constraints: const BoxConstraints(maxHeight: 460),
                margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: accent.withAlpha(40)),
                  boxShadow: <BoxShadow>[
                    BoxShadow(color: Colors.black.withAlpha(60), blurRadius: 28, offset: const Offset(0, 10)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                      child: Row(
                        children: <Widget>[
                          Icon(PluginIcons.resolve(widget.item.icon), size: 18, color: accent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.item.title.isEmpty ? 'Actions' : widget.item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, thickness: 1),
                    if (_actions.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No actions available',
                          style: theme.textTheme.bodyMedium?.copyWith(color: Design.text.withAlpha(120)),
                        ),
                      )
                    else
                      Flexible(
                        child: WindowsScrollView(
                          controller: _scrollController,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              for (int i = 0; i < _actions.length; i++)
                                _PluginActionRow(
                                  action: _actions[i],
                                  isSelected: i == _activeIndex,
                                  accent: accent,
                                  onTap: () => _execute(i),
                                  onHover: () => setState(() => _activeIndex = i),
                                ),
                            ],
                          ),
                        ),
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
    required this.accent,
    required this.onTap,
    required this.onHover,
  });

  final PluginAction action;
  final bool isSelected;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onHover: (PointerHoverEvent event) {
        if (event.delta != Offset.zero) onHover();
      },
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: isSelected ? accent.withAlpha(40) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: <Widget>[
              Icon(PluginIcons.resolve(action.icon), size: 16, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  action.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Design.text : Design.text.withAlpha(210),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
