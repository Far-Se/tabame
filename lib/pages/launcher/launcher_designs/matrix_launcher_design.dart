part of '../launcher_design_builder.dart';

BoxDecoration matrixLauncherOuterDecoration(Color surface, Color accent) => BoxDecoration(
      color: Colors.transparent,
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: Colors.black.withAlpha(70),
          blurRadius: 25,
          spreadRadius: -7,
          offset: const Offset(0, 12),
        ),
      ],
    );

/// Matrix mirrors the Quick Menu implementation: the backdrop, tint, and grid
/// are painted once, then clipped to the measured search and results cards.
class MatrixLauncherFrame extends StatefulWidget {
  const MatrixLauncherFrame({
    super.key,
    required this.searchChild,
    required this.resultsChild,
    required this.surface,
    required this.accent,
    required this.onSurface,
    required this.resultCount,
  });

  final Widget searchChild;
  final Widget resultsChild;
  final Color surface;
  final Color accent;
  final Color onSurface;
  final int resultCount;

  @override
  State<MatrixLauncherFrame> createState() => _MatrixLauncherFrameState();
}

class _MatrixLauncherFrameState extends State<MatrixLauncherFrame> {
  final GlobalKey _stackKey = GlobalKey();
  final GlobalKey _searchKey = GlobalKey();
  final GlobalKey _resultsKey = GlobalKey();
  List<Rect> _sectionRects = <Rect>[];
  bool _measurementScheduled = false;

  @override
  void initState() {
    super.initState();
    _scheduleMeasurement();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleMeasurement();
  }

  @override
  void didUpdateWidget(covariant MatrixLauncherFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleMeasurement();
  }

