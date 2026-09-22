part of '../result_row.dart';

extension _SatinResultRow on LauncherResultRow {
  Widget _buildSatin(BuildContext context) => _interactive(
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(minHeight: 50),
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? Color.alphaBlend(SatinTokens.accent.withValues(alpha: 0.12), SatinTokens.background)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: isSelected
                  ? SatinTokens.accent.withValues(alpha: MediaQuery.highContrastOf(context) ? 0.85 : 0.32)
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
                      _titleText(SatinTokens.font(weight: isSelected ? FontWeight.w600 : FontWeight.w500)),
                      if ((subtitle ?? '').isNotEmpty) ...<Widget>[
                        const SizedBox(height: 2),
                        _subtitleText(SatinTokens.font(size: 12, color: SatinTokens.dim)),
                      ],
                    ],
                  ),
            ),
            if (badge != null) Padding(padding: const EdgeInsets.only(left: 8), child: badge),
            const SizedBox(width: 8),
            SizedBox(
              width: 16,
              child: isSelected ? Icon(Icons.keyboard_return_rounded, size: 15, color: SatinTokens.foreground) : null,
            ),
          ]),
        ),
      );
}
