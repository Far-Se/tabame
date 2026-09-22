part of '../launcher_design_builder.dart';

BoxDecoration _fluentOuterDecoration(Color surface) {
  // Mica window — [surface] is the forced Win11 neutral. The 8px corner,
  // a hairline stroke, and the broad soft shadow Windows 11 puts under
  // every flyout.
  final bool fluentDark = ThemeData.estimateBrightnessForColor(surface) == Brightness.dark;
  return BoxDecoration(
    borderRadius: BorderRadius.circular(Design.borderRadius),
    color: surface,
    border: Border.all(color: fluentDark ? Colors.white.withAlpha(24) : Colors.black.withAlpha(20)),
    boxShadow: <BoxShadow>[
      BoxShadow(
        color: Colors.black.withAlpha(80),
        blurRadius: 34,
        spreadRadius: -8,
        offset: const Offset(0, 16),
      ),
    ],
  );
}

class _FluentSearchBar extends StatelessWidget {
  const _FluentSearchBar(this.content);

  final _LauncherSearchBarContent content;

  @override
  Widget build(BuildContext context) {
    final Color accent = LauncherTheme.accentOf(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    // A WinUI AutoSuggestBox: faint layer fill, hairline stroke, and — since
    // the launcher input is always focused — the 2px accent bottom underline.
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Container(
        decoration: BoxDecoration(
          color: FluentTokens.fill(isDark),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FluentTokens.stroke(isDark)),
        ).withLauncherCorners(),
        child: LauncherClip(
          borderRadius: BorderRadius.circular(4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 10, 7),
                child: Row(
                  children: <Widget>[
                    content.dragHandle,
                    const SizedBox(width: 10),
                    Expanded(
                      child: _LauncherSearchField(content),
                    ),
                    if (content.isSearching)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: accent),
                        ),
                      ),
                  ],
                ),
              ),
              // Focus underline — the accent bottom stroke of a focused text box.
              Container(height: 2, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}

/// The mica window — forced Win11 neutrals, 8px corners, and a footer strip in
/// the shifted chrome shade, like the Start menu's bottom bar.
class FluentLauncherFrame extends StatelessWidget {
  const FluentLauncherFrame({super.key, required this.child, this.resultCount = 0});

  final Widget child;
  final int resultCount;

  @override
  Widget build(BuildContext context) {
    final Color surface = Theme.of(context).colorScheme.surface;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return LauncherSurface(
      constraints: const BoxConstraints(minHeight: 360),
      decoration: _fluentOuterDecoration(surface),
      child: Stack(
        children: <Widget>[
          if (Design.hasBackdrop) const StableBackdrop(),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              child,
              _FluentFooter(resultCount: resultCount, isDark: isDark),
            ],
          ),
        ],
      ),
    );
  }
}

class _FluentFooter extends StatelessWidget {
  const _FluentFooter({required this.resultCount, required this.isDark});

  final int resultCount;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    Widget buildKeyHint(String keyLabel, String caption) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            constraints: const BoxConstraints(minWidth: 18),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: onSurface.withAlpha(12),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: FluentTokens.stroke(isDark)),
            ).withLauncherCorners(),
            child: Text(
              keyLabel,
              style: FluentTokens.segoe(
                fontSize: Design.baseFontSize - 1,
                fontWeight: FontWeight.w600,
                color: onSurface.withAlpha(180),
                height: 1.2,
              ),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            caption,
            style: FluentTokens.segoe(
              fontSize: Design.baseFontSize - 1,
              color: FluentTokens.dim(isDark),
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 7, 14, 7),
      decoration: BoxDecoration(
        color: FluentTokens.chrome(isDark),
        border: Border(top: BorderSide(color: FluentTokens.stroke(isDark))),
      ),
      child: Row(
        children: <Widget>[
          buildKeyHint('↵', 'Open'),
          const SizedBox(width: 12),
          buildKeyHint('→', 'Actions'),
          const SizedBox(width: 12),
          buildKeyHint('Esc', 'Dismiss'),
          const Spacer(),
          Text(
            Globals.isLauncherPluginActive ? "PLUGIN" : (resultCount == 1 ? '1 result' : '$resultCount results'),
            style: FluentTokens.segoe(
              fontSize: Design.baseFontSize - 1,
              color: FluentTokens.dim(isDark),
              fontWeight: FontWeight.w400,
            ),
          ),
          DateTimeWidget(
            padding: const EdgeInsets.only(left: 10),
            style: FluentTokens.segoe(
              fontSize: Design.baseFontSize - 1,
              color: FluentTokens.dim(isDark),
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
