import 'dart:math' as math;

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

/// "Cassette" QuickMenu design — cassette-futurism hardware.
///
/// Instead of a translucent digital panel, the menu renders as a physical
/// piece of retro-future equipment: a molded device shell with corner screws,
/// an engraved fascia label, grip ridges and LED indicators; a raised plate
/// holding the quick-action buttons; and the window switcher recessed behind
/// a scanlined CRT glass window. Everything is derived from the user's theme
/// colors (`Design.background` / `Design.text` / `Design.accent`), and
/// `Design.gradientAlpha` acts as the "phosphor" knob — it scales scanline
/// strength, screen tint and LED glow.
Color _lift(Color base, double amount) => Color.alphaBlend(Colors.white.withValues(alpha: amount), base);
Color _sink(Color base, double amount) => Color.alphaBlend(Colors.black.withValues(alpha: amount), base);

class _DeckPalette {
  _DeckPalette._({
    required this.isDark,
    required this.intensity,
    required this.accent,
    required this.text,
    required this.bezelHi,
    required this.bezelMid,
    required this.bezelLo,
    required this.plateHi,
    required this.plateLo,
    required this.screen,
    required this.grooveDark,
    required this.grooveLight,
    required this.engraved,
  });

  factory _DeckPalette.fromTheme() {
    final Color bg = Design.background;
    final Color text = Design.text;
    final Color accent = Design.accent;
    final bool isDark = bg.computeLuminance() < 0.5;
    final double intensity = (Design.gradientAlpha.clamp(0, 255)) / 255.0;
    return _DeckPalette._(
      isDark: isDark,
      intensity: intensity,
      accent: accent,
      text: text,
      bezelHi: _lift(bg, isDark ? 0.09 : 0.30),
      bezelMid: bg,
      bezelLo: _sink(bg, isDark ? 0.20 : 0.08),
      plateHi: _lift(bg, isDark ? 0.13 : 0.40),
      plateLo: _sink(bg, isDark ? 0.10 : 0.04),
      screen: Color.alphaBlend(
        accent.withValues(alpha: 0.03 + intensity * 0.05),
        _sink(bg, isDark ? 0.35 : 0.10),
      ),
      grooveDark: Colors.black.withValues(alpha: isDark ? 0.45 : 0.16),
      grooveLight: Colors.white.withValues(alpha: isDark ? 0.07 : 0.55),
      engraved: text.withValues(alpha: 0.45),
    );
  }

  final bool isDark;
  final double intensity;
  final Color accent;
  final Color text;
  final Color bezelHi;
  final Color bezelMid;
  final Color bezelLo;
  final Color plateHi;
  final Color plateLo;
  final Color screen;
  final Color grooveDark;
  final Color grooveLight;
  final Color engraved;
}

