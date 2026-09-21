part of '../result_row.dart';

extension _CapillaryResultRow on LauncherResultRow {
  Widget _buildCapillary(BuildContext context) {
    final CapillaryTokens capillary = CapillaryTokens.of(context);
    return _interactive(
      behavior: HitTestBehavior.opaque,
      child: CapillarySurface(
        key: ValueKey<(String?, String?)>((title, subtitle)),
        selected: isSelected,
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: <Widget>[
            SizedBox(width: 28, height: 28, child: Center(child: icon)),
            const SizedBox(width: 12),
            Expanded(
              child: content ??
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _titleText(capillary.font(size: 14, weight: isSelected ? FontWeight.w600 : FontWeight.w500)),
                      if ((subtitle ?? '').isNotEmpty) ...<Widget>[
                        const SizedBox(height: 2),
                        _subtitleText(capillary.font(size: 11, color: capillary.dim)),
                      ],
                    ],
                  ),
            ),
            if (badge != null) Padding(padding: const EdgeInsets.only(left: 8), child: badge),
            const SizedBox(width: 8),
            SizedBox(
              width: 16,
              child: isSelected ? Icon(Icons.keyboard_return_rounded, size: 15, color: capillary.accent) : null,
            ),
          ]),
        ),
      ),
    );
  }
}
