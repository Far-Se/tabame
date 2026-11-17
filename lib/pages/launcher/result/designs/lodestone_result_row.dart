part of '../result_row.dart';

extension _LodestoneResultRow on LauncherResultRow {
  Widget _buildLodestone(BuildContext context) {
    final bool highContrast = MediaQuery.highContrastOf(context);
    final Color pole = LodestoneTokens.accent;
    final TextStyle titleStyle = LodestoneTokens.font(
      size: Design.baseFontSize + 1,
      weight: isSelected ? FontWeight.w600 : FontWeight.w500,
    );
    final TextStyle subtitleStyle = LodestoneTokens.font(
      size: Design.baseFontSize - 1,
      color: LodestoneTokens.dim,
      weight: FontWeight.w400,
    );
    return _interactive(
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        // The selected row is the stone the needle field points at. The pole
        // sits on the icon; LodestoneSurface.poleInset matches this padding.
        child: LodestonePole(
          selected: isSelected,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected ? LodestoneTokens.selection : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: isSelected ? pole.withValues(alpha: highContrast ? 0.95 : 0.5) : Colors.transparent,
              ),
            ).withLauncherCorners(),
            child: Row(children: <Widget>[
              SizedBox(width: 26, height: 26, child: Center(child: icon)),
              const SizedBox(width: 12),
              Expanded(
                child: content ??
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _titleText(titleStyle),
                        if ((subtitle ?? '').isNotEmpty) ...<Widget>[
                          const SizedBox(height: 1),
                          _subtitleText(subtitleStyle),
                        ],
                      ],
                    ),
              ),
              if (badge != null) Padding(padding: const EdgeInsets.only(left: 8), child: badge),
              const SizedBox(width: 8),
              SizedBox(
                width: 16,
                child: isSelected ? Icon(Icons.keyboard_return_rounded, size: 14, color: pole) : null,
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
