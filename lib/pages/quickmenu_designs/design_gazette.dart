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

/// "Gazette" QuickMenu design — a vintage newspaper front page.
///
/// The menu renders as a sheet of aged newsprint: a double-rule page frame,
/// a serif masthead over an Oxford rule (thick line paired with a thin one),
/// the quick actions as the section-links strip, the window switcher boxed as
/// the day's dispatches column, pinned apps behind a dotted classifieds rule,
/// and the info bar as the page footer. Everything is "ink" — flat hairlines,
/// no glows, no gradients on chrome. `Design.gradientAlpha` scales the aged-
/// paper vignette that darkens the page edges.
class _GazetteInk {
  _GazetteInk._({
    required this.isDark,
    required this.intensity,
    required this.ink,
    required this.accent,
    required this.ruleBold,
    required this.rule,
    required this.ruleFaint,
    required this.byline,
  });

  factory _GazetteInk.fromTheme() {
    final Color text = Design.text;
    final bool isDark = Design.background.computeLuminance() < 0.5;
    return _GazetteInk._(
      isDark: isDark,
      intensity: (Design.gradientAlpha.clamp(0, 255)) / 255.0,
      ink: text,
      accent: Design.accent,
      ruleBold: text.withValues(alpha: 0.75),
      rule: text.withValues(alpha: 0.45),
      ruleFaint: text.withValues(alpha: 0.22),
      byline: text.withValues(alpha: 0.55),
    );
  }

  final bool isDark;
  final double intensity;
  final Color ink;
  final Color accent;
  final Color ruleBold;
  final Color rule;
  final Color ruleFaint;
  final Color byline;
}

class MainMenuGazetteWidget extends StatelessWidget {
  const MainMenuGazetteWidget({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // register as theme-dependent so Design.* values update live
    final _GazetteInk g = _GazetteInk.fromTheme();
    final bool hasBackdrop = user.activeBackdropPath.isNotEmpty;
    final double radius = Design.borderRadius;

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: 203,
        maxHeight: MediaQuery.of(context).size.height,
      ),
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(
            children: <Widget>[
              // ---- The paper sheet ----
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
                        color: Design.background.withValues(alpha: hasBackdrop ? 0.86 : 1.0),
                        borderRadius: BorderRadius.circular(radius),
                        border: Border.all(color: g.rule),
                      ),
                      child: Stack(
                        children: <Widget>[
                          if (Design.hasBackdrop) const StableBackdrop(),
                          // Aged-paper vignette: the page edges darken with age.
                          Positioned.fill(
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: RadialGradient(
                                    radius: 1.25,
                                    colors: <Color>[
                                      Colors.transparent,
                                      g.ink.withValues(alpha: (0.03 + g.intensity * 0.07).clamp(0.0, 1.0)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Inner hairline of the double page frame.
                          Positioned.fill(
                            child: IgnorePointer(
                              child: Container(
                                margin: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  border: Border.all(color: g.ruleFaint, width: 0.8),
                                  borderRadius: BorderRadius.circular((radius - 3).clamp(0.0, 100.0)),
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

              // ---- Page content ----
              RepaintBoundary(
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _Masthead(g: g),
                      if (!user.quickActionsAtBottom) ...<Widget>[
                        const Padding(
                          padding: EdgeInsets.fromLTRB(3, 2, 8, 2),
                          child: TopBar(),
                        ),
                        Container(
                          height: 0.8,
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          color: g.rule,
                        ),
                      ] else if (user.bottomBarOnTop)
                        const PinnedAndTrayList(),
                      _DispatchColumn(g: g),
                      if (!user.bottomBarOnTop) ...<Widget>[
                        _DottedRule(g: g),
                        const PinnedAndTrayList(),
                      ],
                      if (user.taskManagerStats) const TaskbarStats(withTopDivider: false),
                      if (user.libreStats) const LibreStats(withTopDivider: false),
                      _PageFooter(g: g),
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
// Masthead — title flanked by rules, over the Oxford rule
// ---------------------------------------------------------------------------

class _Masthead extends StatelessWidget {
  const _Masthead({required this.g});

  final _GazetteInk g;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Container(height: 0.8, color: g.ruleFaint)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _InkDiamond(color: g.accent),
                    const SizedBox(width: 6),
                    // Text(
                    //   "THE TABAME GAZETTE",
                    //   style: TextStyle(
                    //     fontSize: Design.baseFontSize + 0.5,
                    //     fontFamily: Design.uiFontFamily,
                    //     fontWeight: FontWeight.w700,
                    //     letterSpacing: 2.8,
                    //     color: g.ink.withValues(alpha: 0.9),
                    //   ),
                    // ),
                    const SizedBox(width: 6),
                    _InkDiamond(color: g.accent),
                  ],
                ),
              ),
              Expanded(child: Container(height: 0.8, color: g.ruleFaint)),
            ],
          ),
          // const SizedBox(height: 3),
          // Oxford rule: thick over thin.
          // Container(height: 1.6, color: g.ruleBold),
          // const SizedBox(height: 1.5),
          // Container(height: 0.8, color: g.rule),
        ],
      ),
    );
  }
}

class _InkDiamond extends StatelessWidget {
  const _InkDiamond({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: 0.785398, // 45°
      child: Container(width: 4, height: 4, color: color),
    );
  }
}

// ---------------------------------------------------------------------------
// Dispatch column — the window switcher boxed as the lead article
// ---------------------------------------------------------------------------

class _DispatchColumn extends StatelessWidget {
  const _DispatchColumn({required this.g});

  final _GazetteInk g;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(6, 4, 6, 3),
      decoration: BoxDecoration(border: Border.all(color: g.ruleFaint, width: 0.8)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 3, 8, 0),
            child: Row(
              children: <Widget>[
                Expanded(child: Container(height: 0.8, color: g.ruleFaint)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    "ACTIVE WINDOWS",
                    style: TextStyle(
                      fontSize: Design.baseFontSize - 2.5,
                      fontFamily: Design.uiFontFamily,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.4,
                      color: g.byline,
                    ),
                  ),
                ),
                Expanded(child: Container(height: 0.8, color: g.ruleFaint)),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 2),
            child: TaskBar(),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Classifieds rule + page footer
// ---------------------------------------------------------------------------

class _DottedRule extends StatelessWidget {
  const _DottedRule({required this.g});

  final _GazetteInk g;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 1, 8, 1),
      child: SizedBox(
        height: 1,
        child: CustomPaint(painter: _DotsPainter(color: g.rule)),
      ),
    );
  }
}

class _DotsPainter extends CustomPainter {
  const _DotsPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = color;
    for (double x = 0; x < size.width; x += 4) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 1.2, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DotsPainter oldDelegate) => oldDelegate.color != color;
}

class _PageFooter extends StatelessWidget {
  const _PageFooter({required this.g});

  final _GazetteInk g;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Inverted Oxford rule closes the page: thin over thick.
          Container(height: 0.8, color: g.rule),
          const SizedBox(height: 1.5),
          Container(height: 1.6, color: g.ruleBold),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 2, 4, 0),
            child: BottomBar(),
          ),
        ],
      ),
    );
  }
}
