part of '../result_row.dart';

extension _RaycastResultRow on LauncherResultRow {
  Widget _buildRaycast(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final int animMs = reduceMotion || isRepeating ? 40 : 120;
    final int? resultIndex = LauncherRaycastResultIndex.maybeOf(context);
    final bool hasShortcut = resultIndex != null && resultIndex < 8;
    final Widget titleContent = content ??
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _titleText(RaycastTokens.ui(
              fontSize: 14,
              color: isSelected ? RaycastTokens.primary(isDark) : RaycastTokens.secondary(isDark),
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              height: 1.15,
            )),
            if ((subtitle ?? '').isNotEmpty)
              _subtitleText(RaycastTokens.ui(
                fontSize: 11,
                color: isSelected ? RaycastTokens.muted(isDark).withAlpha(210) : RaycastTokens.dim(isDark),
                fontWeight: FontWeight.w400,
                height: 1.1,
              )),
          ],
        );

    return RepaintBoundary(
      child: _interactive(
        child: AnimatedContainer(
          duration: Duration(milliseconds: animMs),
          curve: Curves.easeOutQuart,
          height: 40,
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? RaycastTokens.selected(isDark) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: (isDark ? Colors.white : Colors.black).withAlpha(isSelected ? 18 : 10),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: icon,
              ),
              const SizedBox(width: 10),
              Expanded(child: titleContent),
              if (badge != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: badge,
                ),
              if (hasShortcut)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _RaycastShortcutBadge(index: resultIndex),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shares the result ordinal without moving selection or execution into rows.
class LauncherRaycastResultIndex extends InheritedWidget {
  const LauncherRaycastResultIndex({
    super.key,
    required this.index,
    required super.child,
  });

  final int index;

  static int? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LauncherRaycastResultIndex>()?.index;

  @override
  bool updateShouldNotify(LauncherRaycastResultIndex oldWidget) => index != oldWidget.index;
}

class _RaycastShortcutBadge extends StatelessWidget {
  const _RaycastShortcutBadge({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: RaycastTokens.badge(isDark),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '⌘${index + 1}',
        style: RaycastTokens.mono(
          fontSize: 12,
          color: RaycastTokens.muted(isDark),
          fontWeight: FontWeight.w500,
          height: 1.0,
        ),
      ),
    );
  }
}
