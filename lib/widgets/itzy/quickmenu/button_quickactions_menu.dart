import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';

class QuickActionsMenuButton extends StatefulWidget {
  const QuickActionsMenuButton({Key? key}) : super(key: key);
  @override
  QuickActionsMenuButtonState createState() => QuickActionsMenuButtonState();
}

class QuickActionsMenuButtonState extends State<QuickActionsMenuButton> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: double.maxFinite,
      child: InkWell(
        child: const Tooltip(message: "QuickActions Menu", child: Icon(Icons.grid_view)),
        onTap: () async {
          QuickMenuFunctions.toggleQuickMenu(type: 3, visible: true);
        },
      ),
    );
  }
}
