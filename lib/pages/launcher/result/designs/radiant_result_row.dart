part of '../result_row.dart';

extension _RadiantResultRow on LauncherResultRow {
  Widget _buildRadiant(BuildContext context) {
    final Widget row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(children: <Widget>[
        // Only the icon's backing light blooms; app artwork stays recognizable.
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            // borderRadius: BorderRadius.circular(8),
            boxShadow: MediaQuery.highContrastOf(context)
                ? null
                : <BoxShadow>[
                    BoxShadow(color: RadiantTokens.accent.withValues(alpha: isSelected ? 0.35 : 0.16), blurRadius: 14),
                  ],
          ).withLauncherCorners(),
          child: IconTheme(
            data: IconThemeData(color: RadiantTokens.accent, size: 23),
            child: Center(child: icon),
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
            child: content ??
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _titleText(RadiantTokens.font(weight: isSelected ? FontWeight.w600 : FontWeight.w500)),
                    if ((subtitle ?? '').isNotEmpty) ...<Widget>[
                      const SizedBox(height: 2),
                      _subtitleText(RadiantTokens.font(size: 12, color: RadiantTokens.dim)),
                    ],
                  ],
                )),
        if (badge != null) Padding(padding: const EdgeInsets.only(left: 8), child: badge),
        const SizedBox(width: 12),
        Icon(isSelected ? Icons.arrow_forward_rounded : Icons.chevron_right_rounded,
            size: 17, color: isSelected ? RadiantTokens.foreground : RadiantTokens.dim),
      ]),
    );
    return _interactive(
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        constraints: const BoxConstraints(minHeight: 52),
        child: isSelected
            ? RadiantSurface(kind: RadiantSurfaceKind.selection, radius: 9, child: row)
            : DecoratedBox(
                decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: RadiantTokens.accent.withValues(alpha: 0.09)))),
                child: row,
              ),
      ),
    );
  }
}
