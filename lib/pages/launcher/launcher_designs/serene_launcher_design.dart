part of '../launcher_design_builder.dart';

BoxDecoration _sereneOuterDecoration(Color surface) {
  return BoxDecoration(
    borderRadius: BorderRadius.circular(Design.borderRadius),
    color: surface.withAlpha(230),
    border: Border.all(color: Colors.white.withAlpha(18)),
    boxShadow: <BoxShadow>[
      BoxShadow(
        color: Colors.black.withAlpha(60),
        blurRadius: 40,
        spreadRadius: -4,
        offset: const Offset(0, 16),
      ),
      BoxShadow(
        color: Colors.black.withAlpha(14),
        blurRadius: 6,
        offset: const Offset(0, 2),
      ),
    ],
  );
}

class _SereneSearchBar extends StatelessWidget {
  const _SereneSearchBar(this.content);

  final _LauncherSearchBarContent content;

  @override
  Widget build(BuildContext context) {
    final Color surface = Theme.of(context).colorScheme.surface;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
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
                content.dragHandle,
                const SizedBox(width: 10),
                Expanded(
                  child: _LauncherSearchField(content),
                ),
                if (content.isSearching)
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

/// The frosted-glass outer frame used by the Serene design.
///
class SereneLauncherFrame extends StatelessWidget {
  const SereneLauncherFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Color surface = Theme.of(context).colorScheme.surface;
    final bool hasBackdrop = Design.hasBackdrop;

    return ClipRRect(
      borderRadius: BorderRadius.circular(Design.borderRadius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          constraints: const BoxConstraints(minHeight: 360),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Design.borderRadius),
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
      ),
    );
  }
}
