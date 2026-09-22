import 'dart:math' as math;
import 'package:flutter/material.dart';

/// CSS-like corner shape.
///
/// Equivalent CSS values:
///
/// square   = superellipse(+infinity)
/// squircle = superellipse(2)
/// round    = superellipse(1)
/// bevel    = superellipse(0)
/// scoop    = superellipse(-1)
/// notch    = superellipse(-infinity)
///
///
///

// FOR AI Agent:
// corner-shape: bevel
// Material(
//   color: Colors.blue,
//   shape: CornerShapeBorder.css(
//     borderRadius: BorderRadius.circular(24),
//     cornerShapes: [
//       CornerShape.bevel,
//     ],
//   ),
//   child: const SizedBox(
//     width: 250,
//     height: 100,
//   ),
// )
// corner-shape: notch superellipse(0.6)
// shape: CornerShapeBorder.css(
//   borderRadius: BorderRadius.circular(24),
//   cornerShapes: [
//     CornerShape.notch,
//     CornerShape.superellipse(0.6),
//   ],
// ),
// That expands like CSS to:
// TL = notch
// TR = superellipse(.6)
// BR = notch
// BL = superellipse(.6)
// corner-shape: superellipse(-1.2) square squircle
// shape: CornerShapeBorder.css(
//   borderRadius: BorderRadius.circular(24),
//   cornerShapes: [
//     CornerShape.superellipse(-1.2),
//     CornerShape.square,
//     CornerShape.squircle,
//   ],
// ),
// Your four-corner example
// CSS:
// corner-shape:
//   scoop
//   superellipse(-1.6)
//   superellipse(-2.2)
//   round;
// Flutter:
// shape: CornerShapeBorder.css(
//   borderRadius: BorderRadius.circular(30),
//   cornerShapes: [
//     CornerShape.scoop,
//     CornerShape.superellipse(-1.6),
//     CornerShape.superellipse(-2.2),
//     CornerShape.round,
//   ],
// ),
// And you can independently control the equivalent of border-radius:
// shape: CornerShapeBorder.css(
//   borderRadius: const BorderRadius.only(
//     topLeft: Radius.circular(40),
//     topRight: Radius.circular(28),
//     bottomRight: Radius.circular(50),
//     bottomLeft: Radius.circular(16),
//   ),
//   cornerShapes: [
//     CornerShape.scoop,
//     CornerShape.squircle,
//     CornerShape.bevel,
//     CornerShape.round,
//   ],
// ),
// The arbitrary superellipse(K) implementation above uses the CSS definition where the curve exponent is based on 2^K, so superellipse(-1.6) is meaningfully different from scoop, rather than just being a custom hand-drawn approximation. MDN Web Docs
// For Tabame-style UI, I'd probably use curveSegments: 16 normally; it's visually smooth at typical 10–40 px corner sizes while keeping the generated Path cheap.
class CornerShape {
  final double value;

  const CornerShape._(this.value);

  const CornerShape.superellipse(this.value);

  static const CornerShape square = CornerShape._(double.infinity);
  static const CornerShape squircle = CornerShape._(2.0);
  static const CornerShape round = CornerShape._(1.0);
  static const CornerShape bevel = CornerShape._(0.0);
  static const CornerShape scoop = CornerShape._(-1.0);
  static const CornerShape notch = CornerShape._(double.negativeInfinity);

  @override
  bool operator ==(Object other) => other is CornerShape && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// ShapeBorder implementing CSS-like `corner-shape`.
///
/// Supports different shapes for each individual corner.
///
/// Example:
///
/// ```dart
/// shape: CornerShapeBorder.css(
///   borderRadius: BorderRadius.circular(24),
///   cornerShapes: [
///     CornerShape.scoop,
///     CornerShape.superellipse(-1.6),
///     CornerShape.superellipse(-2.2),
///     CornerShape.round,
///   ],
/// )
/// ```
class CornerShapeBorder extends ShapeBorder {
  final BorderRadius borderRadius;

  final CornerShape topLeft;
  final CornerShape topRight;
  final CornerShape bottomRight;
  final CornerShape bottomLeft;

  final BorderSide side;

  /// Number of points used to approximate a superellipse.
  ///
  /// 16 is usually enough.
  /// 24-32 gives very smooth corners.
  final int curveSegments;

