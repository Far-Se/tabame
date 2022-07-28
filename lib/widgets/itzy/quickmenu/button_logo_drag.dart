import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../../models/utils.dart';

class LogoDragButton extends StatelessWidget {
  const LogoDragButton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (DragStartDetails details) {
        windowManager.startDragging();
      },
      child: InkWell(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Align(
              alignment: Alignment.centerLeft,
              child: globalSettings.customLogo == "" ? Image.asset(globalSettings.logo, width: 15) : Image.file(File(globalSettings.customLogo), width: 15)),
        ),
      ),
    );
  }
}