  void _scheduleMeasurement() {
    if (_measurementScheduled) return;
    _measurementScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurementScheduled = false;
      _updateSectionRects();
    });
  }

  void _updateSectionRects() {
    if (!mounted) return;
    final RenderBox? stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null) return;

    final List<Rect> next = <Rect>[];
    for (final GlobalKey key in <GlobalKey>[_searchKey, _resultsKey]) {
      final RenderBox? box = key.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) continue;
      next.add(box.localToGlobal(Offset.zero, ancestor: stackBox) & box.size);
    }

    if (_sameRects(next, _sectionRects)) return;
    setState(() => _sectionRects = next);
  }

  bool _sameRects(List<Rect> a, List<Rect> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final double radius = Design.borderRadius;
    final Color text = widget.onSurface;

    return LauncherTheme(
      data: const LauncherThemeData(design: LauncherDesign.matrix),
      child: Container(
        constraints: const BoxConstraints(minHeight: 360),
        decoration: matrixLauncherOuterDecoration(widget.surface, widget.accent),
        child: Stack(
          key: _stackKey,
          children: <Widget>[
            if (_sectionRects.isNotEmpty)
              Positioned.fill(
                child: ClipPath(
                  clipper: _MatrixLauncherSectionsClipper(_sectionRects, radius),
                  child: RepaintBoundary(
                    child: _MatrixLauncherGround(
                      surface: widget.surface,
                      accent: widget.accent,
                      radius: radius,
                    ),
                  ),
                ),
              ),
            NotificationListener<SizeChangedLayoutNotification>(
              onNotification: (SizeChangedLayoutNotification notification) {
                _scheduleMeasurement();
                return true;
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _sectionCard(
                      key: _searchKey,
                      radius: radius,
                      text: text,
                      label: 'SEARCH',
                      trailing: 'INPUT',
                      child: widget.searchChild,
                    ),
                    const SizedBox(height: 8),
                    _sectionCard(
                      key: _resultsKey,
                      radius: radius,
                      text: text,
                      label: 'RESULTS',
                      trailing: widget.resultCount.toString().padLeft(2, '0'),
                      child: widget.resultsChild,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({
    required GlobalKey key,
    required double radius,
    required Color text,
    required String label,
    required String trailing,
    required Widget child,
  }) {
    return SizeChangedLayoutNotifier(
      child: Container(
        key: key,
        decoration: BoxDecoration(
          color: text.withAlpha(8),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: text.withAlpha(18)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 6, 11, 0),
              child: Row(
                children: <Widget>[
                  Text(
                    label,
                    style: TextStyle(
                      color: widget.accent.withAlpha(170),
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Container(height: .5, color: text.withAlpha(22))),
                  const SizedBox(width: 8),
                  Text(
                    trailing,
                    style: TextStyle(
                      color: text.withAlpha(85),
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

class _MatrixLauncherGround extends StatelessWidget {
  const _MatrixLauncherGround({
    required this.surface,
    required this.accent,
    required this.radius,
  });

  final Color surface;
  final Color accent;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final List<double> points = Design.panelOpacityPoints;
    final List<double> stops = <double>[];
    final List<Color> colors = <Color>[];
    for (int i = 0; i < points.length; i += 2) {
      stops.add(points[i]);
      colors.add(Colors.white.withValues(alpha: points[i + 1]));
    }

    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (Rect bounds) => LinearGradient(
        begin: panelAlignmentMap[Design.panelOpacityBegin] ?? Alignment.topCenter,
        end: panelAlignmentMap[Design.panelOpacityEnd] ?? Alignment.bottomCenter,
        colors: colors,
        stops: stops,
      ).createShader(bounds),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            accent.withValues(alpha: Design.gradientAlpha / 255),
            surface.withValues(alpha: Design.backdropLauncher ? .72 : 1),
          ),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Stack(
          children: <Widget>[
            if (Design.backdropLauncher) const Positioned.fill(child: StableBackdrop()),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _MatrixLauncherGridPainter(accent.withValues(alpha: .07)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MatrixLauncherSearchBar extends StatelessWidget {
  const MatrixLauncherSearchBar({
    super.key,
    required this.accent,
    required this.onSurface,
    required this.dragHandle,
    required this.textField,
    required this.trailingBadge,
    required this.isSearching,
  });

  final Color accent;
  final Color onSurface;
  final Widget dragHandle;
  final Widget textField;
  final Widget? trailingBadge;
  final bool isSearching;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(11, 2, 11, 7),
        child: Row(
          children: <Widget>[
            dragHandle,
            const SizedBox(width: 8),
            Text(
              '>_',
              style: TextStyle(
                color: accent,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: textField),
            if (trailingBadge != null) trailingBadge!,
            if (isSearching) ...<Widget>[
              const SizedBox(width: 7),
              SizedBox.square(
                dimension: 12,
                child: CircularProgressIndicator(strokeWidth: 1.2, color: accent),
              ),
            ],
          ],
        ),
      );
}

class MatrixLauncherHeader extends StatelessWidget {
  const MatrixLauncherHeader({
    super.key,
    required this.label,
    required this.accent,
  });

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 5, 10, 2),
        child: Text(
          '[ ${label.toUpperCase()} ]',
          style: TextStyle(
            color: accent.withAlpha(150),
            fontSize: Design.baseFontSize - 1,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.4,
          ),
        ),
      );
}

class _MatrixLauncherSectionsClipper extends CustomClipper<Path> {
  const _MatrixLauncherSectionsClipper(this.rects, this.radius);

  final List<Rect> rects;
  final double radius;

  @override
  Path getClip(Size size) {
    final Path path = Path();
    for (final Rect rect in rects) {
      path.addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    }
    return path;
  }

  @override
  bool shouldReclip(covariant _MatrixLauncherSectionsClipper oldClipper) =>
      oldClipper.radius != radius || !_sameRectLists(oldClipper.rects, rects);

  bool _sameRectLists(List<Rect> a, List<Rect> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _MatrixLauncherGridPainter extends CustomPainter {
  const _MatrixLauncherGridPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = .5;
    for (double x = 0; x < size.width; x += 20) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += 20) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MatrixLauncherGridPainter oldDelegate) => oldDelegate.color != color;
}
