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

/// "Manifesto" is an editorial command surface, not a conventional utility
/// panel. Hard rules, registration marks, oversized folio numbers and an
/// asymmetric redaction rail turn the menu into a live printed broadsheet.
class MainMenuManifestoWidget extends StatelessWidget {
  const MainMenuManifestoWidget({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active theme changes.
    final _ManifestoPalette p = _ManifestoPalette.fromTheme();
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
              Positioned.fill(child: _ManifestoGround(p: p, hasBackdrop: hasBackdrop)),
              Padding(
                padding: const EdgeInsets.only(left: 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // _IssueHeader(p: p),
                    if (!user.quickActionsAtBottom)
                      _ActionDeck(p: p)
                    else if (user.bottomBarOnTop)
                      const PinnedAndTrayList(),
                    _WindowField(p: p),
                    if (!user.bottomBarOnTop) _PinnedField(p: p),
                    if (user.taskManagerStats) const TaskbarStats(withTopDivider: false),
                    if (user.libreStats) const LibreStats(withTopDivider: false),
                    _SignalFooter(p: p),
                  ],
                ),
              ),
              Positioned(left: 0, top: 0, bottom: 0, width: 22, child: _FolioRail(p: p)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManifestoPalette {
  const _ManifestoPalette({
    required this.paper,
    required this.ink,
    required this.signal,
    required this.faint,
    required this.isDark,
  });

  factory _ManifestoPalette.fromTheme() {
    final bool isDark = Design.background.computeLuminance() < 0.5;
    return _ManifestoPalette(
      paper: Design.background,
      ink: Design.text,
      signal: Design.accent,
      faint: Design.text.withValues(alpha: isDark ? 0.10 : 0.075),
      isDark: isDark,
    );
  }

  final Color paper;
  final Color ink;
  final Color signal;
  final Color faint;
  final bool isDark;
}

class _ManifestoGround extends StatelessWidget {
  const _ManifestoGround({required this.p, required this.hasBackdrop});

  final _ManifestoPalette p;
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
          color: p.paper.withValues(alpha: hasBackdrop ? 0.91 : 1),
          border: Border.all(color: p.ink, width: 2),
        ),
        child: Stack(
          children: <Widget>[
            if (Design.hasBackdrop) const StableBackdrop(),
            Positioned.fill(
              child: IgnorePointer(child: CustomPaint(painter: _PrintGridPainter(color: p.faint))),
            ),
          ],
        ),
      ),
    );
  }
}

// ignore: unused_element
class _IssueHeader extends StatelessWidget {
  const _IssueHeader({required this.p});

  final _ManifestoPalette p;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.ink, width: 2))),
      child: Row(
        children: <Widget>[
          Container(
            width: 56,
            alignment: Alignment.center,
            color: p.ink,
            child: Text(
              'Q/M',
              style: TextStyle(
                color: p.paper,
                fontFamily: Design.uiFontFamily,
                fontSize: Design.baseFontSize + 4,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.8,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'DIRECT ACTION INDEX',
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                color: p.ink,
                fontFamily: Design.uiFontFamily,
                fontSize: Design.baseFontSize - 0.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.8,
              ),
            ),
          ),
          Container(width: 9, height: 9, color: p.signal),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _ActionDeck extends StatelessWidget {
  const _ActionDeck({required this.p});

  final _ManifestoPalette p;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(3, 3, 8, 4),
      decoration: BoxDecoration(
        color: p.signal.withValues(alpha: p.isDark ? 0.18 : 0.10),
        border: Border(bottom: BorderSide(color: p.ink, width: 1)),
      ),
      child: const TopBar(),
    );
  }
}

class _WindowField extends StatelessWidget {
  const _WindowField({required this.p});

  final _ManifestoPalette p;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        const TaskBar(),
        Positioned(
          right: 0,
          top: 0,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              color: p.ink,
              child: Text(
                '01',
                style: TextStyle(
                  color: p.paper,
                  fontFamily: Design.uiFontFamily,
                  fontSize: Design.baseFontSize - 1,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PinnedField extends StatelessWidget {
  const _PinnedField({required this.p});

  final _ManifestoPalette p;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: p.ink, width: 2),
          bottom: BorderSide(color: p.ink.withValues(alpha: 0.35)),
        ),
      ),
      child: const PinnedAndTrayList(),
    );
  }
}

class _SignalFooter extends StatelessWidget {
  const _SignalFooter({required this.p});

  final _ManifestoPalette p;

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

class _FolioRail extends StatelessWidget {
  const _FolioRail({required this.p});

  final _ManifestoPalette p;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.signal,
        border: Border(right: BorderSide(color: p.ink, width: 2)),
      ),
      child: Column(
        children: <Widget>[
          const SizedBox(height: 8),
          RotatedBox(
            quarterTurns: 1,
            child: Text(
              'TABAME / CONTROL EDITION',
              maxLines: 1,
              style: TextStyle(
                color: p.isDark ? p.paper : p.ink,
                fontFamily: Design.uiFontFamily,
                fontSize: Design.baseFontSize - 2,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
          ),
          const Spacer(),
          Container(width: 8, height: 8, color: p.ink),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _PrintGridPainter extends CustomPainter {
  const _PrintGridPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 0.5;
    for (double y = 46; y < size.height; y += 18) {
      canvas.drawLine(Offset(22, y), Offset(size.width, y), paint);
    }
    for (double x = 78; x < size.width; x += 92) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    final Paint mark = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..strokeWidth = 1;
    canvas.drawLine(const Offset(5, 8), const Offset(17, 8), mark);
    canvas.drawLine(const Offset(11, 2), const Offset(11, 14), mark);
  }

  @override
  bool shouldRepaint(covariant _PrintGridPainter oldDelegate) => oldDelegate.color != color;
}
