import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../models/classes/boxes.dart';
import '../../models/globals.dart';
import '../../models/settings.dart';
import '../../models/util/theme_colors.dart';
import '../../widgets/quickmenu/bottom_bar.dart';
import '../../widgets/quickmenu/info_bar.dart';
import '../../widgets/quickmenu/libre_stats.dart';
import '../../widgets/quickmenu/task_bar.dart';
import '../../widgets/quickmenu/taskbar_stats.dart';
import '../../widgets/quickmenu/top_bar.dart';
import 'design_backdrop_stable.dart';

/// "Console" QuickMenu design — a physical hardware mixing-desk faceplate.
///
/// The menu reads as a piece of brushed-aluminum gear rather than software:
/// a beveled two-tone bezel, four Phillips-head rivets pinning the corners,
/// a small "power" LED that breathes gently while the panel is open, engraved
/// (light-over-dark) groove dividers instead of flat `Divider`s between
/// sections, and a bottom "signal strip" of channel LEDs that light up
/// according to which optional sections (task-manager stats / libre stats)
/// are actually active — so the strip reflects real state, not decoration
/// for its own sake.
///
/// Colors still derive from the user's theme (`Design.background` /
/// `Design.accent`); the brushed-metal texture is a cheap `CustomPainter`
/// (a handful of faint diagonal strokes) rather than an image asset, so it
/// re-themes instantly with everything else.
class MainMenuConsoleWidget extends StatefulWidget {
  const MainMenuConsoleWidget({super.key});

  @override
  State<MainMenuConsoleWidget> createState() => _MainMenuConsoleWidgetState();
}

