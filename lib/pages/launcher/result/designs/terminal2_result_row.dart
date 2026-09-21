part of '../result_row.dart';

extension _Terminal2ResultRow on LauncherResultRow {
  Widget _buildTerminal2(BuildContext context) {
    final int animMs = isRepeating ? 40 : 120;
    final Curve curve = isRepeating ? Curves.linear : Curves.easeOut;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return RepaintBoundary(
      child: _interactive(
        child: AnimatedContainer(
          duration: Duration(milliseconds: animMs),
          curve: curve,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          padding: const EdgeInsets.fromLTRB(7, 5, 8, 5),
          decoration: BoxDecoration(
            color: isSelected ? Terminal2Tokens.raised(isDark) : Colors.transparent,
            border: Border.all(color: isSelected ? accent.withAlpha(150) : Colors.transparent),
          ),
          child: Row(
            children: <Widget>[
              // Selection caret — the TUI line cursor.
              SizedBox(
                width: 14,
                child: Text(
                  isSelected ? '❯' : ' ',
                  style: Terminal2Tokens.mono(
                    fontSize: Design.baseFontSize + 1,
                    color: accent.withAlpha(230),
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                  ),
                ),
              ),
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected ? accent.withAlpha(22) : Terminal2Tokens.chrome(isDark),
                  border: Border.all(
                    color: isSelected ? accent.withAlpha(105) : Terminal2Tokens.dim(isDark).withAlpha(55),
                  ),
                ),
                child: icon,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: content ??
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _titleText(Terminal2Tokens.mono(
                          fontSize: Design.baseFontSize + 1.5,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: isSelected ? accent : Terminal2Tokens.fg(isDark),
                          height: 1.2,
                        )),
                        _subtitleText(Terminal2Tokens.mono(
                          fontSize: Design.baseFontSize - 0.5,
                          color: isSelected ? Terminal2Tokens.fg(isDark).withAlpha(190) : Terminal2Tokens.dim(isDark),
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
              if (isSelected)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    '[enter]',
                    style: Terminal2Tokens.label(
                      fontSize: Design.baseFontSize - 2,
                      fontWeight: FontWeight.w600,
                      color: Terminal2Tokens.amber(isDark),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