  const CornerShapeBorder({
    this.borderRadius = BorderRadius.zero,
    this.topLeft = CornerShape.round,
    this.topRight = CornerShape.round,
    this.bottomRight = CornerShape.round,
    this.bottomLeft = CornerShape.round,
    this.side = BorderSide.none,
    this.curveSegments = 24,
  });

  /// CSS-style shorthand constructor.
  ///
  /// 1 value:
  ///   A A A A
  ///
  /// 2 values:
  ///   A B A B
  ///
  /// 3 values:
  ///   A B C B
  ///
  /// 4 values:
  ///   A B C D
  ///
  /// Order:
  ///   top-left
  ///   top-right
  ///   bottom-right
  ///   bottom-left
  factory CornerShapeBorder.css({
    required BorderRadius borderRadius,
    required List<CornerShape> cornerShapes,
    BorderSide side = BorderSide.none,
    int curveSegments = 24,
  }) {
    if (cornerShapes.isEmpty || cornerShapes.length > 4) {
      throw ArgumentError(
        'cornerShapes must contain between 1 and 4 values.',
      );
    }

    late CornerShape tl;
    late CornerShape tr;
    late CornerShape br;
    late CornerShape bl;

    switch (cornerShapes.length) {
      case 1:
        tl = tr = br = bl = cornerShapes[0];

      case 2:
        tl = br = cornerShapes[0];
        tr = bl = cornerShapes[1];

      case 3:
        tl = cornerShapes[0];
        tr = bl = cornerShapes[1];
        br = cornerShapes[2];

      case 4:
        tl = cornerShapes[0];
        tr = cornerShapes[1];
        br = cornerShapes[2];
        bl = cornerShapes[3];
    }

    return CornerShapeBorder(
      borderRadius: borderRadius,
      topLeft: tl,
      topRight: tr,
      bottomRight: br,
      bottomLeft: bl,
      side: side,
      curveSegments: curveSegments,
    );
  }

  /// Equivalent of:
  ///
  /// corner-shape: bevel;
  factory CornerShapeBorder.all({
    required BorderRadius borderRadius,
    required CornerShape shape,
    BorderSide side = BorderSide.none,
    int curveSegments = 24,
  }) {
    return CornerShapeBorder(
      borderRadius: borderRadius,
      topLeft: shape,
      topRight: shape,
      bottomRight: shape,
      bottomLeft: shape,
      side: side,
      curveSegments: curveSegments,
    );
  }

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  Path getOuterPath(
    Rect rect, {
    TextDirection? textDirection,
  }) {
    final RRect rrect = borderRadius.toRRect(rect).scaleRadii();

    final Path path = Path();

    // ---------------------------------------------------------
    // Start: top-left corner, after the corner radius
    // ---------------------------------------------------------

    path.moveTo(
      rect.left + rrect.tlRadiusX,
      rect.top,
    );

    // ---------------------------------------------------------
    // TOP
    // ---------------------------------------------------------

    path.lineTo(
      rect.right - rrect.trRadiusX,
      rect.top,
    );

    _topRight(
      path,
      rect,
      rrect.trRadiusX,
      rrect.trRadiusY,
      topRight,
    );

    // ---------------------------------------------------------
    // RIGHT
    // ---------------------------------------------------------

    path.lineTo(
      rect.right,
      rect.bottom - rrect.brRadiusY,
    );

    _bottomRight(
      path,
      rect,
      rrect.brRadiusX,
      rrect.brRadiusY,
      bottomRight,
    );

    // ---------------------------------------------------------
    // BOTTOM
    // ---------------------------------------------------------

    path.lineTo(
      rect.left + rrect.blRadiusX,
      rect.bottom,
    );

    _bottomLeft(
      path,
      rect,
      rrect.blRadiusX,
      rrect.blRadiusY,
      bottomLeft,
    );

    // ---------------------------------------------------------
    // LEFT
    // ---------------------------------------------------------

    path.lineTo(
      rect.left,
      rect.top + rrect.tlRadiusY,
    );

    _topLeft(
      path,
      rect,
      rrect.tlRadiusX,
      rrect.tlRadiusY,
      topLeft,
    );

    path.close();

    return path;
  }

