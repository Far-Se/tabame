part of '../launcher_design_builder.dart';

BoxDecoration _ukiyoeOuterDecoration() => BoxDecoration(
      color: UkiyoeTokens.background,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: UkiyoeTokens.accent.withValues(alpha: 0.65)),
    );

class _UkiyoeSearchBar extends StatelessWidget {
  const _UkiyoeSearchBar(this.content);
  final _LauncherSearchBarContent content;

  @override
  Widget build(BuildContext context) => Row(children: <Widget>[
        content.dragHandle,
        const SizedBox(width: 12),
        Expanded(child: _LauncherSearchField(content)),
        if (content.isSearching)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: UkiyoeTokens.vermilion)),
          ),
      ]);
}

class UkiyoeLauncherFrame extends StatelessWidget {
  const UkiyoeLauncherFrame({super.key, required this.searchChild, required this.child, required this.resultCount});
  final Widget searchChild;
  final Widget child;
  final int resultCount;

  @override
  Widget build(BuildContext context) => LauncherSurface(
        decoration: _ukiyoeOuterDecoration(),
        child: UkiyoeSurface(
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
              child: UkiyoeSurface(
                material: UkiyoeMaterial.landscape,
                radius: 3,
                child: DragToMoveArea(
                  child: SizedBox(
                    height: 70,
                    width: double.infinity,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Container(
                        margin: const EdgeInsets.all(10),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        child: searchChild,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Flexible(fit: FlexFit.loose, child: child),
            Container(
              margin: const EdgeInsets.fromLTRB(18, 6, 18, 0),
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: UkiyoeTokens.border))),
              child: Row(children: <Widget>[
                Text(
                    Globals.isLauncherPluginActive
                        ? "PLUGIN"
                        : '$resultCount ${resultCount == 1 ? 'result' : 'results'}',
                    style: UkiyoeTokens.font(size: 11, color: UkiyoeTokens.dim)),
                const SizedBox(width: 20),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: Row(children: <Widget>[
                      _hint('↑ ↓', 'Navigate'),
                      const SizedBox(width: 16),
                      _hint('↵', 'Open'),
                      const SizedBox(width: 16),
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
        Text(key, style: UkiyoeTokens.font(size: 11, weight: FontWeight.w700)),
        const SizedBox(width: 6),
        Text(label, style: UkiyoeTokens.font(size: 11, color: UkiyoeTokens.dim)),
      ]);
}
