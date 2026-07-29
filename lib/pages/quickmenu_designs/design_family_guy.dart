// ignore_for_file: unused_element

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

/// "Family Guy" QuickMenu design — thick cartoon outlines, bright flat colors,
/// and character silhouettes from the show. Peter, Stewie, and Brian peek
/// from the corners while the UI uses bold black strokes and that signature
/// cutaway-gag box style.
class MainMenuFamilyGuyWidget extends StatelessWidget {
  const MainMenuFamilyGuyWidget({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final _FamilyGuyPalette p = _FamilyGuyPalette.fromTheme();
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
            // ---- Cartoon background ----
            Positioned.fill(
              child: RepaintBoundary(
                child: _FamilyGuyGround(p: p, hasBackdrop: hasBackdrop),
              ),
            ),

            // ---- Character stickers (behind content) ----
            Positioned(
              top: 2,
              left: 4,
              width: 42,
              height: 50,
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _PeterSilhouettePainter(color: p.outline),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 6,
              width: 36,
              height: 44,
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _BrianSilhouettePainter(color: p.outline),
                ),
              ),
            ),
            Positioned(
              bottom: 6,
              left: 8,
              width: 30,
              height: 34,
              child: IgnorePointer(
                child: CustomPaint(
                  painter: StewieSilhouettePainter(color: p.outline),
                ),
              ),
            ),

            // ---- Content column ----
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // Title strip with "cutaway" style
                  // _FamilyGuyTitleBar(p: p),

                  if (!user.quickActionsAtBottom) ...<Widget>[
                    const SizedBox(height: 4),
                    _FamilyGuyCutawayBox(
                      p: p,
                      child: const Padding(
                        padding: EdgeInsets.fromLTRB(8, 4, 8, 4),
                        child: TopBar(),
                      ),
                    ),
                  ] else if (user.bottomBarOnTop) ...<Widget>[
                    _FamilyGuySectionMarker(label: 'PINNED', p: p),
                    const PinnedAndTrayList(),
                  ] else
                    const SizedBox(height: 4),

                  _FamilyGuySectionMarker(label: 'WINDOWS', p: p),
                  _FamilyGuyCutawayBox(
                    p: p,
                    inset: true,
                    child: const RepaintBoundary(
                      child: TaskBar(),
                    ),
                  ),

                  if (!user.bottomBarOnTop) ...<Widget>[
                    // _FamilyGuySectionMarker(label: 'PINNED', p: p),
                    const PinnedAndTrayList(),
                  ],

                  if (user.taskManagerStats) const TaskbarStats(withTopDivider: false),
                  if (user.libreStats) const LibreStats(withTopDivider: false),

                  // _FamilyGuySectionMarker(label: 'CONTROL', p: p),
                  _FamilyGuyCutawayBox(
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
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Palette
// ---------------------------------------------------------------------------

class _FamilyGuyPalette {
  const _FamilyGuyPalette({
    required this.bg,
    required this.text,
    required this.accent,
    required this.outline,
    required this.fill,
    required this.shadow,
    required this.isDark,
  });

  factory _FamilyGuyPalette.fromTheme() {
    final bool isDark = Design.background.computeLuminance() < 0.5;
    return _FamilyGuyPalette(
      bg: Design.background,
      text: Design.text,
      accent: Design.accent,
      outline: isDark ? const Color(0xff2A2A2A) : const Color(0xff1A1A1A),
      fill: isDark ? const Color(0xff2E2E3A) : const Color(0xffE8E0D4),
      shadow: isDark ? Colors.black.withValues(alpha: 0.45) : Colors.black.withValues(alpha: 0.18),
      isDark: isDark,
    );
  }

  final Color bg;
  final Color text;
  final Color accent;
  final Color outline;
  final Color fill;
  final Color shadow;
  final bool isDark;
}

// ---------------------------------------------------------------------------
// Background ground
// ---------------------------------------------------------------------------

class _FamilyGuyGround extends StatelessWidget {
  const _FamilyGuyGround({required this.p, required this.hasBackdrop});

  final _FamilyGuyPalette p;
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
          color: p.bg.withValues(alpha: hasBackdrop ? 0.88 : 0.98),
          border: Border.all(color: p.outline, width: 2.5),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: p.shadow,
              blurRadius: 0,
              spreadRadius: 0,
              offset: const Offset(4, 4),
            ),
          ],
        ),
        child: Stack(
          children: <Widget>[
            if (Design.hasBackdrop) const StableBackdrop(),
            // Subtle wallpaper crosshatch like the living room
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: WallpaperPainter(
                    color: p.outline.withValues(alpha: p.isDark ? 0.04 : 0.06),
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
// Decorative widgets
// ---------------------------------------------------------------------------

class _FamilyGuyTitleBar extends StatelessWidget {
  const _FamilyGuyTitleBar({required this.p});

  final _FamilyGuyPalette p;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
      child: Row(
        children: <Widget>[
          // "TV rating" style bug
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: p.accent,
              border: Border.all(color: p.outline, width: 2),
            ),
            child: Text(
              'TV-14',
              style: TextStyle(
                color: p.outline,
                fontFamily: Design.uiFontFamily,
                fontSize: Design.baseFontSize - 2,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'QUAHOG OS',
            style: TextStyle(
              color: p.text,
              fontFamily: Design.uiFontFamily,
              fontSize: Design.baseFontSize,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              height: 1,
            ),
          ),
          const Spacer(),
          // Three "channel dots" like a TV remote
          for (int i = 0; i < 3; i++)
            Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.only(left: 3),
              decoration: BoxDecoration(
                color: i == 0 ? const Color(0xffDC143C) : p.fill,
                shape: BoxShape.circle,
                border: Border.all(color: p.outline, width: 1.5),
              ),
            ),
        ],
      ),
    );
  }
}

