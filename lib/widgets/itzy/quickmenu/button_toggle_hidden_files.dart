import 'package:flutter/material.dart';

import '../../../models/win32/win32.dart';

class ToggleHiddenFilesButton extends StatelessWidget {
  const ToggleHiddenFilesButton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: double.maxFinite,
      child: InkWell(
        child: const Tooltip(message: "Toggle Hidden Files", child: Icon(Icons.folder_off)),
        onTap: () async {
          WinUtils.toggleHiddenFiles();
        },
      ),
    );
  }
}
