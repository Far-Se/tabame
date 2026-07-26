import 'package:flutter/material.dart';
import 'dart:math' as math;

import '../../pages/launcher/launcher_modal_theme.dart';
import '../globals.dart';
import '../settings.dart';

/// Frame for QuickMenu modal popups (`showQuickMenuModal`) so they follow the
/// active QuickMenu design, the same way the launcher's Ctrl+K actions modal
/// follows the launcher design via [LauncherModalTokens]/[LauncherModalFrame].
///
/// The popup hosts arbitrary panel content, so only the frame is themed here —
/// each design's fill, border, corner radius and signature textures (matrix
/// grid, gazette page rules, player brushed metal, terminal accent border…)
/// are re-derived from the same `Design.*` theme values the design widgets in
/// `pages/quickmenu_designs/` use.

Color _lift(Color base, double amount) => Color.alphaBlend(Colors.white.withValues(alpha: amount), base);
Color _sink(Color base, double amount) => Color.alphaBlend(Colors.black.withValues(alpha: amount), base);

class QuickMenuModalFrame extends StatelessWidget {
  const QuickMenuModalFrame({
    super.key,
    required this.width,
    required this.constraints,
    required this.child,
  });

  final double width;
  final BoxConstraints constraints;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Popups opened over the launcher page speak the launcher design instead —
    // the same frame the Ctrl+K actions modal uses.
    if (Globals.quickMenuPage == QuickMenuPage.launcher) {
      return LauncherModalFrame(
        tokens: LauncherModalTokens.of(context),
        width: width,
        margin: EdgeInsets.zero,
        constraints: constraints,
        child: child,
      );
    }

    final QuickMenuDesigns design = QuickMenuDesigns.values[user.quickMenuDesign];
    final ThemeData theme = Theme.of(context);
    final Color surface = theme.colorScheme.surface;
    final Color onSurface = theme.colorScheme.onSurface;
    final Color bg = Design.background;
    final Color accent = Design.accent;
    final Color text = Design.text;
    final bool isDark = bg.computeLuminance() < 0.5;
    final double intensity = (Design.gradientAlpha.clamp(0, 255)) / 255.0;
    final double r = Design.borderRadius;

    // Aurora's signature asymmetric corners; every other design keeps its
    // regular panel radius.
    final BorderRadius radius = design == QuickMenuDesigns.aurora && r > 0
        ? BorderRadius.only(
            topLeft: Radius.circular(r),
            bottomRight: Radius.circular(r),
            topRight: Radius.circular((r * 0.3) + 3),
            bottomLeft: Radius.circular((r * 0.3) + 3),
          )
        : BorderRadius.circular(r);

