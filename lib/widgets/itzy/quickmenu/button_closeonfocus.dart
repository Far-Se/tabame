import 'package:flutter/material.dart';

import '../../../models/settings.dart';
import '../../widgets/quick_actions_item.dart';

class CloseOnFocusLossButton extends StatefulWidget {
  const CloseOnFocusLossButton({super.key});
  @override
  CloseOnFocusLossButtonState createState() => CloseOnFocusLossButtonState();
}

class CloseOnFocusLossButtonState extends State<CloseOnFocusLossButton> {
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
    if (userSettings.hideTabameOnUnfocus) {
      return QuickActionItem(
          message: "Hide on Focus Loss (CTRL + H)",
          icon: const Icon(Icons.disabled_visible_outlined),
          onTap: () => setState(() => userSettings.hideTabameOnUnfocus = !userSettings.hideTabameOnUnfocus));
    }
    return QuickActionItem(
        message: "Stay Visible (CTRL + H)",
        icon: const Icon(Icons.visibility_outlined),
        onTap: () => setState(() => userSettings.hideTabameOnUnfocus = !userSettings.hideTabameOnUnfocus));
  }
}
