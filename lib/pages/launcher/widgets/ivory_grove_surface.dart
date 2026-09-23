import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Static, paint-only paper and foliage shared by the launcher and action cards.
/// The supplied content owns all layout, semantics, and input.
class IvoryGroveSurface extends StatelessWidget {
  const IvoryGroveSurface({super.key, required this.ink, required this.child});

  final Color ink;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.highContrastOf(context)) return child;
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: RepaintBoundary(child: CustomPaint(painter: _IvoryGrovePainter(ink))),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _IvoryGrovePainter extends CustomPainter {
  const _IvoryGrovePainter(this.ink);
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    // Fixed seed keeps the fine paper grain still across selection repaints.
    final math.Random random = math.Random(41);
    final Paint grain = Paint()..color = ink.withValues(alpha: 0.035);
    for (int i = 0; i < 650; i++) {
      canvas.drawCircle(Offset(random.nextDouble() * size.width, random.nextDouble() * size.height), 0.45, grain);
    }
    final double scale = (size.width / 760).clamp(0.55, 1.2).toDouble();
    _sprig(canvas, Offset(size.width + 8, size.height - 12), scale, -0.32);
    _sprig(canvas, Offset(size.width - 26, -38), scale * 0.72, 2.0);
    _sprig(canvas, Offset(size.width * 0.47, size.height + 42), scale * 0.88, -0.64);
    canvas.restore();
  }

  void _sprig(Canvas canvas, Offset origin, double scale, double rotation) {
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.rotate(rotation);
    canvas.scale(scale);
    final Paint stem = Paint()
      ..color = ink.withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;
    final Paint leaf = Paint()..color = ink.withValues(alpha: 0.07);
    canvas.drawPath(
        Path()
          ..moveTo(0, 0)
          ..cubicTo(-68, -65, -25, -175, -94, -285),
        stem);
    for (int i = 0; i < 9; i++) {
      final double t = (i + 1) / 10;
      final double u = 1 - t;
      final Offset joint = Offset(3 * u * u * t * -68 + 3 * u * t * t * -25 + t * t * t * -94,
          3 * u * u * t * -65 + 3 * u * t * t * -175 + t * t * t * -285);
      for (final double side in <double>[-1, 1]) {
        final Offset tip = joint + Offset(side * (37 - t * 12), -32 - t * 8);
        final Offset root = joint + const Offset(0, -2);
        final Offset mid = Offset.lerp(root, tip, 0.5)!;
        canvas.drawPath(
            Path()
              ..moveTo(root.dx, root.dy)
              ..quadraticBezierTo(mid.dx + side * 13, mid.dy + 8, tip.dx, tip.dy)
              ..quadraticBezierTo(mid.dx - side * 7, mid.dy - 12, root.dx, root.dy)
              ..close(),
            leaf);
        canvas.drawLine(root, tip, stem);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_IvoryGrovePainter oldDelegate) => oldDelegate.ink != ink;
}
