part of '../result_row.dart';

extension _ThermalResultRow on LauncherResultRow {
  Widget _buildThermal(BuildContext context) => _interactive(
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: ThermalRegion(
            key: ValueKey<(String?, String?)>((title, subtitle)),
            selected: isSelected,
            child: Container(
              constraints: const BoxConstraints(minHeight: 50),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: isSelected ? ThermalTokens.accent.withAlpha(95) : Colors.transparent),
              ),
              child: Row(children: <Widget>[
                SizedBox(width: 28, height: 28, child: Center(child: icon)),
                const SizedBox(width: 12),
                Expanded(
                  child: content ??
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _titleText(ThermalTokens.font(weight: isSelected ? FontWeight.w600 : FontWeight.w500)),
                          if ((subtitle ?? '').isNotEmpty) ...<Widget>[
                            const SizedBox(height: 2),
                            _subtitleText(ThermalTokens.font(size: 11, color: ThermalTokens.dim)),
                          ],
                        ],
                      ),
                ),
                if (badge != null) Padding(padding: const EdgeInsets.only(left: 8), child: badge),
                const SizedBox(width: 10),
                SizedBox(
                  width: 16,
                  child: isSelected ? Icon(Icons.keyboard_return_rounded, size: 15, color: ThermalTokens.accent) : null,
                ),
              ]),
            ),
          ),
        ),
      );
}
