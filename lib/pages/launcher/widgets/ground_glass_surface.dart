import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:window_manager/window_manager.dart';

import '../launcher_corners.dart';
import '../launcher_design.dart';

/// Ground-glass focusing screen. The selected row is the sharp plane, and
/// typing racks focus for a short settle. Nothing samples the desktop, and
/// the clock stops when the plate is still.
class GroundGlassSurface extends StatefulWidget {
  const GroundGlassSurface({super.key, required this.child, this.radius = 12});

  final Widget child;
  final double radius;

  @override
  State<GroundGlassSurface> createState() => _GroundGlassSurfaceState();
}

class _GroundGlassSurfaceState extends State<GroundGlassSurface>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver, WindowListener {
  static Future<ui.FragmentProgram>? _program;
  ui.FragmentShader? _shader;
  final GlobalKey _sheetKey = GlobalKey();
  late final _GroundGlassPlate _plate = _GroundGlassPlate(_sheetKey);
  late final AnimationController _rack = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 760),
  )..addListener(_coolRack);
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
          await (_program ??= ui.FragmentProgram.fromAsset('resources/shaders/ground_glass.frag'));
      if (!mounted) return;
      setState(() => _shader = program.fragmentShader());
      _plate.enabled = _enabled;
    } catch (error) {
      _program = null;
      debugPrint('Ground Glass shader unavailable: $error');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion = !MediaQuery.disableAnimationsOf(context) &&
        !MediaQuery.highContrastOf(context) &&
        TickerMode.valuesOf(context).enabled;
    _plate.enabled = _enabled;
    if (!_motion) _rest(notify: false);
  }

  void _rest({required bool notify}) {
    _rack.stop();
    if (!notify) {
      _plate.rack = 0;
      return;
    }
    _plate.setRack(0);
  }

  void _coolRack() {
    _plate.setRack(1 - Curves.easeInCubic.transform(_rack.value));
  }

  @override
  void onWindowFocus() {
    _focused = true;
    _plate.enabled = _enabled;
  }

  @override
  void onWindowBlur() {
    _focused = false;
    _plate.enabled = false;
    _rest(notify: true);
  }

  @override
  void onWindowMinimize() => onWindowBlur();

  @override
  void onWindowRestore() => onWindowFocus();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _plate.enabled = _enabled;
    if (!_resumed) _rest(notify: true);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    _rack.dispose();
    _plate.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _GroundGlassScope(
        plate: _plate,
        rack: _rack,
        child: NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification notification) {
            _plate.queueGeometry();
            return false;
          },
          child: LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
            _plate.queueGeometry();
            return LauncherClip(
              borderRadius: BorderRadius.circular(widget.radius),
              child: CustomPaint(
                key: _sheetKey,
                painter: _GroundGlassPainter(
                  shader: _shader,
                  plate: _plate,
                  background: GroundGlassTokens.background,
                  foreground: GroundGlassTokens.foreground,
                  accent: GroundGlassTokens.accent,
                  highContrast: MediaQuery.highContrastOf(context),
                ),
                child: RepaintBoundary(child: widget.child),
              ),
            );
          }),
        ),
      );
}

class _GroundGlassScope extends InheritedWidget {
  const _GroundGlassScope({required this.plate, required this.rack, required super.child});

  final _GroundGlassPlate plate;
  final AnimationController rack;

  static _GroundGlassScope? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_GroundGlassScope>();

  @override
  bool updateShouldNotify(_GroundGlassScope oldWidget) => plate != oldWidget.plate || rack != oldWidget.rack;
}

/// Reports the selected row in focusing-screen coordinates, including clips.
class GroundGlassRegion extends SingleChildRenderObjectWidget {
  const GroundGlassRegion({super.key, required this.selected, required super.child});

  final bool selected;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderGroundGlassRegion(_GroundGlassScope.of(context)?.plate, selected);

  @override
  void updateRenderObject(BuildContext context, covariant RenderObject renderObject) {
    final _RenderGroundGlassRegion region = renderObject as _RenderGroundGlassRegion;
    region
      ..plate = _GroundGlassScope.of(context)?.plate
      ..selected = selected;
  }
}

class _RenderGroundGlassRegion extends RenderProxyBox {
  _RenderGroundGlassRegion(this._plate, this._selected);

  _GroundGlassPlate? _plate;
  bool _selected;

  set plate(_GroundGlassPlate? value) {
    if (_plate == value) return;
    if (attached) _plate?.unregister(this);
    _plate = value;
    if (attached) _plate?.register(this);
  }

  set selected(bool value) {
    if (_selected == value) return;
    _selected = value;
    _plate?.queueGeometry();
  }

