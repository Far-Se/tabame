part of '../launcher_design_builder.dart';

BoxDecoration windowsXpLauncherOuterDecoration() {
  return BoxDecoration(
    color: WindowsXpTokens.surface,
    borderRadius: BorderRadius.circular(7),
    border: Border.all(color: WindowsXpTokens.blueDark, width: 2),
    boxShadow: const <BoxShadow>[
      BoxShadow(color: Color(0x77000000), blurRadius: 16, offset: Offset(5, 8)),
      BoxShadow(color: WindowsXpTokens.blueHighlight, offset: Offset(-1, -1)),
    ],
  );
}

class WindowsXpLauncherSearchBar extends StatelessWidget {
  const WindowsXpLauncherSearchBar({
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        DragToMoveArea(
          child: Container(
            height: 37,
            padding: const EdgeInsets.fromLTRB(9, 4, 8, 4),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  WindowsXpTokens.blueLight,
                  WindowsXpTokens.blue,
                  Color(0xFF0B48C9),
                ],
                stops: <double>[0, 0.5, 1],
              ),
              border: Border(
                top: BorderSide(color: WindowsXpTokens.blueHighlight),
                bottom: BorderSide(color: WindowsXpTokens.blueDark),
              ),
            ),
            child: Row(
              children: <Widget>[
                const _WindowsXpFlag(size: 20),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Tabame Search',
                    style: WindowsXpTokens.tahoma(
                      fontSize: Design.baseFontSize + 3,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFF8FBFF),
                      height: 1.1,
                    ).copyWith(
                      shadows: const <Shadow>[
                        Shadow(color: Color(0x99002A8E), offset: Offset(1, 1)),
                      ],
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: QuickMenuFunctions.hideQuickMenu,
                  child: Container(
                    width: 21,
                    height: 21,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: <Color>[Color(0xFFF39C7C), Color(0xFFC9331D)],
                      ),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: const Color(0xFFFFC4B5)),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(color: Color(0xFF7E1D10), offset: Offset(1, 1)),
                      ],
                    ),
                    child: const Icon(Icons.close, size: 15, color: Color(0xFFFFF8F5)),
                  ),
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: WindowsXpTokens.surface,
            border: const Border(bottom: BorderSide(color: Color(0xFFACA899))),
          ),
          child: Row(
            children: <Widget>[
              Text(
                'Search:',
                style: WindowsXpTokens.tahoma(
                  fontSize: Design.baseFontSize + 1,
                  color: WindowsXpTokens.foreground,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 31),
                  padding: const EdgeInsets.fromLTRB(6, 1, 5, 1),
                  decoration: BoxDecoration(
                    color: WindowsXpTokens.controlLight,
                    border: Border(
                      left: const BorderSide(color: WindowsXpTokens.controlShadow, width: 2),
                      top: const BorderSide(color: WindowsXpTokens.controlShadow, width: 2),
                      right: BorderSide(color: WindowsXpTokens.controlLight),
                      bottom: BorderSide(color: WindowsXpTokens.controlLight),
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      dragHandle,
                      const SizedBox(width: 6),
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
                          padding: EdgeInsets.only(left: 6, right: 2),
                          child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: WindowsXpTokens.selection,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class WindowsXpLauncherHeader extends StatelessWidget {
  const WindowsXpLauncherHeader({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: WindowsXpTokens.tahoma(
              fontSize: Design.baseFontSize + 1,
              fontWeight: FontWeight.w700,
              color: WindowsXpTokens.blueDark,
            ),
          ),
          const SizedBox(height: 3),
          Container(
            height: 2,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[
                  WindowsXpTokens.orange,
                  Color(0xFFFFC66D),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class WindowsXpLauncherFrame extends StatelessWidget {
  const WindowsXpLauncherFrame({
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
      data: const LauncherThemeData(design: LauncherDesign.windowsXp),
      child: Container(
        constraints: const BoxConstraints(minHeight: 360),
        decoration: windowsXpLauncherOuterDecoration(),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: ColoredBox(
            color: WindowsXpTokens.paper,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                child,
                _WindowsXpFooter(resultCount: resultCount),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WindowsXpFooter extends StatelessWidget {
  const _WindowsXpFooter({required this.resultCount});

  final int resultCount;

  Widget _hint(String keyLabel, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          constraints: const BoxConstraints(minWidth: 18),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: WindowsXpTokens.surface,
            border: Border(
              left: BorderSide(color: WindowsXpTokens.controlLight),
              top: BorderSide(color: WindowsXpTokens.controlLight),
              right: const BorderSide(color: WindowsXpTokens.controlShadow),
              bottom: const BorderSide(color: WindowsXpTokens.controlShadow),
            ),
          ),
          child: Text(
            keyLabel,
            style: WindowsXpTokens.tahoma(
              fontSize: Design.baseFontSize - 1,
              fontWeight: FontWeight.w700,
              color: WindowsXpTokens.foreground,
            ),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: WindowsXpTokens.tahoma(
            fontSize: Design.baseFontSize - 1,
            color: const Color(0xFFF4F8FF),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            WindowsXpTokens.blueLight,
            WindowsXpTokens.blue,
            WindowsXpTokens.blueDark,
          ],
        ),
        border: Border(top: BorderSide(color: WindowsXpTokens.blueHighlight)),
      ),
      child: Row(
        children: <Widget>[
          _hint('Enter', 'Open'),
          const SizedBox(width: 12),
          _hint('→', 'Actions'),
          const SizedBox(width: 12),
          _hint('Esc', 'Cancel'),
          const Spacer(),
          Text(
            Globals.isLauncherPluginActive
                ? "PLUGIN"
                : (resultCount == 1 ? '1 item found' : '$resultCount items found'),
            style: WindowsXpTokens.tahoma(
              fontSize: Design.baseFontSize - 1,
              color: const Color(0xFFDDE9FF),
            ),
          ),
          DateTimeWidget(
            padding: const EdgeInsets.only(left: 10),
            style: WindowsXpTokens.tahoma(
              fontSize: Design.baseFontSize - 1,
              color: const Color(0xFFDDE9FF),
            ),
          ),
        ],
      ),
    );
  }
}

class _WindowsXpFlag extends StatelessWidget {
  const _WindowsXpFlag({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.08,
      child: SizedBox(
        width: size,
        height: size,
        child: GridView.count(
          crossAxisCount: 2,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 1.2,
          crossAxisSpacing: 1.2,
          children: const <Widget>[
            ColoredBox(color: Color(0xFFF25022)),
            ColoredBox(color: Color(0xFF7FBA00)),
            ColoredBox(color: Color(0xFF00A4EF)),
            ColoredBox(color: Color(0xFFFFB900)),
          ],
        ),
      ),
    );
  }
}
