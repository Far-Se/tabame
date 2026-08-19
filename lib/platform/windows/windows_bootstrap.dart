import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../app_catalog_service.dart';
import '../audio_system_service.dart';
import '../clipboard_service.dart';
import '../file_picker_service.dart';
import '../hotkey_action_service.dart';
import '../hotkey_service.dart';
import '../input_service.dart';
import '../monitor_service.dart';
import '../notification_service.dart';
import '../platform_capabilities.dart';
import '../quick_snap_service.dart';
import '../screen_capture_service.dart';
import '../window_service.dart';
import 'win32_api.dart' as win32;
import 'windows_app_catalog_provider.dart';
import 'windows_audio_service.dart';
import 'windows_clipboard_service.dart';
import 'windows_file_picker_service.dart';
import 'windows_hotkey_action_service.dart';
import 'windows_hotkey_service.dart';
import 'windows_input_service.dart';
import 'windows_monitor_service.dart';
import 'windows_native_window_bridge.dart';
import 'windows_notification_service.dart';
import 'windows_quick_snap_service.dart';
import 'windows_ocr_service.dart';
import 'windows_screen_capture_service.dart';
import 'windows_window_service.dart';

/// Windows-only startup and packaging bridge.
///
/// This is deliberately small. It owns only initialization that must happen
/// before the shared application graph starts; native feature behavior remains
/// in the existing Windows implementation.
class WindowsBootstrap {
  WindowsBootstrap._();

  static bool _initialized = false;

  static void initialize() {
    if (_initialized || !Platform.isWindows) return;
    _initialized = true;

    FilePickerService.register(const WindowsFilePickerService());
    ClipboardService.register(WindowsClipboardService());
    ScreenCaptureService.register(WindowsScreenCaptureService());
    OcrService.register(WindowsOcrService());
    AppCatalogService.register(PortableAppCatalogService(WindowsAppCatalogProvider()));
    WindowService.register(WindowsWindowService(bridge: const WindowsNativeWindowBridge()));
    MonitorService.register(WindowsMonitorService());
    QuickSnapService.register(WindowsQuickSnapService());
    HotkeyService.register(WindowsHotkeyService());
    InputService.register(const WindowsInputService());
    NotificationService.register(WindowsNotificationService());
    HotkeyActionService.register(const WindowsHotkeyActionService());
    WindowsHotkeyActionService.registerCallbacks();
    AudioSystemService.register(WindowsAudioService.instance);
    MediaSessionService.register(WindowsMediaSessionService.instance);
    unawaited(
      Future.wait(<Future<bool>>[
        AudioSystemService.instance.initialize(),
        MediaSessionService.instance.initialize(),
      ]).then((List<bool> _) => refreshCapabilities()),
    );
    refreshCapabilities();
    win32.SetProcessDpiAwarenessContext(win32.DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    prepareSqliteRuntime();
  }

  static PlatformCapabilities refreshCapabilities() {
    final ClipboardService clipboard = ClipboardService.instance;
    final ScreenCaptureService capture = ScreenCaptureService.instance;
    final OcrService ocr = OcrService.instance;
    final PlatformCapabilities capabilities = PlatformCapabilities.current.copyWith(
      windowEnumeration: true,
      windowActivation: true,
      monitorGeometry: MonitorService.instance.isAvailable,
      quickSnap: QuickSnapService.instance.isAvailable,
      quickSnapDrag: QuickSnapService.instance.supportsDragTriggers,
      globalHotkeys: HotkeyService.instance.isAvailable,
      inputInjection: InputService.instance.isAvailable,
      clipboardMonitoring: clipboard.isMonitoringAvailable,
      richClipboard: clipboard.supportsRichText || clipboard.supportsImages,
      screenCapture: capture.isAvailable,
      ocr: capture.isAvailable && ocr.isAvailable,
      audioDeviceControl: AudioSystemService.instance.isAvailable,
      perProcessAudio: AudioSystemService.instance.supportsPerProcessAudio,
      mediaSessions: MediaSessionService.instance.isAvailable,
      systemNotifications: NotificationService.instance.isAvailable,
    );
    PlatformCapabilities.register(capabilities);
    return capabilities;
  }

  /// Places the development-layout SQLite DLL beside the executable.
  ///
  /// Release packaging performs the same placement in CI. Keeping this
  /// fallback here preserves local Windows builds without making shared
  /// database services know about Windows packaging paths.
  static void prepareSqliteRuntime() {
    if (!Platform.isWindows) return;

    final String executableDirectory = p.dirname(Platform.resolvedExecutable);
    final String sqlitePath = p.join(executableDirectory, 'sqlite3.dll');
    if (File(sqlitePath).existsSync()) return;

    final String developmentPath = p.join(executableDirectory, 'windows', 'sqlite3.dll');
    final File developmentFile = File(developmentPath);
    if (!developmentFile.existsSync()) return;

    try {
      developmentFile.renameSync(sqlitePath);
    } catch (_) {
      // Packaging or another process may already have moved the DLL. The
      // database layer reports a native loading failure if it is still absent.
    }
  }
}
