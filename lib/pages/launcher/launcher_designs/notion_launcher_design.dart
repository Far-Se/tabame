part of '../launcher_design_builder.dart';

BoxDecoration notionLauncherOuterDecoration(Color surface) {
  final bool isDark = surface.computeLuminance() < 0.5;
  return BoxDecoration(
    color: NotionTokens.canvas(isDark),
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: NotionTokens.border(isDark)),
    boxShadow: <BoxShadow>[
      BoxShadow(
        color: Colors.black.withAlpha(isDark ? 100 : 32),
        blurRadius: 28,
        spreadRadius: -8,
        offset: const Offset(0, 13),
      ),
      BoxShadow(
        color: Colors.black.withAlpha(isDark ? 28 : 10),
        blurRadius: 3,
        offset: const Offset(0, 1),
      ),
    ],
  );
}

class NotionLauncherSearchBar extends StatelessWidget {
  const NotionLauncherSearchBar({
    super.key,
    required this.accent,
    required this.onSurface,
    required this.dragHandle,
    required this.textField,
    required this.trailingBadge,
    required this.isSearching,
  });

  final Color accent;
  final Color onSurface;
  final Widget dragHandle;
  final Widget textField;
  final Widget? trailingBadge;
  final bool isSearching;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return ColoredBox(
      color: NotionTokens.canvas(isDark),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          DragToMoveArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 6),
              child: Row(
                children: <Widget>[
                  _NotionLauncherMark(isDark: isDark, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'QuickLaunch',
                    style: NotionTokens.ui(
                      fontSize: Design.baseFontSize + 1,
                      fontWeight: FontWeight.w600,
                      color: onSurface,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 3),
                  _NotionKeycap(label: WinUtils.shellUser()),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
            child: Row(
              children: <Widget>[
                dragHandle,
                const SizedBox(width: 9),
                Expanded(
                  child: Stack(
                    alignment: Alignment.centerRight,
                    children: <Widget>[
                      textField,
                      if (trailingBadge != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: trailingBadge!,
                        ),
                    ],
                  ),
                ),
                if (isSearching)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 1.8, color: accent),
                    ),
                  ),
              ],
            ),
          ),
          Container(height: 1, color: NotionTokens.border(isDark)),
        ],
      ),
    );
  }
}

class NotionLauncherHeader extends StatelessWidget {
  const NotionLauncherHeader({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 3),
      child: Text(
        label,
        style: NotionTokens.ui(
          fontSize: Design.baseFontSize,
          fontWeight: FontWeight.w600,
          color: NotionTokens.dim(isDark),
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}

class NotionLauncherFrame extends StatelessWidget {
  const NotionLauncherFrame({
    super.key,
    required this.child,
    required this.surface,
    required this.resultCount,
  });

  final Widget child;
  final Color surface;
  final int resultCount;

  @override
  Widget build(BuildContext context) {
    final bool isDark = surface.computeLuminance() < 0.5;
    return LauncherTheme(
      data: const LauncherThemeData(design: LauncherDesign.notion),
      child: Container(
        constraints: const BoxConstraints(minHeight: 360),
        decoration: notionLauncherOuterDecoration(surface),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: ColoredBox(
            color: NotionTokens.canvas(isDark),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                child,
                _NotionLauncherFooter(isDark: isDark, resultCount: resultCount),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NotionLauncherFooter extends StatelessWidget {
  const _NotionLauncherFooter({required this.isDark, required this.resultCount});

  final bool isDark;
  final int resultCount;

  Widget _hint(String keys, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _NotionKeycap(label: keys),
        const SizedBox(width: 5),
        Text(
          label,
          style: NotionTokens.ui(
            fontSize: Design.baseFontSize - 1,
            color: NotionTokens.dim(isDark),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
      decoration: BoxDecoration(
        color: NotionTokens.sidebar(isDark),
        border: Border(top: BorderSide(color: NotionTokens.border(isDark))),
      ),
      child: Row(
        children: <Widget>[
          _hint('↑↓', 'select'),
          const SizedBox(width: 12),
          _hint('↵', 'open'),
          const SizedBox(width: 12),
          _hint('esc', 'close'),
          const Spacer(),
          Text(
            Globals.isLauncherPluginActive ? "PLUGIN" : (resultCount == 1 ? '1 result' : '$resultCount results'),
            style: NotionTokens.ui(
              fontSize: Design.baseFontSize - 1,
              color: NotionTokens.dim(isDark),
            ),
          ),
          DateTimeWidget(
              padding: const EdgeInsets.only(left: 10),
              style: NotionTokens.ui(
                fontSize: Design.baseFontSize - 1,
                color: NotionTokens.dim(isDark),
              )),
        ],
      ),
    );
  }
}

class _NotionKeycap extends StatelessWidget {
  const _NotionKeycap({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      constraints: const BoxConstraints(minWidth: 17),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: NotionTokens.selection(isDark),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: NotionTokens.border(isDark)),
      ),
      child: Text(
        label,
        style: NotionTokens.ui(
          fontSize: Design.baseFontSize - 1.5,
          fontWeight: FontWeight.w500,
          color: NotionTokens.dim(isDark),
          height: 1.25,
        ),
      ),
    );
  }
}

class _NotionLauncherMark extends StatelessWidget {
  const _NotionLauncherMark({required this.isDark, required this.size});

  final bool isDark;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: NotionTokens.foreground(isDark).withAlpha(190)),
      ),
      child: Text(
        'T',
        style: TextStyle(
          fontFamily: 'Georgia',
          fontSize: size * 0.64,
          fontWeight: FontWeight.w700,
          color: NotionTokens.foreground(isDark),
          height: 1,
        ),
      ),
    );
  }
}
