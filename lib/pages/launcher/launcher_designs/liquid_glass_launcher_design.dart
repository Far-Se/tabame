part of '../launcher_design_builder.dart';

BoxDecoration _liquidGlassOuterDecoration() => BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: LiquidGlassTokens.edge, width: 0.8),
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: Colors.black.withValues(alpha: LiquidGlassTokens.isDark ? 0.26 : 0.12),
          blurRadius: 28,
          offset: const Offset(0, 12),
        ),
      ],
    );

class _LiquidGlassSearchBar extends StatelessWidget {
  const _LiquidGlassSearchBar(this.content);

  final _LauncherSearchBarContent content;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: LiquidGlassSurface(
          kind: LiquidGlassKind.search,
          radius: 18,
          opacity: 0.88,
          child: Container(
            constraints: const BoxConstraints(minHeight: 62),
            padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: MediaQuery.highContrastOf(context) ? LiquidGlassTokens.foreground : LiquidGlassTokens.border,
                width: 0.8,
              ),
            ).withLauncherCorners(),
            child: Row(children: <Widget>[
              content.dragHandle,
              const SizedBox(width: 13),
              Expanded(child: _LauncherSearchField(content)),
              if (content.isSearching)
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: LauncherTheme.accentOf(context),
                      semanticsLabel: 'Searching',
                    ),
                  ),
                ),
            ]),
          ),
        ),
      );
}

class LiquidGlassLauncherFrame extends StatelessWidget {
  const LiquidGlassLauncherFrame({super.key, required this.child, required this.resultCount});

  final Widget child;
  final int resultCount;

  @override
  Widget build(BuildContext context) => LiquidGlassMotion(
        child: LauncherSurface(
          decoration: _liquidGlassOuterDecoration(),
          child: LiquidGlassSurface(
            opacity: Design.glassOpacity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (user.launcherShowTitlebar)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 10, 16, 0),
                    child: Row(children: <Widget>[
                      Expanded(
                        child: DragToMoveArea(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text('Tabame',
                                overflow: TextOverflow.ellipsis,
                                style: LiquidGlassTokens.font(
                                  size: Design.baseFontSize + 2,
                                  color: LiquidGlassTokens.dim,
                                  weight: FontWeight.w600,
                                )),
                          ),
                        ),
                      ),
                      _control('Minimize', Icons.remove_rounded, () => windowManager.minimize()),
                      const SizedBox(width: 4),
                      _control('Hide launcher', Icons.close_rounded, () => windowManager.hide()),
                    ]),
                  ),
                Flexible(fit: FlexFit.loose, child: child),
                _footer(context),
              ],
            ),
          ),
        ),
      );

  Widget _control(String label, IconData icon, VoidCallback onPressed) => SizedBox(
        width: 30,
        height: 30,
        child: IconButton(
          tooltip: label,
          padding: EdgeInsets.zero,
          onPressed: onPressed,
          icon: Icon(icon, size: 16, color: LiquidGlassTokens.dim),
          style: IconButton.styleFrom(hoverColor: LiquidGlassTokens.foreground.withValues(alpha: 0.07)),
        ),
      );

  Widget _footer(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 2, 24, 12),
        child: LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
          final bool plugin = Globals.isLauncherPluginActive;
          final double textScale = MediaQuery.textScalerOf(context).scale(Design.baseFontSize + 1) / 11;
          return Row(children: <Widget>[
            Expanded(
              child: Text(
                plugin ? 'Plugin' : '$resultCount ${resultCount == 1 ? 'result' : 'results'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: LiquidGlassTokens.font(size: Design.baseFontSize + 1, color: LiquidGlassTokens.dim),
              ),
            ),
            if (!plugin && constraints.maxWidth > 380 * textScale) ...<Widget>[
              _hint('Enter', 'Open'),
              const SizedBox(width: 18),
              _hint('Ctrl K', 'Actions'),
            ],
          ]);
        }),
      );

  Widget _hint(String key, String label) => Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Text(label, style: LiquidGlassTokens.font(size: Design.baseFontSize + 1, color: LiquidGlassTokens.dim)),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: LiquidGlassTokens.foreground.withValues(alpha: 0.045),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: LiquidGlassTokens.border, width: 0.7),
          ).withLauncherCorners(),
          child: Text(key, style: LiquidGlassTokens.font(size: Design.baseFontSize, weight: FontWeight.w500)),
        ),
      ]);
}
