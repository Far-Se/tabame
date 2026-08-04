part of '../launcher_design_builder.dart';

Color _steamLauncherLift(Color base, double amount) => Color.alphaBlend(Colors.white.withValues(alpha: amount), base);
Color _steamLauncherSink(Color base, double amount) => Color.alphaBlend(Colors.black.withValues(alpha: amount), base);

BoxDecoration steamLauncherOuterDecoration(Color surface, Color accent) {
  final bool isDark = surface.computeLuminance() < .5;
  return BoxDecoration(
    borderRadius: BorderRadius.circular(Design.borderRadius),
    color: surface,
    border: Border.all(color: isDark ? Colors.black.withAlpha(130) : Colors.black.withAlpha(30)),
    boxShadow: <BoxShadow>[
      BoxShadow(color: Colors.black.withAlpha(85), blurRadius: 30, spreadRadius: -7, offset: const Offset(0, 14))
    ],
  );
}

class SteamLauncherFrame extends StatelessWidget {
  const SteamLauncherFrame(
      {super.key,
      required this.child,
      required this.surface,
      required this.accent,
      required this.onSurface,
      required this.resultCount});
  final Widget child;
  final Color surface;
  final Color accent;
  final Color onSurface;
  final int resultCount;
  @override
  Widget build(BuildContext context) {
    final bool isDark = surface.computeLuminance() < .5;
    final Color header = _steamLauncherSink(surface, isDark ? .32 : .06);
    final Color footer = _steamLauncherSink(surface, isDark ? .26 : .05);
    final Color panel = Color.alphaBlend(accent.withAlpha(15), _steamLauncherLift(surface, isDark ? .055 : .35));
    final Color stroke = isDark ? Colors.white.withAlpha(15) : Colors.black.withAlpha(20);
    return LauncherTheme(
      data: const LauncherThemeData(design: LauncherDesign.steam),
      child: Container(
        constraints: const BoxConstraints(minHeight: 360),
        decoration: steamLauncherOuterDecoration(surface, accent),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Design.borderRadius),
          child: Stack(children: <Widget>[
            Positioned.fill(child: ColoredBox(color: surface)),
            if (Design.hasBackdrop) const Positioned.fill(child: StableBackdrop()),
            Positioned.fill(
                child: IgnorePointer(
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            gradient: RadialGradient(
                                center: const Alignment(-.6, -1.4),
                                radius: 1.6,
                                colors: <Color>[accent.withAlpha(36), Colors.transparent]))))),
            Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              ColoredBox(
                color: header.withAlpha(245),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(13, 7, 13, 6),
                  child: Row(children: <Widget>[
                    Text('TABAME',
                        style: TextStyle(
                            color: onSurface.withAlpha(85),
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.4)),
                    const SizedBox(width: 14),
                    Text('LIBRARY',
                        style: TextStyle(
                            color: onSurface.withAlpha(220),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.4)),
                    const SizedBox(width: 14),
                    Text('QuickLaunch',
                        style: TextStyle(
                            color: onSurface.withAlpha(85),
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.4)),
                    const Spacer(),
                    Text(Globals.isLauncherPluginActive ? "PLUGIN" : '$resultCount ITEMS',
                        style: TextStyle(
                            color: accent.withAlpha(190),
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.1)),
                    DateTimeWidget(
                        padding: const EdgeInsets.only(left: 10),
                        style: TextStyle(
                            color: accent.withAlpha(190),
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.1)),
                  ]),
                ),
              ),
              Container(
                  height: 1,
                  decoration: BoxDecoration(
                      gradient: LinearGradient(
                          colors: <Color>[accent.withAlpha(140), Colors.transparent], stops: const <double>[0, .85]))),
              Container(
                margin: const EdgeInsets.fromLTRB(8, 7, 8, 4),
                decoration: BoxDecoration(
                    color: panel.withAlpha(240),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: stroke)),
                child: child,
              ),
              Container(
                color: footer.withAlpha(245),
                padding: const EdgeInsets.fromLTRB(11, 5, 11, 6),
                child: Row(children: <Widget>[
                  Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: accent)),
                  const SizedBox(width: 7),
                  Text('ONLINE',
                      style: TextStyle(
                          color: onSurface.withAlpha(115),
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2)),
                  const Spacer(),
                  Text('ENTER  LAUNCH   ·   ESC  CLOSE',
                      style: TextStyle(color: onSurface.withAlpha(90), fontSize: 9, letterSpacing: .8)),
                ]),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class SteamLauncherSearchBar extends StatelessWidget {
  const SteamLauncherSearchBar(
      {super.key,
      required this.accent,
      required this.onSurface,
      required this.dragHandle,
      required this.textField,
      required this.trailingBadge,
      required this.isSearching});
  final Color accent;
  final Color onSurface;
  final Widget dragHandle;
  final Widget textField;
  final Widget? trailingBadge;
  final bool isSearching;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(9, 8, 9, 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color: onSurface.withAlpha(9),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: onSurface.withAlpha(19))),
        child: Row(children: <Widget>[
          dragHandle,
          const SizedBox(width: 9),
          Expanded(child: textField),
          if (trailingBadge != null) trailingBadge!,
          if (isSearching) ...<Widget>[
            const SizedBox(width: 7),
            SizedBox.square(dimension: 13, child: CircularProgressIndicator(strokeWidth: 1.5, color: accent))
          ],
        ]),
      );
}

class SteamLauncherHeader extends StatelessWidget {
  const SteamLauncherHeader({super.key, required this.label, required this.accent});
  final String label;
  final Color accent;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 7, 10, 2),
        child: Row(children: <Widget>[
          Text(label.toUpperCase(),
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withAlpha(105),
                  fontSize: Design.baseFontSize - 2,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2)),
          const SizedBox(width: 8),
          Expanded(child: Container(height: 1, color: Theme.of(context).colorScheme.onSurface.withAlpha(18))),
          const SizedBox(width: 6),
          Icon(Icons.grid_view_rounded, size: 10, color: accent.withAlpha(170)),
        ]),
      );
}
