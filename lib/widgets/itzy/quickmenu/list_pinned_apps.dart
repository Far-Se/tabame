import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/win32/keys.dart';
import '../../containers/bar_with_buttons.dart';
import 'button_window_app.dart';

class PinnedApps extends StatelessWidget {
  const PinnedApps({super.key});

  @override
  Widget build(BuildContext context) {
    final List<String> pinned = Boxes().pinnedApps;

    if (pinned.isEmpty) return const SizedBox();
    return BarWithButtons(children: <Widget>[
      for (String item in pinned)
        GestureDetector(
          onSecondaryTap: () {
            final int x = pinned.indexWhere((String element) => element == item);
            WinKeys.send("{#WIN}{#ALT}${x + 1}");
            if (kReleaseMode) QuickMenuFunctions.toggleQuickMenu(visible: false);
          },
          child: WindowsAppButton(
            path: item,
          ),
        )
    ]);
  }
}
