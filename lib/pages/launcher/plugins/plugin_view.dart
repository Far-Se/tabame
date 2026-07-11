import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:markdown_widget/markdown_widget.dart';

import '../../../models/settings.dart';
import '../../../models/win32/win_utils.dart';
import '../../../widgets/widgets/windows_scroll.dart';
import '../result/result_row.dart';
import 'plugin_form_view.dart';
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
    required this.onFormSubmit,
    required this.onFormCancel,
    this.detailScrollController,
  });

  final PluginRenderFrame frame;
  final int activeIndex;
  final bool isRepeating;
  final void Function(int index) onTapItem;
  final void Function(int index) onHoverItem;

  /// Launcher-owned controller for the detail document, so arrow/page keys
  /// (handled by the launcher) can scroll it.
  final ScrollController? detailScrollController;

  /// Form view: the user pressed Enter/submit with these field values.
  final void Function(Map<String, Object?> values) onFormSubmit;

  /// Form view: the user pressed Escape.
  final VoidCallback onFormCancel;

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
      return _buildDetail(frame.detailMarkdown ?? '', frame.detailMetadata);
    }

    if (frame.view == PluginViewType.form) {
      final PluginForm? form = frame.form;
      if (form == null) return _buildEmptyOrLoading(frame);
      return PluginFormView(
        form: form,
        onSubmit: widget.onFormSubmit,
        onCancel: widget.onFormCancel,
      );
    }

    if (frame.items.isEmpty) {
      return _buildEmptyOrLoading(frame);
    }

    final Widget itemsPane = frame.view == PluginViewType.grid ? _buildGrid(frame) : _buildList(frame);

    if (!frame.hasPreview) return itemsPane;

    // Split layout: items on the left, a markdown/metadata preview of the
    // selected item on the right.
    final int idx = widget.activeIndex.clamp(0, frame.items.length - 1);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(flex: 5, child: itemsPane),
        Container(width: 1, color: Design.accent.withAlpha(30)),
        Expanded(flex: 4, child: _buildPreviewPane(frame.items[idx])),
      ],
    );
  }

  Widget _buildEmptyOrLoading(PluginRenderFrame frame) {
    if (frame.loading) {
      final String? caption = frame.loadingText;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, value: frame.loadingProgress),
            ),
            if (caption != null && caption.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  caption,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Design.text.withAlpha(150)),
                ),
              ),
            ],
          ],
        ),
      );
    }
    final PluginEmptyState? empty = frame.empty;
    if (empty == null) {
      return Center(
        child: Text(frame.emptyText, style: TextStyle(fontSize: 13, color: Design.text.withAlpha(120))),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (empty.icon != null) ...<Widget>[
            Icon(PluginIcons.resolve(empty.icon), size: 26, color: Design.accent.withAlpha(140)),
            const SizedBox(height: 8),
          ],
          if (empty.title.isNotEmpty)
            Text(
              empty.title,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Design.text.withAlpha(190)),
            ),
          if (empty.hint.isNotEmpty) ...<Widget>[
            const SizedBox(height: 3),
            Text(empty.hint, style: TextStyle(fontSize: 11, color: Design.text.withAlpha(110))),
          ],
        ],
      ),
    );
  }

  /// A slim uppercase section header, rendered whenever an item's `section`
  /// differs from the previous item's.
  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 2),
      child: Row(
        children: <Widget>[
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: Design.text.withAlpha(120),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Container(height: 1, color: Design.text.withAlpha(18))),
        ],
      ),
    );
  }

  Widget _buildList(PluginRenderFrame frame) {
    return WindowsScrollView(
      controller: _scrollController,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int i = 0; i < frame.items.length; i++) ...<Widget>[
            if (frame.items[i].section != null && (i == 0 || frame.items[i].section != frame.items[i - 1].section))
              _sectionHeader(frame.items[i].section!),
            KeyedSubtree(
              key: _keyFor(i),
              child: Column(
                children: <Widget>[
                  LauncherResultRow(
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
                    inlineMarkup: true,
                    subtitleMaxLines: frame.items[i].subtitleLines,
                  ),
                  if (frame.items[i].progress != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 4),
                      child: _PluginProgressBar(value: frame.items[i].progress!),
                    ),
                ],
              ),
            ),
          ],
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
              icon: accessory.icon != null ? PluginIcons.resolve(accessory.icon) : Icons.label_important_rounded,
              label: accessory.text,
              color: accessory.color ?? Design.accent,
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

  Widget _buildDetail(String markdown, List<PluginMetadataEntry> metadata) {
    final bool hasMarkdown = markdown.trim().isNotEmpty;
    return WindowsScrollView(
      controller: widget.detailScrollController,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: !hasMarkdown && metadata.isEmpty
            ? Text('No content', style: TextStyle(fontSize: 13, color: Design.text.withAlpha(120)))
            // Cap the measure in the widened window — full-width prose lines
            // are unreadable at 1080px.
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (hasMarkdown) MarkdownBlock(data: markdown, config: _markdownConfig),
                      if (metadata.isNotEmpty) _PluginMetadataPane(entries: metadata, topGap: hasMarkdown),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildPreviewPane(PluginItem item) {
    final String markdown = item.previewMarkdown ?? '';
    final bool hasMarkdown = markdown.trim().isNotEmpty;
    return WindowsScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: !hasMarkdown && item.previewMetadata.isEmpty
            ? Text('No preview', style: TextStyle(fontSize: 12, color: Design.text.withAlpha(90)))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (hasMarkdown) MarkdownBlock(data: markdown, config: _markdownConfig),
                  if (item.previewMetadata.isNotEmpty)
                    _PluginMetadataPane(entries: item.previewMetadata, topGap: hasMarkdown),
                ],
              ),
      ),
    );
  }

  /// Markdown styling tied to the active theme. Every block type is retinted
  /// with [Design] colors — the package defaults render headings, list bullets,
  /// checkboxes, rules and syntax tokens with hardcoded light-mode grays/blacks
  /// (e.g. a 32px black `# H1` under a `#d7dde3` underline) that are unreadable
  /// and visually foreign against the launcher's themed backdrop.
  MarkdownConfig get _markdownConfig {
    final Color text = Design.text;
    final Color accent = Design.accent;

    // Compact heading scale sized for the launcher's density, not the package's
    // article-page defaults. Level headings share w700 and the theme text
    // color, stepping down in size/opacity; h1/h2 keep a hairline rule.
    _MdHeadingConfig heading(
      MarkdownTag tag,
      double size, {
      int alpha = 255,
      double spacing = 0,
      HeadingDivider? divider,
      EdgeInsets padding = const EdgeInsets.only(top: 10, bottom: 3),
    }) =>
        _MdHeadingConfig(
          tag: tag.name,
          style: TextStyle(
            color: text.withAlpha(alpha),
            fontSize: size,
            height: 1.3,
            fontWeight: FontWeight.w700,
            letterSpacing: spacing,
          ),
          divider: divider,
          padding: padding,
        );

    // Syntax palette derived from the accent hue so highlighted code reads as
    // part of the theme (and adapts to any accent) instead of GitHub-light
    // colors. Unlisted tokens fall through to [text] via styleNotMatched.
    final Map<String, TextStyle> codeTheme = <String, TextStyle>{
      'root': TextStyle(color: text, backgroundColor: Colors.transparent),
      'comment': TextStyle(color: text.withAlpha(105), fontStyle: FontStyle.italic),
      'quote': TextStyle(color: text.withAlpha(105), fontStyle: FontStyle.italic),
      'meta': TextStyle(color: text.withAlpha(150)),
      'keyword': TextStyle(color: accent),
      'selector-tag': TextStyle(color: accent),
      'built_in': TextStyle(color: accent),
      'tag': TextStyle(color: accent),
      'type': TextStyle(color: Design.accentHue(-40)),
      'number': TextStyle(color: Design.accentHue(-40)),
      'literal': TextStyle(color: Design.accentHue(-40)),
      'string': TextStyle(color: Design.accentHue(120, saturation: 0.85)),
      'attr': TextStyle(color: Design.accentHue(120, saturation: 0.85)),
      'title': TextStyle(color: Design.accentHue(45)),
      'section': TextStyle(color: Design.accentHue(45)),
      'function': TextStyle(color: Design.accentHue(45)),
    };

    return MarkdownConfig(
configs: <WidgetConfig>[
        PConfig(textStyle: TextStyle(color: text, fontSize: 13, height: 1.5)),
        heading(MarkdownTag.h1, 18,
            spacing: -0.2,
            divider: HeadingDivider(color: text.withAlpha(28), space: 6, height: 1),
            padding: const EdgeInsets.only(top: 12, bottom: 5)),
        heading(MarkdownTag.h2, 15.5,
            divider: HeadingDivider(color: text.withAlpha(20), space: 5, height: 1),
            padding: const EdgeInsets.only(top: 12, bottom: 4)),
        heading(MarkdownTag.h3, 14),
        heading(MarkdownTag.h4, 13, alpha: 225),
        heading(MarkdownTag.h5, 12, alpha: 195),
        heading(MarkdownTag.h6, 11.5, alpha: 150, spacing: 0.3),
        // `---` as a launcher hairline rather than the default 2px light bar.
        HrConfig(height: 1, color: text.withAlpha(28)),
        // Tighter indent + accent bullets (the default marker inherits a
        // theme text color that renders near-black on a dark backdrop).
        const ListConfig(marginLeft: 22, marker: _mdListMarker),
        // Task lists: accent check / muted empty box instead of a black icon.
        CheckBoxConfig(
          builder: (bool checked) => Padding(
            padding: const EdgeInsets.only(right: 5, top: 1),
            child: Icon(
              checked ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
              size: 15,
              color: checked ? accent : text.withAlpha(120),
            ),
          ),
        ),
        // Inline `code`: accent text on a faint accent fill.
        CodeConfig(
          style: TextStyle(
            color: accent,
            backgroundColor: accent.withAlpha(28),
            fontFamily: 'Consolas',
            fontSize: 12.5,
          ),
        ),
        // Fenced code blocks: theme-tinted syntax over a subtle panel.
        PreConfig(
          textStyle: const TextStyle(fontFamily: 'Consolas', fontSize: 12.5, height: 1.45),
          styleNotMatched: TextStyle(color: text),
          theme: codeTheme,
          decoration: BoxDecoration(
            color: text.withAlpha(14),
            border: Border.all(color: accent.withAlpha(30)),
            borderRadius: BorderRadius.circular(6),
          ),
          padding: const EdgeInsets.all(10),
        ),
        BlockquoteConfig(
          sideColor: accent.withAlpha(150),
          sideWith: 3,
          textColor: text.withAlpha(205),
          padding: const EdgeInsets.fromLTRB(12, 2, 0, 2),
        ),
        // Tables: the package default draws full-opacity text-colored grid
        // lines — soften to the launcher's hairline style with a tinted header.
        TableConfig(
          border: TableBorder.all(color: text.withAlpha(40)),
          headerRowDecoration: BoxDecoration(color: accent.withAlpha(18)),
          headerStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: accent),
          bodyStyle: TextStyle(fontSize: 12, color: text),
          headPadding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
          bodyPadding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
        ),
        LinkConfig(
          style: TextStyle(color: accent, decoration: TextDecoration.underline),
          onTap: (String url) {
            final String target = url.trim();
            if (target.isNotEmpty) WinUtils.open(target);
          },
        ),
        // The package default only loads http rasters / Flutter assets;
        // plugins reference local `file://` images (including generated SVGs).
        ImgConfig(builder: (String url, Map<String, String> attributes) => _markdownImage(url)),
      ],
    );
  }

  /// Renders a markdown image from a `file://` path or http(s) URL, with SVG
  /// support via flutter_svg, scaled down to the pane width.
  Widget _markdownImage(String url) {
    final String value = url.trim();
    final Widget broken = Icon(Icons.broken_image_rounded, size: 16, color: Design.text.withAlpha(90));
    final bool isSvg = Uri.tryParse(value)?.path.toLowerCase().endsWith('.svg') ?? false;
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
      final double? width = constraints.maxWidth.isFinite ? constraints.maxWidth : null;
      if (value.startsWith('http://') || value.startsWith('https://')) {
        return isSvg
            ? SvgPicture.network(value, width: width, errorBuilder: (_, __, ___) => broken)
            : Image.network(value, width: width, errorBuilder: (_, __, ___) => broken);
      }
      if (value.startsWith('file://')) {
        final File file = File(Uri.parse(value).toFilePath(windows: true));
        if (!file.existsSync()) return broken;
        return isSvg
            ? SvgPicture.file(file, width: width, errorBuilder: (_, __, ___) => broken)
            : Image.file(file, width: width, errorBuilder: (_, __, ___) => broken);
      }
      return broken;
    });
  }
}