  bool get selected => _selected;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _plate?.register(this);
  }

  @override
  void detach() {
    _plate?.unregister(this);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (selected) _plate?.queueGeometry();
    super.paint(context, offset);
  }
}

/// A text edit racks the focusing screen. Caret movement alone does not.
class GroundGlassQueryRack extends StatefulWidget {
  const GroundGlassQueryRack({super.key, required this.controller, required this.child});

  final TextEditingController controller;
  final Widget child;

  @override
  State<GroundGlassQueryRack> createState() => _GroundGlassQueryRackState();
}

class _GroundGlassQueryRackState extends State<GroundGlassQueryRack> {
  String _text = '';
  _GroundGlassPlate? _plate;
  AnimationController? _rack;

  @override
  void initState() {
    super.initState();
    _text = widget.controller.text;
    widget.controller.addListener(_onEdit);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final _GroundGlassScope? scope = _GroundGlassScope.of(context);
    _plate = scope?.plate;
    _rack = scope?.rack;
  }

  @override
  void didUpdateWidget(covariant GroundGlassQueryRack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_onEdit);
    _text = widget.controller.text;
    widget.controller.addListener(_onEdit);
  }

  void _onEdit() {
    if (widget.controller.text == _text) return;
    _text = widget.controller.text;
    final _GroundGlassPlate? plate = _plate;
    if (plate == null || !plate.enabled) return;
    _rack?.forward(from: 0);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onEdit);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _GroundGlassPlate extends ChangeNotifier {
  _GroundGlassPlate(this.sheetKey);

  final GlobalKey sheetKey;
  final Set<_RenderGroundGlassRegion> _regions = <_RenderGroundGlassRegion>{};
  Rect? focus;
  double rack = 0;
  bool enabled = true;
  bool _disposed = false;
  bool _geometryPending = false;

  RenderBox? get _sheet {
    final RenderObject? render = sheetKey.currentContext?.findRenderObject();
    return render is RenderBox && render.attached && render.hasSize ? render : null;
  }

  void register(_RenderGroundGlassRegion region) {
    if (_disposed) return;
    _regions.add(region);
    queueGeometry();
  }

  void unregister(_RenderGroundGlassRegion region) {
    _regions.remove(region);
    queueGeometry();
  }

  void queueGeometry() {
    if (_disposed || _geometryPending) return;
    _geometryPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _geometryPending = false;
      if (!_disposed) _syncFocus();
    });
  }

  Rect? _visibleBounds(_RenderGroundGlassRegion region) {
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

  void _syncFocus() {
    _RenderGroundGlassRegion? selected;
    for (final _RenderGroundGlassRegion region in _regions) {
      if (region.selected) selected = region;
    }
    final Rect? bounds = selected == null ? null : _visibleBounds(selected);
    if (bounds == focus) return;
    focus = bounds;
    notifyListeners();
  }

  void setRack(double value) {
    if (_disposed || (value - rack).abs() < 0.001) return;
    rack = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class _GroundGlassPainter extends CustomPainter {
  _GroundGlassPainter({
    required this.shader,
    required this.plate,
    required this.background,
    required this.foreground,
    required this.accent,
    required this.highContrast,
  }) : super(repaint: plate);

  final ui.FragmentShader? shader;
  final _GroundGlassPlate plate;
  final Color background;
  final Color foreground;
  final Color accent;
  final bool highContrast;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final Rect bounds = Offset.zero & size;
    if (highContrast || shader == null) {
      canvas.drawRect(bounds, Paint()..color = background);
      final Rect? focus = plate.focus;
      if (!highContrast && focus != null) {
        canvas.drawRect(
          focus,
          Paint()..color = accent.withValues(alpha: 0.08),
        );
      }
      return;
    }
    final Rect? focus = plate.focus;
    final ui.FragmentShader effect = shader!;
    // Float slots match ground_glass.frag.
    effect
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, focus?.center.dx ?? 0)
      ..setFloat(3, focus?.center.dy ?? 0)
      ..setFloat(4, (focus?.width ?? 0) * 0.5)
      ..setFloat(5, (focus?.height ?? 0) * 0.5)
      ..setFloat(6, plate.rack);
    int slot = 7;
    for (final Color color in <Color>[background, foreground, accent]) {
      effect
        ..setFloat(slot++, color.r)
        ..setFloat(slot++, color.g)
        ..setFloat(slot++, color.b);
    }
    canvas.drawRect(bounds, Paint()..shader = effect);
  }

  @override
  bool shouldRepaint(_GroundGlassPainter oldDelegate) =>
      shader != oldDelegate.shader ||
      plate != oldDelegate.plate ||
      background != oldDelegate.background ||
      foreground != oldDelegate.foreground ||
      accent != oldDelegate.accent ||
      highContrast != oldDelegate.highContrast;
}
