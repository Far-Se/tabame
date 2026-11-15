import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../models/settings.dart';
import '../../models/util/theme_colors.dart';
import 'design_backdrop_stable.dart';

/// Hour in `[0, 24)`. Shared with [lampDaylight].
double lampHour(DateTime time) => time.hour + time.minute / 60.0;

/// 1 at 14:00, 0 at 02:00. The shader consumes this directly.
double lampDaylight(double hour) => 0.5 + 0.5 * math.cos((hour - 14.0) * (math.pi * 2.0 / 24.0));

/// Corner color. Dark recedes toward a warm black; daylight recedes toward a cool gray.
Color lampShadow(Color pool, {required bool dark}) {
  return Color.lerp(pool, dark ? const Color(0xFF0B0907) : const Color(0xFFD3D7DE), dark ? 0.84 : 0.70)!;
}

/// Shade-edge color. The accent only tints the lip, not the reading surface.
Color lampLip(Color pool, Color accent, {required bool dark}) {
  return Color.lerp(pool, accent, dark ? 0.62 : 0.40)!;
}

/// Painted field for the Lamp QuickMenu. The light is still unless the pointer
/// moves, and it follows the clock instead of looping.
class LampSurface extends StatefulWidget {
  const LampSurface({
    super.key,
    required this.child,
    required this.pool,
    required this.shadow,
    required this.lip,
    required this.dark,
    this.surfaceOpacity = 1,
    this.includeBackdrop = false,
  });

  final Widget child;
  final Color pool;
  final Color shadow;
  final Color lip;
  final bool dark;
  final double surfaceOpacity;
  final bool includeBackdrop;

  @override
  State<LampSurface> createState() => _LampSurfaceState();
}

class _LampSurfaceState extends State<LampSurface>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver, WindowListener {
  static Future<ui.FragmentProgram>? _program;
  ui.FragmentShader? _shader;
  final ValueNotifier<Offset> _light = ValueNotifier<Offset>(Offset.zero);
  final ValueNotifier<double> _day = ValueNotifier<double>(lampDaylight(lampHour(DateTime.now())));
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  )..addListener(_updateLight);
  Timer? _clock;
  Offset _from = Offset.zero;
  Offset _to = Offset.zero;
  bool _motion = false;
  bool _focused = true;
  bool _resumed = true;

  bool get _motionAllowed => _motion && _focused && _resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);
    _readClock();
    _clock = Timer.periodic(const Duration(minutes: 1), (Timer timer) => _readClock());
    _load();
  }

  Future<void> _load() async {
    try {
      final ui.FragmentProgram program =
          await (_program ??= ui.FragmentProgram.fromAsset('resources/shaders/lamp.frag'));
      final ui.FragmentShader shader = program.fragmentShader();
      if (!mounted) {
        shader.dispose();
        return;
      }
      setState(() => _shader = shader);
    } catch (error) {
      _program = null;
      debugPrint('Lamp shader unavailable: $error');
    }
  }

  void _readClock() {
    if (!mounted) return;
    _day.value = lampDaylight(lampHour(DateTime.now()));
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
    if (_motionAllowed) return;
    _settle.stop();
    _from = Offset.zero;
    _to = Offset.zero;
    _light.value = Offset.zero;
  }

  void _updateLight() {
    _light.value = Offset.lerp(_from, _to, Curves.easeOutCubic.transform(_settle.value))!;
  }

  void _aim(Offset target) {
    if (!_motionAllowed || (target - _to).distanceSquared < 0.0001) return;
    _from = _light.value;
    _to = target;
    _settle.forward(from: 0);
  }

  void _hover(PointerEvent event) {
    if (!_motionAllowed) return;
    final RenderObject? object = context.findRenderObject();
    if (object is! RenderBox || !object.hasSize || object.size.isEmpty) return;
    final double dx = (event.localPosition.dx / object.size.width - 0.5).clamp(-0.5, 0.5).toDouble();
    final double dy = (event.localPosition.dy / object.size.height - 0.5).clamp(-0.5, 0.5).toDouble();
    _aim(Offset(dx, dy));
  }

  @override
  void onWindowFocus() {
    _focused = true;
    _readClock();
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
    if (_resumed) _readClock();
    _sync();
  }

  @override
  void dispose() {
    _clock?.cancel();
    windowManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    _settle.dispose();
    _light.dispose();
    _day.dispose();
    _shader?.dispose();
    super.dispose();
  }

  bool _panelFades(List<double> points) {
    for (int i = 1; i < points.length; i += 2) {
      if (points[i] < 0.999) return true;
    }
    return false;
  }

  Shader _opacityShader(Rect bounds) {
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
  }

  @override
  Widget build(BuildContext context) {
    final bool highContrast = MediaQuery.highContrastOf(context);
    Widget field = CustomPaint(
      painter: _LampPainter(
        shader: _shader,
        light: _light,
        day: _day,
        pool: widget.pool,
        shadow: widget.shadow,
        lip: widget.lip,
        dark: widget.dark,
        surfaceOpacity: widget.surfaceOpacity,
        highContrast: highContrast,
      ),
      size: Size.infinite,
    );
    final List<double> points = Design.panelOpacityPoints;
    if (!highContrast && _panelFades(points) && points.length >= 4) {
      field = ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: _opacityShader,
        child: field,
      );
    }

    return MouseRegion(
      hitTestBehavior: HitTestBehavior.translucent,
      onHover: _hover,
      onExit: (_) => _aim(Offset.zero),
      child: Stack(
        children: <Widget>[
          if (widget.includeBackdrop) const StableBackdrop(),
          Positioned.fill(child: RepaintBoundary(child: field)),
          RepaintBoundary(child: widget.child),
        ],
      ),
    );
  }
}

