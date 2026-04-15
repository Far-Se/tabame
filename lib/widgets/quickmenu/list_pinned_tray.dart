import 'package:flutter/material.dart';

import '../itzy/quickmenu/list_pinned_apps.dart';
import 'tray_bar.dart';

class PinnedAndTrayList extends StatelessWidget {
  const PinnedAndTrayList({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 280,
      height: 31,
      child: Padding(
        padding: EdgeInsets.only(left: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: PinnedApps(),
              ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: TrayBar(),
              ),
            ),
            SizedBox(width: 1.3)
          ],
        ),
      ),
    );
  }
}
