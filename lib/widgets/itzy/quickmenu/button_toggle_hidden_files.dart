import 'package:flutter/material.dart';

import '../../../models/win32/win_utils.dart';
import '../../widgets/quick_actions_item.dart';

class ToggleHiddenFilesButton extends StatefulWidget {
  const ToggleHiddenFilesButton({super.key});

  @override
  State<ToggleHiddenFilesButton> createState() => _ToggleHiddenFilesButtonState();
}

class _ToggleHiddenFilesButtonState extends State<ToggleHiddenFilesButton> {
  int _visible = WinUtils.areHiddenFilesVisible();

  @override
  void initState() {
    super.initState();
    _visible = WinUtils.areHiddenFilesVisible();
  }

  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message: _visible == 1 ? "Hide Hidden Files" : "Show Hidden Files",
      icon: Icon(_visible == 1 ? Icons.folder_outlined : Icons.folder_off_outlined),
      onTap: () async {
        WinUtils.toggleHiddenFiles();
        setState(() {
          if (_visible != -1) _visible = _visible == 1 ? 0 : 1;
        });
      },
      onSecondaryTap: () => WinUtils.toggleHiddenFiles(visible: false),
      onTertiaryTapUp: (TapUpDetails details) => WinUtils.toggleHiddenFiles(visible: true),
    );
  }
}
