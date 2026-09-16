part of '../launcher_design_builder.dart';

class OpticalGlassSearchBar extends StatelessWidget {
  const OpticalGlassSearchBar(
      {super.key,
      required this.dragHandle,
      required this.textField,
      required this.trailingBadge,
      required this.isSearching});
  final Widget dragHandle;
  final Widget textField;
  final Widget? trailingBadge;
  final bool isSearching;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: OpticalGlassSurface(
          selected: true,
          radius: 18,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18), border: Border.all(color: OpticalGlassTokens.border)),
            child: Row(children: <Widget>[
              dragHandle,
              const SizedBox(width: 14),
              Expanded(child: textField),
              if (trailingBadge != null) trailingBadge!,
              if (isSearching)
                Padding(
                  padding: EdgeInsets.only(left: 10),
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

class OpticalGlassLauncherFrame extends StatelessWidget {
  const OpticalGlassLauncherFrame(
      {super.key,
      required this.surface,
      required this.accent,
      required this.onSurface,
      required this.resultCount,
      required this.child});
  final Color surface;
  final Color accent;
  final Color onSurface;
  final int resultCount;
  final Widget child;

  @override
  Widget build(BuildContext context) => LauncherTheme(
        data: const LauncherThemeData(design: LauncherDesign.opticalGlass),
        child: LiquidMetalMotion(
          child: OpticalGlassSurface(
            raised: false,
            radius: 24,
            child: OpticalGlassSurface(
              overlay: true,
              radius: 24,
              child: Container(
                decoration: LauncherDesign.opticalGlass.outerDecoration(surface: surface, accent: accent),
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
                          Text('$resultCount results',
                              style: OpticalGlassTokens.font(size: 11, color: OpticalGlassTokens.dim)),
                        ]),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );

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
