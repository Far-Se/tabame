import 'package:flutter/material.dart';

import '../../models/globals.dart';
import '../../models/win32/win32.dart';
import '../../pages/interface.dart';
import '../itzy/always_awake_button.dart';
import '../itzy/audio_button.dart';
import '../itzy/change_theme_button.dart';
import '../itzy/logo_drag_button.dart';
import '../itzy/media_control_button.dart';
import '../itzy/mic_mute_button.dart';
import '../itzy/pin_window_button.dart';
import '../itzy/pinned_apps.dart';
import '../itzy/simulate_key_button.dart';
import '../containers/bar_with_buttons.dart';
import '../itzy/task_manager_button.dart';
import '../itzy/toggle_taskbar_button.dart';
import '../itzy/virtual_desktop_button.dart';

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
                    const Flexible(
                      fit: FlexFit.loose,
                      child: BarWithButtons(
                        withScroll: false,
                        children: <Widget>[
                          LogoDragButton(),
                          AudioButton(),
                          MediaControlButton(),
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
                    const Flexible(fit: FlexFit.tight, child: PinnedApps()),
                  ],
                ),
              ),
              SizedBox(
                width: 50,
                child: Align(
                  child: BarWithButtons(
                    height: 25,
                    withScroll: false,
                    children: <Widget>[
                      const SimulateKeyButton(icon: Icons.desktop_windows, simulateKeys: "{#WIN}D", tooltip: "Toggle Desktop"),
                      Material(
                        type: MaterialType.transparency,
                        child: SizedBox(
                          width: 25,
                          child: IconButton(
                            padding: const EdgeInsets.all(0),
                            splashRadius: 25,
                            icon: const Icon(
                              Icons.settings,
                            ),
                            onPressed: () {
                              PaintingBinding.instance.imageCache.clear();
                              PaintingBinding.instance.imageCache.clearLiveImages();
                              Navigator.of(context).pushAndRemoveUntil(
                                MaterialPageRoute<Interface>(maintainState: false, builder: (BuildContext context) => const Interface()),
                                (Route<dynamic> route) => false,
                              );
                              // Navigator.push(
                              //   context,
                              //   MaterialPageRoute<Interface>(builder: (BuildContext context) => const Interface()),
                              // );
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
    );
  }
}
