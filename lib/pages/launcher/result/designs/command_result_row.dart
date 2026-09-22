part of '../result_row.dart';

extension _CommandResultRow on LauncherResultRow {
  Widget _buildCommand(BuildContext context) {
    final int animMs = isRepeating ? 50 : 160;
    final Curve curve = isRepeating ? Curves.linear : Curves.easeOutCubic;

    return RepaintBoundary(
      child: _interactive(
        child: AnimatedContainer(
          duration: Duration(milliseconds: animMs),
          curve: curve,
          margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            gradient: isSelected
                ? LinearGradient(
                    colors: <Color>[accent.withAlpha(48), accent.withAlpha(14)],
                  )
                : null,
          ).withLauncherCorners(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 5, 8, 5),
            child: Row(
              children: <Widget>[
                // Bright selection rail.
                AnimatedContainer(
                  duration: Duration(milliseconds: animMs),
                  curve: curve,
                  width: isSelected ? 3 : 0,
                  height: 26,
                  margin: EdgeInsets.only(right: isSelected ? 7 : 0),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(2),
                  ).withLauncherCorners(),
                ),
                // Bordered square icon chip.
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withAlpha(isSelected ? 26 : 14),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: accent.withAlpha(isSelected ? 70 : 36)),
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
                          _titleText(entryStyle(
                            isSelected,
                            fontSize: Design.baseFontSize + 2,
                            letterSpacing: 0.2,
                          )),
                          const SizedBox(height: 1),
                          _subtitleText(TextStyle(
                            fontSize: Design.baseFontSize - 0.5,
                            letterSpacing: 0.1,
                            color: isSelected ? onSurface.withAlpha(160) : onSurface.withAlpha(110),
                          )),
                        ],
                      ),
                ),
                if (badge != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: badge,
                  ),
                // Trailing enter key — only on the active row.
                AnimatedSize(
                  duration: Duration(milliseconds: animMs),
                  curve: curve,
                  child: isSelected
                      ? Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: accent.withAlpha(30),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: accent.withAlpha(80)),
                            ).withLauncherCorners(),
                            child: Text(
                              '↵',
                              style: TextStyle(
                                fontSize: Design.baseFontSize + 1,
                                height: 1.0,
                                fontWeight: FontWeight.w700,
                                color: accent.withAlpha(220),
                              ),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
