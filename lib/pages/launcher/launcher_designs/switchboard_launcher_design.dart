part of '../launcher_design_builder.dart';

BoxDecoration switchboardLauncherOuterDecoration(Color surface, Color accent) {
  final bool isDark = surface.computeLuminance() < 0.5;
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

class SwitchboardLauncherSearchBar extends StatelessWidget {
  const SwitchboardLauncherSearchBar({
    super.key,
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
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return ColoredBox(
      color: SwitchboardTokens.panel(isDark),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: <Widget>[
            dragHandle,
            const SizedBox(width: 10),
            DragToMoveArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2),
                ),
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
              child: Stack(
                alignment: Alignment.centerRight,
                children: <Widget>[
                  textField,
                  if (trailingBadge != null) trailingBadge!,
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 16,
              height: 16,
              child: isSearching
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
  const SwitchboardLauncherFrame({
    super.key,
    required this.child,
    required this.surface,
    required this.accent,
    required this.resultCount,
  });

  final Widget child;
  final Color surface;
  final Color accent;
  final int resultCount;

  @override
  Widget build(BuildContext context) {
    final bool isDark = surface.computeLuminance() < 0.5;
    final double radius = math.min(Design.borderRadius, 8);
    return LauncherTheme(
      data: const LauncherThemeData(design: LauncherDesign.switchboard),
      child: Container(
        constraints: const BoxConstraints(minHeight: 360),
        decoration: switchboardLauncherOuterDecoration(surface, accent),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(math.max(0, radius - 1)),
          child: ColoredBox(
            color: SwitchboardTokens.canvas(isDark),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                child,
                _SwitchboardFooter(
                  isDark: isDark,
                  accent: accent,
                  resultCount: resultCount,
                ),
              ],
            ),
          ),
        ),
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
  const _SwitchboardFooter({required this.isDark, required this.accent, required this.resultCount});

  final bool isDark;
  final Color accent;
  final int resultCount;

  @override
  Widget build(BuildContext context) {
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
            resultCount == 1 ? '1 route' : '$resultCount routes',
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
