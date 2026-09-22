part of '../launcher_design_builder.dart';

BoxDecoration _newCastOuterDecoration(Color surface) {
  final bool isDark = ThemeData.estimateBrightnessForColor(surface) == Brightness.dark;
  return BoxDecoration(
    borderRadius: BorderRadius.circular(14),
    color: surface.withAlpha(236),
    border: Border.all(color: (isDark ? Colors.white : Colors.black).withAlpha(10)),
    boxShadow: <BoxShadow>[
      BoxShadow(
        color: Colors.black.withAlpha(72),
        blurRadius: 28,
        spreadRadius: -5,
        offset: const Offset(0, 14),
      ),
    ],
  );
}

class _RaycastSearchBar extends StatelessWidget {
  const _RaycastSearchBar(this.content);

  final _LauncherSearchBarContent content;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          height: 56,
          color: RaycastTokens.deepSurface(isDark).withAlpha(80),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
            child: Row(
              children: <Widget>[
                content.dragHandle,
                const SizedBox(width: 10),
                Expanded(
                  child: _LauncherSearchField(content),
                ),
                if (content.isSearching)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, right: 8),
                    child: SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: RaycastTokens.muted(isDark).withAlpha(150),
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
        Divider(
          height: 1,
          thickness: 1,
          color: RaycastTokens.divider(isDark),
        ),
      ],
    );
  }
}

class RaycastLauncherFrame extends StatelessWidget {
  const RaycastLauncherFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Color surface = Theme.of(context).colorScheme.surface;
    final bool isDark = ThemeData.estimateBrightnessForColor(surface) == Brightness.dark;
    final Color sheen = isDark ? Colors.white : Colors.black;

    return LauncherSurface(
      decoration: _newCastOuterDecoration(surface),
      child: Stack(
        children: <Widget>[
          if (Design.hasBackdrop) const StableBackdrop(),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: const Alignment(-0.18, 0.38),
                    colors: <Color>[
                      sheen.withAlpha(isDark ? 26 : 10),
                      sheen.withAlpha(isDark ? 8 : 4),
                      Colors.transparent,
                    ],
                    stops: const <double>[0, 0.28, 1],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: -74,
            right: -34,
            width: 250,
            height: 170,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.topRight,
                    radius: 1.0,
                    colors: <Color>[sheen.withAlpha(isDark ? 10 : 5), Colors.transparent],
                  ),
                ),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              child,
              const _RaycastFooter(),
            ],
          ),
        ],
      ),
    );
  }
}

class _RaycastFooter extends StatelessWidget {
  const _RaycastFooter();

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final TextStyle labelStyle = RaycastTokens.ui(
      fontSize: 13,
      color: RaycastTokens.dim(isDark),
      fontWeight: FontWeight.w500,
      height: 1.0,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: <Widget>[
                Text(
                  '⌘',
                  style: RaycastTokens.mono(
                    fontSize: 15,
                    color: RaycastTokens.muted(isDark),
                    fontWeight: FontWeight.w500,
                    height: 1.0,
                  ),
                ),
                const SizedBox(width: 7),
                Text('Displays', style: labelStyle),
                const Spacer(),
                Icon(Icons.keyboard_return_rounded, size: 14, color: RaycastTokens.muted(isDark)),
                const SizedBox(width: 5),
                Text('Open', style: labelStyle),
                const SizedBox(width: 16),
                Container(width: 1, height: 15, color: RaycastTokens.divider(isDark)),
                const SizedBox(width: 16),
                Text('Actions', style: labelStyle),
                const SizedBox(width: 7),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                  decoration: BoxDecoration(
                    color: RaycastTokens.badge(isDark),
                    borderRadius: BorderRadius.circular(4),
                  ).withLauncherCorners(),
                  child: Text(
                    '⌘K',
                    style: RaycastTokens.mono(
                      fontSize: 11,
                      color: RaycastTokens.muted(isDark),
                      fontWeight: FontWeight.w500,
                      height: 1.0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Divider(
          height: 1,
          thickness: 1,
          color: RaycastTokens.divider(isDark),
        ),
      ],
    );
  }
}
