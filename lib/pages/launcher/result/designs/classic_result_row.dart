part of '../result_row.dart';

extension _ClassicResultRow on LauncherResultRow {
  Widget _buildClassic(BuildContext context) {
    final int animMs = isRepeating ? 50 : 200;
    final Curve animCurve = isRepeating ? Curves.linear : Curves.easeOutCubic;

    return RepaintBoundary(
      child: _interactive(
        child: AnimatedContainer(
          duration: Duration(milliseconds: animMs),
          curve: animCurve,
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: isSelected ? accent.withAlpha(55) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ).withLauncherCorners(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: <Widget>[
                AnimatedContainer(
                  duration: Duration(milliseconds: animMs),
                  curve: animCurve,
                  width: isSelected ? 2.5 : 0,
                  height: 22,
                  margin: EdgeInsets.only(right: isSelected ? 7 : 0),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(2),
                  ).withLauncherCorners(),
                ),
                icon,
                const SizedBox(width: 8),
                Expanded(
                  child: content == null
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            _titleText(entryStyle(isSelected, fontSize: Design.baseFontSize + 2)),
                            const SizedBox(height: 2),
                            _subtitleText(TextStyle(
                              fontSize: Design.baseFontSize,
                              color: isSelected ? onSurface.withAlpha(170) : onSurface.withAlpha(130),
                            )),
                          ],
                        )
                      : content!,
                ),
                if (badge != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: badge,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
