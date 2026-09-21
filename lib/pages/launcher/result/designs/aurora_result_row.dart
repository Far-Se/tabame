part of '../result_row.dart';

extension _AuroraResultRow on LauncherResultRow {
  Widget _buildAurora(BuildContext context) {
    return _interactive(
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? AuroraTokens.background.withAlpha(225) : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: isSelected ? AuroraTokens.accent : Colors.transparent),
          boxShadow:
              isSelected ? <BoxShadow>[BoxShadow(color: AuroraTokens.accent.withAlpha(45), blurRadius: 10)] : null,
        ),
        child: Row(children: <Widget>[
          SizedBox(width: 30, height: 32, child: Center(child: icon)),
          const SizedBox(width: 15),
          Expanded(
              child: content ??
                  Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _titleText(AuroraTokens.font(size: 14)),
                        if ((subtitle ?? '').isNotEmpty)
                          _subtitleText(
                              AuroraTokens.font(size: 11, color: isSelected ? AuroraTokens.accent : AuroraTokens.dim)),
                      ])),
          if (badge != null) Padding(padding: const EdgeInsets.only(left: 10), child: badge),
          if (isSelected)
            const Padding(
                padding: EdgeInsets.only(left: 16),
                child: Icon(Icons.keyboard_return_rounded, color: AuroraTokens.accent, size: 21)),
        ]),
      ),
    );
  }
}
