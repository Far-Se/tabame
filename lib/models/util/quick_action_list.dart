// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:flutter/material.dart';

import '../../widgets/itzy/quickmenu/button_adb.dart';
import '../../widgets/itzy/quickmenu/button_always_awake.dart';
import '../../widgets/itzy/quickmenu/button_app_audio.dart';
import '../../widgets/itzy/quickmenu/button_apps.dart';
import '../../widgets/itzy/quickmenu/button_audio.dart';
import '../../widgets/itzy/quickmenu/button_authenticator.dart';
import '../../widgets/itzy/quickmenu/button_bookmarks.dart';
import '../../widgets/itzy/quickmenu/button_calculator.dart';
import '../../widgets/itzy/quickmenu/button_change_theme.dart';
import '../../widgets/itzy/quickmenu/button_chars.dart';
import '../../widgets/itzy/quickmenu/button_block_keyboard.dart';
import '../../widgets/itzy/quickmenu/button_claude_usage.dart';
import '../../widgets/itzy/quickmenu/button_cli_book.dart';
import '../../widgets/itzy/quickmenu/button_clipboard_history.dart';
import '../../widgets/itzy/quickmenu/button_closeonfocus.dart';
import '../../widgets/itzy/quickmenu/button_color_picker.dart';
import '../../widgets/itzy/quickmenu/button_color_picker_instant.dart';
import '../../widgets/itzy/quickmenu/button_countdown.dart';
import '../../widgets/itzy/quickmenu/button_currency_converter.dart';
import '../../widgets/itzy/quickmenu/button_desktop_files.dart';
import '../../widgets/itzy/quickmenu/button_disk_cleanup.dart';
import '../../widgets/itzy/quickmenu/button_edit_color.dart';
import '../../widgets/itzy/quickmenu/button_emoji.dart';
import '../../widgets/itzy/quickmenu/button_fancyshot.dart';
import '../../widgets/itzy/quickmenu/button_fancyshot_browser.dart';
import '../../widgets/itzy/quickmenu/button_folder_icon.dart';
import '../../widgets/itzy/quickmenu/button_hdr.dart';
import '../../widgets/itzy/quickmenu/button_hide_desktop_files.dart';
// import '../../widgets/itzy/quickmenu/button_image_modifier.dart';
import '../../widgets/itzy/quickmenu/button_image_modifier.dart';
import '../../widgets/itzy/quickmenu/button_launcher.dart';
import '../../widgets/itzy/quickmenu/button_media_control.dart';
import '../../widgets/itzy/quickmenu/button_memo.dart';
import '../../widgets/itzy/quickmenu/button_menu_design.dart';
import '../../widgets/itzy/quickmenu/button_mic_mute.dart';
import '../../widgets/itzy/quickmenu/button_music_player.dart';
import '../../widgets/itzy/quickmenu/button_notion.dart';
import '../../widgets/itzy/quickmenu/button_obsidian.dart';
import '../../widgets/itzy/quickmenu/button_ocr.dart';
import '../../widgets/itzy/quickmenu/button_pin_window.dart';
import '../../widgets/itzy/quickmenu/button_qr_scanner.dart';
import '../../widgets/itzy/quickmenu/button_quickactions.dart';
import '../../widgets/itzy/quickmenu/button_quickmenu_settings.dart';
import '../../widgets/itzy/quickmenu/button_screen_recorder.dart';
import '../../widgets/itzy/quickmenu/button_screendraw.dart';
import '../../widgets/itzy/quickmenu/button_shutdown.dart';
import '../../widgets/itzy/quickmenu/button_spotlight.dart';
import '../../widgets/itzy/quickmenu/button_steam.dart';
import '../../widgets/itzy/quickmenu/button_subscription.dart';
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
  String? name;
  IconData icon;
  Widget Function() widget;
  VoidCallback? onExecute;

  QuickAction({
    this.name,
    required this.icon,
    required this.widget,
    this.onExecute,
  });
}

