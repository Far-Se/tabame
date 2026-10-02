import 'package:flutter/material.dart';

import '../../models/globals.dart';
import '../../models/quick_menu_bar_layout.dart';
import '../../models/settings.dart';
import 'quick_menu_bar_contents.dart';

class TopBar extends StatelessWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final QuickMenuBarLayout layout = user.quickMenuBarLayout;
    if (layout.quickActionsAtBottom || !layout.hasContentAtTop) return const SizedBox.shrink();

    Globals.heights.topbar = 25;
    return Theme(
      data: Theme.of(context).copyWith(
        iconTheme: IconThemeData(size: 16, color: Theme.of(context).iconTheme.color),
        hoverColor: Colors.grey.withAlpha(50),
        tooltipTheme: Theme.of(context)
            .tooltipTheme
            .copyWith(decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface), preferBelow: false),
      ),
      child: const SizedBox(
        height: 25,
        child: QuickMenuBarContents(position: QuickMenuBarPosition.top),
      ),
    );
  }
}
