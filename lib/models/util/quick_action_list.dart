// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:flutter/material.dart';

import '../../widgets/itzy/quickmenu/button_always_awake.dart';
import '../../widgets/itzy/quickmenu/button_app_audio.dart';
import '../../widgets/itzy/quickmenu/button_apps.dart';
import '../../widgets/itzy/quickmenu/button_audio.dart';
import '../../widgets/itzy/quickmenu/button_authenticator.dart';
import '../../widgets/itzy/quickmenu/button_bookmarks.dart';
import '../../widgets/itzy/quickmenu/button_calculator.dart';
import '../../widgets/itzy/quickmenu/button_change_theme.dart';
import '../../widgets/itzy/quickmenu/button_chars.dart';
import '../../widgets/itzy/quickmenu/button_clear_keyboard.dart';
import '../../widgets/itzy/quickmenu/button_cli_book.dart';
import '../../widgets/itzy/quickmenu/button_clipboard_history.dart';
import '../../widgets/itzy/quickmenu/button_closeonfocus.dart';
import '../../widgets/itzy/quickmenu/button_color_picker.dart';
import '../../widgets/itzy/quickmenu/button_color_picker_instant.dart';
import '../../widgets/itzy/quickmenu/button_countdown.dart';
import '../../widgets/itzy/quickmenu/button_currency_converter.dart';
import '../../widgets/itzy/quickmenu/button_desktop_files.dart';
import '../../widgets/itzy/quickmenu/button_disk_cleanup.dart';
import '../../widgets/itzy/quickmenu/button_emoji.dart';
import '../../widgets/itzy/quickmenu/button_fancyshot.dart';
import '../../widgets/itzy/quickmenu/button_hide_desktop_files.dart';
import '../../widgets/itzy/quickmenu/button_launcher.dart';
import '../../widgets/itzy/quickmenu/button_media_control.dart';
import '../../widgets/itzy/quickmenu/button_memo.dart';
import '../../widgets/itzy/quickmenu/button_menu_design.dart';
import '../../widgets/itzy/quickmenu/button_mic_mute.dart';
import '../../widgets/itzy/quickmenu/button_music_player.dart';
import '../../widgets/itzy/quickmenu/button_notion.dart';
import '../../widgets/itzy/quickmenu/button_pin_window.dart';
import '../../widgets/itzy/quickmenu/button_qr_scanner.dart';
import '../../widgets/itzy/quickmenu/button_quickactions.dart';
import '../../widgets/itzy/quickmenu/button_screendraw.dart';
import '../../widgets/itzy/quickmenu/button_shutdown.dart';
import '../../widgets/itzy/quickmenu/button_spotlight.dart';
import '../../widgets/itzy/quickmenu/button_task_manager.dart';
import '../../widgets/itzy/quickmenu/button_timers.dart';
import '../../widgets/itzy/quickmenu/button_timezone.dart';
import '../../widgets/itzy/quickmenu/button_toggle_desktop.dart';
import '../../widgets/itzy/quickmenu/button_toggle_hidden_files.dart';
import '../../widgets/itzy/quickmenu/button_toggle_taskbar.dart';
import '../../widgets/itzy/quickmenu/button_toggle_wallpaper_mode.dart';
import '../../widgets/itzy/quickmenu/button_translator.dart';
import '../../widgets/itzy/quickmenu/button_vault.dart';
import '../../widgets/itzy/quickmenu/button_virtual_desktop.dart';
import '../../widgets/itzy/quickmenu/button_wallpapers.dart';
import '../../widgets/itzy/quickmenu/button_weather.dart';
import '../../widgets/itzy/quickmenu/button_workspaces.dart';
import '../../widgets/itzy/quickmenu/toggle_windows_theme.dart';

class QuickAction {
  String name;
  IconData icon;
  Widget Function() widget;
  VoidCallback? onExecute;

  QuickAction({
    required this.name,
    required this.icon,
    required this.widget,
    this.onExecute,
  });
}

