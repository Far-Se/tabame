part of '../launcher_design_builder.dart';

BoxDecoration vectorLauncherOuterDecoration(Color surface, Color accent) => BoxDecoration(
      borderRadius: BorderRadius.circular(Design.borderRadius),
      color: surface.withAlpha(247),
      border: Border.all(
          color: ThemeData.estimateBrightnessForColor(surface) == Brightness.dark
              ? Colors.white.withAlpha(24)
              : Colors.black.withAlpha(28),
          width: .5),
      boxShadow: <BoxShadow>[
        BoxShadow(color: Colors.black.withAlpha(76), blurRadius: 24, spreadRadius: -6, offset: const Offset(0, 10))
      ],
    );

class VectorLauncherFrame extends StatelessWidget {
  const VectorLauncherFrame(
      {super.key,
      required this.child,
      required this.surface,
      required this.accent,
      required this.onSurface,
      required this.resultCount});
  final Widget child;
  final Color surface;
  final Color accent;
  final Color onSurface;
  final int resultCount;
  @override
  Widget build(BuildContext context) {
    final bool isDark = surface.computeLuminance() < .5;
    return LauncherTheme(
      data: const LauncherThemeData(design: LauncherDesign.vector),
      child: Container(
        constraints: const BoxConstraints(minHeight: 360),
        decoration: vectorLauncherOuterDecoration(surface, accent),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Design.borderRadius),
          child: Stack(children: <Widget>[
            Positioned.fill(child: ColoredBox(color: surface.withAlpha(247))),
            if (Design.hasBackdrop) const Positioned.fill(child: StableBackdrop()),
            Positioned.fill(
                child: IgnorePointer(
                    child: CustomPaint(painter: _VectorLauncherScanPainter(onSurface.withAlpha(isDark ? 12 : 9))))),
            Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 7, 12, 0),
                child: Row(children: <Widget>[
                  Container(width: 4, height: 4, color: accent),
                  const SizedBox(width: 6),
                  Text('VEC / 01',
                      style: TextStyle(color: accent, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
                  const SizedBox(width: 7),
                  Text('TARGET INDEX',
                      style: TextStyle(
                          color: onSurface.withAlpha(120), fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 2)),
                  const Spacer(),
                  Text(resultCount.toString().padLeft(3, '0'),
                      style: TextStyle(
                          color: accent.withAlpha(190), fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
                ]),
              ),
              child,
            ]),
            Positioned.fill(
                child: IgnorePointer(
                    child: CustomPaint(
                        painter: _VectorLauncherReticlePainter(accent: accent, tick: onSurface.withAlpha(100))))),
          ]),
        ),
      ),
    );
  }
}

class VectorLauncherSearchBar extends StatelessWidget {
  const VectorLauncherSearchBar(
      {super.key,
      required this.accent,
      required this.onSurface,
      required this.dragHandle,
      required this.textField,
      required this.trailingBadge,
      required this.isSearching});
  final Color accent;
  final Color onSurface;
  final Widget dragHandle;
  final Widget textField;
  final Widget? trailingBadge;
  final bool isSearching;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(10, 8, 10, 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration:
            BoxDecoration(color: accent.withAlpha(13), border: Border.all(color: accent.withAlpha(62), width: .6)),
        child: Row(children: <Widget>[
          dragHandle,
          const SizedBox(width: 8),
          Text('›', style: TextStyle(color: accent, fontSize: 20, height: 1)),
          const SizedBox(width: 7),
          Expanded(child: textField),
          if (trailingBadge != null) trailingBadge!,
          if (isSearching) ...<Widget>[
            const SizedBox(width: 7),
            SizedBox.square(dimension: 12, child: CircularProgressIndicator(strokeWidth: 1.3, color: accent))
          ],
        ]),
      );
}

class VectorLauncherHeader extends StatelessWidget {
  const VectorLauncherHeader({super.key, required this.label, required this.accent});
  final String label;
  final Color accent;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 3),
        child: Row(children: <Widget>[
          Container(width: 3.5, height: 3.5, color: accent),
          const SizedBox(width: 5),
          Text('02',
              style: TextStyle(
                  color: accent, fontSize: Design.baseFontSize - 1, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
          const SizedBox(width: 6),
          Text(label.toUpperCase(),
              style: TextStyle(
                  color: accent.withAlpha(155),
                  fontSize: Design.baseFontSize - 1.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2.2)),
          const SizedBox(width: 8),
          Expanded(child: Container(height: .5, color: accent.withAlpha(42))),
        ]),
      );
}

class _VectorLauncherScanPainter extends CustomPainter {
  const _VectorLauncherScanPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = .5;
    for (double y = 1.5; y < size.height; y += 3) canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
  }

  @override
  bool shouldRepaint(covariant _VectorLauncherScanPainter oldDelegate) => oldDelegate.color != color;
}

class _VectorLauncherReticlePainter extends CustomPainter {
  const _VectorLauncherReticlePainter({required this.accent, required this.tick});
  final Color accent;
  final Color tick;
  @override
  void paint(Canvas canvas, Size size) {
    const double inset = 2.5, len = 11;
    final double right = size.width - inset, bottom = size.height - inset;
    final Paint bracket = Paint()
      ..color = accent
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    final Path corners = Path()
      ..moveTo(inset, inset + len)
      ..lineTo(inset, inset)
      ..lineTo(inset + len, inset)
      ..moveTo(right - len, inset)
      ..lineTo(right, inset)
      ..lineTo(right, inset + len)
      ..moveTo(right, bottom - len)
      ..lineTo(right, bottom)
      ..lineTo(right - len, bottom)
      ..moveTo(inset + len, bottom)
      ..lineTo(inset, bottom)
      ..lineTo(inset, bottom - len);
    canvas.drawPath(corners, bracket);
    final Paint tickPaint = Paint()
      ..color = tick
      ..strokeWidth = 1;
    final double cx = size.width / 2, cy = size.height / 2;
    canvas.drawLine(Offset(cx, inset), Offset(cx, inset + 5), tickPaint);
    canvas.drawLine(Offset(cx, bottom - 5), Offset(cx, bottom), tickPaint);
    canvas.drawLine(Offset(inset, cy), Offset(inset + 5, cy), tickPaint);
    canvas.drawLine(Offset(right - 5, cy), Offset(right, cy), tickPaint);
  }

  @override
  bool shouldRepaint(covariant _VectorLauncherReticlePainter oldDelegate) =>
      oldDelegate.accent != accent || oldDelegate.tick != tick;
}
