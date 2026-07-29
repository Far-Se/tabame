part of '../launcher_design_builder.dart';

BoxDecoration cyberLauncherOuterDecoration(Color surface, Color accent) => BoxDecoration(
      color: surface.withAlpha(248),
      border: Border.all(color: accent.withAlpha(70), width: .8),
      boxShadow: <BoxShadow>[
        BoxShadow(color: Colors.black.withAlpha(90), blurRadius: 26, spreadRadius: -7, offset: const Offset(0, 13))
      ],
    );

class CyberLauncherFrame extends StatelessWidget {
  const CyberLauncherFrame(
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
      data: const LauncherThemeData(design: LauncherDesign.cyber),
      child: Container(
        constraints: const BoxConstraints(minHeight: 360),
        decoration: cyberLauncherOuterDecoration(surface, accent),
        child: ClipPath(
          clipper: _CyberLauncherClipper(),
          child: Stack(children: <Widget>[
            Positioned.fill(child: ColoredBox(color: surface.withAlpha(248))),
            if (Design.backdropLauncher) const Positioned.fill(child: StableBackdrop()),
            Positioned.fill(
                child: IgnorePointer(
                    child: CustomPaint(painter: _CyberLauncherGridPainter(accent.withAlpha(isDark ? 16 : 10))))),
            Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(13, 7, 13, 0),
                child: Row(children: <Widget>[
                  Text('「 TABAME // LAUNCHER 』',
                      style: TextStyle(color: accent, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
                  const Spacer(),
                  Container(width: 5, height: 5, color: accent),
                  const SizedBox(width: 5),
                  Text('SYNC $resultCount',
                      style: TextStyle(
                          color: onSurface.withAlpha(125),
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.1)),
                ]),
              ),
              child,
            ]),
            Positioned.fill(
                child: IgnorePointer(
                    child: CustomPaint(painter: _CyberLauncherFramePainter(neon: accent, isDark: isDark)))),
          ]),
        ),
      ),
    );
  }
}

class CyberLauncherSearchBar extends StatelessWidget {
  const CyberLauncherSearchBar(
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
        margin: const EdgeInsets.fromLTRB(12, 9, 12, 5),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: accent.withAlpha(12),
          border: Border(left: BorderSide(color: accent, width: 2), bottom: BorderSide(color: accent.withAlpha(72))),
        ),
        child: Row(children: <Widget>[
          dragHandle,
          const SizedBox(width: 8),
          Text('SYS>', style: TextStyle(color: accent, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.1)),
          const SizedBox(width: 8),
          Expanded(child: textField),
          if (trailingBadge != null) trailingBadge!,
          if (isSearching) ...<Widget>[
            const SizedBox(width: 7),
            SizedBox.square(dimension: 12, child: CircularProgressIndicator(strokeWidth: 1.3, color: accent))
          ],
        ]),
      );
}

class CyberLauncherHeader extends StatelessWidget {
  const CyberLauncherHeader({super.key, required this.label, required this.accent});
  final String label;
  final Color accent;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 7, 14, 2),
        child: Row(children: <Widget>[
          Text('「', style: TextStyle(color: accent, fontSize: Design.baseFontSize - 1, fontWeight: FontWeight.w700)),
          const SizedBox(width: 4),
          Text(label.toUpperCase(),
              style: TextStyle(
                  color: accent, fontSize: Design.baseFontSize - 2, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
          const SizedBox(width: 4),
          Text('』', style: TextStyle(color: accent, fontSize: Design.baseFontSize - 1, fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          Expanded(
              child: Container(
                  height: .75,
                  decoration: BoxDecoration(
                      gradient: LinearGradient(colors: <Color>[accent.withAlpha(175), Colors.transparent])))),
        ]),
      );
}

class _CyberLauncherClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => Path()
    ..moveTo(0, 8)
    ..lineTo(8, 0)
    ..lineTo(size.width - 15, 0)
    ..lineTo(size.width, 15)
    ..lineTo(size.width, size.height - 8)
    ..lineTo(size.width - 8, size.height)
    ..lineTo(15, size.height)
    ..lineTo(0, size.height - 15)
    ..close();
  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _CyberLauncherGridPainter extends CustomPainter {
  const _CyberLauncherGridPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = .5;
    for (double x = 0; x < size.width; x += 12) canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    for (double y = 0; y < size.height; y += 12) canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
  }

  @override
  bool shouldRepaint(covariant _CyberLauncherGridPainter oldDelegate) => oldDelegate.color != color;
}

class _CyberLauncherFramePainter extends CustomPainter {
  const _CyberLauncherFramePainter({required this.neon, required this.isDark});
  final Color neon;
  final bool isDark;
  @override
  void paint(Canvas canvas, Size size) {
    final Paint line = Paint()
      ..color = neon.withAlpha(isDark ? 205 : 150)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(size.width - 22, 5), Offset(size.width - 5, 5), line);
    canvas.drawLine(Offset(size.width - 5, 5), Offset(size.width - 5, 22), line);
    canvas.drawLine(Offset(22, size.height - 5), Offset(5, size.height - 5), line);
    canvas.drawLine(Offset(5, size.height - 5), Offset(5, size.height - 22), line);
    final Paint node = Paint()..color = neon;
    canvas.drawCircle(Offset(size.width - 5, 5), 2, node);
    canvas.drawCircle(Offset(5, size.height - 5), 2, node);
  }

  @override
  bool shouldRepaint(covariant _CyberLauncherFramePainter oldDelegate) =>
      oldDelegate.neon != neon || oldDelegate.isDark != isDark;
}
