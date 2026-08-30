import 'dart:math' show max;

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

/// "Winamp" QuickMenu design — a faithful homage to the classic late-90s
/// Nullsoft media player. Brushed-metal body, hard 3D bevels, recessed
/// LCD wells with corner ticks and glass glare, LED dot-matrix section
/// markers, and a live equalizer bar strip. Everything is sharp, metallic,
/// and deliberately low-fi.
class MainMenuWinampWidget extends StatelessWidget {
  const MainMenuWinampWidget({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when theme changes.
    final _WinampTokens t = _WinampTokens.fromTheme();
    final bool hasBackdrop = user.activeBackdropPath.isNotEmpty;

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: 203,
        maxHeight: MediaQuery.of(context).size.height - 30,
      ),
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Design.borderRadius),
          child: Stack(
            children: <Widget>[
              // ---- Brushed-metal chassis ----
              Positioned.fill(
                child: RepaintBoundary(
                  child: _WinampChassis(t: t, hasBackdrop: hasBackdrop),
                ),
              ),

              // ---- Faceplate ----
              RepaintBoundary(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // Title / LED strip
                    DragToMoveArea(child: _WinampTitleBar(t: t)),

                    if (!user.quickActionsAtBottom)
                      _WinampBevel(
                        t: t,
                        margin: const EdgeInsets.fromLTRB(4, 2, 4, 2),
                        child: const Padding(
                          padding: EdgeInsets.fromLTRB(3, 2, 8, 2),
                          child: TopBar(),
                        ),
                      )
                    else if (user.bottomBarOnTop)
                      const PinnedAndTrayList(),

                    // Main LCD well — window switcher
                    _WinampBevel(
                      t: t,
                      inset: true,
                      margin: const EdgeInsets.fromLTRB(5, 3, 5, 2),
                      color: t.lcd.withValues(alpha: hasBackdrop ? 0.88 : 1.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.zero,
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
                                    painter: WinampLcdPainter(
                                      accent: t.accent,
                                      glow: t.glow,
                                      isDark: t.isDark,
                                    ),
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

                    // Info bar LCD well
                    _WinampBevel(
                      t: t,
                      inset: true,
                      margin: const EdgeInsets.fromLTRB(5, 2, 5, 4),
                      color: t.lcd.withValues(alpha: hasBackdrop ? 0.88 : 1.0),
                      child: const Padding(
                        padding: EdgeInsets.fromLTRB(6, 1, 6, 1),
                        child: BottomBar(),
                      ),
                    ),
                    // Equalizer visualizer strip
                    _WinampEqualizer(t: t),
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
// Tokens
// ---------------------------------------------------------------------------

class _WinampTokens {
  _WinampTokens._({
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
    required this.ledOff,
  });

  factory _WinampTokens.fromTheme() {
    final Color bg = Design.background;
    final Color text = Design.text;
    final Color accent = Design.accent;
    final bool isDark = bg.computeLuminance() < 0.5;
    final double glow = (Design.gradientAlpha.clamp(0, 255)) / 255.0;

    Color lift(Color base, double a) => Color.alphaBlend(Colors.white.withValues(alpha: a), base);
    Color sink(Color base, double a) => Color.alphaBlend(Colors.black.withValues(alpha: a), base);

    return _WinampTokens._(
      isDark: isDark,
      glow: glow,
      accent: accent,
      text: text,
      bevelHi: Colors.white.withValues(alpha: isDark ? 0.18 : 0.70),
      bevelLo: Colors.black.withValues(alpha: isDark ? 0.60 : 0.35),
      metalHi: lift(bg, isDark ? 0.12 : 0.30),
      metalMid: bg,
      metalLo: sink(bg, isDark ? 0.18 : 0.12),
      lcd: Color.alphaBlend(
        accent.withValues(alpha: 0.05 + glow * 0.06),
        sink(bg, isDark ? 0.35 : 0.18),
      ),
      ledOff: text.withValues(alpha: isDark ? 0.15 : 0.22),
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
  final Color ledOff;
}

// ---------------------------------------------------------------------------
// Chassis background
// ---------------------------------------------------------------------------

class _WinampChassis extends StatelessWidget {
  const _WinampChassis({required this.t, required this.hasBackdrop});

  final _WinampTokens t;
  final bool hasBackdrop;

  @override
  Widget build(BuildContext context) {
    final double bodyAlpha = hasBackdrop ? 0.84 : 1.0;

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
      child: Container(
        decoration: BoxDecoration(
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
          borderRadius: BorderRadius.circular(Design.borderRadius),
          border: Border.all(
            color: t.isDark ? Colors.white.withValues(alpha: 0.10) : Colors.white.withValues(alpha: 0.50),
          ),
        ),
        child: Stack(
          children: <Widget>[
            if (Design.hasBackdrop) const StableBackdrop(),
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: WinampBrushedPainter(isDark: t.isDark),
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
// 3D Bevel widget
// ---------------------------------------------------------------------------

class _WinampBevel extends StatelessWidget {
  const _WinampBevel({
    required this.t,
    required this.child,
    this.inset = false,
    this.color,
    this.margin,
  });

  final _WinampTokens t;
  final Widget child;
  final bool inset;
  final Color? color;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.zero,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: inset ? <Color>[t.bevelLo, t.bevelHi] : <Color>[t.bevelHi, t.bevelLo],
        ),
      ),
      padding: const EdgeInsets.all(1),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.zero,
          color: color,
        ),
        child: child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Title bar with LED dots
// ---------------------------------------------------------------------------

class _WinampTitleBar extends StatelessWidget {
  const _WinampTitleBar({required this.t});

  final _WinampTokens t;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
      child: Row(
        children: <Widget>[
          // Stereo LED indicators
          _LedDot(t: t, on: true),
          const SizedBox(width: 2),
          _LedDot(t: t, on: true),
          const SizedBox(width: 6),
          Text(
            'QUICKMENU',
            style: TextStyle(
              fontSize: Design.baseFontSize - 1,
              fontFamily: Design.uiFontFamily,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              color: t.text.withValues(alpha: 0.45),
            ),
          ),
          const Spacer(),
          // Minimize / close box dots (decorative)
          for (int i = 0; i < 3; i++) ...<Widget>[
            _LedDot(t: t, on: i < 2),
            const SizedBox(width: 2),
          ],
        ],
      ),
    );
  }
}

class _LedDot extends StatelessWidget {
  const _LedDot({required this.t, required this.on});

  final _WinampTokens t;
  final bool on;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 5,
      height: 3,
      decoration: BoxDecoration(
        color: on ? t.accent : t.ledOff,
        borderRadius: BorderRadius.zero,
        boxShadow: on
            ? <BoxShadow>[
                BoxShadow(
                  color: t.accent.withValues(alpha: 0.65),
                  blurRadius: 4,
                  spreadRadius: 0,
                ),
              ]
            : null,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Equalizer visualization strip
// ---------------------------------------------------------------------------

class _WinampEqualizer extends StatelessWidget {
  const _WinampEqualizer({required this.t});

  final _WinampTokens t;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 2, 6, 3),
      child: SizedBox(
        height: 14,
        child: Row(
          children: <Widget>[
            for (int i = 0; i < 12; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: _EqBar(
                    t: t,
                    fill: _kEqPattern[i % _kEqPattern.length],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

const List<double> _kEqPattern = <double>[
  0.75,
  0.45,
  0.90,
  0.30,
  0.60,
  0.85,
  0.40,
  0.70,
  0.55,
  0.95,
  0.35,
  0.65,
];

class _EqBar extends StatelessWidget {
  const _EqBar({required this.t, required this.fill});

  final _WinampTokens t;
  final double fill;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int segments = max(4, constraints.maxHeight ~/ 2.5);
        final int lit = (segments * fill).round().clamp(1, segments);
        return Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            for (int i = 0; i < segments; i++)
              Container(
                height: 1.5,
                margin: const EdgeInsets.only(bottom: 1),
                color: i >= (segments - lit) ? t.accent : t.ledOff,
              ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Section marker with LED pip
// ---------------------------------------------------------------------------

// ignore: unused_element
class _WinampSectionMarker extends StatelessWidget {
  const _WinampSectionMarker({required this.label, required this.t});

  final String label;
  final _WinampTokens t;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 4, 2),
      child: Row(
        children: <Widget>[
          _LedDot(t: t, on: true),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: t.accent,
              fontFamily: Design.uiFontFamily,
              fontSize: Design.baseFontSize - 1,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
              height: 1,
              shadows: <Shadow>[
                Shadow(
                  color: t.accent.withValues(alpha: 0.55),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Container(
              height: 1,
              color: t.text.withValues(alpha: t.isDark ? 0.12 : 0.18),
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

/// Fine horizontal brushed-metal grain.
class WinampBrushedPainter extends CustomPainter {
  const WinampBrushedPainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint light = Paint()..color = Colors.white.withValues(alpha: isDark ? 0.012 : 0.08);
    final Paint dark = Paint()..color = Colors.black.withValues(alpha: isDark ? 0.025 : 0.03);
    for (double y = 0; y < size.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), dark);
      canvas.drawRect(Rect.fromLTWH(0, y + 1, size.width, 1), light);
    }
  }

  @override
  bool shouldRepaint(covariant WinampBrushedPainter oldDelegate) => oldDelegate.isDark != isDark;
}

/// LCD glass overlay: corner ticks, top shadow, diagonal glare.
class WinampLcdPainter extends CustomPainter {
  const WinampLcdPainter({
    required this.accent,
    required this.glow,
    required this.isDark,
  });

  final Color accent;
  final double glow;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;

    // Corner ticks (OSD style)
    final Paint tick = Paint()..color = accent.withValues(alpha: (0.28 + glow * 0.30).clamp(0.0, 1.0));
    const double inset = 3;
    const double len = 6;
    const double w = 1.2;

    canvas.drawRect(const Rect.fromLTWH(inset, inset, len, w), tick);
    canvas.drawRect(const Rect.fromLTWH(inset, inset, w, len), tick);
    canvas.drawRect(Rect.fromLTWH(size.width - inset - len, inset, len, w), tick);
    canvas.drawRect(Rect.fromLTWH(size.width - inset - w, inset, w, len), tick);
    canvas.drawRect(Rect.fromLTWH(inset, size.height - inset - w, len, w), tick);
    canvas.drawRect(Rect.fromLTWH(inset, size.height - inset - len, w, len), tick);
    canvas.drawRect(Rect.fromLTWH(size.width - inset - len, size.height - inset - w, len, w), tick);
    canvas.drawRect(Rect.fromLTWH(size.width - inset - w, size.height - inset - len, w, len), tick);

    // Top recess shadow
    final Paint topShadow = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          Colors.black.withValues(alpha: isDark ? 0.32 : 0.18),
          Colors.transparent,
        ],
        stops: const <double>[0.0, 0.14],
      ).createShader(rect);
    canvas.drawRect(rect, topShadow);

    // Diagonal glare
    final Paint glare = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.center,
        colors: <Color>[
          Colors.white.withValues(alpha: (isDark ? 0.025 : 0.06) + glow * 0.015),
          Colors.transparent,
        ],
      ).createShader(rect);
    canvas.drawRect(rect, glare);
  }

  @override
  bool shouldRepaint(covariant WinampLcdPainter oldDelegate) =>
      oldDelegate.accent != accent || oldDelegate.glow != glow || oldDelegate.isDark != isDark;
}
