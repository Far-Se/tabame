import 'dart:math' show cos, sin, pi;

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

/// "Anime" QuickMenu design — a soft, dreamy pastel aesthetic inspired by
/// magical-girl HUDs and visual-novel interfaces. Rounded bubbly containers,
/// floating sparkle motes, soft glow gradients, and star-shaped section
/// markers give the menu a light, kawaii personality without sacrificing
/// readability.
class MainMenuAnime2Widget extends StatelessWidget {
  const MainMenuAnime2Widget({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active theme changes.
    final _AnimePalette p = _AnimePalette.fromTheme();
    final bool hasBackdrop = user.activeBackdropPath.isNotEmpty;

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: 203,
        maxHeight: MediaQuery.of(context).size.height - 50,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Design.borderRadius),
        child: Stack(
          children: <Widget>[
            // ---- Dreamy background layer ----
            Positioned.fill(
              child: RepaintBoundary(
                child: _AnimeGround(p: p, hasBackdrop: hasBackdrop),
              ),
            ),

            // ---- Content column ----
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // Decorative top sparkle strip

                  if (!user.quickActionsAtBottom) ...<Widget>[
                    const SizedBox(height: 4),
                    _AnimeBubble(
                      p: p,
                      child: const Padding(
                        padding: EdgeInsets.fromLTRB(8, 4, 8, 4),
                        child: TopBar(),
                      ),
                    ),
                  ] else if (user.bottomBarOnTop) ...<Widget>[
                    // _AnimeSectionMarker(label: 'PINNED', p: p),
                    const PinnedAndTrayList(),
                  ] else
                    const SizedBox(height: 4),

                  _AnimeSectionMarker(label: 'WINDOWS', p: p),
                  _AnimeBubble(
                    p: p,
                    inset: true,
                    child: const RepaintBoundary(
                      child: TaskBar(),
                    ),
                  ),

                  if (!user.bottomBarOnTop) ...<Widget>[
                    _AnimeSectionMarker(label: 'PINNED', p: p),
                    const PinnedAndTrayList(),
                  ],

                  if (user.taskManagerStats) const TaskbarStats(withTopDivider: false),
                  if (user.libreStats) const LibreStats(withTopDivider: false),

                  // _AnimeSectionMarker(label: 'CONTROL', p: p),
                  _AnimeBubble(
                    p: p,
                    inset: true,
                    child: const Padding(
                      padding: EdgeInsets.fromLTRB(6, 2, 6, 2),
                      child: BottomBar(),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),

            // ---- Floating sparkles overlay ----
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _AnimeSparklePainter(
                      accent: p.sparkle,
                      glow: p.glowStrength,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Palette
// ---------------------------------------------------------------------------

class _AnimePalette {
  const _AnimePalette({
    required this.bg,
    required this.text,
    required this.accent,
    required this.glow,
    required this.bubble,
    required this.bubbleEdge,
    required this.sparkle,
    required this.glowStrength,
    required this.isDark,
  });

  factory _AnimePalette.fromTheme() {
    final bool isDark = Design.background.computeLuminance() < 0.5;
    final Color accent = Design.accent;
    return _AnimePalette(
      bg: Design.background,
      text: Design.text,
      accent: accent,
      glow: accent.withValues(alpha: isDark ? 0.18 : 0.12),
      bubble: isDark
          ? Color.alphaBlend(
              accent.withValues(alpha: 0.08),
              Design.background,
            )
          : Color.alphaBlend(
              accent.withValues(alpha: 0.06),
              Colors.white.withValues(alpha: 0.35),
            ),
      bubbleEdge: accent.withValues(alpha: isDark ? 0.35 : 0.45),
      sparkle: isDark ? Color.alphaBlend(Colors.white.withValues(alpha: 0.6), accent) : accent,
      glowStrength: (Design.gradientAlpha.clamp(0, 255)) / 255.0,
      isDark: isDark,
    );
  }

  final Color bg;
  final Color text;
  final Color accent;
  final Color glow;
  final Color bubble;
  final Color bubbleEdge;
  final Color sparkle;
  final double glowStrength;
  final bool isDark;
}

// ---------------------------------------------------------------------------
// Background ground
// ---------------------------------------------------------------------------

class _AnimeGround extends StatelessWidget {
  const _AnimeGround({required this.p, required this.hasBackdrop});

  final _AnimePalette p;
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
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              p.bg.withValues(alpha: hasBackdrop ? 0.82 : 0.96),
              Color.alphaBlend(
                p.accent.withValues(alpha: p.isDark ? 0.08 : 0.04),
                p.bg,
              ).withValues(alpha: hasBackdrop ? 0.82 : 0.96),
            ],
          ),
          border: Border.all(
            color: p.accent.withValues(alpha: p.isDark ? 0.20 : 0.30),
            width: 1.0,
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: p.accent.withValues(alpha: p.isDark ? 0.15 : 0.10),
              blurRadius: 20,
              spreadRadius: -4,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Stack(
          children: <Widget>[
            if (Design.hasBackdrop) const StableBackdrop(),
            // Soft radial glow in the center-top
            Positioned(
              top: -40,
              left: 0,
              right: 0,
              child: Container(
                height: 140,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.0, 0.0),
                    radius: 0.8,
                    colors: <Color>[
                      p.glow.withValues(alpha: 0.5 + p.glowStrength * 0.3),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Decorative widgets
// ---------------------------------------------------------------------------

// ignore: unused_element
class _AnimeTopSparkles extends StatelessWidget {
  const _AnimeTopSparkles({required this.p});

  final _AnimePalette p;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
      child: Row(
        children: <Widget>[
          _StarIcon(color: p.sparkle, size: 8),
          const SizedBox(width: 6),
          _StarIcon(color: p.sparkle, size: 6),
          const Spacer(),
          _StarIcon(color: p.sparkle, size: 6),
          const SizedBox(width: 6),
          _StarIcon(color: p.sparkle, size: 8),
        ],
      ),
    );
  }
}

class _StarIcon extends StatelessWidget {
  const _StarIcon({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _StarPainter(color: color),
    );
  }
}

class _AnimeSectionMarker extends StatelessWidget {
  const _AnimeSectionMarker({required this.label, required this.p});

  final String label;
  final _AnimePalette p;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 4, 3),
      child: Row(
        children: <Widget>[
          _StarIcon(color: p.accent, size: 7),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: p.accent.withValues(alpha: 0.85),
              fontFamily: Design.uiFontFamily,
              fontSize: Design.baseFontSize - 1,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
              height: 1,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[
                    p.accent.withValues(alpha: 0.35),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimeBubble extends StatelessWidget {
  const _AnimeBubble({
    required this.p,
    required this.child,
    this.inset = false,
  });

  final _AnimePalette p;
  final Widget child;
  final bool inset;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: inset ? p.bg.withValues(alpha: p.isDark ? 0.45 : 0.55) : p.bubble,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: p.bubbleEdge,
          width: 1.2,
        ),
        boxShadow: inset
            ? null
            : <BoxShadow>[
                BoxShadow(
                  color: p.accent.withValues(alpha: p.isDark ? 0.10 : 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Painters
// ---------------------------------------------------------------------------

class _StarPainter extends CustomPainter {
  const _StarPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = color;
    final double cx = size.width / 2;
    final double cy = size.height / 2;
    final double outer = size.width / 2;
    final double inner = outer * 0.45;

    final Path path = Path();
    for (int i = 0; i < 5; i++) {
      final double a1 = (i * 4 * pi / 5) - pi / 2;
      final double a2 = ((i * 4 + 2) * pi / 5) - pi / 2;
      if (i == 0) {
        path.moveTo(cx + cos(a1) * outer, cy + sin(a1) * outer);
      } else {
        path.lineTo(cx + cos(a1) * outer, cy + sin(a1) * outer);
      }
      path.lineTo(cx + cos(a2) * inner, cy + sin(a2) * inner);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _StarPainter oldDelegate) => oldDelegate.color != color;
}

class _AnimeSparklePainter extends CustomPainter {
  const _AnimeSparklePainter({required this.accent, required this.glow});

  final Color accent;
  final double glow;

  static const List<Offset> _kSparkles = <Offset>[
    Offset(0.10, 0.08),
    Offset(0.85, 0.12),
    Offset(0.45, 0.05),
    Offset(0.08, 0.32),
    Offset(0.92, 0.38),
    Offset(0.30, 0.22),
    Offset(0.70, 0.26),
    Offset(0.15, 0.52),
    Offset(0.88, 0.58),
    Offset(0.50, 0.48),
    Offset(0.25, 0.72),
    Offset(0.75, 0.70),
    Offset(0.10, 0.88),
    Offset(0.90, 0.86),
    Offset(0.50, 0.94),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = accent.withValues(alpha: (0.25 + glow * 0.2).clamp(0.0, 1.0));

    for (final Offset rel in _kSparkles) {
      final double x = rel.dx * size.width;
      final double y = rel.dy * size.height;
      const double r = 2.5;

      final Path sparkle = Path()
        ..moveTo(x, y - r)
        ..lineTo(x + r * 0.25, y - r * 0.25)
        ..lineTo(x + r, y)
        ..lineTo(x + r * 0.25, y + r * 0.25)
        ..lineTo(x, y + r)
        ..lineTo(x - r * 0.25, y + r * 0.25)
        ..lineTo(x - r, y)
        ..lineTo(x - r * 0.25, y - r * 0.25)
        ..close();

      canvas.drawPath(sparkle, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AnimeSparklePainter oldDelegate) =>
      oldDelegate.accent != accent || oldDelegate.glow != glow;
}
