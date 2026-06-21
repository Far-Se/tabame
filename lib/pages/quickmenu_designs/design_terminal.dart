import 'package:flutter/material.dart';

import '../../models/settings.dart';
import '../../models/util/theme_colors.dart';
import '../../widgets/quickmenu/bottom_bar.dart';
import '../../widgets/quickmenu/info_bar.dart';
import '../../widgets/quickmenu/libre_stats.dart';
import '../../widgets/quickmenu/task_bar.dart';
import '../../widgets/quickmenu/taskbar_stats.dart';
import '../../widgets/quickmenu/top_bar.dart';
import '../launcher/launcher_design.dart';
import 'design_backdrop_stable.dart';

class MainMenuTerminalWidget extends StatelessWidget {
  const MainMenuTerminalWidget({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // register as theme-dependent so Design.* values update live
    final Color accent = Design.accent;
    final double radius = Design.borderRadius;

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: 203,
        maxHeight: MediaQuery.of(context).size.height - 90,
      ),
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(
            children: <Widget>[
              // Console surface — semi-transparent when a backdrop is active.
              Positioned.fill(
                child: RepaintBoundary(
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (Rect bounds) {
                      final List<double> points = Design.panelOpacityPoints;
                      final List<double> stops = <double>[];
                      final List<Color> colors = <Color>[];
                      for (int i = 0; i < points.length; i += 2) {
                        stops.add(points[i]);
                        colors.add(Colors.white.withValues(alpha: points[i + 1]));
                      }
                      return LinearGradient(
                        begin: panelAlignmentMap[Design.panelOpacityBegin] ?? Alignment.topCenter,
                        end: panelAlignmentMap[Design.panelOpacityEnd] ?? Alignment.bottomCenter,
                        colors: colors,
                        stops: stops,
                      ).createShader(bounds);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Design.background.withValues(
                          alpha: user.activeBackdropPath.isNotEmpty ? 0.82 : 1.0,
                        ),
                        border: Border.all(color: accent.withAlpha(70), width: 1.0),
                      ),
                      child: Design.hasBackdrop ? const Stack(children: <Widget>[StableBackdrop()]) : null,
                    ),
                  ),
                ),
              ),
              // Left accent rail (TUI frame left edge).
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(width: 3, color: accent.withAlpha(100)),
              ),
              // Content, inset past the rail.
              RepaintBoundary(
                child: Padding(
                  padding: const EdgeInsets.only(left: 3),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const _TerminalTitleBar(),
                      _TerminalHairline(accent: accent),
                      const TaskBar(),
                      _TerminalHairline(accent: accent),
                      if (!user.bottomBarOnTop) const PinnedAndTrayList(),
                      if (user.taskManagerStats) const TaskbarStats(),
                      if (user.libreStats) const LibreStats(),
                      _TerminalStatusBar(accent: accent),
                    ],
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

// ---------------------------------------------------------------------------
// Chrome helpers
// ---------------------------------------------------------------------------

class _TerminalTitleBar extends StatelessWidget {
  const _TerminalTitleBar();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: TerminalTokens.chrome,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(3, 3, 8, 3),
        child: user.bottomBarOnTop ? const PinnedAndTrayList() : const TopBar(),
      ),
    );
  }
}

class _TerminalHairline extends StatelessWidget {
  const _TerminalHairline({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: accent.withAlpha(40));
  }
}

class _TerminalStatusBar extends StatelessWidget {
  const _TerminalStatusBar({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: TerminalTokens.chrome,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(height: 1, color: accent.withAlpha(40)),
          const BottomBar(),
        ],
      ),
    );
  }
}
