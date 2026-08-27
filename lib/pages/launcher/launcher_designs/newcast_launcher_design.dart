part of '../launcher_design_builder.dart';

class _RaycastSearchBar extends StatelessWidget {
  const _RaycastSearchBar({
    required this.dragHandle,
    required this.textField,
    required this.trailingBadge,
    required this.isSearching,
  });

  final Widget dragHandle;
  final Widget textField;
  final Widget? trailingBadge;
  final bool isSearching;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          height: 56,
          color: RaycastTokens.deepSurface.withAlpha(80),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
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
                    padding: const EdgeInsets.only(left: 8, right: 8),
                    child: SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: RaycastTokens.muted.withAlpha(150),
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                // const _RaycastQuickAiButton(),
              ],
            ),
          ),
        ),
        const Divider(
          height: 1,
          thickness: 1,
          color: RaycastTokens.divider,
        ),
      ],
    );
  }
}

// ignore: unused_element
class _RaycastQuickAiButton extends StatelessWidget {
  const _RaycastQuickAiButton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Quick AI',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: RaycastTokens.badge,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.move_to_inbox_rounded,
              size: 14,
              color: RaycastTokens.muted,
            ),
            const SizedBox(width: 5),
            Text(
              'Quick AI',
              style: RaycastTokens.ui(
                fontSize: 13,
                color: RaycastTokens.secondary,
                fontWeight: FontWeight.w500,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RaycastLauncherFrame extends StatelessWidget {
  const RaycastLauncherFrame({
    super.key,
    required this.child,
    required this.surface,
    required this.accent,
    required this.onSurface,
  });

  final Widget child;
  final Color surface;
  final Color accent;
  final Color onSurface;

  @override
  Widget build(BuildContext context) {
    const BorderRadius radius = BorderRadius.all(Radius.circular(14));

    return LauncherTheme(
      data: const LauncherThemeData(design: LauncherDesign.newCast),
      child: Container(
        decoration: LauncherDesign.newCast.outerDecoration(
          surface: surface,
          accent: accent,
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            children: <Widget>[
              if (Design.hasBackdrop)
                const Positioned.fill(
                  child: IgnorePointer(child: StableBackdrop()),
                ),
              const Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topRight,
                        end: Alignment(-0.18, 0.38),
                        colors: <Color>[
                          Color(0x1AFFFFFF),
                          Color(0x08FFFFFF),
                          Colors.transparent,
                        ],
                        stops: <double>[0, 0.28, 1],
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
                        colors: <Color>[Colors.white.withAlpha(10), Colors.transparent],
                      ),
                    ),
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  child,
                  _RaycastFooter(onSurface: onSurface),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RaycastFooter extends StatelessWidget {
  const _RaycastFooter({required this.onSurface});

  final Color onSurface;

  @override
  Widget build(BuildContext context) {
    final TextStyle labelStyle = RaycastTokens.ui(
      fontSize: 13,
      color: RaycastTokens.dim,
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
                    color: RaycastTokens.muted,
                    fontWeight: FontWeight.w500,
                    height: 1.0,
                  ),
                ),
                const SizedBox(width: 7),
                Text('Displays', style: labelStyle),
                const Spacer(),
                const Icon(Icons.keyboard_return_rounded, size: 14, color: RaycastTokens.muted),
                const SizedBox(width: 5),
                Text('Open', style: labelStyle),
                const SizedBox(width: 16),
                Container(width: 1, height: 15, color: RaycastTokens.divider),
                const SizedBox(width: 16),
                Text('Actions', style: labelStyle),
                const SizedBox(width: 7),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                  decoration: BoxDecoration(
                    color: RaycastTokens.badge,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '⌘K',
                    style: RaycastTokens.mono(
                      fontSize: 11,
                      color: RaycastTokens.muted,
                      fontWeight: FontWeight.w500,
                      height: 1.0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(
          height: 1,
          thickness: 1,
          color: RaycastTokens.divider,
        ),
      ],
    );
  }
}
