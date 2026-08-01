import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:markdown_widget/markdown_widget.dart';

import '../../../models/settings.dart';
import '../../../widgets/widgets/windows_scroll.dart';
import '../launcher_modal_theme.dart';
import '../result/result_row.dart';
import 'plugin_icons.dart';
import 'plugin_form_view.dart';
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
    this.readmeAction,
    this.onReadmeSelected,
  });

  /// The highlighted item; null when the view has no items (detail/form).
  final PluginItem? item;

  /// Frame-level actions, shown after the item's own.
  final List<PluginAction> frameActions;

  final void Function(PluginAction action, {required bool isFrameAction}) onSelected;

  /// A launcher-owned documentation action, always shown after plugin actions.
  final PluginAction? readmeAction;
  final VoidCallback? onReadmeSelected;

  @override
  State<PluginActionsPanel> createState() => _PluginActionsPanelState();
}

class _PluginActionsPanelState extends State<PluginActionsPanel> {
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _actionKeys = <int, GlobalKey>{};
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
  List<PluginAction> get _actions => <PluginAction>[
        ..._itemActions,
        ...widget.frameActions,
        if (widget.readmeAction != null) widget.readmeAction!,
      ];

  GlobalKey _keyFor(int index) => _actionKeys.putIfAbsent(index, () => GlobalKey());

  void _scrollActiveIntoView() {
    if (!mounted) return;
    final BuildContext? actionContext = _actionKeys[_activeIndex]?.currentContext;
    if (actionContext == null) return;
    Scrollable.ensureVisible(
      actionContext,
      alignment: 0.5,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
    );
  }

