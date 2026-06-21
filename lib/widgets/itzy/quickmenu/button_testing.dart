// ignore_for_file: unused_import, dead_code

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tabamewin32/tabamewin32.dart';

// import '../../../models/win32/win32.dart';
import '../../../models/settings.dart';
import '../../../models/util/quickmenu_modal.dart';
import '../../../models/win32/win32.dart';
import '../../../models/win32/win_utils.dart';
import '../../widgets/panel_header.dart';
import '../../widgets/quick_actions_item.dart';

class TestingButton extends StatefulWidget {
  const TestingButton({super.key});

  @override
  State<TestingButton> createState() => _TestingButtonState();
}

class _TestingButtonState extends State<TestingButton> {
  Timer? timer;
  Uint8List? xIcon;
  AppInfo? app;
  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message: "Testing",
      icon: xIcon != null ? Image.memory(xIcon!) : const Icon(Icons.science),
      onTap: () async {
        if (kReleaseMode || true) {
          showQuickMenuModal(
            context: context,
            child: const TestingChild(),
          );
          return;
        }
        final MediaSessionResult result = await MediaSessionPlugin.getMediaSessions();

        print('Current: ${result.currentSession?.title}');

        for (final MediaSession session in result.sessions) {
          print('${session.isCurrent ? "▶" : " "} [${session.id}] '
              '${session.title} — ${session.artist} (${session.playbackStatus})');
          print(session);
          if (session.thumbnailImage != null) {
            xIcon = session.thumbnail!;
            setState(() {});
          }
        }

        return;
        // xIcon = WinUtils.extractIconInternal(
        //     r"C:\Users\Far Se\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Antigravity\Antigravity.lnk", 0);
        xIcon = WinUtils.extractIconInternal(
            r"C:\Users\Far Se\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Steam\Counter-Strike.url", 0);
        print(xIcon!.length);
        setState(() {});
        return;
        const String path = 'C:\\Windows\\System32\\notepad.exe';
        print("Querying context menu items for $path...");
        try {
          final List<ShellMenuItem> items = await ShellContextMenu.getMenuItems(path);
          print("Found ${items.length} items:");
          for (final ShellMenuItem item in items) {
            print(
                "  - ID: ${item.id}, Label: ${item.label}, Verb: ${item.verb}, Enabled: ${item.enabled}, Icon bytes size: ${item.iconBytes?.length}");
          }
          if (items.isNotEmpty) {
            final ShellMenuItem openItem = items.firstWhere(
              (ShellMenuItem e) => e.verb == 'open' || e.label.toLowerCase().contains('open'),
              orElse: () => items.first,
            );
            print("Invoking: ${openItem.label} (Verb: ${openItem.verb}, ID: ${openItem.id})");
            final bool success = await ShellContextMenu.invoke(path, Win32.hWnd, verb: openItem.verb, id: openItem.id);
            print("Invoke success: $success");
          }
        } catch (e) {
          print("Error testing context menu: $e");
        }
        return;
        // print(FocusScope.of(context).focusedChild);
        // print(Globals.quickMenuPage);
        return;
      },
      onSecondaryTap: () async {
        WinUtils.open("shell:AppsFolder\\${app?.appUserModelId ?? "a"}");
        return;
        final List<TaskbarButtonInfo> taskbar = await TaskbarUia.getButtonInfos();
        for (final TaskbarButtonInfo button in taskbar) {
          print(button);
        }
      },
      onTertiaryTapUp: (TapUpDetails details) async {
        final List<ExtendedTrayIcon> icons = await WinTray.enumAllIcons();
        //get current mouse position
        print(icons);
        // final Pointer<POINT> point = calloc<POINT>();
        // GetCursorPos(point);
        // final int x = point.ref.x;
        // final int y = point.ref.y;
        // free(point);
        // WinTray.click(icons.where((ExtendedTrayIcon element) => element.processId == 10632).first,
        //     clickType: TrayClickType.left);
        // // interval 10ms move mosue back to pos
        // await Future<void>.delayed(const Duration(milliseconds: 400));
        // SetCursorPos(x, y);
      },
    );
  }
}

class TestingChild extends StatelessWidget {
  const TestingChild({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: M.start,
      crossAxisAlignment: C.start,
      children: <Widget>[
        const PanelHeader(icon: Icons.science, title: "Debug"),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
          child: Column(
            mainAxisAlignment: M.start,
            crossAxisAlignment: C.start,
            children: <Widget>[
              Text('user.runAsAdministrator : ${user.runAsAdministrator}'),
              Text('WinUtils.isAdministrator : ${WinUtils.isAdministrator()}'),
              Text('user.args.contains -tryadmin: ${user.args.join(' ').contains('-tryadmin')}'),
              Text('user.args: ${user.args.join(' ')}'),
            ],
          ),
        ),
      ],
    );
  }
}