/// A [HeadingConfig] with a caller-supplied tag, style, divider and padding —
/// the package's built-in `H1Config`…`H6Config` bake in article-sized styles
/// and a fixed light-gray underline, none of which suit the launcher.
class _MdHeadingConfig extends HeadingConfig {
  const _MdHeadingConfig({
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

/// Accent-tinted list markers: a filled dot / hollow ring / small square by
/// nesting depth for bullets, and dimmed accent numerals for ordered lists.
/// Vertical offsets are tuned to the 13px/1.5 body line so markers sit on the
/// first text line.
Widget _mdListMarker(bool isOrdered, int depth, int index) {
  if (isOrdered) {
    return Container(
      alignment: Alignment.topRight,
      padding: const EdgeInsets.only(right: 6, top: 1),
      child: Text(
        '${index + 1}.',
        style: TextStyle(
          fontSize: 12.5,
          height: 1.5,
          fontWeight: FontWeight.w600,
          color: Design.accent.withAlpha(210),
        ),
      ),
    );
  }
  final Color color = Design.accent.withAlpha(210);
  final BoxDecoration decoration = depth == 0
      ? BoxDecoration(color: color, shape: BoxShape.circle)
      : depth == 1
          ? BoxDecoration(border: Border.all(color: color, width: 1.2), shape: BoxShape.circle)
          : BoxDecoration(color: color.withAlpha(150), borderRadius: BorderRadius.circular(1));
  return Padding(
    padding: const EdgeInsets.only(right: 8, top: 7),
    child: Align(
      alignment: Alignment.topRight,
      child: Container(width: 5, height: 5, decoration: decoration),
    ),
  );
}

/// Resolves a plugin icon string to a widget: a `#RRGGBB` color swatch, a
/// Material icon name, a local `file://` image, or a remote `https://` image
/// (images fall back to the icon on error).
class _PluginIcon extends StatelessWidget {
  const _PluginIcon({required this.name, required this.accent, this.size = 16});
  final String? name;
  final Color accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    final String? value = name?.trim();
    final Color? swatch = parsePluginColor(value);
    if (swatch != null) {
      return Container(
        width: size + 4,
        height: size + 4,
        decoration: BoxDecoration(
          color: swatch,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: Design.text.withAlpha(40)),
        ),
      );
    }
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

/// A thin determinate bar shown under a list row that carries `"progress"`.
class _PluginProgressBar extends StatelessWidget {
  const _PluginProgressBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 3,
        child: LinearProgressIndicator(
          value: value,
          backgroundColor: Design.text.withAlpha(20),
          valueColor: AlwaysStoppedAnimation<Color>(Design.accent.withAlpha(200)),
        ),
      ),
    );
  }
}

