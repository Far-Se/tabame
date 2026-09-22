part of '../launcher_design_builder.dart';

BoxDecoration _omarchyOuterDecoration(Color surface) {
  return BoxDecoration(
    color: surface,
    border: Border.all(color: OmarchyTokens.border),
  );
}

class _OmarchySearchBar extends StatelessWidget {
  const _OmarchySearchBar(this.content);

  final _LauncherSearchBarContent content;

  @override
  Widget build(BuildContext context) {
    final Color accent = LauncherTheme.accentOf(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(border: Border.all(color: accent)),
      child: Row(children: <Widget>[
        Tooltip(message: 'Drag launcher', child: content.dragHandle),
        const SizedBox(width: 8),
        Text('>', style: OmarchyTokens.mono(fontSize: 20, color: accent, fontWeight: FontWeight.w600)),
        const SizedBox(width: 10),
        Expanded(child: content.textField),
        if (content.trailingBadge != null) content.trailingBadge!,
        if (content.isSearching)
          Semantics(
            label: 'Searching',
            child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5, color: accent)),
          ),
      ]),
    );
  }
}

class OmarchyLauncherHeader extends StatelessWidget {
  const OmarchyLauncherHeader({super.key, required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(children: <Widget>[
        Text('─ ', style: OmarchyTokens.mono(color: OmarchyTokens.border)),
        Flexible(
            child: Text(label.toLowerCase(),
                overflow: TextOverflow.ellipsis,
                style:
                    OmarchyTokens.mono(fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.w600, color: accent))),
        const SizedBox(width: 8),
        Expanded(child: Container(height: 1, color: OmarchyTokens.border.withAlpha(100))),
      ]),
    );
  }
}

/// A compact, square terminal frame. Search and execution stay in the shared launcher.
class OmarchyLauncherFrame extends StatelessWidget {
  const OmarchyLauncherFrame({super.key, required this.child, this.resultCount = 0});

  final Widget child;
  final int resultCount;

  @override
  Widget build(BuildContext context) {
    final Color surface = Theme.of(context).colorScheme.surface;
    final Color accent = LauncherTheme.accentOf(context);
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final TextStyle label =
        OmarchyTokens.mono(fontSize: Design.baseFontSize + 1, color: OmarchyTokens.dim, height: 1.2);
    return LauncherSurface(
      decoration: _omarchyOuterDecoration(surface),
      child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        if (user.launcherShowTitlebar)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 8, 2),
            child: Row(children: <Widget>[
              Expanded(
                  child: DragToMoveArea(
                      child: Row(children: <Widget>[
                Text('▰ ', style: label.copyWith(color: accent)),
                Text('tabame', style: label.copyWith(color: onSurface, fontWeight: FontWeight.w600)),
                const SizedBox(width: 10),
                Flexible(child: Text('/ launcher', overflow: TextOverflow.ellipsis, style: label)),
              ]))),
              IconButton(
                tooltip: 'Close launcher (Esc)',
                onPressed: QuickMenuFunctions.hideQuickMenu,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: const EdgeInsets.all(6),
                icon: Text('×', style: label.copyWith(fontSize: 20)),
              ),
            ]),
          ),
        child,
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: OmarchyTokens.border))),
          child: LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
            return Wrap(
              spacing: 16,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Text('$resultCount ${resultCount == 1 ? 'result' : 'results'}', style: label.copyWith(color: accent)),
                if (constraints.maxWidth > 460) Text('↑↓ move', style: label),
                Text('↵ open', style: label),
                Text('ctrl+k actions', style: label),
                Text('esc close', style: label),
              ],
            );
          }),
        ),
      ]),
    );
  }
}
