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
    return QuickActionItem(
        message: user.hideTabameOnUnfocus ? "Hides on Focus Loss (CTRL + H)" : "Stays Visible (CTRL + H)",
        icon: user.hideTabameOnUnfocus
            ? const Icon(Icons.disabled_visible_outlined)
            : const Icon(Icons.visibility_outlined),
        onTap: () => setState(() => user.hideTabameOnUnfocus = !user.hideTabameOnUnfocus));
  }
}
