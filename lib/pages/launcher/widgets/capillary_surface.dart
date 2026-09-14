import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../launcher_design.dart';

/// A single, demand-driven clock for all the paper in a launcher or dialog.
/// Ink finishes drying before the ticker stops; idle paper never repaints.
class CapillaryMotion extends StatefulWidget {
  const CapillaryMotion({super.key, required this.child, this.queryController});

  final Widget child;
  final TextEditingController? queryController;

  @override
  State<CapillaryMotion> createState() => _CapillaryMotionState();
}

class _CapillaryMotionState extends State<CapillaryMotion>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver, WindowListener {
  late final _CapillaryClock _clock = _CapillaryClock(this);
  String _query = '';
  bool _focused = true;
  bool _resumed = true;
  bool _motion = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);
    HardwareKeyboard.instance.addHandler(_onKey);
    _attachQuery();
  }

  void _attachQuery() {
    _query = widget.queryController?.text ?? '';
    widget.queryController?.addListener(_onQuery);
  }

  void _onQuery() {
    final TextEditingValue? value = widget.queryController?.value;
    if (value == null || value.text == _query) return;
    _query = value.text;
    if (!_clock.enabled) return;
    final int caret =
        value.selection.isValid ? value.selection.extentOffset.clamp(0, _query.length).toInt() : _query.length;
    // Keep measuring bounded for pasted paths/queries. The ink is fed into the
    // lower paper edge, leaving the actual caret and text entirely untouched.
    final TextPainter measure = TextPainter(
      text: TextSpan(
          text: _query.substring(math.max(0, caret - 80), caret),
          style: CapillaryTokens.of(context).font(size: 18, weight: FontWeight.w400)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    _clock.feed(36 + measure.width);
    measure.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        (event.logicalKey != LogicalKeyboardKey.enter && event.logicalKey != LogicalKeyboardKey.numpadEnter) ||
        !_clock.enabled) return false;
    final BuildContext? focusedContext = FocusManager.instance.primaryFocus?.context;
    final ModalRoute<dynamic>? route = ModalRoute.of(context);
    if (focusedContext != null && route?.isCurrent != false && ModalRoute.of(focusedContext) == route) {
      _clock.stamp.value++;
    }
    // Decorative feedback only: the launcher's existing handler owns the key.
    return false;
  }

  @override
  void didUpdateWidget(covariant CapillaryMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.queryController != widget.queryController) {
      oldWidget.queryController?.removeListener(_onQuery);
      _attachQuery();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion = !MediaQuery.disableAnimationsOf(context) && TickerMode.valuesOf(context).enabled;
    _sync();
  }

  void _sync() => _clock.setEnabled(_motion && _focused && _resumed);

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
    widget.queryController?.removeListener(_onQuery);
    HardwareKeyboard.instance.removeHandler(_onKey);
    windowManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _CapillaryScope(clock: _clock, child: widget.child);
}

class _CapillaryClock extends ChangeNotifier {
  _CapillaryClock(TickerProvider vsync) {
    _ticker = vsync.createTicker(_tick);
  }

  late final Ticker _ticker;
  final ValueNotifier<int> stamp = ValueNotifier<int>(0);
  final List<({double x, double time})> drops = <({double x, double time})>[];
  double time = 0;
  double _startedAt = 0;
  double _deadline = 0;
  bool enabled = false;

  void setEnabled(bool value) {
    if (enabled == value) return;
    enabled = value;
    if (!enabled) {
      _ticker.stop();
      // Settle old marks instead of replaying them after focus is restored.
      time = math.max(time, _deadline) + 2;
      _deadline = time;
      drops.clear();
    }
    notifyListeners();
  }

  void wake() {
    if (!enabled) return;
    _deadline = time + 1.8;
    if (!_ticker.isActive) {
      _startedAt = time;
      _ticker.start();
    }
  }

