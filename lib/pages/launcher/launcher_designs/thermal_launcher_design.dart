part of '../launcher_design_builder.dart';

BoxDecoration _thermalOuterDecoration() {
  return BoxDecoration(
    borderRadius: BorderRadius.circular(10),
    border: Border.all(color: ThermalTokens.border),
  );
}

class _ThermalSearchBar extends StatelessWidget {
  const _ThermalSearchBar(this.content);

  final _LauncherSearchBarContent content;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 18),
      padding: const EdgeInsets.fromLTRB(2, 14, 0, 13),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: ThermalTokens.border))),
      child: Row(children: <Widget>[
        content.dragHandle,
        const SizedBox(width: 12),
        Expanded(child: content.textField),
        if (content.trailingBadge != null) content.trailingBadge!,
        if (content.isSearching)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SizedBox(
                width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 1.5, color: ThermalTokens.accent)),
          ),
        const SizedBox(width: 8),
        SizedBox(
          width: 26,
          height: 28,
          child: IconButton(
            tooltip: 'Hide launcher',
            padding: EdgeInsets.zero,
            style: const ButtonStyle(overlayColor: WidgetStatePropertyAll<Color>(Colors.transparent)),
            onPressed: () => windowManager.hide(),
            icon: Icon(Icons.close_rounded, size: 16, color: ThermalTokens.dim),
          ),
        ),
      ]),
    );
  }
}

class ThermalLauncherFrame extends StatelessWidget {
  const ThermalLauncherFrame({super.key, required this.resultCount, required this.child});

  final int resultCount;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ThermalSurface(
      child: LauncherSurface(
        decoration: _thermalOuterDecoration(),
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Flexible(fit: FlexFit.loose, child: child),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 18),
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: ThermalTokens.border))),
            child: Row(children: <Widget>[
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: <Widget>[
                    _hint('\u2191 \u2193', 'Navigate'),
                    _hint('Enter', 'Open'),
                    _hint('Ctrl K', 'Actions'),
                  ]),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                  Globals.isLauncherPluginActive ? "PLUGIN" : '$resultCount ${resultCount == 1 ? 'result' : 'results'}',
                  style: ThermalTokens.font(size: 11, color: ThermalTokens.dim)),
              const SizedBox(width: 12),
              Text('THERMAL', style: ThermalTokens.label()),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _hint(String key, String label) => Padding(
        padding: const EdgeInsets.only(right: 16),
        child: Row(children: <Widget>[
          Text(key, style: ThermalTokens.font(size: 11, weight: FontWeight.w600)),
          const SizedBox(width: 5),
          Text(label, style: ThermalTokens.font(size: 11, color: ThermalTokens.dim)),
        ]),
      );
}
