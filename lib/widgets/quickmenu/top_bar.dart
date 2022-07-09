import 'package:flutter/material.dart';

import '../../main.dart';
import '../../models/globals.dart';
import '../../models/win32/win32.dart';
import '../../pages/interface.dart';
import '../itzy/always_awake_button.dart';
import '../itzy/audio_button.dart';
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
  final futureTaskbarItems = WinUtils.getTaskbarPinnedApps();
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
            children: [
              Flexible(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    const Flexible(
                      fit: FlexFit.loose,
                      child: BarWithButtons(
                        withScroll: false,
                        children: [
                          LogoDragButton(),
                          AudioButton(),
                          MediaControlButton(),
                        ],
                      ),
                    ),
                    Flexible(
                      fit: FlexFit.loose,
                      child: BarWithButtons(
                        children: [
                          const TaskManagerButton(),
                          const VirtualDesktopButton(),
                          const ToggleTaskbarButton(),
                          const PinWindowButton(),
                          const MicMuteButton(),
                          const AlwaysAwakeButton(),
                          Align(
                            child: InkWell(
                              onTap: () {
                                darkThemeNotifier.value = !darkThemeNotifier.value;
                              },
                              child: const Icon(Icons.theater_comedy_sharp),
                            ),
                          )
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
                    children: [
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
    );
  }
}
