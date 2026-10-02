import 'package:flutter/material.dart';

import '../../models/classes/boxes.dart';
import '../../models/globals.dart';
import '../../models/quick_menu_bar_layout.dart';
import '../../models/settings.dart';
import 'quick_menu_bar_contents.dart';

class PinnedAndTrayList extends StatelessWidget {
  const PinnedAndTrayList({
    super.key,
    this.includeQuickActions = true,
    this.position,
    this.hideWhenQuickActionsAtTop = true,
  });

  const PinnedAndTrayList.atBottom({
    super.key,
    this.includeQuickActions = true,
    this.hideWhenQuickActionsAtTop = true,
  }) : position = QuickMenuBarPosition.bottom;

  /// Some designs have a custom action surface and only want the pinned/tray
  /// side of a merged group in this shelf.
  final bool includeQuickActions;

  /// Defaults to the pinned/tray position for existing top and bottom slots.
  final QuickMenuBarPosition? position;
  final bool hideWhenQuickActionsAtTop;

  @override
  Widget build(BuildContext context) {
    final QuickMenuBarLayout layout = user.quickMenuBarLayout;
    final QuickMenuBarPosition resolvedPosition =
        position ?? (layout.hasPinnedTrayAtTop ? QuickMenuBarPosition.top : QuickMenuBarPosition.bottom);
    if (resolvedPosition == QuickMenuBarPosition.top && hideWhenQuickActionsAtTop && layout.quickActionsAtTop) {
      // TopBar owns every group placed at the top when its quick-actions group
      // is there, including separately selected pinned/tray groups.
      return const SizedBox.shrink();
    }

    final bool hasContent = layout.groupsAt(resolvedPosition).any((QuickMenuBarGroup group) {
      return group.items.any((QuickMenuBarItem item) {
        if (item == QuickMenuBarItem.quickActions) return includeQuickActions;
        if (item == QuickMenuBarItem.pinnedApps) return Boxes.pinnedApps.isNotEmpty;
        return user.showTrayBar;
      });
    });
    if (!hasContent) return const SizedBox.shrink();

    final double height = user.expandedTaskbar ? 32 : 27;
    if (resolvedPosition == QuickMenuBarPosition.top) Globals.heights.topbar = height;
    Globals.heights.pinnedAndTray = (user.taskManagerStats || user.libreStats) ? height * 2 : height;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Padding(
        padding:
            !user.expandedTaskbar ? const EdgeInsets.fromLTRB(7, 3, 3, 3) : const EdgeInsets.symmetric(horizontal: 10),
        child: QuickMenuBarContents(
          position: resolvedPosition,
          includeQuickActions: includeQuickActions,
        ),
      ),
    );
  }
}
