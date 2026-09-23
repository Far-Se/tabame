part of '../result_row.dart';

extension _IvoryGroveResultRow on LauncherResultRow {
  Widget _buildIvoryGrove(BuildContext context) {
    final Color surface = Theme.of(context).colorScheme.surface;
    final bool highContrast = MediaQuery.highContrastOf(context);
    return _interactive(
      behavior: HitTestBehavior.opaque,
      child: Container(
        constraints: const BoxConstraints(minHeight: 46),
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(colors: <Color>[
                  Color.alphaBlend(accent.withValues(alpha: 0.27), surface),
                  Color.alphaBlend(accent.withValues(alpha: 0.13), surface),
                ])
              : null,
          borderRadius: BorderRadius.circular(9),
          border:
              Border.all(color: isSelected ? (highContrast ? onSurface : IvoryGroveTokens.edge) : Colors.transparent),
        ).withLauncherCorners(),
        child: Row(children: <Widget>[
          SizedBox(width: 30, height: 30, child: Center(child: icon)),
          const SizedBox(width: 12),
          Expanded(
              child: content ??
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _titleText(IvoryGroveTokens.font(
                          size: Design.baseFontSize + 4, color: onSurface, weight: FontWeight.w600)),
                      if ((subtitle ?? '').isNotEmpty) ...<Widget>[
                        const SizedBox(height: 2),
                        _subtitleText(IvoryGroveTokens.font(
                            size: Design.baseFontSize + 2,
                            color: Color.alphaBlend(onSurface.withValues(alpha: 0.74), surface))),
                      ],
                    ],
                  )),
          if (badge != null) Padding(padding: const EdgeInsets.only(left: 8), child: badge),
          const SizedBox(width: 8),
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: isSelected ? accent.withValues(alpha: 0.16) : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ).withLauncherCorners(),
            child: Icon(isSelected ? Icons.keyboard_return_rounded : Icons.chevron_right_rounded,
                size: 17, color: onSurface.withValues(alpha: isSelected ? 1 : 0.50)),
          ),
        ]),
      ),
    );
  }
}
