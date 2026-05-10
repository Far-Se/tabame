import 'package:flutter/material.dart';

import '../../../models/globals.dart';
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
        if (userSettings.themeType == ThemeType.system &&
            MediaQuery.of(context).platformBrightness == Brightness.dark) {
          userSettings.themeType = ThemeType.dark;
        }
        userSettings.themeType = userSettings.themeType == ThemeType.dark ? ThemeType.light : ThemeType.dark;
        Globals.themeChangeNotifier.value = !Globals.themeChangeNotifier.value;
      },
    );
  }
}
