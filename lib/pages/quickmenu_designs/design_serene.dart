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
    final Color accent = Design.accent;
    final Color surface = theme.colorScheme.surface;
    final bool isDark = theme.brightness == Brightness.dark;

    final List<double> points = Design.panelOpacityPoints;
    final List<double> stops = <double>[];
    final List<Color> maskColors = <Color>[];
    for (int i = 0; i < points.length; i += 2) {
      stops.add(points[i]);
      maskColors.add(Colors.white.withValues(alpha: points[i + 1]));
    }

    final double radius = Design.borderRadius;
    final double tintStrength = (Design.gradientAlpha.clamp(0, 255)) / 255.0;
    final double baseAlpha = user.activeBackdropPath.isNotEmpty ? 0.72 : 0.88;
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
              Positioned.fill(
                child: RepaintBoundary(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                    child: ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (Rect bounds) {
                        return LinearGradient(
                          begin: panelAlignmentMap[Design.panelOpacityBegin] ?? Alignment.topCenter,
                          end: panelAlignmentMap[Design.panelOpacityEnd] ?? Alignment.bottomCenter,
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
              if (Design.hasBackdrop) const StableBackdrop(),
              RepaintBoundary(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (!user.quickActionsAtBottom) ...<Widget>[
                      Container(
                        padding: const EdgeInsets.fromLTRB(4, 5, 10, 6),
                        child: const TopBar(),
                      ),
                      _Hairline(color: dividerColor),
                    ] else if (user.bottomBarOnTop)
                      const PinnedAndTrayList()
                    else
                      const SizedBox(height: 3),
                    const TaskBar(),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: _Hairline(color: dividerColor),
                    ),
                    if (!user.bottomBarOnTop) const PinnedAndTrayList(),
                    if (user.taskManagerStats) const TaskbarStats(),
                    if (user.libreStats) const LibreStats(),
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
