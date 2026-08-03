part of '../launcher_design_builder.dart';

BoxDecoration outrun2LauncherOuterDecoration(Color surface, Color accent) => BoxDecoration(
      borderRadius: BorderRadius.circular(Design.borderRadius),
      color: surface,
      border: Border.all(color: accent, width: 1.2),
      boxShadow: <BoxShadow>[
        BoxShadow(color: accent.withAlpha(62), blurRadius: 16, spreadRadius: -4),
        BoxShadow(color: Colors.black.withAlpha(85), blurRadius: 26, spreadRadius: -7, offset: const Offset(0, 13)),
      ],
    );

class Outrun2LauncherFrame extends StatelessWidget {
  const Outrun2LauncherFrame(
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
    final Color palm = Color.alphaBlend(Colors.black.withAlpha(198), surface);
    return LauncherTheme(
      data: const LauncherThemeData(design: LauncherDesign.outrun2),
      child: Container(
        constraints: const BoxConstraints(minHeight: 360),
        decoration: outrun2LauncherOuterDecoration(surface, accent),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Design.borderRadius),
          child: Stack(children: <Widget>[
            Positioned.fill(child: ColoredBox(color: surface.withAlpha(250))),
            if (Design.hasBackdrop) const Positioned.fill(child: StableBackdrop()),
            Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 110,
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        gradient:
                            LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: <Color>[
                  const Color(0xFFFF00AA).withAlpha(isDark ? 76 : 52),
                  const Color(0xFFFF7700).withAlpha(isDark ? 46 : 30),
                  const Color(0xFFFFD700).withAlpha(12),
                  Colors.transparent,
                ], stops: const <double>[
                  0,
                  .35,
                  .65,
                  1
                ])))),
            Positioned(
                top: 19,
                left: 0,
                right: 0,
                child: Center(
                    child: Container(
                        width: 62,
                        height: 62,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(colors: <Color>[
                              const Color(0xFFFFD700).withAlpha(isDark ? 90 : 62),
                              const Color(0xFFFF00AA).withAlpha(isDark ? 38 : 24),
                              Colors.transparent,
                            ]))))),
            Positioned.fill(
                child: IgnorePointer(
                    child:
                        CustomPaint(painter: _Outrun2LauncherGridPainter(color: accent.withAlpha(isDark ? 60 : 44))))),
            Positioned(
                top: 8,
                left: 7,
                width: 48,
                height: 75,
                child: CustomPaint(painter: _Outrun2LauncherPalmPainter(color: palm))),
            Positioned(
                top: 14,
                right: 10,
                width: 42,
                height: 66,
                child: CustomPaint(painter: _Outrun2LauncherPalmPainter(color: palm))),
            Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(13, 7, 13, 0),
                child: Row(children: <Widget>[
                  Text('OUTRUN',
                      style: TextStyle(
                          color: accent,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          fontStyle: FontStyle.italic,
                          letterSpacing: 2.4,
                          shadows: <Shadow>[Shadow(color: accent.withAlpha(150), blurRadius: 8)])),
                  const SizedBox(width: 8),
                  Expanded(child: Container(height: 1, color: accent.withAlpha(110))),
                  const SizedBox(width: 8),
                  Text(Globals.isLauncherPluginActive ? "PLUGIN" : '$resultCount // 86',
                      style: TextStyle(
                          color: onSurface.withAlpha(145),
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.4)),
                ]),
              ),
              child,
            ]),
            Positioned.fill(
                child: IgnorePointer(
                    child: CustomPaint(painter: _Outrun2LauncherScanPainter(onSurface.withAlpha(isDark ? 11 : 7))))),
          ]),
        ),
      ),
    );
  }
}

class Outrun2LauncherSearchBar extends StatelessWidget {
  const Outrun2LauncherSearchBar(
      {super.key,
      required this.surface,
      required this.accent,
      required this.dragHandle,
      required this.textField,
      required this.trailingBadge,
      required this.isSearching});
  final Color surface;
  final Color accent;
  final Widget dragHandle;
  final Widget textField;
  final Widget? trailingBadge;
  final bool isSearching;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(12, 9, 12, 5),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: surface.withAlpha(190),
          border: Border.all(color: accent, width: 1.2),
          boxShadow: <BoxShadow>[BoxShadow(color: accent.withAlpha(65), blurRadius: 10, spreadRadius: -2)],
        ),
        child: Row(children: <Widget>[
          dragHandle,
          const SizedBox(width: 8),
          CustomPaint(size: const Size(8, 8), painter: _Outrun2LauncherChevronPainter(accent)),
          const SizedBox(width: 8),
          Expanded(child: textField),
          if (trailingBadge != null) trailingBadge!,
          if (isSearching) ...<Widget>[
            const SizedBox(width: 7),
            SizedBox.square(dimension: 13, child: CircularProgressIndicator(strokeWidth: 1.5, color: accent))
          ],
        ]),
      );
}

