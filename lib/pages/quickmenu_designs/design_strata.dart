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

/// "Strata" QuickMenu design — a geological field-survey aesthetic.
///
/// The panel reads as a core sample: horizontal sediment bands of
/// shifting density sit beneath the content, a hairline mineral vein
/// runs along each section rule, and small drill-mark dots sit in the
/// corners, as if the panel had been extracted and logged like rock.
class MainMenuStrataWidget extends StatelessWidget {
  const MainMenuStrataWidget({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // register as theme-dependent so Design.* values update live
    final _StrataPalette p = _StrataPalette.fromTheme();
    final bool hasBackdrop = user.activeBackdropPath.isNotEmpty;

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: 203,
        maxHeight: MediaQuery.of(context).size.height - 40,
      ),
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Design.borderRadius),
          child: Stack(
            children: <Widget>[
              // ---- Core Body ----
              Positioned.fill(
                child: RepaintBoundary(
                  child: _StrataGround(p: p, hasBackdrop: hasBackdrop),
                ),
              ),

              // ---- Log Content ----
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (!user.quickActionsAtBottom) ...<Widget>[
                      const SizedBox(height: 4),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(4, 0, 4, 0),
                        child: TopBar(),
                      ),
                    ] else if (user.bottomBarOnTop) ...<Widget>[
                      _StrataHeader(label: 'DOCK', index: '01', p: p),
                      const PinnedAndTrayList(),
                    ] else
                      const SizedBox(height: 4),
                    DragToMoveArea(
                      child: _StrataHeader(label: 'WINDOWS', index: '02', p: p),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
                      padding: const EdgeInsets.only(left: 6),
                      decoration: BoxDecoration(
                        border: Border(left: BorderSide(color: p.accent, width: 2)),
                      ),
                      child: const RepaintBoundary(
                        child: TaskBar(),
                      ),
                    ),
                    if (!user.bottomBarOnTop) ...<Widget>[
                      _StrataHeader(label: 'TRAY', index: '03', p: p),
                      const PinnedAndTrayList(),
                    ],
                    if (user.taskManagerStats) const TaskbarStats(withTopDivider: false),
                    if (user.libreStats) const LibreStats(withTopDivider: false),
                    _StrataHeader(label: 'CONTROL', index: '04', p: p),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(4, 2, 4, 0),
                      child: BottomBar(),
                    ),
                  ],
                ),
              ),

              // ---- Registration Marks ----
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _StrataCorePainter(accent: p.accent, isDark: p.isDark),
                    ),
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
// Palette & Theme Tokens
// ---------------------------------------------------------------------------

class _StrataPalette {
  const _StrataPalette({
    required this.paper,
    required this.ink,
    required this.accent,
    required this.faint,
    required this.edge,
    required this.isDark,
  });

  factory _StrataPalette.fromTheme() {
    final bool isDark = Design.background.computeLuminance() < 0.5;
    return _StrataPalette(
      paper: Design.background,
      ink: Design.text,
      accent: Design.accent,
      faint: Design.text.withValues(alpha: isDark ? 0.06 : 0.05),
      edge: Design.text.withValues(alpha: isDark ? 0.14 : 0.18),
      isDark: isDark,
    );
  }

  final Color paper;
  final Color ink;
  final Color accent;
  final Color faint;
  final Color edge;
  final bool isDark;
}

// ---------------------------------------------------------------------------
// Ground & Backdrop
// ---------------------------------------------------------------------------

class _StrataGround extends StatelessWidget {
  const _StrataGround({required this.p, required this.hasBackdrop});

