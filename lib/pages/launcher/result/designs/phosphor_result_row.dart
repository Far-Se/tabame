part of '../result_row.dart';

extension _PhosphorResultRow on LauncherResultRow {
  Widget _buildPhosphor(BuildContext context) => _interactive(
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(minHeight: 68),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF10281B) : Colors.transparent,
              border: isSelected
                  ? Border.all(color: PhosphorTokens.accent)
                  : const Border(bottom: BorderSide(color: Color(0xFF20382F)))),
          child: Row(children: <Widget>[
            SizedBox(
                width: 22,
                child: Text(isSelected ? '>' : '', style: PhosphorTokens.font(size: 19, color: PhosphorTokens.accent))),
            SizedBox(width: 38, height: 34, child: Center(child: icon)),
            const SizedBox(width: 16),
            Expanded(
                child: content ??
                    Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _titleText(PhosphorTokens.font(
                              size: 17, color: isSelected ? PhosphorTokens.accent : PhosphorTokens.foreground)),
                          if ((subtitle ?? '').isNotEmpty) ...<Widget>[
                            const SizedBox(height: 4),
                            _subtitleText(PhosphorTokens.font(size: 12, color: PhosphorTokens.dim)),
                          ],
                        ])),
            if (badge != null) Padding(padding: const EdgeInsets.only(left: 10), child: badge),
          ]),
        ),
      );
}
