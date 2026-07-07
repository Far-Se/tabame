import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';

import '../../../models/settings.dart';
import '../../../widgets/widgets/windows_scroll.dart';
import '../result/result_row.dart';
import 'plugin_icons.dart';
import 'plugin_protocol.dart';

/// Renders the live plugin UI described by a [PluginRenderFrame], replacing the
/// launcher's default results list while a plugin is active.
///
/// Supports the three plugin layouts (list / grid / detail) plus an optional
/// split preview pane bound to the selected item. Selection is owned by the
/// launcher and passed down as [activeIndex]; taps and hovers are reported back
/// through [onTapItem] / [onHoverItem]. The widget keeps the highlighted item
/// scrolled into view.
class PluginView extends StatefulWidget {
  const PluginView({
    super.key,
    required this.frame,
    required this.activeIndex,
    required this.isRepeating,
    required this.onTapItem,
    required this.onHoverItem,
  });

  final PluginRenderFrame frame;
  final int activeIndex;
  final bool isRepeating;
  final void Function(int index) onTapItem;
  final void Function(int index) onHoverItem;

  @override
  State<PluginView> createState() => _PluginViewState();
}

class _PluginViewState extends State<PluginView> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = <int, GlobalKey>{};

  // When the selection moves because the pointer hovered a new row, we must NOT
  // scroll it into view — recentering the list under the cursor makes it hover
  // yet another row, producing runaway auto-scroll. Only keyboard-driven
  // selection changes scroll; hovering leaves the scroll offset alone so the
  // user can scroll manually.
  bool _selectionFromHover = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PluginView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeIndex != widget.activeIndex) {
      final bool fromHover = _selectionFromHover;
      _selectionFromHover = false;
      if (!fromHover) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollActiveIntoView());
      }
    }
  }

  /// Reports a hover selection to the launcher, flagging the resulting
  /// [activeIndex] change so [didUpdateWidget] skips the auto-scroll.
  void _hoverSelect(int index) {
    if (index != widget.activeIndex) _selectionFromHover = true;
    widget.onHoverItem(index);
  }

  void _scrollActiveIntoView() {
    if (!mounted) return;
    final BuildContext? itemContext = _itemKeys[widget.activeIndex]?.currentContext;
    if (itemContext == null) return;
    Scrollable.ensureVisible(
      itemContext,
      alignment: 0.5,
      duration: widget.isRepeating ? Duration.zero : const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
    );
  }

  GlobalKey _keyFor(int index) => _itemKeys.putIfAbsent(index, () => GlobalKey());

  @override
  Widget build(BuildContext context) {
    final PluginRenderFrame frame = widget.frame;

    if (frame.view == PluginViewType.detail) {
      return _buildDetail(frame.detailMarkdown ?? '');
    }

    if (frame.items.isEmpty) {
      return _buildEmptyOrLoading(frame);
    }

    final Widget itemsPane = frame.view == PluginViewType.grid ? _buildGrid(frame) : _buildList(frame);

    if (!frame.hasPreview) return itemsPane;

    // Split layout: items on the left, a markdown preview of the selected item
    // on the right.
    final int idx = widget.activeIndex.clamp(0, frame.items.length - 1);
    final String preview = frame.items[idx].previewMarkdown ?? '';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(flex: 5, child: itemsPane),
        Container(width: 1, color: Design.accent.withAlpha(30)),
        Expanded(flex: 4, child: _buildPreviewPane(preview)),
      ],
    );
  }

  Widget _buildEmptyOrLoading(PluginRenderFrame frame) {
    return Center(
      child: frame.loading
          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
          : Text(
              frame.emptyText,
              style: TextStyle(fontSize: 13, color: Design.text.withAlpha(120)),
            ),
    );
  }

  Widget _buildList(PluginRenderFrame frame) {
    return WindowsScrollView(
      controller: _scrollController,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int i = 0; i < frame.items.length; i++)
            KeyedSubtree(
              key: _keyFor(i),
              child: LauncherResultRow(
                isSelected: i == widget.activeIndex,
                isRepeating: widget.isRepeating,
                accent: Design.accent,
                onSurface: Design.text,
                onTap: () => widget.onTapItem(i),
                onHover: () => _hoverSelect(i),
                icon: _PluginIcon(name: frame.items[i].icon, accent: Design.accent),
                title: frame.items[i].title,
                subtitle: frame.items[i].subtitle,
                badge: _accessoryBadge(frame.items[i]),
              ),
            ),
        ],
      ),
    );
  }

  Widget? _accessoryBadge(PluginItem item) {
    if (item.accessories.isEmpty) return null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final PluginAccessory accessory in item.accessories)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: LauncherSereneBadge(
              icon: Icons.label_important_rounded,
              label: accessory.text,
              color: Design.accent,
            ),
          ),
      ],
    );
  }

  Widget _buildGrid(PluginRenderFrame frame) {
    return WindowsScrollView(
      controller: _scrollController,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: frame.items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: frame.gridColumns,
            childAspectRatio: frame.gridAspectRatio,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
          ),
          itemBuilder: (BuildContext context, int i) {
            return KeyedSubtree(
              key: _keyFor(i),
              child: _PluginGridTile(
                item: frame.items[i],
                isSelected: i == widget.activeIndex,
                onTap: () => widget.onTapItem(i),
                onHover: () => _hoverSelect(i),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDetail(String markdown) {
    return WindowsScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: markdown.trim().isEmpty
            ? Text('No content', style: TextStyle(fontSize: 13, color: Design.text.withAlpha(120)))
            : MarkdownBlock(data: markdown, config: _markdownConfig),
      ),
    );
  }

  Widget _buildPreviewPane(String markdown) {
    return WindowsScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: markdown.trim().isEmpty
            ? Text('No preview', style: TextStyle(fontSize: 12, color: Design.text.withAlpha(90)))
            : MarkdownBlock(data: markdown, config: _markdownConfig),
      ),
    );
  }

  /// Markdown styling tied to the active theme. The package defaults render
  /// `inline code` and ```code blocks``` as gray-on-gray, which is unreadable
  /// against the launcher's backdrop — retint them with [Design] colors.
  MarkdownConfig get _markdownConfig => MarkdownConfig(
        configs: <WidgetConfig>[
          PConfig(textStyle: TextStyle(color: Design.text, fontSize: 13)),
          // Inline `code`: accent text on a faint accent fill.
          CodeConfig(
            style: TextStyle(
              color: Design.accent,
              backgroundColor: Design.accent.withAlpha(28),
              fontFamily: 'Consolas',
              fontSize: 12.5,
            ),
          ),
          // Fenced code blocks: readable text over a subtle panel.
          PreConfig(
            textStyle: TextStyle(color: Design.text, fontFamily: 'Consolas', fontSize: 12.5),
            styleNotMatched: TextStyle(color: Design.text),
            decoration: BoxDecoration(
              color: Design.text.withAlpha(14),
              border: Border.all(color: Design.accent.withAlpha(30)),
              borderRadius: BorderRadius.circular(6),
            ),
            padding: const EdgeInsets.all(10),
          ),
          BlockquoteConfig(sideColor: Design.accent.withAlpha(120), textColor: Design.text),
          LinkConfig(style: TextStyle(color: Design.accent, decoration: TextDecoration.underline)),
        ],
      );
}

