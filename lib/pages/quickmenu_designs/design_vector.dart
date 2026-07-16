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

/// "Vector" turns the QuickMenu into a heads-up flight instrument: there is
/// no boxed panel — the content floats on dark glass held together by four
/// accent reticle brackets and mid-edge alignment ticks. Every functional
/// zone is indexed like an avionics page (`01 ▏QUICK ACTIONS`, `02 ▏WINDOWS`…)
/// with a hairline rule, the window switcher sits inside a faint "radar
/// screen" inset, and a soft CRT scanline texture runs under everything.
class MainMenuVectorWidget extends StatelessWidget {
  const MainMenuVectorWidget({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active theme changes.
    final _VectorPalette p = _VectorPalette.fromTheme();
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
              Positioned.fill(child: _VectorGround(p: p, hasBackdrop: hasBackdrop)),
              Padding(
                padding: const EdgeInsets.fromLTRB(7, 6, 7, 7),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (!user.quickActionsAtBottom) ...<Widget>[
                      // _SectionIndex(index: '01', label: 'QUICK ACTIONS', p: p),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(6, 1, 8, 3),
                        child: TopBar(),
                      ),
                    ] else if (user.bottomBarOnTop) ...<Widget>[
                      // _SectionIndex(index: '01', label: 'PINNED / TRAY', p: p),
                      const PinnedAndTrayList(),
                    ] else
                      const SizedBox(height: 2),
                    _SectionIndex(index: '¤', label: 'WINDOWS', p: p),
                    // The switcher reads as a radar screen: a faint signal
                    // wash with a thin signal border around the plain list.
                    Container(
                      margin: const EdgeInsets.fromLTRB(4, 2, 4, 2),
                      decoration: BoxDecoration(
                        color: p.screen,
                        border: Border.all(color: p.screenEdge, width: 0.5),
                      ),
                      child: const TaskBar(),
                    ),
                    if (!user.bottomBarOnTop) ...<Widget>[
                      _SectionIndex(index: '¤', label: 'PINNED / TRAY', p: p),
                      const PinnedAndTrayList(),
                    ],
                    if (user.taskManagerStats) const TaskbarStats(withTopDivider: false),
                    if (user.libreStats) const LibreStats(withTopDivider: false),
                    _SectionIndex(index: '¤', label: 'CONTROL', p: p),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(2, 1, 4, 0),
                      child: BottomBar(),
                    ),
                  ],
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _VectorReticlePainter(accent: p.signal, tick: p.tick)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VectorPalette {
  const _VectorPalette({
    required this.glass,
    required this.ink,
    required this.signal,
    required this.faint,
    required this.hairline,
    required this.edge,
    required this.tick,
    required this.screen,
    required this.screenEdge,
    required this.isDark,
  });

  factory _VectorPalette.fromTheme() {
    final bool isDark = Design.background.computeLuminance() < 0.5;
    final Color ink = Design.text;
    final Color signal = Design.accent;
    return _VectorPalette(
      glass: Design.background,
      ink: ink,
      signal: signal,
      faint: ink.withValues(alpha: isDark ? 0.46 : 0.55),
      hairline: ink.withValues(alpha: isDark ? 0.14 : 0.18),
      edge: ink.withValues(alpha: isDark ? 0.10 : 0.16),
      tick: ink.withValues(alpha: isDark ? 0.38 : 0.45),
      screen: signal.withValues(alpha: isDark ? 0.06 : 0.05),
      screenEdge: signal.withValues(alpha: isDark ? 0.24 : 0.30),
      isDark: isDark,
    );
  }

  final Color glass;
  final Color ink;
  final Color signal;
  final Color faint;
  final Color hairline;
  final Color edge;
  final Color tick;
  final Color screen;
  final Color screenEdge;
  final bool isDark;
}

class _VectorGround extends StatelessWidget {
  const _VectorGround({required this.p, required this.hasBackdrop});

  final _VectorPalette p;
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
          color: p.glass.withValues(alpha: hasBackdrop ? 0.86 : 0.97),
          border: Border.all(color: p.edge, width: 0.5),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: p.isDark ? 0.30 : 0.12),
              blurRadius: 24,
              spreadRadius: -6,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: <Widget>[
            if (Design.hasBackdrop) const StableBackdrop(),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _VectorScanPainter(
                    p.ink.withValues(alpha: p.isDark ? 0.045 : 0.035),
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

/// Avionics page marker: accent pip, index number and micro label, with a
/// hairline rule carrying the eye to the edge of the panel.
class _SectionIndex extends StatelessWidget {
  const _SectionIndex({required this.index, required this.label, required this.p});

  final String index;
  final String label;
  final _VectorPalette p;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(5, 4, 3, 1),
      child: Row(
        children: <Widget>[
          Container(width: 3.5, height: 3.5, color: p.signal),
          const SizedBox(width: 5),
          Text(
            index,
            style: TextStyle(
              color: p.signal,
              fontFamily: Design.uiFontFamily,
              fontSize: Design.baseFontSize - 1,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              height: 1,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: p.faint,
              fontFamily: Design.uiFontFamily,
              fontSize: Design.baseFontSize - 1.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 2.2,
              height: 1,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Container(height: 0.5, color: p.hairline)),
        ],
      ),
    );
  }
}

/// The HUD signature: four accent corner brackets and mid-edge alignment
/// ticks. Deliberately no full frame — the glass stays open and airy.
class _VectorReticlePainter extends CustomPainter {
  const _VectorReticlePainter({required this.accent, required this.tick});

  final Color accent;
  final Color tick;

  static const double _inset = 2.5;
  static const double _len = 11;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint bracket = Paint()
      ..color = accent
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    final double right = size.width - _inset;
    final double bottom = size.height - _inset;

    final Path corners = Path()
      // Top-left
      ..moveTo(_inset, _inset + _len)
      ..lineTo(_inset, _inset)
      ..lineTo(_inset + _len, _inset)
      // Top-right
      ..moveTo(right - _len, _inset)
      ..lineTo(right, _inset)
      ..lineTo(right, _inset + _len)
      // Bottom-right
      ..moveTo(right, bottom - _len)
      ..lineTo(right, bottom)
      ..lineTo(right - _len, bottom)
      // Bottom-left
      ..moveTo(_inset + _len, bottom)
      ..lineTo(_inset, bottom)
      ..lineTo(_inset, bottom - _len);
    canvas.drawPath(corners, bracket);

    final Paint tickPaint = Paint()
      ..color = tick
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.square;

    final double cx = size.width / 2;
    final double cy = size.height / 2;
    // Top / bottom center ticks.
    canvas.drawLine(Offset(cx, _inset - 0.5), Offset(cx, _inset + 4.5), tickPaint);
    canvas.drawLine(Offset(cx, bottom - 4.5), Offset(cx, bottom + 0.5), tickPaint);
    // Left / right center ticks.
    canvas.drawLine(Offset(_inset - 0.5, cy), Offset(_inset + 4.5, cy), tickPaint);
    canvas.drawLine(Offset(right - 4.5, cy), Offset(right + 0.5, cy), tickPaint);
  }

  @override
  bool shouldRepaint(covariant _VectorReticlePainter oldDelegate) =>
      oldDelegate.accent != accent || oldDelegate.tick != tick;
}

/// Soft CRT scanlines running under the whole panel.
class _VectorScanPainter extends CustomPainter {
  const _VectorScanPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 0.5;
    for (double y = 1.5; y < size.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _VectorScanPainter oldDelegate) => oldDelegate.color != color;
}
