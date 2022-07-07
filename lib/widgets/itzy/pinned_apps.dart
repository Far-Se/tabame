import 'package:flutter/material.dart';

import '../../models/boxes.dart';
import '../../models/keys.dart';
import '../containers/bar_with_buttons.dart';
import 'window_app_button.dart';

class PinnedApps extends StatelessWidget {
  const PinnedApps({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var pinned = Boxes.lists.get('pinned')!;
    pinned = [...pinned, ...pinned, ...pinned, ...pinned, ...pinned, ...pinned, ...pinned, ...pinned, ...pinned];
    // print(pinned.value[0]);
    if (pinned.isEmpty) return SizedBox();
    print("xx");
    return SizedBox(
      height: 25,
      child: BarWithButtons(children: [
        for (var item in pinned)
          GestureDetector(
            onSecondaryTap: () {
              final x = pinned.indexWhere((element) => element == item);
              WinKeys.send("{#WIN}{#ALT}${x + 1}");
              print(x);
            },
            child: WindowsAppButton(
              path: item,
            ),
          )
      ]),
    );
  }
}
