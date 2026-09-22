part of '../launcher_design_builder.dart';

BoxDecoration _techOuterDecoration(Color surface, Color accent) => BoxDecoration(
      borderRadius: BorderRadius.circular(Design.borderRadius),
      color: surface.withAlpha(246),
      border: Border.all(color: accent.withAlpha(48)),
      boxShadow: <BoxShadow>[
        BoxShadow(color: Colors.black.withAlpha(65), blurRadius: 28, spreadRadius: -8, offset: const Offset(0, 12)),
      ],
    );

class TechLauncherFrame extends StatelessWidget {
  const TechLauncherFrame({super.key, required this.child, required this.resultCount});

  final Widget child;
  final int resultCount;

  @override
  Widget build(BuildContext context) {
    final Color surface = Theme.of(context).colorScheme.surface;
    final Color accent = LauncherTheme.accentOf(context);
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final bool isDark = ThemeData.estimateBrightnessForColor(surface) == Brightness.dark;
    return LauncherSurface(
      constraints: const BoxConstraints(minHeight: 360),
      decoration: _techOuterDecoration(surface, accent),
      child: Stack(
        children: <Widget>[
          Positioned.fill(child: ColoredBox(color: surface.withAlpha(246))),
          if (Design.hasBackdrop) const Positioned.fill(child: StableBackdrop()),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _TechLauncherDotPainter(accent.withAlpha(isDark ? 22 : 14))),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: onSurface.withAlpha(isDark ? 8 : 5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: accent.withAlpha(38)),
              ).withLauncherCorners(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (user.launcherShowTitlebar) _TechLauncherStatus(resultCount: resultCount),
                  child,
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(child: CustomPaint(painter: _TechLauncherHudPainter(accent: accent))),
          ),
        ],
      ),
    );
  }
}

class _TechLauncherStatus extends StatelessWidget {
  const _TechLauncherStatus({required this.resultCount});
  final int resultCount;
  @override
  Widget build(BuildContext context) {
    final Color accent = LauncherTheme.accentOf(context);
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 0),
      child: Row(
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text('LAUNCH CONTROL',
              style: TextStyle(
                  color: onSurface.withAlpha(140), fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 1.6)),
          const Spacer(),
          Text(Globals.isLauncherPluginActive ? "PLUGIN" : '$resultCount OBJECTS',
              style: TextStyle(
                  color: accent.withAlpha(175), fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
          DateTimeWidget(
              padding: const EdgeInsets.only(left: 10),
              style: TextStyle(
                  color: accent.withAlpha(175), fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
        ],
      ),
    );
  }
}

class _TechLauncherSearchBar extends StatelessWidget {
  const _TechLauncherSearchBar(this.content);

  final _LauncherSearchBarContent content;

  @override
  Widget build(BuildContext context) {
    final Color accent = LauncherTheme.accentOf(context);
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: onSurface.withAlpha(8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withAlpha(52)),
      ).withLauncherCorners(),
      child: Row(children: <Widget>[
        content.dragHandle,
        const SizedBox(width: 9),
        Expanded(child: content.textField),
        if (content.trailingBadge != null) content.trailingBadge!,
        if (content.isSearching) ...<Widget>[
          const SizedBox(width: 7),
          SizedBox.square(dimension: 13, child: CircularProgressIndicator(strokeWidth: 1.5, color: accent))
        ],
      ]),
    );
  }
}

class TechLauncherHeader extends StatelessWidget {
  const TechLauncherHeader({super.key, required this.label, required this.accent});
  final String label;
  final Color accent;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 9, 16, 3),
        child: Row(children: <Widget>[
          Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(3)).withLauncherCorners()),
          const SizedBox(width: 6),
          Text(label.toUpperCase(),
              style: TextStyle(
                  color: accent.withAlpha(170),
                  fontSize: Design.baseFontSize - 2,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2)),
          const SizedBox(width: 10),
          Expanded(
              child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                      gradient: LinearGradient(colors: <Color>[accent.withAlpha(54), Colors.transparent])))),
        ]),
      );
}

class _TechLauncherDotPainter extends CustomPainter {
  const _TechLauncherDotPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = color;
    for (double x = 16; x < size.width; x += 16) {
      for (double y = 16; y < size.height; y += 16) canvas.drawCircle(Offset(x, y), 1.2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TechLauncherDotPainter oldDelegate) => oldDelegate.color != color;
}

class _TechLauncherHudPainter extends CustomPainter {
  const _TechLauncherHudPainter({required this.accent});
  final Color accent;
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = accent.withAlpha(145)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final Path path = Path()
      ..moveTo(size.width - 42, 4)
      ..lineTo(size.width - 4, 4)
      ..lineTo(size.width - 4, 40)
      ..moveTo(42, size.height - 4)
      ..lineTo(4, size.height - 4)
      ..lineTo(4, size.height - 40);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TechLauncherHudPainter oldDelegate) => oldDelegate.accent != accent;
}
