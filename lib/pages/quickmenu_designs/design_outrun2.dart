import 'dart:math' show cos, sin, pi, pow;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../models/settings.dart';
import '../../models/util/theme_colors.dart';
import '../../widgets/quickmenu/bottom_bar.dart';
import '../../widgets/quickmenu/info_bar.dart';
import '../../widgets/quickmenu/libre_stats.dart';
import '../../widgets/quickmenu/task_bar.dart';
import '../../widgets/quickmenu/taskbar_stats.dart';
import '../../widgets/quickmenu/top_bar.dart';
import 'design_backdrop_stable.dart';

/// "Outrun" QuickMenu design — a synthwave / retrowave HUD inspired by the
/// 1986 Sega classic. Features a perspective highway grid rolling toward a
/// purple-pink sunset, neon pink/cyan glow on every container, palm-tree
/// silhouettes, and sharp 80s chrome brackets.
class MainMenuOutrun2Widget extends StatelessWidget {
  const MainMenuOutrun2Widget({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active theme changes.
    final _OutrunPalette p = _OutrunPalette.fromTheme();
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
            // ---- Highway sky & grid ----
            Positioned.fill(
              child: RepaintBoundary(
                child: _OutrunGround(p: p, hasBackdrop: hasBackdrop),
              ),
            ),

            // ---- Content column ----
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (!user.quickActionsAtBottom) ...<Widget>[
                    const SizedBox(height: 4),
                    _OutrunNeonBox(
                      p: p,
                      child: const Padding(
                        padding: EdgeInsets.fromLTRB(8, 4, 8, 4),
                        child: TopBar(),
                      ),
                    ),
                  ] else if (user.bottomBarOnTop) ...<Widget>[
                    // _OutrunSectionMarker(label: 'PINNED', p: p),
                    const PinnedAndTrayList(),
                  ] else
                    const SizedBox(height: 4),
                  DragToMoveArea(child: _OutrunSectionMarker(label: 'WINDOWS', p: p)),
                  _OutrunNeonBox(
                    p: p,
                    inset: true,
                    child: const RepaintBoundary(
                      child: TaskBar(),
                    ),
                  ),
                  if (!user.bottomBarOnTop) ...<Widget>[
                    // _OutrunSectionMarker(label: 'PINNED', p: p),
                    const PinnedAndTrayList(),
                  ],
                  if (user.taskManagerStats) const TaskbarStats(withTopDivider: false),
                  if (user.libreStats) const LibreStats(withTopDivider: false),
                  // _OutrunSectionMarker(label: 'CONTROL', p: p),
                  _OutrunNeonBox(
                    p: p,
                    inset: true,
                    child: const Padding(
                      padding: EdgeInsets.fromLTRB(6, 2, 6, 2),
                      child: BottomBar(),
                    ),
                  ),
                ],
              ),
            ),

            // ---- CRT scanline overlay ----
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: OutrunScanlinePainter(
                      p.text.withValues(alpha: p.isDark ? 0.04 : 0.03),
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

class _OutrunPalette {
  const _OutrunPalette({
    required this.bg,
    required this.text,
    required this.accent,
    required this.grid,
    required this.palm,
    required this.glowStrength,
    required this.isDark,
  });

  factory _OutrunPalette.fromTheme() {
    final bool isDark = Design.background.computeLuminance() < 0.5;
    final Color accent = Design.accent;
    final Color text = Design.text;
    return _OutrunPalette(
      bg: Design.background,
      text: text,
      accent: accent,
      grid: accent.withValues(alpha: isDark ? 0.22 : 0.18),
      palm: Color.alphaBlend(
        Colors.black.withValues(alpha: 0.78),
        Design.background,
      ),
      glowStrength: (Design.gradientAlpha.clamp(0, 255)) / 255.0,
      isDark: isDark,
    );
  }

  final Color bg;
  final Color text;
  final Color accent;
  final Color grid;
  final Color palm;
  final double glowStrength;
  final bool isDark;
}

// ---------------------------------------------------------------------------
// Background ground — sunset, grid, palms
// ---------------------------------------------------------------------------

class _OutrunGround extends StatelessWidget {
  const _OutrunGround({required this.p, required this.hasBackdrop});

  final _OutrunPalette p;
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
          color: p.bg.withValues(alpha: hasBackdrop ? 0.82 : 0.98),
        ),
        child: Stack(
          children: <Widget>[
            if (Design.hasBackdrop) const StableBackdrop(),

            // Setting-sun gradient band
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 90,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      const Color(0xFFFF00AA).withValues(alpha: p.isDark ? 0.30 : 0.22),
                      const Color(0xFFFF7700).withValues(alpha: p.isDark ? 0.18 : 0.12),
                      const Color(0xFFFFD700).withValues(alpha: p.isDark ? 0.06 : 0.04),
                      Colors.transparent,
                    ],
                    stops: const <double>[0.0, 0.35, 0.65, 1.0],
                  ),
                ),
              ),
            ),

            // The sun orb
            Positioned(
              top: 18,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: <Color>[
                        const Color(0xFFFFD700).withValues(alpha: p.isDark ? 0.35 : 0.25),
                        const Color(0xFFFF00AA).withValues(alpha: p.isDark ? 0.15 : 0.10),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Perspective highway grid
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: Outrun2GridPainter(color: p.grid),
                ),
              ),
            ),

            // Palm silhouettes — left
            Positioned(
              top: 8,
              left: 6,
              width: 44,
              height: 68,
              child: CustomPaint(
                painter: _OutrunPalmPainter(color: p.palm),
              ),
            ),

            // Palm silhouettes — right
            Positioned(
              top: 14,
              right: 10,
              width: 38,
              height: 58,
              child: CustomPaint(
                painter: _OutrunPalmPainter(color: p.palm),
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

class _OutrunSectionMarker extends StatelessWidget {
  const _OutrunSectionMarker({required this.label, required this.p});

  final String label;
  final _OutrunPalette p;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 4, 3),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 8,
            height: 8,
            child: CustomPaint(
              painter: _OutrunChevronPainter(color: p.accent),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: p.accent,
              fontFamily: Design.uiFontFamily,
              fontSize: Design.baseFontSize - 1,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.2,
              height: 1,
              shadows: <Shadow>[
                Shadow(
                  color: p.accent.withValues(alpha: 0.75),
                  blurRadius: 10,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[
                    p.accent.withValues(alpha: 0.55),
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

class _OutrunNeonBox extends StatelessWidget {
  const _OutrunNeonBox({
    required this.p,
    required this.child,
    this.inset = false,
  });

  final _OutrunPalette p;
  final Widget child;
  final bool inset;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: inset ? p.bg.withValues(alpha: p.isDark ? 0.45 : 0.55) : p.bg.withValues(alpha: p.isDark ? 0.72 : 0.82),
        borderRadius: BorderRadius.circular(Design.borderRadius),
        border: Border.all(
          color: p.accent,
          width: 1.2,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: p.accent.withValues(alpha: 0.30 + p.glowStrength * 0.15),
            blurRadius: 10,
            spreadRadius: -2,
          ),
          if (!inset)
            BoxShadow(
              color: p.accent.withValues(alpha: 0.12),
              blurRadius: 20,
              spreadRadius: 0,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Design.borderRadius),
        child: child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Painters
// ---------------------------------------------------------------------------

class _OutrunChevronPainter extends CustomPainter {
  const _OutrunChevronPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = color;
    final Path path = Path()
      ..moveTo(0, size.height * 0.5)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _OutrunChevronPainter oldDelegate) => oldDelegate.color != color;
}

/// Perspective highway grid: vertical lines converge to a vanishing point near
/// the top-center horizon; horizontal lines get exponentially tighter upward.
class Outrun2GridPainter extends CustomPainter {
  const Outrun2GridPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final double horizonY = size.height * 0.28;
    final double centerX = size.width / 2;

    // Vertical perspective lines (highway lanes)
    for (int i = -6; i <= 6; i++) {
      final double t = i / 6.0;
      final double bottomX = centerX + t * size.width * 1.1;
      canvas.drawLine(
        Offset(centerX, horizonY),
        Offset(bottomX, size.height),
        paint..strokeWidth = (i == 0 ? 1.2 : 0.7),
      );
    }

    // Horizontal road segments — exponential perspective spacing
    for (int i = 0; i < 18; i++) {
      final double t = i / 18.0;
      final double y = size.height - (size.height - horizonY) * (1 - pow(t, 3).toDouble());
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        paint..strokeWidth = (1.0 - t * 0.6).clamp(0.4, 1.0),
      );
    }
  }

  @override
  bool shouldRepaint(covariant Outrun2GridPainter oldDelegate) => oldDelegate.color != color;
}

/// Stylized palm-tree silhouette — curved trunk and spiky fronds.
class _OutrunPalmPainter extends CustomPainter {
  const _OutrunPalmPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final double w = size.width;
    final double h = size.height;

    // Trunk — curved
    final Path trunk = Path()
      ..moveTo(w * 0.65, h)
      ..quadraticBezierTo(w * 0.55, h * 0.55, w * 0.48, h * 0.18)
      ..lineTo(w * 0.42, h * 0.18)
      ..quadraticBezierTo(w * 0.50, h * 0.55, w * 0.58, h)
      ..close();
    canvas.drawPath(trunk, paint);

    // Fronds radiating from crown
    for (int i = 0; i < 7; i++) {
      final double angle = -pi / 2 + (i - 3) * 0.35;
      final double len = h * 0.38;
      final double cx = w * 0.45;
      final double cy = h * 0.18;

      final Path frond = Path()
        ..moveTo(cx, cy)
        ..quadraticBezierTo(
          cx + cos(angle - 0.25) * len * 0.5,
          cy + sin(angle - 0.25) * len * 0.5,
          cx + cos(angle) * len,
          cy + sin(angle) * len,
        )
        ..lineTo(
          cx + cos(angle + 0.18) * len * 0.88,
          cy + sin(angle + 0.18) * len * 0.88,
        )
        ..quadraticBezierTo(
          cx + cos(angle + 0.08) * len * 0.48,
          cy + sin(angle + 0.08) * len * 0.48,
          cx,
          cy,
        )
        ..close();
      canvas.drawPath(frond, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _OutrunPalmPainter oldDelegate) => oldDelegate.color != color;
}

/// Soft CRT scanlines for that arcade-monitor feel.
class OutrunScanlinePainter extends CustomPainter {
  const OutrunScanlinePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (double y = 0; y < size.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant OutrunScanlinePainter oldDelegate) => oldDelegate.color != color;
}
