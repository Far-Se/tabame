part of '../launcher_design_builder.dart';

BoxDecoration _groundGlassOuterDecoration() => BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: GroundGlassTokens.border),
    );

class _GroundGlassSearchBar extends StatelessWidget {
  const _GroundGlassSearchBar(this.content);

  final _LauncherSearchBarContent content;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.fromLTRB(2, 12, 0, 10),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: GroundGlassTokens.border))),
        child: Row(children: <Widget>[
          content.dragHandle,
          const SizedBox(width: 10),
          Expanded(child: _LauncherSearchField(content)),
          if (content.isSearching)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: GroundGlassTokens.accent),
              ),
            ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Hide launcher',
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: const EdgeInsets.all(6),
            style: const ButtonStyle(overlayColor: WidgetStatePropertyAll<Color>(Colors.transparent)),
            onPressed: () => windowManager.hide(),
            icon: Icon(Icons.close_rounded, size: 16, color: GroundGlassTokens.dim),
          ),
        ]),
      );
}

class GroundGlassLauncherFrame extends StatelessWidget {
  const GroundGlassLauncherFrame({super.key, required this.resultCount, required this.child});

  final int resultCount;
  final Widget child;

  @override
  Widget build(BuildContext context) => GroundGlassSurface(
        child: LauncherSurface(
          decoration: _groundGlassOuterDecoration(),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Flexible(fit: FlexFit.loose, child: child),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: GroundGlassTokens.border))),
              child: Row(children: <Widget>[
                Text('FIELD', style: GroundGlassTokens.label()),
                const SizedBox(width: 12),
                Text(
                  Globals.isLauncherPluginActive ? 'PLUGIN' : '$resultCount ${resultCount == 1 ? 'result' : 'results'}',
                  style: GroundGlassTokens.font(size: 11, color: GroundGlassTokens.dim),
                ),
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
                DateTimeWidget(
                  padding: const EdgeInsets.only(left: 10),
                  style: GroundGlassTokens.font(size: 10, color: GroundGlassTokens.dim),
                ),
              ]),
            ),
          ]),
        ),
      );

  Widget _hint(String key, String label) => Row(children: <Widget>[
        Text(key, style: GroundGlassTokens.font(size: 11, weight: FontWeight.w600)),
        const SizedBox(width: 5),
        Text(label, style: GroundGlassTokens.font(size: 11, color: GroundGlassTokens.dim)),
      ]);
}
