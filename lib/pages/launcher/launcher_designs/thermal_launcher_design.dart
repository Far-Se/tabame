part of '../launcher_design_builder.dart';

class ThermalSearchBar extends StatelessWidget {
  const ThermalSearchBar({
    super.key,
    required this.dragHandle,
    required this.textField,
    required this.trailingBadge,
    required this.isSearching,
  });

  final Widget dragHandle;
  final Widget textField;
  final Widget? trailingBadge;
  final bool isSearching;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 18),
        padding: const EdgeInsets.fromLTRB(2, 14, 0, 13),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: ThermalTokens.border))),
        child: Row(children: <Widget>[
          dragHandle,
          const SizedBox(width: 12),
          Expanded(child: textField),
          if (trailingBadge != null) trailingBadge!,
          if (isSearching)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: ThermalTokens.accent)),
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
              icon: const Icon(Icons.close_rounded, size: 16, color: ThermalTokens.dim),
            ),
          ),
        ]),
      );
}

class ThermalLauncherFrame extends StatelessWidget {
  const ThermalLauncherFrame({
    super.key,
    required this.surface,
    required this.accent,
    required this.onSurface,
    required this.resultCount,
    required this.child,
  });

  final Color surface;
  final Color accent;
  final Color onSurface;
  final int resultCount;
  final Widget child;

  @override
  Widget build(BuildContext context) => LauncherTheme(
        data: const LauncherThemeData(design: LauncherDesign.thermal),
        child: ThermalSurface(
          child: Container(
            decoration: LauncherDesign.thermal.outerDecoration(surface: surface, accent: accent),
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              Flexible(fit: FlexFit.loose, child: child),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 18),
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: ThermalTokens.border))),
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
                  Text('$resultCount ${resultCount == 1 ? 'result' : 'results'}',
                      style: ThermalTokens.font(size: 11, color: ThermalTokens.dim)),
                  const SizedBox(width: 12),
                  Text('THERMAL', style: ThermalTokens.label()),
                ]),
              ),
            ]),
          ),
        ),
      );

  Widget _hint(String key, String label) => Padding(
        padding: const EdgeInsets.only(right: 16),
        child: Row(children: <Widget>[
          Text(key, style: ThermalTokens.font(size: 11, weight: FontWeight.w600)),
          const SizedBox(width: 5),
          Text(label, style: ThermalTokens.font(size: 11, color: ThermalTokens.dim)),
        ]),
      );
}
