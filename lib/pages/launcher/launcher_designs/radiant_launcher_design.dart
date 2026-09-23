part of '../launcher_design_builder.dart';

BoxDecoration _radiantOuterDecoration() => BoxDecoration(
      color: RadiantTokens.background,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: RadiantTokens.accent.withValues(alpha: 0.8)),
      boxShadow: <BoxShadow>[
        BoxShadow(color: RadiantTokens.accent.withValues(alpha: 0.22), blurRadius: 16),
      ],
    );

class _RadiantSearchBar extends StatelessWidget {
  const _RadiantSearchBar(this.content);
  final _LauncherSearchBarContent content;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: RadiantTokens.background.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: RadiantTokens.accent.withValues(alpha: 0.23)),
        ).withLauncherCorners(),
        child: Row(children: <Widget>[
          content.dragHandle,
          const SizedBox(width: 12),
          Expanded(child: _LauncherSearchField(content)),
          if (content.isSearching)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: RadiantTokens.accent)),
            ),
        ]),
      );
}

class RadiantLauncherFrame extends StatelessWidget {
  const RadiantLauncherFrame({super.key, required this.child, required this.resultCount});
  final Widget child;
  final int resultCount;

  @override
  Widget build(BuildContext context) => RadiantMotion(
        child: RadiantSurface(
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Flexible(fit: FlexFit.loose, child: child),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 14),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: RadiantTokens.border))),
              child: Row(children: <Widget>[
                const ExcludeSemantics(
                  child: IgnorePointer(
                    child: SizedBox(
                        width: 132,
                        height: 32,
                        child: RadiantSurface(kind: RadiantSurfaceKind.symbols, child: SizedBox.expand())),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: Row(children: <Widget>[
                      Text(
                          Globals.isLauncherPluginActive
                              ? "PLUGIN"
                              : '$resultCount ${resultCount == 1 ? 'result' : 'results'}',
                          style: RadiantTokens.font(size: 11, color: RadiantTokens.dim)),
                      const SizedBox(width: 12),
                      _hint('↑ ↓', 'Navigate'),
                      const SizedBox(width: 12),
                      _hint('↵', 'Open'),
                      const SizedBox(width: 12),
                      _hint('Ctrl K', 'Actions'),
                    ]),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      );

  Widget _hint(String key, String label) => Row(children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: RadiantTokens.accent.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: RadiantTokens.accent.withValues(alpha: 0.22)),
          ).withLauncherCorners(),
          child: Text(key, style: RadiantTokens.font(size: 10)),
        ),
        const SizedBox(width: 6),
        Text(label, style: RadiantTokens.font(size: 11, color: RadiantTokens.dim)),
      ]);
}
