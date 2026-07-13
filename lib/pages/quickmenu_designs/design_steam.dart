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

/// "Steam" QuickMenu design — the Steam client look.
///
/// Deep navy body with the library's ambient blue glow bleeding in from the
/// top, a darker nav header (the STORE / LIBRARY / COMMUNITY strip) holding
/// the quick actions with a blue gradient underline, the window switcher on
/// a blue-tinted "library" panel with a small caps section label, and the
/// info bar in a recessed status-bar footer with an online pip.
/// `Design.gradientAlpha` scales the ambient glow strength.
Color _lift(Color base, double amount) => Color.alphaBlend(Colors.white.withValues(alpha: amount), base);
Color _sink(Color base, double amount) => Color.alphaBlend(Colors.black.withValues(alpha: amount), base);

class _SteamTokens {
  _SteamTokens._({
    required this.isDark,
    required this.glow,
    required this.accent,
    required this.text,
    required this.header,
    required this.footer,
    required this.panel,
    required this.panelStroke,
    required this.hairline,
    required this.label,
  });

  factory _SteamTokens.fromTheme() {
    final Color bg = Design.background;
    final Color text = Design.text;
    final Color accent = Design.accent;
    final bool isDark = bg.computeLuminance() < 0.5;
    final double glow = (Design.gradientAlpha.clamp(0, 255)) / 255.0;
    return _SteamTokens._(
      isDark: isDark,
      glow: glow,
      accent: accent,
      text: text,
      // The nav strip and status bar sit visibly darker than the body,
      // like Steam's #171a21 header over the #1b2838 client.
      header: _sink(bg, isDark ? 0.32 : 0.06),
      footer: _sink(bg, isDark ? 0.26 : 0.05),
      // Library panel: lifted and pulled toward the accent, like #2a475e.
      panel: Color.alphaBlend(accent.withValues(alpha: 0.06), _lift(bg, isDark ? 0.055 : 0.35)),
      panelStroke: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.08),
      hairline: isDark ? Colors.black.withValues(alpha: 0.35) : Colors.black.withValues(alpha: 0.10),
      label: text.withValues(alpha: 0.45),
    );
  }

  final bool isDark;
  final double glow;
  final Color accent;
  final Color text;
  final Color header;
  final Color footer;
  final Color panel;
  final Color panelStroke;
  final Color hairline;
  final Color label;
}

class MainMenuSteamWidget extends StatelessWidget {
  const MainMenuSteamWidget({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // register as theme-dependent so Design.* values update live
    final _SteamTokens t = _SteamTokens.fromTheme();
    final bool hasBackdrop = user.activeBackdropPath.isNotEmpty;
    final double radius = Design.borderRadius;

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: 203,
        maxHeight: MediaQuery.of(context).size.height - 50,
      ),
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(
            children: <Widget>[
              // ---- Client body ----
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
                        color: Design.background.withValues(alpha: hasBackdrop ? 0.82 : 1.0),
                        borderRadius: BorderRadius.circular(radius),
                        border: Border.all(
                          color: t.isDark ? Colors.black.withValues(alpha: 0.5) : Colors.black.withValues(alpha: 0.12),
                        ),
                      ),
                      child: Stack(
                        children: <Widget>[
                          if (Design.hasBackdrop) const StableBackdrop(),
                          // Library ambient glow drifting in from the top-left.
                          Positioned.fill(
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: RadialGradient(
                                    center: const Alignment(-0.6, -1.4),
                                    radius: 1.6,
                                    colors: <Color>[
                                      t.accent.withValues(alpha: (0.05 + t.glow * 0.18).clamp(0.0, 1.0)),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ---- Client content ----
              RepaintBoundary(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // Nav header strip.
                    if (!user.quickActionsAtBottom) ...<Widget>[
                      ColoredBox(
                        color: t.header.withValues(alpha: hasBackdrop ? 0.85 : 1.0),
                        child: const Padding(
                          padding: EdgeInsets.fromLTRB(5, 4, 10, 4),
                          child: TopBar(),
                        ),
                      ),
                      Container(height: 1, color: t.hairline),
                      // The blue shine under the store header.
                      Container(
                        height: 1,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: <Color>[
                              t.accent.withValues(alpha: 0.55),
                              t.accent.withValues(alpha: 0.0),
                            ],
                            stops: const <double>[0.0, 0.85],
                          ),
                        ),
                      ),
                    ] else if (user.bottomBarOnTop)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: PinnedAndTrayList(),
                      )
                    else
                      const SizedBox(height: 4),

                    // Library panel.
                    Container(
                      margin: const EdgeInsets.fromLTRB(8, 7, 8, 4),
                      decoration: BoxDecoration(
                        color: t.panel.withValues(alpha: hasBackdrop ? 0.88 : 1.0),
                        borderRadius: BorderRadius.circular((radius - 1).clamp(3.0, 8.0)),
                        border: Border.all(color: t.panelStroke),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(9, 4, 9, 0),
                            child: Row(
                              children: <Widget>[
                                Text(
                                  "LIBRARY",
                                  style: TextStyle(
                                    fontSize: Design.baseFontSize - 2,
                                    fontFamily: Design.uiFontFamily,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 2.0,
                                    color: t.label,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(child: Container(height: 1, color: t.panelStroke)),
                              ],
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 2),
                            child: TaskBar(),
                          ),
                        ],
                      ),
                    ),

                    if (!user.bottomBarOnTop) const PinnedAndTrayList(),
                    if (user.taskManagerStats) const TaskbarStats(withTopDivider: false),
                    if (user.libreStats) const LibreStats(withTopDivider: false),

                    // Status bar footer with the online pip.
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: t.footer.withValues(alpha: hasBackdrop ? 0.85 : 1.0),
                        border: Border(
                          top: BorderSide(color: t.isDark ? Colors.white.withValues(alpha: 0.05) : t.hairline),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(9, 3, 5, 5),
                        child: Row(
                          children: <Widget>[
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: t.accent,
                                boxShadow: <BoxShadow>[
                                  BoxShadow(
                                    color: t.accent.withValues(alpha: (0.3 + t.glow * 0.4).clamp(0.0, 1.0)),
                                    blurRadius: 4,
                                    spreadRadius: 0.5,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 7),
                            const Expanded(child: BottomBar()),
                          ],
                        ),
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
