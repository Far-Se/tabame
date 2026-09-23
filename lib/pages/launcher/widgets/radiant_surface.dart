import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../../widgets/widgets/custom_border.dart';
import '../../../widgets/widgets/glass_surface.dart';
import '../launcher_corners.dart';
import '../launcher_design.dart';

/// One clock for the frame, selected row and glowing Tabame wordmark.
class RadiantMotion extends StatefulWidget {
  const RadiantMotion({super.key, required this.child});
  final Widget child;

  @override
  State<RadiantMotion> createState() => _RadiantMotionState();
}

class _RadiantMotionState extends State<RadiantMotion>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver, WindowListener {
  late final AnimationController _clock = AnimationController(vsync: this, duration: const Duration(seconds: 14));
  bool _allowed = false;
  bool _visible = true;
  bool _lifecycleVisible = true;
  int _visibilityRevision = 0;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    WidgetsBinding.instance.addObserver(this);
    _refreshVisibility();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _allowed = !MediaQuery.disableAnimationsOf(context) &&
        !MediaQuery.highContrastOf(context) &&
        TickerMode.valuesOf(context).enabled;
    _sync();
  }

  void _sync() {
    if (_allowed && _visible && _lifecycleVisible) {
      if (!_clock.isAnimating) _clock.repeat();
    } else {
      _clock.stop();
      if (!_allowed) _clock.value = 0;
    }
  }

  Future<void> _refreshVisibility() async {
    final int revision = ++_visibilityRevision;
    final bool visible = await windowManager.isVisible();
    final bool minimized = await windowManager.isMinimized();
    if (!mounted || revision != _visibilityRevision) return;
    _visible = visible && !minimized;
    _sync();
  }

  @override
  void onWindowFocus() {
    _visibilityRevision++;
    _visible = true;
    _sync();
  }

  @override
  void onWindowBlur() => _refreshVisibility();

  @override
  void onWindowMinimize() {
    _visibilityRevision++;
    _visible = false;
    _sync();
  }

  @override
  void onWindowRestore() => onWindowFocus();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleVisible = state == AppLifecycleState.resumed || state == AppLifecycleState.inactive;
    if (_lifecycleVisible) _refreshVisibility();
    _sync();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _RadiantClock(clock: _clock, child: widget.child);
}

class _RadiantClock extends InheritedWidget {
  const _RadiantClock({required this.clock, required super.child});
  final Animation<double> clock;

  @override
  bool updateShouldNotify(_RadiantClock oldWidget) => oldWidget.clock != clock;
}

enum RadiantSurfaceKind { frame, selection, symbols }

/// Paints light behind ordinary widgets, without capturing or blurring text.
class RadiantSurface extends StatefulWidget {
  const RadiantSurface({super.key, required this.child, this.kind = RadiantSurfaceKind.frame, this.radius = 22});
  final Widget child;
  final RadiantSurfaceKind kind;
  final double radius;

  @override
  State<RadiantSurface> createState() => _RadiantSurfaceState();
}

class _RadiantSurfaceState extends State<RadiantSurface> {
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
          await (_program ??= ui.FragmentProgram.fromAsset('resources/shaders/radiant.frag'));
      if (mounted) setState(() => _shader = program.fragmentShader());
    } catch (error) {
      _program = null;
      debugPrint('Radiant shader unavailable; using static lighting: $error');
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Animation<double> clock =
        context.dependOnInheritedWidgetOfExactType<_RadiantClock>()?.clock ?? const AlwaysStoppedAnimation<double>(0);
    final CornerShapeBorder outline = LauncherCorners.shape(
      LauncherCorners.radius(BorderRadius.circular(widget.radius), Directionality.of(context)),
    );
    final double inset = widget.kind == RadiantSurfaceKind.frame ? 12 : 1.5;
    final Widget content = Padding(
      padding: widget.kind == RadiantSurfaceKind.frame ? const EdgeInsets.all(14) : EdgeInsets.zero,
      child: RepaintBoundary(child: widget.child),
    );
    return RepaintBoundary(
      child: CustomPaint(
        willChange: _shader != null && !MediaQuery.disableAnimationsOf(context),
        painter: _RadiantPainter(
          shader: _shader,
          clock: clock,
          kind: widget.kind,
          outline: outline,
          background: RadiantTokens.background,
          accent: RadiantTokens.accent,
          highContrast: MediaQuery.highContrastOf(context),
        ),
        // Clip content to the same inset outline as the shader, while leaving
        // the painter's outside halo free to radiate beyond that outline.
        child: widget.kind == RadiantSurfaceKind.symbols
            ? content
            : widget.kind == RadiantSurfaceKind.frame
                ? GlassClipPath(clipper: _RadiantContentClipper(outline, inset), child: content)
                : ClipPath(clipper: _RadiantContentClipper(outline, inset), child: content),
      ),
    );
  }
}

