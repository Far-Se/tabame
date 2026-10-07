import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../models/classes/boxes.dart';
import '../../models/globals.dart';
import '../../models/quick_menu_bar_layout.dart';
import '../../models/settings.dart';
import '../itzy/quickmenu/list_pinned_apps.dart';
import '../itzy/quickmenu/button_changelog.dart';
import '../itzy/quickmenu/button_logo_drag.dart';
import '../itzy/quickmenu/button_open_settings.dart';
import 'quick_actions_bar.dart';
import 'tray_bar.dart';
import '../widgets/bar_with_buttons.dart';

class QuickMenuBarContents extends StatefulWidget {
  const QuickMenuBarContents({
    super.key,
    required this.position,
    this.includeQuickActions = true,
  });

  final QuickMenuBarPosition position;
  final bool includeQuickActions;

  @override
  State<QuickMenuBarContents> createState() => _QuickMenuBarContentsState();
}

class _QuickMenuBarContentsState extends State<QuickMenuBarContents> with QuickMenuTriggers {
  @override
  void initState() {
    super.initState();
    QuickMenuFunctions.addListener(this);
  }

  @override
  void dispose() {
    QuickMenuFunctions.removeListener(this);
    super.dispose();
  }

  @override
  Future<void> refreshQuickMenu() async {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final QuickMenuBarLayout layout = user.quickMenuBarLayout;
    final List<QuickMenuBarGroup> groups = <QuickMenuBarGroup>[];
    for (final QuickMenuBarGroup group in layout.groupsAt(widget.position)) {
      final List<QuickMenuBarItem> visibleItems = group.items.where((QuickMenuBarItem item) {
        if (item == QuickMenuBarItem.quickActions) return widget.includeQuickActions;
        if (item == QuickMenuBarItem.pinnedApps) return Boxes.pinnedApps.isNotEmpty;
        return user.showTrayBar;
      }).toList();
      if (visibleItems.isNotEmpty) {
        groups.add(QuickMenuBarGroup(items: visibleItems, position: widget.position));
      }
    }

    if (groups.isEmpty) return const SizedBox.shrink();
    if (layout.mergeMode == QuickMenuMergeMode.all && widget.includeQuickActions) {
      return _buildAllMergedGroup(groups.single);
    }

    final List<QuickMenuBarItem> items = groups.expand((QuickMenuBarGroup group) => group.items).toList();
    return _AdaptiveBarRow(
      textDirection: Directionality.of(context),
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      children: <Widget>[
        for (final QuickMenuBarItem item in items)
          KeyedSubtree(
            key: ValueKey<QuickMenuBarItem>(item),
            child: switch (item) {
              QuickMenuBarItem.quickActions => QuickActionsBar(
                  isTop: widget.position == QuickMenuBarPosition.top,
                  shrinkWrap: true,
                ),
              QuickMenuBarItem.pinnedApps => const PinnedApps(),
              QuickMenuBarItem.trayIcons => const TrayBar(),
            },
          ),
      ],
    );
  }

  Widget _buildAllMergedGroup(QuickMenuBarGroup group) {
    final bool isTop = widget.position == QuickMenuBarPosition.top;
    return Theme(
      data: Theme.of(context).copyWith(
        iconTheme: IconThemeData(size: 16, color: Theme.of(context).iconTheme.color),
        hoverColor: Colors.grey.withAlpha(50),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (isTop) const LogoDragButton(),
          if (isTop) const SizedBox(width: 4),
          Expanded(
            child: _AdaptiveBarRow(
              textDirection: Directionality.of(context),
              devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
              children: <Widget>[
                for (final QuickMenuBarItem item in group.items)
                  KeyedSubtree(
                    key: ValueKey<QuickMenuBarItem>(item),
                    child: switch (item) {
                      QuickMenuBarItem.quickActions => BarWithButtons(
                          shrinkWrap: true,
                          height: user.expandedTaskbar ? 32 : 27,
                          children: <Widget>[QuickActionsBar(isTop: isTop, allMerged: true)],
                        ),
                      QuickMenuBarItem.pinnedApps => const PinnedApps(),
                      QuickMenuBarItem.trayIcons => const TrayBar(),
                    },
                  ),
              ],
            ),
          ),
          if (user.lastChangelog != Globals.version) const CheckChangelogButton(),
          const OpenSettingsButton(),
          const SizedBox(width: 2),
        ],
      ),
    );
  }
}

/// Fits small categories to their contents and shares the remaining width
/// equally between categories that still need more room.
class _AdaptiveBarRow extends MultiChildRenderObjectWidget {
  const _AdaptiveBarRow({required this.textDirection, required this.devicePixelRatio, required super.children});

  final TextDirection textDirection;
  final double devicePixelRatio;

  @override
  _RenderAdaptiveBarRow createRenderObject(BuildContext context) =>
      _RenderAdaptiveBarRow(textDirection, devicePixelRatio);

  @override
  void updateRenderObject(BuildContext context, _RenderAdaptiveBarRow renderObject) {
    renderObject.textDirection = textDirection;
    renderObject.devicePixelRatio = devicePixelRatio;
  }
}

class _BarParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderAdaptiveBarRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _BarParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _BarParentData> {
  _RenderAdaptiveBarRow(this._textDirection, this._devicePixelRatio);

  TextDirection _textDirection;
  double _devicePixelRatio;

  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    markNeedsLayout();
  }

  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _BarParentData) {
      child.parentData = _BarParentData();
    }
  }

  @override
  void performLayout() {
    size = constraints.biggest;
    final BoxConstraints measuringConstraints = BoxConstraints(
      maxWidth: size.width,
      minHeight: size.height,
      maxHeight: size.height,
    );
    final List<RenderBox> children = getChildrenAsList();
    // Dry measurement must not resize live scroll viewports: a temporary wider
    // viewport can clamp their scroll offsets and trigger visible corrections.
    final Map<RenderBox, double> naturalWidths = <RenderBox, double>{
      for (final RenderBox child in children)
        child: (child.getDryLayout(measuringConstraints).width * _devicePixelRatio).ceil() / _devicePixelRatio,
    };
    final List<RenderBox> byWidth = List<RenderBox>.of(children)
      ..sort((RenderBox a, RenderBox b) => naturalWidths[a]!.compareTo(naturalWidths[b]!));
    final Map<RenderBox, double> widths = <RenderBox, double>{};
    double remainingWidth = (size.width * _devicePixelRatio).floor() / _devicePixelRatio;
    int remainingCount = byWidth.length;
    for (final RenderBox child in byWidth) {
      final double share = (remainingWidth * _devicePixelRatio / remainingCount).floor() / _devicePixelRatio;
      final double width = naturalWidths[child]!.clamp(0.0, share);
      widths[child] = width;
      remainingWidth = (remainingWidth - width).clamp(0.0, size.width);
      remainingCount--;
    }

    double offset =
        _textDirection == TextDirection.ltr ? 0 : (size.width * _devicePixelRatio).floor() / _devicePixelRatio;
    for (final RenderBox child in children) {
      final double width = widths[child]!;
      child.layout(measuringConstraints.copyWith(maxWidth: width), parentUsesSize: true);
      if (_textDirection == TextDirection.rtl) offset -= width;
      final _BarParentData parentData = child.parentData! as _BarParentData;
      parentData.offset = Offset(offset, 0);
      if (_textDirection == TextDirection.ltr) offset += width;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
