part of '../launcher_design_builder.dart';

BoxDecoration _crtOuterDecoration() {
  return BoxDecoration(
      color: CrtTokens.background,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: CrtTokens.border));
}

class _CrtSearchBar extends StatelessWidget {
  const _CrtSearchBar(this.content);

  final _LauncherSearchBarContent content;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 14),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: CrtTokens.border))),
      child: Row(children: <Widget>[
        content.dragHandle,
        const SizedBox(width: 10),
        Text('>', style: CrtTokens.font(size: 22, color: CrtTokens.accent)),
        const SizedBox(width: 12),
        Expanded(child: content.textField),
        if (content.trailingBadge != null) content.trailingBadge!,
        if (content.isSearching)
          Padding(
              padding: const EdgeInsets.only(left: 8),
              child: SizedBox(
                  width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5, color: CrtTokens.accent))),
      ]),
    );
  }
}

class CrtLauncherFrame extends StatelessWidget {
  const CrtLauncherFrame({super.key, required this.resultCount, required this.child});
  final int resultCount;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LauncherSurface(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
          color: CrtTokens.bezel, borderRadius: BorderRadius.circular(18), border: Border.all(color: CrtTokens.border)),
      child: LauncherClip(
          borderRadius: BorderRadius.circular(12),
          child: CrtSurface(
            background: CrtTokens.background,
            accent: CrtTokens.accent,
            child: ColoredBox(
                color: CrtTokens.background,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                    if (user.launcherShowTitlebar)
                      SizedBox(
                          height: 30,
                          child: Row(children: <Widget>[
                            Expanded(
                                child: DragToMoveArea(
                                    child: Row(children: <Widget>[
                              Icon(Icons.circle, size: 6, color: CrtTokens.accent),
                              const SizedBox(width: 8),
                              Flexible(
                                  child: Text('TABAME / CRT',
                                      overflow: TextOverflow.ellipsis, style: CrtTokens.font(size: 11, spacing: 1.8))),
                            ]))),
                            IconButton(
                                tooltip: 'Hide launcher',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints.tightFor(width: 30, height: 30),
                                onPressed: () {
                                  windowManager.hide();
                                },
                                icon: Icon(Icons.close, size: 15, color: CrtTokens.dim)),
                          ])),
                    Flexible(fit: FlexFit.loose, child: child),
                    Container(
                        padding: const EdgeInsets.fromLTRB(6, 10, 6, 4),
                        decoration: BoxDecoration(border: Border(top: BorderSide(color: CrtTokens.border))),
                        child: Row(children: <Widget>[
                          Expanded(
                              child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Text('↑↓ Navigate   Enter Open   Ctrl+P Preview',
                                      style: CrtTokens.font(size: 11, color: CrtTokens.dim)))),
                          const SizedBox(width: 12),
                          Text('$resultCount results', style: CrtTokens.font(size: 11, color: CrtTokens.accent)),
                        ])),
                  ]),
                )),
          )),
    );
  }
}