    final _FrameSpec spec = switch (design) {
      QuickMenuDesigns.classic => _FrameSpec(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: surface.withValues(alpha: 0.88),
            border: Border.all(color: onSurface.withValues(alpha: 0.12), width: 0.5),
          ),
        ),
      QuickMenuDesigns.modern => _FrameSpec(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                surface.withValues(alpha: 0.95),
                Color.alphaBlend(accent.withAlpha((Design.gradientAlpha * 24 / 100).toInt()), surface)
                    .withValues(alpha: 0.95),
                Color.alphaBlend(accent.withAlpha((Design.gradientAlpha * 10 / 100).toInt()), surface)
                    .withValues(alpha: 0.95),
              ],
            ),
            border: Border.all(color: accent.withAlpha(28)),
          ),
          underlays: <Widget>[
            // Top sheen, same as the panel's inner gradient.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Colors.white.withAlpha(14), Colors.transparent],
                ),
              ),
            ),
          ],
        ),
      QuickMenuDesigns.interface => _FrameSpec(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                Color.alphaBlend(
                        accent.withValues(alpha: 0.04 + ((Design.gradientAlpha.clamp(1, 100)) / 100) * 0.08), surface)
                    .withValues(alpha: 0.93),
                surface.withValues(alpha: 0.93),
              ],
            ),
            border: Border.all(color: onSurface.withValues(alpha: 0.08)),
          ),
        ),
      QuickMenuDesigns.matrix => _FrameSpec(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: Color.alphaBlend(accent.withValues(alpha: Design.gradientAlpha / 255.0), surface)
                .withValues(alpha: 0.95),
            border: Border.all(color: accent.withValues(alpha: 0.25), width: 0.8),
          ),
          underlays: <Widget>[
            CustomPaint(painter: _GridPainter(accent.withValues(alpha: 0.07))),
          ],
        ),
      QuickMenuDesigns.serene => _FrameSpec(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: RadialGradient(
              center: const Alignment(-0.6, -0.7),
              radius: 1.4,
              colors: <Color>[
                Color.alphaBlend(accent.withValues(alpha: 0.10 + intensity * 0.14), surface).withValues(alpha: 0.93),
                surface.withValues(alpha: 0.93),
              ],
            ),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.10) : Colors.white.withValues(alpha: 0.70),
              width: 0.8,
            ),
          ),
        ),
      QuickMenuDesigns.aurora => _FrameSpec(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: surface.withValues(alpha: 0.96),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.07) : accent.withValues(alpha: 0.16),
              width: 0.8,
            ),
          ),
          underlays: _auroraBlobs(accent, intensity),
        ),
      QuickMenuDesigns.terminal => _FrameSpec(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: bg.withValues(alpha: 0.95),
            border: Border.all(color: accent.withAlpha(80)),
          ),
        ),
      QuickMenuDesigns.cassette => _FrameSpec(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                _lift(bg, isDark ? 0.09 : 0.30).withValues(alpha: 0.96),
                bg.withValues(alpha: 0.96),
                _sink(bg, isDark ? 0.20 : 0.08).withValues(alpha: 0.96),
              ],
              stops: const <double>[0.0, 0.45, 1.0],
            ),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.14),
            ),
          ),
        ),
      QuickMenuDesigns.fluent => _FrameSpec(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: bg.withValues(alpha: 0.95),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.09) : Colors.black.withValues(alpha: 0.11),
            ),
          ),
          underlays: <Widget>[
            // Mica tint drifting in from the top.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    accent.withValues(alpha: (intensity * 0.10).clamp(0.0, 1.0)),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ],
        ),
      QuickMenuDesigns.gazette => _FrameSpec(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: bg.withValues(alpha: 0.96),
            border: Border.all(color: text.withValues(alpha: 0.45)),
          ),
          underlays: <Widget>[
            // Aged-paper vignette.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 1.25,
                  colors: <Color>[
                    Colors.transparent,
                    text.withValues(alpha: (0.03 + intensity * 0.07).clamp(0.0, 1.0)),
                  ],
                ),
              ),
            ),
          ],
          overlays: <Widget>[
            // Inner hairline of the double page frame.
            Container(
              margin: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                border: Border.all(color: text.withValues(alpha: 0.22), width: 0.8),
                borderRadius: BorderRadius.circular((r - 3).clamp(0.0, 100.0)),
              ),
            ),
          ],
        ),
      QuickMenuDesigns.player => _FrameSpec(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                _lift(bg, isDark ? 0.14 : 0.35).withValues(alpha: 0.97),
                bg.withValues(alpha: 0.97),
                _sink(bg, isDark ? 0.16 : 0.10).withValues(alpha: 0.97),
                bg.withValues(alpha: 0.97),
              ],
              stops: const <double>[0.0, 0.45, 0.9, 1.0],
            ),
          ),
          bevel: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Colors.white.withValues(alpha: isDark ? 0.16 : 0.75),
              Colors.black.withValues(alpha: isDark ? 0.55 : 0.30),
            ],
          ),
          underlays: <Widget>[
            CustomPaint(painter: _BrushedPainter(isDark: isDark)),
          ],
        ),
      QuickMenuDesigns.steam => _FrameSpec(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: bg.withValues(alpha: 0.95),
            border: Border.all(
              color: isDark ? Colors.black.withValues(alpha: 0.5) : Colors.black.withValues(alpha: 0.12),
            ),
          ),
          underlays: <Widget>[
            // Library ambient glow drifting in from the top-left.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.6, -1.4),
                  radius: 1.6,
                  colors: <Color>[
                    accent.withValues(alpha: (0.05 + intensity * 0.18).clamp(0.0, 1.0)),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ],
        ),
      QuickMenuDesigns.manifesto => _FrameSpec(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: bg.withValues(alpha: 0.98),
            border: Border.all(color: text, width: 2),
          ),
          underlays: <Widget>[
            CustomPaint(painter: _ManifestoRulePainter(text.withValues(alpha: isDark ? 0.10 : 0.075))),
          ],
          overlays: <Widget>[
            Align(
              alignment: Alignment.topRight,
              child: Container(width: 28, height: 6, color: accent),
            ),
          ],
        ),
      QuickMenuDesigns.vector => _FrameSpec(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: bg.withValues(alpha: 0.97),
            border: Border.all(color: text.withValues(alpha: isDark ? 0.14 : 0.18), width: 0.5),
          ),
          underlays: <Widget>[
            CustomPaint(painter: _VectorScanPainter(text.withValues(alpha: isDark ? 0.05 : 0.04))),
          ],
          overlays: <Widget>[
            CustomPaint(painter: _VectorBracketPainter(accent)),
          ],
        ),
      QuickMenuDesigns.ledger => _FrameSpec(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: bg.withValues(alpha: 0.98),
            border: Border.all(color: text.withValues(alpha: isDark ? 0.16 : 0.2), width: 0.6),
          ),
          underlays: <Widget>[
            CustomPaint(
              painter: _LedgerMarginPainter(
                rule: text.withValues(alpha: isDark ? 0.16 : 0.2),
                holeRing: text.withValues(alpha: isDark ? 0.3 : 0.36),
              ),
            ),
          ],
          overlays: <Widget>[
            CustomPaint(painter: _LedgerFoldPainter(text.withValues(alpha: isDark ? 0.22 : 0.26))),
          ],
        ),
      QuickMenuDesigns.console => _FrameSpec(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: bg.withValues(alpha: 0.97),
            border: Border.all(color: text.withValues(alpha: isDark ? 0.20 : 0.24), width: 0.8),
          ),
          underlays: <Widget>[
            CustomPaint(painter: _ConsoleBrushedPainter(isDark: isDark)),
          ],
          overlays: <Widget>[
            CustomPaint(painter: _ConsoleRivetPainter(text.withValues(alpha: isDark ? 0.50 : 0.40))),
          ],
        ),
      QuickMenuDesigns.foundry => _FrameSpec(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: bg.withValues(alpha: 0.98),
            border: Border.all(color: text.withValues(alpha: isDark ? 0.24 : 0.30), width: 0.8),
          ),
          underlays: <Widget>[
            CustomPaint(painter: _FoundryGrainPainter(text.withValues(alpha: isDark ? 0.035 : 0.025))),
          ],
          overlays: <Widget>[
            CustomPaint(painter: _FoundryCornerMarkPainter(accent.withValues(alpha: 0.75))),
          ],
        ),
      QuickMenuDesigns.anime => _FrameSpec(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: bg.withValues(alpha: 0.97),
            border: Border.all(color: accent.withValues(alpha: isDark ? 0.30 : 0.22), width: 0.8),
          ),
          underlays: <Widget>[
            CustomPaint(painter: _SparkleDustPainter(accent.withValues(alpha: isDark ? 0.16 : 0.14))),
          ],
          overlays: <Widget>[
            CustomPaint(painter: _RibbonCornerPainter(accent)),
          ],
        ),
    };

    final bool hasBevel = spec.bevel != null;
    Widget frame = Container(
      width: hasBevel ? null : width,
      constraints: hasBevel ? null : constraints,
      decoration: spec.decoration,
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.passthrough,
          children: <Widget>[
            for (final Widget underlay in spec.underlays) Positioned.fill(child: IgnorePointer(child: underlay)),
            child,
            for (final Widget overlay in spec.overlays) Positioned.fill(child: IgnorePointer(child: overlay)),
          ],
        ),
      ),
    );

    if (hasBevel) {
      // The classic skin emboss: a 1px frame that runs light on the top-left
      // and dark on the bottom-right (Player design).
      frame = Container(
        width: width,
        constraints: constraints,
        padding: const EdgeInsets.all(1),
        decoration: BoxDecoration(gradient: spec.bevel, borderRadius: radius),
        child: frame,
      );
    }
    return frame;
  }

  static List<Widget> _auroraBlobs(Color accent, double intensity) {
    final HSLColor accentHsl = HSLColor.fromColor(accent);
    final Color auroraB = accentHsl
        .withHue((accentHsl.hue + 58) % 360)
        .withSaturation((accentHsl.saturation * 0.92).clamp(0.0, 1.0))
        .toColor();
    return <Widget>[
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-0.95, -1.1),
            radius: 1.25,
            colors: <Color>[
              accent.withValues(alpha: (0.10 + intensity * 0.26).clamp(0.0, 1.0)),
              accent.withValues(alpha: 0.0),
            ],
          ),
        ),
      ),
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(1.15, 1.2),
            radius: 1.35,
            colors: <Color>[
              auroraB.withValues(alpha: (0.08 + intensity * 0.22).clamp(0.0, 1.0)),
              auroraB.withValues(alpha: 0.0),
            ],
          ),
        ),
      ),
    ];
  }
}