final Map<String, QuickAction> quickActionsMap = <String, QuickAction>{
  "LauncherButton": QuickAction(
    name: "LauncherButton",
    icon: Icons.search,
    widget: () => const LauncherButton(),
  ),
  "AudioButton": QuickAction(
    name: "AudioButton",
    icon: Icons.volume_up,
    widget: () => const AudioButton(),
  ),
  "MediaControlButton": QuickAction(
    name: "MediaControlButton",
    icon: Icons.play_arrow,
    widget: () => const MediaControlButton(),
  ),
  "TimersButton": QuickAction(
    name: "TimersButton",
    icon: Icons.timer_sharp,
    widget: () => const TimersButton(),
  ),
  "BookmarksButton": QuickAction(
    name: "BookmarksButton",
    icon: Icons.folder_copy_outlined,
    widget: () => const BookmarksButton(),
  ),
  "CliBookButton": QuickAction(
    name: "CliBookButton",
    icon: Icons.note_alt_outlined,
    widget: () => const CliBookButton(),
  ),
  "EmojiButton": QuickAction(
    name: "EmojiButton",
    icon: Icons.emoji_emotions_outlined,
    widget: () => const EmojiButton(),
  ),
  "ClipboardHistoryButton": QuickAction(
    name: "ClipboardHistoryButton",
    icon: Icons.content_paste_search_rounded,
    widget: () => const ClipboardHistoryButton(),
  ),
  "ClearKeyboardButton": QuickAction(
    name: "ClearKeyboardButton",
    icon: Icons.keyboard_hide_rounded,
    widget: () => const ClearKeyboardButton(),
  ),
  "VaultButton": QuickAction(
    name: "VaultButton",
    icon: Icons.lock_rounded,
    widget: () => const VaultsButton(),
  ),
  "TaskManagerButton": QuickAction(
    name: "TaskManagerButton",
    icon: Icons.app_registration,
    widget: () => const TaskManagerButton(),
  ),
  "AppsButton": QuickAction(
    name: "AppsButton",
    icon: Icons.apps,
    widget: () => const AppsButton(),
  ),
  "MusicServerButton": QuickAction(
    name: "MusicServerButton",
    icon: Icons.library_music_outlined,
    widget: () => const MusicServerButton(),
  ),
  "VirtualDesktopButton": QuickAction(
    name: "VirtualDesktopButton",
    icon: Icons.display_settings_outlined,
    widget: () => const VirtualDesktopButton(),
  ),
  "ToggleTaskbarButton": QuickAction(
    name: "ToggleTaskbarButton",
    icon: Icons.call_to_action_outlined,
    widget: () => const ToggleTaskbarButton(),
  ),
  "ToggleWallpaperModeButton": QuickAction(
    name: "ToggleWallpaperModeButton",
    icon: Icons.wallpaper_rounded,
    widget: () => const ToggleWallpaperModeButton(),
  ),
  //! Audio Control
  "AppAudioControl1": QuickAction(
    name: "App Audio Control 1",
    icon: Icons.music_video_outlined,
    widget: () => const AppAudioButton(index: 0),
  ),
  "AppAudioControl2": QuickAction(
    name: "App Audio Control 2",
    icon: Icons.music_video_outlined,
    widget: () => const AppAudioButton(index: 1),
  ),
  "AppAudioControl3": QuickAction(
    name: "App Audio Control 3",
    icon: Icons.music_video_outlined,
    widget: () => const AppAudioButton(index: 2),
  ),
  "AppAudioControl4": QuickAction(
    name: "App Audio Control 4",
    icon: Icons.music_video_outlined,
    widget: () => const AppAudioButton(index: 3),
  ),
  "AppAudioControl5": QuickAction(
    name: "App Audio Control 5",
    icon: Icons.music_video_outlined,
    widget: () => const AppAudioButton(index: 4),
  ),
  //! Rest
  "MemosButton": QuickAction(
    name: "MemosButton",
    icon: Icons.note_alt_outlined,
    widget: () => const MemosButton(),
  ),
  "NotionButton": QuickAction(
    name: "NotionButton",
    icon: Icons.description_rounded,
    widget: () => const NotionButton(),
  ),
  "WallpapersButton": QuickAction(
    name: "WallpapersButton",
    icon: Icons.photo_library_outlined,
    widget: () => const WallpapersButton(),
  ),
  "CalculatorButton": QuickAction(
    name: "CalculatorButton",
    icon: Icons.calculate_outlined,
    widget: () => const CalculatorButton(),
  ),
  "TimeZoneButton": QuickAction(
    name: "TimeZoneButton",
    icon: Icons.public_rounded,
    widget: () => const TimeZoneButton(),
  ),
  "CurrencyConverterButton": QuickAction(
    name: "CurrencyConverterButton",
    icon: Icons.currency_exchange_rounded,
    widget: () => const CurrencyConverterButton(),
  ),
  "DiskCleanupButton": QuickAction(
    name: "DiskCleanupButton",
    icon: Icons.cleaning_services_rounded,
    widget: () => const DiskCleanupButton(),
  ),
  "TranslatorButton": QuickAction(
    name: "TranslatorButton",
    icon: Icons.translate_rounded,
    widget: () => const TranslatorButton(),
  ),
  "WeatherButton": QuickAction(
    name: "WeatherButton",
    icon: Icons.wb_cloudy_rounded,
    widget: () => const WeatherButton(),
  ),
  "AuthenticatorButton": QuickAction(
    name: "AuthenticatorButton",
    icon: Icons.shield_outlined,
    widget: () => const AuthenticatorButton(),
  ),
  "QrScannerButton": QuickAction(
    name: "QrScannerButton",
    icon: Icons.qr_code_scanner_rounded,
    widget: () => const QrScannerButton(),
  ),
  "ColorPickerButton": QuickAction(
    name: "ColorPickerButton",
    icon: Icons.palette_outlined,
    widget: () => const ColorPickerButton(),
  ),
  "ColorPickerInstantButton": QuickAction(
    name: "ColorPickerInstantButton",
    icon: Icons.colorize_outlined,
    widget: () => const ColorPickerInstantButton(),
  ),
  "ScreenDrawButton": QuickAction(
    name: "ScreenDrawButton",
    icon: Icons.draw_outlined,
    widget: () => const ScreenDrawButton(),
  ),
  "SpotlightButton": QuickAction(
    name: "SpotlightButton",
    icon: Icons.featured_video_rounded,
    widget: () => const SpotlightButton(),
  ),
  "FancyShotLiveButton": QuickAction(
    name: "FancyShotLiveButton",
    icon: Icons.center_focus_strong_outlined,
    widget: () => const FancyShotButton(),
  ),
  "FancyShotFreezeButton": QuickAction(
    name: "FancyShotFreezeButton",
    icon: Icons.center_focus_strong,
    widget: () => const FancyShotButton(freeze: true),
  ),
  "PhotoEditorButton": QuickAction(
    name: "PhotoEditorButton",
    icon: Icons.photo_camera_back_outlined,
    widget: () => const PhotoEditorButton(),
  ),
  "PinWindowButton": QuickAction(
    name: "PinWindowButton",
    icon: Icons.pin_end,
    widget: () => const PinWindowButton(),
  ),
  "MicMuteButton": QuickAction(
    name: "MicMuteButton",
    icon: Icons.mic,
    widget: () => const MicMuteButton(),
  ),
  "AlwaysAwakeButton": QuickAction(
    name: "AlwaysAwakeButton",
    icon: Icons.running_with_errors,
    widget: () => const AlwaysAwakeButton(),
  ),
  "HideDesktopFilesButton": QuickAction(
    name: "HideDesktopFilesButton",
    icon: Icons.hide_image,
    widget: () => const HideDesktopFilesButton(),
  ),
  "ToggleHiddenFilesButton": QuickAction(
    name: "ToggleHiddenFilesButton",
    icon: Icons.folder_off,
    widget: () => const ToggleHiddenFilesButton(),
  ),
  "QuickActionsMenuButton": QuickAction(
    name: "QuickActionsMenuButton",
    icon: Icons.grid_view,
    widget: () => const QuickActionsMenuButton(),
  ),
  "ToggleDesktopButton": QuickAction(
    name: "ToggleDesktopButton",
    icon: Icons.desktop_windows_rounded,
    widget: () => const ToggleDesktopButton(),
  ),
  "ToggleWindowsThemeButton": QuickAction(
    name: "ToggleWindowsThemeButton",
    icon: Icons.desktop_windows_rounded,
    widget: () => const ToggleWindowsThemeButton(),
  ),
  "CountdownButton": QuickAction(
    name: "CountdownButton",
    icon: Icons.hourglass_bottom_rounded,
    widget: () => const CountdownButton(),
  ),
  "CustomCharsButton": QuickAction(
    name: "CustomCharsButton",
    icon: Icons.format_quote,
    widget: () => const CustomCharsButton(),
  ),
  "ShutDownButton": QuickAction(
    name: "ShutDownButton",
    icon: Icons.power_settings_new_rounded,
    widget: () => const ShutDownButton(),
  ),
  "CloseOnFocusLossButton": QuickAction(
    name: "CloseOnFocusLossButton",
    icon: Icons.visibility,
    widget: () => const CloseOnFocusLossButton(),
  ),
  "ChangeThemeButton": QuickAction(
    name: "ChangeThemeButton",
    icon: Icons.theater_comedy_sharp,
    widget: () => const ChangeThemeButton(),
  ),
  "QuickMenuDesignButton": QuickAction(
    name: "QuickMenuDesignButton",
    icon: Icons.palette_rounded,
    widget: () => const QuickMenuDesignButton(),
  ),
  "DesktopFilesButton": QuickAction(
    name: "DesktopFilesButton",
    icon: Icons.desktop_windows_outlined,
    widget: () => const DesktopFilesButton(),
  ),
  "WorkspacesButton": QuickAction(
    name: "WorkspacesButton",
    icon: Icons.dashboard_customize_outlined,
    widget: () => const WorkspacesButton(),
  ),
};
