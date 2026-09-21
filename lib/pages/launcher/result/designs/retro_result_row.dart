part of '../result_row.dart';

extension _RetroResultRow on LauncherResultRow {
  Widget _buildRetro(BuildContext context) => RepaintBoundary(
        child: _interactive(
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: Duration(milliseconds: isRepeating ? 40 : 120),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
            padding: const EdgeInsets.fromLTRB(7, 6, 8, 6),
            decoration: BoxDecoration(
              color: isSelected ? RetroTokens.selected : Colors.transparent,
              border: Border.all(
                color: isSelected ? RetroTokens.accent : RetroTokens.border.withAlpha(100),
              ),
            ),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 22,
                  child: Text(
                    isSelected ? '>' : '',
                    style: RetroTokens.label(size: 10, color: RetroTokens.accent),
                  ),
                ),
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: RetroTokens.panel,
                    border: Border.all(color: isSelected ? RetroTokens.cyan : RetroTokens.border),
                  ),
                  child: icon,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: content ??
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _titleText(RetroTokens.pixel(
                            size: RetroTokens.resultTitleSize,
                            color: isSelected ? RetroTokens.accent : RetroTokens.foreground,
                          )),
                          if ((subtitle ?? '').isNotEmpty)
                            _subtitleText(
                                RetroTokens.pixel(size: RetroTokens.resultSubtitleSize, color: RetroTokens.dim)),
                        ],
                      ),
                ),
                if (badge != null) Padding(padding: const EdgeInsets.only(left: 8), child: badge),
                if (isSelected)
                  Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Text('A', style: RetroTokens.label(size: 8, color: RetroTokens.cyan)),
                  ),
              ],
            ),
          ),
        ),
      );
}
