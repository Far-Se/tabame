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

class MainMenuAuroraWidget extends StatelessWidget {
  const MainMenuAuroraWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = Design.accent;
    final Color surface = theme.colorScheme.surface;
    final Color text = Design.text;
    final bool isDark = theme.brightness == Brightness.dark;
    final bool hasBackdrop = user.activeBackdropPath.isNotEmpty;

    // gradientAlpha is a free 0..255 "intensity" knob each design interprets;
    // Aurora uses it to scale how strongly the aurora wash and spine glow read.
    final double intensity = (Design.gradientAlpha.clamp(0, 255)) / 255.0;

    // Sibling hue, rotated off the accent, gives the wash its aurora two-tone
    // while staying entirely driven by the user's theme color.
    final HSLColor accentHsl = HSLColor.fromColor(accent);
    final Color auroraA = accent;
    final Color auroraB = accentHsl
        .withHue((accentHsl.hue + 58) % 360)
        .withSaturation((accentHsl.saturation * 0.92).clamp(0.0, 1.0))
        .toColor();

    final double r = Design.borderRadius;
    final BorderRadius shape = r == 0
        ? const BorderRadius.all(Radius.circular(0))
        : BorderRadius.only(
            topLeft: Radius.circular(r),
            bottomRight: Radius.circular(r),
            topRight: Radius.circular((r * 0.3) + 3),
            bottomLeft: Radius.circular((r * 0.3) + 3),
          );

    final Color panelBase = surface.withValues(alpha: hasBackdrop ? 0.74 : (isDark ? 0.96 : 0.97));
    final Color hairline = text.withValues(alpha: 0.08);

    // Panel-opacity fade points (shared "fade panel" feature across designs).
    final List<double> points = Design.panelOpacityPoints;
    final List<double> stops = <double>[];
    final List<Color> maskColors = <Color>[];
    for (int i = 0; i < points.length; i += 2) {
      stops.add(points[i]);
      maskColors.add(Colors.white.withValues(alpha: points[i + 1]));
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: 203,
        maxHeight: MediaQuery.of(context).size.height - 90,
      ),
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: shape,
          child: Stack(
            children: <Widget>[
              // ---- Aurora background wash ----
              Positioned.fill(
                child: RepaintBoundary(
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
                        color: panelBase,
                        borderRadius: shape,
                        border: Border.all(
                          color: isDark ? Colors.white.withValues(alpha: 0.07) : accent.withValues(alpha: 0.16),
                          width: 0.8,
                        ),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.34 : 0.12),
                            blurRadius: 30,
                            spreadRadius: -6,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Stack(
                        children: <Widget>[
                          // Drifting aurora blobs (top-left accent, bottom-right sibling).
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: RadialGradient(
                                  center: const Alignment(-0.95, -1.1),
                                  radius: 1.25,
                                  colors: <Color>[
                                    auroraA.withValues(alpha: (0.10 + intensity * 0.26).clamp(0.0, 1.0)),
                                    auroraA.withValues(alpha: 0.0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: RadialGradient(
                                  center: const Alignment(1.15, 1.2),
                                  radius: 1.35,
                                  colors: <Color>[
                                    auroraB.withValues(alpha: (0.08 + intensity * 0.22).clamp(0.0, 1.0)),
                                    auroraB.withValues(alpha: 0.0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Soft top sheen.
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.center,
                                  colors: <Color>[
                                    Colors.white.withValues(alpha: isDark ? 0.05 : 0.16),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (Design.hasBackdrop) const StableBackdrop(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ---- Luminous left spine ----
              _AuroraSpine(accent: accent, intensity: intensity),

              // ---- Foreground content ----
              RepaintBoundary(
                child: Padding(
                  // Clear the spine on the left edge.
                  padding: const EdgeInsets.only(left: 8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (!user.quickActionsAtBottom) ...<Widget>[
                        Container(
                          padding: const EdgeInsets.fromLTRB(4, 6, 10, 6),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: <Color>[
                                accent.withValues(alpha: (0.05 + intensity * 0.06).clamp(0.0, 1.0)),
                                Colors.transparent,
                              ],
                            ),
                          ),
                          child: const TopBar(),
                        ),
                        Divider(thickness: 0.6, height: 1, color: hairline),
                      ] else if (user.bottomBarOnTop)
                        const PinnedAndTrayList()
                      else
                        const SizedBox(height: 4),

                      // The window switcher, recessed into an instrument-screen well.
                      Padding(
                        padding: const EdgeInsets.fromLTRB(6, 6, 8, 4),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: isDark ? Colors.black.withValues(alpha: 0.18) : text.withValues(alpha: 0.035),
                            borderRadius: BorderRadius.circular((r * 0.5) + 8),
                            border: Border.all(color: accent.withValues(alpha: 0.10)),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 3),
                            child: TaskBar(),
                          ),
                        ),
                      ),

                      if (!user.bottomBarOnTop) const PinnedAndTrayList(),
                      if (user.taskManagerStats) const TaskbarStats(withTopDivider: false),
                      if (user.libreStats) const LibreStats(withTopDivider: false),
                      Container(
                        padding: const EdgeInsets.fromLTRB(0, 4, 4, 7),
                        child: const BottomBar(),
                      ),
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

class _AuroraSpine extends StatelessWidget {
  const _AuroraSpine({required this.accent, required this.intensity});

  final Color accent;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      top: 14,
      bottom: 14,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Live pip.
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(left: 1, bottom: 4),
            decoration: BoxDecoration(
              color: accent,
              shape: BoxShape.circle,
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: accent.withValues(alpha: (0.4 + intensity * 0.4).clamp(0.0, 1.0)),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              width: 3,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    accent.withValues(alpha: (0.7 + intensity * 0.25).clamp(0.0, 1.0)),
                    accent.withValues(alpha: 0.18),
                  ],
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: accent.withValues(alpha: (0.18 + intensity * 0.3).clamp(0.0, 1.0)),
                    blurRadius: 9,
                    spreadRadius: 0.5,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
