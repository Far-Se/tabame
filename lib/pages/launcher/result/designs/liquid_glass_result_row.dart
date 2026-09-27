part of '../result_row.dart';

extension _LiquidGlassResultRow on LauncherResultRow {
  Widget _buildLiquidGlass(BuildContext context) {
    final bool highContrast = MediaQuery.highContrastOf(context);
    final Widget body = Container(
      constraints: const BoxConstraints(minHeight: 54),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? accent.withValues(alpha: highContrast ? 1 : 0.38) : Colors.transparent,
          width: 1,
        ),
      ).withLauncherCorners(),
      child: Row(children: <Widget>[
        Container(
          width: 32,
          height: 32,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: isSelected ? onSurface.withValues(alpha: 0.055) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ).withLauncherCorners(),
          child: Center(child: icon),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: content ??
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _titleText(LiquidGlassTokens.font(
                    size: Design.baseFontSize + 4,
                    color: onSurface,
                    weight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  )),
                  if ((subtitle ?? '').isNotEmpty) ...<Widget>[
                    const SizedBox(height: 2),
                    _subtitleText(LiquidGlassTokens.font(
                      size: Design.baseFontSize + 2,
                      color: highContrast ? onSurface : LiquidGlassTokens.dim,
                    )),
                  ],
                ],
              ),
        ),
        if (badge != null) Padding(padding: const EdgeInsets.only(left: 8), child: badge),
        const SizedBox(width: 10),
        SizedBox(
          width: 16,
          child: isSelected ? Icon(Icons.keyboard_return_rounded, size: 16, color: onSurface) : null,
        ),
      ]),
    );

    // Selection is synchronous, including held arrows. Only the active row
    // owns a shader; custom content, badges, and movement-only hover stay shared.
    return _interactive(
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: isSelected
            ? LiquidGlassSurface(kind: LiquidGlassKind.selection, radius: 16, opacity: 0.94, child: body)
            : body,
      ),
    );
  }
}
