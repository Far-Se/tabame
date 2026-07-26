import 'dart:math' as math;

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

/// "Impact" QuickMenu design — a shonen manga action panel.
///
/// The menu reads as a printed comic panel rather than a software surface:
/// a halftone (Ben-Day dot) ground standing in for gradients, a heavy ink
/// border, a diagonal cut-corner "episode tab" in the top right holding the
/// panel number, and a speed-line burst radiating from the top-left corner —
/// the visual shorthand manga uses for a sudden beat or an entrance panel.
/// The footer is a solid ink gutter with a double ruled line, echoing the
/// panel-gutter convention between comic frames.
///
/// Colors follow the user's theme (`Design.background` / `Design.accent`);
/// the halftone and speed-line overlays are painted, not imaged, so they
/// scale cleanly with the panel and stay crisp at any DPI.
class MainMenuImpactWidget extends StatelessWidget {
  const MainMenuImpactWidget({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // register as theme-dependent so Design.* values update live
    final _ImpactPalette p = _ImpactPalette.fromTheme();
    final bool hasBackdrop = user.activeBackdropPath.isNotEmpty;

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: 203,
        maxHeight: MediaQuery.of(context).size.height - 50,
      ),
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Design.borderRadius),
          child: Stack(
            children: <Widget>[
              Positioned.fill(child: _ImpactGround(p: p, hasBackdrop: hasBackdrop)),

              RepaintBoundary(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _ActionHeader(p: p),
                    if (!user.quickActionsAtBottom)
                      const TopBar()
                    else if (user.bottomBarOnTop)
                      const PinnedAndTrayList(),
                    const TaskBar(),
                    if (!user.bottomBarOnTop) const PinnedAndTrayList(),
                    if (user.taskManagerStats) const TaskbarStats(withTopDivider: false),
                    if (user.libreStats) const LibreStats(withTopDivider: false),
                    _GutterFooter(p: p),
                  ],
                ),
              ),

              // Panel furniture painted above the content, ignoring hit-testing.
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _SpeedlineBurstPainter(accent: p.signal, ink: p.ink)),
                ),
              ),
              Positioned(top: 0, right: 0, child: _EpisodeTab(p: p)),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Palette
// ---------------------------------------------------------------------------

class _ImpactPalette {
  const _ImpactPalette({
    required this.paper,
    required this.ink,
    required this.signal,
    required this.halftone,
    required this.isDark,
  });

  factory _ImpactPalette.fromTheme() {
    final bool isDark = Design.background.computeLuminance() < 0.5;
    return _ImpactPalette(
      paper: Design.background,
      ink: Design.text,
      signal: Design.accent,
      halftone: Design.accent.withValues(alpha: isDark ? 0.09 : 0.07),
      isDark: isDark,
    );
  }

  final Color paper;
  final Color ink;
  final Color signal;
  final Color halftone;
  final bool isDark;
}

// ---------------------------------------------------------------------------
// Ground — paper, ink border, halftone dot screen, backdrop
// ---------------------------------------------------------------------------

class _ImpactGround extends StatelessWidget {
  const _ImpactGround({required this.p, required this.hasBackdrop});

  final _ImpactPalette p;
  final bool hasBackdrop;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
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
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: p.paper.withValues(alpha: hasBackdrop ? 0.9 : 1),
          border: Border.all(color: p.ink, width: 2.5),
        ),
        child: Stack(
          children: <Widget>[
            if (Design.hasBackdrop) const StableBackdrop(),
            Positioned.fill(
              child: IgnorePointer(child: CustomPaint(painter: _HalftonePainter(color: p.halftone))),
            ),
          ],
        ),
      ),
    );
  }
}

class _HalftonePainter extends CustomPainter {
  const _HalftonePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint dot = Paint()..color = color;
    const double spacing = 9;
    for (double y = 4; y < size.height; y += spacing) {
      for (double x = 4; x < size.width; x += spacing) {
        final double t = (x / size.width + y / size.height) / 2;
        canvas.drawCircle(Offset(x, y), 0.6 + t * 1.2, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HalftonePainter oldDelegate) => oldDelegate.color != color;
}

// ---------------------------------------------------------------------------
// Speed-line burst — radiates from the top-left corner, manga "impact" beat
// ---------------------------------------------------------------------------

class _SpeedlineBurstPainter extends CustomPainter {
  const _SpeedlineBurstPainter({required this.accent, required this.ink});

  final Color accent;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint line = Paint()
      ..color = accent.withValues(alpha: 0.45)
      ..strokeWidth = 1.1;
    const Offset origin = Offset(-4, -4);
    const int rays = 10;
    const double spread = 1.35; // radians swept from horizontal
    for (int i = 0; i < rays; i++) {
      final double angle = (i / (rays - 1)) * spread;
      final double len = 24 + (i.isEven ? 12 : 0);
      final Offset end = origin + Offset(len * math.cos(angle), len * math.sin(angle));
      canvas.drawLine(origin, end, line);
    }
  }

  @override
  bool shouldRepaint(covariant _SpeedlineBurstPainter oldDelegate) =>
      oldDelegate.accent != accent || oldDelegate.ink != ink;
}

// ---------------------------------------------------------------------------
// Episode tab — diagonal cut-corner plate, top right
// ---------------------------------------------------------------------------

class _EpisodeTab extends StatelessWidget {
  const _EpisodeTab({required this.p});

  final _ImpactPalette p;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: const Size(46, 30),
        painter: _EpisodeTabPainter(ink: p.ink, accent: p.signal),
      ),
    );
  }
}

class _EpisodeTabPainter extends CustomPainter {
  const _EpisodeTabPainter({required this.ink, required this.accent});

  final Color ink;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final Path cut = Path()
      ..moveTo(size.width - 30, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, 30)
      ..close();
    canvas.drawPath(cut, Paint()..color = ink);
    canvas.drawLine(
      Offset(size.width - 30, 0),
      Offset(size.width, 30),
      Paint()
        ..color = accent
        ..strokeWidth = 2,
    );

    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: '01',
        style: TextStyle(
          color: accent,
          fontFamily: Design.uiFontFamily,
          fontSize: Design.baseFontSize - 1,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(size.width - 15, 10));
  }

  @override
  bool shouldRepaint(covariant _EpisodeTabPainter oldDelegate) =>
      oldDelegate.ink != ink || oldDelegate.accent != accent;
}

// ---------------------------------------------------------------------------
// Header — action row on a tinted plate, ruled off like a panel border
// ---------------------------------------------------------------------------

class _ActionHeader extends StatelessWidget {
  const _ActionHeader({required this.p});

  final _ImpactPalette p;

  @override
  Widget build(BuildContext context) {
    if (user.quickActionsAtBottom) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 3, 34, 4),
      decoration: BoxDecoration(
        color: p.signal.withValues(alpha: p.isDark ? 0.16 : 0.09),
        border: Border(bottom: BorderSide(color: p.ink, width: 1.5)),
      ),
      child: const TopBar(),
    );
  }
}

// ---------------------------------------------------------------------------
// Footer — solid ink gutter with a double rule, panel-gutter convention
// ---------------------------------------------------------------------------

class _GutterFooter extends StatelessWidget {
  const _GutterFooter({required this.p});

  final _ImpactPalette p;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: p.ink,
        border: Border(top: BorderSide(color: p.signal, width: 3)),
      ),
      padding: const EdgeInsets.fromLTRB(0, 2, 2, 3),
      child: ColorFiltered(
        colorFilter: ColorFilter.mode(p.paper, BlendMode.srcIn),
        child: const BottomBar(),
      ),
    );
  }
}
