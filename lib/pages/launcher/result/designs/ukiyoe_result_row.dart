part of '../result_row.dart';

extension _UkiyoeResultRow on LauncherResultRow {
  Widget _buildUkiyoe(BuildContext context) {
    final Widget row = Container(
      constraints: const BoxConstraints(minHeight: 50),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
            color: isSelected
                ? UkiyoeTokens.accent.withValues(alpha: MediaQuery.highContrastOf(context) ? 1 : 0.5)
                : Colors.transparent),
      ).withLauncherCorners(),
      child: Row(children: <Widget>[
        SizedBox(width: 28, height: 28, child: Center(child: icon)),
        const SizedBox(width: 12),
        Expanded(
            child: content ??
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _titleText(UkiyoeTokens.font(size: 15, weight: isSelected ? FontWeight.w700 : FontWeight.w500)),
                    if ((subtitle ?? '').isNotEmpty) ...<Widget>[
                      const SizedBox(height: 2),
                      _subtitleText(UkiyoeTokens.font(size: 12, color: UkiyoeTokens.dim)),
                    ],
                  ],
                )),
        if (badge != null) Padding(padding: const EdgeInsets.only(left: 8), child: badge),
        const SizedBox(width: 10),
        SizedBox(
            width: 18,
            child: isSelected ? Icon(Icons.keyboard_return_rounded, size: 16, color: UkiyoeTokens.vermilion) : null),
      ]),
    );
    return _interactive(
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: isSelected ? UkiyoeSurface(material: UkiyoeMaterial.selection, radius: 4, child: row) : row,
      ),
    );
  }
}
