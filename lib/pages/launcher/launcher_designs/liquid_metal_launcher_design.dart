part of '../launcher_design_builder.dart';

BoxDecoration _liquidMetalOuterDecoration() {
  return BoxDecoration(
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: LiquidMetalTokens.border),
  );
}

class _LiquidMetalSearchBar extends StatelessWidget {
  const _LiquidMetalSearchBar(this.content);

  final _LauncherSearchBarContent content;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: LiquidMetalSurface(
        selected: true,
        radius: 12,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: LiquidMetalTokens.border),
          ),
          child: Row(children: <Widget>[
            content.dragHandle,
            const SizedBox(width: 12),
            Expanded(child: content.textField),
            if (content.trailingBadge != null) content.trailingBadge!,
            if (content.isSearching)
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: LiquidMetalTokens.accent)),
              ),
          ]),
        ),
      ),
    );
  }
}

class LiquidMetalLauncherFrame extends StatelessWidget {
  const LiquidMetalLauncherFrame({super.key, required this.resultCount, required this.child});
  final int resultCount;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LiquidMetalMotion(
      child: LiquidMetalSurface(
        radius: 16,
        raised: false,
        child: LiquidMetalSurface(
          radius: 16,
          overlay: true,
          child: Container(
            decoration: _liquidMetalOuterDecoration(),
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              if (user.launcherShowTitlebar)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 12, 2),
                  child: Row(children: <Widget>[
                    Expanded(
                        child: DragToMoveArea(
                            child: Row(children: <Widget>[
                      Icon(Icons.blur_circular_rounded, color: LiquidMetalTokens.accent, size: 16),
                      const SizedBox(width: 8),
                      Text('LIQUID METAL', style: LiquidMetalTokens.font(size: 10, spacing: 2)),
                    ]))),
                    // _windowControl('Minimize', Icons.remove_rounded, () {
                    //   windowManager.minimize();
                    // }),
                    // const SizedBox(width: 4),
                    // _windowControl('Hide launcher', Icons.close_rounded, () {
                    //   windowManager.hide();
                    // }),
                  ]),
                ),
              Flexible(fit: FlexFit.loose, child: child),
              LiquidMetalSurface(
                radius: 0,
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: LiquidMetalTokens.border))),
                  child: Row(children: <Widget>[
                    Expanded(
                        child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: <Widget>[
                        _hint('↑ ↓', 'Navigate'),
                        _hint('Enter', 'Open'),
                        _hint('Ctrl P', 'Preview'),
                      ]),
                    )),
                    const SizedBox(width: 12),
                    Text('$resultCount results', style: LiquidMetalTokens.font(size: 11, color: LiquidMetalTokens.dim)),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _windowControl(String label, IconData icon, VoidCallback onPressed) => LiquidMetalSurface(
        radius: 5,
        child: SizedBox(
            width: 30,
            height: 26,
            child: IconButton(
              padding: EdgeInsets.zero,
              tooltip: label,
              onPressed: onPressed,
              icon: Icon(icon, size: 15, color: LiquidMetalTokens.dim),
            )),
      );

  Widget _hint(String key, String label) => Padding(
        padding: const EdgeInsets.only(right: 20),
        child: Row(children: <Widget>[
          Text(key, style: LiquidMetalTokens.font(size: 11)),
          const SizedBox(width: 7),
          Text(label, style: LiquidMetalTokens.font(size: 11, color: LiquidMetalTokens.dim)),
        ]),
      );
}
