part of '../launcher_design_builder.dart';

class CapillarySearchBar extends StatelessWidget {
  const CapillarySearchBar({
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
            dragHandle,
            const SizedBox(width: 12),
            Expanded(child: textField),
            if (trailingBadge != null) trailingBadge!,
            if (isSearching)
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
  const CapillaryLauncherFrame({
    super.key,
    required this.surface,
    required this.accent,
    required this.onSurface,
    required this.resultCount,
    required this.child,
    this.queryController,
  });

  final Color surface;
  final Color accent;
  final Color onSurface;
  final int resultCount;
  final Widget child;
  final TextEditingController? queryController;

  @override
  Widget build(BuildContext context) {
    final CapillaryTokens capillary = CapillaryTokens.of(context);
    return LauncherTheme(
      data: const LauncherThemeData(design: LauncherDesign.capillary),
      child: CapillaryMotion(
        queryController: queryController,
        child: CapillarySurface(
          kind: CapillarySurfaceKind.paper,
          radius: 8,
          child: CapillarySurface(
            kind: CapillarySurfaceKind.overlay,
            radius: 8,
            child: Container(
              decoration: LauncherDesign.capillary.outerDecoration(surface: surface, accent: accent),
              child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                // Padding(
                //   padding: const EdgeInsets.fromLTRB(20, 10, 10, 2),
                //   child: Row(children: <Widget>[
                //     Expanded(
                //       child: DragToMoveArea(
                //         child: Row(children: <Widget>[
                //           Icon(Icons.water_drop_outlined, size: 17, color: capillary.accent),
                //           const SizedBox(width: 9),
                //           Flexible(child: Text('Capillary', overflow: TextOverflow.ellipsis, style: capillary.title())),
                //         ]),
                //       ),
                //     ),
                //     _control(capillary, 'Minimize', Icons.remove_rounded, () {
                //       windowManager.minimize();
                //     }),
                //     const SizedBox(width: 2),
                //     _control(capillary, 'Hide launcher', Icons.close_rounded, () {
                //       windowManager.hide();
                //     }),
                //   ]),
                // ),
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
      ),
    );
  }

  Widget _control(CapillaryTokens capillary, String label, IconData icon, VoidCallback action) => CapillarySurface(
        child: SizedBox(
          width: 28,
          height: 28,
          child: IconButton(
            tooltip: label,
            padding: EdgeInsets.zero,
            onPressed: action,
            style: const ButtonStyle(overlayColor: WidgetStatePropertyAll<Color>(Colors.transparent)),
            icon: Icon(icon, size: 16, color: capillary.dim),
          ),
        ),
      );

  Widget _hint(CapillaryTokens capillary, String key, String label) => Padding(
        padding: const EdgeInsets.only(right: 16),
        child: Row(children: <Widget>[
          Text(key, style: capillary.font(size: 11, weight: FontWeight.w600)),
          const SizedBox(width: 5),
          Text(label, style: capillary.font(size: 11, color: capillary.dim)),
        ]),
      );
}
