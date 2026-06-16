import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../../models/win32/win_utils.dart';
import '../../widgets/quick_actions_item.dart';

class HideDesktopFilesButton extends StatefulWidget {
  const HideDesktopFilesButton({super.key});

  @override
  State<HideDesktopFilesButton> createState() => _HideDesktopFilesButtonState();
}

class _HideDesktopFilesButtonState extends State<HideDesktopFilesButton> {
  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message: "Desktop Files: ${user.hideDesktopFiles ? 'Hidden' : 'Visible'}",
      icon: Icon(user.hideDesktopFiles ? Icons.desktop_access_disabled_outlined : Icons.folder_open),
      onTap: () {
        user.hideDesktopFiles = !user.hideDesktopFiles;
        Boxes.updateSettings("hideDesktopFiles", user.hideDesktopFiles);
        if (user.hideDesktopFiles) {
          WinUtils.toggleDesktopFiles(visible: false);
        } else {
          WinUtils.toggleDesktopFiles(visible: true);
        }
        setState(() {});
      },
    );
  }
}