class _FrameSpec {
  const _FrameSpec({
    required this.decoration,
    this.bevel,
    this.underlays = const <Widget>[],
    this.overlays = const <Widget>[],
  });

  final BoxDecoration decoration;

  /// When set, the frame is wrapped in a 1px gradient emboss (Player design).
  final Gradient? bevel;
  final List<Widget> underlays;
  final List<Widget> overlays;
}

/// Faint square grid, same as the Matrix design's background.
class _GridPainter extends CustomPainter {
  const _GridPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 0.5;
    const double step = 20;
    for (double i = 0; i < size.width; i += step) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += step) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => oldDelegate.color != color;
}

/// Horizontal brushed-metal hairlines, same as the Player design's body.
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

/// Sparse editorial rules used by the Manifesto panel and its popups.
class _ManifestoRulePainter extends CustomPainter {
  const _ManifestoRulePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 0.5;
    for (double y = 18; y < size.height; y += 18) {
      canvas.drawLine(Offset.zero.translate(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ManifestoRulePainter oldDelegate) => oldDelegate.color != color;
}

/// Soft CRT scanlines, same as the Vector design's background texture.
class _VectorScanPainter extends CustomPainter {
  const _VectorScanPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 0.5;
    for (double y = 1.5; y < size.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _VectorScanPainter oldDelegate) => oldDelegate.color != color;
}

/// Faint diagonal brushed-metal strokes, fixed-seed so they don't jitter
/// on rebuild. Cheap stand-in for the full widget's texture layer.
class _ConsoleBrushedPainter extends CustomPainter {
  _ConsoleBrushedPainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(7);
    final Color strokeColor = isDark ? Colors.white : Colors.black;
    final Paint paint = Paint()..strokeWidth = 1;
    final double diag = size.width + size.height;
    final int lineCount = (diag / 5).floor();

    for (int i = 0; i < lineCount; i++) {
      final double offset = i * 5.0 + rnd.nextDouble() * 2;
      paint.color = strokeColor.withValues(alpha: 0.012 + rnd.nextDouble() * 0.02);
      canvas.drawLine(Offset(offset - size.height, 0), Offset(offset, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ConsoleBrushedPainter oldDelegate) => oldDelegate.isDark != isDark;
}

/// Four Phillips-head rivets pinning the corners of the frame, inset just
/// inside the border — the modal-preview version of the full widget's
/// `_Rivet` widgets, collapsed into one painter since there's no need for
/// separate widget/gesture handling here.
class _ConsoleRivetPainter extends CustomPainter {
  _ConsoleRivetPainter(this.color);

  final Color color;
  static const double _inset = 8;
  static const double _radius = 2.6;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint fill = Paint()..color = color;
    final Paint slot = Paint()
      ..color = Colors.black.withValues(alpha: 0.5)
      ..strokeWidth = 0.8;

    final List<Offset> corners = <Offset>[
      const Offset(_inset, _inset),
      Offset(size.width - _inset, _inset),
      Offset(_inset, size.height - _inset),
      Offset(size.width - _inset, size.height - _inset),
    ];

    for (final Offset c in corners) {
      canvas.drawCircle(c, _radius, fill);
      canvas.drawLine(Offset(c.dx - _radius + 0.6, c.dy), Offset(c.dx + _radius - 0.6, c.dy), slot);
    }
  }

  @override
  bool shouldRepaint(covariant _ConsoleRivetPainter oldDelegate) => oldDelegate.color != color;
}

/// Binder margin for the modal frame: a hairline rule down the left edge
/// with a short run of hollow punch-holes near the top. Same motif as the
/// QuickMenu panel, scaled to whatever size the modal ends up being.
class _LedgerMarginPainter extends CustomPainter {
  const _LedgerMarginPainter({required this.rule, required this.holeRing});

  final Color rule;
  final Color holeRing;

  static const double _marginX = 18;
  static const double _holeR = 2.3;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint rulePaint = Paint()
      ..color = rule
      ..strokeWidth = 0.6;
    canvas.drawLine(const Offset(_marginX, 8), Offset(_marginX, size.height - 8), rulePaint);

    final Paint ring = Paint()
      ..color = holeRing
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    const double holeX = _marginX / 2;
    double y = 16;
    while (y < size.height - 12) {
      canvas.drawCircle(Offset(holeX, y), _holeR, ring);
      y += 26;
    }
  }

  @override
  bool shouldRepaint(covariant _LedgerMarginPainter oldDelegate) =>
      oldDelegate.rule != rule || oldDelegate.holeRing != holeRing;
}

/// Folded page-corner, top right — two thin strokes standing in for a
/// dog-eared corner, kept as an overlay so it always sits above content.
class _LedgerFoldPainter extends CustomPainter {
  const _LedgerFoldPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint stroke = Paint()
      ..color = color
      ..strokeWidth = 0.6
      ..style = PaintingStyle.stroke;
    final Path fold = Path()
      ..moveTo(size.width - 14, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, 14)
      ..moveTo(size.width - 9, 0)
      ..lineTo(size.width, 9);
    canvas.drawPath(fold, stroke);
  }

  @override
  bool shouldRepaint(covariant _LedgerFoldPainter oldDelegate) => oldDelegate.color != color;
}

/// Corner reticle brackets used by the Vector design's panel and popups.
class _VectorBracketPainter extends CustomPainter {
  const _VectorBracketPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    const double inset = 3;
    const double len = 9;
    final double right = size.width - inset;
    final double bottom = size.height - inset;
    final Path corners = Path()
      ..moveTo(inset, inset + len)
      ..lineTo(inset, inset)
      ..lineTo(inset + len, inset)
      ..moveTo(right - len, inset)
      ..lineTo(right, inset)
      ..lineTo(right, inset + len)
      ..moveTo(right, bottom - len)
      ..lineTo(right, bottom)
      ..lineTo(right - len, bottom)
      ..moveTo(inset + len, bottom)
      ..lineTo(inset, bottom)
      ..lineTo(inset, bottom - len);
    canvas.drawPath(corners, paint);
  }