class _FamilyGuySectionMarker extends StatelessWidget {
  const _FamilyGuySectionMarker({required this.label, required this.p});

  final String label;
  final _FamilyGuyPalette p;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 4, 3),
      child: Row(
        children: <Widget>[
          // "Cutaway" style arrow
          CustomPaint(
            size: const Size(10, 10),
            painter: _CartoonArrowPainter(color: p.accent, outline: p.outline),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: p.text,
              fontFamily: Design.uiFontFamily,
              fontSize: Design.baseFontSize - 1,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              height: 1,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 2.5,
              color: p.outline,
            ),
          ),
        ],
      ),
    );
  }
}

/// The signature "cutaway gag" box — thick black outline, flat fill,
/// and a hard drop shadow offset diagonally.
class _FamilyGuyCutawayBox extends StatelessWidget {
  const _FamilyGuyCutawayBox({
    required this.p,
    required this.child,
    this.inset = false,
  });

  final _FamilyGuyPalette p;
  final Widget child;
  final bool inset;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(4, 2, 4, 2),
      decoration: BoxDecoration(
        color: inset ? p.bg.withValues(alpha: p.isDark ? 0.50 : 0.60) : p.fill,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: p.outline, width: 2.5),
        boxShadow: inset
            ? null
            : <BoxShadow>[
                BoxShadow(
                  color: p.shadow,
                  blurRadius: 0,
                  spreadRadius: 0,
                  offset: const Offset(3, 3),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(0),
        child: child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Painters
// ---------------------------------------------------------------------------

/// Living-room wallpaper crosshatch.
class WallpaperPainter extends CustomPainter {
  const WallpaperPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    const double spacing = 16;
    for (double x = 0; x < size.width + size.height; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x - size.height, size.height), paint);
      canvas.drawLine(Offset(x - size.height, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant WallpaperPainter oldDelegate) => oldDelegate.color != color;
}

/// Thick cartoon arrow for section markers.
class _CartoonArrowPainter extends CustomPainter {
  const _CartoonArrowPainter({required this.color, required this.outline});

  final Color color;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final Path path = Path()
      ..moveTo(0, size.height * 0.5)
      ..lineTo(size.width * 0.7, 0)
      ..lineTo(size.width * 0.7, size.height * 0.35)
      ..lineTo(size.width, size.height * 0.35)
      ..lineTo(size.width, size.height * 0.65)
      ..lineTo(size.width * 0.7, size.height * 0.65)
      ..lineTo(size.width * 0.7, size.height)
      ..close();

    canvas.drawPath(
      path,
      Paint()..color = outline,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _CartoonArrowPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.outline != outline;
}

/// Peter Griffin silhouette — round body, cleft chin bump, pants line.
class _PeterSilhouettePainter extends CustomPainter {
  const _PeterSilhouettePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = color.withValues(alpha: 0.12);

    final Path body = Path()
      // Head
      ..addOval(Rect.fromLTWH(size.width * 0.25, 0, size.width * 0.50, size.height * 0.38))
      // Cleft chin
      ..addOval(Rect.fromLTWH(size.width * 0.42, size.height * 0.30, size.width * 0.16, size.height * 0.14))
      // Torso (round)
      ..addOval(Rect.fromLTWH(size.width * 0.10, size.height * 0.32, size.width * 0.80, size.height * 0.48))
      // Left arm
      ..addOval(Rect.fromLTWH(-size.width * 0.05, size.height * 0.38, size.width * 0.30, size.height * 0.35))
      // Right arm
      ..addOval(Rect.fromLTWH(size.width * 0.75, size.height * 0.38, size.width * 0.30, size.height * 0.35));

    canvas.drawPath(body, paint);

    // Pants line
    canvas.drawLine(
      Offset(size.width * 0.12, size.height * 0.68),
      Offset(size.width * 0.88, size.height * 0.68),
      Paint()
        ..color = color.withValues(alpha: 0.08)
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _PeterSilhouettePainter oldDelegate) => oldDelegate.color != color;
}

/// Brian Griffin silhouette — dog snout, ears, collar, tail.
class _BrianSilhouettePainter extends CustomPainter {
  const _BrianSilhouettePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = color.withValues(alpha: 0.12);

    final Path body = Path()
      // Head / snout
      ..moveTo(size.width * 0.20, size.height * 0.45)
      ..lineTo(size.width * 0.05, size.height * 0.50)
      ..lineTo(size.width * 0.20, size.height * 0.58)
      // Neck
      ..lineTo(size.width * 0.35, size.height * 0.62)
      // Body
      ..lineTo(size.width * 0.85, size.height * 0.62)
      // Tail
      ..quadraticBezierTo(
        size.width * 1.05,
        size.height * 0.45,
        size.width * 0.90,
        size.height * 0.35,
      )
      // Back
      ..lineTo(size.width * 0.55, size.height * 0.20)
      // Ears
      ..lineTo(size.width * 0.45, size.height * 0.05)
      ..lineTo(size.width * 0.40, size.height * 0.22)
      // Forehead
      ..lineTo(size.width * 0.28, size.height * 0.28)
      ..close();

    canvas.drawPath(body, paint);

    // Collar
    canvas.drawOval(
      Rect.fromLTWH(size.width * 0.32, size.height * 0.58, size.width * 0.12, size.height * 0.08),
      Paint()..color = color.withValues(alpha: 0.08),
    );
  }

  @override
  bool shouldRepaint(covariant _BrianSilhouettePainter oldDelegate) => oldDelegate.color != color;
}

/// Stewie Griffin silhouette — football head, overalls, shoes.
class StewieSilhouettePainter extends CustomPainter {
  const StewieSilhouettePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = color.withValues(alpha: 0.12);

    final Path body = Path()
      // Football head
      ..moveTo(size.width * 0.50, size.height * 0.05)
      ..quadraticBezierTo(
        size.width * 0.95,
        size.height * 0.25,
        size.width * 0.85,
        size.height * 0.55,
      )
      // Right side
      ..lineTo(size.width * 0.75, size.height * 0.62)
      // Body / overalls
      ..lineTo(size.width * 0.80, size.height * 0.85)
      // Right foot
      ..lineTo(size.width * 0.90, size.height * 0.95)
      ..lineTo(size.width * 0.75, size.height * 0.95)
      // Bottom
      ..lineTo(size.width * 0.25, size.height * 0.95)
      // Left foot
      ..lineTo(size.width * 0.10, size.height * 0.95)
      ..lineTo(size.width * 0.20, size.height * 0.85)
      // Left side
      ..lineTo(size.width * 0.25, size.height * 0.62)
      ..quadraticBezierTo(
        size.width * 0.05,
        size.height * 0.55,
        size.width * 0.15,
        size.height * 0.25,
      )
      ..close();

    canvas.drawPath(body, paint);
  }

  @override
  bool shouldRepaint(covariant StewieSilhouettePainter oldDelegate) => oldDelegate.color != color;
}
