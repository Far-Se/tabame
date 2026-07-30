import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../models/settings.dart';
import '../../models/util/theme_colors.dart';
import '../../widgets/quickmenu/bottom_bar.dart';
import '../../widgets/quickmenu/libre_stats.dart';
import '../../widgets/quickmenu/task_bar.dart';
import '../../widgets/quickmenu/taskbar_stats.dart';
import '../../widgets/quickmenu/top_bar.dart';
import 'design_backdrop_stable.dart';

/// "Manga" QuickMenu design — a black-and-white comic page.
///
/// The menu renders as a single inked panel: a bold double-ruled frame like
/// a comic page border, a slanted "impact" masthead with a burst mark and
/// speed lines racing off the top-right corner, section headers as skewed
/// ink tabs (`WINDOWS`, `PINNED`) standing in for panel captions, and a
/// hard-ruled caption box at the foot of the page holding the info bar.
/// A halftone dot screentone washes over the whole sheet for shading.
///
/// Colors follow the user's theme (`Design.background` / `Design.accent`);
/// `Design.gradientAlpha` scales how visible the halftone screentone is.
class _MangaInk {
  _MangaInk._({
    required this.isDark,
    required this.intensity,
    required this.ink,
    required this.accent,
    required this.paper,
    required this.gutter,
    required this.gutterFaint,
  });

  factory _MangaInk.fromTheme() {
    final Color text = Design.text;
    final Color bg = Design.background;
    final bool isDark = bg.computeLuminance() < 0.5;
    return _MangaInk._(
      isDark: isDark,
      intensity: (Design.gradientAlpha.clamp(0, 255)) / 255.0,
      ink: text,
      accent: Design.accent,
      paper: bg,
      gutter: text.withValues(alpha: 0.88),
      gutterFaint: text.withValues(alpha: 0.30),
    );
  }

  final bool isDark;
  final double intensity;
  final Color ink;
  final Color accent;
  final Color paper;
  final Color gutter;
  final Color gutterFaint;
}

