part of '../launcher_design_builder.dart';

class _OmarchySearchBar extends StatelessWidget {
  const _OmarchySearchBar(
      {required this.dragHandle,
      required this.textField,
      required this.trailingBadge,
      required this.isSearching,
      required this.accent});

  final Widget dragHandle;
  final Widget textField;
  final Widget? trailingBadge;
  final bool isSearching;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(border: Border.all(color: accent)),
      child: Row(children: <Widget>[
        Tooltip(message: 'Drag launcher', child: dragHandle),
        const SizedBox(width: 8),
        Text('>', style: OmarchyTokens.mono(fontSize: 20, color: accent, fontWeight: FontWeight.w600)),
        const SizedBox(width: 10),
        Expanded(child: textField),
        if (trailingBadge != null) trailingBadge!,
        if (isSearching)
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
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(children: <Widget>[
        Text('─ ', style: OmarchyTokens.mono(color: OmarchyTokens.border(dark))),
        Flexible(
            child: Text(label.toLowerCase(),
                overflow: TextOverflow.ellipsis,
                style:
                    OmarchyTokens.mono(fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.w600, color: accent))),
        const SizedBox(width: 8),
        Expanded(child: Container(height: 1, color: OmarchyTokens.border(dark).withAlpha(100))),
      ]),
    );
  }
}

/// A compact, square terminal frame. Search and execution stay in the shared launcher.
class OmarchyLauncherFrame extends StatelessWidget {
  const OmarchyLauncherFrame(
      {super.key,
      required this.child,
      required this.surface,
      required this.accent,
      required this.onSurface,
      this.resultCount = 0});

  final Widget child;
  final Color surface;
  final Color accent;
  final Color onSurface;
  final int resultCount;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final TextStyle label =
        OmarchyTokens.mono(fontSize: Design.baseFontSize + 1, color: OmarchyTokens.dim(dark), height: 1.2);
    return LauncherTheme(
      data: const LauncherThemeData(design: LauncherDesign.omarchy),
      child: Container(
        decoration: LauncherDesign.omarchy.outerDecoration(surface: surface, accent: accent),
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
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
            decoration: BoxDecoration(border: Border(top: BorderSide(color: OmarchyTokens.border(dark)))),
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
      ),
    );
  }
}