class _LampPainter extends CustomPainter {
  _LampPainter({
    required this.shader,
    required this.light,
    required this.day,
    required this.pool,
    required this.shadow,
    required this.lip,
    required this.dark,
    required this.surfaceOpacity,
    required this.highContrast,
  }) : super(repaint: Listenable.merge(<Listenable>[light, day]));

  final ui.FragmentShader? shader;
  final ValueNotifier<Offset> light;
  final ValueNotifier<double> day;
  final Color pool;
  final Color shadow;
  final Color lip;
  final bool dark;
  final double surfaceOpacity;
  final bool highContrast;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final Rect bounds = Offset.zero & size;
    final double opacity = highContrast ? 1 : surfaceOpacity.clamp(0.0, 1.0).toDouble();
    final bool layer = opacity < 1;
    if (layer) {
      canvas.saveLayer(bounds, Paint()..color = Colors.white.withValues(alpha: opacity));
    }
    if (highContrast) {
      canvas.drawRect(bounds, Paint()..color = pool);
    } else if (shader == null) {
      _drawFallback(canvas, bounds);
    } else {
      _drawShader(canvas, bounds);
    }
    if (layer) canvas.restore();
  }

  void _drawFallback(Canvas canvas, Rect bounds) {
    final double dayValue = day.value.clamp(0.0, 1.0).toDouble();
    final Color center = Color.lerp(pool, lip, 0.08 * (1.0 - dayValue))!;
    final Gradient gradient = RadialGradient(
      center: Alignment(light.value.dx * 0.4, -0.12),
      radius: 0.85 + dayValue * 0.35,
      colors: <Color>[center, shadow],
      stops: const <double>[0.42, 1],
    );
    canvas.drawRect(bounds, Paint()..shader = gradient.createShader(bounds));
  }

  void _drawShader(Canvas canvas, Rect bounds) {
    final ui.FragmentShader effect = shader!;
    final Offset lean = light.value;
    effect
      ..setFloat(0, bounds.width)
      ..setFloat(1, bounds.height)
      ..setFloat(2, lean.dx)
      ..setFloat(3, lean.dy)
      ..setFloat(4, day.value)
      ..setFloat(5, dark ? 1 : 0);
    int slot = 6;
    for (final Color color in <Color>[pool, shadow, lip]) {
      effect
        ..setFloat(slot++, color.r)
        ..setFloat(slot++, color.g)
        ..setFloat(slot++, color.b);
    }
    canvas.drawRect(bounds, Paint()..shader = effect);
  }

  @override
  bool shouldRepaint(_LampPainter oldDelegate) {
    return shader != oldDelegate.shader ||
        light != oldDelegate.light ||
        day != oldDelegate.day ||
        pool != oldDelegate.pool ||
        shadow != oldDelegate.shadow ||
        lip != oldDelegate.lip ||
        dark != oldDelegate.dark ||
        surfaceOpacity != oldDelegate.surfaceOpacity ||
        highContrast != oldDelegate.highContrast;
  }
}
