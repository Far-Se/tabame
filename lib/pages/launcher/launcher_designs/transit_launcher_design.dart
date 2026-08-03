part of '../launcher_design_builder.dart';

class _TransitSearchBar extends StatelessWidget {
  const _TransitSearchBar({
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 14, 9),
          child: Row(
            children: <Widget>[
              // Line roundel — the metro-line bullet (also the drag handle).
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: accent, width: 2.4),
                ),
                child: dragHandle,
              ),
              const SizedBox(width: 11),
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
                  padding: const EdgeInsets.only(left: 8),
                  child: SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(strokeWidth: 1.6, color: accent.withAlpha(170)),
                  ),
                ),
            ],
          ),
        ),
        // The line-color band — the identity stripe of a station sign.
        Container(height: 5, color: accent),
      ],
    );
  }
}

/// Dashed fare-zone boundary line used by the Transit section header.
class _TransitZonePainter extends CustomPainter {
  const _TransitZonePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    const double dash = 5;
    const double gap = 5;
    final double y = size.height / 2;
    for (double x = 0; x < size.width; x += dash + gap) {
      canvas.drawLine(Offset(x, y), Offset((x + dash).clamp(0, size.width), y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TransitZonePainter oldDelegate) => oldDelegate.color != color;
}

/// The station sign — forced signage palette, a flat enamel plate with the
/// accent as the metro-line color, and a platform strip along the bottom.
class TransitLauncherFrame extends StatelessWidget {
  const TransitLauncherFrame({
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
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return LauncherTheme(
      data: const LauncherThemeData(design: LauncherDesign.transit),
      child: Container(
        constraints: const BoxConstraints(minHeight: 360),
        decoration: LauncherDesign.transit.outerDecoration(surface: surface, accent: accent),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Design.borderRadius),
          child: Stack(
            children: <Widget>[
              if (Design.hasBackdrop) const StableBackdrop(),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  child,
                  _TransitFooter(accent: accent, resultCount: resultCount, isDark: isDark),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The platform strip: boarding hints on the left, the stop count on the
/// right — all in signage lettering.
class _TransitFooter extends StatelessWidget {
  const _TransitFooter({required this.accent, required this.resultCount, required this.isDark});

  final Color accent;
  final int resultCount;
  final bool isDark;

  Widget _hint(String key, String caption) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          key,
          style: TransitTokens.sign(
            fontSize: Design.baseFontSize - 1,
            color: accent,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
        Text(
          ' $caption',
          style: TransitTokens.sign(
            fontSize: Design.baseFontSize - 1,
            color: TransitTokens.dim(isDark),
            fontWeight: FontWeight.w600,
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      decoration: BoxDecoration(
        color: TransitTokens.chrome(isDark),
        border: Border(top: BorderSide(color: accent.withAlpha(90))),
      ),
      child: Row(
        children: <Widget>[
          _hint('↵', 'BOARD'),
          const SizedBox(width: 14),
          _hint('→', 'LINES'),
          const SizedBox(width: 14),
          _hint('ESC', 'EXIT'),
          const Spacer(),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: accent, width: 2),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            Globals.isLauncherPluginActive ? "PLUGIN" : (resultCount == 1 ? '1 STOP' : '$resultCount STOPS'),
            style: TransitTokens.sign(
              fontSize: Design.baseFontSize - 1,
              color: TransitTokens.dim(isDark),
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Fluent (Windows 11) — a WinUI text box with the accent focus underline, a
// mica frame, and a Start-menu-style footer strip. Results render as WinUI
// list items with the accent selection pill (see LauncherResultRow._buildFluent).
// ---------------------------------------------------------------------------
