import 'package:flutter/material.dart';

import '../../models/globals.dart';
import '../itzy/quickmenu/button_always_awake.dart';
import '../itzy/quickmenu/button_audio.dart';
import '../itzy/quickmenu/button_change_theme.dart';
import '../itzy/quickmenu/button_logo_drag.dart';
import '../itzy/quickmenu/button_media_control.dart';
import '../itzy/quickmenu/button_mic_mute.dart';
import '../itzy/quickmenu/button_open_settings.dart';
import '../itzy/quickmenu/button_pin_window.dart';
import '../itzy/quickmenu/list_pinned_apps.dart';
import '../itzy/quickmenu/button_simulate_key.dart';
import '../containers/bar_with_buttons.dart';
import '../itzy/quickmenu/button_task_manager.dart';
import '../itzy/quickmenu/button_toggle_taskbar.dart';
import '../itzy/quickmenu/button_virtual_desktop.dart';

class TopBar extends StatelessWidget {
  const TopBar({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    Globals.heights.topbar = 25;
    return Theme(
      data: Theme.of(context).copyWith(
          iconTheme: const IconThemeData(size: 16),
          hoverColor: Colors.grey.withAlpha(50),
          tooltipTheme: Theme.of(context).tooltipTheme.copyWith(decoration: BoxDecoration(color: Theme.of(context).backgroundColor), preferBelow: false)),
      child: IconTheme(
        data: IconThemeData(
          size: 16,
          color: Theme.of(context).iconTheme.color,
        ),
        child: SizedBox(
          height: 25,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.max,
            children: <Widget>[
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.max,
                  children: <Widget>[
                    const Expanded(
                      flex: 3,
                      // fit: FlexFit.loose,
                      child: BarWithButtons(
                        withScroll: false,
                        children: <Widget>[
                          LogoDragButton(),
                          AudioButton(),
                          MediaControlButton(),
                          /* Align(
                            child: InkWell(
                              onTap: () {
                                WinUtils.setVolumeOSDStyle(type: VolumeOSDStyle.media, applyStyle: false);
                                WinUtils.setVolumeOSDStyle(type: VolumeOSDStyle.thin, applyStyle: true);
                              },
                              child: const Icon(Icons.auto_fix_high),
                            ),
                          ), */
                          // const WindowsAppButton(path: "C:\\Windows\\System32\\Taskmgr.exe"),
                        ],
                      ),
                    ),
                    const Expanded(
                      flex: 4,
                      // fit: FlexFit.loose,
                      child: BarWithButtons(
                        children: <Widget>[
                          TaskManagerButton(),
                          VirtualDesktopButton(),
                          ToggleTaskbarButton(),
                          PinWindowButton(),
                          MicMuteButton(),
                          AlwaysAwakeButton(),
                          ChangeThemeButton()
                        ],
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Expanded(flex: 3, child: PinnedApps()),
                  ],
                ),
              ),
              const SizedBox(
                width: 50,
                child: Align(
                  child: BarWithButtons(
                    height: 25,
                    withScroll: false,
                    children: <Widget>[
                      SimulateKeyButton(icon: Icons.desktop_windows, simulateKeys: "{#WIN}D", tooltip: "Toggle Desktop"),
                      OpenSettingsButton(),
                    ],
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
