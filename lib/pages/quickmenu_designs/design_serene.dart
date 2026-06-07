import 'dart:ui';

import 'package:flutter/material.dart';

import '../../models/settings.dart';
import '../../models/util/theme_colors.dart';
import '../../widgets/quickmenu/bottom_bar.dart';
import 'design_backdrop_stable.dart';
import '../../widgets/quickmenu/info_bar.dart';
import '../../widgets/quickmenu/libre_stats.dart';
import '../../widgets/quickmenu/task_bar.dart';
import '../../widgets/quickmenu/taskbar_stats.dart';
import '../../widgets/quickmenu/top_bar.dart';

class MainMenuSereneWidget extends StatelessWidget {
  const MainMenuSereneWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = userSettings.themeColors.accent;
    final Color surface = theme.colorScheme.surface;
    final bool isDark = theme.brightness == Brightness.dark;

    final List<double> points = userSettings.themeColors.panelOpacityPoints;
    final List<double> stops = <double>[];
    final List<Color> maskColors = <Color>[];
    for (int i = 0; i < points.length; i += 2) {
      stops.add(points[i]);
      maskColors.add(Colors.white.withValues(alpha: points[i + 1]));
    }

    final double radius = User.theme.borderRadius;
    final double tintStrength = (userSettings.themeColors.gradientAlpha.clamp(0, 255)) / 255.0;
    final double baseAlpha = userSettings.activeBackdropPath.isNotEmpty ? 0.72 : 0.88;
    final Color panelBase = surface.withValues(alpha: baseAlpha);

    final Color glowColor = Color.alphaBlend(
      accent.withValues(alpha: 0.10 + tintStrength * 0.14),
      surface,
    );

    final Color borderColor = isDark ? Colors.white.withValues(alpha: 0.10) : Colors.white.withValues(alpha: 0.70);

    final Color dividerColor = theme.colorScheme.onSurface.withValues(alpha: 0.07);

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
              // ── Layer 0: backdrop image ──────────────────────────────────
              // Lives OUTSIDE the BackdropFilter so the blur never
              // re-snapshots it.  Tooltip repaints or any other dirty-region
              // above this layer cannot cause it to flicker.

              // ── Layer 1: frosted-glass panel ─────────────────────────────
              // BackdropFilter now only sees Layer 0 (the backdrop image or
              // the window content behind the panel) — never the UI content
              // column, which is promoted to Layer 2.
              Positioned.fill(
                child: RepaintBoundary(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                    child: ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (Rect bounds) {
                        return LinearGradient(
                          begin: panelAlignmentMap[userSettings.themeColors.panelOpacityBegin] ?? Alignment.topCenter,
                          end: panelAlignmentMap[userSettings.themeColors.panelOpacityEnd] ?? Alignment.bottomCenter,
                          colors: maskColors,
                          stops: stops,
                        ).createShader(bounds);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(radius),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.10),
                              blurRadius: 32,
                              spreadRadius: -4,
                              offset: const Offset(0, 6),
                            ),
                          ],
                          gradient: RadialGradient(
                            center: const Alignment(-0.6, -0.7),
                            radius: 1.4,
                            colors: <Color>[glowColor, panelBase],
                          ),
                          border: Border.all(color: borderColor, width: 0.8),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              const StableBackdrop(),

              // ── Layer 2: UI content ───────────────────────────────────────
              // Promoted to its own RepaintBoundary so tooltip hovers,
              // hover-state changes, or any widget repaint here cannot
              // propagate down into the BackdropFilter's snapshot region.
              RepaintBoundary(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (!userSettings.quickActionsAtBottom) ...<Widget>[
                      Container(
                        padding: const EdgeInsets.fromLTRB(4, 5, 10, 6),
                        child: const TopBar(),
                      ),
                      _Hairline(color: dividerColor),
                    ] else if (userSettings.bottomBarOnTop)
                      const PinnedAndTrayList()
                    else
                      const SizedBox(height: 3),
                    const TaskBar(),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: _Hairline(color: dividerColor),
                    ),
                    if (!userSettings.bottomBarOnTop) const PinnedAndTrayList(),
                    if (userSettings.taskManagerStats) const TaskbarStats(),
                    if (userSettings.libreStats) const LibreStats(),
                    Container(
                      padding: const EdgeInsets.fromLTRB(0, 4, 2, 6),
                      child: const BottomBar(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hairline extends StatelessWidget {
  final Color color;
  const _Hairline({required this.color});

  @override
  Widget build(BuildContext context) {
    return Divider(thickness: 0.6, height: 1, color: color);
  }
}
