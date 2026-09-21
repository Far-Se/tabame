part of '../result_row.dart';

extension _StrataResultRow on LauncherResultRow {
  Widget _buildStrata(BuildContext context) {
    return _interactive(
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF15323C) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? StrataTokens.accent : StrataTokens.border.withAlpha(120)),
        ),
        child: Row(children: <Widget>[
          Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: const Color(0xFF183547), borderRadius: BorderRadius.circular(6)),
              child: Center(child: icon)),
          const SizedBox(width: 15),
          Expanded(
              child: content ??
                  Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _titleText(StrataTokens.font(size: 15)),
                        if ((subtitle ?? '').isNotEmpty)
                          _subtitleText(StrataTokens.font(size: 12, color: StrataTokens.dim)),
                      ])),
          if (badge != null) Padding(padding: const EdgeInsets.only(left: 10), child: badge),
          if (isSelected)
            Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Icon(Icons.keyboard_return_rounded, color: StrataTokens.accent, size: 21)),
        ]),
      ),
    );
  }
}