  @override
  bool shouldRepaint(covariant _VectorBracketPainter oldDelegate) => oldDelegate.color != color;
}

/// A scatter of tiny fixed sparkles across the modal — same low-key dust
/// texture language as the QuickMenu panel's sparkle field, but static
/// (no timer) since the modal frame paints once per build.
class _SparkleDustPainter extends CustomPainter {
  const _SparkleDustPainter(this.color);
  final Color color;

  // Fixed, seeded-looking positions — deterministic so repaints don't jitter.
  static const List<Offset> _spots = <Offset>[
    Offset(0.08, 0.12),
    Offset(0.22, 0.30),
    Offset(0.40, 0.08),
    Offset(0.62, 0.22),
    Offset(0.80, 0.14),
    Offset(0.90, 0.34),
    Offset(0.15, 0.55),
    Offset(0.35, 0.68),
    Offset(0.58, 0.60),
    Offset(0.75, 0.72),
    Offset(0.90, 0.85),
    Offset(0.10, 0.88),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()..color = color;
    for (int i = 0; i < _spots.length; i++) {
      final double cx = _spots[i].dx * size.width;
      final double cy = _spots[i].dy * size.height;
      final double r = i.isEven ? 2.2 : 1.4;
      final Path diamond = Path()
        ..moveTo(cx, cy - r)
        ..lineTo(cx + r * 0.45, cy)
        ..lineTo(cx, cy + r)
        ..lineTo(cx - r * 0.45, cy)
        ..close();
      canvas.drawPath(diamond, p);
    }
  }