final Map<String, QuickAction> quickActionsMap = <String, QuickAction>{
  "LauncherButton": QuickAction(
    icon: Icons.search,
    widget: () => const LauncherButton(),
  ),
  "AudioButton": QuickAction(
    icon: Icons.volume_up,
    widget: () => const AudioButton(),
  ),
  "MediaControlButton": QuickAction(
    icon: Icons.play_arrow,
    widget: () => const MediaControlButton(),
  ),
  "TimersButton": QuickAction(
    icon: Icons.timer_sharp,
    widget: () => const TimersButton(),
  ),
  "BookmarksButton": QuickAction(
    icon: Icons.folder_copy_outlined,
    widget: () => const BookmarksButton(),
  ),
  "CliBookButton": QuickAction(
    icon: Icons.note_alt_outlined,
    widget: () => const CliBookButton(),
  ),
  "SubscriptionButton": QuickAction(
    icon: Icons.subscriptions_outlined,
    widget: () => const SubscriptionPanelButton(),
  ),
  "ClaudeUsageButton": QuickAction(
    icon: Icons.bar_chart_rounded,
    widget: () => const ClaudeUsageButton(),
  ),
  "EmojiButton": QuickAction(
    icon: Icons.emoji_emotions_outlined,
    widget: () => const EmojiButton(),
  ),
  "ClipboardHistoryButton": QuickAction(
    icon: Icons.content_paste_search_rounded,
    widget: () => const ClipboardHistoryButton(),
  ),
  "BlockKeyboardButton": QuickAction(
    icon: Icons.keyboard_hide_rounded,
    widget: () => const BlockKeyboardButton(),
  ),
  "VaultButton": QuickAction(
    icon: Icons.lock_rounded,
    widget: () => const VaultsButton(),
  ),
  "TaskManagerButton": QuickAction(
    icon: Icons.app_registration,
    widget: () => const TaskManagerButton(),
  ),
  "AppsButton": QuickAction(
    icon: Icons.apps,
    widget: () => const AppsButton(),
  ),
  "MusicServerButton": QuickAction(
    icon: Icons.library_music_outlined,
    widget: () => const MusicServerButton(),
  ),
  "VirtualDesktopButton": QuickAction(
    icon: Icons.display_settings_outlined,
    widget: () => const VirtualDesktopButton(),
  ),
  "ToggleTaskbarButton": QuickAction(
    icon: Icons.call_to_action_outlined,
    widget: () => const ToggleTaskbarButton(),
  ),
  "ToggleWallpaperModeButton": QuickAction(
    icon: Icons.wallpaper_rounded,
    widget: () => const ToggleWallpaperModeButton(),
  ),
  //! Audio Control
  "AppAudioControl1": QuickAction(
    icon: Icons.music_video_outlined,
    widget: () => const AppAudioButton(index: 0),
  ),
  "AppAudioControl2": QuickAction(
    icon: Icons.music_video_outlined,
    widget: () => const AppAudioButton(index: 1),
  ),
  "AppAudioControl3": QuickAction(
    icon: Icons.music_video_outlined,
    widget: () => const AppAudioButton(index: 2),
  ),
  "AppAudioControl4": QuickAction(
    icon: Icons.music_video_outlined,
    widget: () => const AppAudioButton(index: 3),
  ),
  "AppAudioControl5": QuickAction(
    icon: Icons.music_video_outlined,
    widget: () => const AppAudioButton(index: 4),
  ),
  //! Rest
  "MemosButton": QuickAction(
    icon: Icons.note_alt_outlined,
    widget: () => const MemosButton(),
  ),
  "NotionButton": QuickAction(
    icon: Icons.description_rounded,
    widget: () => const NotionButton(),
  ),
  "ObsidianButton": QuickAction(
    icon: Icons.menu_book_rounded,
    widget: () => const ObsidianButton(),
  ),
  "WallpapersButton": QuickAction(
    icon: Icons.photo_library_outlined,
    widget: () => const WallpapersButton(),
  ),
  "FolderIconButton": QuickAction(
    icon: Icons.folder_special_rounded,
    widget: () => const FolderIconButton(),
  ),
  "CalculatorButton": QuickAction(
    icon: Icons.calculate_outlined,
    widget: () => const CalculatorButton(),
  ),
  "TimeZoneButton": QuickAction(
    icon: Icons.public_rounded,
    widget: () => const TimeZoneButton(),
  ),
  "CurrencyConverterButton": QuickAction(
    icon: Icons.currency_exchange_rounded,
    widget: () => const CurrencyConverterButton(),
  ),
  "DiskCleanupButton": QuickAction(
    icon: Icons.cleaning_services_rounded,
    widget: () => const DiskCleanupButton(),
  ),
  "TranslatorButton": QuickAction(
    icon: Icons.translate_rounded,
    widget: () => const TranslatorButton(),
  ),
  "WeatherButton": QuickAction(
    icon: Icons.wb_cloudy_rounded,
    widget: () => const WeatherButton(),
  ),
  "AuthenticatorButton": QuickAction(
    icon: Icons.shield_outlined,
    widget: () => const AuthenticatorButton(),
  ),
  "QrScannerButton": QuickAction(
    icon: Icons.qr_code_scanner_rounded,
    widget: () => const QrScannerButton(),
  ),
  "OcrButton": QuickAction(
    icon: Icons.text_snippet_outlined,
    widget: () => const OcrButton(),
  ),
  "ColorPickerButton": QuickAction(
    icon: Icons.palette_outlined,
    widget: () => const ColorPickerButton(),
  ),
  "ColorPickerInstantButton": QuickAction(
    icon: Icons.colorize_outlined,
    widget: () => const ColorPickerInstantButton(),
  ),
  "EditColorButton": QuickAction(
    icon: Icons.edit_rounded,
    widget: () => const EditColorButton(),
  ),
  "ScreenDrawButton": QuickAction(
    icon: Icons.draw_outlined,
    widget: () => const ScreenDrawButton(),
  ),
  "ScreenRecordingButton": QuickAction(
    icon: Icons.camera,
    widget: () => const ScreenRecordingButton(),
  ),
  "SpotlightButton": QuickAction(
    icon: Icons.featured_video_rounded,
    widget: () => const SpotlightButton(),
  ),
  "FancyShotLiveButton": QuickAction(
    icon: Icons.center_focus_strong_outlined,
    widget: () => const FancyShotButton(),
  ),
  "FancyShotFreezeButton": QuickAction(
    icon: Icons.center_focus_strong,
    widget: () => const FancyShotButton(freeze: true),
  ),
  "PhotoEditorButton": QuickAction(
    icon: Icons.photo_camera_back_outlined,
    widget: () => const PhotoEditorButton(),
  ),
  "FancyShotBrowserButton": QuickAction(
    icon: Icons.photo_album_outlined,
    widget: () => const FancyShotBrowserButton(),
  ),
  "ImageConverterButton": QuickAction(
    icon: Icons.transform_rounded,
    widget: () => const ImageConverterButton(),
  ),

  "PinWindowButton": QuickAction(
    icon: Icons.pin_end,
    widget: () => const PinWindowButton(),
  ),
  "MicMuteButton": QuickAction(
    icon: Icons.mic,
    widget: () => const MicMuteButton(),
  ),
  "AlwaysAwakeButton": QuickAction(
    icon: Icons.running_with_errors,
    widget: () => const AlwaysAwakeButton(),
  ),
  "HideDesktopFilesButton": QuickAction(
    icon: Icons.hide_image,
    widget: () => const HideDesktopFilesButton(),
  ),
  "ToggleHiddenFilesButton": QuickAction(
    icon: Icons.folder_off,
    widget: () => const ToggleHiddenFilesButton(),
  ),
  "ToggleDesktopButton": QuickAction(
    icon: Icons.desktop_windows_rounded,
    widget: () => const ToggleDesktopButton(),
  ),
  "ToggleWindowsThemeButton": QuickAction(
    icon: Icons.desktop_windows_rounded,
    widget: () => const ToggleWindowsThemeButton(),
  ),
  "CountdownButton": QuickAction(
    icon: Icons.hourglass_bottom_rounded,
    widget: () => const CountdownButton(),
  ),
  "CustomCharsButton": QuickAction(
    icon: Icons.format_quote,
    widget: () => const CustomCharsButton(),
  ),
  "ShutDownButton": QuickAction(
    icon: Icons.power_settings_new_rounded,
    widget: () => const ShutDownButton(),
  ),
  "CloseOnFocusLossButton(Ctrl+H )": QuickAction(
    icon: Icons.visibility,
    widget: () => const CloseOnFocusLossButton(),
  ),
  "ChangeThemeButton": QuickAction(
    icon: Icons.theater_comedy_sharp,
    widget: () => const ChangeThemeButton(),
  ),
  "DesktopFilesButton": QuickAction(
    icon: Icons.desktop_windows_outlined,
    widget: () => const DesktopFilesButton(),
  ),
  "WorkspacesButton": QuickAction(
    icon: Icons.dashboard_customize_outlined,
    widget: () => const WorkspacesButton(),
  ),
  "QuickMenuDesignButton": QuickAction(
    icon: Icons.palette_rounded,
    widget: () => const QuickMenuDesignButton(),
  ),
  "QuickActionsMenuButton": QuickAction(
    icon: Icons.grid_view,
    widget: () => const QuickActionsMenuButton(),
  ),
  "QuickMenuSettingsButton": QuickAction(
    icon: Icons.tune_rounded,
    widget: () => const QuickMenuSettingsButton(),
  ),
  "AdbButton": QuickAction(
    icon: Icons.android,
    widget: () => const AdbButton(),
  ),
  "SteamButton": QuickAction(
    icon: Icons.sports_esports_rounded,
    widget: () => const SteamButton(),
  ),
  "HDRButton": QuickAction(
    icon: Icons.hdr_on_rounded,
    widget: () => const HDRButton(),
  ),
};
