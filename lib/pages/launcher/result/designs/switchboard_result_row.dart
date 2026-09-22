part of '../result_row.dart';

extension _SwitchboardResultRow on LauncherResultRow {
  Widget _buildSwitchboard(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final int animMs = isRepeating ? 35 : 110;
    final Color foreground = SwitchboardTokens.foreground(isDark);
    final Color dim = SwitchboardTokens.dim(isDark);

    return RepaintBoundary(
      child: _interactive(
        child: AnimatedContainer(
          duration: Duration(milliseconds: animMs),
          curve: Curves.easeOutQuart,
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          decoration: BoxDecoration(
            color: isSelected ? SwitchboardTokens.raised(isDark) : Colors.transparent,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: isSelected ? accent.withAlpha(150) : Colors.transparent,
            ),
          ).withLauncherCorners(),
          child: Row(
            children: <Widget>[
              AnimatedContainer(
                duration: Duration(milliseconds: animMs),
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected ? accent.withAlpha(30) : SwitchboardTokens.panel(isDark),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: isSelected ? accent.withAlpha(110) : SwitchboardTokens.border(isDark),
                  ),
                ).withLauncherCorners(),
                child: icon,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: content ??
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _titleText(SwitchboardTokens.body(
                          fontSize: Design.baseFontSize + 1.5,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: foreground,
                          height: 1.15,
                        )),
                        const SizedBox(height: 2),
                        _subtitleText(SwitchboardTokens.body(
                          fontSize: Design.baseFontSize - 0.5,
                          fontWeight: FontWeight.w400,
                          color: dim,
                          height: 1.15,
                        )),
                      ],
                    ),
              ),
              if (badge != null)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: badge,
                ),
              AnimatedOpacity(
                duration: Duration(milliseconds: animMs),
                opacity: isSelected ? 1 : 0,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(Icons.arrow_forward_rounded, size: 15, color: accent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
