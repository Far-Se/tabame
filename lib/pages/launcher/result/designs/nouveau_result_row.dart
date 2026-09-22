part of '../result_row.dart';

extension _NouveauResultRow on LauncherResultRow {
  Widget _buildNouveau(BuildContext context) => _interactive(
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? NouveauTokens.accent.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: isSelected
                  ? NouveauTokens.accent.withValues(alpha: MediaQuery.highContrastOf(context) ? 0.9 : 0.25)
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
                      _titleText(NouveauTokens.font(weight: isSelected ? FontWeight.w500 : FontWeight.w400)),
                      if ((subtitle ?? '').isNotEmpty) ...<Widget>[
                        const SizedBox(height: 2),
                        _subtitleText(NouveauTokens.font(size: 12, color: NouveauTokens.dim)),
                      ],
                    ],
                  ),
            ),
            if (badge != null) Padding(padding: const EdgeInsets.only(left: 8), child: badge),
            const SizedBox(width: 8),
            SizedBox(
              width: 24,
              height: 24,
              child: isSelected
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        color: NouveauTokens.background.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(Icons.keyboard_return_rounded, size: 14, color: NouveauTokens.foreground),
                    )
                  : null,
            ),
          ]),
        ),
      );
}