class _MainMenuConsoleWidgetState extends State<MainMenuConsoleWidget>
    with SingleTickerProviderStateMixin, QuickMenuTriggers {
  late final AnimationController _breathe;

  @override
  void initState() {
    super.initState();
    _breathe = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    QuickMenuFunctions.addListener(this);
    if (QuickMenuFunctions.isQuickMenuVisible) {
      _breathe.repeat(reverse: true);
    }
  }

  @override
  Future<void> onQuickMenuToggled(bool visible, QuickMenuPage type) async {
    if (visible) {
      _breathe.repeat(reverse: true);
    } else {
      _breathe.stop();
    }
  }

  @override
  void dispose() {
    QuickMenuFunctions.removeListener(this);
    _breathe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData themeX = Theme.of(context);
    final Color accent = Design.accent;
    final Color bg = Design.background;
    final bool isDark = bg.computeLuminance() < 0.5;
    final bool hasBackdrop = user.activeBackdropPath.isNotEmpty;
    final double radius = Design.borderRadius;

    final Color bezelLight = Color.alphaBlend((isDark ? Colors.white : Colors.black).withAlpha(isDark ? 26 : 10), bg);
    final Color bezelDark = Color.alphaBlend((isDark ? Colors.black : Colors.black).withAlpha(isDark ? 90 : 40), bg);

    final List<double> points = Design.panelOpacityPoints;
    final List<double> stops = <double>[];
    final List<Color> gradColors = <Color>[];
    for (int i = 0; i < points.length; i += 2) {
      stops.add(points[i]);
      gradColors.add(Colors.white.withValues(alpha: points[i + 1]));
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: 203,
        maxHeight: MediaQuery.of(context).size.height - 50,
      ),
      child: RepaintBoundary(
        child: Container(
          // Outer bezel edge — dark, like a routed metal lip.
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            color: bezelDark,
            boxShadow: <BoxShadow>[
              BoxShadow(color: Colors.black.withValues(alpha: 0.22), blurRadius: 22, offset: const Offset(0, 10)),
            ],
          ),
          child: Container(
            // Inner bezel edge — light, catching the "overhead" light.
            padding: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius - 1),
              color: bezelLight,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius - 2),
              child: Stack(
                children: <Widget>[
                  // Faceplate surface: brushed texture + backdrop mask.
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: ShaderMask(
                        blendMode: BlendMode.dstIn,
                        shaderCallback: (Rect bounds) {
                          return LinearGradient(
                            begin: panelAlignmentMap[Design.panelOpacityBegin] ?? Alignment.topCenter,
                            end: panelAlignmentMap[Design.panelOpacityEnd] ?? Alignment.bottomCenter,
                            colors: gradColors,
                            stops: stops,
                          ).createShader(bounds);
                        },
                        child: Container(
                          color: bg.withValues(alpha: hasBackdrop ? 0.85 : 1.0),
                          child: Stack(
                            fit: StackFit.expand,
                            children: <Widget>[
                              CustomPaint(painter: _BrushedMetalPainter(isDark: isDark)),
                              if (Design.hasBackdrop) const StableBackdrop(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ---- Panel content ----
                  RepaintBoundary(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        DragToMoveArea(child: _ConsoleHeader(accent: accent, breathe: _breathe)),
                        if (!user.quickActionsAtBottom)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(6, 0, 6, 2),
                            child: TopBar(),
                          )
                        else if (user.bottomBarOnTop)
                          const PinnedAndTrayList(),
                        _GrooveDivider(color: themeX.colorScheme.onSurface),
                        const TaskBar(),
                        _GrooveDivider(color: themeX.colorScheme.onSurface),
                        if (!user.bottomBarOnTop) const PinnedAndTrayList(),
                        if (user.taskManagerStats) const TaskbarStats(),
                        if (user.libreStats) const LibreStats(),
                        _SignalStrip(
                          accent: accent,
                          channelsOn: <bool>[true, user.taskManagerStats, user.libreStats, hasBackdrop],
                        ),
                        const BottomBar(),
                      ],
                    ),
                  ),

                  // ---- Rivets, pinning the faceplate to its corners ----
                  Positioned(top: 5, left: 5, child: _Rivet(isDark: isDark)),
                  Positioned(top: 5, right: 5, child: _Rivet(isDark: isDark)),
                  Positioned(bottom: 5, left: 5, child: _Rivet(isDark: isDark)),
                  Positioned(bottom: 5, right: 5, child: _Rivet(isDark: isDark)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header — power LED + unit label, standing in for the old TopBar slot.
// ---------------------------------------------------------------------------

class _ConsoleHeader extends StatelessWidget {
  const _ConsoleHeader({required this.accent, required this.breathe});

  final Color accent;
  final AnimationController breathe;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 10, 4),
      child: Row(
        children: <Widget>[
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: breathe,
              builder: (BuildContext context, Widget? child) {
                final double t = 0.35 + breathe.value * 0.5;
                return Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(alpha: t),
                    boxShadow: <BoxShadow>[
                      BoxShadow(color: accent.withValues(alpha: t * 0.6), blurRadius: 6, spreadRadius: 1),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'TABAME · UNIT 01',
            style: TextStyle(
              fontSize: Design.baseFontSize - 1.5,
              fontFamily: Design.uiFontFamily,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              color: Design.text.withValues(alpha: 0.38),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Rivet — small Phillips-head screw sitting in each corner of the bezel.
// ---------------------------------------------------------------------------

class _Rivet extends StatelessWidget {
  const _Rivet({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final Color base = isDark ? const Color(0xffB9BEC6) : const Color(0xff8A8F98);
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: <Color>[base.withValues(alpha: 0.9), base.withValues(alpha: 0.35)],
          center: const Alignment(-0.3, -0.3),
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Colors.black38, blurRadius: 1.5, offset: Offset(0.5, 0.5)),
        ],
      ),
      child: CustomPaint(painter: _ScrewSlotPainter()),
    );
  }
}

class _ScrewSlotPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = Colors.black.withValues(alpha: 0.55)
      ..strokeWidth = 0.8;
    final double c = size.width / 2;
    canvas.drawLine(Offset(c - 2.2, c), Offset(c + 2.2, c), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Groove divider — an engraved line (dark hairline + light hairline) instead
// of a flat single-tone Divider, so sections read as milled into the metal.
// ---------------------------------------------------------------------------

class _GrooveDivider extends StatelessWidget {
  const _GrooveDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        children: <Widget>[
          Container(height: 1, color: color.withValues(alpha: 0.14)),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.05)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Signal strip — a row of channel LEDs along the bottom, lit according to
// which optional sections are actually enabled. Real state, not decoration.
// ---------------------------------------------------------------------------

class _SignalStrip extends StatelessWidget {
  const _SignalStrip({required this.accent, required this.channelsOn});

  final Color accent;
  final List<bool> channelsOn;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          for (final bool on in channelsOn) ...<Widget>[
            Container(
              width: 5,
              height: 5,
              margin: const EdgeInsets.only(left: 5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on ? accent.withValues(alpha: 0.85) : Colors.white.withValues(alpha: 0.08),
                boxShadow: on
                    ? <BoxShadow>[BoxShadow(color: accent.withValues(alpha: 0.5), blurRadius: 4, spreadRadius: 0.5)]
                    : null,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Brushed metal texture — a handful of faint, slightly-jittered diagonal
// strokes. Cheap to paint, cheap to re-theme, no image asset required.
// ---------------------------------------------------------------------------

class _BrushedMetalPainter extends CustomPainter {
  _BrushedMetalPainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final math.Random rnd = math.Random(7); // fixed seed: stable across rebuilds
    final Color strokeColor = (isDark ? Colors.white : Colors.black);
    final Paint paint = Paint()..strokeWidth = 1;
    final double diag = size.width + size.height;
    final int lineCount = (diag / 5).floor();

    for (int i = 0; i < lineCount; i++) {
      final double offset = i * 5.0 + rnd.nextDouble() * 2;
      final double alpha = 0.012 + rnd.nextDouble() * 0.02;
      paint.color = strokeColor.withValues(alpha: alpha);
      canvas.drawLine(
        Offset(offset - size.height, 0),
        Offset(offset, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BrushedMetalPainter oldDelegate) => oldDelegate.isDark != isDark;
}
