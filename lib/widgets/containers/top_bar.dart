import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:win32/win32.dart';

import '../../models/win32/win32.dart';
import '../../pages/interface.dart';
import '../itzy/audio_button.dart';
import '../itzy/logo_drag_button.dart';
import '../itzy/media_control_button.dart';
import '../itzy/mic_mute_button.dart';
import '../itzy/pinned_apps.dart';
import '../itzy/simulate_key_button.dart';
import 'bar_with_buttons.dart';

class TopBar extends StatelessWidget {
  TopBar({Key? key}) : super(key: key);
  final futureTaskbarItems = WinUtils.getTaskbarPinnedApps();
  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(
        iconTheme: IconThemeData(size: 16),
      ),
      child: IconTheme(
        data: IconThemeData(
          size: 16,
          color: Colors.grey.shade200,
        ),
        child: SizedBox(
          height: 25,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0xff3B414D),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.max,
              children: [
                Flexible(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LogoDragButton(),
                      AudioButton(),
                      MediaControlButton(),
                      MicMuteButton(),
                      Align(
                        child: InkWell(
                          child: Icon(Icons.text_snippet),
                          onTap: () async {
                            // Win32.setCenter(useMouse: true);
                            final lpRect = calloc<RECT>();
                            GetWindowRect(Win32.hWnd, lpRect);
                            print("L:${lpRect.ref.left} T:${lpRect.ref.top} R:${lpRect.ref.right} B:${lpRect.ref.bottom}");
                            final monitor = Win32.getWindowMonitor(Win32.hWnd);
                            //print(Monitor.monitorSizes[monitor]);
                            Win32.setCenter(useMouse: true);
                            free(lpRect);
                          },
                        ),
                      ),
                      Flexible(child: PinnedApps()),
                    ],
                  ),
                ),
                // Spacer(flex: 1),
                SizedBox(
                  width: 50,
                  child: Align(
                    child: BarWithButtons(
                      height: 25,
                      withScroll: false,
                      children: [
                        SimulateKeyButton(icon: Icons.desktop_windows, simulateKeys: "{#WIN}D"),
                        Material(
                          type: MaterialType.transparency,
                          child: SizedBox(
                            width: 25,
                            child: IconButton(
                              padding: EdgeInsets.all(0),
                              splashRadius: 25,
                              icon: Icon(
                                Icons.settings,
                              ),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => const Interface()),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
