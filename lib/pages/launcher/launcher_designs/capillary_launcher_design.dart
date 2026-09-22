part of '../launcher_design_builder.dart';

BoxDecoration _capillaryOuterDecoration(Color surface) {
  return BoxDecoration(
    borderRadius: BorderRadius.circular(8),
    border: Border.all(
        color: CapillaryTokens.resolve(ThemeData.estimateBrightnessForColor(surface) == Brightness.dark).border),
  );
}

class _CapillarySearchBar extends StatelessWidget {
  const _CapillarySearchBar(this.content);

  final _LauncherSearchBarContent content;

  @override
  Widget build(BuildContext context) {
    final CapillaryTokens capillary = CapillaryTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: CapillarySurface(
        kind: CapillarySurfaceKind.search,
        radius: 0,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 14),
          child: Row(children: <Widget>[
            content.dragHandle,
            const SizedBox(width: 12),
            Expanded(child: content.textField),
            if (content.trailingBadge != null) content.trailingBadge!,
            if (content.isSearching)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: capillary.accent),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class CapillaryLauncherFrame extends StatelessWidget {
  const CapillaryLauncherFrame({super.key, required this.resultCount, required this.child, this.queryController});

  final int resultCount;
  final Widget child;
  final TextEditingController? queryController;

  @override
  Widget build(BuildContext context) {
    final Color surface = Theme.of(context).colorScheme.surface;
    final CapillaryTokens capillary = CapillaryTokens.of(context);
    return CapillaryMotion(
      queryController: queryController,
      child: CapillarySurface(
        kind: CapillarySurfaceKind.paper,
        radius: 8,
        child: CapillarySurface(
          kind: CapillarySurfaceKind.overlay,
          radius: 8,
          child: LauncherSurface(
            decoration: _capillaryOuterDecoration(surface),
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              Flexible(fit: FlexFit.loose, child: child),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: capillary.border))),
                child: Row(children: <Widget>[
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: <Widget>[
                        _hint(capillary, '\u2191 \u2193', 'Navigate'),
                        _hint(capillary, 'Enter', 'Open'),
                        _hint(capillary, 'Ctrl K', 'Actions'),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('$resultCount ${resultCount == 1 ? 'result' : 'results'}',
                      style: capillary.font(size: 11, color: capillary.dim)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _hint(CapillaryTokens capillary, String key, String label) => Padding(
        padding: const EdgeInsets.only(right: 16),
        child: Row(children: <Widget>[
          Text(key, style: capillary.font(size: 11, weight: FontWeight.w600)),
          const SizedBox(width: 5),
          Text(label, style: capillary.font(size: 11, color: capillary.dim)),
        ]),
      );
}
