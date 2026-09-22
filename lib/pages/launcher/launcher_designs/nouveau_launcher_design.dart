part of '../launcher_design_builder.dart';

BoxDecoration _nouveauOuterDecoration() => BoxDecoration(
      color: NouveauTokens.background,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: NouveauTokens.accent.withValues(alpha: 0.65)),
    );

class _NouveauSearchBar extends StatelessWidget {
  const _NouveauSearchBar(this.content);
  final _LauncherSearchBarContent content;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(40, 22, 40, 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Color.alphaBlend(NouveauTokens.foreground.withValues(alpha: 0.025), NouveauTokens.background),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: NouveauTokens.border),
        ).withLauncherCorners(),
        child: Row(children: <Widget>[
          content.dragHandle,
          const SizedBox(width: 12),
          Expanded(child: _LauncherSearchField(content)),
          if (content.isSearching)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: NouveauTokens.brass),
              ),
            ),
        ]),
      );
}

class NouveauLauncherFrame extends StatefulWidget {
  const NouveauLauncherFrame({super.key, required this.child, required this.resultCount});
  final Widget child;
  final int resultCount;

  @override
  State<NouveauLauncherFrame> createState() => _NouveauLauncherFrameState();
}

class _NouveauLauncherFrameState extends State<NouveauLauncherFrame>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver, WindowListener {
  late final AnimationController _motion = AnimationController(vsync: this, duration: const Duration(seconds: 15));
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
    _allowed = true; //!MediaQuery.disableAnimationsOf(context) && TickerMode.valuesOf(context).enabled;
    _syncMotion();
  }

  void _syncMotion() {
    if (_allowed && _visible && _lifecycleVisible) {
      if (!_motion.isAnimating) _motion.repeat();
    } else {
      _motion.stop();
      if (!_allowed) _motion.value = 0;
    }
  }

  @override
  void onWindowFocus() {
    _visibilityRevision++;
    _visible = true;
    _syncMotion();
  }

  // A visible launcher can be unfocused (for example beside a native dialog).
  // Focus is not visibility: only stop when it is actually hidden/minimized.
  Future<void> _refreshVisibility() async {
    final int revision = ++_visibilityRevision;
    final bool visible = await windowManager.isVisible();
    final bool minimized = await windowManager.isMinimized();
    if (!mounted || revision != _visibilityRevision) return;
    _visible = visible && !minimized;
    _syncMotion();
  }

  @override
  void onWindowBlur() => _refreshVisibility();

  @override
  void onWindowMinimize() {
    _visibilityRevision++;
    _visible = false;
    _syncMotion();
  }

  @override
  void onWindowRestore() => onWindowFocus();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleVisible = state == AppLifecycleState.resumed || state == AppLifecycleState.inactive;
    if (_lifecycleVisible) _refreshVisibility();
    _syncMotion();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LauncherSurface(
        decoration: _nouveauOuterDecoration(),
        child: Stack(children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 14, 28, 12),
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              Flexible(fit: FlexFit.loose, child: widget.child),
              Padding(
                padding: const EdgeInsets.fromLTRB(36, 6, 36, 0),
                child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                  Row(children: <Widget>[
                    Expanded(child: Divider(height: 1, color: NouveauTokens.border)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 9),
                      child: _NouveauDiamond(color: NouveauTokens.brass),
                    ),
                    Expanded(child: Divider(height: 1, color: NouveauTokens.border)),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: <Widget>[
                    Text('${widget.resultCount} ${widget.resultCount == 1 ? 'result' : 'results'}',
                        style: NouveauTokens.font(size: 11, color: NouveauTokens.dim)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        reverse: true,
                        child: Row(children: <Widget>[
                          _hint('↑ ↓', 'Navigate'),
                          const SizedBox(width: 14),
                          _hint('↵', 'Open'),
                          const SizedBox(width: 14),
                          _hint('Ctrl K', 'Actions'),
                        ]),
                      ),
                    ),
                  ]),
                ]),
              ),
            ]),
          ),
          // Only the corner drawings repaint; typing and result layout are
          // independent of the decorative clock. The overlay never takes input.
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: RepaintBoundary(
                  child: CustomPaint(
                    willChange: true,
                    painter: _NouveauOrnaments(
                      motion: _motion,
                      ink: NouveauTokens.accent,
                      brass: NouveauTokens.brass,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ]),
      );

  Widget _hint(String key, String label) => Row(children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          decoration: BoxDecoration(
            color: NouveauTokens.accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(key, style: NouveauTokens.font(size: 10, weight: FontWeight.w500)),
        ),
        const SizedBox(width: 5),
        Text(label, style: NouveauTokens.font(size: 11, color: NouveauTokens.dim)),
      ]);
}