  // ---------------------------------------------------------------------------
  // Corners
  // ---------------------------------------------------------------------------

  void _topRight(
    Path path,
    Rect rect,
    double rx,
    double ry,
    CornerShape shape,
  ) {
    if (rx <= 0 || ry <= 0) {
      path.lineTo(rect.right, rect.top);
      return;
    }

    // square
    if (shape.value == double.infinity) {
      path.lineTo(rect.right, rect.top);
      path.lineTo(rect.right, rect.top + ry);
      return;
    }

    // notch
    if (shape.value == double.negativeInfinity) {
      path.lineTo(
        rect.right - rx,
        rect.top + ry,
      );

      path.lineTo(
        rect.right,
        rect.top + ry,
      );

      return;
    }

    final double cx = rect.right - rx;
    final double cy = rect.top + ry;

    _superellipse(
      shape.value,
      (double u, double v) {
        path.lineTo(
          cx + rx * u,
          cy - ry * v,
        );
      },
    );
  }

  void _bottomRight(
    Path path,
    Rect rect,
    double rx,
    double ry,
    CornerShape shape,
  ) {
    if (rx <= 0 || ry <= 0) {
      path.lineTo(rect.right, rect.bottom);
      return;
    }

    if (shape.value == double.infinity) {
      path.lineTo(rect.right, rect.bottom);
      path.lineTo(rect.right - rx, rect.bottom);
      return;
    }

    if (shape.value == double.negativeInfinity) {
      path.lineTo(
        rect.right - rx,
        rect.bottom - ry,
      );

      path.lineTo(
        rect.right - rx,
        rect.bottom,
      );

      return;
    }

    final double cx = rect.right - rx;
    final double cy = rect.bottom - ry;

    _superellipse(
      shape.value,
      (double u, double v) {
        path.lineTo(
          cx + rx * v,
          cy + ry * u,
        );
      },
    );
  }

  void _bottomLeft(
    Path path,
    Rect rect,
    double rx,
    double ry,
    CornerShape shape,
  ) {
    if (rx <= 0 || ry <= 0) {
      path.lineTo(rect.left, rect.bottom);
      return;
    }

    if (shape.value == double.infinity) {
      path.lineTo(rect.left, rect.bottom);
      path.lineTo(rect.left, rect.bottom - ry);
      return;
    }

    if (shape.value == double.negativeInfinity) {
      path.lineTo(
        rect.left + rx,
        rect.bottom - ry,
      );

      path.lineTo(
        rect.left,
        rect.bottom - ry,
      );

      return;
    }

    final double cx = rect.left + rx;
    final double cy = rect.bottom - ry;

    _superellipse(
      shape.value,
      (double u, double v) {
        path.lineTo(
          cx - rx * u,
          cy + ry * v,
        );
      },
    );
  }

