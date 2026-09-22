part of '../launcher_design_builder.dart';

BoxDecoration _phosphorOuterDecoration() {
  return BoxDecoration(
      color: PhosphorTokens.background,
      borderRadius: BorderRadius.zero,
      border: Border.all(color: PhosphorTokens.border));
}

class _PhosphorSearchBar extends StatelessWidget {
  const _PhosphorSearchBar(this.content);

  final _LauncherSearchBarContent content;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(20, 8, 4, 8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: PhosphorTokens.border))),
      child: Row(children: <Widget>[
        DragToMoveArea(
            child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(r'C:\>', style: PhosphorTokens.font(size: 18, color: PhosphorTokens.accent)))),
        const SizedBox(width: 20),
        Expanded(child: content.textField),
        if (content.trailingBadge != null) content.trailingBadge!,
        if (content.isSearching)
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: PhosphorTokens.accent))),
        const SizedBox(width: 8),
      ]),
    );
  }
}

class PhosphorLauncherFrame extends StatelessWidget {
  const PhosphorLauncherFrame({super.key, required this.resultCount, required this.child});
  final int resultCount;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LauncherSurface(
        decoration: _phosphorOuterDecoration(),
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Flexible(fit: FlexFit.loose, child: child),
          Container(
              height: 44,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: PhosphorTokens.border))),
              child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) => Row(children: <Widget>[
                        Expanded(
                            child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(children: <Widget>[
                                  _hint('↑↓ ', 'Navigate'),
                                  _hint('Enter', 'Open'),
                                  _hint('Ctrl + ↵ ', 'Open Folder'),
                                ]))),
                        const SizedBox(width: 12),
                        Text('$resultCount results',
                            style: PhosphorTokens.font(size: 12, color: PhosphorTokens.accent)),
                      ]))),
        ]));
  }

  Widget _hint(String key, String label) => Padding(
      padding: const EdgeInsets.only(right: 20),
      child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(border: Border.all(color: PhosphorTokens.accent.withAlpha(160))),
            child: Text(key, style: PhosphorTokens.font(size: 11, color: PhosphorTokens.accent))),
        const SizedBox(width: 12),
        Text(label, style: PhosphorTokens.font(size: 11, color: PhosphorTokens.dim)),
      ]));
}

class PhosphorResultsPanel extends StatelessWidget {
  const PhosphorResultsPanel({super.key, required this.enabled, required this.child});
  final bool enabled;
  final Widget child;
  @override
  Widget build(BuildContext context) => enabled
      ? Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(border: Border.all(color: PhosphorTokens.border)),
          child: child)
      : child;
}
