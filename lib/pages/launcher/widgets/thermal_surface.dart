import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../launcher_corners.dart';
import '../launcher_design.dart';

/// One continuous mineral sheet, with a bounded history in panel coordinates.
/// Only the background repaints. Search, icons and previews retain their pixels.
class ThermalSurface extends StatefulWidget {
  const ThermalSurface({super.key, required this.child, this.radius = 10});

  final Widget child;
  final double radius;

  @override
  State<ThermalSurface> createState() => _ThermalSurfaceState();
}

class _ThermalSurfaceState extends State<ThermalSurface>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver, WindowListener {
  static Future<ui.FragmentProgram>? _program;
  final GlobalKey _sheetKey = GlobalKey();
  late final _ThermalField _field = _ThermalField(this, _sheetKey);
  ui.FragmentShader? _shader;
  bool _motion = false;
  bool _focused = true;
  bool _resumed = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);
    HardwareKeyboard.instance.addHandler(_onKey);
    _load();
  }

  Future<void> _load() async {
    final Future<ui.FragmentProgram> loading =
        _program ??= ui.FragmentProgram.fromAsset('resources/shaders/thermal.frag');
    try {
      final ui.FragmentProgram program = await loading;
      if (!mounted) return;
      setState(() => _shader = program.fragmentShader());
      _syncMotion();
    } catch (error) {
      if (identical(_program, loading)) {
        _program = null;
        debugPrint('Thermal shader unavailable: $error');
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion = !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled &&
        ModalRoute.of(context)?.isCurrent != false;
    _syncMotion();
  }

  void _syncMotion() => _field.setEnabled(_shader != null && _motion && _focused && _resumed);

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        !_field.enabled ||
        (event.logicalKey != LogicalKeyboardKey.enter && event.logicalKey != LogicalKeyboardKey.numpadEnter)) {
      return false;
    }
    final BuildContext? focus = FocusManager.instance.primaryFocus?.context;
    final ModalRoute<dynamic>? route = ModalRoute.of(context);
    if (focus != null && route?.isCurrent != false && ModalRoute.of(focus) == route) {
      final Rect? row = _field.selectionRect;
      if (row != null) _field.press(Offset(row.right - 20, row.center.dy));
    }
    // The launcher's existing handlers retain ownership of execution and timing.
    return false;
  }

  @override
  void onWindowFocus() {
    _focused = true;
    _syncMotion();
  }

  @override
  void onWindowBlur() {
    _focused = false;
    _syncMotion();
  }

  @override
  void onWindowMinimize() => onWindowBlur();

  @override
  void onWindowRestore() => onWindowFocus();

  @override
  void onWindowResize() => _field.queueGeometry();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _syncMotion();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    windowManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    _field.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ThermalScope(
        field: _field,
        child: NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification notification) {
            _field.queueGeometry();
            return false;
          },
          child: LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
            _field.queueGeometry();
            return MouseRegion(
              onEnter: (PointerEnterEvent event) => _field.hover(event.localPosition),
              onHover: (PointerHoverEvent event) => _field.hover(event.localPosition),
              onExit: (_) => _field.leave(),
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (PointerDownEvent event) => _field.press(event.localPosition),
                child: RepaintBoundary(
                  child: LauncherClip(
                    borderRadius: BorderRadius.circular(widget.radius),
                    child: CustomPaint(
                      key: _sheetKey,
                      painter: _ThermalPainter(
                        field: _field,
                        shader: _shader,
                        isDark: Theme.of(context).brightness == Brightness.dark,
                        background: ThermalTokens.background,
                        foreground: ThermalTokens.foreground,
                        accent: ThermalTokens.accent,
                      ),
                      child: RepaintBoundary(child: widget.child),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      );
}

class _ThermalScope extends InheritedWidget {
  const _ThermalScope({required this.field, required super.child});

  final _ThermalField field;

  static _ThermalField? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_ThermalScope>()?.field;

  @override
  bool updateShouldNotify(_ThermalScope oldWidget) => field != oldWidget.field;
}

/// Reports real row geometry, including viewport clipping, to the shared sheet.
/// Heat survives row disposal, so changing a query does not erase its history.
class ThermalRegion extends SingleChildRenderObjectWidget {
  const ThermalRegion({super.key, required this.selected, required super.child});

  final bool selected;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderThermalRegion(_ThermalScope.of(context), selected);

  @override
  void updateRenderObject(BuildContext context, covariant RenderObject renderObject) {
    final _RenderThermalRegion region = renderObject as _RenderThermalRegion;
    region
      ..field = _ThermalScope.of(context)
      ..selected = selected;
  }
}

class _RenderThermalRegion extends RenderProxyBox {
  _RenderThermalRegion(this._field, this._selected);

  _ThermalField? _field;
  bool _selected;

  set field(_ThermalField? value) {
    if (_field == value) return;
    if (attached) _field?.unregister(this);
    _field = value;
    if (attached) _field?.register(this);
  }

  bool get selected => _selected;

  set selected(bool value) {
    if (_selected == value) return;
    _selected = value;
    _field?.queueGeometry();
  }

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

/// Measures the rendered caret after editing/layout, including scrolling, text
/// scaling, custom fonts, RTL and IME composition. Selection-only changes are cold.
class ThermalQueryHeat extends StatefulWidget {
  const ThermalQueryHeat({super.key, required this.controller, required this.child});

  final TextEditingController controller;
  final Widget child;

  @override
  State<ThermalQueryHeat> createState() => _ThermalQueryHeatState();
}

class _ThermalQueryHeatState extends State<ThermalQueryHeat> {
  final GlobalKey _inputKey = GlobalKey();
  final Stopwatch _watch = Stopwatch()..start();
  _ThermalField? _field;
  EditableTextState? _editable;
  String _text = '';
  double _lastEdit = -10;
  double _speed = 0;
  bool _pending = false;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _attach() {
    _text = widget.controller.text;
    widget.controller.addListener(_onEdit);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _field = _ThermalScope.of(context);
  }

  @override
  void didUpdateWidget(covariant ThermalQueryHeat oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onEdit);
      _editable = null;
      _attach();
    }
  }

  void _onEdit() {
    if (widget.controller.text == _text) return;
    _text = widget.controller.text;
    if (_field?.enabled != true) return;
    final double now = _watch.elapsedMicroseconds / Duration.microsecondsPerSecond;
    _speed = (1 - (now - _lastEdit) / 0.3).clamp(0.0, 1.0).toDouble();
    _lastEdit = now;
    if (_pending) return;
    _pending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pending = false;
      if (!mounted || _field?.enabled != true) return;
      if (_editable?.mounted != true) {
        void findEditable(Element element) {
          if (_editable?.mounted == true) return;
          if (element is StatefulElement) {
            final State<StatefulWidget> state = element.state;
            if (state is EditableTextState) {
              _editable = state;
              return;
            }
          }
          element.visitChildElements(findEditable);
        }

        _inputKey.currentContext?.visitChildElements(findEditable);
      }
      final EditableTextState? editable = _editable;
      final TextSelection selection = widget.controller.selection;
      if (editable == null || !editable.widget.focusNode.hasFocus || !selection.isValid) return;
      final RenderEditable render = editable.renderEditable;
      if (!render.attached || !render.hasSize) return;
      final Rect caret = render.getLocalRectForCaret(selection.extent);
      final Offset underCaret = Offset(
        caret.center.dx.clamp(0.0, render.size.width).toDouble(),
        caret.bottom.clamp(0.0, render.size.height).toDouble() + 3,
      );
      final Offset? position = _field?.toLocal(render.localToGlobal(underCaret));
      if (position != null) _field?.type(position, _speed);
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onEdit);
    _watch.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KeyedSubtree(key: _inputKey, child: widget.child);
}

class _ThermalMark {
  const _ThermalMark(this.bounds, this.strength, this.born, this.life, this.softness, this.diffusion);

  final Rect bounds;
  final double strength;
  final double born;
  final double life;
  final double softness;
  final double diffusion;

  double heat(double now) {
    final double age = math.max(0, now - born);
    final double end = (1 - age / life).clamp(0.0, 1.0).toDouble();
    // The tail reaches exactly zero before the ticker sleeps.
    return strength * math.exp(-age * 0.6) * end;
  }

  double spread(double now) => math.sqrt(softness * softness + math.max(0, now - born) * diffusion);
}

class _ThermalField extends ChangeNotifier {
  _ThermalField(TickerProvider vsync, this.sheetKey) {
    _ticker = vsync.createTicker(_tick);
  }

  final GlobalKey sheetKey;
  final Stopwatch _watch = Stopwatch()..start();
  final Set<_RenderThermalRegion> _regions = <_RenderThermalRegion>{};
  final List<_ThermalMark> rows = <_ThermalMark>[];
  final List<_ThermalMark> touches = <_ThermalMark>[];
  final List<_ThermalMark> typing = <_ThermalMark>[];
  final List<_ThermalMark> clicks = <_ThermalMark>[];
  late final Ticker _ticker;
  _RenderThermalRegion? _selection;
  Rect? selectionRect;
  Offset? pointer;
  double _selectedAt = -10;
  double _hoveredAt = -10;
  double _deadline = 0;
  bool enabled = false;
  bool _geometryPending = false;
  bool _disposed = false;

  double get time => _watch.elapsedMicroseconds / Duration.microsecondsPerSecond;
  double get selectionHeat => selectionRect == null
      ? 0
      : enabled
          ? 0.04 + 0.54 * (1 - math.exp(-math.min(time - _selectedAt, 1.2) * 4))
          : 0.58;
  double get hoverHeat => pointer == null ? 0 : 0.72 * (1 - math.exp(-math.min(time - _hoveredAt, 1.4) * 3.8));

  RenderBox? get _sheet {
    final RenderObject? render = sheetKey.currentContext?.findRenderObject();
    return render is RenderBox && render.attached && render.hasSize ? render : null;
  }

  Offset? toLocal(Offset global) => _sheet?.globalToLocal(global);

  void register(_RenderThermalRegion region) {
    if (_disposed) return;
    _regions.add(region);
    queueGeometry();
  }

  void unregister(_RenderThermalRegion region) {
    _regions.remove(region);
    queueGeometry();
  }

  void queueGeometry() {
    if (_disposed || _geometryPending) return;
    _geometryPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _geometryPending = false;
      if (!_disposed) _syncSelection();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  Rect? _visibleBounds(_RenderThermalRegion region) {
    final RenderBox? sheet = _sheet;
    if (sheet == null || !region.attached || !region.hasSize) return null;
    Rect bounds = MatrixUtils.transformRect(region.getTransformTo(sheet), Offset.zero & region.size);
    RenderObject child = region;
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

  void _syncSelection() {
    _RenderThermalRegion? next;
    for (final _RenderThermalRegion region in _regions) {
      if (region.selected) next = region;
    }
    final Rect? bounds = next == null ? null : _visibleBounds(next);
    if (next == _selection && bounds == selectionRect) return;
    if (next != _selection) {
      final Rect? previous = selectionRect;
      if (enabled && previous != null) {
        _add(rows, _ThermalMark(previous, selectionHeat, time, 3.8, 5, 65), 3);
      }
      _selection = next;
      _selectedAt = time;
      _wake(1.3);
    }
    selectionRect = bounds;
    notifyListeners();
  }

  void setEnabled(bool value) {
    if (_disposed || enabled == value) return;
    enabled = value;
    _ticker.stop();
    rows.clear();
    touches.clear();
    typing.clear();
    clicks.clear();
    pointer = null;
    _selectedAt = time - 2;
    _deadline = time;
    notifyListeners();
  }

  void _wake(double duration) {
    if (!enabled || _disposed) return;
    _deadline = math.max(_deadline, time + duration);
    if (!_ticker.isActive) _ticker.start();
  }

  void _add(List<_ThermalMark> marks, _ThermalMark mark, int limit) {
    if (!enabled) return;
    marks.insert(0, mark);
    if (marks.length > limit) marks.removeLast();
    _wake(mark.life);
  }

  void hover(Offset position) {
    if (!enabled) return;
    final Offset? previous = pointer;
    // Keep stationary heat stationary; pointer events do not restart its warming.
    if (previous != null && (position - previous).distanceSquared < 49) return;
    if (previous != null) {
      _add(touches, _ThermalMark(Rect.fromCenter(center: previous, width: 0, height: 0), hoverHeat, time, 2.5, 24, 100),
          3);
    }
    pointer = position;
    _hoveredAt = time;
    _wake(1.5);
    notifyListeners();
  }

  void leave() {
    if (pointer == null) return;
    _add(touches, _ThermalMark(Rect.fromCenter(center: pointer!, width: 0, height: 0), hoverHeat, time, 2.5, 24, 100),
        3);
    pointer = null;
    notifyListeners();
  }

  void press(Offset position) {
    if (!enabled) return;
    _add(clicks, _ThermalMark(Rect.fromCenter(center: position, width: 0, height: 0), 1.8, time, 1.8, 9, 85), 2);
    notifyListeners();
  }

  void type(Offset position, double speed) {
    if (!enabled) return;
    _add(
        typing,
        _ThermalMark(Rect.fromCenter(center: position, width: 8 + speed * 12, height: 0), 0.85 + speed * 0.2, time, 1.2,
            7 + speed * 3, 45 + speed * 65),
        3);
    notifyListeners();
  }

  void _tick(Duration elapsed) {
    final double now = time;
    for (final List<_ThermalMark> marks in <List<_ThermalMark>>[rows, touches, typing, clicks]) {
      marks.removeWhere((_ThermalMark mark) => now - mark.born >= mark.life);
    }
    notifyListeners();
    if (now >= _deadline) _ticker.stop();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker.dispose();
    _watch.stop();
    _regions.clear();
    super.dispose();
  }
}

class _ThermalPainter extends CustomPainter {
  _ThermalPainter({
    required this.field,
    required this.shader,
    required this.isDark,
    required this.background,
    required this.foreground,
    required this.accent,
  }) : super(repaint: field);

  final _ThermalField field;
  final ui.FragmentShader? shader;
  final bool isDark;
  final Color background;
  final Color foreground;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final Rect panel = Offset.zero & size;
    final ui.FragmentShader? effect = shader;
    if (effect == null) {
      canvas.drawRect(panel, Paint()..color = background);
      final Rect? selected = field.selectionRect;
      if (selected != null) {
        canvas.drawRRect(RRect.fromRectAndRadius(selected, const Radius.circular(5)),
            Paint()..color = ThermalTokens.rust.withAlpha(115));
      }
      return;
    }
    effect
      ..setFloat(0, size.width)
      ..setFloat(1, size.height);
    int slot = 2;
    void source(Rect? rect, double heat, double softness) {
      effect
        ..setFloat(slot++, rect?.center.dx ?? 0)
        ..setFloat(slot++, rect?.center.dy ?? 0)
        ..setFloat(slot++, (rect?.width ?? 0) / 2)
        ..setFloat(slot++, (rect?.height ?? 0) / 2)
        ..setFloat(slot++, heat)
        ..setFloat(slot++, softness);
    }

    // The first 80 float slots contain state in thermal.frag declaration order.
    // Empty slots are cleared on every paint; the four history budgets cannot
    // evict one another. Palette colors follow the state slots below.
    source(field.selectionRect, field.selectionHeat, 5);
    source(field.pointer == null ? null : Rect.fromCenter(center: field.pointer!, width: 0, height: 0), field.hoverHeat,
        24);
    final double now = field.time;
    void history(List<_ThermalMark> marks, int count) {
      for (int index = 0; index < count; index++) {
        final _ThermalMark? mark = index < marks.length ? marks[index] : null;
        source(mark?.bounds, mark?.heat(now) ?? 0, mark?.spread(now) ?? 1);
      }
    }

    history(field.rows, 3);
    history(field.touches, 3);
    history(field.typing, 3);
    history(field.clicks, 2);
    for (final Color color in <Color>[background, foreground, accent]) {
      effect
        ..setFloat(slot++, color.r)
        ..setFloat(slot++, color.g)
        ..setFloat(slot++, color.b);
    }
    canvas.drawRect(panel, Paint()..shader = effect);
  }

  @override
  bool shouldRepaint(_ThermalPainter oldDelegate) =>
      field != oldDelegate.field ||
      shader != oldDelegate.shader ||
      isDark != oldDelegate.isDark ||
      background != oldDelegate.background ||
      foreground != oldDelegate.foreground ||
      accent != oldDelegate.accent;
}
