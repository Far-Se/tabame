part of '../result_row.dart';

extension _OpticalGlassResultRow on LauncherResultRow {
  Widget _buildOpticalGlass(BuildContext context) => _interactive(
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: OpticalGlassSurface(
            selected: isSelected,
            child: Container(
              constraints: const BoxConstraints(minHeight: 60),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border:
                    Border.all(color: isSelected ? OpticalGlassTokens.accent : OpticalGlassTokens.border.withAlpha(85)),
              ).withLauncherCorners(),
              child: Row(children: <Widget>[
                OpticalGlassSurface(
                    radius: 17,
                    selected: isSelected,
                    child: SizedBox(width: 34, height: 34, child: Center(child: icon))),
                const SizedBox(width: 12),
                Expanded(
                    child: content ??
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            _titleText(OpticalGlassTokens.font(
                                size: 15, weight: isSelected ? FontWeight.w600 : FontWeight.w500)),
                            if ((subtitle ?? '').isNotEmpty) ...<Widget>[
                              const SizedBox(height: 3),
                              _subtitleText(OpticalGlassTokens.font(size: 12, color: OpticalGlassTokens.dim)),
                            ],
                          ],
                        )),
                if (badge != null) Padding(padding: const EdgeInsets.only(left: 8), child: badge),
                if (isSelected)
                  Padding(
                      padding: const EdgeInsets.only(left: 10),
                      child: Icon(Icons.arrow_outward_rounded, size: 16, color: OpticalGlassTokens.accent)),
              ]),
            ),
          ),
        ),
      );
}
