part of '../launcher_design_builder.dart';

class _ClassicSearchBar extends StatelessWidget {
  const _ClassicSearchBar({
    required this.surface,
    required this.accent,
    required this.onSurface,
    required this.dragHandle,
    required this.textField,
    required this.trailingBadge,
    required this.isSearching,
  });

  final Color surface;
  final Color accent;
  final Color onSurface;
  final Widget dragHandle;
  final Widget textField;
  final Widget? trailingBadge;
  final bool isSearching;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: surface.withAlpha(100),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withAlpha(32)),
      ),
      child: Row(
        children: <Widget>[
          dragHandle,
          const SizedBox(width: 10),
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
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: accent.withAlpha(100),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Serene search bar
// ---------------------------------------------------------------------------

class ClassicLauncherFrame extends StatelessWidget {
  const ClassicLauncherFrame({
    super.key,
    required this.child,
    required this.surface,
    required this.accent,
    Color? onSurface,
    int? resultCount,
  });

  final Widget child;
  final Color surface;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return LauncherTheme(
      data: const LauncherThemeData(design: LauncherDesign.classic),
      child: Container(
        constraints: const BoxConstraints(minHeight: 360),
        decoration: LauncherDesign.classic.outerDecoration(
          surface: surface,
          accent: accent,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Design.borderRadius),
          child: Stack(
            children: <Widget>[
              if (Design.hasBackdrop) const StableBackdrop(),
              child,
              Positioned(
                bottom: 0,
                right: 0,
                child: DateTimeWidget(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Command search bar — a terminal input line with a chevron prompt.
// ---------------------------------------------------------------------------
