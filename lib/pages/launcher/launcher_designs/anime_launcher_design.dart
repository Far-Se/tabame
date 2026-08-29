part of '../launcher_design_builder.dart';

class AnimeLauncherFrame extends StatelessWidget {
  const AnimeLauncherFrame({
    super.key,
    required this.child,
    required this.surface,
    required this.accent,
    required this.onSurface,
    required this.resultCount,
  });

  final Widget child;
  final Color surface;
  final Color accent;
  final Color onSurface;
  final int resultCount;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool hasBackdrop = Design.hasBackdrop;
    final int cardAlpha = hasBackdrop ? (isDark ? 224 : 232) : 255;
    final int ribbonAlpha = hasBackdrop ? (isDark ? 216 : 224) : 255;
    final Color card = Color.alphaBlend(Colors.white.withAlpha(isDark ? 13 : 105), surface).withAlpha(cardAlpha);
    final Color ribbon = Color.alphaBlend(accent.withAlpha(isDark ? 76 : 48), surface).withAlpha(ribbonAlpha);
    return LauncherTheme(
      data: const LauncherThemeData(design: LauncherDesign.anime),
      child: Container(
        constraints: const BoxConstraints(minHeight: 360),
        decoration: LauncherDesign.anime.outerDecoration(surface: surface, accent: accent),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Design.borderRadius),
          child: Stack(
            children: <Widget>[
              if (Design.hasBackdrop) const StableBackdrop(),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _AnimeLauncherSparklePainter(accent: accent)),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    height: 25,
                    color: ribbon,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.auto_awesome_rounded, size: 13, color: onSurface.withAlpha(190)),
                        const Spacer(),
                        Icon(Icons.star_rounded, size: 10, color: onSurface.withAlpha(160)),
                        const SizedBox(width: 3),
                        Icon(Icons.star_rounded, size: 8, color: onSurface.withAlpha(120)),
                      ],
                    ),
                  ),
                  Container(color: card, child: child),
                  Container(
                    margin: const EdgeInsets.fromLTRB(9, 0, 9, 7),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: ribbon,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: accent.withAlpha(55)),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.favorite_rounded, size: 10, color: accent.withAlpha(210)),
                        const SizedBox(width: 6),
                        Text('ENTER  OPEN   •   ESC  CLOSE',
                            style: TextStyle(fontSize: 10, color: onSurface.withAlpha(150))),
                        const Spacer(),
                        Text(Globals.isLauncherPluginActive ? "PLUGIN" : '$resultCount MATCHES',
                            style: TextStyle(fontSize: 10, color: onSurface.withAlpha(150))),
                        DateTimeWidget(
                            padding: const EdgeInsets.only(left: 10),
                            style: TextStyle(fontSize: 10, color: onSurface.withAlpha(150))),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnimeSearchBar extends StatelessWidget {
  const _AnimeSearchBar({
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
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(9, 9, 9, 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(28),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withAlpha(60)),
      ),
      child: Row(
        children: <Widget>[
          dragHandle,
          const SizedBox(width: 8),
          Expanded(child: textField),
          if (trailingBadge != null) trailingBadge!,
          if (isSearching) ...<Widget>[
            const SizedBox(width: 7),
            SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 1.5, color: accent)),
          ],
        ],
      ),
    );
  }
}

class _AnimeLauncherSparklePainter extends CustomPainter {
  const _AnimeLauncherSparklePainter({required this.accent});

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    const List<Offset> spots = <Offset>[
      Offset(.08, .20),
      Offset(.91, .16),
      Offset(.18, .58),
      Offset(.84, .73),
      Offset(.47, .88),
    ];
    final Paint paint = Paint()..color = accent.withAlpha(68);
    for (final Offset spot in spots) {
      final Offset center = Offset(spot.dx * size.width, spot.dy * size.height);
      canvas.drawCircle(center, 1.5, paint);
      canvas.drawLine(center - const Offset(3, 0), center + const Offset(3, 0), paint..strokeWidth = .7);
      canvas.drawLine(center - const Offset(0, 3), center + const Offset(0, 3), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AnimeLauncherSparklePainter oldDelegate) => oldDelegate.accent != accent;
}
