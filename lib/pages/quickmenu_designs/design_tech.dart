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

/// "Tech" QuickMenu design — a Modern Smart Glass / Aerospace HUD aesthetic.
///
/// The menu discards retro terminal tropes in favor of a sleek, modern dashboard.
/// It uses frosted glass panels, soft glowing accent lines, highly rounded
/// corners, and a subtle blueprint dot-matrix underlay. Sections are marked
/// with minimalist geometric tags `[ • LABEL ]` and a glowing trailing line.
class MainMenuTechWidget extends StatelessWidget {
  const MainMenuTechWidget({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // register as theme-dependent so Design.* values update live
    final _TechPalette p = _TechPalette.fromTheme();
    final bool hasBackdrop = user.activeBackdropPath.isNotEmpty;

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: 203,
        maxHeight: MediaQuery.of(context).size.height - 40,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Design.borderRadius),
        child: Stack(
          children: <Widget>[
            // ---- Frosted Glass Body ----
            Positioned.fill(
              child: RepaintBoundary(
                child: _TechGround(p: p, hasBackdrop: hasBackdrop),
              ),
            ),

            // ---- Dashboard Content ----
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (!user.quickActionsAtBottom) ...<Widget>[
                    // _TechHeader(label: 'QUICK ACTIONS', p: p),
                    // const SizedBox(height: 4),
                    _TechCard(
                      p: p,
                      child: const Padding(
                        padding: EdgeInsets.fromLTRB(8, 6, 8, 6),
                        child: TopBar(),
                      ),
                    ),
                  ] else if (user.bottomBarOnTop) ...<Widget>[
                    // _TechHeader(label: 'SYSTEM TRAY', p: p),
                    const PinnedAndTrayList(),
                  ] else
                    const SizedBox(height: 4),
                  DragToMoveArea(child: _TechHeader(label: 'ACTIVE WINDOWS', p: p)),
                  _TechCard(
                    p: p,
                    inset: true,
                    child: const Padding(
                      padding: EdgeInsets.fromLTRB(6, 4, 6, 4),
                      child: TaskBar(),
                    ),
                  ),
                  if (!user.bottomBarOnTop) ...<Widget>[
                    // _TechHeader(label: 'SYSTEM TRAY', p: p),
                    const PinnedAndTrayList(),
                  ],
                  if (user.taskManagerStats) const TaskbarStats(withTopDivider: false),
                  if (user.libreStats) const LibreStats(withTopDivider: false),
                  // _TechHeader(label: 'CONTROL', p: p),
                  _TechCard(
                    p: p,
                    child: const Padding(
                      padding: EdgeInsets.fromLTRB(8, 2, 8, 2),
                      child: BottomBar(),
                    ),
                  ),
                ],
              ),
            ),

            // ---- HUD Overlays (Soft glowing edges) ----
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(painter: _TechHUDPainter(neon: p.neon, isDark: p.isDark)),
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
// Palette & Theme Tokens
// ---------------------------------------------------------------------------

class _TechPalette {
  const _TechPalette({
    required this.glass,
    required this.ink,
    required this.neon,
    required this.faint,
    required this.hairline,
    required this.edge,
    required this.screen,
    required this.cardBg,
    required this.isDark,
  });

  factory _TechPalette.fromTheme() {
    final bool isDark = Design.background.computeLuminance() < 0.5;
    final Color ink = Design.text;
    final Color neon = Design.accent;
    return _TechPalette(
      glass: Design.background,
      ink: ink,
      neon: neon,
      faint: ink.withValues(alpha: isDark ? 0.5 : 0.6),
      hairline: ink.withValues(alpha: isDark ? 0.15 : 0.1),
      edge: neon.withValues(alpha: isDark ? 0.2 : 0.15),
      screen: neon.withValues(alpha: isDark ? 0.04 : 0.03),
      cardBg: ink.withValues(alpha: isDark ? 0.03 : 0.02),
      isDark: isDark,
    );
  }

  final Color glass;
  final Color ink;
  final Color neon;
  final Color faint;
  final Color hairline;
  final Color edge;
  final Color screen;
  final Color cardBg;
  final bool isDark;
}

// ---------------------------------------------------------------------------
// Ground & Backdrop
// ---------------------------------------------------------------------------

class _TechGround extends StatelessWidget {
  const _TechGround({required this.p, required this.hasBackdrop});

  final _TechPalette p;
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
          color: p.glass.withValues(alpha: hasBackdrop ? 0.80 : 0.95),
        ),
        child: Stack(
          children: <Widget>[
            if (Design.hasBackdrop) const StableBackdrop(),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _TechDotMatrixPainter(
                    p.neon.withValues(alpha: p.isDark ? 0.08 : 0.05),
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
// UI Components
// ---------------------------------------------------------------------------

/// Modern minimalist section header: `[ • LABEL ]` with a glowing line extending.
class _TechHeader extends StatelessWidget {
  const _TechHeader({required this.label, required this.p});

  final String label;
  final _TechPalette p;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 4),
      child: Row(
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: p.neon,
              borderRadius: BorderRadius.circular(3),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: p.neon.withValues(alpha: 0.6),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: p.faint,
              fontFamily: Design.uiFontFamily,
              fontSize: Design.baseFontSize - 2,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
              height: 1,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[
                    p.hairline,
                    p.hairline.withValues(alpha: 0.0),
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

/// A modern frosted card container for housing UI strips.
class _TechCard extends StatelessWidget {
  const _TechCard({
    required this.p,
    required this.child,
    this.inset = false,
  });

  final _TechPalette p;
  final Widget child;
  final bool inset;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: p.cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: p.edge,
          width: 1,
        ),
        boxShadow: <BoxShadow>[
          if (!inset)
            BoxShadow(
              color: p.neon.withValues(alpha: p.isDark ? 0.05 : 0.02),
              blurRadius: 8,
              spreadRadius: 0,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// Painters
// ---------------------------------------------------------------------------

/// Fine dot-matrix blueprint pattern running under the whole panel.
class _TechDotMatrixPainter extends CustomPainter {
  const _TechDotMatrixPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = color;
    const double step = 16.0;
    const double radius = 1.2;

    for (double x = step; x < size.width; x += step) {
      for (double y = step; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TechDotMatrixPainter oldDelegate) => oldDelegate.color != color;
}

/// Soft glowing accents on the edges to simulate a high-end glass HUD.
class _TechHUDPainter extends CustomPainter {
  const _TechHUDPainter({required this.neon, required this.isDark});

  final Color neon;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint glowPaint = Paint()
      ..color = neon.withValues(alpha: isDark ? 0.8 : 0.5)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

    // Top right soft bracket
    final Path topRight = Path()
      ..moveTo(size.width - 40, 4)
      ..lineTo(size.width - 4, 4)
      ..lineTo(size.width - 4, 40);
    canvas.drawPath(topRight, glowPaint);

    // Bottom left soft bracket
    final Path bottomLeft = Path()
      ..moveTo(40, size.height - 4)
      ..lineTo(4, size.height - 4)
      ..lineTo(4, size.height - 40);
    canvas.drawPath(bottomLeft, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _TechHUDPainter oldDelegate) => oldDelegate.neon != neon || oldDelegate.isDark != isDark;
}
