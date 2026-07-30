// ignore_for_file: unused_element

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

/// "Outrun" QuickMenu design — a 1980s Synthwave / Miami Vice aesthetic.
///
/// The menu drops into a neo-noir night highway: a deep purple void overlaid
/// with a glowing wireframe perspective grid and a retro sliced sunset at the
/// top. The UI components are framed in glowing neon tubes (cyan and magenta),
/// with bold, high-contrast monospaced typography.
class MainMenuOutrunWidget extends StatelessWidget {
  const MainMenuOutrunWidget({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // register as theme-dependent so Design.* values update live
    final _OutrunPalette p = _OutrunPalette.fromTheme();
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
            // ---- Neon Highway Ground ----
            Positioned.fill(
              child: RepaintBoundary(
                child: _OutrunGround(p: p, hasBackdrop: hasBackdrop),
              ),
            ),

            // ---- HUD Content ----
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (!user.quickActionsAtBottom) ...<Widget>[
                    // _OutrunHeader(label: 'SYSTEM', p: p),
                    // const SizedBox(height: 4),
                    _NeonBox(
                      p: p,
                      color: p.cyan,
                      child: const Padding(
                        padding: EdgeInsets.fromLTRB(6, 4, 6, 4),
                        child: TopBar(),
                      ),
                    ),
                  ] else ...<Widget>[
                    // _OutrunHeader(label: 'TRAY', p: p),
                    const PinnedAndTrayList(),
                  ], //else
                  // const SizedBox(height: 4),
                  DragToMoveArea(child: _OutrunHeader(label: 'WINDOWS', p: p)),
                  _NeonBox(
                    p: p,
                    color: p.magenta,
                    child: const Padding(
                      padding: EdgeInsets.fromLTRB(6, 4, 6, 4),
                      child: TaskBar(),
                    ),
                  ),
                  if (!user.bottomBarOnTop) ...<Widget>[
                    // _OutrunHeader(label: 'TRAY', p: p),
                    const PinnedAndTrayList(),
                  ],
                  if (user.taskManagerStats) const TaskbarStats(withTopDivider: false),
                  if (user.libreStats) const LibreStats(withTopDivider: false),
                  // _OutrunHeader(label: 'CONTROL', p: p),
                  _NeonBox(
                    p: p,
                    color: p.cyan,
                    child: const Padding(
                      padding: EdgeInsets.fromLTRB(6, 0, 6, 0),
                      child: BottomBar(),
                    ),
                  ),
                ],
              ),
            ),

            // ---- Glow Overlays ----
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(painter: _OutrunEdgePainter(p: p)),
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

class _OutrunPalette {
  const _OutrunPalette({
    required this.bg,
    required this.ink,
    required this.cyan,
    required this.magenta,
    required this.sunset1,
    required this.sunset2,
    required this.sunset3,
    required this.grid,
    required this.isDark,
  });

  factory _OutrunPalette.fromTheme() {
    final bool isDark = Design.background.computeLuminance() < 0.5;
    return _OutrunPalette(
      bg: Design.background,
      ink: Design.text,
      cyan: Design.accent, // Using accent as primary neon (Cyan in dark mode)
      magenta: isDark ? const Color(0xffFF2A6D) : const Color(0xffD300C5),
      sunset1: isDark ? const Color(0xffFFE53B) : const Color(0xffFFD300),
      sunset2: isDark ? const Color(0xffFF2A6D) : const Color(0xffFF8A00),
      sunset3: isDark ? const Color(0xff7700a6) : const Color(0xff7700a6),
      grid: isDark ? const Color(0xffFF2A6D) : const Color(0xffD300C5),
      isDark: isDark,
    );
  }

  final Color bg;
  final Color ink;
  final Color cyan;
  final Color magenta;
  final Color sunset1;
  final Color sunset2;
  final Color sunset3;
  final Color grid;
  final bool isDark;
}

