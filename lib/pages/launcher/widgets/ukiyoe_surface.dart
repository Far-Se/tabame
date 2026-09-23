import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../launcher_corners.dart';
import '../launcher_design.dart';

enum UkiyoeMaterial { paper, landscape, selection }

/// A still print: no tickers or content capture. Text remains ordinary Flutter
/// text, and shared launcher clipping handles round, squircle and bevel alike.
class UkiyoeSurface extends StatefulWidget {
  const UkiyoeSurface({super.key, required this.child, this.material = UkiyoeMaterial.paper, this.radius = 6});
  final Widget child;
  final UkiyoeMaterial material;
  final double radius;

  @override
  State<UkiyoeSurface> createState() => _UkiyoeSurfaceState();
}

class _UkiyoeSurfaceState extends State<UkiyoeSurface> {
  static Future<ui.FragmentProgram>? _program;
  ui.FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final ui.FragmentProgram program =
          await (_program ??= ui.FragmentProgram.fromAsset('resources/shaders/ukiyoe.frag'));
      if (mounted) setState(() => _shader = program.fragmentShader());
    } catch (error) {
      _program = null;
      debugPrint('Ukiyo-e shader unavailable; using flat print colors: $error');
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: LauncherClip(
          borderRadius: BorderRadius.circular(widget.radius),
          child: CustomPaint(
            painter: _UkiyoePainter(
              shader: _shader,
              material: widget.material,
              paper: UkiyoeTokens.background,
              ink: UkiyoeTokens.accent,
              vermilion: UkiyoeTokens.vermilion,
              highContrast: MediaQuery.highContrastOf(context),
            ),
            child: RepaintBoundary(child: widget.child),
          ),
        ),
      );
}

class _UkiyoePainter extends CustomPainter {
  const _UkiyoePainter(
      {required this.shader,
      required this.material,
      required this.paper,
      required this.ink,
      required this.vermilion,
      required this.highContrast});
  final ui.FragmentShader? shader;
  final UkiyoeMaterial material;
  final Color paper;
  final Color ink;
  final Color vermilion;
  final bool highContrast;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final Rect bounds = Offset.zero & size;
    final ui.FragmentShader? effect = shader;
    if (effect == null || highContrast) {
      canvas.drawRect(
          bounds,
          Paint()
            ..color =
                material == UkiyoeMaterial.selection ? Color.alphaBlend(ink.withValues(alpha: 0.18), paper) : paper);
      if (material == UkiyoeMaterial.landscape) _fallbackLandscape(canvas, size);
      return;
    }
    effect
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, material.index.toDouble());
    int slot = 3;
    for (final Color color in <Color>[paper, ink, vermilion]) {
      effect
        ..setFloat(slot++, color.r)
        ..setFloat(slot++, color.g)
        ..setFloat(slot++, color.b);
    }
    canvas.drawRect(bounds, Paint()..shader = effect);
  }

  void _fallbackLandscape(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    canvas.drawCircle(Offset(w * 0.88, h * 0.28), h * 0.15, Paint()..color = vermilion);
    canvas.drawPath(
        Path()
          ..moveTo(w * 0.60, h * 0.88)
          ..lineTo(w * 0.76, h * 0.23)
          ..lineTo(w * 0.92, h * 0.88)
          ..close(),
        Paint()..color = Color.alphaBlend(ink.withValues(alpha: 0.5), paper));
    final Path wave = Path()
      ..moveTo(0, h * 0.76)
      ..cubicTo(w * 0.2, h * 0.44, w * 0.33, h, w * 0.5, h * 0.7)
      ..cubicTo(w * 0.65, h * 0.46, w * 0.85, h, w, h * 0.7)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(wave, Paint()..color = ink);
  }

  @override
  bool shouldRepaint(_UkiyoePainter oldDelegate) =>
      shader != oldDelegate.shader ||
      material != oldDelegate.material ||
      paper != oldDelegate.paper ||
      ink != oldDelegate.ink ||
      vermilion != oldDelegate.vermilion ||
      highContrast != oldDelegate.highContrast;
}
