import 'package:flutter/material.dart';

import '../../models/settings.dart';
import '../../models/util/theme_colors.dart';
import '../../widgets/quickmenu/bottom_bar.dart';
import '../../widgets/quickmenu/design_backdrop.dart';
import '../../widgets/quickmenu/info_bar.dart';
import '../../widgets/quickmenu/task_bar.dart';
import '../../widgets/quickmenu/taskbar_stats.dart';
import '../../widgets/quickmenu/top_bar.dart';

class MainMenuModernWidget extends StatelessWidget {
  const MainMenuModernWidget({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = globalSettings.themeColors.accentColor;
    final Color surface = theme.colorScheme.surface;

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
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: <Widget>[
            // Background Layer (Transparent Gradient applied via ShaderMask)
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
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: <Color>[
                          surface.withValues(alpha: globalSettings.activeBackdropPath.isNotEmpty ? 0.8 : 0.95),
                          Color.alphaBlend(
                              accent.withAlpha((globalSettings.themeColors.gradientAlpha * 24 / 100).toInt()), surface),
                          Color.alphaBlend(
                              accent.withAlpha((globalSettings.themeColors.gradientAlpha * 10 / 100).toInt()), surface),
                        ],
                      ),
                      border: Border.all(color: accent.withAlpha(28)),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: Colors.black.withAlpha(18),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: surface.withValues(alpha: globalSettings.activeBackdropPath.isNotEmpty ? 0.7 : 0.9),
                          border: Border.all(color: accent.withAlpha(18)),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: <Color>[
                              Colors.white.withAlpha(14),
                              Colors.transparent,
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
              ),
            ),
            // Interaction Layer (Fully Opaque)
            RepaintBoundary(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (!globalSettings.quickActionsAtBottom)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(3, 3, 6, 4),
                      child: TopBar(),
                    )
                  else
                    const PinnedAndTrayList(),
                  const TaskBar(),
                  Divider(thickness: 1, height: 1, color: globalSettings.themeColors.textColor.withValues(alpha: 0.08)),
                  if (!globalSettings.bottomBarOnTop) const PinnedAndTrayList(),
                  if (globalSettings.taskManagerStats) const TaskbarStats(),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(0, 4, 1, 6),
                    child: BottomBar(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
