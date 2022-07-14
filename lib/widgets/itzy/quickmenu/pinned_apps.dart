import 'package:flutter/material.dart';

import '../../../models/boxes.dart';
import '../../../models/keys.dart';
import '../../containers/bar_with_buttons.dart';
import 'window_app_button.dart';

class PinnedApps extends StatelessWidget {
  const PinnedApps({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    List<String> pinned = Boxes.lists.get('pinned') as List<String>;

    if (pinned.isEmpty) return const SizedBox();
    return BarWithButtons(children: <Widget>[
      for (String item in pinned)
        GestureDetector(
          onSecondaryTap: () {
            final int x = pinned.indexWhere((String element) => element == item);
            WinKeys.send("{#WIN}{#ALT}${x + 1}");
          },
          child: WindowsAppButton(
            path: item,
          ),
        )
    ]);
  }
}
