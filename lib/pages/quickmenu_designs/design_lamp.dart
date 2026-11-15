import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../models/quick_menu_bar_layout.dart';
import '../../models/settings.dart';
import '../../widgets/quickmenu/bottom_bar.dart';
import '../../widgets/quickmenu/info_bar.dart';
import '../../widgets/quickmenu/libre_stats.dart';
import '../../widgets/quickmenu/task_bar.dart';
import '../../widgets/quickmenu/taskbar_stats.dart';
import '../../widgets/quickmenu/top_bar.dart';
import '../../widgets/widgets/glass_surface.dart';
import 'lamp_surface.dart';

/// A desk under one lamp. The middle of the panel stays evenly lit so window
/// titles, pins, and audio stay one contrast; the corners recede, and the top
/// edge warms after dusk. The bars themselves are the standard QuickMenu.
class MainMenuLampWidget extends StatelessWidget {
  const MainMenuLampWidget({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final bool dark = Design.background.computeLuminance() < 0.5;
    final bool highContrast = MediaQuery.highContrastOf(context);
    final Color pool = Design.background;
    final Color accent = Design.accent;
    final double radius = Design.borderRadius;
    final QuickMenuBarLayout layout = user.quickMenuBarLayout;
    final Color hairline = Design.text.withValues(alpha: dark ? 0.10 : 0.08);
    final Color borderColor = highContrast ? Design.text : Design.text.withValues(alpha: dark ? 0.18 : 0.14);
    final bool topActions = !layout.quickActionsAtBottom && layout.hasContentAtTop;

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: 203,
        maxHeight: MediaQuery.sizeOf(context).height - 30,
      ),
      child: RepaintBoundary(
        child: GlassClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: LampSurface(
            pool: pool,
            shadow: lampShadow(pool, dark: dark),
            lip: lampLip(pool, accent, dark: dark),
            dark: dark,
            includeBackdrop: Design.hasBackdrop,
            surfaceOpacity: Design.hasBackdrop ? 0.86 : 1,
            child: Stack(
              children: <Widget>[
                Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _ShadeGrabber(color: Design.text.withValues(alpha: dark ? 0.40 : 0.28)),
                    if (topActions) ...<Widget>[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(6, 0, 8, 4),
                        child: TopBar(),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _Hairline(color: hairline),
                      ),
                    ],
                    if (layout.pinnedTrayAtTop && layout.quickActionsAtBottom)
                      const PinnedAndTrayList()
                    else
                      const SizedBox(height: 2),
                    const TaskBar(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 3, 16, 3),
                      child: _Hairline(color: hairline),
                    ),
                    if (layout.hasContentAtBottom) const PinnedAndTrayList.atBottom(),
                    if (user.taskManagerStats) const TaskbarStats(),
                    if (user.libreStats) const LibreStats(),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(2, 2, 4, 6),
                      child: BottomBar(),
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

class _ShadeGrabber extends StatelessWidget {
  const _ShadeGrabber({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 13,
      child: DragToMoveArea(
        child: Center(
          child: Container(
            width: 36,
            height: 3,
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.all(Radius.circular(3)),
            ),
          ),
        ),
      ),
    );
  }
}

class _Hairline extends StatelessWidget {
  const _Hairline({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: color,
      child: const SizedBox(height: 1, width: double.infinity),
    );
  }
}