class MainMenuCassetteWidget extends StatelessWidget {
  const MainMenuCassetteWidget({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // register as theme-dependent so Design.* values update live
    final _DeckPalette p = _DeckPalette.fromTheme();
    final bool hasBackdrop = user.activeBackdropPath.isNotEmpty;
    final double radius = Design.borderRadius;
    final double shellAlpha = hasBackdrop ? 0.82 : 1.0;

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: 203,
        maxHeight: MediaQuery.of(context).size.height - 50,
      ),
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(
            children: <Widget>[
              // ---- Device shell (molded bezel) ----
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
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            p.bezelHi.withValues(alpha: shellAlpha),
                            p.bezelMid.withValues(alpha: shellAlpha),
                            p.bezelLo.withValues(alpha: shellAlpha),
                          ],
                          stops: const <double>[0.0, 0.45, 1.0],
                        ),
                        borderRadius: BorderRadius.circular(radius),
                        border: Border.all(
                          color: p.isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.14),
                        ),
                      ),
                      child: Design.hasBackdrop ? const Stack(children: <Widget>[StableBackdrop()]) : null,
                    ),
                  ),
                ),
              ),

              // ---- Fascia content ----
              RepaintBoundary(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _FasciaHeader(p: p),
                    if (!user.quickActionsAtBottom) _ButtonPlate(p: p),
                    if (user.bottomBarOnTop) const PinnedAndTrayList(),
                    _CrtScreen(p: p, hasBackdrop: hasBackdrop),
                    if (!user.bottomBarOnTop) const PinnedAndTrayList(),
                    if (user.taskManagerStats) const TaskbarStats(withTopDivider: false),
                    if (user.libreStats) const LibreStats(withTopDivider: false),
                    _StatusPlate(p: p, shellAlpha: shellAlpha),
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
// Fascia header — screws, engraved model label, grip ridges, LED cluster
// ---------------------------------------------------------------------------

class _FasciaHeader extends StatelessWidget {
  const _FasciaHeader({required this.p});

  final _DeckPalette p;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(9, 6, 9, 4),
      child: Row(
        children: <Widget>[
          _Screw(p: p, angle: 0.6),
          const SizedBox(width: 8),
          Text(
            "TABAME · QM-70",
            style: TextStyle(
              fontSize: Design.baseFontSize - 1.5,
              fontFamily: Design.uiFontFamily,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.2,
              color: p.engraved,
              shadows: p.isDark ? null : <Shadow>[Shadow(color: p.grooveLight, offset: const Offset(0, 1))],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: SizedBox(
                height: 7,
                child: CustomPaint(
                  painter: _RidgePainter(light: p.grooveLight, dark: p.grooveDark),
                ),
              ),
            ),
          ),
          _LedCluster(p: p),
          const SizedBox(width: 8),
          _Screw(p: p, angle: 2.1),
        ],
      ),
    );
  }
}

class _Screw extends StatelessWidget {
  const _Screw({required this.p, required this.angle});

  final _DeckPalette p;
  final double angle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.4, -0.5),
          colors: <Color>[p.plateHi, p.bezelLo],
        ),
        border: Border.all(color: Colors.black.withValues(alpha: p.isDark ? 0.4 : 0.2), width: 0.5),
      ),
      child: Center(
        child: Transform.rotate(
          angle: angle,
          child: Container(
            width: 4.5,
            height: 1,
            color: Colors.black.withValues(alpha: p.isDark ? 0.5 : 0.35),
          ),
        ),
      ),
    );
  }
}

class _LedCluster extends StatelessWidget {
  const _LedCluster({required this.p});

  final _DeckPalette p;

  @override
  Widget build(BuildContext context) {
    final double glow = (0.3 + p.intensity * 0.5).clamp(0.0, 1.0);
    Widget pip(Color fill, {List<BoxShadow>? shadow}) {
      return Container(
        width: 4,
        height: 4,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: fill,
          boxShadow: shadow,
          border: Border.all(color: Colors.black.withValues(alpha: p.isDark ? 0.4 : 0.15), width: 0.5),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        pip(
          p.accent,
          shadow: <BoxShadow>[BoxShadow(color: p.accent.withValues(alpha: glow), blurRadius: 5, spreadRadius: 0.5)],
        ),
        const SizedBox(width: 4),
        pip(p.accent.withValues(alpha: 0.25)),
        const SizedBox(width: 4),
        pip(p.text.withValues(alpha: 0.12)),
      ],
    );
  }
}

/// Machined grip grooves: alternating dark/light 1px vertical lines.
class _RidgePainter extends CustomPainter {
  const _RidgePainter({required this.light, required this.dark});

  final Color light;
  final Color dark;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint darkPaint = Paint()..color = dark;
    final Paint lightPaint = Paint()..color = light;
    for (double x = 0; x + 2 <= size.width; x += 4) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 1, size.height), darkPaint);
      canvas.drawRect(Rect.fromLTWH(x + 1, 0, 1, size.height), lightPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RidgePainter oldDelegate) => oldDelegate.light != light || oldDelegate.dark != dark;
}

