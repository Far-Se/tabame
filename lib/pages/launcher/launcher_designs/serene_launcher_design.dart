part of '../launcher_design_builder.dart';

class _SereneSearchBar extends StatelessWidget {
  const _SereneSearchBar({
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
      decoration: BoxDecoration(
        color: surface.withAlpha(70),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
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
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: onSurface.withAlpha(80),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Hairline separator — replaces the boxy card border
          Divider(
            height: 1,
            thickness: 1,
            indent: 0,
            endIndent: 0,
            color: onSurface.withAlpha(18),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SereneLauncherFrame
// ---------------------------------------------------------------------------

/// The frosted-glass outer frame used by the Serene design.
///
/// This widget:
/// 1. Applies backdrop blur + frosted surface.
/// 2. Injects a [LauncherTheme] with [LauncherDesign.serene] so that all
///    descendant result-item widgets automatically inherit the Serene variant
///    without needing an explicit parameter.
class SereneLauncherFrame extends StatelessWidget {
  const SereneLauncherFrame({
    super.key,
    required this.child,
    required this.accent,
  });

  final Widget child;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final Color surface = Theme.of(context).colorScheme.surface;
    final bool hasBackdrop = Design.backdropType.isNotEmpty && user.activeBackdropPath.isNotEmpty;

    // Wrap in LauncherTheme so descendants can read the design without a
    // parameter chain.
    return LauncherTheme(
      data: const LauncherThemeData(design: LauncherDesign.serene),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            constraints: const BoxConstraints(minHeight: 360),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: surface.withAlpha(hasBackdrop ? 180 : 240),
              border: Border.all(color: Colors.white.withAlpha(18)),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withAlpha(60),
                  blurRadius: 40,
                  spreadRadius: -4,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Design.backdropLauncher
                ? Stack(
                    children: <Widget>[
                      const StableBackdrop(),
                      child,
                    ],
                  )
                : child,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ClassicLauncherFrame
// ---------------------------------------------------------------------------

/// The glass-card outer frame used by the Classic design.
///
/// Mirrors [SereneLauncherFrame]: wraps [child] in a [LauncherTheme] with
/// [LauncherDesign.classic] so descendants inherit the correct variant.