  void feed(double x) {
    if (!enabled) return;
    drops.insert(0, (x: x, time: time));
    if (drops.length > 3) drops.removeLast();
    wake();
    notifyListeners();
  }

  void _tick(Duration elapsed) {
    time = _startedAt + elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    notifyListeners();
    if (time >= _deadline) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    stamp.dispose();
    super.dispose();
  }
}

class _CapillaryScope extends InheritedWidget {
  const _CapillaryScope({required this.clock, required super.child});
  final _CapillaryClock clock;

  @override
  bool updateShouldNotify(_CapillaryScope oldWidget) => clock != oldWidget.clock;
}

enum CapillarySurfaceKind { paper, wash, search, overlay }

/// Shader pigment lives beneath content. The optional foreground paper grain
/// unifies opaque plugin controls without capturing or distorting their pixels.
class CapillarySurface extends StatefulWidget {
  const CapillarySurface({
    super.key,
    required this.child,
    this.selected = false,
    this.radius = 4,
    this.kind = CapillarySurfaceKind.wash,
  });

  final Widget child;
  final bool selected;
  final double radius;
  final CapillarySurfaceKind kind;

  @override
  State<CapillarySurface> createState() => _CapillarySurfaceState();
}

class _CapillarySurfaceState extends State<CapillarySurface> {
  static Future<ui.FragmentProgram>? _program;
  ui.FragmentShader? _shader;
  _CapillaryClock? _clock;
  final _CapillaryMarks _marks = _CapillaryMarks();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final Future<ui.FragmentProgram> loading =
        _program ??= ui.FragmentProgram.fromAsset('resources/shaders/capillary.frag');
    try {
      final ui.FragmentProgram program = await loading;
      if (mounted) setState(() => _shader = program.fragmentShader());
    } catch (error) {
      if (identical(_program, loading)) {
        _program = null;
        debugPrint('Capillary shader unavailable: $error');
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final _CapillaryClock? clock = context.dependOnInheritedWidgetOfExactType<_CapillaryScope>()?.clock;
    if (_clock != clock) {
      _clock?.stamp.removeListener(_stampSelected);
      _clock = clock;
      _clock?.stamp.addListener(_stampSelected);
      if (widget.selected) {
        _marks.selectedAt = clock?.time ?? 0;
        clock?.wake();
      }
    }
  }

  @override
  void didUpdateWidget(covariant CapillarySurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      if (widget.selected) {
        _marks.selectedAt = _clock?.time ?? 0;
      } else {
        _marks.releasedAt = _clock?.time ?? 0;
      }
      _clock?.wake();
    }
  }

  void _stampSelected() {
    if (!widget.selected || widget.kind != CapillarySurfaceKind.wash) return;
    final RenderObject? render = context.findRenderObject();
    if (render is RenderBox && render.hasSize) _press(Offset(26, render.size.height / 2));
  }

  void _press(Offset position) {
    if (_clock?.enabled != true) return;
    _marks.press = position;
    _marks.pressedAt = _clock!.time;
    _clock!.wake();
    _marks.changed();
  }

  void _hover(Offset position) {
    if (_clock?.enabled != true) return;
    if (!_marks.hovered) _marks.hoveredAt = _clock!.time;
    _marks.hovered = true;
    _marks.pointer = position;
    _clock!.wake();
    _marks.changed();
  }

  void _leave() {
    _marks.hovered = false;
    _marks.leftAt = _clock?.time ?? 0;
    _clock?.wake();
    _marks.changed();
  }

