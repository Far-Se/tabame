part of '../launcher_design_builder.dart';

BoxDecoration _satinOuterDecoration() => BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: SatinTokens.border),
    );

class _SatinSearchBar extends StatelessWidget {
  const _SatinSearchBar(this.content);
  final _LauncherSearchBarContent content;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: SatinTokens.border))),
        child: Row(children: <Widget>[
          content.dragHandle,
          const SizedBox(width: 12),
          Expanded(child: content.textField),
          if (content.trailingBadge != null) content.trailingBadge!,
          if (content.isSearching)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: SatinTokens.accent),
              ),
            ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Hide launcher',
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: const EdgeInsets.all(6),
            onPressed: () => windowManager.hide(),
            icon: Icon(Icons.close_rounded, size: 16, color: SatinTokens.dim),
          ),
        ]),
      );
}

class SatinLauncherFrame extends StatelessWidget {
  const SatinLauncherFrame({super.key, required this.resultCount, required this.child});

  final int resultCount;
  final Widget child;

  @override
  Widget build(BuildContext context) => SatinSurface(
        child: Container(
          decoration: _satinOuterDecoration(),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Flexible(fit: FlexFit.loose, child: child),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: SatinTokens.border))),
              child: Row(children: <Widget>[
                Text('SATIN', style: SatinTokens.label()),
                const SizedBox(width: 12),
                Text('$resultCount ${resultCount == 1 ? 'result' : 'results'}',
                    style: SatinTokens.font(size: 11, color: SatinTokens.dim)),
                const SizedBox(width: 16),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: Row(children: <Widget>[
                      _hint('\u2191\u2193', 'Navigate'),
                      const SizedBox(width: 14),
                      _hint('\u21b5', 'Open'),
                      const SizedBox(width: 14),
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
        Text(key, style: SatinTokens.font(size: 11, weight: FontWeight.w600)),
        const SizedBox(width: 5),
        Text(label, style: SatinTokens.font(size: 11, color: SatinTokens.dim)),
      ]);
}
