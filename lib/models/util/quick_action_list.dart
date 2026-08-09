// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:flutter/material.dart';

import '../../widgets/itzy/quickmenu/button_adb.dart';
import '../../widgets/itzy/quickmenu/button_always_awake.dart';
import '../../widgets/itzy/quickmenu/button_app_audio.dart';
import '../../widgets/itzy/quickmenu/button_apps.dart';
import '../../widgets/itzy/quickmenu/button_audio.dart';
import '../../widgets/itzy/quickmenu/button_authenticator.dart';
import '../../widgets/itzy/quickmenu/button_bluetooth.dart';
import '../../widgets/itzy/quickmenu/button_bookmarks.dart';
import '../../widgets/itzy/quickmenu/button_brightness.dart';
import '../../widgets/itzy/quickmenu/button_calculator.dart';
import '../../widgets/itzy/quickmenu/button_change_theme.dart';
import '../../widgets/itzy/quickmenu/button_chars.dart';
import '../../widgets/itzy/quickmenu/button_block_keyboard.dart';
import '../../widgets/itzy/quickmenu/button_ai_usage.dart';
import '../../widgets/itzy/quickmenu/button_cli_book.dart';
import '../../widgets/itzy/quickmenu/button_clipboard_history.dart';
import '../../widgets/itzy/quickmenu/button_closeonfocus.dart';
import '../../widgets/itzy/quickmenu/button_color_picker.dart';
import '../../widgets/itzy/quickmenu/button_color_picker_instant.dart';
import '../../widgets/itzy/quickmenu/button_countdown.dart';
import '../../widgets/itzy/quickmenu/button_currency_converter.dart';
import '../../widgets/itzy/quickmenu/button_desktop_files.dart';
import '../../widgets/itzy/quickmenu/button_dev_toolbox.dart';
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
import '../../widgets/itzy/quickmenu/button_monitor_input.dart';
import '../../widgets/itzy/quickmenu/button_mouse_control.dart';
import '../../widgets/itzy/quickmenu/button_mouse_jiggler.dart';
import '../../widgets/itzy/quickmenu/button_music_player.dart';
import '../../widgets/itzy/quickmenu/button_notion.dart';
import '../../widgets/itzy/quickmenu/button_obsidian.dart';
import '../../widgets/itzy/quickmenu/button_ocr.dart';
import '../../widgets/itzy/quickmenu/button_pin_window.dart';
import '../../widgets/itzy/quickmenu/button_plugin_manager.dart';
import '../../widgets/itzy/quickmenu/button_qr_scanner.dart';
import '../../widgets/itzy/quickmenu/button_quickactions.dart';
import '../../widgets/itzy/quickmenu/button_quickmenu_settings.dart';
import '../../widgets/itzy/quickmenu/button_keystrokes.dart';
import '../../widgets/itzy/quickmenu/button_present_mode.dart';
import '../../widgets/itzy/quickmenu/button_quicksnap_standalone.dart';
import '../../widgets/itzy/quickmenu/button_screen_recorder.dart';
import '../../widgets/itzy/quickmenu/button_screen_ruler.dart';
import '../../widgets/itzy/quickmenu/button_screendraw.dart';
import '../../widgets/itzy/quickmenu/button_shutdown.dart';
import '../../widgets/itzy/quickmenu/button_spotify.dart';
import '../../widgets/itzy/quickmenu/button_spotlight.dart';
import '../../widgets/itzy/quickmenu/button_steam.dart';
import '../../widgets/itzy/quickmenu/button_subscription.dart';
import '../../widgets/itzy/quickmenu/button_task_manager.dart';
import '../../widgets/itzy/quickmenu/button_text_snippets.dart';
import '../../widgets/itzy/quickmenu/button_timers.dart';
import '../../widgets/itzy/quickmenu/button_timezone.dart';
import '../../widgets/itzy/quickmenu/button_toggle_desktop.dart';
import '../../widgets/itzy/quickmenu/button_toggle_hidden_files.dart';
import '../../widgets/itzy/quickmenu/button_toggle_taskbar.dart';
import '../../widgets/itzy/quickmenu/button_toggle_wallpaper_mode.dart';
import '../../widgets/itzy/quickmenu/button_translator.dart';
import '../../widgets/itzy/quickmenu/button_trktivity_today.dart';
import '../../widgets/itzy/quickmenu/button_universal_converter.dart';
import '../../widgets/itzy/quickmenu/button_vault.dart';
import '../../widgets/itzy/quickmenu/button_virtual_desktop.dart';
import '../../widgets/itzy/quickmenu/button_wallpapers.dart';
import '../../widgets/itzy/quickmenu/button_weather.dart';
import '../../widgets/itzy/quickmenu/button_window_layouts.dart';
import '../../widgets/itzy/quickmenu/button_workspaces.dart';
import '../../widgets/itzy/quickmenu/button_ytdlp.dart';
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
  "AudioButton": QuickAction(
    icon: Icons.volume_up,
    widget: () => const AudioButton(),
  ),
  "AdbButton": QuickAction(
    icon: Icons.android,
    widget: () => const AdbButton(),
  ),
  "AlwaysAwakeButton": QuickAction(
    icon: Icons.running_with_errors,
    widget: () => const AlwaysAwakeButton(),
  ),
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
  "AppsButton": QuickAction(
    icon: Icons.apps,
    widget: () => const AppsButton(),
  ),
  "AuthenticatorButton": QuickAction(
    icon: Icons.shield_outlined,
    widget: () => const AuthenticatorButton(),
  ),
  "BlockKeyboardButton": QuickAction(
    icon: Icons.keyboard_hide_rounded,
    widget: () => const BlockKeyboardButton(),
  ),
  "BluetoothButton": QuickAction(
    icon: Icons.bluetooth_rounded,
    widget: () => const BluetoothButton(),
  ),
  "BookmarksButton": QuickAction(
    icon: Icons.folder_copy_outlined,
    widget: () => const BookmarksButton(),
  ),
  "BrightnessButton": QuickAction(
    icon: Icons.brightness_6_rounded,
    widget: () => const BrightnessButton(),
  ),
  "CalculatorButton": QuickAction(
    icon: Icons.calculate_outlined,
    widget: () => const CalculatorButton(),
  ),
  "ChangeThemeButton": QuickAction(
    icon: Icons.theater_comedy_sharp,
    widget: () => const ChangeThemeButton(),
  ),
  "ClaudeUsageButton": QuickAction(
    name: "AI Usage Stats",
    icon: Icons.bar_chart_rounded,
    widget: () => const AiUsageButton(),
  ),
  "CliBookButton": QuickAction(
    icon: Icons.note_alt_outlined,
    widget: () => const CliBookButton(),
  ),
  "ClipboardHistoryButton": QuickAction(
    icon: Icons.content_paste_search_rounded,
    widget: () => const ClipboardHistoryButton(),
  ),
  "CloseOnFocusLossButton(Ctrl+H )": QuickAction(
    icon: Icons.visibility,
    widget: () => const CloseOnFocusLossButton(),
  ),
  "ColorPickerButton": QuickAction(
    icon: Icons.palette_outlined,
    widget: () => const ColorPickerButton(),
  ),
  "ColorPickerInstantButton": QuickAction(
    icon: Icons.colorize_outlined,
    widget: () => const ColorPickerInstantButton(),
  ),
  "CountdownButton": QuickAction(
    icon: Icons.hourglass_bottom_rounded,
    widget: () => const CountdownButton(),
  ),
  "CurrencyConverterButton": QuickAction(
    icon: Icons.currency_exchange_rounded,
    widget: () => const CurrencyConverterButton(),
  ),
  "CustomCharsButton": QuickAction(
    icon: Icons.format_quote,
    widget: () => const CustomCharsButton(),
  ),
  "DesktopFilesButton": QuickAction(
    icon: Icons.desktop_windows_outlined,
    widget: () => const DesktopFilesButton(),
  ),
  "DevToolboxButton": QuickAction(
    icon: Icons.terminal_rounded,
    widget: () => const DevToolboxButton(),
  ),
  "DiskCleanupButton": QuickAction(
    icon: Icons.cleaning_services_rounded,
    widget: () => const DiskCleanupButton(),
  ),
  "EditColorButton": QuickAction(
    icon: Icons.edit_rounded,
    widget: () => const EditColorButton(),
  ),
  "EmojiButton": QuickAction(
    icon: Icons.emoji_emotions_outlined,
    widget: () => const EmojiButton(),
  ),
  "FancyShotBrowserButton": QuickAction(
    icon: Icons.photo_album_outlined,
    widget: () => const FancyShotBrowserButton(),
  ),
  "FancyShotFreezeButton": QuickAction(
    icon: Icons.center_focus_strong,
    widget: () => const FancyShotButton(freeze: true),
  ),
  "FancyShotLiveButton": QuickAction(
    icon: Icons.center_focus_strong_outlined,
    widget: () => const FancyShotButton(),
  ),
  "FolderIconButton": QuickAction(
    icon: Icons.folder_special_rounded,
    widget: () => const FolderIconButton(),
  ),
  "HDRButton": QuickAction(
    icon: Icons.hdr_on_rounded,
    widget: () => const HDRButton(),
  ),
  "HideDesktopFilesButton": QuickAction(
    icon: Icons.hide_image,
    widget: () => const HideDesktopFilesButton(),
  ),
  "ImageConverterButton": QuickAction(
    icon: Icons.transform_rounded,
    widget: () => const ImageConverterButton(),
  ),
  "KeystrokesButton": QuickAction(
    icon: Icons.keyboard_alt_outlined,
    widget: () => const KeystrokesButton(),
  ),
  "LauncherButton": QuickAction(
    icon: Icons.search,
    widget: () => const LauncherButton(),
  ),
  "MediaControlButton": QuickAction(
    icon: Icons.play_arrow,
    widget: () => const MediaControlButton(),
  ),
  "MemosButton": QuickAction(
    icon: Icons.note_alt_outlined,
    widget: () => const MemosButton(),
  ),
  "MicMuteButton": QuickAction(
    icon: Icons.mic,
    widget: () => const MicMuteButton(),
  ),
  "MonitorInputButton": QuickAction(
    icon: Icons.settings_input_hdmi_rounded,
    widget: () => const MonitorInputButton(),
  ),
  "MouseControlButton": QuickAction(
    icon: Icons.gesture,
    widget: () => const MouseControlButton(),
  ),
  "MouseJigglerButton": QuickAction(
    icon: Icons.mouse_rounded,
    widget: () => const MouseJigglerButton(),
  ),
  "MusicServerButton": QuickAction(
    icon: Icons.library_music_outlined,
    widget: () => const MusicServerButton(),
  ),
  "NotionButton": QuickAction(
    icon: Icons.description_rounded,
    widget: () => const NotionButton(),
  ),
  "ObsidianButton": QuickAction(
    icon: Icons.menu_book_rounded,
    widget: () => const ObsidianButton(),
  ),
  "OcrButton": QuickAction(
    icon: Icons.text_snippet_outlined,
    widget: () => const OcrButton(),
  ),
  "PhotoEditorButton": QuickAction(
    icon: Icons.photo_camera_back_outlined,
    widget: () => const PhotoEditorButton(),
  ),
  "PinWindowButton": QuickAction(
    icon: Icons.pin_end,
    widget: () => const PinWindowButton(),
  ),
  "PresentModeButton": QuickAction(
    icon: Icons.co_present_outlined,
    widget: () => const PresentModeButton(),
  ),
  "QrScannerButton": QuickAction(
    icon: Icons.qr_code_scanner_rounded,
    widget: () => const QrScannerButton(),
  ),
  "QuickSnapStandalone": QuickAction(
    icon: Icons.view_quilt_rounded,
    widget: () => const QuickSnapStandalone(),
  ),
  // "RewindlyButton": QuickAction(
  //   icon: Icons.history_rounded,
  //   widget: () => const RewindlyButton(),
  // ),
  "ScreenDrawButton": QuickAction(
    icon: Icons.draw_outlined,
    widget: () => const ScreenDrawButton(),
  ),
  "ScreenRecordingButton": QuickAction(
    icon: Icons.camera,
    widget: () => const ScreenRecordingButton(),
  ),
  "ScreenRulerButton": QuickAction(
    icon: Icons.straighten_rounded,
    widget: () => const ScreenRulerButton(),
  ),
  "ShutDownButton": QuickAction(
    icon: Icons.power_settings_new_rounded,
    widget: () => const ShutDownButton(),
  ),
  "SpotifyButton": QuickAction(
    icon: Icons.music_note_rounded,
    widget: () => const SpotifyButton(),
  ),
  "SpotlightButton": QuickAction(
    icon: Icons.featured_video_rounded,
    widget: () => const SpotlightButton(),
  ),
  "SteamButton": QuickAction(
    icon: Icons.sports_esports_rounded,
    widget: () => const SteamButton(),
  ),
  "SubscriptionButton": QuickAction(
    icon: Icons.subscriptions_outlined,
    widget: () => const SubscriptionPanelButton(),
  ),
  "TaskManagerButton": QuickAction(
    icon: Icons.app_registration,
    widget: () => const TaskManagerButton(),
  ),
  "TextSnippetsButton": QuickAction(
    icon: Icons.short_text_rounded,
    widget: () => const TextSnippetsButton(),
  ),
  "TimersButton": QuickAction(
    icon: Icons.timer_sharp,
    widget: () => const TimersButton(),
  ),
  "TimeZoneButton": QuickAction(
    icon: Icons.public_rounded,
    widget: () => const TimeZoneButton(),
  ),
  "ToggleDesktopButton": QuickAction(
    icon: Icons.desktop_windows_rounded,
    widget: () => const ToggleDesktopButton(),
  ),
  "ToggleHiddenFilesButton": QuickAction(
    icon: Icons.folder_off,
    widget: () => const ToggleHiddenFilesButton(),
  ),
  "ToggleTaskbarButton": QuickAction(
    icon: Icons.call_to_action_outlined,
    widget: () => const ToggleTaskbarButton(),
  ),
  "ToggleWallpaperModeButton": QuickAction(
    icon: Icons.wallpaper_rounded,
    widget: () => const ToggleWallpaperModeButton(),
  ),
  "ToggleWindowsThemeButton": QuickAction(
    icon: Icons.desktop_windows_rounded,
    widget: () => const ToggleWindowsThemeButton(),
  ),
  "TranslatorButton": QuickAction(
    icon: Icons.translate_rounded,
    widget: () => const TranslatorButton(),
  ),
  "TrktivityTodayButton": QuickAction(
    icon: Icons.insights_outlined,
    widget: () => const TrktivityTodayButton(),
  ),
  "UniversalConverterButton": QuickAction(
    icon: Icons.straighten_rounded,
    widget: () => const UniversalConverterButton(),
  ),
  "VaultButton": QuickAction(
    icon: Icons.lock_rounded,
    widget: () => const VaultsButton(),
  ),
  "VirtualDesktopButton": QuickAction(
    icon: Icons.display_settings_outlined,
    widget: () => const VirtualDesktopButton(),
  ),
  "WallpapersButton": QuickAction(
    icon: Icons.photo_library_outlined,
    widget: () => const WallpapersButton(),
  ),
  "WeatherButton": QuickAction(
    icon: Icons.wb_cloudy_rounded,
    widget: () => const WeatherButton(),
  ),
  "WindowLayoutsButton": QuickAction(
    icon: Icons.view_quilt_outlined,
    widget: () => const WindowLayoutsButton(),
  ),
  "WorkspacesButton": QuickAction(
    icon: Icons.dashboard_customize_outlined,
    widget: () => const WorkspacesButton(),
  ),
  "YtDlpButton": QuickAction(
    icon: Icons.download_for_offline_outlined,
    widget: () => const YtDlpButton(),
  ),
  "PluginManagerButton": QuickAction(
    icon: Icons.extension_outlined,
    widget: () => const PluginManagerButton(),
  ),
  "QuickActionsMenuButton": QuickAction(
    icon: Icons.grid_view,
    widget: () => const QuickActionsMenuButton(),
  ),
  "QuickMenuDesignButton": QuickAction(
    icon: Icons.palette_rounded,
    widget: () => const QuickMenuDesignButton(),
  ),
  "QuickMenuSettingsButton": QuickAction(
    icon: Icons.tune_rounded,
    widget: () => const QuickMenuSettingsButton(),
  ),
};
