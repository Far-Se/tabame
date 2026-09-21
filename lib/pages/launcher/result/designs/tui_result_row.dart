part of '../result_row.dart';

extension _TuiResultRow on LauncherResultRow {
  Widget _buildTui(BuildContext context) {
    final bool customContent = content != null && title == null;
    final Color ink = isSelected && !customContent ? TuiTokens.background : TuiTokens.foreground;
    final TextStyle textStyle = TuiTokens.mono(color: ink);
    return _interactive(
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        color: isSelected
            ? customContent
                ? Color.alphaBlend(TuiTokens.accent.withValues(alpha: 0.18), TuiTokens.background)
                : TuiTokens.foreground
            : Colors.transparent,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(isSelected ? '> ' : '  ', style: textStyle),
          SizedBox(
            width: 22,
            height: 22,
            child: Center(
              child: Opacity(
                opacity: 0.72,
                child: ColorFiltered(
                  colorFilter: isSelected
                      ? const ColorFilter.matrix(<double>[
                          0.35,
                          0,
                          0,
                          0,
                          0,
                          0,
                          0.35,
                          0,
                          0,
                          0,
                          0,
                          0,
                          0.35,
                          0,
                          0,
                          0,
                          0,
                          0,
                          1,
                          0,
                        ])
                      : const ColorFilter.matrix(<double>[
                          0.2126,
                          0.7152,
                          0.0722,
                          0,
                          0,
                          0.2126,
                          0.7152,
                          0.0722,
                          0,
                          0,
                          0.2126,
                          0.7152,
                          0.0722,
                          0,
                          0,
                          0,
                          0,
                          0,
                          1,
                          0
                        ]),
                  child: icon,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
              child: customContent
                  ? content!
                  : LayoutBuilder(
                      builder: (BuildContext context, BoxConstraints constraints) {
                        final Widget name = _titleText(textStyle);
                        final Widget detail =
                            _subtitleText(textStyle.copyWith(color: isSelected ? ink : TuiTokens.dim));
                        if (subtitle == null || subtitle!.isEmpty) return name;
                        if (constraints.maxWidth < 420) {
                          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[name, detail]);
                        }
                        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                          Expanded(flex: 5, child: name),
                          const SizedBox(width: 16),
                          Expanded(flex: 4, child: detail),
                        ]);
                      },
                    )),
          if (badge != null)
            Padding(padding: const EdgeInsets.only(left: 8), child: DefaultTextStyle(style: textStyle, child: badge!)),
        ]),
      ),
    );
  }
}
