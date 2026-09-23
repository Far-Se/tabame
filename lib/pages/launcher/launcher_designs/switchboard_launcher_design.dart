part of '../launcher_design_builder.dart';

BoxDecoration _switchboardOuterDecoration(Color surface) {
  final bool isDark = ThemeData.estimateBrightnessForColor(surface) == Brightness.dark;
  return BoxDecoration(
    color: SwitchboardTokens.canvas(isDark),
    borderRadius: BorderRadius.circular(math.min(Design.borderRadius, 8)),
    border: Border.all(color: SwitchboardTokens.border(isDark)),
    boxShadow: <BoxShadow>[
      BoxShadow(
        color: Colors.black.withAlpha(isDark ? 85 : 24),
        blurRadius: 26,
        spreadRadius: -8,
        offset: const Offset(0, 13),
      ),
    ],
  );
}

class _SwitchboardLauncherSearchBar extends StatelessWidget {
  const _SwitchboardLauncherSearchBar(this.content);

  final _LauncherSearchBarContent content;

  @override
  Widget build(BuildContext context) {
    final Color accent = LauncherTheme.accentOf(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return ColoredBox(
      color: SwitchboardTokens.panel(isDark),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: <Widget>[
            content.dragHandle,
            const SizedBox(width: 10),
            DragToMoveArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2),
                ).withLauncherCorners(),
                child: Text(
                  'ROUTE',
                  style: SwitchboardTokens.label(
                    fontSize: Design.baseFontSize - 1,
                    fontWeight: FontWeight.w700,
                    color: SwitchboardTokens.panel(isDark),
                    letterSpacing: 1.3,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _LauncherSearchField(content, badgePadding: 0),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 16,
              height: 16,
              child: content.isSearching
                  ? CircularProgressIndicator(strokeWidth: 1.7, color: accent)
                  : Icon(Icons.keyboard_command_key_rounded, size: 15, color: SwitchboardTokens.dim(isDark)),
            ),
          ],
        ),
      ),
    );
  }
}

class SwitchboardLauncherHeader extends StatelessWidget {
  const SwitchboardLauncherHeader({super.key, required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 3),
      child: Row(
        children: <Widget>[
          Text(
            label.toUpperCase(),
            style: SwitchboardTokens.label(
              fontSize: Design.baseFontSize,
              fontWeight: FontWeight.w700,
              color: SwitchboardTokens.foreground(isDark),
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Container(height: 1, color: SwitchboardTokens.border(isDark))),
          const SizedBox(width: 8),
          Text(
            'RANKED',
            style: SwitchboardTokens.label(
              fontSize: Design.baseFontSize - 1.5,
              fontWeight: FontWeight.w600,
              color: accent,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class SwitchboardLauncherFrame extends StatelessWidget {
  const SwitchboardLauncherFrame({super.key, required this.child, required this.resultCount});

  final Widget child;
  final int resultCount;

  @override
  Widget build(BuildContext context) {
    final Color surface = Theme.of(context).colorScheme.surface;
    final bool isDark = ThemeData.estimateBrightnessForColor(surface) == Brightness.dark;
    return LauncherSurface(
      constraints: const BoxConstraints(minHeight: 360),
      decoration: _switchboardOuterDecoration(surface),
      child: Stack(
        children: <Widget>[
          if (Design.hasBackdrop) const StableBackdrop(),
          ColoredBox(
            color: SwitchboardTokens.canvas(isDark).withAlpha(Design.hasBackdrop ? (isDark ? 224 : 232) : 255),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                child,
                _SwitchboardFooter(isDark: isDark, resultCount: resultCount),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SwitchboardEmptyState extends StatelessWidget {
  const SwitchboardEmptyState({super.key, required this.isSearching, required this.hasQuery, required this.accent});

  final bool isSearching;
  final bool hasQuery;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final String title = isSearching ? 'Routing query' : (hasQuery ? 'No route found' : 'Start typing to route');
    final String detail = isSearching
        ? 'Checking active sources and plugins.'
        : (hasQuery
            ? 'Try a broader query or another launcher prefix.'
            : 'Applications, files, windows and commands share one ranked list.');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (isSearching)
              SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 1.7, color: accent),
              )
            else
              Icon(Icons.route_rounded, size: 26, color: accent),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: SwitchboardTokens.body(
                fontSize: Design.baseFontSize + 2,
                fontWeight: FontWeight.w600,
                color: SwitchboardTokens.foreground(isDark),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: SwitchboardTokens.body(
                fontSize: Design.baseFontSize,
                color: SwitchboardTokens.dim(isDark),
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwitchboardFooter extends StatelessWidget {
  const _SwitchboardFooter({required this.isDark, required this.resultCount});

  final bool isDark;
  final int resultCount;

  @override
  Widget build(BuildContext context) {
    final Color accent = LauncherTheme.accentOf(context);
    final Color dim = SwitchboardTokens.dim(isDark);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
      decoration: BoxDecoration(
        color: SwitchboardTokens.panel(isDark),
        border: Border(top: BorderSide(color: SwitchboardTokens.border(isDark))),
      ),
      child: Row(
        children: <Widget>[
          _hint('↑↓', 'navigate', dim),
          const SizedBox(width: 12),
          _hint('↵', 'open', dim),
          const SizedBox(width: 12),
          _hint('ctrl+k', 'actions', dim),
          const Spacer(),
          Container(width: 5, height: 5, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
          const SizedBox(width: 7),
          Text(
            Globals.isLauncherPluginActive ? "PLUGIN" : (resultCount == 1 ? '1 route' : '$resultCount routes'),
            style: SwitchboardTokens.body(fontSize: Design.baseFontSize - 1, color: dim),
          ),
        ],
      ),
    );
  }

  Widget _hint(String key, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          key,
          style: SwitchboardTokens.label(
            fontSize: Design.baseFontSize - 1,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: SwitchboardTokens.body(fontSize: Design.baseFontSize - 1, color: color)),
      ],
    );
  }
}
