import 'package:flutter/material.dart';

import '../../../models/win32/win32.dart';

class HideDesktopFilesButton extends StatelessWidget {
  const HideDesktopFilesButton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: double.maxFinite,
      child: InkWell(
        child: const Tooltip(message: "Toggle Desktop Files", child: Icon(Icons.hide_image)),
        onTap: () async {
          WinUtils.toggleDesktopFiles();
        },
      ),
    );
  }
}
