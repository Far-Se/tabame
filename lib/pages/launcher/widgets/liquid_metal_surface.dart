import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// One clock per launcher. Painters listen directly without rebuilding content.
class LiquidMetalMotion extends StatefulWidget {
  const LiquidMetalMotion({super.key, required this.child});
  final Widget child;

  @override
  State<LiquidMetalMotion> createState() => _LiquidMetalMotionState();
}

class _LiquidMetalMotionState extends State<LiquidMetalMotion>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver, WindowListener {
  late final AnimationController _clock = AnimationController(vsync: this, duration: const Duration(seconds: 120));
  bool _focused = true;
  bool _resumed = true;
  bool _motion = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion = !MediaQuery.disableAnimationsOf(context) && TickerMode.valuesOf(context).enabled;
    _sync();
  }

  void _sync() {
    if (_motion && _focused && _resumed) {
      if (!_clock.isAnimating) _clock.repeat(reverse: true);
    } else {
      _clock.stop();
    }
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
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _MetalClock(clock: _clock, child: widget.child);
}

class _MetalClock extends InheritedWidget {
  const _MetalClock({required this.clock, required super.child});
  final Animation<double> clock;

  @override
  bool updateShouldNotify(_MetalClock oldWidget) => clock != oldWidget.clock;
}

/// Actual fragment-shader metal, with an independent shader per paint surface.
/// [overlay] adds a restrained reflection to opaque plugin/preview controls.
class LiquidMetalSurface extends StatefulWidget {
  const LiquidMetalSurface({
    super.key,
    required this.child,
    this.selected = false,
    this.radius = 10,
    this.raised = true,
    this.overlay = false,
    this.optical = false,
  });
  final Widget child;
  final bool selected;
  final double radius;
  final bool raised;
  final bool overlay;
  final bool optical;

  @override
  State<LiquidMetalSurface> createState() => _LiquidMetalSurfaceState();
}

class _LiquidMetalSurfaceState extends State<LiquidMetalSurface> {
  static final Map<String, Future<ui.FragmentProgram>> _programs = <String, Future<ui.FragmentProgram>>{};
  ui.FragmentShader? _shader;
  int _loadGeneration = 0;
  final ValueNotifier<Offset?> _pointer = ValueNotifier<Offset?>(null);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final int generation = ++_loadGeneration;
    final String asset =
        widget.optical ? 'resources/shaders/optical_glass.frag' : 'resources/shaders/liquid_metal.frag';
    try {
      final ui.FragmentProgram program = await (_programs[asset] ??= ui.FragmentProgram.fromAsset(asset));
      if (mounted && generation == _loadGeneration) setState(() => _shader = program.fragmentShader());
    } catch (error) {
      // A failed load never takes the launcher down. New surfaces can retry.
      _programs.remove(asset);
      debugPrint('Launcher shader unavailable ($asset): $error');
    }
  }

  @override
  void didUpdateWidget(covariant LiquidMetalSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.optical != oldWidget.optical) {
      _shader?.dispose();
      _shader = null;
      _load();
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    _pointer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Animation<double> clock =
        context.dependOnInheritedWidgetOfExactType<_MetalClock>()?.clock ?? const AlwaysStoppedAnimation<double>(0);
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    final _LiquidMetalPainter painter = _LiquidMetalPainter(
      shader: _shader,
      clock: clock,
      pointer: _pointer,
      selected: widget.selected,
      mode: widget.overlay ? 2 : (widget.raised ? 1 : 0),
      reduceMotion: reduceMotion,
      optical: widget.optical,
      radius: widget.radius,
    );
    return MouseRegion(
      onHover: reduceMotion ? null : (PointerEvent event) => _pointer.value = event.localPosition,
      onExit: (PointerEvent event) => _pointer.value = null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.radius),
        child: CustomPaint(
          painter: widget.overlay ? null : painter,
          foregroundPainter: widget.overlay ? painter : null,
          child: RepaintBoundary(child: widget.child),
        ),
      ),
    );
  }
}

class _LiquidMetalPainter extends CustomPainter {
  _LiquidMetalPainter({
    required this.shader,
    required this.clock,
    required this.pointer,
    required this.selected,
    required this.mode,
    required this.reduceMotion,
    required this.optical,
    required this.radius,
  }) : super(repaint: Listenable.merge(<Listenable>[clock, pointer]));

  final ui.FragmentShader? shader;
  final Animation<double> clock;
  final ValueNotifier<Offset?> pointer;
  final bool selected;
  final double mode;
  final bool reduceMotion;
  final bool optical;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final Rect rect = Offset.zero & size;
    final ui.FragmentShader? effect = shader;
    if (effect == null) {
      if (mode == 2) return;
      canvas.drawRect(
          rect,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: optical
                  ? <Color>[
                      const Color(0xFFF2F4FA),
                      selected ? const Color(0xFFDCE5FA) : const Color(0xFFE5EAF2),
                      const Color(0xFFF4EEF4),
                    ]
                  : <Color>[
                      selected ? const Color(0xFF45443F) : const Color(0xFF292C30),
                      const Color(0xFF12151A),
                      const Color(0xFF303238),
                    ],
            ).createShader(rect));
      return;
    }
    final Offset cursor = reduceMotion ? size.center(Offset.zero) : pointer.value ?? size.center(Offset.zero);
    effect
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, reduceMotion ? 0 : clock.value * 120)
      ..setFloat(3, cursor.dx)
      ..setFloat(4, cursor.dy)
      ..setFloat(5, selected ? 1 : (!reduceMotion && pointer.value != null ? 0.45 : 0))
      ..setFloat(6, mode);
    if (optical) effect.setFloat(7, radius);
    canvas.drawRect(rect, Paint()..shader = effect);
  }

  @override
  bool shouldRepaint(_LiquidMetalPainter oldDelegate) =>
      shader != oldDelegate.shader ||
      selected != oldDelegate.selected ||
      mode != oldDelegate.mode ||
      optical != oldDelegate.optical ||
      radius != oldDelegate.radius ||
      reduceMotion != oldDelegate.reduceMotion;
}

/// Optical material uses the same clock and resource lifecycle as Liquid Metal.
class OpticalGlassSurface extends StatelessWidget {
  const OpticalGlassSurface(
      {super.key,
      required this.child,
      this.selected = false,
      this.radius = 14,
      this.raised = true,
      this.overlay = false});
  final Widget child;
  final bool selected;
  final double radius;
  final bool raised;
  final bool overlay;

  @override
  Widget build(BuildContext context) => LiquidMetalSurface(
        key: const ValueKey<String>('optical-glass'),
        optical: true,
        selected: selected,
        radius: radius,
        raised: raised,
        overlay: overlay,
        child: child,
      );
}
