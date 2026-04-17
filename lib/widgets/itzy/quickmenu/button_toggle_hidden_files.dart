import 'package:flutter/material.dart';

import '../../../models/globals.dart';
import '../../../models/win32/win32.dart';
import 'package:tabame/widgets/widgets/custom_tooltip.dart';

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
    if (Globals.quickMenuPage == QuickMenuPage.quickActions) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            onTap: () => WinUtils.toggleHiddenFiles(visible: false),
            child: const SizedBox(
              height: 25,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  SizedBox(width: 5),
                  SizedBox(width: 20, child: Icon(Icons.folder_off_outlined)),
                  SizedBox(width: 5),
                  Text("Hide Hidden Files")
                ],
              ),
            ),
          ),
          InkWell(
            onTap: () => WinUtils.toggleHiddenFiles(visible: true),
            child: const SizedBox(
              height: 25,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  SizedBox(width: 5),
                  SizedBox(width: 20, child: Icon(Icons.folder_outlined)),
                  SizedBox(width: 5),
                  Text("Show Hidden Files")
                ],
              ),
            ),
          )
        ],
      );
    }
    return SizedBox(
      width: 20,
      height: double.maxFinite,
      child: GestureDetector(
        onSecondaryTap: () => WinUtils.toggleHiddenFiles(visible: false),
        onTertiaryTapUp: (TapUpDetails details) => WinUtils.toggleHiddenFiles(visible: true),
        child: InkWell(
          child: CustomTooltip(
              message: _visible == 1 ? "Hide Hidden Files" : "Show Hidden Files",
              child: Icon(_visible == 1 ? Icons.folder_outlined : Icons.folder_off_outlined)),
          onTap: () async {
            WinUtils.toggleHiddenFiles();
            setState(() {
              if (_visible != -1) _visible = _visible == 1 ? 0 : 1;
            });
          },
        ),
      ),
    );
  }
}
