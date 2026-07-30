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

/// A calibrated workshop control surface. Foundry groups every active area
/// into an engraved band, while the tiny footer indicators reflect the live
/// modules available in this instance of QuickMenu.
class MainMenuFoundryWidget extends StatelessWidget {
  const MainMenuFoundryWidget({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final _FoundryPalette palette = _FoundryPalette.fromTheme();
    final bool hasBackdrop = user.activeBackdropPath.isNotEmpty;

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: 203, maxHeight: MediaQuery.of(context).size.height - 50),
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Design.borderRadius),
          child: Stack(
            children: <Widget>[
              Positioned.fill(child: _FoundryGround(palette: palette, hasBackdrop: hasBackdrop)),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // _FoundryHeader(palette: palette),
                    if (!user.quickActionsAtBottom)
                      _FoundryBand(
                        index: '01',
                        label: 'ACTIONS',
                        palette: palette,
                        child: const Padding(padding: EdgeInsets.fromLTRB(3, 2, 3, 3), child: TopBar()),
                      )
                    else if (user.bottomBarOnTop)
                      _FoundryBand(index: '02', label: 'PINNED', palette: palette, child: const PinnedAndTrayList()),
                    DragToMoveArea(
                        child: _FoundryBand(index: '03', label: 'WINDOWS', palette: palette, child: const TaskBar())),
                    if (!user.bottomBarOnTop)
                      _FoundryBand(index: '04', label: 'PINNED', palette: palette, child: const PinnedAndTrayList()),
                    if (user.taskManagerStats) const TaskbarStats(withTopDivider: false),
                    if (user.libreStats) const LibreStats(withTopDivider: false),
                    _FoundryFooter(
                      palette: palette,
                      signals: <bool>[true, user.taskManagerStats, user.libreStats, hasBackdrop],
                    ),
                  ],
                ),
              ),
              Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _FoundryFramePainter(palette.accent)))),
            ],
          ),
        ),
      ),
    );
  }
}

class _FoundryPalette {
  const _FoundryPalette({required this.background, required this.text, required this.accent, required this.rule});

  factory _FoundryPalette.fromTheme() {
    final bool dark = Design.background.computeLuminance() < 0.5;
    return _FoundryPalette(
      background: Design.background,
      text: Design.text,
      accent: Design.accent,
      rule: Design.text.withValues(alpha: dark ? 0.17 : 0.20),
    );
  }

  final Color background;
  final Color text;
  final Color accent;
  final Color rule;
}

class _FoundryGround extends StatelessWidget {
  const _FoundryGround({required this.palette, required this.hasBackdrop});

  final _FoundryPalette palette;
  final bool hasBackdrop;

  @override
  Widget build(BuildContext context) {
    final List<double> points = Design.panelOpacityPoints;
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (Rect bounds) => LinearGradient(
        begin: panelAlignmentMap[Design.panelOpacityBegin] ?? Alignment.topCenter,
        end: panelAlignmentMap[Design.panelOpacityEnd] ?? Alignment.bottomCenter,
        stops: <double>[for (int i = 0; i < points.length; i += 2) points[i]],
        colors: <Color>[for (int i = 1; i < points.length; i += 2) Colors.white.withValues(alpha: points[i])],
      ).createShader(bounds),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.background.withValues(alpha: hasBackdrop ? 0.91 : 1),
          border: Border.all(color: palette.rule, width: 0.8),
        ),
        child: Stack(
          children: <Widget>[
            if (Design.hasBackdrop) const StableBackdrop(),
            Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _FoundryGrain(palette.rule)))),
          ],
        ),
      ),
    );
  }
}

// ignore: unused_element
class _FoundryHeader extends StatelessWidget {
  const _FoundryHeader({required this.palette});

  final _FoundryPalette palette;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(5, 2, 4, 5),
        child: Row(
          children: <Widget>[
            Container(width: 6, height: 6, color: palette.accent),
            const SizedBox(width: 7),
            Text(
              'TABAME  /  FOUNDRY',
              style: TextStyle(
                color: palette.text.withValues(alpha: 0.72),
                fontFamily: Design.uiFontFamily,
                fontSize: Design.baseFontSize - 1.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
            const Spacer(),
            Text(
              'LIVE',
              style: TextStyle(
                color: palette.accent,
                fontFamily: Design.uiFontFamily,
                fontSize: Design.baseFontSize - 2,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      );
}

class _FoundryBand extends StatelessWidget {
  const _FoundryBand({required this.index, required this.label, required this.palette, required this.child});

  final String index;
  final String label;
  final _FoundryPalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 3),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: palette.rule, width: 0.8))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 3, 4, 2),
              child: Row(
                children: <Widget>[
                  // Text(index, style: _bandStyle(palette.accent)),
                  // const SizedBox(width: 6),
                  Text(label, style: _bandStyle(palette.text.withValues(alpha: 0.58))),
                  const SizedBox(width: 7),
                  Expanded(child: Container(height: 0.5, color: palette.rule)),
                ],
              ),
            ),
            child,
          ],
        ),
      );

  TextStyle _bandStyle(Color color) => TextStyle(
        color: color,
        fontFamily: Design.uiFontFamily,
        fontSize: Design.baseFontSize - 2,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.3,
        height: 1,
      );
}

class _FoundryFooter extends StatelessWidget {
  const _FoundryFooter({required this.palette, required this.signals});

  final _FoundryPalette palette;
  final List<bool> signals;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(4, 2, 2, 1),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: palette.rule, width: 0.8))),
        child: Row(
          children: <Widget>[
            const Expanded(child: BottomBar()),
            for (final bool active in signals)
              Container(
                width: 4,
                height: 4,
                margin: const EdgeInsets.only(left: 4),
                color: active ? palette.accent : palette.text.withValues(alpha: 0.14),
              ),
          ],
        ),
      );
}

class _FoundryFramePainter extends CustomPainter {
  const _FoundryFramePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color.withValues(alpha: 0.72)
      ..strokeWidth = 1.2;
    const double inset = 3;
    const double length = 9;
    canvas.drawLine(const Offset(inset, inset), const Offset(inset + length, inset), paint);
    canvas.drawLine(const Offset(inset, inset), const Offset(inset, inset + length), paint);
    canvas.drawLine(Offset(size.width - inset - length, inset), Offset(size.width - inset, inset), paint);
    canvas.drawLine(Offset(size.width - inset, inset), Offset(size.width - inset, inset + length), paint);
  }

  @override
  bool shouldRepaint(covariant _FoundryFramePainter oldDelegate) => oldDelegate.color != color;
}

class _FoundryGrain extends CustomPainter {
  const _FoundryGrain(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color.withValues(alpha: 0.34)
      ..strokeWidth = 0.5;
    for (double y = 13; y < size.height; y += 13) {
      canvas.drawLine(Offset.zero.translate(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _FoundryGrain oldDelegate) => oldDelegate.color != color;
}
