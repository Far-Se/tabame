part of '../result_row.dart';

extension _TerminalResultRow on LauncherResultRow {
  Widget _buildTerminal(BuildContext context) {
    final int animMs = isRepeating ? 40 : 120;
    final Curve curve = isRepeating ? Curves.linear : Curves.easeOut;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return RepaintBoundary(
      child: _interactive(
        child: AnimatedContainer(
          duration: Duration(milliseconds: animMs),
          curve: curve,
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          padding: const EdgeInsets.fromLTRB(6, 4, 8, 4),
          decoration: BoxDecoration(
            color: isSelected ? accent.withAlpha(36) : Colors.transparent,
            borderRadius: BorderRadius.circular(3),
            border: Border(
              left: BorderSide(
                color: isSelected ? accent : Colors.transparent,
                width: 2.5,
              ),
            ),
          ),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 14,
                child: Text(
                  isSelected ? '❯' : ' ',
                  style: TerminalTokens.mono(
                    fontSize: Design.baseFontSize + 1,
                    color: accent.withAlpha(230),
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
              SizedBox(width: 18, height: 18, child: Center(child: icon)),
              const SizedBox(width: 9),
              Expanded(
                child: content ??
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _titleText(TerminalTokens.mono(
                          fontSize: Design.baseFontSize + 2,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? accent : TerminalTokens.fg(isDark),
                          height: 1.25,
                        )),
                        _subtitleText(TerminalTokens.mono(
                          fontSize: Design.baseFontSize,
                          color: isSelected ? TerminalTokens.fg(isDark).withAlpha(190) : TerminalTokens.dim(isDark),
                          height: 1.2,
                        )),
                      ],
                    ),
              ),
              if (badge != null)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: badge,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
