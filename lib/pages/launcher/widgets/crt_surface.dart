import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:window_manager/window_manager.dart';

/// Captures live content on the GPU; hit testing remains on the widget tree.
class CrtSurface extends StatefulWidget {
  const CrtSurface({
    super.key,
    required this.child,
    this.shaderAsset = 'resources/shaders/crt.frag',
    this.pixelSize = 0,
    this.persistenceRate = 9,
    this.effectName = 'CRT',
    this.background,
    this.accent,
  });
  final Widget child;
  final String shaderAsset;
  final double pixelSize;
  final double persistenceRate;
  final String effectName;
  final Color? background;
  final Color? accent;

  @override
  State<CrtSurface> createState() => _CrtSurfaceState();
}

/// The stronger arcade pass used by the Retro launcher design.
class RetroSurface extends CrtSurface {
  const RetroSurface({
    super.key,
    required super.child,
    super.background,
    super.accent,
  }) : super(
          shaderAsset: 'resources/shaders/retro.frag',
          pixelSize: 0.32,
          persistenceRate: 11.7,
          effectName: 'Retro',
        );
}

class _CrtSurfaceState extends State<CrtSurface>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver, WindowListener {
  static final Map<String, Future<List<ui.FragmentProgram>>> _programs = <String, Future<List<ui.FragmentProgram>>>{};
  late final AnimationController _clock = AnimationController(vsync: this, duration: const Duration(hours: 1));
  ui.FragmentProgram? _screen;
  ui.FragmentProgram? _persistence;
  bool _focused = true;
  bool _resumed = true;
  bool _motion = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);
    _load();
  }

  Future<void> _load() async {
    try {
      final Future<List<ui.FragmentProgram>> loading = _programs.putIfAbsent(
        widget.shaderAsset,
        () => Future.wait(<Future<ui.FragmentProgram>>[
          ui.FragmentProgram.fromAsset(widget.shaderAsset),
          ui.FragmentProgram.fromAsset('resources/shaders/crt_persistence.frag'),
        ]),
      );
      final List<ui.FragmentProgram> programs = await loading;
      if (!mounted) return;
      setState(() {
        _screen = programs[0];
        _persistence = programs[1];
      });
      _sync();
    } catch (error) {
      _programs.remove(widget.shaderAsset);
      debugPrint('${widget.effectName} shaders unavailable; using static launcher: $error');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion = !MediaQuery.disableAnimationsOf(context) && TickerMode.valuesOf(context).enabled;
    _sync();
  }

  void _sync() {
    if (_motion && _focused && _resumed && _screen != null) {
      if (!_clock.isAnimating) _clock.repeat();
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
  Widget build(BuildContext context) => _screen == null
      ? widget.child
      : _CrtSampler(
          screen: _screen!,
          persistence: _persistence!,
          clock: _clock,
          motion: _motion,
          background: widget.background ?? Theme.of(context).colorScheme.surface,
          accent: widget.accent ?? Theme.of(context).colorScheme.primary,
          pixelSize: widget.pixelSize,
          persistenceRate: widget.persistenceRate,
          pixelRatio: MediaQuery.devicePixelRatioOf(context).clamp(1.0, 2.0),
          child: widget.child);
}

class _CrtSampler extends SingleChildRenderObjectWidget {
  const _CrtSampler(
      {required this.screen,
      required this.persistence,
      required this.clock,
      required this.motion,
      required this.pixelRatio,
      required this.background,
      required this.accent,
      required this.pixelSize,
      required this.persistenceRate,
      required super.child});
  final ui.FragmentProgram screen;
  final ui.FragmentProgram persistence;
  final Animation<double> clock;
  final bool motion;
  final double pixelRatio;
  final Color background;
  final Color accent;
  final double pixelSize;
  final double persistenceRate;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderCrt(screen, persistence, clock, motion, pixelRatio, background, accent, pixelSize, persistenceRate);
  @override
  void updateRenderObject(BuildContext context, covariant _RenderCrt renderObject) {
    renderObject.configure(motion, pixelRatio, background, accent, pixelSize, persistenceRate);
  }
}

class _RenderCrt extends RenderProxyBox {
  _RenderCrt(this.screen, this.persistence, this.clock, this.motion, this.pixelRatio, this.background, this.accent,
      this.pixelSize, this.persistenceRate);
  final ui.FragmentProgram screen;
  final ui.FragmentProgram persistence;
  final Animation<double> clock;
  bool motion;
  double pixelRatio;
  Color background;
  Color accent;
  double pixelSize;
  double persistenceRate;

  void configure(bool nextMotion, double nextRatio, Color nextBackground, Color nextAccent, double nextPixelSize,
      double nextPersistenceRate) {
    background = nextBackground;
    accent = nextAccent;
    motion = nextMotion;
    pixelRatio = nextRatio;
    pixelSize = nextPixelSize;
    persistenceRate = nextPersistenceRate;
    markNeedsCompositedLayerUpdate();
  }

  void _tick() {
    if (layer is _CrtLayer && (layer! as _CrtLayer).failed) return;
    markNeedsCompositedLayerUpdate();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    clock.addListener(_tick);
  }

  @override
  void detach() {
    clock.removeListener(_tick);
    super.detach();
  }

  @override
  bool get isRepaintBoundary => true;
  @override
  bool get alwaysNeedsCompositing => true;

  @override
  OffsetLayer updateCompositedLayer({covariant _CrtLayer? oldLayer}) {
    final _CrtLayer result = oldLayer ?? _CrtLayer(screen.fragmentShader(), persistence.fragmentShader());
    result.configure(size, pixelRatio, clock.value * 3600, motion, background, accent, pixelSize, persistenceRate);
    return result;
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (size.isEmpty || child == null || (layer is _CrtLayer && (layer! as _CrtLayer).failed)) {
      return super.hitTestChildren(result, position: position);
    }
    final Offset p = Offset(position.dx / size.width * 2 - 1, position.dy / size.height * 2 - 1);
    final double bulge = 1 + 0.018 * p.distanceSquared;
    final Offset mapped = Offset((p.dx * bulge + 1) * size.width / 2, (p.dy * bulge + 1) * size.height / 2);
    return result.addWithPaintOffset(
        offset: position - mapped,
        position: position,
        hitTest: (BoxHitTestResult result, Offset local) => child!.hitTest(result, position: local));
  }
}

/// Separate child scene avoids CPU readback and preserves composited children.
/// The persistence texture contains unwarped content, never the optical output.
class _CrtLayer extends OffsetLayer {
  _CrtLayer(this.screen, this.persistence);
  final ui.FragmentShader screen;
  final ui.FragmentShader persistence;
  ui.Image? _history;
  ui.Picture? _picture;
  Size _size = Size.zero;
  double _ratio = 1;
  double _time = 0;
  double? _lastTime;
  final Stopwatch _elapsed = Stopwatch()..start();
  bool _motion = false;
  bool failed = false;
  Color _background = Colors.black;
  Color _accent = Colors.white;
  double _pixelSize = 0;
  double _persistenceRate = 9;

  void configure(Size size, double ratio, double time, bool motion, Color background, Color accent, double pixelSize,
      double persistenceRate) {
    if (_size != size ||
        _ratio != ratio ||
        _motion != motion ||
        _background != background ||
        _accent != accent ||
        _pixelSize != pixelSize ||
        _persistenceRate != persistenceRate) {
      _history?.dispose();
      _history = null;
      _lastTime = null;
    }
    _background = background;
    _accent = accent;
    _size = size;
    _ratio = ratio;
    _time = time;
    _motion = motion;
    _pixelSize = pixelSize;
    _persistenceRate = persistenceRate;
    markNeedsAddToScene();
  }

  ui.Image _capture() {
    final ui.SceneBuilder builder = ui.SceneBuilder();
    builder.pushTransform(Matrix4.diagonal3Values(_ratio, _ratio, 1).storage);
    addChildrenToScene(builder);
    builder.pop();
    final ui.Scene scene = builder.build();
    try {
      return scene.toImageSync((_size.width * _ratio).ceil(), (_size.height * _ratio).ceil());
    } finally {
      scene.dispose();
    }
  }

  @override
  void addToScene(ui.SceneBuilder builder) {
    if (_size.isEmpty) return;
    if (failed) {
      super.addToScene(builder);
      return;
    }
    ui.Image? current;
    ui.Image? next;
    try {
      current = _capture();
      final double now = _elapsed.elapsedMicroseconds / 1000000;
      final double elapsed = _lastTime == null ? 1 : now - _lastTime!;
      // No stale trails after pause/resume, resize or reduced-motion changes.
      final double decay = _motion && elapsed >= 0 && elapsed < 0.5 ? math.exp(-elapsed * _persistenceRate) : 0;
      persistence
        ..setFloat(0, _size.width)
        ..setFloat(1, _size.height)
        ..setFloat(2, decay)
        ..setImageSampler(0, current)
        ..setImageSampler(1, _history ?? current);
      final ui.PictureRecorder accumulation = ui.PictureRecorder();
      final Canvas accumulationCanvas = Canvas(accumulation)..scale(_ratio);
      accumulationCanvas.drawRect(Offset.zero & _size, Paint()..shader = persistence);
      final ui.Picture accumulationPicture = accumulation.endRecording();
      try {
        next = accumulationPicture.toImageSync(current.width, current.height);
      } finally {
        accumulationPicture.dispose();
      }
      screen
        ..setFloat(0, _size.width)
        ..setFloat(1, _size.height)
        ..setFloat(2, _time)
        ..setFloat(3, _motion ? 1 : 0)
        ..setFloat(4, _background.r)
        ..setFloat(5, _background.g)
        ..setFloat(6, _background.b)
        ..setFloat(7, _accent.r)
        ..setFloat(8, _accent.g)
        ..setFloat(9, _accent.b)
        ..setImageSampler(0, next);
      if (_pixelSize > 0) screen.setFloat(10, _pixelSize);
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(Offset.zero & _size, Paint()..shader = screen);
      final ui.Picture picture = recorder.endRecording();
      _picture?.dispose();
      _picture = picture;
      builder.addPicture(offset, picture);
      _history?.dispose();
      _history = next;
      next = null;
      _lastTime = now;
    } catch (error) {
      failed = true;
      _history?.dispose();
      _history = null;
      debugPrint('CRT renderer unavailable; using static launcher: $error');
      super.addToScene(builder);
    } finally {
      current?.dispose();
      next?.dispose();
    }
  }

  @override
  void dispose() {
    _history?.dispose();
    _picture?.dispose();
    screen.dispose();
    persistence.dispose();
    super.dispose();
  }
}
