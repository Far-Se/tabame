import 'package:flutter/material.dart';

import '../../models/globals.dart';

class QuickActionItem extends StatelessWidget {
  final String message;
  final Widget icon;
  final Function() onTap;
  const QuickActionItem({super.key, required this.message, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (Globals.quickMenuPage == QuickMenuPage.quickActions) {
      return InkWell(
          onTap: () => onTap(),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[const SizedBox(width: 5), SizedBox(width: 20, child: icon), const SizedBox(width: 5), Text(message)],
          ));
    }
    return SizedBox(width: 20, height: double.maxFinite, child: InkWell(child: Tooltip(message: message, child: icon), onTap: () => onTap()));
  }
}
