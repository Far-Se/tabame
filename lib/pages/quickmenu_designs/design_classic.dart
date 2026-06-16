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

class MainMenuClassicWidget extends StatelessWidget {
  const MainMenuClassicWidget({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final List<double> points = Design.panelOpacityPoints;
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
        borderRadius: BorderRadius.circular(Design.borderRadius),
        child: Stack(
          children: <Widget>[
            // Background Layer
            Positioned.fill(
              child: RepaintBoundary(
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (Rect bounds) {
                    return LinearGradient(
                      begin: panelAlignmentMap[Design.panelOpacityBegin] ?? Alignment.topCenter,
                      end: panelAlignmentMap[Design.panelOpacityEnd] ?? Alignment.bottomCenter,
                      colors: colors,
                      stops: stops,
                    ).createShader(bounds);
                  },
                  child: Container(
                    decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surface
                            .withValues(alpha: user.activeBackdropPath.isNotEmpty ? 0.7 : 1.0),
                        gradient: LinearGradient(
                          colors: <Color>[
                            Theme.of(context)
                                .colorScheme
                                .surface
                                .withValues(alpha: user.activeBackdropPath.isNotEmpty ? 0.8 : 1.0),
                            Theme.of(context).colorScheme.surface.withAlpha(Design.gradientAlpha),
                            Theme.of(context)
                                .colorScheme
                                .surface
                                .withValues(alpha: user.activeBackdropPath.isNotEmpty ? 0.8 : 1.0),
                          ],
                          stops: const <double>[0, 0.4, 1],
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: const <BoxShadow>[
                          BoxShadow(color: Colors.black26, offset: Offset(3, 5), blurStyle: BlurStyle.inner),
                        ]),
                    child: Design.hasBackdrop
                        ? const Stack(
                            children: <Widget>[
                              StableBackdrop(),
                            ],
                          )
                        : null,
                  ),
                ),
              ),
            ),
            // Foreground Content
            RepaintBoundary(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (!user.bottomBarOnTop)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(3, 3, 6, 3),
                      child: TopBar(),
                    )
                  else
                    const PinnedAndTrayList(),
                  const TaskBar(),
                  const Divider(thickness: 1, height: 1),
                  if (!user.bottomBarOnTop) const PinnedAndTrayList(),
                  if (user.taskManagerStats) const TaskbarStats(),
                  if (user.libreStats) const LibreStats(),
                  const BottomBar(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
