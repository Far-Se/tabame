import 'package:flutter/material.dart';

import '../../../main.dart';
import '../../../models/settings.dart';
import '../../widgets/quick_actions_item.dart';

class ChangeThemeButton extends StatelessWidget {
  const ChangeThemeButton({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message: "Change Theme",
      icon: const Icon(Icons.theater_comedy_sharp),
      onTap: () {
        if (globalSettings.themeType == ThemeType.system && MediaQuery.of(context).platformBrightness == Brightness.dark) globalSettings.themeType = ThemeType.dark;
        globalSettings.themeType = globalSettings.themeType == ThemeType.dark ? ThemeType.light : ThemeType.dark;
        themeChangeNotifier.value = !themeChangeNotifier.value;
      },
    );
  }
}
