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

/// "Player" QuickMenu design — an early-2000s skinned media player (BSPlayer /
/// Winamp era).
///
/// The menu renders as a Y2K "blue steel" player skin: brushed-metal body with
/// a cylindrical sheen, hard 3D bevels on every strip (light top-left edge,
/// dark bottom-right), an embossed brand label with speaker-grille vents, the
/// quick actions as a raised toolbar, and the window switcher + info bar
/// recessed into dark LCD wells with accent corner ticks and a glass glare.
/// `Design.gradientAlpha` scales the LCD tint/glare strength.
Color _lift(Color base, double amount) => Color.alphaBlend(Colors.white.withValues(alpha: amount), base);
Color _sink(Color base, double amount) => Color.alphaBlend(Colors.black.withValues(alpha: amount), base);

class _MetalTokens {
  _MetalTokens._({
    required this.isDark,
    required this.glow,
    required this.accent,
    required this.text,
    required this.bevelHi,
    required this.bevelLo,
    required this.metalHi,
    required this.metalMid,
    required this.metalLo,
    required this.lcd,
    required this.slot,
    required this.embossed,
  });

  factory _MetalTokens.fromTheme() {
    final Color bg = Design.background;
    final Color text = Design.text;
    final Color accent = Design.accent;
    final bool isDark = bg.computeLuminance() < 0.5;
    final double glow = (Design.gradientAlpha.clamp(0, 255)) / 255.0;
    return _MetalTokens._(
      isDark: isDark,
      glow: glow,
      accent: accent,
      text: text,
      bevelHi: Colors.white.withValues(alpha: isDark ? 0.16 : 0.75),
      bevelLo: Colors.black.withValues(alpha: isDark ? 0.55 : 0.30),
      metalHi: _lift(bg, isDark ? 0.14 : 0.35),
      metalMid: bg,
      metalLo: _sink(bg, isDark ? 0.16 : 0.10),
      lcd: Color.alphaBlend(
        accent.withValues(alpha: 0.06 + glow * 0.08),
        _sink(bg, isDark ? 0.30 : 0.14),
      ),
      slot: Colors.black.withValues(alpha: isDark ? 0.5 : 0.28),
      embossed: text.withValues(alpha: 0.55),
    );
  }

  final bool isDark;
  final double glow;
  final Color accent;
  final Color text;
  final Color bevelHi;
  final Color bevelLo;
  final Color metalHi;
  final Color metalMid;
  final Color metalLo;
  final Color lcd;
  final Color slot;
  final Color embossed;
}

/// The classic skin emboss: a 1px frame that runs light on the top-left and
/// dark on the bottom-right (or inverted for recessed wells), wrapped around
/// the child. Built as two nested boxes because Flutter forbids non-uniform
/// borders together with a corner radius.
class _Bevel extends StatelessWidget {
  const _Bevel({
    required this.t,
    required this.child,
    this.inset = false,
    this.color,
    this.gradient,
    this.margin,
  });

  static const double radius = 5;

  final _MetalTokens t;
  final Widget child;
  final bool inset;
  final Color? color;
  final Gradient? gradient;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: inset ? <Color>[t.bevelLo, t.bevelHi] : <Color>[t.bevelHi, t.bevelLo],
        ),
      ),
      padding: const EdgeInsets.all(1),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular((radius - 1).clamp(0.0, 100.0)),
          color: color,
          gradient: gradient,
        ),
        child: child,
      ),
    );
  }
}

