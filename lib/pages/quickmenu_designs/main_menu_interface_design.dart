import 'package:flutter/material.dart';
import '../../models/settings.dart';
import '../../widgets/quickmenu/bottom_bar.dart';
import '../../widgets/quickmenu/list_pinned_tray.dart';
import '../../widgets/quickmenu/task_bar.dart';
import '../../widgets/quickmenu/top_bar.dart';

class MainMenuInterfaceWidget extends StatelessWidget {
  const MainMenuInterfaceWidget({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = Color(globalSettings.themeColors.accentColor);
    final Color surface = theme.colorScheme.surface;
    final double gradientStrength = (globalSettings.themeColors.gradientAlpha.clamp(1, 100)) / 100;
    final double outerAccentAlpha = 0.04 + (gradientStrength * 0.08);
    final double innerAccentAlpha = 0.05 + (gradientStrength * 0.10);
    final double headerAccentAlpha =
        globalSettings.themeColors.gradientAlpha == 0 ? 0 : 0.04 + (gradientStrength * 0.12);

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 203, maxHeight: 540),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Color.alphaBlend(accent.withValues(alpha: outerAccentAlpha), surface.withValues(alpha: 0.98)),
              surface.withValues(alpha: 0.95),
            ],
          ),
          border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.08)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: surface.withValues(alpha: 0.90),
              border: Border.all(color: accent.withValues(alpha: innerAccentAlpha)),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  theme.colorScheme.surface.withAlpha(245),
                  Color.alphaBlend(accent.withValues(alpha: headerAccentAlpha + headerAccentAlpha * 0.24),
                      theme.colorScheme.surface),
                  Color.alphaBlend(accent.withValues(alpha: headerAccentAlpha + headerAccentAlpha * 0.10),
                      theme.colorScheme.surface),
                  // accent.withValues(alpha: headerAccentAlpha),
                  // Colors.transparent,
                ],
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Container(padding: const EdgeInsets.fromLTRB(0, 5, 10, 6), child: const TopBar()),
                Divider(thickness: 1, height: 1, color: theme.colorScheme.onSurface.withValues(alpha: 0.08)),
                const TaskBar(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Divider(thickness: 1, height: 1, color: theme.colorScheme.onSurface.withValues(alpha: 0.08)),
                ),
                const Flexible(child: PinnedAndTrayList()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Divider(thickness: 1, height: 1, color: theme.colorScheme.onSurface.withValues(alpha: 0.08)),
                ),
                Container(padding: const EdgeInsets.fromLTRB(0, 6, 2, 10), child: const BottomBar()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