class MainMenuMangaWidget extends StatelessWidget {
  const MainMenuMangaWidget({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // register as theme-dependent so Design.* values update live
    final _MangaInk m = _MangaInk.fromTheme();
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
              // ---- The inked page ----
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
                        color: m.paper.withValues(alpha: hasBackdrop ? 0.88 : 1.0),
                        border: Border.all(color: m.gutter, width: 2.2),
                        borderRadius: BorderRadius.circular(radius),
                      ),
                      child: Stack(
                        children: <Widget>[
                          if (Design.hasBackdrop) const StableBackdrop(),
                          // Screentone shading over the whole sheet.
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: _HalftonePainter(
                                  m.ink.withValues(alpha: (0.05 + m.intensity * 0.05).clamp(0.0, 1.0)),
                                ),
                              ),
                            ),
                          ),
                          // Second ruling just inside the frame — the double panel border.
                          Positioned.fill(
                            child: IgnorePointer(
                              child: Container(
                                margin: const EdgeInsets.all(3.5),
                                decoration: BoxDecoration(
                                  border: Border.all(color: m.gutterFaint, width: 0.9),
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
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    DragToMoveArea(child: _ImpactHeader(m: m)),
                    if (!user.quickActionsAtBottom)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(6, 3, 6, 0),
                        child: TopBar(),
                      )
                    else if (user.bottomBarOnTop)
                      const PinnedAndTrayList(),
                    DragToMoveArea(child: _PanelLabel(text: 'WINDOWS', m: m)),
                    const TaskBar(),
                    if (!user.bottomBarOnTop) ...<Widget>[
                      // _PanelLabel(text: 'PINNED', m: m),
                      const PinnedAndTrayList(),
                    ],
                    if (user.taskManagerStats) const TaskbarStats(withTopDivider: false),
                    if (user.libreStats) const LibreStats(withTopDivider: false),
                    _CaptionFooter(m: m),
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

// ---------------------------------------------------------------------------
// Impact header — slanted masthead, burst mark, speed lines
// ---------------------------------------------------------------------------

class _ImpactHeader extends StatelessWidget {
  const _ImpactHeader({required this.m});

  final _MangaInk m;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      decoration: BoxDecoration(
        color: m.gutter,
        border: Border(bottom: BorderSide(color: m.gutter, width: 2.2)),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // Speed lines racing in from the top-right corner.
          Positioned.fill(
            child: CustomPaint(painter: _SpeedLinesPainter(m.paper.withValues(alpha: 0.14))),
          ),
          Row(
            children: <Widget>[
              const SizedBox(width: 10),
              _ImpactBurst(color: m.accent, size: 13),
              const SizedBox(width: 8),
              Expanded(
                child: Transform(
                  alignment: Alignment.centerLeft,
                  transform: Matrix4.skewX(-0.18),
                  child: Text(
                    'TABAME',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: Design.baseFontSize + 2,
                      fontFamily: Design.uiFontFamily,
                      fontWeight: FontWeight.w900,
                      fontStyle: FontStyle.italic,
                      letterSpacing: 1.1,
                      color: m.paper,
                    ),
                  ),
                ),
              ),
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                color: m.accent,
                child: Text(
                  _shellUser(),
                  style: TextStyle(
                    fontSize: Design.baseFontSize - 3,
                    fontFamily: Design.uiFontFamily,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    color: m.paper,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _shellUser() {
    final String name = Platform.environment['USERNAME'] ?? 'user';
    final String clean = name.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    return clean.isEmpty ? 'user' : clean;
  }
}

/// Small ink burst / impact star used next to the masthead.
class _ImpactBurst extends StatelessWidget {
  const _ImpactBurst({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: size, height: size, child: CustomPaint(painter: _BurstPainter(color)));
  }
}

class _BurstPainter extends CustomPainter {
  const _BurstPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = color;
    final Offset c = Offset(size.width / 2, size.height / 2);
    final double outer = size.width / 2;
    final double inner = outer * 0.42;
    const int spikes = 8;
    final Path path = Path();
    for (int i = 0; i < spikes * 2; i++) {
      final double r = i.isEven ? outer : inner;
      final double angle = (i * math.pi) / spikes;
      final Offset p = Offset(c.dx + r * math.cos(angle), c.dy + r * math.sin(angle));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BurstPainter oldDelegate) => oldDelegate.color != color;
}

class _SpeedLinesPainter extends CustomPainter {
  const _SpeedLinesPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke;
    final Offset origin = Offset(size.width, 0);
    const int lines = 12;
    for (int i = 0; i < lines; i++) {
      final double angle = math.pi * (0.55 + (i / lines) * 0.42);
      final double len = size.width * 0.95;
      final Offset end = Offset(origin.dx + len * math.cos(angle), origin.dy + len * math.sin(angle));
      canvas.drawLine(origin, end, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SpeedLinesPainter oldDelegate) => oldDelegate.color != color;
}

// ---------------------------------------------------------------------------
// Screentone halftone wash
// ---------------------------------------------------------------------------

class _HalftonePainter extends CustomPainter {
  const _HalftonePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (color.a == 0) return;
    final Paint paint = Paint()..color = color;
    const double spacing = 5.5;
    const double dotRadius = 0.8;
    int row = 0;
    for (double y = spacing / 2; y < size.height; y += spacing) {
      final double offset = row.isEven ? 0.0 : spacing / 2;
      for (double x = spacing / 2 + offset; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), dotRadius, paint);
      }
      row++;
    }
  }

  @override
  bool shouldRepaint(covariant _HalftonePainter oldDelegate) => oldDelegate.color != color;
}

// ---------------------------------------------------------------------------
// Panel label — skewed ink caption tab (used above the switcher / pinned strip)
// ---------------------------------------------------------------------------

class _PanelLabel extends StatelessWidget {
  const _PanelLabel({required this.text, required this.m});

  final String text;
  final _MangaInk m;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
      child: Row(
        children: <Widget>[
          Transform(
            alignment: Alignment.center,
            transform: Matrix4.skewX(-0.3),
            child: Container(
              color: m.gutter,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1.5),
              child: Text(
                text,
                style: TextStyle(
                  fontSize: Design.baseFontSize - 2.5,
                  fontFamily: Design.uiFontFamily,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.6,
                  color: m.paper,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(child: Container(height: 1.4, color: m.gutterFaint)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Caption footer — hard-ruled box holding the info bar
// ---------------------------------------------------------------------------

class _CaptionFooter extends StatelessWidget {
  const _CaptionFooter({required this.m});

  final _MangaInk m;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 3, 0, 0),
      decoration: BoxDecoration(border: Border.all(color: m.gutter, width: 1.4)),
      padding: const EdgeInsets.fromLTRB(4, 1, 4, 1),
      child: const PinnedAndTrayList(),
    );
  }
}
