part of '../launcher_design_builder.dart';

BoxDecoration _ivoryGroveOuterDecoration(Color surface, Color accent) => BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[surface, Color.alphaBlend(accent.withValues(alpha: 0.055), surface)],
      ),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: IvoryGroveTokens.edge),
      boxShadow: <BoxShadow>[
        BoxShadow(color: Colors.black.withValues(alpha: 0.16), blurRadius: 28, offset: const Offset(0, 12)),
      ],
    );

class _IvoryGroveSearchBar extends StatelessWidget {
  const _IvoryGroveSearchBar(this.content);
  final _LauncherSearchBarContent content;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: IvoryGroveTokens.background.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: IvoryGroveTokens.edge),
          boxShadow: <BoxShadow>[
            BoxShadow(
                color: IvoryGroveTokens.foreground.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 3)),
          ],
        ).withLauncherCorners(),
        child: Row(children: <Widget>[
          content.dragHandle,
          const SizedBox(width: 12),
          Expanded(child: _LauncherSearchField(content)),
          if (content.isSearching)
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: LauncherTheme.accentOf(context))),
            ),
        ]),
      );
}

class IvoryGroveLauncherFrame extends StatelessWidget {
  const IvoryGroveLauncherFrame({super.key, required this.child, required this.resultCount});
  final Widget child;
  final int resultCount;

  @override
  Widget build(BuildContext context) => LauncherSurface(
        decoration: _ivoryGroveOuterDecoration(Theme.of(context).colorScheme.surface, LauncherTheme.accentOf(context)),
        child: IvoryGroveSurface(
          ink: IvoryGroveTokens.foreground,
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Flexible(fit: FlexFit.loose, child: child),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: IvoryGroveTokens.background.withValues(alpha: 0.85),
                border: Border(top: BorderSide(color: IvoryGroveTokens.border)),
              ),
              child: LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
                final double available =
                    constraints.maxWidth / (MediaQuery.textScalerOf(context).scale(Design.baseFontSize + 1) / 11);
                return Row(children: <Widget>[
                  Icon(Icons.eco_outlined, color: LauncherTheme.accentOf(context), size: 18),
                  const SizedBox(width: 9),
                  Expanded(
                      child: Text(
                          Globals.isLauncherPluginActive
                              ? 'PLUGIN'
                              : '$resultCount ${resultCount == 1 ? 'result' : 'results'}',
                          overflow: TextOverflow.ellipsis,
                          style: IvoryGroveTokens.font(size: Design.baseFontSize + 1, color: IvoryGroveTokens.dim))),
                  if (available > 470) ...<Widget>[
                    _hint(Icons.unfold_more_rounded, 'Navigate'),
                    const SizedBox(width: 16),
                  ],
                  if (available > 340) ...<Widget>[
                    _hint(Icons.keyboard_return_rounded, 'Open'),
                    const SizedBox(width: 16),
                  ],
                  if (available > 230) _hint(null, 'Close', keyLabel: 'esc'),
                ]);
              }),
            ),
          ]),
        ),
      );

  Widget _hint(IconData? icon, String label, {String? keyLabel}) =>
      Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: IvoryGroveTokens.panel,
            border: Border.all(color: IvoryGroveTokens.border),
            borderRadius: BorderRadius.circular(6),
          ).withLauncherCorners(),
          child: keyLabel == null
              ? Icon(icon, size: 14, color: IvoryGroveTokens.dim)
              : Text(keyLabel, style: IvoryGroveTokens.font(size: 11, color: IvoryGroveTokens.dim)),
        ),
        const SizedBox(width: 6),
        Text(label, style: IvoryGroveTokens.font(size: Design.baseFontSize + 1, color: IvoryGroveTokens.dim)),
      ]);
}
