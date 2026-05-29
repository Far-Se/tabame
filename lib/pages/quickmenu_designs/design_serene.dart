import 'dart:ui';

import 'package:flutter/material.dart';

import '../../models/settings.dart';
import '../../models/util/theme_colors.dart';
import '../../widgets/quickmenu/bottom_bar.dart';
import '../../widgets/quickmenu/design_backdrop.dart';
import '../../widgets/quickmenu/info_bar.dart';
import '../../widgets/quickmenu/task_bar.dart';
import '../../widgets/quickmenu/taskbar_stats.dart';
import '../../widgets/quickmenu/top_bar.dart';

/// A calm, unified frosted-glass panel.
///
/// Architecture mirrors [MainMenuInterfaceWidget] — one ClipRRect shell,
/// background layer + foreground column — but the aesthetic shifts toward
/// a soft, luminous Serene-like feel:
///
///  - Single panel with no floating card sub-sections.
///  - `BackdropFilter` blur on the whole shell for a frosted-glass look.
///  - Background is a gentle radial glow from the accent colour, not a
///    flat gradient or a grid.
///  - Dividers are nearly invisible hairlines — present for rhythm, not noise.
///  - Outer shell has a translucent specular border and a single diffused
///    shadow; no inner accent border.
class MainMenuSereneWidget extends StatelessWidget {
  const MainMenuSereneWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = userSettings.themeColors.accentColor;
    final Color surface = theme.colorScheme.surface;
    final bool isDark = theme.brightness == Brightness.dark;

    // Opacity mask — reuse the user's panel opacity points exactly like the
    // other designs do, so the fade-out behaviour is consistent.
    final List<double> points = userSettings.themeColors.panelOpacityPoints;
    final List<double> stops = <double>[];
    final List<Color> maskColors = <Color>[];
    for (int i = 0; i < points.length; i += 2) {
      stops.add(points[i]);
      maskColors.add(Colors.white.withValues(alpha: points[i + 1]));
    }

    final double radius = User.theme.borderRadius;

    // How strongly the accent tints the background (driven by gradientAlpha).
    final double tintStrength = (userSettings.themeColors.gradientAlpha.clamp(0, 255)) / 255.0;

    // Panel base: surface colour at high opacity so content is always legible.
    final double baseAlpha = userSettings.activeBackdropPath.isNotEmpty ? 0.72 : 0.88;

    final Color panelBase = surface.withValues(alpha: baseAlpha);

    // Glow centre colour — accent at very low opacity, blended into surface.
    final Color glowColor = Color.alphaBlend(
      accent.withValues(alpha: 0.10 + tintStrength * 0.14),
      surface,
    );

    // Hairline border — white highlight on dark, soft grey on light.
    final Color borderColor = isDark ? Colors.white.withValues(alpha: 0.10) : Colors.white.withValues(alpha: 0.70);

    // Divider colour — barely there.
    final Color dividerColor = theme.colorScheme.onSurface.withValues(alpha: 0.07);

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: 203,
        maxHeight: MediaQuery.of(context).size.height - 90,
      ),
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          // Frosted-glass blur applied to everything beneath the panel.
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
                  // Soft drop shadow — one layer, large blur, no hard edge.
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.10),
                      blurRadius: 32,
                      spreadRadius: -4,
                      offset: const Offset(0, 6),
                    ),
                  ],
                  // Radial glow from top-left: accent tint bleeds into
                  // neutral surface — subtle, not saturated.
                  gradient: RadialGradient(
                    center: const Alignment(-0.6, -0.7),
                    radius: 1.4,
                    colors: <Color>[
                      glowColor,
                      panelBase,
                    ],
                  ),
                  // Specular hairline border.
                  border: Border.all(color: borderColor, width: 0.8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radius),
                  child: Stack(
                    children: <Widget>[
                      // Optional backdrop image underneath everything.
                      if (userSettings.themeColors.backdropType.isNotEmpty)
                        Positioned.fill(
                          child: DesignBackdrop(
                            path: userSettings.activeBackdropPath,
                            opacity: userSettings.themeColors.backdropOpacity,
                          ),
                        ),

                      // Content column — mirrors interface design's structure.
                      RepaintBoundary(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            // ── Top bar / quick-actions header ────────────
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

                            // ── Task list ─────────────────────────────────
                            const TaskBar(),

                            // ── Separator before footer ───────────────────
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              child: _Hairline(color: dividerColor),
                            ),

                            // ── Pinned + tray ─────────────────────────────
                            if (!userSettings.bottomBarOnTop) const PinnedAndTrayList(),

                            // ── Optional system stats ─────────────────────
                            if (userSettings.taskManagerStats) const TaskbarStats(),

                            // ── Bottom bar ────────────────────────────────
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
            ),
          ),
        ),
      ),
    );
  }
}

/// A one-pixel hairline divider that carries zero visual weight on its own —
/// it only becomes perceptible where two content regions need a breath of air
/// between them. Using a dedicated widget keeps the column readable.
class _Hairline extends StatelessWidget {
  final Color color;
  const _Hairline({required this.color});

  @override
  Widget build(BuildContext context) {
    return Divider(thickness: 0.6, height: 1, color: color);
  }
}
