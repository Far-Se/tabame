import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/classes/saved_maps.dart';
import '../../models/settings.dart';
import '../../widgets/widgets/custom_border.dart';
import '../../widgets/widgets/glass_surface.dart';

/// Shared corner geometry from the active launcher theme.
abstract final class LauncherCorners {
  static List<CornerShape> get shapes => switch (user.launcherThemeColors.cornerShape) {
        ThemeCornerShape.round => const <CornerShape>[CornerShape.round],
        ThemeCornerShape.squircle => const <CornerShape>[CornerShape.squircle],
        ThemeCornerShape.bevel => const <CornerShape>[CornerShape.bevel],
      };
  static double? get radiusOverride => Design.borderRadius;

  static BorderRadius radius(BorderRadiusGeometry original, TextDirection direction) =>
      radiusOverride == null ? original.resolve(direction) : BorderRadius.circular(radiusOverride!);

  static CornerShapeBorder shape(BorderRadius radius, {BorderSide side = BorderSide.none}) => CornerShapeBorder.css(
        borderRadius: radius,
        cornerShapes: shapes,
        side: side,
        curveSegments: 16,
      );
}

/// Keeps design-specific fills, gradients, shadows, images, and edge colors.
/// ShapeDecoration also works in AnimatedContainer, so selection animations
/// don't need a separate surface implementation.
extension LauncherCornerDecoration on BoxDecoration {
  ShapeDecoration withLauncherCorners({TextDirection textDirection = TextDirection.ltr}) {
    if (shape == BoxShape.circle) return ShapeDecoration.fromBoxDecoration(this);
    final BorderRadius radius = LauncherCorners.radius(borderRadius ?? BorderRadius.zero, textDirection);
    final BoxBorder? edges = border;
    final ShapeBorder outline = edges == null || edges.isUniform
        ? LauncherCorners.shape(radius, side: edges?.top ?? BorderSide.none)
        : _LauncherEdgeBorder(radius, edges);
    return ShapeDecoration(color: color, gradient: gradient, image: image, shadows: boxShadow, shape: outline);
  }
}

/// Clips painted descendants and ink to the same corner policy as decorations.
class LauncherClip extends StatelessWidget {
  const LauncherClip({
    super.key,
    required this.borderRadius,
    required this.child,
    this.clipBehavior = Clip.antiAlias,
  });

  final BorderRadiusGeometry borderRadius;
  final Widget child;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) => Material(
        type: MaterialType.transparency,
        animationDuration: Duration.zero,
        shape: LauncherCorners.shape(LauncherCorners.radius(borderRadius, Directionality.of(context))),
        clipBehavior: clipBehavior,
        child: child,
      );
}

/// A frame owns one decoration and one matching Material clip. Designs supply
/// their existing BoxDecoration instead of repeating corner-shape plumbing.
class LauncherSurface extends StatelessWidget {
  const LauncherSurface({
    super.key,
    required this.decoration,
    required this.child,
    this.width,
    this.constraints,
    this.margin,
    this.padding,
    this.glass = true,
  });

  final BoxDecoration decoration;
  final Widget child;
  final double? width;
  final BoxConstraints? constraints;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final ShapeDecoration shaped = decoration.withLauncherCorners(textDirection: Directionality.of(context));
    final Widget surface = Container(
      width: width,
      constraints: constraints,
      // The Material paints the outline in front of its children. The outside
      // decoration paints only the fill and shadow, without clipping the shadow.
      decoration: ShapeDecoration(
        color: shaped.color == null ? null : Design.glassColor(shaped.color!),
        gradient: Design.glassEnabled ? shaped.gradient?.scale(Design.glassOpacity) : shaped.gradient,
        image: shaped.image,
        shadows: shaped.shadows,
        shape: LauncherCorners.shape(
            LauncherCorners.radius(decoration.borderRadius ?? BorderRadius.zero, Directionality.of(context))),
      ),
      child: Material(
        type: MaterialType.transparency,
        animationDuration: Duration.zero,
        shape: shaped.shape,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: (padding ?? EdgeInsets.zero).add(shaped.padding),
          child: child,
        ),
      ),
    );
    // Matrix supplies disconnected section paths inside its transparent frame.
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: glass ? GlassSurface(shape: shaped.shape, child: surface) : surface,
    );
  }
}

/// Retains directional / two-tone borders (for example Windows 98) when trying
/// a nonzero radius. Each edge paints its part of the same corner-shaped ring.
class _LauncherEdgeBorder extends ShapeBorder {
  const _LauncherEdgeBorder(this.radius, this.edges);

  final BorderRadius radius;
  final BoxBorder edges;

  @override
  EdgeInsetsGeometry get dimensions => edges.dimensions;

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => LauncherCorners.shape(radius).getOuterPath(rect);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    final EdgeInsets inset = dimensions.resolve(textDirection ?? TextDirection.ltr);
    final Rect inner = inset.deflateRect(rect);
    if (inner.isEmpty) return Path();
    Radius shrink(Radius corner, double horizontal, double vertical) =>
        Radius.elliptical(math.max(0, corner.x - horizontal), math.max(0, corner.y - vertical));
    return LauncherCorners.shape(BorderRadius.only(
      topLeft: shrink(radius.topLeft, inset.left, inset.top),
      topRight: shrink(radius.topRight, inset.right, inset.top),
      bottomLeft: shrink(radius.bottomLeft, inset.left, inset.bottom),
      bottomRight: shrink(radius.bottomRight, inset.right, inset.bottom),
    )).getOuterPath(inner);
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (rect.isEmpty) return;
    final bool rtl = textDirection == TextDirection.rtl;
    final BorderSide left;
    final BorderSide right;
    if (edges is Border) {
      left = (edges as Border).left;
      right = (edges as Border).right;
    } else {
      final BorderDirectional directional = edges as BorderDirectional;
      left = rtl ? directional.end : directional.start;
      right = rtl ? directional.start : directional.end;
    }
    final Path ring =
        Path.combine(PathOperation.difference, getOuterPath(rect), getInnerPath(rect, textDirection: textDirection));
    final List<Offset> corners = <Offset>[rect.topLeft, rect.topRight, rect.bottomRight, rect.bottomLeft];
    final List<BorderSide> sides = <BorderSide>[edges.top, right, edges.bottom, left];
    for (int i = 0; i < 4; i++) {
      final BorderSide side = sides[i];
      if (side.style == BorderStyle.none || side.width <= 0) continue;
      final Path wedge = Path()..addPolygon(<Offset>[rect.center, corners[i], corners[(i + 1) % 4]], true);
      canvas.save();
      canvas.clipPath(wedge, doAntiAlias: false);
      canvas.drawPath(ring, Paint()..color = side.color);
      canvas.restore();
    }
  }

  @override
  ShapeBorder scale(double t) => _LauncherEdgeBorder(radius * t, BoxBorder.lerp(null, edges, t)!);

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) => a is _LauncherEdgeBorder
      ? _LauncherEdgeBorder(BorderRadius.lerp(a.radius, radius, t)!, BoxBorder.lerp(a.edges, edges, t)!)
      : super.lerpFrom(a, t);

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) => b is _LauncherEdgeBorder
      ? _LauncherEdgeBorder(BorderRadius.lerp(radius, b.radius, t)!, BoxBorder.lerp(edges, b.edges, t)!)
      : super.lerpTo(b, t);

  @override
  bool operator ==(Object other) => other is _LauncherEdgeBorder && other.radius == radius && other.edges == edges;

  @override
  int get hashCode => Object.hash(radius, edges);
}