  void _moveActive(int offset) {
    final int actionCount = _actions.length;
    if (actionCount == 0) return;
    setState(() => _activeIndex = (_activeIndex + offset) % actionCount);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollActiveIntoView());
  }

  void _execute(int index) {
    final List<PluginAction> actions = _actions;
    if (index < 0 || index >= actions.length) return;
    final bool isReadme = widget.readmeAction != null && index == actions.length - 1;
    final bool isFrame = index >= _itemActions.length;
    Navigator.of(context).pop();
    if (isReadme) {
      widget.onReadmeSelected?.call();
      return;
    }
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
      _moveActive(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _moveActive(-1);
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
                                    key: _keyFor(i),
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

/// Scrollable Markdown preview for a plugin's local README.md.
class PluginReadmePanel extends StatefulWidget {
  const PluginReadmePanel({super.key, required this.pluginName, required this.markdown});

  final String pluginName;
  final String markdown;

  @override
  State<PluginReadmePanel> createState() => _PluginReadmePanelState();
}

class _PluginReadmePanelState extends State<PluginReadmePanel> {
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

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

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape ||
        (event.logicalKey == LogicalKeyboardKey.keyK && HardwareKeyboard.instance.isControlPressed)) {
      Navigator.of(context).pop();
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
                width: 760,
                maxHeight: 640,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    LauncherModalHeader(
                      tokens: tokens,
                      icon: Icon(Icons.description_rounded, size: 18, color: tokens.accent),
                      title: widget.pluginName,
                      badgeLabel: 'README.md',
                    ),
                    Divider(height: 1, thickness: 1, color: tokens.onSurface.withAlpha(20)),
                    Flexible(
                      child: WindowsScrollView(
                        controller: _scrollController,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
                          child: SelectionArea(
                            child: widget.markdown.trim().isEmpty
                                ? Text('README.md is empty.', style: tokens.text(color: tokens.dim))
                                : MarkdownBlock(
                                    data: widget.markdown,
                                    config: _markdownConfig(tokens),
                                  ),
                          ),
                        ),
                      ),
                    ),
                    LauncherModalFooter(
                      tokens: tokens,
                      hints: const <(String, String)>[('Esc', 'close')],
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

  /// Replaces markdown_widget's light-mode defaults with the palette and
  /// typography of the active launcher design. The package otherwise renders
  /// several elements (notably code, headings, rules, and list markers) with
  /// hard-coded grays that lose contrast in themed modal surfaces.
  MarkdownConfig _markdownConfig(LauncherModalTokens tokens) {
    final Color text = tokens.onSurface;
    final Color accent = tokens.accent;

    _ReadmeHeadingConfig heading(
      MarkdownTag tag,
      double size, {
      int alpha = 255,
      double letterSpacing = 0,
      HeadingDivider? divider,
      EdgeInsets padding = const EdgeInsets.only(top: 10, bottom: 3),
    }) {
      return _ReadmeHeadingConfig(
        tag: tag.name,
        style: tokens.text(
          color: text.withAlpha(alpha),
          fontSize: size,
          fontWeight: FontWeight.w700,
          letterSpacing: letterSpacing,
          height: 1.3,
        ),
        divider: divider,
        padding: padding,
      );
    }

    final Color coolTone = Color.lerp(accent, text, 0.32)!;
    final Color warmTone = Color.lerp(accent, const Color(0xFFE3A85B), 0.42)!;
    final Map<String, TextStyle> codeTheme = <String, TextStyle>{
      'root': TextStyle(color: text, backgroundColor: Colors.transparent),
      'comment': TextStyle(color: text.withAlpha(120), fontStyle: FontStyle.italic),
      'quote': TextStyle(color: text.withAlpha(120), fontStyle: FontStyle.italic),
      'meta': TextStyle(color: text.withAlpha(170)),
      'keyword': TextStyle(color: accent),
      'selector-tag': TextStyle(color: accent),
      'built_in': TextStyle(color: accent),
      'tag': TextStyle(color: accent),
      'type': TextStyle(color: coolTone),
      'number': TextStyle(color: coolTone),
      'literal': TextStyle(color: coolTone),
      'string': TextStyle(color: warmTone),
      'attr': TextStyle(color: warmTone),
      'title': TextStyle(color: warmTone),
      'section': TextStyle(color: warmTone),
      'function': TextStyle(color: warmTone),
    };

    return MarkdownConfig(
      configs: <WidgetConfig>[
        PConfig(textStyle: tokens.text(color: text.withAlpha(225), fontSize: 13, height: 1.5)),
        heading(
          MarkdownTag.h1,
          18,
          letterSpacing: -0.2,
          divider: HeadingDivider(color: text.withAlpha(32), space: 6, height: 1),
          padding: const EdgeInsets.only(top: 12, bottom: 5),
        ),
        heading(
          MarkdownTag.h2,
          15.5,
          divider: HeadingDivider(color: text.withAlpha(24), space: 5, height: 1),
          padding: const EdgeInsets.only(top: 12, bottom: 4),
        ),
        heading(MarkdownTag.h3, 14),
        heading(MarkdownTag.h4, 13, alpha: 225),
        heading(MarkdownTag.h5, 12, alpha: 195),
        heading(MarkdownTag.h6, 11.5, alpha: 155, letterSpacing: 0.3),
        HrConfig(height: 1, color: text.withAlpha(30)),
        ListConfig(
          marginLeft: 22,
          marker: (bool ordered, int depth, int index) =>
              _readmeListMarker(tokens, ordered: ordered, depth: depth, index: index),
        ),
        CheckBoxConfig(
          builder: (bool checked) => Padding(
            padding: const EdgeInsets.only(right: 5, top: 1),
            child: Icon(
              checked ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
              size: 15,
              color: checked ? accent : text.withAlpha(125),
            ),
          ),
        ),
        CodeConfig(
          style: TextStyle(
            color: accent,
            backgroundColor: accent.withAlpha(28),
            fontFamily: 'Consolas',
            fontSize: 12.5,
          ),
        ),
        PreConfig(
          textStyle: const TextStyle(fontFamily: 'Consolas', fontSize: 12.5, height: 1.45),
          styleNotMatched: TextStyle(color: text),
          theme: codeTheme,
          decoration: BoxDecoration(
            color: text.withAlpha(tokens.isDark ? 14 : 10),
            border: Border.all(color: accent.withAlpha(42)),
            borderRadius: BorderRadius.circular(tokens.controlRadius.clamp(3, 7)),
          ),
          padding: const EdgeInsets.all(10),
        ),
        BlockquoteConfig(
          sideColor: accent.withAlpha(150),
          sideWith: 3,
          textColor: text.withAlpha(205),
          padding: const EdgeInsets.fromLTRB(12, 2, 0, 2),
        ),
        TableConfig(
          border: TableBorder.all(color: text.withAlpha(42)),
          headerRowDecoration: BoxDecoration(color: accent.withAlpha(20)),
          headerStyle: tokens.text(fontSize: 12, fontWeight: FontWeight.w700, color: accent),
          bodyStyle: tokens.text(fontSize: 12, color: text.withAlpha(225)),
          headPadding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
          bodyPadding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
        ),
        LinkConfig(
          style: tokens
              .text(
                color: accent,
                fontWeight: FontWeight.w600,
              )
              .copyWith(
                decoration: TextDecoration.underline,
                decorationColor: accent.withAlpha(150),
              ),
        ),
      ],
    );
  }
}

/// A heading config with launcher-sized type instead of markdown_widget's
/// oversized article defaults and fixed light-gray dividers.
class _ReadmeHeadingConfig extends HeadingConfig {
  const _ReadmeHeadingConfig({
    required this.tag,
    required this.style,
    this.divider,
    this.padding = const EdgeInsets.only(top: 10, bottom: 3),
  });

  @override
  final String tag;
  @override
  final TextStyle style;
  @override
  final HeadingDivider? divider;
  @override
  final EdgeInsets padding;
}

Widget _readmeListMarker(
  LauncherModalTokens tokens, {
  required bool ordered,
  required int depth,
  required int index,
}) {
  final Color markerColor = tokens.accent.withAlpha(210);
  if (ordered) {
    return Container(
      alignment: Alignment.topRight,
      padding: const EdgeInsets.only(right: 6, top: 1),
      child: Text(
        '${index + 1}.',
        style: tokens.text(
          color: markerColor,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          height: 1.5,
        ),
      ),
    );
  }

  final BoxDecoration decoration = switch (depth) {
    0 => BoxDecoration(color: markerColor, shape: BoxShape.circle),
    1 => BoxDecoration(border: Border.all(color: markerColor, width: 1.2), shape: BoxShape.circle),
    _ => BoxDecoration(color: markerColor.withAlpha(160), borderRadius: BorderRadius.circular(1)),
  };
  return Padding(
    padding: const EdgeInsets.only(right: 8, top: 7),
    child: Align(
      alignment: Alignment.topRight,
      child: Container(width: 5, height: 5, decoration: decoration),
    ),
  );
}

class _PluginActionRow extends StatelessWidget {
  const _PluginActionRow({
    super.key,
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
                    : isSelected && (tokens.design == LauncherDesign.terminal || tokens.design == LauncherDesign.orbit)
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

/// Compact parameter collection shown before an action is dispatched. It
/// reuses the regular form controls so action parameters have identical
/// validation and picker behaviour to a full `form` frame.
class PluginActionParametersPanel extends StatelessWidget {
  const PluginActionParametersPanel({super.key, required this.action});

  final PluginAction action;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
          child: Material(
            color: Colors.transparent,
            child: PluginFormView(
              form: PluginForm(title: action.title, submitLabel: 'Continue', fields: action.parameters),
              onSubmit: (Map<String, Object?> values, {String? button}) => Navigator.of(context).pop(values),
              onCancel: () => Navigator.of(context).pop(),
            ),
          ),
        ),
      ),
    );
  }
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
    final PluginConfirm confirm =
        widget.action.confirm ?? const PluginConfirm(title: 'Are you sure?', message: '', confirmLabel: 'Confirm');
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
