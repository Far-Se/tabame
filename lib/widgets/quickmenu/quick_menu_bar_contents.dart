import 'package:flutter/material.dart';

import '../../models/classes/boxes.dart';
import '../../models/globals.dart';
import '../../models/quick_menu_bar_layout.dart';
import '../../models/settings.dart';
import '../itzy/quickmenu/list_pinned_apps.dart';
import '../itzy/quickmenu/button_changelog.dart';
import '../itzy/quickmenu/button_logo_drag.dart';
import '../itzy/quickmenu/button_open_settings.dart';
import '../widgets/bar_with_buttons.dart';
import 'quick_actions_bar.dart';
import 'tray_bar.dart';
import '../widgets/windows_scroll.dart';

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

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final QuickMenuBarGroup group in groups)
          Expanded(
            flex: group.items.length * 4,
            child: _buildGroup(group),
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
            child: BarWithButtons(
              height: user.expandedTaskbar ? 32 : 27,
              children: <Widget>[
                if (group.contains(QuickMenuBarItem.quickActions)) QuickActionsBar(isTop: isTop, allMerged: true),
                if (group.contains(QuickMenuBarItem.pinnedApps)) const PinnedApps(wrapScroll: false),
                if (group.contains(QuickMenuBarItem.trayIcons)) const TrayBar(wrapScroll: false),
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

  Widget _buildGroup(QuickMenuBarGroup group) {
    final bool hasQuickActions = group.contains(QuickMenuBarItem.quickActions);
    final bool hasPinnedApps = group.contains(QuickMenuBarItem.pinnedApps);
    final bool hasTrayIcons = group.contains(QuickMenuBarItem.trayIcons);

    if (hasQuickActions && (hasPinnedApps || hasTrayIcons)) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            flex: 6,
            child: QuickActionsBar(isTop: widget.position == QuickMenuBarPosition.top),
          ),
          Expanded(
            flex: 4,
            child: _buildPinnedAndTray(hasPinnedApps: hasPinnedApps, hasTrayIcons: hasTrayIcons, merged: true),
          ),
        ],
      );
    }

    if (hasQuickActions) return QuickActionsBar(isTop: widget.position == QuickMenuBarPosition.top);
    return _buildPinnedAndTray(
      hasPinnedApps: hasPinnedApps,
      hasTrayIcons: hasTrayIcons,
      merged: hasPinnedApps && hasTrayIcons,
    );
  }

  Widget _buildPinnedAndTray({required bool hasPinnedApps, required bool hasTrayIcons, required bool merged}) {
    if (hasPinnedApps && hasTrayIcons && merged) {
      return const ClipRRect(child: _MergedPinnedTray());
    }
    if (hasPinnedApps && hasTrayIcons) {
      return const Row(
        children: <Widget>[
          Expanded(child: PinnedApps()),
          Expanded(child: TrayBar()),
        ],
      );
    }
    if (hasPinnedApps) return const PinnedApps();
    if (hasTrayIcons) return const TrayBar();
    return const SizedBox.shrink();
  }
}

class _MergedPinnedTray extends StatelessWidget {
  const _MergedPinnedTray();

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ShaderMask(
        shaderCallback: (Rect rect) => const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: <Color>[Colors.transparent, Colors.transparent, Color.fromARGB(255, 0, 0, 0)],
          stops: <double>[0.0, 0.93, 1.0],
        ).createShader(rect),
        blendMode: BlendMode.dstOut,
        child: WindowsScrollView(
          scrollDirection: Axis.horizontal,
          showScrollbar: false,
          draggable: true,
          clipBehavior: Clip.hardEdge,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const PinnedApps(wrapScroll: false),
              if (user.showTrayBar) const TrayBar(wrapScroll: false),
            ],
          ),
        ),
      ),
    );
  }
}