  @override
  bool shouldRepaint(covariant _SparkleDustPainter oldDelegate) => oldDelegate.color != color;
}

/// A little bow tucked into the top-right corner, top right — two curved
/// ribbon tails and a knot. Same "corner accent" role the ledger design
/// gives its folded page-corner.
class _RibbonCornerPainter extends CustomPainter {
  const _RibbonCornerPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint fill = Paint()..color = color.withValues(alpha: 0.85);
    final double cx = size.width - 14;
    const double cy = 12;

    // Two ribbon-tail triangles fanning out from the knot.
    final Path leftTail = Path()
      ..moveTo(cx, cy)
      ..lineTo(cx - 9, cy - 5)
      ..lineTo(cx - 6, cy + 2)
      ..close();
    final Path rightTail = Path()
      ..moveTo(cx, cy)
      ..lineTo(cx + 9, cy - 5)
      ..lineTo(cx + 6, cy + 2)
      ..close();
    canvas.drawPath(leftTail, fill);
    canvas.drawPath(rightTail, fill);

    // Knot.
    canvas.drawCircle(Offset(cx, cy), 2.6, fill);
  }

  @override
  bool shouldRepaint(covariant _RibbonCornerPainter oldDelegate) => oldDelegate.color != color;
}

//---
class _FoundryGrainPainter extends CustomPainter {
  const _FoundryGrainPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 0.5;
    for (double y = 13; y < size.height; y += 13) {
      canvas.drawLine(Offset.zero.translate(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _FoundryGrainPainter oldDelegate) => oldDelegate.color != color;
}

class _FoundryCornerMarkPainter extends CustomPainter {
  const _FoundryCornerMarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    const double inset = 5;
    const double length = 8;
    canvas.drawLine(const Offset(inset, inset), const Offset(inset + length, inset), paint);
    canvas.drawLine(const Offset(inset, inset), const Offset(inset, inset + length), paint);
    canvas.drawLine(Offset(size.width - inset - length, inset), Offset(size.width - inset, inset), paint);
    canvas.drawLine(Offset(size.width - inset, inset), Offset(size.width - inset, inset + length), paint);
  }

  @override
  bool shouldRepaint(covariant _FoundryCornerMarkPainter oldDelegate) => oldDelegate.color != color;
}