class _NouveauDiamond extends StatelessWidget {
  const _NouveauDiamond({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 7,
        height: 9,
        child: CustomPaint(painter: _NouveauDiamondPainter(color)),
      );
}

class _NouveauDiamondPainter extends CustomPainter {
  const _NouveauDiamondPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(size.width / 2, 0)
        ..lineTo(size.width, size.height / 2)
        ..lineTo(size.width / 2, size.height)
        ..lineTo(0, size.height / 2)
        ..close(),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(_NouveauDiamondPainter oldDelegate) => oldDelegate.color != color;
}

/// Hand-drawn botanical corners: anchored stems, paired leaves, inward scrolls
/// and small brass lozenges. Curves sway and line tips extend/retract far enough
/// to be visible within a few seconds, without moving the corner anchors.
/// Every component is periodic across the full 24-second cycle.
class _NouveauOrnaments extends CustomPainter {
  _NouveauOrnaments({required this.motion, required this.ink, required this.brass}) : super(repaint: motion);
  final Animation<double> motion;
  final Color ink;
  final Color brass;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final double scale = math.min(1.0, math.min(size.width / 360, size.height / 310));
    final double phase = motion.value * math.pi * 2;
    for (int corner = 0; corner < 4; corner++) {
      final bool right = corner.isOdd;
      final bool bottom = corner >= 2;
      // Smaller lower ornaments leave the final result and footer unobstructed.
      final double cornerScale = scale * (bottom ? 0.65 : 1);
      canvas.save();
      canvas.translate(right ? size.width : 0, bottom ? size.height : 0);
      canvas.scale(right ? -cornerScale : cornerScale, bottom ? -cornerScale : cornerScale);
      _corner(canvas, phase + corner * math.pi / 2, scroll: right != bottom);
      canvas.restore();
    }
  }

  void _corner(Canvas canvas, double phase, {required bool scroll}) {
    final double sway = math.sin(phase) * 6;
    final double curl = math.cos(phase) * 5;
    final double tip = math.sin(phase + math.pi / 4) * 12;
    final Paint pen = Paint()
      ..color = ink.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    void draw(Path path) => canvas.drawPath(path, pen);
    // Keep the corner anchors fixed; animate the actual ink geometry, including
    // the long rules, so the motion is legible without a shimmer or a flash.
    draw(Path()
      ..moveTo(12, 139 + tip)
      ..lineTo(12, 92)
      ..cubicTo(12, 70, 36 + sway, 73, 35 + sway, 49)
      ..cubicTo(34, 29 + curl, 51, 11, 77, 11)
      ..lineTo(125 + tip, 11));
    draw(Path()
      ..moveTo(19, 117 - tip * 0.6)
      ..lineTo(19, 93)
      ..cubicTo(19, 77, 44 + sway, 73, 42 + sway, 49)
      ..cubicTo(42, 33, 56, 18, 79, 18)
      ..lineTo(105 - tip * 0.7, 18));
    draw(Path()
      ..moveTo(88 + tip * 0.35, 25)
      ..lineTo(76, 25)
      ..quadraticBezierTo(63, 25, 56, 32));

    if (scroll) {
      draw(Path()
        ..moveTo(34 + sway, 53)
        ..cubicTo(35, 40, 12, 44, 12, 27)
        ..cubicTo(12, 9, 35 + curl, 12, 33 + curl, 26)
        ..cubicTo(32, 37, 20, 33, 22, 26)
        ..quadraticBezierTo(23, 22, 27, 25));
      draw(Path()
        ..moveTo(23, 86)
        ..cubicTo(43, 73, 34, 59 + curl, 24, 64 + curl)
        ..quadraticBezierTo(17, 67, 21, 73));
    } else {
      // Two pointed leaves with a central vein, echoing the reference's
      // botanical linework without filling the surrounding paper.
      draw(Path()
        ..moveTo(34 + sway, 54)
        ..cubicTo(14, 55, 10, 42, 12, 34)
        ..cubicTo(27, 34, 34 + sway, 43, 34 + sway, 54)
        ..close());
      draw(Path()
        ..moveTo(19, 41)
        ..quadraticBezierTo(24, 48 + curl, 34 + sway, 54));
      draw(Path()
        ..moveTo(40 + sway, 37)
        ..cubicTo(32, 28, 34, 18, 39, 12)
        ..cubicTo(46 + curl, 20, 44, 30, 40 + sway, 37)
        ..close());
      draw(Path()
        ..moveTo(39, 20)
        ..lineTo(40 + sway, 37));
      draw(Path()
        ..moveTo(24, 91)
        ..cubicTo(20, 74, 39, 73, 34, 65)
        ..cubicTo(30, 59, 19, 61, 21, 69));
    }

    canvas.drawCircle(Offset(51 + sway * 0.4, 53), 4.5, pen);
    final Paint gold = Paint()
      ..color = brass
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    canvas.drawPath(
        Path()
          ..moveTo(62, 36)
          ..lineTo(66, 41)
          ..lineTo(62, 46)
          ..lineTo(58, 41)
          ..close(),
        gold);
    gold.style = PaintingStyle.fill;
    canvas.drawCircle(Offset(19, 127 - tip * 0.6), 1.8, gold);
    canvas.drawCircle(Offset(12, 148 + tip), 1.5, gold);
    canvas.drawCircle(Offset(25 + sway * 0.3, 103), 1.5, pen..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(_NouveauOrnaments oldDelegate) =>
      oldDelegate.motion != motion || oldDelegate.ink != ink || oldDelegate.brass != brass;
}
