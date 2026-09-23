import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../models/globals.dart';
import '../../models/glass_effect.dart';
import '../../models/settings.dart';
import '../../platform/glass_effect_service.dart';

/// Marks actual painted surfaces, excluding window padding, shadows and gaps.
/// The path is shared with Flutter's clip, including disconnected Matrix panels.
class GlassSurface extends SingleChildRenderObjectWidget {
  const GlassSurface({super.key, this.shape, this.clipper, required super.child});

  final ShapeBorder? shape;
  final CustomClipper<Path>? clipper;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderGlassSurface(
        shape: shape,
        clipper: clipper,
        direction: Directionality.of(context),
        pixelRatio: MediaQuery.devicePixelRatioOf(context),
      );

  @override
  void updateRenderObject(BuildContext context, covariant RenderGlassSurface renderObject) {
    renderObject
      ..shape = shape
      ..clipper = clipper
      ..direction = Directionality.of(context)
      ..pixelRatio = MediaQuery.devicePixelRatioOf(context)
      ..markNeedsPaint();
  }
}

class GlassClipRRect extends StatelessWidget {
  const GlassClipRRect({super.key, required this.borderRadius, required this.child});

  final BorderRadius borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) => GlassSurface(
        shape: RoundedRectangleBorder(borderRadius: borderRadius),
        child: ClipRRect(borderRadius: borderRadius, child: child),
      );
}

class GlassClipPath extends StatelessWidget {
  const GlassClipPath({super.key, required this.clipper, required this.child});

  final CustomClipper<Path> clipper;
  final Widget child;

  @override
  Widget build(BuildContext context) => GlassSurface(
        clipper: clipper,
        child: ClipPath(clipper: clipper, child: child),
      );
}

class RenderGlassSurface extends RenderProxyBox {
  RenderGlassSurface(
      {required this.shape, required CustomClipper<Path>? clipper, required this.direction, required this.pixelRatio})
      : _clipper = clipper;

  ShapeBorder? shape;
  TextDirection direction;
  double pixelRatio;
  CustomClipper<Path>? _clipper;
  Map<String, Object>? _cachedRegion;
  Float64List? _cachedTransform;
  Size? _cachedSize;
  ShapeBorder? _cachedShape;
  TextDirection? _cachedDirection;
  double? _cachedPixelRatio;
  CustomClipper<Path>? get clipper => _clipper;
  set clipper(CustomClipper<Path>? value) {
    if (identical(value, _clipper)) return;
    if (attached) _clipper?.removeListener(_onClipChanged);
    _clipper = value;
    _cachedRegion = null;
    if (attached) _clipper?.addListener(_onClipChanged);
  }

  void _onClipChanged() {
    _cachedRegion = null;
    _scheduleUpdate();
  }

  static final Set<RenderGlassSurface> _surfaces = <RenderGlassSurface>{};
  static bool _updatePending = false;
  static bool _observingFrames = false;

  static void _scheduleUpdate() {
    if (_updatePending || !GlassEffectService.supported) return;
    _updatePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updatePending = false;
      final bool activePage = user.page == TPage.quickmenu &&
          !user.previewTheme &&
          (Globals.quickMenuPage == QuickMenuPage.quickMenu || Globals.quickMenuPage == QuickMenuPage.launcher);
      final GlassEffect effect = activePage ? user.glassEffect : GlassEffect.none;
      unawaited(GlassEffectService.update(
        effect: effect,
        options: user.activeGlassOptions,
        tint: Design.background.toARGB32(),
        regions: effect == GlassEffect.none
            ? <Map<String, Object>>[]
            : _surfaces
                .map((RenderGlassSurface surface) => surface._region())
                .whereType<Map<String, Object>>()
                .toList(),
      ));
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _surfaces.add(this);
    _clipper?.addListener(_onClipChanged);
    if (!_observingFrames) {
      _observingFrames = true;
      // Ancestor transforms/opacity can change without repainting a retained
      // child layer. Observe frames Flutter already renders; never run a ticker.
      WidgetsBinding.instance.addPersistentFrameCallback((_) {
        if (_surfaces.isNotEmpty) _scheduleUpdate();
      });
    }
    _scheduleUpdate();
  }

  @override
  void detach() {
    _clipper?.removeListener(_onClipChanged);
    _surfaces.remove(this);
    _scheduleUpdate();
    super.detach();
  }

  @override
  void performLayout() {
    super.performLayout();
    _scheduleUpdate();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    // Includes position-only changes and animated paths; no polling at idle.
    _scheduleUpdate();
  }

  Map<String, Object>? _region() {
    if (!attached || !hasSize || size.isEmpty) return null;
    RenderObject? ancestor = parent;
    RenderObject descendant = this;
    while (ancestor != null) {
      if (!ancestor.paintsChild(descendant)) return null;
      descendant = ancestor;
      ancestor = ancestor.parent;
    }
    final Float64List transform = getTransformTo(null).storage;
    if (_cachedRegion != null &&
        _cachedSize == size &&
        _cachedShape == shape &&
        _cachedDirection == direction &&
        _cachedPixelRatio == pixelRatio &&
        listEquals(_cachedTransform, transform)) return _cachedRegion;
    final Path localPath = clipper?.getClip(size) ??
        shape?.getOuterPath(Offset.zero & size, textDirection: direction) ??
        (Path()..addRect(Offset.zero & size));
    final Path path = localPath.transform(transform);
    final List<Int32List> contours = <Int32List>[];
    for (final ui.PathMetric metric in path.computeMetrics(forceClosed: true)) {
      if (metric.length <= 0 || !metric.length.isFinite) continue;
      // Subpixel sampling also captures custom bevel/squircle paths. Round once
      // here so the native region follows per-monitor DPI without filling gaps.
      final int samples = math.max(3, (metric.length * pixelRatio * 2).ceil()).clamp(3, 32768);
      final List<int> points = <int>[];
      for (int i = 0; i < samples; i++) {
        final Offset point = metric.getTangentForOffset(metric.length * i / samples)!.position;
        final int x = (point.dx * pixelRatio).round();
        final int y = (point.dy * pixelRatio).round();
        final int length = points.length;
        if (length >= 2 && points[length - 2] == x && points[length - 1] == y) continue;
        // Collapse straight edges so rectangular panels send a few vertices,
        // even on high-DPI monitors. Keep direction changes and curved corners.
        if (length >= 4) {
          final int dx = points[length - 2] - points[length - 4];
          final int dy = points[length - 1] - points[length - 3];
          final int nextDx = x - points[length - 2];
          final int nextDy = y - points[length - 1];
          if (dx * nextDy == dy * nextDx && dx * nextDx + dy * nextDy > 0) {
            points.removeRange(length - 2, length);
          }
        }
        points.addAll(<int>[x, y]);
      }
      if (points.length >= 6) contours.add(Int32List.fromList(points));
    }
    if (contours.isEmpty) return null;
    _cachedTransform = Float64List.fromList(transform);
    _cachedSize = size;
    _cachedShape = shape;
    _cachedDirection = direction;
    _cachedPixelRatio = pixelRatio;
    return _cachedRegion = <String, Object>{'contours': contours, 'evenOdd': path.fillType == PathFillType.evenOdd};
  }
}
