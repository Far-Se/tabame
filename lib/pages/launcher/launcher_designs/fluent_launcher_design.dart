part of '../launcher_design_builder.dart';

class _FluentSearchBar extends StatelessWidget {
  const _FluentSearchBar({
    required this.accent,
    required this.dragHandle,
    required this.textField,
    required this.trailingBadge,
    required this.isSearching,
  });

  final Color accent;
  final Widget dragHandle;
  final Widget textField;
  final Widget? trailingBadge;
  final bool isSearching;

  @override
  Widget build(BuildContext context) {
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
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 10, 7),
                child: Row(
                  children: <Widget>[
                    dragHandle,
                    const SizedBox(width: 10),
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
  const FluentLauncherFrame({
    super.key,
    required this.child,
    required this.surface,
    required this.accent,
    required this.onSurface,
    this.resultCount = 0,
  });

  final Widget child;
  final Color surface;
  final Color accent;
  final Color onSurface;
  final int resultCount;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return LauncherTheme(
      data: const LauncherThemeData(design: LauncherDesign.fluent),
      child: Container(
        constraints: const BoxConstraints(minHeight: 360),
        decoration: LauncherDesign.fluent.outerDecoration(surface: surface, accent: accent),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Design.borderRadius),
          child: Stack(
            children: <Widget>[
              if (Design.hasBackdrop) const StableBackdrop(),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  child,
                  _FluentFooter(onSurface: onSurface, resultCount: resultCount, isDark: isDark),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FluentFooter extends StatelessWidget {
  const _FluentFooter({required this.onSurface, required this.resultCount, required this.isDark});

  final Color onSurface;
  final int resultCount;
  final bool isDark;

  Widget _kbd(String keyLabel, String caption) {
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
          ),
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

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 7, 14, 7),
      decoration: BoxDecoration(
        color: FluentTokens.chrome(isDark),
        border: Border(top: BorderSide(color: FluentTokens.stroke(isDark))),
      ),
      child: Row(
        children: <Widget>[
          _kbd('↵', 'Open'),
          const SizedBox(width: 12),
          _kbd('→', 'Actions'),
          const SizedBox(width: 12),
          _kbd('Esc', 'Dismiss'),
          if (!Globals.isLauncherPluginActive) const Spacer(),
          if (!Globals.isLauncherPluginActive)
            Text(
              resultCount == 1 ? '1 result' : '$resultCount results',
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

/// An editorial command sheet with a permanent issue rail, registration grid,
/// hard shadow and an ink-black keyboard legend.
