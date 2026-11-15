part of '../result_row.dart';

extension _GroundGlassResultRow on LauncherResultRow {
  Widget _buildGroundGlass(BuildContext context) {
    final bool highContrast = MediaQuery.highContrastOf(context);
    return _interactive(
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: GroundGlassRegion(
          selected: isSelected,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isSelected
                    ? GroundGlassTokens.accent.withValues(alpha: highContrast ? 0.9 : 0.55)
                    : Colors.transparent,
              ),
            ).withLauncherCorners(),
            child: Row(children: <Widget>[
              SizedBox(width: 28, height: 28, child: Center(child: icon)),
              const SizedBox(width: 12),
              Expanded(
                child: content ??
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _titleText(GroundGlassTokens.font(weight: isSelected ? FontWeight.w600 : FontWeight.w500)),
                        if ((subtitle ?? '').isNotEmpty) ...<Widget>[
                          const SizedBox(height: 2),
                          _subtitleText(GroundGlassTokens.font(size: 12, color: GroundGlassTokens.dim)),
                        ],
                      ],
                    ),
              ),
              if (badge != null) Padding(padding: const EdgeInsets.only(left: 8), child: badge),
              const SizedBox(width: 8),
              SizedBox(
                width: 16,
                child: isSelected
                    ? Icon(Icons.keyboard_return_rounded, size: 15, color: GroundGlassTokens.foreground)
                    : null,
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