class _RadiantContentClipper extends CustomClipper<Path> {
  const _RadiantContentClipper(this.outline, this.inset);
  final CornerShapeBorder outline;
  final double inset;

  @override
  Path getClip(Size size) => outline.getOuterPath((Offset.zero & size).deflate(inset));

  @override
  bool shouldReclip(_RadiantContentClipper oldClipper) => outline != oldClipper.outline || inset != oldClipper.inset;
}

class _RadiantPainter extends CustomPainter {
  _RadiantPainter(
      {required this.shader,
      required this.clock,
      required this.kind,
      required this.outline,
      required this.background,
      required this.accent,
      required this.highContrast})
      : super(repaint: clock);
  final ui.FragmentShader? shader;
  final Animation<double> clock;
  final RadiantSurfaceKind kind;
  final CornerShapeBorder outline;
  final Color background;
  final Color accent;
  final bool highContrast;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final Rect bounds = Offset.zero & size;
    final ui.FragmentShader? effect = shader;
    if (effect == null || highContrast) {
      if (kind == RadiantSurfaceKind.symbols) {
        // Keep the same branding while loading and in high-contrast mode.
        final TextPainter wordmark = TextPainter(
          text: TextSpan(text: 'Tabame', style: RadiantTokens.font(size: 20, color: accent, spacing: 2)),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout(maxWidth: size.width);
        wordmark.paint(canvas, Offset((size.width - wordmark.width) / 2, (size.height - wordmark.height) / 2));
        wordmark.dispose();
        return;
      }
      final Path shape = outline.getOuterPath(bounds.deflate(kind == RadiantSurfaceKind.frame ? 12 : 1.5));
      canvas.drawPath(
          shape,
          Paint()
            ..color = kind == RadiantSurfaceKind.selection
                ? Color.alphaBlend(accent.withValues(alpha: 0.2), background)
                : background);
      canvas.drawPath(
          shape,
          Paint()
            ..color = accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = highContrast ? 2 : 1);
      return;
    }
    effect
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, clock.value * math.pi * 2)
      ..setFloat(3, outline.borderRadius.topLeft.x)
      ..setFloat(4, kind.index.toDouble());
    int slot = 5;
    for (final Color color in <Color>[background, accent]) {
      effect
        ..setFloat(slot++, color.r)
        ..setFloat(slot++, color.g)
        ..setFloat(slot++, color.b);
    }
    // CSS superellipse K shared by LauncherCorners: bevel=0, round=1,
    // squircle=2. Keep this after the RGB uniforms (float slot 11).
    effect.setFloat(11, outline.topLeft.value);
    canvas.drawRect(bounds, Paint()..shader = effect);
  }

  @override
  bool shouldRepaint(_RadiantPainter oldDelegate) =>
      shader != oldDelegate.shader ||
      clock != oldDelegate.clock ||
      kind != oldDelegate.kind ||
      outline != oldDelegate.outline ||
      background != oldDelegate.background ||
      accent != oldDelegate.accent ||
      highContrast != oldDelegate.highContrast;
}
