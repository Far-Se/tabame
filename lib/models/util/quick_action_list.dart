// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:flutter/material.dart';
import '../../widgets/itzy/quickmenu/button_always_awake.dart';
import '../../widgets/itzy/quickmenu/button_bookmarks.dart';
import '../../widgets/itzy/quickmenu/button_case_change.dart';
import '../../widgets/itzy/quickmenu/button_change_theme.dart';
import '../../widgets/itzy/quickmenu/button_chars.dart';
import '../../widgets/itzy/quickmenu/button_closeonfocus.dart';
import '../../widgets/itzy/quickmenu/button_countdown.dart';
import '../../widgets/itzy/quickmenu/button_fancyshot.dart';
import '../../widgets/itzy/quickmenu/button_hide_desktop_files.dart';
import '../../widgets/itzy/quickmenu/button_memo.dart';
import '../../widgets/itzy/quickmenu/button_mic_mute.dart';
import '../../widgets/itzy/quickmenu/button_pin_window.dart';
import '../../widgets/itzy/quickmenu/button_quickactions_menu.dart';
import '../../widgets/itzy/quickmenu/button_shutdown.dart';
import '../../widgets/itzy/quickmenu/button_spotify.dart';
import '../../widgets/itzy/quickmenu/button_task_manager.dart';
import '../../widgets/itzy/quickmenu/button_timers.dart';
import '../../widgets/itzy/quickmenu/button_toggle_hidden_files.dart';
import '../../widgets/itzy/quickmenu/button_workspace.dart';
import '../../widgets/itzy/quickmenu/button_toggle_taskbar.dart';
import '../../widgets/itzy/quickmenu/button_virtual_desktop.dart';

class QuickAction {
  String name;
  IconData icon;
  Widget widget;
  QuickAction({
    required this.name,
    required this.icon,
    required this.widget,
  });
}

final Map<String, QuickAction> quickActionsMap = <String, QuickAction>{
  "TaskManagerButton": QuickAction(
    name: "TaskManagerButton",
    icon: Icons.app_registration,
    widget: const TaskManagerButton(),
  ),
  "SpotifyButton": QuickAction(
    name: "SpotifyButton",
    icon: Icons.music_note,
    widget: const SpotifyButton(),
  ),
  "WorkSpaceButton": QuickAction(
    name: "WorkSpaceButton",
    icon: Icons.add,
    widget: const WorkSpaceButton(),
  ),
  "VirtualDesktopButton": QuickAction(
    name: "VirtualDesktopButton",
    icon: Icons.display_settings_outlined,
    widget: const VirtualDesktopButton(),
  ),
  "ToggleTaskbarButton": QuickAction(
    name: "ToggleTaskbarButton",
    icon: Icons.call_to_action_outlined,
    widget: const ToggleTaskbarButton(),
  ),
  "PinWindowButton": QuickAction(
    name: "PinWindowButton",
    icon: Icons.pin_end,
    widget: const PinWindowButton(),
  ),
  "MicMuteButton": QuickAction(
    name: "MicMuteButton",
    icon: Icons.mic,
    widget: const MicMuteButton(),
  ),
  "AlwaysAwakeButton": QuickAction(
    name: "AlwaysAwakeButton",
    icon: Icons.running_with_errors,
    widget: const AlwaysAwakeButton(),
  ),
  "ChangeThemeButton": QuickAction(
    name: "ChangeThemeButton",
    icon: Icons.theater_comedy_sharp,
    widget: const ChangeThemeButton(),
  ),
  "HideDesktopFilesButton": QuickAction(
    name: "HideDesktopFilesButton",
    icon: Icons.hide_image,
    widget: const HideDesktopFilesButton(),
  ),
  "ToggleHiddenFilesButton": QuickAction(
    name: "ToggleHiddenFilesButton",
    icon: Icons.folder_off,
    widget: const ToggleHiddenFilesButton(),
  ),
  "QuickActionsMenuButton": QuickAction(
    name: "QuickActionsMenuButton",
    icon: Icons.grid_view,
    widget: const QuickActionsMenuButton(),
  ),
  "FancyShotButton": QuickAction(
    name: "FancyShotButton",
    icon: Icons.center_focus_strong_rounded,
    widget: const FancyShotButton(),
  ),
  "TimersButton": QuickAction(
    name: "TimersButton",
    icon: Icons.timer_sharp,
    widget: const TimersButton(),
  ),
  "CountdownButton": QuickAction(
    name: "CountdownButton",
    icon: Icons.hourglass_bottom_rounded,
    widget: const CountdownButton(),
  ),
  "BookmarksButton": QuickAction(
    name: "BookmarksButton",
    icon: Icons.folder_copy_outlined,
    widget: const BookmarksButton(),
  ),
  "CustomCharsButton": QuickAction(
    name: "CustomCharsButton",
    icon: Icons.format_quote,
    widget: const CustomCharsButton(),
  ),
  "ShutDownButton": QuickAction(
    name: "ShutDownButton",
    icon: Icons.power_settings_new_rounded,
    widget: const ShutDownButton(),
  ),
  "CaseChangeButton": QuickAction(
    name: "CaseChangeButton",
    icon: Icons.visibility,
    widget: const CaseChangeButton(),
  ),
  "CloseOnFocusLossButton": QuickAction(
    name: "CloseOnFocusLossButton",
    icon: Icons.text_fields_rounded,
    widget: const CloseOnFocusLossButton(),
  ),
  "MemosButton": QuickAction(
    name: "MemosButton",
    icon: Icons.note_alt_outlined,
    widget: const MemosButton(),
  ),
};
