import 'package:flutter/material.dart';
import '../../models/settings.dart';
import '../../widgets/quickmenu/bottom_bar.dart';
import '../../widgets/quickmenu/list_pinned_tray.dart';
import '../../widgets/quickmenu/task_bar.dart';
import '../../widgets/quickmenu/top_bar.dart';

class MainMenuModernWidget extends StatelessWidget {
  const MainMenuModernWidget({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = Color(globalSettings.themeColors.accentColor);
    final Color surface = theme.colorScheme.surface;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 203, maxHeight: 540),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              surface.withAlpha(245),
              Color.alphaBlend(
                  accent.withAlpha((globalSettings.themeColors.gradientAlpha * 24 / 100).toInt()), surface),
              Color.alphaBlend(
                  accent.withAlpha((globalSettings.themeColors.gradientAlpha * 10 / 100).toInt()), surface),
            ],
          ),
          border: Border.all(color: accent.withAlpha(28)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withAlpha(18),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: surface.withAlpha(235),
              border: Border.all(color: accent.withAlpha(18)),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Colors.white.withAlpha(14),
                  Colors.transparent,
                ],
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const TopBar(),
                const TaskBar(),
                Divider(thickness: 1, height: 1, color: accent.withAlpha(28)),
                const PinnedAndTrayList(),
                const BottomBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