/// Axis-free inline mini-chart used by metadata entries with `"sparkline"`.
class _PluginSparkline extends StatelessWidget {
  const _PluginSparkline({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(90, 16),
      painter: _SparklinePainter(values: values, color: color),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    double min = values.first, max = values.first;
    for (final double v in values) {
      if (v < min) min = v;
      if (v > max) max = v;
    }
    final double range = max - min;
    // Inset vertically so the stroke doesn't clip at the extremes.
    const double inset = 1.5;
    final double drawHeight = size.height - inset * 2;
    final Path line = Path();
    for (int i = 0; i < values.length; i++) {
      final double x = size.width * i / (values.length - 1);
      final double normalized = range == 0 ? 0.5 : (values[i] - min) / range;
      final double y = inset + drawHeight * (1 - normalized);
      if (i == 0) {
        line.moveTo(x, y);
      } else {
        line.lineTo(x, y);
      }
    }
    // Faint fill under the line, then the line itself.
    final Path fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = color.withAlpha(26));
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter oldDelegate) =>
      oldDelegate.color != color || !listEquals(oldDelegate.values, values);
}

/// Dense key-value rows shown under preview/detail markdown: label column on
/// the left, value (with optional icon, tint, and link) on the right.
class _PluginMetadataPane extends StatelessWidget {
  const _PluginMetadataPane({required this.entries, required this.topGap});

