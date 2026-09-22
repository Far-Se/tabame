part of '../result_row.dart';

extension _LiquidMetalResultRow on LauncherResultRow {
  Widget _buildLiquidMetal(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color iconFill = LiquidMetalTokens.foreground.withAlpha(
      isDark ? (isSelected ? 22 : 12) : (isSelected ? 48 : 30),
    );
    final Color iconBorder = (isSelected ? LiquidMetalTokens.accent : LiquidMetalTokens.border)
        .withAlpha(isSelected ? (isDark ? 120 : 105) : 80);

    return _interactive(
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: LiquidMetalFrostedSurface(
          selected: isSelected,
          child: Container(
            constraints: const BoxConstraints(minHeight: 58),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isSelected ? LiquidMetalTokens.accent.withAlpha(150) : iconBorder),
            ).withLauncherCorners(),
            child: Row(children: <Widget>[
              DecoratedBox(
                decoration: BoxDecoration(
                  color: iconFill,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: iconBorder),
                ).withLauncherCorners(),
                child: SizedBox(width: 34, height: 34, child: Center(child: icon)),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: content ??
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _titleText(
                              LiquidMetalTokens.font(size: 15, weight: isSelected ? FontWeight.w600 : FontWeight.w500)),
                          if ((subtitle ?? '').isNotEmpty) ...<Widget>[
                            const SizedBox(height: 3),
                            _subtitleText(LiquidMetalTokens.font(size: 12, color: LiquidMetalTokens.dim)),
                          ],
                        ],
                      )),
              if (badge != null) Padding(padding: const EdgeInsets.only(left: 8), child: badge),
              if (isSelected)
                Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Icon(Icons.keyboard_return_rounded, size: 16, color: LiquidMetalTokens.accent)),
            ]),
          ),
        ),
      ),
    );
  }
}
