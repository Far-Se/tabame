// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:flutter/material.dart';
import '../../widgets/itzy/quickmenu/button_always_awake.dart';
import '../../widgets/itzy/quickmenu/button_audio.dart';
import '../../widgets/itzy/quickmenu/button_bookmarks.dart';
import '../../widgets/itzy/quickmenu/button_change_theme.dart';
import '../../widgets/itzy/quickmenu/button_chars.dart';
import '../../widgets/itzy/quickmenu/button_cli_book.dart';
import '../../widgets/itzy/quickmenu/button_color_picker.dart';
import '../../widgets/itzy/quickmenu/button_closeonfocus.dart';
import '../../widgets/itzy/quickmenu/button_countdown.dart';
import '../../widgets/itzy/quickmenu/button_currency_converter.dart';
import '../../widgets/itzy/quickmenu/button_authenticator.dart';
import '../../widgets/itzy/quickmenu/button_fancyshot.dart';
import '../../widgets/itzy/quickmenu/button_hide_desktop_files.dart';
import '../../widgets/itzy/quickmenu/button_media_control.dart';
import '../../widgets/itzy/quickmenu/button_memo.dart';
import '../../widgets/itzy/quickmenu/button_menu_design.dart';
import '../../widgets/itzy/quickmenu/button_qr_scanner.dart';
import '../../widgets/itzy/quickmenu/button_timezone.dart';
import '../../widgets/itzy/quickmenu/button_mic_mute.dart';
import '../../widgets/itzy/quickmenu/button_app_audio.dart';
import '../../widgets/itzy/quickmenu/button_pin_window.dart';
import '../../widgets/itzy/quickmenu/button_quickactions.dart';
import '../../widgets/itzy/quickmenu/button_shutdown.dart';
import '../../widgets/itzy/quickmenu/button_spotify.dart';
import '../../widgets/itzy/quickmenu/button_task_manager.dart';
import '../../widgets/itzy/quickmenu/button_timers.dart';
import '../../widgets/itzy/quickmenu/button_toggle_desktop.dart';
import '../../widgets/itzy/quickmenu/button_toggle_hidden_files.dart';
import '../../widgets/itzy/quickmenu/button_toggle_wallpaper_mode.dart';
import '../../widgets/itzy/quickmenu/button_toggle_taskbar.dart';
import '../../widgets/itzy/quickmenu/button_virtual_desktop.dart';
import '../../widgets/itzy/quickmenu/button_vault.dart';
import '../../widgets/itzy/quickmenu/button_calculator.dart';
import '../../widgets/itzy/quickmenu/button_wallpapers.dart';
import '../../widgets/itzy/quickmenu/button_apps.dart';

class QuickAction {
  String name;
  IconData icon;
  Widget widget;
  VoidCallback? onExecute;
  QuickAction({
    required this.name,
    required this.icon,
    required this.widget,
    this.onExecute,
  });
}

final Map<String, QuickAction> quickActionsMap = <String, QuickAction>{
  "AudioButton": QuickAction(
    name: "AudioButton",
    icon: Icons.volume_up,
    widget: const AudioButton(),
  ),
  "MediaControlButton": QuickAction(
    name: "MediaControlButton",
    icon: Icons.play_arrow,
    widget: const MediaControlButton(),
  ),
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
  //! Audio Control
  "AppAudioControl1": QuickAction(
    name: "App Audio Control 1",
    icon: Icons.music_video_outlined,
    widget: const AppAudioButton(index: 0),
  ),
  "AppAudioControl2": QuickAction(
    name: "App Audio Control 2",
    icon: Icons.music_video_outlined,
    widget: const AppAudioButton(index: 1),
  ),
  "AppAudioControl3": QuickAction(
    name: "App Audio Control 3",
    icon: Icons.music_video_outlined,
    widget: const AppAudioButton(index: 2),
  ),
  "AppAudioControl4": QuickAction(
    name: "App Audio Control 4",
    icon: Icons.music_video_outlined,
    widget: const AppAudioButton(index: 3),
  ),
  "AppAudioControl5": QuickAction(
    name: "App Audio Control 5",
    icon: Icons.music_video_outlined,
    widget: const AppAudioButton(index: 4),
  ),
  //! Rest
  "AppsButton": QuickAction(
    name: "AppsButton",
    icon: Icons.apps,
    widget: const AppsButton(),
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
  "ToggleWallpaperModeButton": QuickAction(
    name: "ToggleWallpaperModeButton",
    icon: Icons.wallpaper_rounded,
    widget: const ToggleWallpaperModeButton(),
  ),
  "TimersButton": QuickAction(
    name: "TimersButton",
    icon: Icons.timer_sharp,
    widget: const TimersButton(),
  ),
  "BookmarksButton": QuickAction(
    name: "BookmarksButton",
    icon: Icons.folder_copy_outlined,
    widget: const BookmarksButton(),
  ),
  "CliBookButton": QuickAction(
    name: "CliBookButton",
    icon: Icons.note_alt_outlined,
    widget: const CliBookButton(),
  ),
  "VaultButton": QuickAction(
    name: "VaultButton",
    icon: Icons.lock_rounded,
    widget: const VaultButton(),
  ),
  "MemosButton": QuickAction(
    name: "MemosButton",
    icon: Icons.note_alt_outlined,
    widget: const MemosButton(),
  ),
  "WallpapersButton": QuickAction(
    name: "WallpapersButton",
    icon: Icons.photo_library_outlined,
    widget: const WallpapersButton(),
  ),
  "CalculatorButton": QuickAction(
    name: "CalculatorButton",
    icon: Icons.calculate_outlined,
    widget: const CalculatorButton(),
  ),
  "TimeZoneButton": QuickAction(
    name: "TimeZoneButton",
    icon: Icons.public_rounded,
    widget: const TimeZoneButton(),
  ),
  "CurrencyConverterButton": QuickAction(
    name: "CurrencyConverterButton",
    icon: Icons.currency_exchange_rounded,
    widget: const CurrencyConverterButton(),
  ),
  "AuthenticatorButton": QuickAction(
    name: "AuthenticatorButton",
    icon: Icons.shield_outlined,
    widget: const AuthenticatorButton(),
  ),
  "QrScannerButton": QuickAction(
    name: "QrScannerButton",
    icon: Icons.qr_code_scanner_rounded,
    widget: const QrScannerButton(),
  ),
  "ColorPickerButton": QuickAction(
    name: "ColorPickerButton",
    icon: Icons.palette_outlined,
    widget: const ColorPickerButton(),
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
  "ToggleDesktopButton": QuickAction(
    name: "ToggleDesktopButton",
    icon: Icons.desktop_windows_rounded,
    widget: const ToggleDesktopButton(),
  ),
  "CountdownButton": QuickAction(
    name: "CountdownButton",
    icon: Icons.hourglass_bottom_rounded,
    widget: const CountdownButton(),
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
  "ChangeThemeButton": QuickAction(
    name: "ChangeThemeButton",
    icon: Icons.theater_comedy_sharp,
    widget: const ChangeThemeButton(),
  ),
  "CloseOnFocusLossButton": QuickAction(
    name: "CloseOnFocusLossButton",
    icon: Icons.visibility,
    widget: const CloseOnFocusLossButton(),
  ),
  "SwitchQuickMenuDesignButton": QuickAction(
    name: "SwitchQuickMenuDesignButton",
    icon: Icons.dashboard_customize_outlined,
    widget: const SwitchQuickMenuDesignButton(),
  ),
};
