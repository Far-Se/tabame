part of '../launcher_design_builder.dart';

BoxDecoration _toonOuterDecoration() {
  return BoxDecoration(
    color: ToonTokens.background,
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: ToonTokens.orange.withAlpha(180), width: 1.5),
    boxShadow: <BoxShadow>[
      BoxShadow(
        color: ToonTokens.ink.withAlpha(220),
        blurRadius: 0,
        offset: const Offset(5, 5),
      ),
    ],
  );
}

class _ToonSearchBar extends StatelessWidget {
  const _ToonSearchBar(this.content);

  final _LauncherSearchBarContent content;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: ToonTokens.panel,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: ToonTokens.orange.withAlpha(190), width: 2),
          boxShadow: <BoxShadow>[
            BoxShadow(color: ToonTokens.ink.withAlpha(180), offset: const Offset(2, 3), blurRadius: 0),
          ],
        ),
        child: Row(
          children: <Widget>[
            content.dragHandle,
            const SizedBox(width: 8),
            const SizedBox(width: 9),
            Expanded(child: content.textField),
            if (content.trailingBadge != null) content.trailingBadge!,
            if (content.isSearching)
              Padding(
                padding: const EdgeInsets.only(left: 10),
                child: SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(strokeWidth: 2, color: ToonTokens.red),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ToonLauncherFrame extends StatelessWidget {
  const ToonLauncherFrame({super.key, required this.resultCount, required this.child});

  final int resultCount;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _toonOuterDecoration(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CrtSurface(
          shaderAsset: 'resources/shaders/toon.frag',
          animateEffect: false,
          effectName: 'Toon',
          background: ToonTokens.background,
          accent: ToonTokens.orange,
          child: ColoredBox(
            color: ToonTokens.background,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (user.launcherShowTitlebar)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(17, 10, 11, 5),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: DragToMoveArea(
                            child: Row(
                              children: <Widget>[
                                Icon(Icons.bolt_rounded, size: 18, color: ToonTokens.orange),
                                const SizedBox(width: 7),
                                Text(
                                  'TABAME // TOON',
                                  style: ToonTokens.font(
                                    size: 12,
                                    color: ToonTokens.cream,
                                    spacing: 1.3,
                                    weight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 9),
                                Transform.rotate(
                                  angle: 0.785398,
                                  child: SizedBox(
                                    width: 6,
                                    height: 6,
                                    child: ColoredBox(color: ToonTokens.red),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        _control('Minimize', Icons.remove_rounded, windowManager.minimize),
                        const SizedBox(width: 3),
                        _control('Hide launcher', Icons.close_rounded, windowManager.hide),
                      ],
                    ),
                  ),
                Flexible(fit: FlexFit.loose, child: child),
                Container(
                  padding: const EdgeInsets.fromLTRB(17, 8, 15, 9),
                  decoration: BoxDecoration(
                    color: ToonTokens.panel,
                    border: Border(top: BorderSide(color: ToonTokens.orange.withAlpha(105), width: 2)),
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: <Widget>[
                              _hint('UP/DOWN', 'Navigate'),
                              _hint('ENTER', 'Open'),
                              _hint('CTRL P', 'Preview'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${resultCount.toString().padLeft(2, '0')} INKED',
                        style: ToonTokens.font(size: 10, color: ToonTokens.dim, spacing: 1.1),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _control(String label, IconData icon, VoidCallback onPressed) {
    return SizedBox(
      width: 28,
      height: 26,
      child: IconButton(
        tooltip: label,
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        icon: Icon(icon, size: 15, color: ToonTokens.dim),
      ),
    );
  }

  Widget _hint(String key, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 19),
      child: Row(
        children: <Widget>[
          Text(key, style: ToonTokens.font(size: 10, color: ToonTokens.cream, spacing: 0.6, weight: FontWeight.w700)),
          const SizedBox(width: 5),
          Text(label, style: ToonTokens.font(size: 10, color: ToonTokens.dim)),
        ],
      ),
    );
  }
}