  final _StrataPalette p;
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
          border: Border.all(color: p.edge, width: 0.5),
        ),
        child: Stack(
          children: <Widget>[
            if (Design.hasBackdrop) const StableBackdrop(),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _StrataLayerPainter(ink: p.ink, accent: p.accent, isDark: p.isDark),
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
// Headers
// ---------------------------------------------------------------------------

/// Field-log section header: a filled index chip (`01`) followed by the
/// label and a double hairline rule, evoking a strata log entry.
class _StrataHeader extends StatelessWidget {
  const _StrataHeader({required this.label, required this.index, required this.p});

  final String label;
  final String index;
  final _StrataPalette p;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 3),
      child: Row(
        children: <Widget>[
          Container(
            width: 16,
            height: 14,
            alignment: Alignment.center,
            color: p.accent,
            child: Text(
              index,
              style: TextStyle(
                color: p.paper,
                fontFamily: Design.uiFontFamily,
                fontSize: Design.baseFontSize - 3,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: p.ink,
              fontFamily: Design.uiFontFamily,
              fontSize: Design.baseFontSize - 2,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              height: 1,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(height: 1, color: p.ink.withValues(alpha: 0.5)),
                const SizedBox(height: 1.5),
                Container(height: 0.5, color: p.accent.withValues(alpha: 0.6)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Painters
// ---------------------------------------------------------------------------

/// Horizontal sediment bands of irregular thickness, drawn from a mix of
/// ink and accent at low alpha, with a slightly wavy boundary per band.
class _StrataLayerPainter extends CustomPainter {
  const _StrataLayerPainter({required this.ink, required this.accent, required this.isDark});

  final Color ink;
  final Color accent;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final double baseAlpha = isDark ? 0.05 : 0.04;
    double y = 0;
    int i = 0;
    // Pseudo-random but deterministic band thicknesses.
    final List<double> thicknesses = <double>[14, 22, 9, 30, 16, 11, 25, 18, 13, 20];

    while (y < size.height) {
      final double h = thicknesses[i % thicknesses.length];
      final bool accented = i.isOdd;
      final Paint paint = Paint()
        ..color = (accented ? accent : ink).withValues(alpha: baseAlpha * (accented ? 1.4 : 1.0));

      final Path band = Path()..moveTo(0, y);
      for (double x = 0; x <= size.width; x += 20) {
        final double wobble = (((x / 20).floor() + i) % 2 == 0) ? 0.6 : -0.6;
        band.lineTo(x, y + wobble);
      }
      band.lineTo(size.width, y + h);
      for (double x = size.width; x >= 0; x -= 20) {
        final double wobble = (((x / 20).floor() + i) % 2 == 0) ? -0.6 : 0.6;
        band.lineTo(x, y + h + wobble);
      }
      band.close();

      canvas.drawPath(band, paint);
      y += h;
      i++;
    }
  }

  @override
  bool shouldRepaint(covariant _StrataLayerPainter oldDelegate) =>
      oldDelegate.ink != ink || oldDelegate.accent != accent || oldDelegate.isDark != isDark;
}

/// Drill-mark registration dots with a short tick, one per corner —
/// the panel's "core sample" log marks.
class _StrataCorePainter extends CustomPainter {
  const _StrataCorePainter({required this.accent, required this.isDark});

  final Color accent;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint dot = Paint()..color = accent.withValues(alpha: isDark ? 0.9 : 0.75);
    final Paint tick = Paint()
      ..color = accent.withValues(alpha: isDark ? 0.5 : 0.4)
      ..strokeWidth = 1;

    void mark(Offset center, Offset tickEnd) {
      canvas.drawCircle(center, 1.8, dot);
      canvas.drawLine(center, tickEnd, tick);
    }

    mark(const Offset(7, 7), const Offset(7, 16));
    mark(Offset(size.width - 7, 7), Offset(size.width - 7, 16));
    mark(Offset(7, size.height - 7), Offset(7, size.height - 16));
    mark(Offset(size.width - 7, size.height - 7), Offset(size.width - 7, size.height - 16));
  }

  @override
  bool shouldRepaint(covariant _StrataCorePainter oldDelegate) =>
      oldDelegate.accent != accent || oldDelegate.isDark != isDark;
}
