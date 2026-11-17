import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:window_manager/window_manager.dart';

import '../launcher_design.dart';

/// A field of compass needles behind the results. The selected row is the
/// lodestone, and every needle turns to point at it. Moving the selection
/// swings the field once, then it stops. Nothing runs while the field is still.
class LodestoneSurface extends StatefulWidget {
  const LodestoneSurface({super.key, required this.child});

  /// Distance between needle pivots, in logical pixels.
  static const double pitch = 14;

  /// The pole sits on the selected row's icon, this far in from its left edge.
  static const double poleInset = 23;

  final Widget child;

  @override
  State<LodestoneSurface> createState() => _LodestoneSurfaceState();
}

class _LodestoneSurfaceState extends State<LodestoneSurface>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver, WindowListener {
  static Future<ui.FragmentProgram>? _program;
  static const double _settleSeconds = 0.62;

  ui.FragmentShader? _shader;
  final GlobalKey _sheetKey = GlobalKey();
  final Stopwatch _watch = Stopwatch()..start();
  late final _LodestoneField _field = _LodestoneField(_sheetKey, _onShift);
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  )..addListener(_onSettle);

  Offset _fromDrift = Offset.zero;
  double _fromPull = 0;
  double _swingPeak = 0;
  int _lastShift = -1000;
  bool _motion = false;
  bool _focused = true;
  bool _resumed = true;

  bool get _enabled => _motion && _focused && _resumed && _shader != null;

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
          await (_program ??= ui.FragmentProgram.fromAsset('resources/shaders/lodestone.frag'));
      if (!mounted) return;
      setState(() => _shader = program.fragmentShader());
      _rest();
    } catch (error) {
      _program = null;
      debugPrint('Lodestone shader unavailable: $error');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion = !MediaQuery.disableAnimationsOf(context) &&
        !MediaQuery.highContrastOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (!_motion) _rest();
  }

  /// The selection moved, appeared, or left. [from] is where the stone was
  /// drawn, relative to where it is now.
  void _onShift(Offset from) {
    if (!_enabled) {
      _rest();
      return;
    }
    // Held arrow keys arrive faster than a swing can read. Follow them exactly.
    final int now = _watch.elapsedMilliseconds;
    final bool rapid = now - _lastShift < 110;
    _lastShift = now;
    _fromDrift = rapid ? Offset.zero : from;
    _fromPull = _field.pull;
    _swingPeak = rapid ? 0 : (from == Offset.zero ? 0.35 : 1);
    _settle.forward(from: 0);
  }

  void _onSettle() {
    final double t = _settle.value;
    final double travel = Curves.easeOutCubic.transform(t < 0.4 ? t / 0.4 : 1);
    final double attack = Curves.easeOut.transform(t < 0.08 ? t / 0.08 : 1);
    _field.present(
      drift: _fromDrift * (1 - travel),
      pull: ui.lerpDouble(_fromPull, _field.held ? 1 : 0, travel)!,
      swing: _swingPeak * attack * (1 - t) * (1 - t),
      clock: t * _settleSeconds,
    );
  }

  void _rest() {
    _settle.stop();
    _field.present(drift: Offset.zero, pull: _field.held ? 1 : 0, swing: 0, clock: 0);
  }

  @override
  void onWindowFocus() => _focused = true;

  @override
  void onWindowBlur() {
    _focused = false;
    _rest();
  }

  @override
  void onWindowMinimize() => onWindowBlur();

  @override
  void onWindowRestore() => onWindowFocus();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    if (!_resumed) _rest();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    _settle.dispose();
    _field.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _LodestoneScope(
        field: _field,
        child: NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification notification) {
            _field.queueGeometry();
            return false;
          },
          child: RepaintBoundary(
            child: CustomPaint(
              key: _sheetKey,
              painter: _LodestonePainter(
                shader: _shader,
                field: _field,
                foreground: LodestoneTokens.foreground,
                accent: LodestoneTokens.accent,
                isDark: LodestoneTokens.isDark,
                highContrast: MediaQuery.highContrastOf(context),
              ),
              child: RepaintBoundary(child: widget.child),
            ),
          ),
        ),
      );
}

class _LodestoneScope extends InheritedWidget {
  const _LodestoneScope({required this.field, required super.child});

  final _LodestoneField field;

  static _LodestoneField? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_LodestoneScope>()?.field;

  @override
  bool updateShouldNotify(_LodestoneScope oldWidget) => field != oldWidget.field;
}

/// Reports a row to the field. The selected one becomes the lodestone. Outside
/// a [LodestoneSurface] this is a plain pass-through.
class LodestonePole extends SingleChildRenderObjectWidget {
  const LodestonePole({super.key, required this.selected, required super.child});

  final bool selected;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderLodestonePole(_LodestoneScope.of(context), selected);

  @override
  void updateRenderObject(BuildContext context, covariant RenderObject renderObject) {
    final _RenderLodestonePole pole = renderObject as _RenderLodestonePole;
    pole
      ..field = _LodestoneScope.of(context)
      ..selected = selected;
  }
}

class _RenderLodestonePole extends RenderProxyBox {
  _RenderLodestonePole(this._field, this._selected);

  _LodestoneField? _field;
  bool _selected;

  set field(_LodestoneField? value) {
    if (_field == value) return;
    if (attached) _field?.unregister(this);
    _field = value;
    if (attached) _field?.register(this);
  }

  set selected(bool value) {
    if (_selected == value) return;
    _selected = value;
    _field?.queueGeometry();
  }

