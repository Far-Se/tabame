part of '../launcher_design_builder.dart';

BoxDecoration _glassOuterDecoration(Color accent) {
  // Just the floating-glass shadow + accent refraction glow; the glassy
  // fill, border and specular highlights live inside [GlassLauncherFrame].
  return BoxDecoration(
    borderRadius: BorderRadius.circular(Design.borderRadius),
    boxShadow: <BoxShadow>[
      BoxShadow(
        color: accent.withAlpha(100),
        blurRadius: 30,
        spreadRadius: -19,
        offset: const Offset(0, 18),
      ),
      BoxShadow(
        color: Colors.black.withAlpha(70),
        blurRadius: 30,
        spreadRadius: -8,
        offset: const Offset(0, 12),
      ),
    ],
  );
}

class _GlassSearchBar extends StatelessWidget {
  const _GlassSearchBar(this.content);

  final _LauncherSearchBarContent content;

  @override
  Widget build(BuildContext context) {
    final Color accent = LauncherTheme.accentOf(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    // A bright floating glass capsule.
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Colors.white.withAlpha(isDark ? 24 : 150),
              Colors.white.withAlpha(isDark ? 8 : 80),
            ],
          ),
          border: Border.all(color: Colors.white.withAlpha(isDark ? 44 : 180), width: 1),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withAlpha(isDark ? 46 : 18),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
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
                  child: CircularProgressIndicator(strokeWidth: 1.8, color: accent.withAlpha(170)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class GlassLauncherFrame extends StatelessWidget {
  const GlassLauncherFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Color surface = Theme.of(context).colorScheme.surface;
    final Color accent = LauncherTheme.accentOf(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool hasBackdrop = Design.hasBackdrop;
    final Color baseFill = surface.withAlpha(hasBackdrop ? (isDark ? 150 : 170) : (isDark ? 188 : 212));

    return Container(
      constraints: const BoxConstraints(minHeight: 360),
      decoration: _glassOuterDecoration(accent),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Design.borderRadius),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Design.borderRadius),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  Color.alphaBlend(Colors.white.withAlpha(isDark ? 60 : 92), baseFill),
                  baseFill,
                  Color.alphaBlend(accent.withAlpha(isDark ? 46 : 30), baseFill),
                ],
              ),
              border: Border.all(color: Colors.white.withAlpha(isDark ? 40 : 120), width: 1.2),
            ),
            child: Stack(
              children: <Widget>[
                if (Design.hasBackdrop) const StableBackdrop(),
                // Accent refraction glow drifting from the bottom-right.
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(1.1, 1.2),
                          radius: 1.4,
                          colors: <Color>[accent.withAlpha(isDark ? 48 : 34), accent.withAlpha(0)],
                        ),
                      ),
                    ),
                  ),
                ),
                // Specular sheen — the glass shine from the top-left.
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.center,
                          colors: <Color>[Colors.white.withAlpha(isDark ? 26 : 96), Colors.transparent],
                        ),
                      ),
                    ),
                  ),
                ),
                // Bright glass edge along the very top.
                Positioned(
                  top: 0,
                  left: 18,
                  right: 18,
                  height: 1.5,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: <Color>[
                            Colors.transparent,
                            Colors.white.withAlpha(isDark ? 70 : 200),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                ClipRRect(
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
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
