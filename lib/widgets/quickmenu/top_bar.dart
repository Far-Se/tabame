import 'package:flutter/material.dart';

import '../../models/globals.dart';
import '../../models/utils.dart';
import '../../models/win32/win32.dart';
import '../itzy/quickmenu/always_awake_button.dart';
import '../itzy/quickmenu/audio_button.dart';
import '../itzy/quickmenu/change_theme_button.dart';
import '../itzy/quickmenu/logo_drag_button.dart';
import '../itzy/quickmenu/media_control_button.dart';
import '../itzy/quickmenu/mic_mute_button.dart';
import '../itzy/quickmenu/open_settings_button.dart';
import '../itzy/quickmenu/pin_window_button.dart';
import '../itzy/quickmenu/pinned_apps.dart';
import '../itzy/quickmenu/simulate_key_button.dart';
import '../containers/bar_with_buttons.dart';
import '../itzy/quickmenu/task_manager_button.dart';
import '../itzy/quickmenu/toggle_taskbar_button.dart';
import '../itzy/quickmenu/virtual_desktop_button.dart';

class TopBar extends StatelessWidget {
  TopBar({Key? key}) : super(key: key);
  final Future<List<String>> futureTaskbarItems = WinUtils.getTaskbarPinnedApps();
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
              Flexible(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.max,
                  children: <Widget>[
                    Flexible(
                      fit: FlexFit.loose,
                      child: BarWithButtons(
                        withScroll: false,
                        children: <Widget>[
                          const LogoDragButton(),
                          const AudioButton(),
                          const MediaControlButton(),
                          Align(
                            child: InkWell(
                              onTap: () {
                                WinUtils.setVolumeOSDStyle(type: VolumeOSDStyle.media, applyStyle: false);
                                WinUtils.setVolumeOSDStyle(type: VolumeOSDStyle.thin, applyStyle: true);
                              },
                              child: const Icon(Icons.auto_fix_high),
                            ),
                          ),
                          // const WindowsAppButton(path: "C:\\Windows\\System32\\Taskmgr.exe"),
                        ],
                      ),
                    ),
                    const Flexible(
                      fit: FlexFit.loose,
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
                    const SizedBox(width: 3),
                    const Flexible(fit: FlexFit.loose, child: PinnedApps()),
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