// ---------------------------------------------------------------------------
// Ground & Backdrop
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
          color: p.bg.withValues(alpha: hasBackdrop ? 0.85 : 0.98),
        ),
        child: Stack(
          children: <Widget>[
            if (Design.hasBackdrop) const StableBackdrop(),
            // Retro Sunset
            // Positioned(
            //   top: 0,
            //   left: 0,
            //   right: 0,
            //   height: 80,
            //   child: IgnorePointer(
            //     child: CustomPaint(painter: _SunsetPainter(p: p)),
            //   ),
            // ),
            // Wireframe Grid
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _OutrunPerspectiveGridPainter(color: p.grid.withValues(alpha: p.isDark ? 0.25 : 0.15)),
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

/// Synthwave section header: `< // LABEL >`
class _OutrunHeader extends StatelessWidget {
  const _OutrunHeader({required this.label, required this.p});

  final String label;
  final _OutrunPalette p;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
      child: Row(
        children: <Widget>[
          Text(
            '// ',
            style: TextStyle(
              color: p.magenta,
              fontFamily: Design.uiFontFamily,
              fontSize: Design.baseFontSize - 1,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: p.cyan,
              fontFamily: Design.uiFontFamily,
              fontSize: Design.baseFontSize - 1,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.0,
              shadows: <Shadow>[
                Shadow(color: p.cyan.withValues(alpha: 0.8), blurRadius: 4),
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
                    p.magenta.withValues(alpha: 0.8),
                    p.magenta.withValues(alpha: 0.0),
                  ],
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(color: p.magenta.withValues(alpha: 0.5), blurRadius: 2),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A glowing neon-bordered box for UI elements.
class _NeonBox extends StatelessWidget {
  const _NeonBox({required this.p, required this.child, required this.color});

  final _OutrunPalette p;
  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: p.bg.withValues(alpha: p.isDark ? 0.7 : 0.5),
        border: Border.all(color: color, width: 1.2),
        borderRadius: BorderRadius.circular(2),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: color.withValues(alpha: p.isDark ? 0.4 : 0.2),
            blurRadius: 6,
            spreadRadius: 1,
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

/// The classic 80s sliced sunset.
class _SunsetPainter extends CustomPainter {
  const _SunsetPainter({required this.p});

  final _OutrunPalette p;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Rect.fromLTWH(0, 0, size.width, size.height);

    // Sky gradient
    final Paint skyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[p.sunset3, p.sunset2, p.sunset1],
      ).createShader(rect);
    canvas.drawRect(rect, skyPaint);

    // Sun circle
    final double sunRadius = size.width * 0.3;
    final Rect sunRect = Rect.fromCircle(center: Offset(size.width / 2, size.height * 0.8), radius: sunRadius);
    final Paint sunPaint = Paint()
      ..shader = RadialGradient(
        colors: <Color>[p.sunset1, p.sunset2],
      ).createShader(sunRect);
    canvas.drawCircle(sunRect.center, sunRadius, sunPaint);

    // Slices (mask out lines)
    final Paint slicePaint = Paint()
      ..color = p.bg.withValues(alpha: 1.0)
      ..blendMode = BlendMode.srcOut;
    for (int i = 0; i < 6; i++) {
      final double y = size.height * 0.5 + (i * 5.0) + (i * i * 1.5);
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 2.0 + i * 0.5), slicePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SunsetPainter oldDelegate) => oldDelegate.p != p;
}

/// Perspective grid moving toward the horizon.
class _OutrunPerspectiveGridPainter extends CustomPainter {
  const _OutrunPerspectiveGridPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final double horizon = size.height * 0.35;
    final double bottom = size.height;
    final double cx = size.width / 2;

    // Horizontal lines (exponential spacing)
    for (int i = 1; i <= 12; i++) {
      final double t = i / 12.0;
      final double y = horizon + (bottom - horizon) * (t * t);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Vertical lines converging to center
    for (int i = -10; i <= 10; i++) {
      if (i == 0) continue;
      final double xBottom = cx + (i * (size.width / 8.0));
      canvas.drawLine(Offset(xBottom, bottom), Offset(cx, horizon), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _OutrunPerspectiveGridPainter oldDelegate) => oldDelegate.color != color;
}

/// Neon corner accents and edge glows.
class _OutrunEdgePainter extends CustomPainter {
  const _OutrunEdgePainter({required this.p});

  final _OutrunPalette p;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint cyanPaint = Paint()
      ..color = p.cyan
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    // Top-left corner accent
    canvas.drawLine(const Offset(0, 15), const Offset(0, 0), cyanPaint);
    canvas.drawLine(const Offset(0, 0), const Offset(15, 0), cyanPaint);

    // Bottom-right corner accent
    canvas.drawLine(Offset(size.width, size.height - 15), Offset(size.width, size.height), cyanPaint);
    canvas.drawLine(Offset(size.width, size.height), Offset(size.width - 15, size.height), cyanPaint);

    final Paint magentaPaint = Paint()
      ..color = p.magenta
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Top-right corner accent
    canvas.drawLine(Offset(size.width - 15, 0), Offset(size.width, 0), magentaPaint);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, 15), magentaPaint);

    // Bottom-left corner accent
    canvas.drawLine(Offset(15, size.height), Offset(0, size.height), magentaPaint);
    canvas.drawLine(Offset(0, size.height), Offset(0, size.height - 15), magentaPaint);
  }

  @override
  bool shouldRepaint(covariant _OutrunEdgePainter oldDelegate) => oldDelegate.p != p;
}
