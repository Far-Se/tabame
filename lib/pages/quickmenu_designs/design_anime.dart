import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../models/classes/boxes/quick_menu_box.dart';
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

/// "Anime" QuickMenu design — a kawaii character-card / visual-novel panel.
///
/// The menu renders as a soft sticker-card: a scalloped ribbon banner across
/// the top (with a little sparkle-star cluster tucked in the corner), a
/// pastel card body dusted with a slow-twinkling sparkle field, a strip of
/// "washi tape" pinning the window switcher card in place like a photo in a
/// scrapbook, and a rounded pill-shaped footer ribbon (with a small heart)
/// holding the info bar. `Design.gradientAlpha` scales the sparkle brightness
/// so louder themes twinkle harder.
class _AnimeTokens {
  _AnimeTokens._({
    required this.isDark,
    required this.glow,
    required this.accent,
    required this.text,
    required this.bg,
    required this.card,
    required this.cardBorder,
    required this.cardShadow,
    required this.ribbon,
    required this.ribbonText,
    required this.tape,
  });

  factory _AnimeTokens.fromTheme() {
    final Color bg = Design.background;
    final Color text = Design.text;
    final Color accent = Design.accent;
    final bool isDark = bg.computeLuminance() < 0.5;
    final double glow = (Design.gradientAlpha.clamp(0, 255)) / 255.0;
    return _AnimeTokens._(
      isDark: isDark,
      glow: glow,
      accent: accent,
      text: text,
      bg: bg,
      card: Color.alphaBlend(Colors.white.withValues(alpha: isDark ? 0.05 : 0.55), bg),
      cardBorder: accent.withValues(alpha: isDark ? 0.30 : 0.22),
      cardShadow: Colors.black.withValues(alpha: isDark ? 0.45 : 0.16),
      ribbon: Color.alphaBlend(accent.withValues(alpha: isDark ? 0.32 : 0.20), bg),
      ribbonText: isDark
          ? Colors.white.withValues(alpha: 0.90)
          : Color.alphaBlend(Colors.black.withValues(alpha: 0.55), accent),
      tape: accent.withValues(alpha: isDark ? 0.55 : 0.45),
    );
  }

  final bool isDark;
  final double glow;
  final Color accent;
  final Color text;
  final Color bg;
  final Color card;
  final Color cardBorder;
  final Color cardShadow;
  final Color ribbon;
  final Color ribbonText;
  final Color tape;
}

