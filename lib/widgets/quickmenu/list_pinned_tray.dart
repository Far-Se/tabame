import 'package:flutter/material.dart';

import '../itzy/quickmenu/list_pinned_apps.dart';
import 'tray_bar.dart';

class PinnedAndTrayList extends StatelessWidget {
  const PinnedAndTrayList({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      height: 30,
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          SizedBox(width: 5),
          Expanded(flex: 2, child: PinnedApps()),
          Expanded(flex: 2, child: Align(alignment: Alignment.centerRight, child: TrayBar())),
        ],
      ),
    );
  }
}
