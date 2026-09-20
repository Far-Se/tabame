part of '../launcher_design_builder.dart';

BoxDecoration _zenOuterDecoration(Color surface, Color accent) {
  // Soft "dawn" wash over the forced sage surface; big, diffuse shadow.
  return BoxDecoration(
    borderRadius: BorderRadius.circular(Design.borderRadius),
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[
        Color.alphaBlend(Colors.white.withAlpha(22), surface),
        surface,
      ],
    ),
    border: Border.all(color: accent.withAlpha(40)),
    boxShadow: <BoxShadow>[
      BoxShadow(
        color: Colors.black.withAlpha(28),
        blurRadius: 48,
        spreadRadius: -8,
        offset: const Offset(0, 20),
      ),
    ],
  );
}

class _ZenSearchBar extends StatelessWidget {
  const _ZenSearchBar(this.content);

  final _LauncherSearchBarContent content;

  @override
  Widget build(BuildContext context) {
    final Color accent = LauncherTheme.accentOf(context);
    // A soft floating pill with generous margin — room to breathe.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: accent.withAlpha(18),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: accent.withAlpha(36)),
        ),
        child: Row(
          children: <Widget>[
            content.dragHandle,
            const SizedBox(width: 12),
            Expanded(
              child: _LauncherSearchField(content),
            ),
            if (content.isSearching)
              Padding(
                padding: const EdgeInsets.only(left: 10),
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.6, color: accent.withAlpha(140)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The calm outer frame — soft dawn wash, big rounding, and a faint
/// rolling-hills horizon footer.
class ZenLauncherFrame extends StatelessWidget {
  const ZenLauncherFrame({super.key, required this.child, this.resultCount = 0});

  final Widget child;
  final int resultCount;

  @override
  Widget build(BuildContext context) {
    final Color surface = Theme.of(context).colorScheme.surface;
    final Color accent = LauncherTheme.accentOf(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 340),
      decoration: _zenOuterDecoration(surface, accent),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Design.borderRadius),
        child: Stack(
          children: <Widget>[
            if (Design.hasBackdrop) const StableBackdrop(),
            // Soft dawn glow drifting in from the top-left.
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(-0.7, -0.9),
                      radius: 1.3,
                      colors: <Color>[accent.withAlpha(22), accent.withAlpha(0)],
                    ),
                  ),
                ),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                child,
                _ZenFooter(resultCount: resultCount),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ZenFooter extends StatelessWidget {
  const _ZenFooter({required this.resultCount});

  final int resultCount;

  @override
  Widget build(BuildContext context) {
    final Color accent = LauncherTheme.accentOf(context);
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      width: double.infinity,
      height: 30,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: <Widget>[
          // Rolling-hills horizon.
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _ZenHillsPainter(accent)),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    Globals.isLauncherPluginActive ? "PLUGIN" : (resultCount == 0 ? 'breathe' : '$resultCount found'),
                    style: ZenTokens.soft(
                      fontSize: Design.baseFontSize - 1,
                      color: onSurface.withAlpha(120),
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1.2,
                    ),
                  ),
                  DateTimeWidget(
                    padding: const EdgeInsets.only(left: 10),
                    style: ZenTokens.soft(
                      fontSize: Design.baseFontSize - 1,
                      color: onSurface.withAlpha(120),
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Two soft overlapping hills along the bottom edge — a quiet horizon.
class _ZenHillsPainter extends CustomPainter {
  const _ZenHillsPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final double h = size.height;
    final double w = size.width;

    final Paint back = Paint()
      ..color = color.withAlpha(24)
      ..style = PaintingStyle.fill;
    final Path backHill = Path()
      ..moveTo(0, h)
      ..lineTo(0, h * 0.62)
      ..quadraticBezierTo(w * 0.28, h * 0.22, w * 0.55, h * 0.55)
      ..quadraticBezierTo(w * 0.8, h * 0.85, w, h * 0.45)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(backHill, back);

    final Paint front = Paint()
      ..color = color.withAlpha(40)
      ..style = PaintingStyle.fill;
    final Path frontHill = Path()
      ..moveTo(0, h)
      ..lineTo(0, h * 0.82)
      ..quadraticBezierTo(w * 0.4, h * 0.5, w * 0.7, h * 0.78)
      ..quadraticBezierTo(w * 0.88, h * 0.92, w, h * 0.72)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(frontHill, front);
  }

  @override
  bool shouldRepaint(covariant _ZenHillsPainter oldDelegate) => oldDelegate.color != color;
}