// ---------------------------------------------------------------------------
// Raised button plate (quick actions as a physical control strip)
// ---------------------------------------------------------------------------

class _ButtonPlate extends StatelessWidget {
  const _ButtonPlate({required this.p});

  final _DeckPalette p;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(5, 0, 5, 1),
      padding: const EdgeInsets.fromLTRB(3, 2, 8, 2),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[p.plateHi, p.plateLo],
        ),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.black.withValues(alpha: p.isDark ? 0.35 : 0.12), width: 0.8),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: p.isDark ? 0.35 : 0.14),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: const TopBar(),
    );
  }
}

// ---------------------------------------------------------------------------
// CRT window — the task switcher recessed behind scanlined glass
// ---------------------------------------------------------------------------

class _CrtScreen extends StatelessWidget {
  const _CrtScreen({required this.p, required this.hasBackdrop});

  final _DeckPalette p;
  final bool hasBackdrop;

  @override
  Widget build(BuildContext context) {
    final double screenRadius = math.max(4.0, Design.borderRadius * 0.5);
    return Container(
      margin: const EdgeInsets.fromLTRB(6, 5, 6, 3),
      decoration: BoxDecoration(
        color: p.screen.withValues(alpha: hasBackdrop ? 0.85 : 1.0),
        borderRadius: BorderRadius.circular(screenRadius),
        border: Border.all(color: Colors.black.withValues(alpha: p.isDark ? 0.55 : 0.25)),
        // Bottom lip highlight — sells the "recessed into the shell" cut.
        boxShadow: <BoxShadow>[
          BoxShadow(color: p.grooveLight, offset: const Offset(0, 1)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(screenRadius - 1),
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
                    painter: _ScreenFxPainter(strength: p.intensity, isDark: p.isDark),
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

/// Scanlines + inner shadow + diagonal glass sheen over the CRT window.
class _ScreenFxPainter extends CustomPainter {
  const _ScreenFxPainter({required this.strength, required this.isDark});

  final double strength;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;

    // Scanlines.
    final Paint line = Paint()
      ..color = Colors.black.withValues(alpha: ((isDark ? 0.05 : 0.025) + strength * 0.07).clamp(0.0, 1.0));
    for (double y = 1; y < size.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), line);
    }

    // Recess shadow along the top edge.
    final Paint topShadow = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          Colors.black.withValues(alpha: isDark ? 0.30 : 0.14),
          Colors.transparent,
        ],
        stops: const <double>[0.0, 0.14],
      ).createShader(rect);
    canvas.drawRect(rect, topShadow);

    // Diagonal glass sheen from the top-left corner.
    final Paint sheen = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.center,
        colors: <Color>[
          Colors.white.withValues(alpha: isDark ? 0.04 : 0.10),
          Colors.transparent,
        ],
      ).createShader(rect);
    canvas.drawRect(rect, sheen);
  }

  @override
  bool shouldRepaint(covariant _ScreenFxPainter oldDelegate) =>
      oldDelegate.strength != strength || oldDelegate.isDark != isDark;
}

// ---------------------------------------------------------------------------
// Status plate — riveted base plate holding the info bar
// ---------------------------------------------------------------------------

class _StatusPlate extends StatelessWidget {
  const _StatusPlate({required this.p, required this.shellAlpha});

  final _DeckPalette p;
  final double shellAlpha;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            p.plateLo.withValues(alpha: shellAlpha),
            p.bezelLo.withValues(alpha: shellAlpha),
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Embossed seam: shadow line over highlight line reads as a groove.
          Container(height: 1, color: p.grooveDark),
          Container(height: 1, color: p.grooveLight),
          Padding(
            padding: const EdgeInsets.fromLTRB(9, 3, 9, 5),
            child: Row(
              children: <Widget>[
                _Screw(p: p, angle: 1.2),
                const SizedBox(width: 8),
                const Expanded(child: BottomBar()),
                const SizedBox(width: 8),
                _Screw(p: p, angle: 2.8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
