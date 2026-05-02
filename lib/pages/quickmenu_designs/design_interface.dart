import 'package:flutter/material.dart';

import '../../models/settings.dart';
import '../../models/util/theme_colors.dart';
import '../../widgets/quickmenu/bottom_bar.dart';
import '../../widgets/quickmenu/design_backdrop.dart';
import '../../widgets/quickmenu/info_bar.dart';
import '../../widgets/quickmenu/task_bar.dart';
import '../../widgets/quickmenu/taskbar_stats.dart';
import '../../widgets/quickmenu/top_bar.dart';

class MainMenuInterfaceWidget extends StatelessWidget {
  const MainMenuInterfaceWidget({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = globalSettings.themeColors.accentColor;
    final Color surface = theme.colorScheme.surface;
    final double gradientStrength = (globalSettings.themeColors.gradientAlpha.clamp(1, 100)) / 100;
    final double outerAccentAlpha = 0.04 + (gradientStrength * 0.08);
    final double innerAccentAlpha = 0.05 + (gradientStrength * 0.10);
    final double headerAccentAlpha =
        globalSettings.themeColors.gradientAlpha == 0 ? 0 : 0.04 + (gradientStrength * 0.12);
    final List<double> points = globalSettings.themeColors.panelOpacityPoints;
    final List<double> stops = <double>[];
    final List<Color> colors = <Color>[];
    for (int i = 0; i < points.length; i += 2) {
      stops.add(points[i]);
      colors.add(Colors.white.withValues(alpha: points[i + 1]));
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: 203,
        maxHeight: MediaQuery.of(context).size.height - 100,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: <Widget>[
            // Background Layer
            Positioned.fill(
                child: RepaintBoundary(
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (Rect bounds) {
                  return LinearGradient(
                    begin: panelAlignmentMap[globalSettings.themeColors.panelOpacityBegin] ?? Alignment.topCenter,
                    end: panelAlignmentMap[globalSettings.themeColors.panelOpacityEnd] ?? Alignment.bottomCenter,
                    colors: colors,
                    stops: stops,
                  ).createShader(bounds);
                },
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        Color.alphaBlend(accent.withValues(alpha: outerAccentAlpha),
                            surface.withValues(alpha: globalSettings.activeBackdropPath.isNotEmpty ? 0.8 : 0.98)),
                        surface.withValues(alpha: globalSettings.activeBackdropPath.isNotEmpty ? 0.7 : 0.95),
                      ],
                    ),
                    border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.08)),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.10),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: surface.withValues(alpha: globalSettings.activeBackdropPath.isNotEmpty ? 0.8 : 0.90),
                        border: Border.all(color: accent.withValues(alpha: innerAccentAlpha)),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: <Color>[
                            theme.colorScheme.surface.withAlpha(245),
                            Color.alphaBlend(accent.withValues(alpha: headerAccentAlpha + headerAccentAlpha * 0.24),
                                theme.colorScheme.surface),
                            Color.alphaBlend(accent.withValues(alpha: headerAccentAlpha + headerAccentAlpha * 0.10),
                                theme.colorScheme.surface),
                          ],
                        ),
                      ),
                      child: Stack(
                        children: <Widget>[
                          if (globalSettings.themeColors.backdropType.isNotEmpty)
                            Positioned.fill(
                                child: DesignBackdrop(
                              path: globalSettings.activeBackdropPath,
                              opacity: globalSettings.themeColors.backdropOpacity,
                            )),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            )),
            // Foreground Content
            RepaintBoundary(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (!globalSettings.quickActionsAtBottom) ...<Widget>[
                    Container(padding: const EdgeInsets.fromLTRB(4, 5, 10, 6), child: const TopBar()),
                    Divider(thickness: 1, height: 1, color: theme.colorScheme.onSurface.withValues(alpha: 0.08))
                  ] else
                    const SizedBox(height: 3),
                  const TaskBar(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Divider(thickness: 1, height: 1, color: theme.colorScheme.onSurface.withValues(alpha: 0.08)),
                  ),
                  const PinnedAndTrayList(),
                  if (globalSettings.taskManagerStats) const TaskbarStats(),
                  Container(padding: const EdgeInsets.fromLTRB(0, 4, 2, 6), child: const BottomBar()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
