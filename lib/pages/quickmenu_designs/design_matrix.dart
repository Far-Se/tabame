import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/settings.dart';
import '../../models/util/theme_colors.dart';
import '../../widgets/quickmenu/bottom_bar.dart';
import 'design_backdrop_stable.dart';
import '../../widgets/quickmenu/info_bar.dart';
import '../../widgets/quickmenu/libre_stats.dart';
import '../../widgets/quickmenu/task_bar.dart';
import '../../widgets/quickmenu/taskbar_stats.dart';
import '../../widgets/quickmenu/top_bar.dart';

class MainMenuMatrixWidget extends StatefulWidget {
  const MainMenuMatrixWidget({
    super.key,
  });

  @override
  State<MainMenuMatrixWidget> createState() => _MainMenuMatrixWidgetState();
}

class _MainMenuMatrixWidgetState extends State<MainMenuMatrixWidget> {
  final GlobalKey _stackKey = GlobalKey();
  final GlobalKey _topKey = GlobalKey();
  final GlobalKey _taskKey = GlobalKey();
  final GlobalKey _listKey = GlobalKey();
  final GlobalKey _bottomKey = GlobalKey();

  List<Rect> _itemRects = <Rect>[];
  late _GridPainter _gridPainter;

  @override
  void initState() {
    super.initState();
    _gridPainter = _GridPainter(Design.accent.withValues(alpha: 0.07));
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateClip());
  }

  void _updateClip() {
    if (!mounted) return;
    final RenderBox? stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null) return;

    final List<Rect> newRects = <Rect>[];
    final List<GlobalKey> keys = <GlobalKey>[_topKey, _taskKey, _listKey, _bottomKey];

    for (final GlobalKey key in keys) {
      final RenderBox? box = key.currentContext?.findRenderObject() as RenderBox?;
      if (box != null) {
        final Offset offset = box.localToGlobal(Offset.zero, ancestor: stackBox);
        newRects.add(offset & box.size);
      }
    }

    if (!listEquals(_itemRects, newRects)) {
      setState(() {
        _itemRects = newRects;
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateClip());
  }

  @override
  Widget build(BuildContext context) {
    // Trigger measurement on every build to handle layout changes (e.g. tray expansion)
    // WidgetsBinding.instance.addPostFrameCallback((_) => _updateClip());

    final ThemeData theme = Theme.of(context);
    final Color accent = Design.accent;
    final Color surface = theme.colorScheme.surface;

    final List<double> points = Design.panelOpacityPoints;
    final List<double> stops = <double>[];
    final List<Color> colors = <Color>[];
    for (int i = 0; i < points.length; i += 2) {
      stops.add(points[i]);
      colors.add(Colors.white.withValues(alpha: points[i + 1]));
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: 250,
        maxHeight: MediaQuery.of(context).size.height - 20,
      ),
      child: Stack(
        key: _stackKey,
        children: <Widget>[
          // Background Layer (Clipped to floating cards)
          if (_itemRects.isNotEmpty)
            Positioned.fill(
              child: ClipPath(
                clipper: MatrixFloatingClipper(_itemRects, Design.borderRadius),
                child: RepaintBoundary(
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (Rect bounds) {
                      return LinearGradient(
                        begin: panelAlignmentMap[Design.panelOpacityBegin] ?? Alignment.topCenter,
                        end: panelAlignmentMap[Design.panelOpacityEnd] ?? Alignment.bottomCenter,
                        colors: colors,
                        stops: stops,
                      ).createShader(bounds);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Color.alphaBlend(
                          accent.withValues(alpha: Design.gradientAlpha / 255.0),
                          surface.withValues(alpha: user.activeBackdropPath.isNotEmpty ? 0.7 : 1.0),
                        ),
                        borderRadius: BorderRadius.circular(Design.borderRadius),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(Design.borderRadius),
                        child: Stack(
                          children: <Widget>[
                            if (Design.hasBackdrop) const StableBackdrop(),
                            // Technical Grid Overlay
                            Positioned.fill(
                              child: IgnorePointer(
                                child: CustomPaint(
                                  painter: _gridPainter, //_GridPainter(accent.withValues(alpha: 0.07)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          // Interaction Layer (Provides the frames for measurement)
          RepaintBoundary(
            child: NotificationListener<SizeChangedLayoutNotification>(
              onNotification: (SizeChangedLayoutNotification notification) {
                WidgetsBinding.instance.addPostFrameCallback((_) => _updateClip());
                return true;
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: user.quickActionsAtBottom && !user.bottomBarOnTop
                      ? _buildBottomQuickActionsSections()
                      : _buildDefaultSections(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildDefaultSections() {
    return <Widget>[
      _sectionCard(key: _topKey, child: user.bottomBarOnTop ? const PinnedAndTrayList() : const TopBar()),
      const SizedBox(height: 8),
      _sectionCard(key: _taskKey, child: const TaskBar()),
      if (!user.bottomBarOnTop) ...<Widget>[
        const SizedBox(height: 8),
        _sectionCard(
            key: _listKey,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: const PinnedAndTrayList())
      ],
      //_sectionCard(key: _listKey, child: const PinnedAndTrayList(), padding: const EdgeInsets.symmetric(vertical: 2)),
      const SizedBox(height: 8),
      _sectionCard(
          key: _bottomKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (user.taskManagerStats) const TaskbarStats(withTopDivider: false),
              if (user.libreStats) const LibreStats(withTopDivider: false),
              const SizedBox(height: 6),
              const BottomBar(),
            ],
          )),
    ];
  }

  List<Widget> _buildBottomQuickActionsSections() {
    return <Widget>[
      _sectionCard(key: _taskKey, child: const TaskBar()),
      const SizedBox(height: 8),
      _sectionCard(
        key: _listKey,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const PinnedAndTrayList(),
            const SizedBox(height: 6),
            if (user.taskManagerStats) const TaskbarStats(),
            if (user.libreStats) const LibreStats(),
            const BottomBar(),
          ],
        ),
      ),
    ];
  }

  // 3. In _sectionCard, capture the radius from a local variable
  // so it's read fresh on every build pass
  Widget _sectionCard({
    required Key key,
    required Widget child,
    EdgeInsets? padding,
  }) {
    final double radius = Design.borderRadius;
    final Color textColor = Design.text;
    return SizeChangedLayoutNotifier(
      child: Container(
        key: key,
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: textColor.withAlpha(8),
          borderRadius: BorderRadius.circular(radius), // <-- uses local var
          border: Border.all(
            color: textColor.withAlpha(18),
          ),
        ),
        child: child,
      ),
    );
  }
}

// 1. Pass borderRadius into MatrixFloatingClipper
class MatrixFloatingClipper extends CustomClipper<Path> {
  final List<Rect> rects;
  final double borderRadius; // <-- add this

  MatrixFloatingClipper(this.rects, this.borderRadius); // <-- add this

  @override
  Path getClip(Size size) {
    final Path path = Path();
    for (final Rect rect in rects) {
      path.addRRect(RRect.fromRectAndRadius(rect, Radius.circular(borderRadius)));
    }
    return path;
  }

  @override
  bool shouldReclip(covariant MatrixFloatingClipper oldClipper) {
    return !listEquals(oldClipper.rects, rects) || oldClipper.borderRadius != borderRadius; // <-- add radius check
  }
}

class _GridPainter extends CustomPainter {
  final Color color;
  _GridPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 0.5;

    const double step = 20;
    for (double i = 0; i < size.width; i += step) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += step) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