class Outrun2LauncherHeader extends StatelessWidget {
  const Outrun2LauncherHeader({super.key, required this.label, required this.accent});
  final String label;
  final Color accent;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(17, 8, 14, 3),
        child: Row(children: <Widget>[
          CustomPaint(size: const Size(8, 8), painter: _Outrun2LauncherChevronPainter(accent)),
          const SizedBox(width: 6),
          Text(label.toUpperCase(),
              style: TextStyle(
                  color: accent,
                  fontSize: Design.baseFontSize - 1,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.2,
                  shadows: <Shadow>[Shadow(color: accent.withAlpha(120), blurRadius: 8)])),
          const SizedBox(width: 8),
          Expanded(
              child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                      gradient: LinearGradient(colors: <Color>[accent.withAlpha(140), Colors.transparent])))),
        ]),
      );
}

class _Outrun2LauncherChevronPainter extends CustomPainter {
  const _Outrun2LauncherChevronPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(
      Path()
        ..moveTo(0, size.height / 2)
        ..lineTo(size.width, 0)
        ..lineTo(size.width, size.height)
        ..close(),
      Paint()..color = color);
  @override
  bool shouldRepaint(covariant _Outrun2LauncherChevronPainter oldDelegate) => oldDelegate.color != color;
}

class _Outrun2LauncherGridPainter extends CustomPainter {
  const _Outrun2LauncherGridPainter({required this.color});
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke;
    final double horizon = size.height * .28, center = size.width / 2;
    for (int i = -6; i <= 6; i++) {
      final double t = i / 6;
      canvas.drawLine(Offset(center, horizon), Offset(center + t * size.width * 1.1, size.height),
          paint..strokeWidth = i == 0 ? 1.2 : .7);
    }
    for (int i = 0; i < 18; i++) {
      final double t = i / 18;
      final double y = size.height - (size.height - horizon) * (1 - math.pow(t, 3).toDouble());
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint..strokeWidth = (1 - t * .6).clamp(.4, 1));
    }
  }

  @override
  bool shouldRepaint(covariant _Outrun2LauncherGridPainter oldDelegate) => oldDelegate.color != color;
}

class _Outrun2LauncherPalmPainter extends CustomPainter {
  const _Outrun2LauncherPalmPainter({required this.color});
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = color;
    final double w = size.width, h = size.height;
    canvas.drawPath(
        Path()
          ..moveTo(w * .65, h)
          ..quadraticBezierTo(w * .55, h * .55, w * .48, h * .18)
          ..lineTo(w * .42, h * .18)
          ..quadraticBezierTo(w * .50, h * .55, w * .58, h)
          ..close(),
        paint);
    for (int i = 0; i < 7; i++) {
      final double angle = -math.pi / 2 + (i - 3) * .35, len = h * .38, cx = w * .45, cy = h * .18;
      canvas.drawPath(
          Path()
            ..moveTo(cx, cy)
            ..quadraticBezierTo(cx + math.cos(angle - .25) * len * .5, cy + math.sin(angle - .25) * len * .5,
                cx + math.cos(angle) * len, cy + math.sin(angle) * len)
            ..lineTo(cx + math.cos(angle + .18) * len * .88, cy + math.sin(angle + .18) * len * .88)
            ..quadraticBezierTo(cx + math.cos(angle + .08) * len * .48, cy + math.sin(angle + .08) * len * .48, cx, cy)
            ..close(),
          paint);
    }
  }

  @override
  bool shouldRepaint(covariant _Outrun2LauncherPalmPainter oldDelegate) => oldDelegate.color != color;
}

class _Outrun2LauncherScanPainter extends CustomPainter {
  const _Outrun2LauncherScanPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (double y = 0; y < size.height; y += 3) canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
  }

  @override
  bool shouldRepaint(covariant _Outrun2LauncherScanPainter oldDelegate) => oldDelegate.color != color;
}
