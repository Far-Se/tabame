part of '../result_row.dart';

extension _CrtResultRow on LauncherResultRow {
  Widget _buildCrt(BuildContext context) => _interactive(
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
              color: isSelected ? CrtTokens.selected : Colors.transparent,
              border: isSelected
                  ? Border.all(color: CrtTokens.accent)
                  : Border(bottom: BorderSide(color: CrtTokens.border))),
          child: Row(children: <Widget>[
            SizedBox(
                width: 22,
                child: Text(isSelected ? '>' : '', style: CrtTokens.font(size: 19, color: CrtTokens.accent))),
            SizedBox(width: 38, height: 34, child: Center(child: icon)),
            const SizedBox(width: 16),
            Expanded(
                child: content ??
                    Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _titleText(
                              CrtTokens.font(size: 17, color: isSelected ? CrtTokens.accent : CrtTokens.foreground)),
                          if ((subtitle ?? '').isNotEmpty) ...<Widget>[
                            const SizedBox(height: 4),
                            _subtitleText(CrtTokens.font(size: 12, color: CrtTokens.dim)),
                          ],
                        ])),
            if (badge != null) Padding(padding: const EdgeInsets.only(left: 10), child: badge),
          ]),
        ),
      );
}