class MainMenuAnimeWidget extends StatelessWidget {
  const MainMenuAnimeWidget({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // register as theme-dependent so Design.* values update live
    final _AnimeTokens t = _AnimeTokens.fromTheme();
    final bool hasBackdrop = user.activeBackdropPath.isNotEmpty;
    final double radius = Design.borderRadius;

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: 203,
        maxHeight: MediaQuery.of(context).size.height - 40,
      ),
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(
            children: <Widget>[
              // ---- Pastel card body ----
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
                        color: t.bg.withValues(alpha: hasBackdrop ? 0.85 : 1.0),
                        borderRadius: BorderRadius.circular(radius),
                        border: Border.all(color: t.cardBorder),
                      ),
                      child: Stack(
                        children: <Widget>[
                          if (Design.hasBackdrop) const StableBackdrop(),
                          Positioned.fill(
                            child: IgnorePointer(
                              child: RepaintBoundary(
                                child: _SparkleField(accent: t.accent, glow: t.glow),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ---- Card front ----
              RepaintBoundary(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _RibbonHeader(t: t),
                    if (!user.quickActionsAtBottom)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(9, 3, 9, 0),
                        child: TopBar(),
                      )
                    else if (user.bottomBarOnTop)
                      const PinnedAndTrayList(),

                    // Window switcher, "taped" onto the card like a photo.
                    _WashiCard(
                      t: t,
                      margin: const EdgeInsets.fromLTRB(7, 7, 7, 3),
                      child: const TaskBar(),
                    ),

                    if (!user.bottomBarOnTop) const PinnedAndTrayList(),
                    if (user.taskManagerStats) const TaskbarStats(withTopDivider: false),
                    if (user.libreStats) const LibreStats(withTopDivider: false),

                    _RibbonFooter(t: t),
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
// Header — scalloped ribbon banner
// ---------------------------------------------------------------------------

class _RibbonHeader extends StatelessWidget {
  const _RibbonHeader({required this.t});

  final _AnimeTokens t;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(painter: _ScallopPainter(color: t.ribbon, isDark: t.isDark)),
            ),
          ),
          Positioned(
            left: 8,
            top: 0,
            bottom: 3,
            child: Center(
              child: Icon(Icons.auto_awesome_rounded, size: 11, color: t.ribbonText.withValues(alpha: 0.85)),
            ),
          ),
          Positioned(
            right: 8,
            top: 0,
            bottom: 3,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (int i = 0; i < 3; i++)
                    Padding(
                      padding: const EdgeInsets.only(left: 3),
                      child: Icon(
                        Icons.star_rounded,
                        size: 7 + i.toDouble(),
                        color: t.ribbonText.withValues(alpha: 0.75 - i * 0.15),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A banner shape with a scalloped (bumpy) bottom edge, like a card-topper
/// ribbon or a cut-paper sticker tab.
class _ScallopPainter extends CustomPainter {
  const _ScallopPainter({required this.color, required this.isDark});

  final Color color;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    const double scallopHeight = 4;
    const double bump = 7;
    final double bodyHeight = size.height - scallopHeight;

    final Path path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, bodyHeight);

    double x = size.width;
    while (x > 0) {
      final double nx = (x - bump).clamp(0.0, size.width);
      path.quadraticBezierTo(x - bump / 2, bodyHeight + scallopHeight, nx, bodyHeight);
      x = nx;
    }
    path.close();

    canvas.drawPath(path, Paint()..color = color);
    canvas.drawLine(
      Offset(0, bodyHeight),
      Offset(size.width, bodyHeight),
      Paint()
        ..color = Colors.black.withValues(alpha: isDark ? 0.22 : 0.08)
        ..strokeWidth = 0.6,
    );
  }

  @override
  bool shouldRepaint(covariant _ScallopPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.isDark != isDark;
}

// ---------------------------------------------------------------------------
// Washi-taped card — wraps the window switcher
// ---------------------------------------------------------------------------

class _WashiCard extends StatelessWidget {
  const _WashiCard({required this.t, required this.child, this.margin});

  final _AnimeTokens t;
  final Widget child;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.cardBorder, width: 0.8),
        boxShadow: <BoxShadow>[BoxShadow(color: t.cardShadow, blurRadius: 5, offset: const Offset(0, 2))],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: child),
          ),
          // The "tape" strip pinning the card down.
          Positioned(
            top: -5,
            left: 0,
            right: 0,
            child: Center(
              child: Transform.rotate(
                angle: -0.035,
                child: Container(
                  width: 36,
                  height: 10,
                  decoration: BoxDecoration(
                    color: t.tape,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: <BoxShadow>[BoxShadow(color: t.cardShadow, blurRadius: 2, offset: const Offset(0, 1))],
                  ),
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
// Footer — rounded ribbon pill holding the info bar
// ---------------------------------------------------------------------------

class _RibbonFooter extends StatelessWidget {
  const _RibbonFooter({required this.t});

  final _AnimeTokens t;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(7, 0, 7, 6),
      padding: const EdgeInsets.fromLTRB(9, 2, 7, 2),
      decoration: BoxDecoration(
        color: t.ribbon,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.cardBorder, width: 0.6),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.favorite_rounded, size: 9, color: t.accent.withValues(alpha: 0.85)),
          const SizedBox(width: 6),
          const Expanded(child: BottomBar()),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sparkle field — a slow, self-pausing twinkle overlay
// ---------------------------------------------------------------------------

class _SparkleField extends StatefulWidget {
  const _SparkleField({required this.accent, required this.glow});

  final Color accent;
  final double glow;

  @override
  State<_SparkleField> createState() => _SparkleFieldState();
}

class _SparkleFieldState extends State<_SparkleField> with QuickMenuTriggers {
  Timer? _timer;
  int _phase = 0;

  // Fixed, seeded positions so the field doesn't reshuffle on every rebuild.
  static final List<Offset> _spots = List<Offset>.generate(
    14,
    (int i) => Offset(Random(i * 97 + 3).nextDouble(), Random(i * 53 + 7).nextDouble()),
  );

  @override
  void initState() {
    super.initState();
    QuickMenuFunctions.addListener(this);
    _start();
  }

  void _start() {
    _timer ??= Timer.periodic(const Duration(milliseconds: 900), (_) {
      if (mounted) setState(() => _phase++);
    });
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Future<void> onQuickMenuToggled(bool visible, QuickMenuPage type) async {
    // The QuickMenu stays mounted while hidden — stop ticking off-screen.
    if (visible) {
      _start();
    } else {
      _stop();
    }
  }

  @override
  void dispose() {
    _stop();
    QuickMenuFunctions.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SparklePainter(spots: _spots, accent: widget.accent, glow: widget.glow, phase: _phase),
    );
  }
}

class _SparklePainter extends CustomPainter {
  const _SparklePainter({required this.spots, required this.accent, required this.glow, required this.phase});

  final List<Offset> spots;
  final Color accent;
  final double glow;
  final int phase;

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < spots.length; i++) {
      final Offset o = spots[i];
      final double cx = o.dx * size.width;
      final double cy = o.dy * size.height;

      // Each sparkle lights up on its own slow beat.
      final bool lit = (phase + i) % 5 == 0;
      final double a = ((lit ? 0.55 : 0.10) * (0.5 + glow * 0.5)).clamp(0.0, 1.0);
      final double r = lit ? 2.6 : 1.3;
      final Paint p = Paint()..color = accent.withValues(alpha: a);

      // Tiny 4-point sparkle: a diamond, with a cross flare when lit.
      final Path diamond = Path()
        ..moveTo(cx, cy - r)
        ..lineTo(cx + r * 0.45, cy)
        ..lineTo(cx, cy + r)
        ..lineTo(cx - r * 0.45, cy)
        ..close();
      canvas.drawPath(diamond, p);

      if (lit) {
        final Paint flare = Paint()
          ..color = accent.withValues(alpha: a * 0.7)
          ..strokeWidth = 0.6;
        canvas.drawLine(Offset(cx - r * 1.7, cy), Offset(cx + r * 1.7, cy), flare);
        canvas.drawLine(Offset(cx, cy - r * 1.7), Offset(cx, cy + r * 1.7), flare);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SparklePainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.accent != accent || oldDelegate.glow != glow;
}
