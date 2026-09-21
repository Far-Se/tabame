part of '../result_row.dart';

extension _OmarchyResultRow on LauncherResultRow {
  Widget _buildOmarchy() {
    final Color foreground = OmarchyTokens.fg;
    return _interactive(
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? OmarchyTokens.selected : Colors.transparent,
          border: Border.all(color: isSelected ? accent : Colors.transparent),
        ),
        child: Row(children: <Widget>[
          SizedBox(
              width: 18,
              child: Text(isSelected ? '>' : ' ',
                  style: OmarchyTokens.mono(fontSize: 18, color: accent, fontWeight: FontWeight.w600))),
          SizedBox(width: 22, height: 22, child: Center(child: icon)),
          const SizedBox(width: 12),
          Expanded(
              child: content ??
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _titleText(OmarchyTokens.mono(
                          fontSize: Design.baseFontSize + 3,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? accent : foreground,
                          height: 1.2)),
                      _subtitleText(OmarchyTokens.mono(
                          fontSize: Design.baseFontSize + 1, color: OmarchyTokens.dim, height: 1.25)),
                    ],
                  )),
          if (badge != null) Padding(padding: const EdgeInsets.only(left: 8), child: badge),
          if (isSelected)
            Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text('↵', style: OmarchyTokens.mono(fontSize: 18, color: accent))),
        ]),
      ),
    );
  }
}
