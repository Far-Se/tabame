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

/// "Anime" QuickMenu design — a Cyberpunk/Mecha anime HUD aesthetic.
///
/// The menu renders as a high-tech tactical overlay: sharp asymmetrical
/// clipped corners, glowing neon borders, and digital grid underlays.
/// Sections are labeled like system diagnostics `「 WINDOWS 」`, and the
/// window switcher sits inside a recessed neon well.
class MainMenuCyberWidget extends StatelessWidget {
  const MainMenuCyberWidget({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // register as theme-dependent so Design.* values update live
    final _AnimePalette p = _AnimePalette.fromTheme();
    final bool hasBackdrop = user.activeBackdropPath.isNotEmpty;

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: 203,
        maxHeight: MediaQuery.of(context).size.height - 40,
      ),
      child: ClipPath(
        clipper: _AnimeClipper(),
        child: Stack(
          children: <Widget>[
            // ---- Tactical Glass Body ----
            Positioned.fill(
              child: RepaintBoundary(
                child: _AnimeGround(p: p, hasBackdrop: hasBackdrop),
              ),
            ),

            // ---- HUD Content ----
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (!user.quickActionsAtBottom) ...<Widget>[
                    // _AnimeHeader(label: 'INITIATE', p: p),
                    const SizedBox(height: 4),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(4, 0, 4, 0),
                      child: TopBar(),
                    ),
                  ] else if (user.bottomBarOnTop) ...<Widget>[
                    _AnimeHeader(label: 'DOCK', p: p),
                    const PinnedAndTrayList(),
                  ] else
                    const SizedBox(height: 4),
                  _AnimeHeader(label: 'WINDOWS', p: p),
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
                    decoration: BoxDecoration(
                      color: p.screen,
                      border: Border(
                        left: BorderSide(color: p.neon, width: 2),
                        bottom: BorderSide(color: p.neon.withValues(alpha: 0.3), width: 1),
                      ),
                    ),
                    child: const RepaintBoundary(
                      child: TaskBar(),
                    ),
                  ),
                  if (!user.bottomBarOnTop) ...<Widget>[
                    _AnimeHeader(label: 'SYSTEM TRAY', p: p),
                    const PinnedAndTrayList(),
                  ],
                  if (user.taskManagerStats) const TaskbarStats(withTopDivider: false),
                  if (user.libreStats) const LibreStats(withTopDivider: false),
                  _AnimeHeader(label: 'CONTROL', p: p),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 2, 4, 0),
                    child: BottomBar(),
                  ),
                ],
              ),
            ),

            // ---- HUD Overlays (Glitches / Reticles) ----
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(painter: _AnimeFramePainter(neon: p.neon, isDark: p.isDark)),
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

class _AnimePalette {
  const _AnimePalette({
    required this.glass,
    required this.ink,
    required this.neon,
    required this.faint,
    required this.hairline,
    required this.edge,
    required this.screen,
    required this.isDark,
  });

  factory _AnimePalette.fromTheme() {
    final bool isDark = Design.background.computeLuminance() < 0.5;
    final Color ink = Design.text;
    final Color neon = Design.accent;
    return _AnimePalette(
      glass: Design.background,
      ink: ink,
      neon: neon,
      faint: ink.withValues(alpha: isDark ? 0.5 : 0.6),
      hairline: neon.withValues(alpha: isDark ? 0.3 : 0.4),
      edge: ink.withValues(alpha: isDark ? 0.1 : 0.16),
      screen: neon.withValues(alpha: isDark ? 0.05 : 0.04),
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
  final bool isDark;
}

// ---------------------------------------------------------------------------
// Ground & Backdrop
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
          color: p.glass.withValues(alpha: hasBackdrop ? 0.88 : 0.97),
          border: Border.all(color: p.edge, width: 0.5),
        ),
        child: Stack(
          children: <Widget>[
            if (Design.hasBackdrop) const StableBackdrop(),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _AnimeGridPainter(
                    p.neon.withValues(alpha: p.isDark ? 0.06 : 0.04),
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
// Headers
// ---------------------------------------------------------------------------

/// Mecha-style section header: `「 LABEL 」` with a glowing line extending.
class _AnimeHeader extends StatelessWidget {
  const _AnimeHeader({required this.label, required this.p});

  final String label;
  final _AnimePalette p;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
      child: Row(
        children: <Widget>[
          Text(
            '「',
            style: TextStyle(
              color: p.neon,
              fontFamily: Design.uiFontFamily,
              fontSize: Design.baseFontSize - 1,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: p.neon,
              fontFamily: Design.uiFontFamily,
              fontSize: Design.baseFontSize - 2,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              height: 1,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '」',
            style: TextStyle(
              color: p.neon,
              fontFamily: Design.uiFontFamily,
              fontSize: Design.baseFontSize - 1,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 0.75,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[
                    p.neon.withValues(alpha: 0.7),
                    p.neon.withValues(alpha: 0.0),
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

// ---------------------------------------------------------------------------
// Clippers & Painters
// ---------------------------------------------------------------------------

/// Asymmetrical polygon clipper for mecha/plated armor edges.
class _AnimeClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final Path path = Path();
    // Start top-left
    path.moveTo(0, 8);
    path.lineTo(8, 0);
    path.lineTo(size.width - 15, 0);
    path.lineTo(size.width, 15);
    path.lineTo(size.width, size.height - 8);
    path.lineTo(size.width - 8, size.height);
    path.lineTo(15, size.height);
    path.lineTo(0, size.height - 15);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// Fine digital grid pattern running under the whole panel.
class _AnimeGridPainter extends CustomPainter {
  const _AnimeGridPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 0.5;

    for (double x = 0; x < size.width; x += 12) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += 12) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AnimeGridPainter oldDelegate) => oldDelegate.color != color;
}

/// Glitchy reticle marks and status nodes overlaid on the edges.
class _AnimeFramePainter extends CustomPainter {
  const _AnimeFramePainter({required this.neon, required this.isDark});

  final Color neon;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint glowPaint = Paint()
      ..color = neon.withValues(alpha: isDark ? 0.8 : 0.6)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final Paint solidPaint = Paint()
      ..color = neon
      ..strokeWidth = 2
      ..style = PaintingStyle.fill;

    // Top right reticle mark
    canvas.drawLine(
      Offset(size.width - 20, 5),
      Offset(size.width - 5, 5),
      glowPaint,
    );
    canvas.drawLine(
      Offset(size.width - 5, 5),
      Offset(size.width - 5, 20),
      glowPaint,
    );

    // Status nodes (dots)
    canvas.drawCircle(Offset(size.width - 5, 5), 2, solidPaint);
    canvas.drawCircle(Offset(5, size.height - 5), 2, solidPaint);

    // Bottom left reticle mark
    canvas.drawLine(
      Offset(20, size.height - 5),
      Offset(5, size.height - 5),
      glowPaint,
    );
    canvas.drawLine(
      Offset(5, size.height - 5),
      Offset(5, size.height - 20),
      glowPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _AnimeFramePainter oldDelegate) =>
      oldDelegate.neon != neon || oldDelegate.isDark != isDark;
}
