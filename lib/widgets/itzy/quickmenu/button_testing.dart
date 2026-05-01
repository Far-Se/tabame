// ignore_for_file: dead_code, unused_import

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tabamewin32/tabamewin32.dart';
import 'package:win32/win32.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/classes/boxes/quick_menu_box.dart';
import '../../../models/classes/hotkeys.dart';
import '../../../models/globals.dart';
import '../../../models/settings.dart';
import '../../../models/win32/mixed.dart';
import '../../../models/win32/win32.dart';
import '../../../models/win32/win_utils.dart';
import '../../../models/win32/window_event.dart';
import '../../widgets/custom_tooltip.dart';
import '../../widgets/quick_actions_item.dart';
import 'button_apps.dart';
import 'button_window_app.dart';

class TestingButton extends StatefulWidget {
  const TestingButton({super.key});

  @override
  State<TestingButton> createState() => _TestingButtonState();
}

class _TestingButtonState extends State<TestingButton> {
  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message: "Testing",
      icon: const Icon(Icons.science),
      onTap: () async {
        if (kReleaseMode) {
          final String res = await WindowsAppButton.getCacheInKb();
          WinUtils.msgBox("Cache", "${WindowsAppButton.iconFutureCache.length} Cache: $res ");
        }
        print(FocusScope.of(context).focusedChild);
        // print(Globals.quickMenuPage);
        return;
      },
      onSecondaryTap: () async {
        final List<TaskbarButtonInfo> taskbar = await TaskbarUia.getButtonInfos();
        for (final TaskbarButtonInfo button in taskbar) {
          print(button);
        }
      },
      onTertiaryTapUp: (TapUpDetails details) async {
        final List<ExtendedTrayIcon> icons = await WinTray.enumAllIcons();
        //get current mouse position
        final Pointer<POINT> point = calloc<POINT>();
        GetCursorPos(point);
        final int x = point.ref.x;
        final int y = point.ref.y;
        free(point);
        WinTray.click(icons.where((ExtendedTrayIcon element) => element.processId == 10632).first,
            clickType: TrayClickType.left);
        // interval 10ms move mosue back to pos
        await Future<void>.delayed(const Duration(milliseconds: 400));
        SetCursorPos(x, y);
      },
    );
  }
}
