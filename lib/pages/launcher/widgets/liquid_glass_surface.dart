import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../../models/classes/saved_maps.dart';
import '../../../models/settings.dart';
import '../launcher_corners.dart';
import '../launcher_design.dart';

/// One finite light response for the frame and its lenses. No idle ticker.
class LiquidGlassMotion extends StatefulWidget {
  const LiquidGlassMotion({super.key, required this.child});

  final Widget child;

  @override
  State<LiquidGlassMotion> createState() => _LiquidGlassMotionState();
}

class _LiquidGlassMotionState extends State<LiquidGlassMotion>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver, WindowListener {
  final ValueNotifier<Offset> _light = ValueNotifier<Offset>(Offset.zero);
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  )..addListener(_updateLight);
  Offset _from = Offset.zero;
  Offset _target = Offset.zero;
  bool _motion = false;
  bool _focused = true;
  bool _resumed = true;

  bool get _enabled => _motion && _focused && _resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);
    final AppLifecycleState? lifecycle = WidgetsBinding.instance.lifecycleState;
    _resumed = lifecycle == null || lifecycle == AppLifecycleState.resumed;
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
    if (_enabled) return;
    _settle.stop();
    _from = _target = Offset.zero;
    _light.value = Offset.zero;
  }

  void _updateLight() {
    _light.value = Offset.lerp(_from, _target, Curves.easeOutCubic.transform(_settle.value))!;
  }

  void _aim(Offset target) {
    if (!_enabled || (target - _target).distanceSquared < 0.0001) return;
    _from = _light.value;
    _target = target;
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
  void onWindowClose() => onWindowBlur();

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _LiquidGlassLight(
        light: _light,
        child: MouseRegion(
          opaque: false,
          onHover: _hover,
          onExit: (_) => _aim(Offset.zero),
          child: widget.child,
        ),
      );
}

class _LiquidGlassLight extends InheritedWidget {
  const _LiquidGlassLight({required this.light, required super.child});

  final ValueNotifier<Offset> light;

  @override
  bool updateShouldNotify(_LiquidGlassLight oldWidget) => light != oldWidget.light;
}

enum LiquidGlassKind { frame, search, selection }

/// Refraction of a procedural environment, plus a real Flutter backdrop blur
/// on inner lenses. Desktop glass remains the existing native compositor's job.
class LiquidGlassSurface extends StatefulWidget {
  const LiquidGlassSurface({
    super.key,
    required this.child,
    this.kind = LiquidGlassKind.frame,
    this.radius = 24,
    this.opacity = 1,
  });

  final Widget child;
  final LiquidGlassKind kind;
  final double radius;
  final double opacity;

  @override
  State<LiquidGlassSurface> createState() => _LiquidGlassSurfaceState();
}

class _LiquidGlassSurfaceState extends State<LiquidGlassSurface> {
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
          await (_program ??= ui.FragmentProgram.fromAsset('resources/shaders/liquid_glass.frag'));
      if (mounted) setState(() => _shader = program.fragmentShader());
    } catch (error) {
      _program = null;
      debugPrint('Liquid Glass shader unavailable: $error');
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool highContrast = MediaQuery.highContrastOf(context);
    final ValueNotifier<Offset>? light = context.dependOnInheritedWidgetOfExactType<_LiquidGlassLight>()?.light;
    final BorderRadius radius =
        LauncherCorners.radius(BorderRadius.circular(widget.radius), Directionality.of(context));
    Widget surface = CustomPaint(
      painter: _LiquidGlassPainter(
        shader: _shader,
        light: light,
        radius: radius.topLeft.x,
        corner: user.launcherThemeColors.cornerShape,
        kind: widget.kind,
        opacity: widget.opacity,
        background: LiquidGlassTokens.background,
        foreground: LiquidGlassTokens.foreground,
        accent: LiquidGlassTokens.accent,
        highContrast: highContrast,
      ),
      child: RepaintBoundary(child: widget.child),
    );
    // Only search and the selected row blur; unselected rows have no filter.
    if (!highContrast && widget.kind != LiquidGlassKind.frame) {
      surface = BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: surface,
      );
    }
    return RepaintBoundary(
      child: LauncherClip(borderRadius: radius, child: surface),
    );
  }
}

class _LiquidGlassPainter extends CustomPainter {
  _LiquidGlassPainter({
    required this.shader,
    required this.light,
    required this.radius,
    required this.corner,
    required this.kind,
    required this.opacity,
    required this.background,
    required this.foreground,
    required this.accent,
    required this.highContrast,
  }) : super(repaint: light);

  final ui.FragmentShader? shader;
  final ValueNotifier<Offset>? light;
  final double radius;
  final ThemeCornerShape corner;
  final LiquidGlassKind kind;
  final double opacity;
  final Color background;
  final Color foreground;
  final Color accent;
  final bool highContrast;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final Rect rect = Offset.zero & size;
    final bool selected = kind == LiquidGlassKind.selection;
    final Color fill = selected ? Color.alphaBlend(accent.withValues(alpha: 0.12), background) : background;
    if (highContrast) {
      canvas.drawRect(rect, Paint()..color = fill.withValues(alpha: 1));
      return;
    }

    final ui.FragmentShader? effect = shader;
    final double alpha = opacity.clamp(0.0, 1.0);
    if (effect == null) {
      final bool dark = ThemeData.estimateBrightnessForColor(background) == Brightness.dark;
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Color.alphaBlend(Colors.white.withValues(alpha: dark ? 0.09 : 0.55), fill).withValues(alpha: alpha),
              fill.withValues(alpha: alpha),
              Color.alphaBlend(accent.withValues(alpha: 0.07), fill).withValues(alpha: alpha),
            ],
            stops: const <double>[0, 0.45, 1],
          ).createShader(rect),
      );
      return;
    }

    final Offset aim = light?.value ?? Offset.zero;
    // liquid_glass.frag: 18 floats, no samplers. Geometry (0..7), RGB (8..16), brightness (17).
    effect
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, aim.dx)
      ..setFloat(3, aim.dy)
      ..setFloat(4, radius)
      ..setFloat(
          5,
          switch (corner) {
            ThemeCornerShape.round => 0,
            ThemeCornerShape.squircle => 1,
            ThemeCornerShape.bevel => 2,
          })
      ..setFloat(6, kind.index.toDouble())
      ..setFloat(7, alpha);
    int slot = 8;
    for (final Color color in <Color>[background, foreground, accent]) {
      effect
        ..setFloat(slot++, color.r)
        ..setFloat(slot++, color.g)
        ..setFloat(slot++, color.b);
    }
    effect.setFloat(17, ThemeData.estimateBrightnessForColor(background) == Brightness.dark ? 1 : 0);
    canvas.drawRect(rect, Paint()..shader = effect);
  }

  @override
  bool shouldRepaint(_LiquidGlassPainter oldDelegate) =>
      shader != oldDelegate.shader ||
      light != oldDelegate.light ||
      radius != oldDelegate.radius ||
      corner != oldDelegate.corner ||
      kind != oldDelegate.kind ||
      opacity != oldDelegate.opacity ||
      background != oldDelegate.background ||
      foreground != oldDelegate.foreground ||
      accent != oldDelegate.accent ||
      highContrast != oldDelegate.highContrast;
}
