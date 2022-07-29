import 'package:flutter/material.dart';

import '../../../main.dart';
import '../../../models/settings.dart';

class ChangeThemeButton extends StatelessWidget {
  const ChangeThemeButton({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: double.maxFinite,
      child: InkWell(
        onTap: () {
          if (globalSettings.themeType == ThemeType.system && MediaQuery.of(context).platformBrightness == Brightness.dark) globalSettings.themeType = ThemeType.dark;
          globalSettings.themeType = globalSettings.themeType == ThemeType.dark ? ThemeType.light : ThemeType.dark;
          themeChangeNotifier.value = !themeChangeNotifier.value;
        },
        child: const Tooltip(message: "Change Theme", child: Icon(Icons.theater_comedy_sharp)),
      ),
    );
  }
}