class MainMenuPlayerWidget extends StatelessWidget {
  const MainMenuPlayerWidget({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // register as theme-dependent so Design.* values update live
    final _MetalTokens t = _MetalTokens.fromTheme();
    final bool hasBackdrop = user.activeBackdropPath.isNotEmpty;
    final double radius = Design.borderRadius;
    final double bodyAlpha = hasBackdrop ? 0.84 : 1.0;

    final Gradient toolbarMetal = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[t.metalHi, t.metalLo],
    );

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: 203,
        maxHeight: MediaQuery.of(context).size.height - 30,
      ),
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(
            children: <Widget>[
              // ---- Brushed-metal body ----
              Positioned.fill(
                child: RepaintBoundary(
                  child: ShaderMask(
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
                    child: Container(
                      decoration: BoxDecoration(
                        // Cylindrical metal sheen: bright crown, darker base,
                        // small rim light at the very bottom.
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            t.metalHi.withValues(alpha: bodyAlpha),
                            t.metalMid.withValues(alpha: bodyAlpha),
                            t.metalLo.withValues(alpha: bodyAlpha),
                            t.metalMid.withValues(alpha: bodyAlpha),
                          ],
                          stops: const <double>[0.0, 0.45, 0.9, 1.0],
                        ),
                        borderRadius: BorderRadius.circular(radius),
                        border: Border.all(
                          color: t.isDark ? Colors.white.withValues(alpha: 0.10) : Colors.white.withValues(alpha: 0.55),
                        ),
                      ),
                      child: Stack(
                        children: <Widget>[
                          if (Design.hasBackdrop) const StableBackdrop(),
                          Positioned.fill(
                            child: IgnorePointer(
                              child: RepaintBoundary(
                                child: CustomPaint(painter: _BrushedPainter(isDark: t.isDark)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ---- Skin faceplate ----
              RepaintBoundary(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _BrandStrip(t: t),
                    if (!user.quickActionsAtBottom)
                      _Bevel(
                        t: t,
                        margin: const EdgeInsets.fromLTRB(5, 2, 5, 2),
                        gradient: toolbarMetal,
                        child: const Padding(
                          padding: EdgeInsets.fromLTRB(3, 2, 8, 2),
                          child: TopBar(),
                        ),
                      )
                    else if (user.bottomBarOnTop)
                      const PinnedAndTrayList(),

                    // Main LCD well — the window switcher behind glass.
                    _Bevel(
                      t: t,
                      inset: true,
                      margin: const EdgeInsets.fromLTRB(7, 4, 7, 3),
                      color: t.lcd.withValues(alpha: hasBackdrop ? 0.88 : 1.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Stack(
                          children: <Widget>[
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 3),
                              child: TaskBar(),
                            ),
                            Positioned.fill(
                              child: IgnorePointer(
                                child: RepaintBoundary(
                                  child: CustomPaint(
                                    painter: _LcdGlassPainter(accent: t.accent, glow: t.glow, isDark: t.isDark),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    if (!user.bottomBarOnTop) const PinnedAndTrayList(),
                    if (user.taskManagerStats) const TaskbarStats(withTopDivider: false),
                    if (user.libreStats) const LibreStats(withTopDivider: false),

                    // Timecode-style readout strip for the info bar.
                    _Bevel(
                      t: t,
                      inset: true,
                      margin: const EdgeInsets.fromLTRB(7, 2, 7, 6),
                      color: t.lcd.withValues(alpha: hasBackdrop ? 0.88 : 1.0),
                      child: const Padding(
                        padding: EdgeInsets.fromLTRB(6, 1, 6, 1),
                        child: BottomBar(),
                      ),
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

// ---------------------------------------------------------------------------
// Brand strip — embossed label + speaker-grille vents
// ---------------------------------------------------------------------------

class _BrandStrip extends StatelessWidget {
  const _BrandStrip({required this.t});

  final _MetalTokens t;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(9, 5, 9, 2),
      child: Row(
        children: <Widget>[
          // Text(
          //   "TABAME",
          //   style: TextStyle(
          //     fontSize: Design.baseFontSize - 1,
          //     fontFamily: Design.uiFontFamily,
          //     fontWeight: FontWeight.w700,
          //     letterSpacing: 1.8,
          //     color: t.embossed,
          //     // Light shadow just below the glyphs = stamped-into-metal look.
          //     shadows: <Shadow>[Shadow(color: t.bevelHi, offset: const Offset(0, 1))],
          //   ),
          // ),
          const Spacer(),
          for (int i = 0; i < 5; i++)
            Container(
              width: 11,
              height: 3,
              margin: const EdgeInsets.only(left: 3),
              decoration: BoxDecoration(
                color: t.slot,
                borderRadius: BorderRadius.circular(2),
                boxShadow: <BoxShadow>[BoxShadow(color: t.bevelHi, offset: const Offset(0, 1))],
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

/// Fine horizontal brushed-metal graining over the body.
class _BrushedPainter extends CustomPainter {
  const _BrushedPainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint light = Paint()..color = Colors.white.withValues(alpha: isDark ? 0.015 : 0.10);
    final Paint dark = Paint()..color = Colors.black.withValues(alpha: isDark ? 0.03 : 0.035);
    for (double y = 0; y < size.height; y += 4) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), dark);
      canvas.drawRect(Rect.fromLTWH(0, y + 1, size.width, 1), light);
    }
  }

  @override
  bool shouldRepaint(covariant _BrushedPainter oldDelegate) => oldDelegate.isDark != isDark;
}

/// LCD glass overlay: accent corner ticks, a top recess shadow and a
/// diagonal glare sweep.
class _LcdGlassPainter extends CustomPainter {
  const _LcdGlassPainter({required this.accent, required this.glow, required this.isDark});

  final Color accent;
  final double glow;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;

    // OSD-style corner ticks.
    final Paint tick = Paint()..color = accent.withValues(alpha: (0.30 + glow * 0.35).clamp(0.0, 1.0));
    const double inset = 3;
    const double len = 6;
    const double w = 1.2;
    // Top-left / top-right / bottom-left / bottom-right.
    canvas.drawRect(const Rect.fromLTWH(inset, inset, len, w), tick);
    canvas.drawRect(const Rect.fromLTWH(inset, inset, w, len), tick);
    canvas.drawRect(Rect.fromLTWH(size.width - inset - len, inset, len, w), tick);
    canvas.drawRect(Rect.fromLTWH(size.width - inset - w, inset, w, len), tick);
    canvas.drawRect(Rect.fromLTWH(inset, size.height - inset - w, len, w), tick);
    canvas.drawRect(Rect.fromLTWH(inset, size.height - inset - len, w, len), tick);
    canvas.drawRect(Rect.fromLTWH(size.width - inset - len, size.height - inset - w, len, w), tick);
    canvas.drawRect(Rect.fromLTWH(size.width - inset - w, size.height - inset - len, w, len), tick);

    // Recess shadow along the top edge of the well.
    final Paint topShadow = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          Colors.black.withValues(alpha: isDark ? 0.28 : 0.16),
          Colors.transparent,
        ],
        stops: const <double>[0.0, 0.16],
      ).createShader(rect);
    canvas.drawRect(rect, topShadow);

    // Diagonal glass glare.
    final Paint glare = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.center,
        colors: <Color>[
          Colors.white.withValues(alpha: (isDark ? 0.03 : 0.07) + glow * 0.02),
          Colors.transparent,
        ],
      ).createShader(rect);
    canvas.drawRect(rect, glare);
  }

  @override
  bool shouldRepaint(covariant _LcdGlassPainter oldDelegate) =>
      oldDelegate.accent != accent || oldDelegate.glow != glow || oldDelegate.isDark != isDark;
}
