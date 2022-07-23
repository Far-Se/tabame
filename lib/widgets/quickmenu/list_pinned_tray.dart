import 'package:flutter/material.dart';

import '../itzy/quickmenu/list_pinned_apps.dart';
import 'tray_bar.dart';

class PinnedAndTrayList extends StatelessWidget {
  const PinnedAndTrayList({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      height: 30,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          const SizedBox(width: 5),
          const Expanded(flex: 2, child: PinnedApps()),
          const Expanded(flex: 2, child: Align(alignment: Alignment.centerRight, child: TrayBar())),
        ],
      ),
    );
  }
}
