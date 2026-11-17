import 'package:flutter/material.dart';

import '../../models/quick_menu_bar_layout.dart';
import '../../models/settings.dart';
import '../../widgets/quickmenu/bottom_bar.dart';
import '../../widgets/quickmenu/info_bar.dart';
import '../../widgets/quickmenu/libre_stats.dart';
import '../../widgets/quickmenu/task_bar.dart';
import '../../widgets/quickmenu/taskbar_stats.dart';
import '../../widgets/quickmenu/top_bar.dart';
import '../../widgets/widgets/glass_surface.dart';
import 'void_surface.dart';

/// Three matte terraces – tools, windows, status – on one tinted neutral.
/// The window list keeps the plain ground, so the part you read is the
/// quietest part and colour is left to the app icons you are looking for.
class MainMenuVoidWidget extends StatelessWidget {
  const MainMenuVoidWidget({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final bool dark = Design.background.computeLuminance() < 0.5;
    final bool highContrast = MediaQuery.highContrastOf(context);
    final Color ink = Design.text;
    final double radius = Design.borderRadius;
    final QuickMenuBarLayout layout = user.quickMenuBarLayout;
    final Color shelf = highContrast ? Colors.transparent : voidShelf(ink, dark: dark);
    final Color rule = highContrast ? ink : voidRule(ink, dark: dark);
    final Color borderColor = highContrast ? ink : ink.withValues(alpha: dark ? 0.16 : 0.13);
    final bool topActions = !layout.quickActionsAtBottom && layout.hasContentAtTop;
    final bool topPins = layout.pinnedTrayAtTop && layout.quickActionsAtBottom;

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: 190,
        maxHeight: MediaQuery.sizeOf(context).height - 30,
      ),
      child: RepaintBoundary(
        child: GlassClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: VoidSurface(
            ground: Design.background,
            dark: dark,
            wash: Design.gradientAlpha.clamp(0, 255) / 255,
            includeBackdrop: Design.hasBackdrop,
            surfaceOpacity: Design.hasBackdrop ? 0.86 : 1,
            child: Stack(
              children: <Widget>[
                Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (topActions || topPins)
                      _Shelf(
                        color: shelf,
                        rule: rule,
                        ruleBelow: true,
                        children: <Widget>[
                          if (topActions)
                            const Padding(
                              padding: EdgeInsets.fromLTRB(6, 5, 8, 4),
                              child: TopBar(),
                            ),
                          if (topPins) const PinnedAndTrayList(),
                        ],
                      ),
                    SizedBox(height: topActions || topPins ? 3 : 5),
                    const TaskBar(),
                    const SizedBox(height: 3),
                    _Shelf(
                      color: shelf,
                      rule: rule,
                      ruleBelow: false,
                      children: <Widget>[
                        if (layout.hasContentAtBottom) const PinnedAndTrayList.atBottom(),
                        if (user.taskManagerStats) const TaskbarStats(),
                        if (user.libreStats) const LibreStats(),
                        const Padding(
                          padding: EdgeInsets.fromLTRB(2, 2, 4, 5),
                          child: BottomBar(),
                        ),
                      ],
                    ),
                  ],
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(radius),
                        border: Border.all(color: borderColor, width: highContrast ? 2 : 1),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A terrace: a faint tone step closed by one sharp rule on its inner edge.
class _Shelf extends StatelessWidget {
  const _Shelf({
    required this.color,
    required this.rule,
    required this.ruleBelow,
    required this.children,
  });

  final Color color;
  final Color rule;
  final bool ruleBelow;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final BorderSide edge = BorderSide(color: rule);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        border: Border(
          top: ruleBelow ? BorderSide.none : edge,
          bottom: ruleBelow ? edge : BorderSide.none,
        ),
      ),
      child: Padding(
        // Keep the content clear of the rule drawn on the box edge.
        padding: EdgeInsets.only(top: ruleBelow ? 0 : 1, bottom: ruleBelow ? 1 : 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}
