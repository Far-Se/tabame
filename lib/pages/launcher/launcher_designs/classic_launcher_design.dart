part of '../launcher_design_builder.dart';

BoxDecoration _classicOuterDecoration(Color surface, Color accent) {
  return BoxDecoration(
    borderRadius: BorderRadius.circular(Design.borderRadius),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[
        surface.withAlpha(245),
        Color.alphaBlend(accent.withAlpha(24), surface),
        Color.alphaBlend(accent.withAlpha(10), surface),
      ],
    ),
    border: Border.all(color: accent.withAlpha(28)),
    boxShadow: <BoxShadow>[
      BoxShadow(
        color: Colors.black.withAlpha(18),
        blurRadius: 20,
        offset: const Offset(0, 8),
      ),
    ],
  );
}

class _ClassicSearchBar extends StatelessWidget {
  const _ClassicSearchBar(this.content);

  final _LauncherSearchBarContent content;

  @override
  Widget build(BuildContext context) {
    final Color surface = Theme.of(context).colorScheme.surface;
    final Color accent = LauncherTheme.accentOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: surface.withAlpha(100),
        // borderRadius: BorderRadius.circular(14),
        borderRadius: BorderRadius.circular(Design.borderRadius),
        border: Border.all(color: accent.withAlpha(32)),
      ).withLauncherCorners(),
      child: Row(
        children: <Widget>[
          content.dragHandle,
          const SizedBox(width: 10),
          Expanded(
            child: _LauncherSearchField(content),
          ),
          if (content.isSearching)
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

class ClassicLauncherFrame extends StatelessWidget {
  const ClassicLauncherFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Color surface = Theme.of(context).colorScheme.surface;
    final Color accent = LauncherTheme.accentOf(context);
    return LauncherSurface(
      constraints: const BoxConstraints(minHeight: 360),
      decoration: _classicOuterDecoration(surface, accent),
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
    );
  }
}
