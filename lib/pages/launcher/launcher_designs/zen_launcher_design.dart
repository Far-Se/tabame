part of '../launcher_design_builder.dart';

class _ZenSearchBar extends StatelessWidget {
  const _ZenSearchBar({
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
            dragHandle,
            const SizedBox(width: 12),
            Expanded(
              child: Stack(
                alignment: Alignment.centerRight,
                children: <Widget>[
                  textField,
                  if (trailingBadge != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: trailingBadge!,
                    ),
                ],
              ),
            ),
            if (isSearching)
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
  const ZenLauncherFrame({
    super.key,
    required this.child,
    required this.surface,
    required this.accent,
    required this.onSurface,
    this.resultCount = 0,
  });

  final Widget child;
  final Color surface;
  final Color accent;
  final Color onSurface;
  final int resultCount;

  @override
  Widget build(BuildContext context) {
    return LauncherTheme(
      data: const LauncherThemeData(design: LauncherDesign.zen),
      child: Container(
        constraints: const BoxConstraints(minHeight: 340),
        decoration: LauncherDesign.zen.outerDecoration(surface: surface, accent: accent),
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
                  _ZenFooter(accent: accent, onSurface: onSurface, resultCount: resultCount),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ZenFooter extends StatelessWidget {
  const _ZenFooter({required this.accent, required this.onSurface, required this.resultCount});

  final Color accent;
  final Color onSurface;
  final int resultCount;

  @override
  Widget build(BuildContext context) {
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

// ---------------------------------------------------------------------------
// Glass (iOS Liquid Glass) — translucent capsule search field + layered glass
// frame with specular highlights and an accent refraction glow.
// ---------------------------------------------------------------------------
