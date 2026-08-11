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

/// "Relay" QuickMenu design — a compact communications console built from
/// Vector's indexed avionics language and Cyber's angular signal hardware.
///
/// The panel is organized around routed signal rails, a recessed window bus,
/// and compact readouts. It stays information-dense and technical without
/// turning every edge into a neon glow.
class MainMenuRelayWidget extends StatelessWidget {
  const MainMenuRelayWidget({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active theme changes.
    final _RelayPalette p = _RelayPalette.fromTheme();
    final bool hasBackdrop = user.activeBackdropPath.isNotEmpty;

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: 203,
        maxHeight: MediaQuery.of(context).size.height - 46,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Design.borderRadius),
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: RepaintBoundary(
                child: _RelayGround(p: p, hasBackdrop: hasBackdrop),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 5, 8, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (!user.quickActionsAtBottom) ...<Widget>[
                    DragToMoveArea(child: _RelaySection(code: '01', label: 'COMMAND LINK', p: p)),
                    _RelayModule(
                      p: p,
                      child: const Padding(
                        padding: EdgeInsets.fromLTRB(7, 4, 7, 4),
                        child: TopBar(),
                      ),
                    ),
                  ] else if (user.bottomBarOnTop) ...<Widget>[
                    _RelaySection(code: '01', label: 'PINNED LINK', p: p),
                    _RelayModule(
                      p: p,
                      inset: true,
                      child: const PinnedAndTrayList(),
                    ),
                  ] else
                    const SizedBox(height: 4),
                  // DragToMoveArea(
                  //   child: _RelaySection(code: '02', label: 'WINDOW BUS', p: p),
                  // ),
                  _RelayModule(
                    p: p,
                    inset: true,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        DragToMoveArea(child: _RelayReadout(p: p)),
                        const Padding(
                          padding: EdgeInsets.fromLTRB(4, 2, 4, 2),
                          child: RepaintBoundary(child: TaskBar()),
                        ),
                      ],
                    ),
                  ),
                  if (!user.bottomBarOnTop) ...<Widget>[
                    _RelaySection(code: '03', label: 'PINNED CACHE', p: p),
                    _RelayModule(
                      p: p,
                      inset: true,
                      child: const PinnedAndTrayList(),
                    ),
                  ],
                  if (user.taskManagerStats) const TaskbarStats(withTopDivider: false),
                  if (user.libreStats) const LibreStats(withTopDivider: false),
                  _RelaySection(code: '04', label: 'CONTROL ARRAY', p: p),
                  _RelayModule(
                    p: p,
                    child: const Padding(
                      padding: EdgeInsets.fromLTRB(6, 2, 6, 2),
                      child: BottomBar(),
                    ),
                  ),
                ],
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _RelayOverlayPainter(
                      accent: p.accent,
                      quiet: p.quiet,
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

class _RelayPalette {
  const _RelayPalette({
    required this.background,
    required this.text,
    required this.accent,
    required this.quiet,
    required this.rule,
    required this.module,
    required this.scope,
    required this.scopeEdge,
    required this.isDark,
  });

  factory _RelayPalette.fromTheme() {
    final Color background = Design.background;
    final Color text = Design.text;
    final Color accent = Design.accent;
    final bool isDark = background.computeLuminance() < 0.5;
    return _RelayPalette(
      background: background,
      text: text,
      accent: accent,
      quiet: text.withValues(alpha: isDark ? 0.48 : 0.56),
      rule: text.withValues(alpha: isDark ? 0.16 : 0.19),
      module: Color.alphaBlend(
        text.withValues(alpha: isDark ? 0.035 : 0.045),
        background,
      ),
      scope: Color.alphaBlend(
        accent.withValues(alpha: isDark ? 0.055 : 0.045),
        background,
      ),
      scopeEdge: accent.withValues(alpha: isDark ? 0.28 : 0.32),
      isDark: isDark,
    );
  }

  final Color background;
  final Color text;
  final Color accent;
  final Color quiet;
  final Color rule;
  final Color module;
  final Color scope;
  final Color scopeEdge;
  final bool isDark;
}

class _RelayGround extends StatelessWidget {
  const _RelayGround({required this.p, required this.hasBackdrop});

  final _RelayPalette p;
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
          color: p.background.withValues(alpha: hasBackdrop ? 0.86 : 0.97),
          border: Border.all(color: p.rule, width: 0.7),
        ),
        child: Stack(
          children: <Widget>[
            if (Design.hasBackdrop) const StableBackdrop(),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _RelayTracePainter(
                    rail: p.accent.withValues(alpha: p.isDark ? 0.075 : 0.055),
                    quiet: p.text.withValues(alpha: p.isDark ? 0.04 : 0.035),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 24,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        p.accent.withValues(alpha: p.isDark ? 0.08 : 0.055),
                        Colors.transparent,
                      ],
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

class _RelaySection extends StatelessWidget {
  const _RelaySection({required this.code, required this.label, required this.p});

  final String code;
  final String label;
  final _RelayPalette p;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(5, 5, 4, 2),
      child: Row(
        children: <Widget>[
          Container(width: 4, height: 4, color: p.accent),
          // const SizedBox(width: 5),
          // Text(
          //   code,
          //   style: TextStyle(
          //     color: p.accent,
          //     fontFamily: Design.uiFontFamily,
          //     fontSize: Design.baseFontSize - 1,
          //     fontWeight: FontWeight.w700,
          //     letterSpacing: 1.1,
          //     height: 1,
          //   ),
          // ),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: p.quiet,
              fontFamily: Design.uiFontFamily,
              fontSize: Design.baseFontSize - 1.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.8,
              height: 1,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Container(height: 0.6, color: p.rule)),
          const SizedBox(width: 7),
          Text(
            'LINK',
            style: TextStyle(
              color: p.accent.withValues(alpha: 0.72),
              fontFamily: Design.entryFontFamily,
              fontSize: Design.baseFontSize - 2,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _RelayModule extends StatelessWidget {
  const _RelayModule({required this.p, required this.child, this.inset = false});

  final _RelayPalette p;
  final Widget child;
  final bool inset;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: ClipPath(
        clipper: _RelayModuleClipper(),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: inset ? p.background.withValues(alpha: p.isDark ? 0.38 : 0.48) : p.module,
            border: Border(
              left: BorderSide(color: p.accent, width: 2),
              top: BorderSide(color: p.rule, width: 0.7),
              right: BorderSide(color: p.rule, width: 0.7),
              bottom: BorderSide(color: p.rule, width: 0.7),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _RelayReadout extends StatelessWidget {
  const _RelayReadout({required this.p});

  final _RelayPalette p;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: p.scope,
        border: Border(bottom: BorderSide(color: p.scopeEdge, width: 0.7)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.swap_horiz_rounded, size: 12, color: p.accent),
          const SizedBox(width: 5),
          Text(
            'WINDOW BUS',
            style: TextStyle(
              color: p.quiet,
              fontFamily: Design.uiFontFamily,
              fontSize: Design.baseFontSize - 1.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.15,
              height: 1,
            ),
          ),
          const Spacer(),
          Text(
            'SYNC',
            style: TextStyle(
              color: p.quiet,
              fontFamily: Design.entryFontFamily,
              fontSize: Design.baseFontSize - 2,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
              height: 1,
            ),
          ),
          const SizedBox(width: 5),
          Container(
            width: 18,
            height: 3,
            decoration: BoxDecoration(
              color: p.accent.withValues(alpha: 0.24),
              border: Border(left: BorderSide(color: p.accent, width: 5)),
            ),
          ),
        ],
      ),
    );
  }
}

class _RelayModuleClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    const double cut = 6;
    const double bottomCut = 5;
    final Path path = Path()
      ..moveTo(cut, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height - bottomCut)
      ..lineTo(size.width - bottomCut, size.height)
      ..lineTo(0, size.height)
      ..lineTo(0, cut)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(covariant _RelayModuleClipper oldClipper) => false;
}

class _RelayTracePainter extends CustomPainter {
  const _RelayTracePainter({required this.rail, required this.quiet});

  final Color rail;
  final Color quiet;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint railPaint = Paint()
      ..color = rail
      ..strokeWidth = 0.7
      ..style = PaintingStyle.stroke;
    final Paint quietPaint = Paint()
      ..color = quiet
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    for (double y = 16; y < size.height; y += 22) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), quietPaint);
    }

    final double right = size.width - 10;
    final Path upperTrace = Path()
      ..moveTo(0, 32)
      ..lineTo(size.width * 0.18, 32)
      ..lineTo(size.width * 0.21, 28)
      ..lineTo(size.width * 0.46, 28)
      ..lineTo(size.width * 0.49, 32)
      ..lineTo(size.width * 0.72, 32);
    canvas.drawPath(upperTrace, railPaint);

    final Path lowerTrace = Path()
      ..moveTo(size.width * 0.52, size.height - 18)
      ..lineTo(size.width * 0.68, size.height - 18)
      ..lineTo(size.width * 0.71, size.height - 22)
      ..lineTo(right, size.height - 22);
    canvas.drawPath(lowerTrace, railPaint);

    for (final Offset node in <Offset>[
      Offset(size.width * 0.21, 28),
      Offset(size.width * 0.49, 32),
      Offset(size.width * 0.71, size.height - 22),
    ]) {
      canvas.drawCircle(node, 1.5, Paint()..color = rail);
    }
  }

  @override
  bool shouldRepaint(covariant _RelayTracePainter oldDelegate) =>
      oldDelegate.rail != rail || oldDelegate.quiet != quiet;
}

class _RelayOverlayPainter extends CustomPainter {
  const _RelayOverlayPainter({required this.accent, required this.quiet});

  final Color accent;
  final Color quiet;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint core = Paint()
      ..color = accent
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    final Paint tick = Paint()
      ..color = quiet
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    final Paint node = Paint()..color = accent;

    const double inset = 3;
    const double length = 9;
    final double right = size.width - inset;
    final double bottom = size.height - inset;
    final Path brackets = Path()
      ..moveTo(inset, inset + length)
      ..lineTo(inset, inset)
      ..lineTo(inset + length, inset)
      ..moveTo(right - length, inset)
      ..lineTo(right, inset)
      ..lineTo(right, inset + length)
      ..moveTo(right, bottom - length)
      ..lineTo(right, bottom)
      ..lineTo(right - length, bottom)
      ..moveTo(inset + length, bottom)
      ..lineTo(inset, bottom)
      ..lineTo(inset, bottom - length);
    canvas.drawPath(brackets, core);

    final double cx = size.width / 2;
    final double cy = size.height / 2;
    canvas.drawLine(Offset(cx, inset - 1), Offset(cx, inset + 4), tick);
    canvas.drawLine(Offset(cx, bottom - 4), Offset(cx, bottom + 1), tick);
    canvas.drawLine(Offset(inset - 1, cy), Offset(inset + 4, cy), tick);
    canvas.drawLine(Offset(right - 4, cy), Offset(right + 1, cy), tick);

    const double busX = 7;
    final Paint bus = Paint()
      ..color = accent.withValues(alpha: 0.55)
      ..strokeWidth = 0.8;
    canvas.drawLine(const Offset(busX, 20), Offset(busX, size.height - 20), bus);
    for (final double y in <double>[26, size.height * 0.5, size.height - 26]) {
      canvas.drawCircle(Offset(busX, y), 1.4, node);
    }

    final Paint status = Paint()
      ..color = accent.withValues(alpha: 0.62)
      ..strokeWidth = 1;
    final double statusY = size.height - 8;
    for (int i = 0; i < 4; i++) {
      final double x = size.width - 42 + (i * 6);
      canvas.drawLine(Offset(x, statusY), Offset(x + 3, statusY), status);
    }
  }

  @override
  bool shouldRepaint(covariant _RelayOverlayPainter oldDelegate) =>
      oldDelegate.accent != accent || oldDelegate.quiet != quiet;
}
