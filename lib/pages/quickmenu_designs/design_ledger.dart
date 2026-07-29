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

/// "Ledger" turns the QuickMenu into a ruled accounting page: a punched
/// binder-hole margin runs down the far left, a folded page-corner marks
/// the top right, and every section reads like a ledger line — label,
/// dotted leader, page number — closed off by a double rule. Where Vector
/// is an instrument HUD and Matrix is a stack of floating cards, Ledger
/// stays flat and paper-like: no glow, no shadowed panels, just ruled
/// lines and print-shop restraint.
class MainMenuLedgerWidget extends StatelessWidget {
  const MainMenuLedgerWidget({super.key});

  static const double _marginWidth = 18;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active theme changes.
    final _LedgerPalette p = _LedgerPalette.fromTheme();
    final bool hasBackdrop = user.activeBackdropPath.isNotEmpty;

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: 210,
        maxHeight: MediaQuery.of(context).size.height - 50,
      ),
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Design.borderRadius),
          child: Stack(
            children: <Widget>[
              Positioned.fill(child: _LedgerGround(p: p, hasBackdrop: hasBackdrop)),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _LedgerMarginPainter(p: p)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(_marginWidth + 8, 7, 8, 7),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (!user.quickActionsAtBottom) ...<Widget>[
                      // _LedgerHeading(label: 'QUICK ACTIONS', code: '01', p: p),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(2, 2, 2, 4),
                        child: TopBar(),
                      ),
                    ] else if (user.bottomBarOnTop) ...<Widget>[
                      // _LedgerHeading(label: 'PINNED / TRAY', code: '01', p: p),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(2, 2, 2, 4),
                        child: PinnedAndTrayList(),
                      ),
                    ] else
                      const SizedBox(height: 3),
                    _LedgerHeading(label: 'WINDOWS', code: '02', p: p),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(2, 2, 2, 2),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(color: p.rule, width: 0.5),
                            bottom: BorderSide(color: p.rule, width: 0.5),
                          ),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 3),
                          child: TaskBar(),
                        ),
                      ),
                    ),
                    if (!user.bottomBarOnTop) ...<Widget>[
                      _LedgerHeading(label: 'PINNED / TRAY', code: '03', p: p),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(2, 2, 2, 4),
                        child: PinnedAndTrayList(),
                      ),
                    ],
                    if (user.taskManagerStats) const TaskbarStats(withTopDivider: false),
                    if (user.libreStats) const LibreStats(withTopDivider: false),
                    _LedgerHeading(label: 'CONTROL', code: '04', p: p),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(2, 2, 2, 0),
                      child: BottomBar(),
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

class _LedgerPalette {
  const _LedgerPalette({
    required this.paper,
    required this.ink,
    required this.stamp,
    required this.faint,
    required this.rule,
    required this.edge,
    required this.hole,
    required this.holeRing,
    required this.isDark,
  });

  factory _LedgerPalette.fromTheme() {
    final bool isDark = Design.background.computeLuminance() < 0.5;
    final Color ink = Design.text;
    final Color stamp = Design.accent;
    return _LedgerPalette(
      paper: Design.background,
      ink: ink,
      stamp: stamp,
      faint: ink.withValues(alpha: isDark ? 0.42 : 0.5),
      rule: ink.withValues(alpha: isDark ? 0.16 : 0.2),
      edge: ink.withValues(alpha: isDark ? 0.10 : 0.16),
      hole: Design.background,
      holeRing: ink.withValues(alpha: isDark ? 0.28 : 0.34),
      isDark: isDark,
    );
  }

  final Color paper;
  final Color ink;
  final Color stamp;
  final Color faint;
  final Color rule;
  final Color edge;
  final Color hole;
  final Color holeRing;
  final bool isDark;
}

class _LedgerGround extends StatelessWidget {
  const _LedgerGround({required this.p, required this.hasBackdrop});

  final _LedgerPalette p;
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
          color: p.paper.withValues(alpha: hasBackdrop ? 0.88 : 0.98),
          border: Border.all(color: p.edge, width: 0.5),
        ),
        child: Stack(
          children: <Widget>[
            if (Design.hasBackdrop) const StableBackdrop(),
            // Folded page-corner, top right: two thin strokes standing in
            // for a dog-eared corner rather than a filled shape, so it
            // stays subtle against any backdrop.
            Positioned(
              top: 0,
              right: 0,
              child: IgnorePointer(
                child: CustomPaint(
                  size: const Size(20, 20),
                  painter: _PageFoldPainter(color: p.rule),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Binder margin: a hairline rule the full height of the panel, with a
/// short run of hollow punch-holes near the top — just enough to read as
/// "ledger page", without pretending to be a literal 3-ring binder.
class _LedgerMarginPainter extends CustomPainter {
  const _LedgerMarginPainter({required this.p});

  final _LedgerPalette p;

  static const double _ruleX = MainMenuLedgerWidget._marginWidth;
  static const double _holeR = 2.3;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint rule = Paint()
      ..color = p.rule
      ..strokeWidth = 0.6;
    canvas.drawLine(const Offset(_ruleX, 6), Offset(_ruleX, size.height - 6), rule);

    final Paint ring = Paint()
      ..color = p.holeRing
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    final Paint fill = Paint()..color = p.hole;

    const double holeX = MainMenuLedgerWidget._marginWidth / 2;
    double y = 14;
    while (y < size.height - 10) {
      canvas.drawCircle(Offset(holeX, y), _holeR, fill);
      canvas.drawCircle(Offset(holeX, y), _holeR, ring);
      y += 26;
    }
  }

  @override
  bool shouldRepaint(covariant _LedgerMarginPainter oldDelegate) =>
      oldDelegate.p.rule != p.rule || oldDelegate.p.holeRing != p.holeRing;
}

class _PageFoldPainter extends CustomPainter {
  const _PageFoldPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint stroke = Paint()
      ..color = color
      ..strokeWidth = 0.6
      ..style = PaintingStyle.stroke;
    final Path fold = Path()
      ..moveTo(size.width - 14, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, 14)
      ..moveTo(size.width - 9, 0)
      ..lineTo(size.width, 9);
    canvas.drawPath(fold, stroke);
  }

  @override
  bool shouldRepaint(covariant _PageFoldPainter oldDelegate) => oldDelegate.color != color;
}

/// Ledger-line section header: LABEL ····················· 0N, closed
/// with a single hairline. The number sits at the margin like a page
/// reference, reversed from a typical index — this is a page of entries,
/// not an instrument readout.
class _LedgerHeading extends StatelessWidget {
  const _LedgerHeading({required this.label, required this.code, required this.p});

  final String label;
  final String code;
  final _LedgerPalette p;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 5, 2, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              color: p.ink,
              fontFamily: Design.uiFontFamily,
              fontSize: Design.baseFontSize - 1.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
              height: 1,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 1.5),
              child: CustomPaint(painter: _DottedLeaderPainter(color: p.faint)),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            code,
            style: TextStyle(
              color: p.stamp,
              fontFamily: Design.uiFontFamily,
              fontSize: Design.baseFontSize - 1.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _DottedLeaderPainter extends CustomPainter {
  const _DottedLeaderPainter({required this.color});

  final Color color;
  static const double _dot = 1.1;
  static const double _gap = 3.5;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = color;
    double x = 0;
    final double y = size.height / 2;
    while (x < size.width) {
      canvas.drawCircle(Offset(x, y), _dot / 2, paint);
      x += _gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DottedLeaderPainter oldDelegate) => oldDelegate.color != color;
}
