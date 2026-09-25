import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../launcher_corners.dart';
import '../launcher_design.dart';

/// A single matte shader behind the content. Light moves only after input and
/// settles in 360 ms; there is no ambient clock or texture capture.
class SatinSurface extends StatefulWidget {
  const SatinSurface({
    super.key,
    required this.child,
    this.radius = 14,
    this.background,
    this.foreground,
    this.accent,
    this.surfaceOpacity = 1,
    this.useLauncherCorners = true,
  });

  final Widget child;
  final double radius;
  final Color? background;
  final Color? foreground;
  final Color? accent;
  final double surfaceOpacity;
  final bool useLauncherCorners;

  @override
  State<SatinSurface> createState() => _SatinSurfaceState();
}

class _SatinSurfaceState extends State<SatinSurface>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver, WindowListener {
  static Future<ui.FragmentProgram>? _program;
  ui.FragmentShader? _shader;
  final ValueNotifier<Offset> _light = ValueNotifier<Offset>(Offset.zero);
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  )..addListener(_updateLight);
  Offset _from = Offset.zero;
  Offset _to = Offset.zero;
  bool _motion = false;
  bool _focused = true;
  bool _resumed = true;

  bool get _enabled => _motion && _focused && _resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);
    _load();
  }

  Future<void> _load() async {
    try {
      final ui.FragmentProgram program =
          await (_program ??= ui.FragmentProgram.fromAsset('resources/shaders/satin.frag'));
      if (mounted) setState(() => _shader = program.fragmentShader());
    } catch (error) {
      _program = null;
      debugPrint('Satin shader unavailable: $error');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion = !MediaQuery.disableAnimationsOf(context) &&
        !MediaQuery.highContrastOf(context) &&
        TickerMode.valuesOf(context).enabled;
    _sync();
  }

  void _sync() {
    if (!_enabled) {
      _settle.stop();
      _from = _to = Offset.zero;
      _light.value = Offset.zero;
    }
  }

  void _updateLight() {
    _light.value = Offset.lerp(_from, _to, Curves.easeOutCubic.transform(_settle.value))!;
  }

  void _aim(Offset target) {
    if (!_enabled || (target - _to).distanceSquared < 0.0001) return;
    _from = _light.value;
    _to = target;
    _settle.forward(from: 0);
  }

  void _hover(PointerEvent event) {
    if (!_enabled) return;
    final RenderObject? object = context.findRenderObject();
    if (object is! RenderBox || !object.hasSize || object.size.isEmpty) return;
    _aim(Offset(
      (event.localPosition.dx / object.size.width - 0.5).clamp(-0.5, 0.5),
      (event.localPosition.dy / object.size.height - 0.5).clamp(-0.5, 0.5),
    ));
  }

  @override
  void onWindowFocus() {
    _focused = true;
    _sync();
  }

  @override
  void onWindowBlur() {
    _focused = false;
    _sync();
  }

  @override
  void onWindowMinimize() => onWindowBlur();

  @override
  void onWindowRestore() => onWindowFocus();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _sync();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    _settle.dispose();
    _light.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget surface = CustomPaint(
      painter: _SatinPainter(
        shader: _shader,
        light: _light,
        background: widget.background ?? SatinTokens.background,
        foreground: widget.foreground ?? SatinTokens.foreground,
        accent: widget.accent ?? SatinTokens.accent,
        surfaceOpacity: widget.surfaceOpacity,
        highContrast: MediaQuery.highContrastOf(context),
      ),
      child: RepaintBoundary(child: widget.child),
    );
    return RepaintBoundary(
      child: MouseRegion(
        onHover: _hover,
        onExit: (_) => _aim(Offset.zero),
        child: widget.useLauncherCorners
            ? LauncherClip(borderRadius: BorderRadius.circular(widget.radius), child: surface)
            : ClipRRect(borderRadius: BorderRadius.circular(widget.radius), child: surface),
      ),
    );
  }
}

class _SatinPainter extends CustomPainter {
  _SatinPainter({
    required this.shader,
    required this.light,
    required this.background,
    required this.foreground,
    required this.accent,
    required this.surfaceOpacity,
    required this.highContrast,
  }) : super(repaint: light);

  final ui.FragmentShader? shader;
  final ValueNotifier<Offset> light;
  final Color background;
  final Color foreground;
  final Color accent;
  final double surfaceOpacity;
  final bool highContrast;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final Rect bounds = Offset.zero & size;
    final double paintOpacity = surfaceOpacity.clamp(0.0, 1.0).toDouble();
    final bool applyOpacity = paintOpacity < 1;
    if (applyOpacity) {
      canvas.saveLayer(bounds, Paint()..color = Colors.white.withValues(alpha: paintOpacity));
    }
    final ui.FragmentShader? effect = shader;
    if (highContrast) {
      canvas.drawRect(bounds, Paint()..color = background);
      if (applyOpacity) canvas.restore();
      return;
    }
    if (effect == null) {
      canvas.drawRect(
        bounds,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Color.alphaBlend(accent.withValues(alpha: 0.045), background),
              background,
              Color.alphaBlend(foreground.withValues(alpha: 0.025), background),
            ],
          ).createShader(bounds),
      );
      if (applyOpacity) canvas.restore();
      return;
    }
    // Float slots match satin.frag: size (2), light (2), three RGB colors (9).
    effect
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, light.value.dx)
      ..setFloat(3, light.value.dy);
    int slot = 4;
    for (final Color color in <Color>[background, foreground, accent]) {
      effect
        ..setFloat(slot++, color.r)
        ..setFloat(slot++, color.g)
        ..setFloat(slot++, color.b);
    }
    canvas.drawRect(bounds, Paint()..shader = effect);
    if (applyOpacity) canvas.restore();
  }

  @override
  bool shouldRepaint(_SatinPainter oldDelegate) =>
      shader != oldDelegate.shader ||
      light != oldDelegate.light ||
      background != oldDelegate.background ||
      foreground != oldDelegate.foreground ||
      accent != oldDelegate.accent ||
      surfaceOpacity != oldDelegate.surfaceOpacity ||
      highContrast != oldDelegate.highContrast;
}