/// Resolves a plugin icon string to a widget: a Material icon name, a local
/// `file://` image, or a remote `https://` image (both fall back to the icon on
/// error).
class _PluginIcon extends StatelessWidget {
  const _PluginIcon({required this.name, required this.accent, this.size = 16});
  final String? name;
  final Color accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    final String? value = name?.trim();
    if (value != null && (value.startsWith('http://') || value.startsWith('https://'))) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.network(
          value,
          width: size + 6,
          height: size + 6,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Icon(PluginIcons.fallback, size: size, color: accent),
        ),
      );
    }
    if (value != null && value.startsWith('file://')) {
      final String path = Uri.parse(value).toFilePath(windows: true);
      final File file = File(path);
      if (file.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.file(
            file,
            width: size + 6,
            height: size + 6,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Icon(PluginIcons.fallback, size: size, color: accent),
          ),
        );
      }
    }
    return Icon(PluginIcons.resolve(value), size: size, color: accent);
  }
}

/// A single grid tile: icon over title/subtitle, with an accent selection
/// treatment matching the launcher's design language.
class _PluginGridTile extends StatelessWidget {
  const _PluginGridTile({
    required this.item,
    required this.isSelected,
    required this.onTap,
    required this.onHover,
  });

  final PluginItem item;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final Color accent = Design.accent;
    final Color onSurface = Design.text;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onHover: (PointerHoverEvent event) {
        if (event.delta != Offset.zero) onHover();
      },
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isSelected ? accent.withAlpha(40) : onSurface.withAlpha(8),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isSelected ? accent.withAlpha(120) : onSurface.withAlpha(14)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              _PluginIcon(name: item.icon, accent: accent, size: 22),
              if (item.title.isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? onSurface : onSurface.withAlpha(210),
                  ),
                ),
              ],
              if (item.subtitle.isNotEmpty)
                Text(
                  item.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 9, color: onSurface.withAlpha(130)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
