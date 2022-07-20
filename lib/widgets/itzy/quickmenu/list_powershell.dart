import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:win32/win32.dart';

import '../../../models/utils.dart';
import '../../../models/win32/win32.dart';
import '../../containers/bar_with_buttons.dart';

class PowershellList extends StatefulWidget {
  const PowershellList({Key? key}) : super(key: key);

  @override
  PowershellListState createState() => PowershellListState();
}

class PowershellListState extends State<PowershellList> {
  final List<PowerShellScript> scripts = Boxes().getPowerShellScripts().where((PowerShellScript element) => !element.disabled).toList();
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    if (scripts.isEmpty) return const SizedBox(width: 0);
    final Color color = Color(darkerColor(Theme.of(context).backgroundColor.value, darkenBy: 0x30) as int).withOpacity(0.3);
    return Align(
      alignment: Alignment.centerRight,
      child: BarWithButtons(
        children: <Widget>[
          for (PowerShellScript item in scripts)
            Container(
              constraints: const BoxConstraints(maxWidth: 20, minWidth: 20, minHeight: 20),
              margin: const EdgeInsets.only(right: 2),
              decoration:
                  BoxDecoration(shape: BoxShape.circle, color: Color(darkerColor(Theme.of(context).backgroundColor.value, darkenBy: 0x30) as int).withOpacity(0.3)),
              child: Tooltip(
                message: item.name,
                child: InkWell(
                    child: Center(
                      child: Text(
                        item.name.substring(0, 1),
                        style: const TextStyle(fontSize: 12, height: 1),
                      ),
                    ),
                    onTap: () async {
                      if (!item.showTerminal) {
                        WinUtils.runPowerShell(<String>[item.command]);
                      } else {
                        ShellExecute(Win32.hWnd, TEXT("open"), TEXT('powershell'), TEXT('-NoExit -executionpolicy bypass -command "${item.command}"'),
                            Pointer<Utf16>.fromAddress(0), SW_SHOWNORMAL);
                      }
                    }),
              ),
            )
        ],
      ),
    );
  }
}