  bool get selected => _selected;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _field?.register(this);
  }

  @override
  void detach() {
    _field?.unregister(this);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (selected) _field?.queueGeometry();
    super.paint(context, offset);
  }
}

class _LodestoneField extends ChangeNotifier {
  _LodestoneField(this.sheetKey, this.onShift);

  final GlobalKey sheetKey;
  final void Function(Offset from) onShift;
  final Set<_RenderLodestonePole> _poles = <_RenderLodestonePole>{};
  _RenderLodestonePole? _holder;

  /// Where the selected row is, in field coordinates. Kept after the selection
  /// leaves so the pull can fade out in place.
  Rect stone = Rect.zero;
  bool held = false;

  /// What the painter shows: [stone] offset by [drift] while it travels.
  Offset drift = Offset.zero;
  double pull = 0;
  double swing = 0;
  double clock = 0;

  bool _disposed = false;
  bool _geometryPending = false;

  RenderBox? get _sheet {
    final RenderObject? render = sheetKey.currentContext?.findRenderObject();
    return render is RenderBox && render.attached && render.hasSize ? render : null;
  }

  void register(_RenderLodestonePole pole) {
    if (_disposed) return;
    _poles.add(pole);
    queueGeometry();
  }

  void unregister(_RenderLodestonePole pole) {
    _poles.remove(pole);
    queueGeometry();
  }

  void queueGeometry() {
    if (_disposed || _geometryPending) return;
    _geometryPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _geometryPending = false;
      if (!_disposed) _sync();
    });
  }

  Rect? _visibleBounds(_RenderLodestonePole pole) {
    final RenderBox? sheet = _sheet;
    if (sheet == null || !pole.attached || !pole.hasSize) return null;
    Rect bounds = MatrixUtils.transformRect(pole.getTransformTo(sheet), Offset.zero & pole.size);
    RenderObject child = pole;
    RenderObject? ancestor = child.parent;
    while (ancestor != null && ancestor != sheet) {
      final Rect? clip = ancestor.describeApproximatePaintClip(child);
      if (clip != null) bounds = bounds.intersect(MatrixUtils.transformRect(ancestor.getTransformTo(sheet), clip));
      child = ancestor;
      ancestor = ancestor.parent;
    }
    bounds = bounds.intersect(Offset.zero & sheet.size);
    return bounds.isEmpty || !bounds.isFinite ? null : bounds;
  }

  void _sync() {
    _RenderLodestonePole? selected;
    for (final _RenderLodestonePole pole in _poles) {
      if (pole.selected) selected = pole;
    }
    final Rect? bounds = selected == null ? null : _visibleBounds(selected);
    if (bounds == null) {
      if (!held) return;
      held = false;
      _holder = null;
      onShift(Offset.zero);
      return;
    }
    final bool changedRow = selected != _holder;
    if (held && !changedRow && bounds == stone) return;
    final Offset shown = stone.center + drift;
    final bool wasHeld = held;
    stone = bounds;
    held = true;
    _holder = selected;
    if (!wasHeld) {
      onShift(Offset.zero);
    } else if (changedRow) {
      onShift(shown - bounds.center);
    } else {
      // Same row, new place: the list scrolled or resized. Follow it exactly.
      notifyListeners();
    }
  }

  void present({required Offset drift, required double pull, required double swing, required double clock}) {
    if (_disposed) return;
    this.drift = drift;
    this.pull = pull;
    this.swing = swing;
    this.clock = clock;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class _LodestonePainter extends CustomPainter {
  _LodestonePainter({
    required this.shader,
    required this.field,
    required this.foreground,
    required this.accent,
    required this.isDark,
    required this.highContrast,
  }) : super(repaint: field);

  final ui.FragmentShader? shader;
  final _LodestoneField field;
  final Color foreground;
  final Color accent;
  final bool isDark;
  final bool highContrast;

  @override
  void paint(Canvas canvas, Size size) {
    final ui.FragmentShader? effect = shader;
    // Without the shader, or in high contrast, the surface stays flat. Rows
    // carry their own selection plate, so nothing is lost.
    if (size.isEmpty || highContrast || effect == null) return;
    final Rect stone = field.stone.shift(field.drift);
    // Float slots match lodestone.frag.
    effect
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, stone.left + LodestoneSurface.poleInset)
      ..setFloat(3, stone.center.dy)
      ..setFloat(4, stone.center.dx)
      ..setFloat(5, stone.center.dy)
      ..setFloat(6, stone.width * 0.5)
      ..setFloat(7, stone.height * 0.5)
      ..setFloat(8, field.pull)
      ..setFloat(9, field.swing)
      ..setFloat(10, field.clock)
      ..setFloat(11, LodestoneSurface.pitch)
      ..setFloat(12, isDark ? 1 : 0);
    int slot = 13;
    for (final Color color in <Color>[foreground, accent]) {
      effect
        ..setFloat(slot++, color.r)
        ..setFloat(slot++, color.g)
        ..setFloat(slot++, color.b);
    }
    canvas.drawRect(Offset.zero & size, Paint()..shader = effect);
  }

  @override
  bool shouldRepaint(_LodestonePainter oldDelegate) =>
      shader != oldDelegate.shader ||
      field != oldDelegate.field ||
      foreground != oldDelegate.foreground ||
      accent != oldDelegate.accent ||
      isDark != oldDelegate.isDark ||
      highContrast != oldDelegate.highContrast;
}
