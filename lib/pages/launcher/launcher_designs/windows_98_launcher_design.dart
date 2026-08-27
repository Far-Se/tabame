part of '../launcher_design_builder.dart';

BoxDecoration windows98LauncherOuterDecoration() {
  return BoxDecoration(
    color: Windows98Tokens.face,
    border: Border(
      left: BorderSide(color: Windows98Tokens.light, width: 2),
      top: BorderSide(color: Windows98Tokens.light, width: 2),
      right: BorderSide(color: Windows98Tokens.dark, width: 2),
      bottom: BorderSide(color: Windows98Tokens.dark, width: 2),
    ),
    boxShadow: <BoxShadow>[
      const BoxShadow(color: Color(0x66000000), offset: Offset(4, 5), blurRadius: 0),
    ],
  );
}

class Windows98LauncherSearchBar extends StatelessWidget {
  const Windows98LauncherSearchBar({
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
    return ColoredBox(
      color: Windows98Tokens.face,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(2, 2, 2, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            DragToMoveArea(
              child: Container(
                height: 23,
                padding: const EdgeInsets.fromLTRB(3, 2, 2, 2),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: <Color>[Windows98Tokens.title, Windows98Tokens.titleLight],
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    const _Windows98Flag(size: 16),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Tabame Search',
                        style: Windows98Tokens.system(
                          fontSize: Design.baseFontSize + 1,
                          fontWeight: FontWeight.w700,
                          color: Windows98Tokens.light,
                          height: 1,
                        ),
                      ),
                    ),
                    const _Windows98CaptionButton(label: '_'),
                    const SizedBox(width: 2),
                    const _Windows98CaptionButton(label: '□'),
                    const SizedBox(width: 2),
                    const _Windows98CaptionButton(
                      label: '×',
                      onTap: QuickMenuFunctions.hideQuickMenu,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(7, 7, 7, 7),
              child: Row(
                children: <Widget>[
                  Text(
                    'Look for:',
                    style: Windows98Tokens.system(
                      fontSize: Design.baseFontSize,
                      color: Windows98Tokens.foreground,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: _Windows98Bevel(
                      raised: false,
                      child: ColoredBox(
                        color: Windows98Tokens.field,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(5, 1, 4, 1),
                          child: Row(
                            children: <Widget>[
                              dragHandle,
                              const SizedBox(width: 5),
                              Expanded(
                                child: Stack(
                                  alignment: Alignment.centerRight,
                                  children: <Widget>[
                                    textField,
                                    if (trailingBadge != null) trailingBadge!,
                                  ],
                                ),
                              ),
                              if (isSearching)
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 4),
                                  child: SizedBox(
                                    width: 13,
                                    height: 13,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Windows98Tokens.title,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const _Windows98EtchedLine(),
          ],
        ),
      ),
    );
  }
}

class Windows98LauncherHeader extends StatelessWidget {
  const Windows98LauncherHeader({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 3),
      child: Row(
        children: <Widget>[
          Text(
            label,
            style: Windows98Tokens.system(
              fontSize: Design.baseFontSize,
              fontWeight: FontWeight.w700,
              color: Windows98Tokens.foreground,
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(child: _Windows98EtchedLine()),
        ],
      ),
    );
  }
}

class Windows98LauncherFrame extends StatelessWidget {
  const Windows98LauncherFrame({
    super.key,
    required this.child,
    required this.resultCount,
    Color? surface,
    Color? accent,
    Color? onSurface,
  });

  final Widget child;
  final int resultCount;

  @override
  Widget build(BuildContext context) {
    return LauncherTheme(
      data: const LauncherThemeData(design: LauncherDesign.windows98),
      child: Container(
        constraints: const BoxConstraints(minHeight: 360),
        decoration: windows98LauncherOuterDecoration(),
        child: Padding(
          padding: const EdgeInsets.all(1),
          child: Container(
            decoration: BoxDecoration(
              color: Windows98Tokens.face,
              border: Border(
                left: BorderSide(color: Windows98Tokens.highlight),
                top: BorderSide(color: Windows98Tokens.highlight),
                right: BorderSide(color: Windows98Tokens.shadow),
                bottom: BorderSide(color: Windows98Tokens.shadow),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                child,
                _Windows98Footer(resultCount: resultCount),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Windows98Footer extends StatelessWidget {
  const _Windows98Footer({required this.resultCount});

  final int resultCount;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Windows98Tokens.face,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(3, 2, 3, 3),
        child: Row(
          children: <Widget>[
            Expanded(
              child: _Windows98Bevel(
                raised: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(5, 3, 5, 3),
                  child: Row(
                    children: <Widget>[
                      DateTimeWidget(
                        padding: const EdgeInsets.only(right: 10),
                        style: Windows98Tokens.system(
                          fontSize: Design.baseFontSize - 1,
                          color: Windows98Tokens.foreground,
                          height: 1,
                        ),
                      ),
                      Text(
                        Globals.isLauncherPluginActive
                            ? "PLUGIN"
                            : (resultCount == 1 ? '1 object' : '$resultCount objects'),
                        style: Windows98Tokens.system(
                          fontSize: Design.baseFontSize - 1,
                          color: Windows98Tokens.foreground,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 3),
            _Windows98Bevel(
              raised: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(5, 3, 5, 3),
                child: Text(
                  'Enter: Open   →: Actions   Esc: Cancel',
                  style: Windows98Tokens.system(
                    fontSize: Design.baseFontSize - 1,
                    color: Windows98Tokens.foreground,
                    height: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Windows98CaptionButton extends StatelessWidget {
  const _Windows98CaptionButton({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: _Windows98Bevel(
        raised: true,
        child: SizedBox(
          width: 17,
          height: 17,
          child: ColoredBox(
            color: Windows98Tokens.face,
            child: Center(
              child: Text(
                label,
                style: Windows98Tokens.system(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Windows98Tokens.dark,
                  height: 0.9,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Windows98EtchedLine extends StatelessWidget {
  const _Windows98EtchedLine();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ColoredBox(color: Windows98Tokens.shadow, child: const SizedBox(height: 1, width: double.infinity)),
        ColoredBox(color: Windows98Tokens.light, child: const SizedBox(height: 1, width: double.infinity)),
      ],
    );
  }
}

class _Windows98Bevel extends StatelessWidget {
  const _Windows98Bevel({required this.raised, required this.child});

  final bool raised;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Color outerTopLeft = raised ? Windows98Tokens.light : Windows98Tokens.dark;
    final Color outerBottomRight = raised ? Windows98Tokens.dark : Windows98Tokens.light;
    final Color innerTopLeft = raised ? Windows98Tokens.highlight : Windows98Tokens.shadow;
    final Color innerBottomRight = raised ? Windows98Tokens.shadow : Windows98Tokens.highlight;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: outerTopLeft),
          top: BorderSide(color: outerTopLeft),
          right: BorderSide(color: outerBottomRight),
          bottom: BorderSide(color: outerBottomRight),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: innerTopLeft),
            top: BorderSide(color: innerTopLeft),
            right: BorderSide(color: innerBottomRight),
            bottom: BorderSide(color: innerBottomRight),
          ),
        ),
        child: child,
      ),
    );
  }
}

class _Windows98Flag extends StatelessWidget {
  const _Windows98Flag({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: GridView.count(
        crossAxisCount: 2,
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 1,
        crossAxisSpacing: 1,
        children: const <Widget>[
          ColoredBox(color: Color(0xFFFF0000)),
          ColoredBox(color: Color(0xFF00A000)),
          ColoredBox(color: Color(0xFF0000FF)),
          ColoredBox(color: Color(0xFFFFFF00)),
        ],
      ),
    );
  }
}
