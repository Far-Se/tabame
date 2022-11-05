import 'package:flutter/material.dart';

import '../../../models/settings.dart';
import '../../widgets/quick_actions_item.dart';

class CloseOnFocusLossButton extends StatefulWidget {
  const CloseOnFocusLossButton({Key? key}) : super(key: key);
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
    if (globalSettings.hideTabameOnUnfocus) {
      return QuickActionItem(
          message: "Hide on Focus Loss",
          icon: const Icon(Icons.disabled_visible_outlined),
          onTap: () => setState(() => globalSettings.hideTabameOnUnfocus = !globalSettings.hideTabameOnUnfocus));
    }
    return QuickActionItem(
        message: "Stay Visible",
        icon: const Icon(Icons.visibility_outlined),
        onTap: () => setState(() => globalSettings.hideTabameOnUnfocus = !globalSettings.hideTabameOnUnfocus));
  }
}
