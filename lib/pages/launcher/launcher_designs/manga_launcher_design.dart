part of '../launcher_design_builder.dart';

BoxDecoration _mangaOuterDecoration(Color surface) {
  final Color ink = ThemeData.estimateBrightnessForColor(surface) == Brightness.dark
      ? const Color(0xFFF2EFE8)
      : const Color(0xFF181719);
  return BoxDecoration(
    borderRadius: BorderRadius.circular(Design.borderRadius),
    color: surface,
    border: Border.all(color: ink.withAlpha(230), width: 2.2),
    boxShadow: <BoxShadow>[BoxShadow(color: Colors.black.withAlpha(105), blurRadius: 0, offset: const Offset(6, 6))],
  );
}

class MangaLauncherFrame extends StatelessWidget {
  const MangaLauncherFrame({super.key, required this.child, required this.resultCount});
  final Widget child;
  final int resultCount;
  @override
  Widget build(BuildContext context) {
    final Color surface = Theme.of(context).colorScheme.surface;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final double intensity = Design.gradientAlpha.clamp(0, 255) / 255;
    return Container(
      constraints: const BoxConstraints(minHeight: 360),
      decoration: _mangaOuterDecoration(surface),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Design.borderRadius),
        child: Stack(children: <Widget>[
          Positioned.fill(child: ColoredBox(color: surface.withAlpha(250))),
          if (Design.hasBackdrop) const Positioned.fill(child: StableBackdrop()),
          Positioned.fill(
              child: IgnorePointer(
                  child: CustomPaint(
                      painter: _MangaLauncherHalftonePainter(onSurface.withValues(alpha: .05 + intensity * .05))))),
          Positioned.fill(
              child: IgnorePointer(
                  child: Container(
                      margin: const EdgeInsets.all(3.5),
                      decoration: BoxDecoration(
                          border: Border.all(color: onSurface.withAlpha(75), width: .9),
                          borderRadius: BorderRadius.circular(11))))),
          Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            if (user.launcherShowTitlebar)
              _MangaLauncherMasthead(ink: onSurface, paper: surface, resultCount: resultCount),
            child,
          ]),
        ]),
      ),
    );
  }
}

class _MangaLauncherMasthead extends StatelessWidget {
  const _MangaLauncherMasthead({required this.ink, required this.paper, required this.resultCount});
  final Color ink;
  final Color paper;
  final int resultCount;
  @override
  Widget build(BuildContext context) {
    final Color accent = LauncherTheme.accentOf(context);
    return Container(
      height: 28,
      color: ink,
      child: Stack(fit: StackFit.expand, children: <Widget>[
        CustomPaint(painter: _MangaLauncherSpeedLinesPainter(paper.withAlpha(35))),
        Row(children: <Widget>[
          const SizedBox(width: 10),
          CustomPaint(size: const Size(14, 14), painter: _MangaLauncherBurstPainter(accent)),
          const SizedBox(width: 8),
          Transform(
            alignment: Alignment.centerLeft,
            transform: Matrix4.skewX(-.18),
            child: Text('TABAME!',
                style: TextStyle(
                    color: paper,
                    fontSize: Design.baseFontSize + 2,
                    fontWeight: FontWeight.w700,
                    fontStyle: FontStyle.italic,
                    letterSpacing: 1.1)),
          ),
          const Spacer(),
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            color: accent,
            child: Text(Globals.isLauncherPluginActive ? "PLUGIN" : 'CH. ${resultCount.toString().padLeft(2, '0')}',
                style: TextStyle(
                    color: paper, fontSize: Design.baseFontSize - 3, fontWeight: FontWeight.w700, letterSpacing: 1.3)),
          ),
          DateTimeWidget(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              style: TextStyle(
                  color: paper, fontSize: Design.baseFontSize - 3, fontWeight: FontWeight.w700, letterSpacing: 1.3)),
        ]),
      ]),
    );
  }
}

class _MangaLauncherSearchBar extends StatelessWidget {
  const _MangaLauncherSearchBar(this.content);

  final _LauncherSearchBarContent content;

  @override
  Widget build(BuildContext context) {
    final Color surface = Theme.of(context).colorScheme.surface;
    final Color accent = LauncherTheme.accentOf(context);
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      margin: const EdgeInsets.fromLTRB(9, 8, 9, 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration:
          BoxDecoration(color: surface.withAlpha(220), border: Border.all(color: onSurface.withAlpha(220), width: 1.4)),
      child: Row(children: <Widget>[
        content.dragHandle,
        const SizedBox(width: 8),
        Container(
            color: onSurface,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Text('FIND',
                style: TextStyle(color: surface, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.2))),
        const SizedBox(width: 8),
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

class MangaLauncherHeader extends StatelessWidget {
  const MangaLauncherHeader({super.key, required this.label, required this.accent});
  final String label;
  final Color accent;
  @override
  Widget build(BuildContext context) {
    final Color ink = Theme.of(context).colorScheme.onSurface;
    final Color paper = Theme.of(context).colorScheme.surface;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 3),
      child: Row(children: <Widget>[
        Transform(
          alignment: Alignment.center,
          transform: Matrix4.skewX(-.3),
          child: Container(
              color: ink,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Text(label.toUpperCase(),
                  style: TextStyle(
                      color: paper,
                      fontSize: Design.baseFontSize - 2,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.6))),
        ),
        const SizedBox(width: 7),
        Expanded(child: Container(height: 1.4, color: ink.withAlpha(78))),
        const SizedBox(width: 6),
        CustomPaint(size: const Size(10, 10), painter: _MangaLauncherBurstPainter(accent)),
      ]),
    );
  }
}

class _MangaLauncherBurstPainter extends CustomPainter {
  const _MangaLauncherBurstPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double outer = size.width / 2, inner = outer * .42;
    final Path path = Path();
    for (int i = 0; i < 16; i++) {
      final double radius = i.isEven ? outer : inner, angle = i * math.pi / 8;
      final Offset point = Offset(center.dx + radius * math.cos(angle), center.dy + radius * math.sin(angle));
      if (i == 0)
        path.moveTo(point.dx, point.dy);
      else
        path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path..close(), Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _MangaLauncherBurstPainter oldDelegate) => oldDelegate.color != color;
}

class _MangaLauncherSpeedLinesPainter extends CustomPainter {
  const _MangaLauncherSpeedLinesPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1.1;
    final Offset origin = Offset(size.width, 0);
    for (int i = 0; i < 12; i++) {
      final double angle = math.pi * (.55 + i / 12 * .42), len = size.width * .95;
      canvas.drawLine(origin, Offset(origin.dx + len * math.cos(angle), origin.dy + len * math.sin(angle)), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MangaLauncherSpeedLinesPainter oldDelegate) => oldDelegate.color != color;
}

class _MangaLauncherHalftonePainter extends CustomPainter {
  const _MangaLauncherHalftonePainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = color;
    int row = 0;
    for (double y = 2.75; y < size.height; y += 5.5) {
      final double offset = row.isEven ? 0 : 2.75;
      for (double x = 2.75 + offset; x < size.width; x += 5.5) canvas.drawCircle(Offset(x, y), .8, paint);
      row++;
    }
  }

  @override
  bool shouldRepaint(covariant _MangaLauncherHalftonePainter oldDelegate) => oldDelegate.color != color;
}