  void _topLeft(
    Path path,
    Rect rect,
    double rx,
    double ry,
    CornerShape shape,
  ) {
    if (rx <= 0 || ry <= 0) {
      path.lineTo(rect.left, rect.top);
      return;
    }

    if (shape.value == double.infinity) {
      path.lineTo(rect.left, rect.top);
      path.lineTo(rect.left + rx, rect.top);
      return;
    }

    if (shape.value == double.negativeInfinity) {
      path.lineTo(
        rect.left + rx,
        rect.top + ry,
      );

      path.lineTo(
        rect.left + rx,
        rect.top,
      );

      return;
    }

    final double cx = rect.left + rx;
    final double cy = rect.top + ry;

    _superellipse(
      shape.value,
      (double u, double v) {
        path.lineTo(
          cx - rx * v,
          cy - ry * u,
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Superellipse
  // ---------------------------------------------------------------------------

  void _superellipse(
    double k,
    void Function(double u, double v) addPoint,
  ) {
    //
    // CSS uses:
    //
    //     x^(2^K) + y^(2^K) = 1
    //
    // A convenient parametric form is:
    //
    //     x = sin(t) ^ (2 / 2^K)
    //     y = cos(t) ^ (2 / 2^K)
    //
    // therefore:
    //
    //     exponent = 2^(1 - K)
    //

    final double exponent = math
        .pow(
          2.0,
          1.0 - k,
        )
        .toDouble();

    for (int i = 1; i <= curveSegments; i++) {
      final double t = (i / curveSegments) * math.pi / 2;

      final double sinT = math.sin(t);
      final double cosT = math.cos(t);

      final double u = math.pow(sinT, exponent).toDouble();
      final double v = math.pow(cosT, exponent).toDouble();

      addPoint(u, v);
    }
  }

  // ---------------------------------------------------------------------------
  // Inner path / border
  // ---------------------------------------------------------------------------

  @override
  Path getInnerPath(
    Rect rect, {
    TextDirection? textDirection,
  }) {
    if (side == BorderSide.none || side.width <= 0) {
      return getOuterPath(
        rect,
        textDirection: textDirection,
      );
    }

    final double inset = side.width;

    final Rect innerRect = rect.deflate(inset);

    if (innerRect.width <= 0 || innerRect.height <= 0) {
      return Path();
    }

    final BorderRadius innerRadius = _deflateRadius(
      borderRadius,
      inset,
    );

    return CornerShapeBorder(
      borderRadius: innerRadius,
      topLeft: topLeft,
      topRight: topRight,
      bottomRight: bottomRight,
      bottomLeft: bottomLeft,
      curveSegments: curveSegments,
    ).getOuterPath(innerRect);
  }

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    TextDirection? textDirection,
  }) {
    if (side == BorderSide.none || side.style == BorderStyle.none || side.width <= 0) {
      return;
    }

    // Paint inside the outline so Material clipping keeps the full border.
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        getOuterPath(rect, textDirection: textDirection),
        getInnerPath(rect, textDirection: textDirection),
      ),
      Paint()..color = side.color,
    );
  }

  bool _sameCorners(CornerShapeBorder other) =>
      topLeft == other.topLeft &&
      topRight == other.topRight &&
      bottomRight == other.bottomRight &&
      bottomLeft == other.bottomLeft;

  CornerShapeBorder _lerp(CornerShapeBorder other, double t) => CornerShapeBorder(
        borderRadius: BorderRadius.lerp(borderRadius, other.borderRadius, t)!,
        topLeft: topLeft,
        topRight: topRight,
        bottomRight: bottomRight,
        bottomLeft: bottomLeft,
        side: BorderSide.lerp(side, other.side, t),
        curveSegments: t < 0.5 ? curveSegments : other.curveSegments,
      );

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) =>
      a is CornerShapeBorder && _sameCorners(a) ? a._lerp(this, t) : super.lerpFrom(a, t);

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) =>
      b is CornerShapeBorder && _sameCorners(b) ? _lerp(b, t) : super.lerpTo(b, t);

  @override
  bool operator ==(Object other) =>
      other is CornerShapeBorder &&
      borderRadius == other.borderRadius &&
      _sameCorners(other) &&
      side == other.side &&
      curveSegments == other.curveSegments;

  @override
  int get hashCode => Object.hash(borderRadius, topLeft, topRight, bottomRight, bottomLeft, side, curveSegments);

  @override
  ShapeBorder scale(double t) {
    return CornerShapeBorder(
      borderRadius: _scaleRadius(borderRadius, t),
      topLeft: topLeft,
      topRight: topRight,
      bottomRight: bottomRight,
      bottomLeft: bottomLeft,
      side: side.scale(t),
      curveSegments: curveSegments,
    );
  }

  static BorderRadius _deflateRadius(
    BorderRadius radius,
    double amount,
  ) {
    Radius shrink(Radius r) {
      return Radius.elliptical(
        math.max(0.0, r.x - amount),
        math.max(0.0, r.y - amount),
      );
    }

    return BorderRadius.only(
      topLeft: shrink(radius.topLeft),
      topRight: shrink(radius.topRight),
      bottomRight: shrink(radius.bottomRight),
      bottomLeft: shrink(radius.bottomLeft),
    );
  }

  static BorderRadius _scaleRadius(
    BorderRadius radius,
    double scale,
  ) {
    Radius resize(Radius r) {
      return Radius.elliptical(
        r.x * scale,
        r.y * scale,
      );
    }

    return BorderRadius.only(
      topLeft: resize(radius.topLeft),
      topRight: resize(radius.topRight),
      bottomRight: resize(radius.bottomRight),
      bottomLeft: resize(radius.bottomLeft),
    );
  }
}
