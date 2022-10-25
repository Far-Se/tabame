import 'package:flutter/material.dart';

import '../../../models/settings.dart';

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
    return SizedBox(
      width: 20,
      height: double.maxFinite,
      child: InkWell(
        child: globalSettings.hideTabameOnUnfocus
            ? const Tooltip(message: "Hide on Focus Loss", child: Icon(Icons.disabled_visible_outlined))
            : const Tooltip(message: "Stay Visible", child: Icon(Icons.visibility_outlined)),
        onTap: () => setState(() => globalSettings.hideTabameOnUnfocus = !globalSettings.hideTabameOnUnfocus),
      ),
    );
  }
}