  final List<PluginMetadataEntry> entries;

  /// Whether markdown precedes the pane (adds a separating divider).
  final bool topGap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: topGap ? 10 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (topGap)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(height: 1, color: Design.text.withAlpha(18)),
            ),
          for (final PluginMetadataEntry entry in entries)
            if (entry.separator)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Container(height: 1, color: Design.text.withAlpha(18)),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2.5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: 90,
                      child: Text(
                        entry.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Design.text.withAlpha(120),
                          height: 1.35,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: _value(entry)),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _value(PluginMetadataEntry entry) {
    final Color valueColor = entry.color ?? Design.text.withAlpha(210);
    final Widget text = Text(
      entry.text,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: entry.url != null ? Design.accent : valueColor,
        decoration: entry.url != null ? TextDecoration.underline : null,
        height: 1.35,
      ),
    );
    final Widget value = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (entry.sparkline != null)
          Padding(
            padding: EdgeInsets.only(right: entry.text.isEmpty ? 0 : 6, top: 1),
            child: _PluginSparkline(values: entry.sparkline!, color: entry.color ?? Design.accent),
          ),
        if (entry.icon != null)
          Padding(
            padding: const EdgeInsets.only(right: 5, top: 1),
            child: Icon(PluginIcons.resolve(entry.icon), size: 12, color: entry.color ?? Design.accent),
          )
        else if (entry.color != null && entry.sparkline == null)
          Padding(
            padding: const EdgeInsets.only(right: 5, top: 4),
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: entry.color, shape: BoxShape.circle),
            ),
          ),
        Flexible(child: text),
      ],
    );
    if (entry.url == null) return value;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => WinUtils.open(entry.url!.trim()),
        child: value,
      ),
    );
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

    // A tileColor turns the tile into a filled swatch: text flips to black or
    // white for contrast, and selection becomes a contrast ring (an accent
    // border would clash with arbitrary swatch colors).
    final Color? tile = item.tileColor;
    final Color labelColor = tile == null ? onSurface : (tile.computeLuminance() > 0.5 ? Colors.black : Colors.white);

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
            color: tile ?? (isSelected ? accent.withAlpha(40) : onSurface.withAlpha(8)),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: tile != null
                  ? (isSelected ? labelColor.withAlpha(220) : labelColor.withAlpha(40))
                  : (isSelected ? accent.withAlpha(120) : onSurface.withAlpha(14)),
              width: tile != null && isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (tile == null || item.icon != null) _PluginIcon(name: item.icon, accent: accent, size: 22),
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
                    color: isSelected ? labelColor : labelColor.withAlpha(210),
                  ),
                ),
              ],
              if (item.subtitle.isNotEmpty)
                Text(
                  item.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 9, color: labelColor.withAlpha(130)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
