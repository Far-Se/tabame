part of '../launcher_design_builder.dart';

BoxDecoration _opticalGlassOuterDecoration() {
  return BoxDecoration(borderRadius: BorderRadius.circular(24), border: Border.all(color: OpticalGlassTokens.border));
}

class _OpticalGlassSearchBar extends StatelessWidget {
  const _OpticalGlassSearchBar(this.content);

  final _LauncherSearchBarContent content;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: OpticalGlassSurface(
        selected: true,
        radius: 18,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18), border: Border.all(color: OpticalGlassTokens.border))
              .withLauncherCorners(),
          child: Row(children: <Widget>[
            content.dragHandle,
            const SizedBox(width: 14),
            Expanded(child: content.textField),
            if (content.trailingBadge != null) content.trailingBadge!,
            if (content.isSearching)
              Padding(
                padding: const EdgeInsets.only(left: 10),
                child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: OpticalGlassTokens.accent)),
              ),
          ]),
        ),
      ),
    );
  }
}

class OpticalGlassLauncherFrame extends StatelessWidget {
  const OpticalGlassLauncherFrame({super.key, required this.resultCount, required this.child});
  final int resultCount;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LiquidMetalMotion(
      child: OpticalGlassSurface(
        raised: false,
        radius: 24,
        child: OpticalGlassSurface(
          overlay: true,
          radius: 24,
          child: LauncherSurface(
            decoration: _opticalGlassOuterDecoration(),
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              if (user.launcherShowTitlebar)
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 12, 14, 10),
                  child: Row(children: <Widget>[
                    Expanded(
                        child: DragToMoveArea(
                            child: Row(children: <Widget>[
                      OpticalGlassSurface(
                          radius: 14,
                          selected: true,
                          child: SizedBox(
                              width: 28,
                              height: 28,
                              child: Icon(Icons.lens_blur_rounded, size: 20, color: OpticalGlassTokens.accent))),
                      const SizedBox(width: 10),
                      Flexible(
                          child: Text('Optical Glass',
                              overflow: TextOverflow.ellipsis,
                              style: OpticalGlassTokens.font(size: 14, weight: FontWeight.w600))),
                    ]))),
                    _control('Minimize', Icons.remove_rounded, () {
                      windowManager.minimize();
                    }),
                    const SizedBox(width: 6),
                    _control('Hide launcher', Icons.close_rounded, () {
                      windowManager.hide();
                    }),
                  ]),
                ),
              Flexible(fit: FlexFit.loose, child: child),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                child: OpticalGlassSurface(
                  radius: 12,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    child: Row(children: <Widget>[
                      Expanded(
                          child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(children: <Widget>[
                                _hint('↑ ↓', 'Navigate'),
                                _hint('Enter', 'Open'),
                                _hint('Ctrl P', 'Preview'),
                              ]))),
                      const SizedBox(width: 8),
                      Text(Globals.isLauncherPluginActive ? "PLUGIN" : '$resultCount results',
                          style: OpticalGlassTokens.font(size: 11, color: OpticalGlassTokens.dim)),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _control(String label, IconData icon, VoidCallback onPressed) => OpticalGlassSurface(
        radius: 14,
        child: SizedBox(
            width: 28,
            height: 28,
            child: IconButton(
              tooltip: label,
              padding: EdgeInsets.zero,
              onPressed: onPressed,
              icon: Icon(icon, size: 16, color: OpticalGlassTokens.dim),
            )),
      );

  Widget _hint(String key, String label) => Padding(
        padding: const EdgeInsets.only(right: 16),
        child: Row(children: <Widget>[
          Text(key, style: OpticalGlassTokens.font(size: 11, weight: FontWeight.w600)),
          const SizedBox(width: 6),
          Text(label, style: OpticalGlassTokens.font(size: 11, color: OpticalGlassTokens.dim)),
        ]),
      );
}
