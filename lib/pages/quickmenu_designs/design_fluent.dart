import 'package:flutter/material.dart';

import '../../models/settings.dart';
import '../../models/util/theme_colors.dart';
import '../../widgets/quickmenu/bottom_bar.dart';
import '../../widgets/quickmenu/info_bar.dart';
import '../../widgets/quickmenu/libre_stats.dart';
import '../../widgets/quickmenu/task_bar.dart';
import '../../widgets/quickmenu/taskbar_stats.dart';
import '../../widgets/quickmenu/top_bar.dart';
import 'design_backdrop_stable.dart';

/// "Fluent" QuickMenu design — Windows 11 flyout styling.
///
/// Mimics the taskbar flyouts (quick settings / notification center): a mica
/// sheet with a faint accent tint, hairline surface strokes, the window
/// switcher raised on a layered card, and a tonally separated footer strip.
/// `Design.gradientAlpha` scales the mica tint strength.
class _FluentTokens {
  _FluentTokens._({
    required this.isDark,
    required this.tint,
    required this.accent,
    required this.text,
    required this.stroke,
    required this.divider,
    required this.cardBg,
    required this.cardStroke,
    required this.cardEdge,
    required this.footer,
  });

  factory _FluentTokens.fromTheme() {
    final Color text = Design.text;
    final Color accent = Design.accent;
    final bool isDark = Design.background.computeLuminance() < 0.5;
    final double tint = (Design.gradientAlpha.clamp(0, 255)) / 255.0;
    return _FluentTokens._(
      isDark: isDark,
      tint: tint,
      accent: accent,
      text: text,
      // WinUI "surface stroke" — the 1px outline around the whole flyout.
      stroke: isDark ? Colors.white.withValues(alpha: 0.09) : Colors.black.withValues(alpha: 0.11),
      divider: text.withValues(alpha: 0.08),
      // "Layer on mica" card the switcher sits on.
      cardBg: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.70),
      cardStroke: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
      // WinUI control stroke reads darker along the bottom edge.
      cardEdge: isDark ? Colors.black.withValues(alpha: 0.25) : Colors.black.withValues(alpha: 0.11),
      footer: isDark ? Colors.black.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.03),
    );
  }

  final bool isDark;
  final double tint;
  final Color accent;
  final Color text;
  final Color stroke;
  final Color divider;
  final Color cardBg;
  final Color cardStroke;
  final Color cardEdge;
  final Color footer;
}

class MainMenuFluentWidget extends StatelessWidget {
  const MainMenuFluentWidget({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // register as theme-dependent so Design.* values update live
    final _FluentTokens t = _FluentTokens.fromTheme();
    final bool hasBackdrop = user.activeBackdropPath.isNotEmpty;
    final double radius = Design.borderRadius;

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: 203,
        maxHeight: MediaQuery.of(context).size.height - 30,
      ),
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(
            children: <Widget>[
              // ---- Mica sheet ----
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
                        color: Design.background.withValues(alpha: hasBackdrop ? 0.78 : 1.0),
                        borderRadius: BorderRadius.circular(radius),
                        border: Border.all(color: t.stroke),
                      ),
                      child: Stack(
                        children: <Widget>[
                          // Mica desktop-tint impression: a faint accent wash
                          // drifting in from the top, scaled by gradientAlpha.
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: <Color>[
                                    t.accent.withValues(alpha: (t.tint * 0.10).clamp(0.0, 1.0)),
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

              // ---- Flyout content ----
              RepaintBoundary(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (!user.quickActionsAtBottom) ...<Widget>[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(6, 6, 10, 5),
                        child: TopBar(),
                      ),
                      Container(height: 1, margin: const EdgeInsets.symmetric(horizontal: 1), color: t.divider),
                    ] else if (user.bottomBarOnTop)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: PinnedAndTrayList(),
                      )
                    else
                      const SizedBox(height: 4),

                    // Window switcher on a raised "layer" card.
                    Container(
                      margin: const EdgeInsets.fromLTRB(8, 7, 8, 4),
                      decoration: BoxDecoration(
                        color: t.cardBg,
                        borderRadius: BorderRadius.circular((radius - 2).clamp(4.0, 12.0)),
                        border: Border.all(color: t.cardStroke),
                        // Darker bottom edge as a 1px hard shadow so the card
                        // keeps its "raised layer" lift while staying rounded.
                        boxShadow: <BoxShadow>[
                          BoxShadow(color: t.cardEdge, offset: const Offset(0, 1)),
                        ],
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 0),
                        child: TaskBar(),
                      ),
                    ),

                    if (!user.bottomBarOnTop) const PinnedAndTrayList(),
                    if (user.taskManagerStats) const TaskbarStats(withTopDivider: false),
                    if (user.libreStats) const LibreStats(withTopDivider: false),

                    // Footer strip — tonally separated like the quick-settings
                    // battery/settings row.
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: t.footer,
                        border: Border(top: BorderSide(color: t.divider)),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.fromLTRB(4, 3, 4, 5),
                        child: BottomBar(),
                      ),
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