  @override
  void dispose() {
    _clock?.stamp.removeListener(_stampSelected);
    _shader?.dispose();
    _marks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool overlay = widget.kind == CapillarySurfaceKind.overlay;
    final CapillaryTokens capillary = CapillaryTokens.of(context);
    final _CapillaryPainter painter = _CapillaryPainter(
      shader: _shader,
      clock: _clock,
      marks: _marks,
      kind: widget.kind,
      selected: widget.selected,
      paper: capillary.background,
      pigment: capillary.accent,
    );
    final Widget paper = RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.radius),
        child: CustomPaint(
          painter: overlay ? null : painter,
          foregroundPainter: overlay ? painter : null,
          child: RepaintBoundary(child: widget.child),
        ),
      ),
    );
    if (overlay) return paper;
    return MouseRegion(
      onEnter: (PointerEnterEvent event) => _hover(event.localPosition),
      onHover: (PointerHoverEvent event) => _hover(event.localPosition),
      onExit: (_) => _leave(),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (PointerDownEvent event) => _press(event.localPosition),
        child: paper,
      ),
    );
  }
}

class _CapillaryMarks extends ChangeNotifier {
  double selectedAt = -100;
  double releasedAt = -100;
  double hoveredAt = -100;
  double leftAt = -100;
  double pressedAt = -100;
  bool hovered = false;
  Offset pointer = Offset.zero;
  Offset press = Offset.zero;

  void changed() => notifyListeners();
}

class _CapillaryPainter extends CustomPainter {
  _CapillaryPainter({
    required this.shader,
    required this.clock,
    required this.marks,
    required this.kind,
    required this.selected,
    required this.paper,
    required this.pigment,
  }) : super(repaint: kind == CapillarySurfaceKind.overlay ? null : Listenable.merge(<Listenable?>[clock, marks]));

  final ui.FragmentShader? shader;
  final _CapillaryClock? clock;
  final _CapillaryMarks marks;
  final CapillarySurfaceKind kind;
  final bool selected;
  final Color paper;
  final Color pigment;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final Rect rect = Offset.zero & size;
    final ui.FragmentShader? effect = shader;
    if (effect == null) {
      if (kind == CapillarySurfaceKind.overlay) return;
      canvas.drawRect(rect, Paint()..color = paper);
      if (selected) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(rect.deflate(3), const Radius.circular(4)), Paint()..color = pigment.withAlpha(32));
      }
      return;
    }
    final double time = clock?.time ?? 0;
    final bool motion = clock?.enabled ?? false;
    effect
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, kind.index.toDouble())
      ..setFloat(3, selected ? 1 : 0)
      ..setFloat(4, motion ? math.max(0, (selected ? time : marks.releasedAt) - marks.selectedAt) : 10)
      ..setFloat(5, motion ? time - marks.releasedAt : 100)
      ..setFloat(6, marks.pointer.dx)
      ..setFloat(7, marks.pointer.dy)
      ..setFloat(8, motion && marks.hovered ? 1 : 0)
      ..setFloat(9, motion ? time - marks.hoveredAt : 100)
      ..setFloat(10, motion ? time - marks.leftAt : 100)
      ..setFloat(11, marks.press.dx)
      ..setFloat(12, marks.press.dy)
      ..setFloat(13, motion ? time - marks.pressedAt : 100);
    for (int index = 0; index < 3; index++) {
      final ({double x, double time})? drop =
          motion && clock != null && index < clock!.drops.length ? clock!.drops[index] : null;
      effect
        ..setFloat(14 + index * 2, drop?.x.clamp(16.0, math.max(16.0, size.width - 16)).toDouble() ?? 16)
        ..setFloat(15 + index * 2, drop == null ? 100 : time - drop.time);
    }
    effect
      ..setFloat(20, paper.r)
      ..setFloat(21, paper.g)
      ..setFloat(22, paper.b)
      ..setFloat(23, pigment.r)
      ..setFloat(24, pigment.g)
      ..setFloat(25, pigment.b);
    canvas.drawRect(rect, Paint()..shader = effect);
  }

  @override
  bool shouldRepaint(_CapillaryPainter oldDelegate) =>
      shader != oldDelegate.shader ||
      clock != oldDelegate.clock ||
      marks != oldDelegate.marks ||
      paper != oldDelegate.paper ||
      pigment != oldDelegate.pigment ||
      kind != oldDelegate.kind ||
      selected != oldDelegate.selected;
}
