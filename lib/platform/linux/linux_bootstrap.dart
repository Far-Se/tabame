import 'dart:async';
import 'dart:io';

import '../app_catalog_service.dart';
import '../audio_system_service.dart';
import '../clipboard_service.dart';
import '../hotkey_service.dart';
import '../input_service.dart';
import '../monitor_service.dart';
import '../notification_service.dart';
import '../platform_capabilities.dart';
import '../platform_models.dart';
import '../screen_capture_service.dart';
import '../secret_store_registry.dart';
import '../window_service.dart';
import '../linux_app_catalog_provider.dart';

import 'linux_audio_service.dart';
import 'linux_clipboard_service.dart';
import 'linux_file_watcher.dart';
import 'linux_hotkey_service.dart';
import 'linux_monitor_service.dart';
import 'linux_notification_service.dart';
import 'linux_platform_channel.dart';
import 'linux_secret_store.dart';
import 'linux_window_service.dart';

/// Registers Linux services and keeps X11-only capabilities explicit.
class LinuxBootstrap {
  LinuxBootstrap._();

  static bool _initialized = false;
  static bool _summonRegistered = false;
  static bool _clipboardStarted = false;
  static HotkeyRegistrationResult? _summonResult;
  static StreamSubscription<PlatformHotkeyEvent>? _summonSubscription;
  static final StreamController<LinuxCapabilitySnapshot> _capabilityChanges =
      StreamController<LinuxCapabilitySnapshot>.broadcast();
  static LinuxCapabilitySnapshot _capabilitySnapshot = const LinuxCapabilitySnapshot.unknown();

  static LinuxPlatformChannel get channel => LinuxPlatformChannel.instance;
  static LinuxCapabilitySnapshot get capabilitySnapshot => _capabilitySnapshot;

  static Future<void> initialize() async {
    if (!Platform.isLinux) return;
    if (_initialized) return;
    _initialized = true;

    AppCatalogService.register(
      PortableAppCatalogService(LinuxAppCatalogProvider()),
    );
    WindowService.register(LinuxWindowService(channel: channel));
    MonitorService.register(LinuxMonitorService(channel: channel));
    HotkeyService.register(LinuxHotkeyService(channel: channel));
    InputService.register(const UnavailableInputService(
      reason:
          'Linux low-level keyboard/mouse observation and injection are deferred; use the visible Tabame window instead.',
    ));
    ClipboardService.register(LinuxClipboardService(channel: channel));
    ScreenCaptureService.register(const UnavailableScreenCaptureService(
      reason: 'Linux screen capture and OCR are deferred; portal/PipeWire presence does not enable capture.',
    ));
    OcrService.register(const UnavailableOcrService(
      reason: 'Linux OCR is deferred; no X11 or Wayland OCR backend is enabled.',
    ));
    NotificationService.register(LinuxNotificationService(channel: channel));
    AudioSystemService.register(LinuxAudioService.instance);
    MediaSessionService.register(LinuxMediaSessionService.instance);

    final LinuxSecretStore secretStore = LinuxSecretStore.instance;
    SecretStores.register(secretStore);
    // Secret Service and capability probing are intentionally deferred until
    // after the portable shell is visible. Their native D-Bus calls are
    // synchronous, so scheduling them here could still delay the first frame.
  }

  /// Initializes the optional machine-bound key after the shell is running.
  /// Failure leaves password-based encryption and explicit re-entry available.
  static Future<void> initializeOptionalServices() async {
    if (!Platform.isLinux) return;
    await initialize();
    // Give GTK/Flutter a chance to present the first frame before optional
    // D-Bus probes run on the native platform thread.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await refreshCapabilities();
    await AudioSystemService.instance.initialize();
    await MediaSessionService.instance.initialize();
    try {
      await LinuxSecretStore.instance.initialize();
    } catch (_) {}
    await refreshCapabilities();
  }

  /// Starts text clipboard polling and a conservative X11 summon shortcut.
  /// Wayland returns an explicit unavailable result and retains the visible
  /// window as the fallback summon action.
  static Future<HotkeyRegistrationResult?> startCoreServices({
    required Future<void> Function() onSummon,
  }) async {
    if (!Platform.isLinux) return null;
    await initialize();

    try {
      _clipboardStarted = await ClipboardService.instance.start();
    } catch (_) {
      _clipboardStarted = false;
    }

    await _summonSubscription?.cancel();
    _summonSubscription = HotkeyService.instance.events.listen(
      (PlatformHotkeyEvent event) {
        if (event.name == 'summon') unawaited(onSummon());
      },
      onError: (_) {},
    );

    HotkeyRegistrationResult result;
    try {
      result = await HotkeyService.instance.registerGlobal(
        key: 'SPACE',
        modifiers: const <String>['CTRL', 'ALT'],
        name: 'summon',
      );
      _summonRegistered = result.registered;
    } catch (error) {
      _summonRegistered = false;
      result = HotkeyRegistrationResult(
        registered: false,
        permissionRequired: true,
        reason: '$error',
      );
    }
    _summonResult = result;
    // Capability probing is started by initializeOptionalServices after the
    // shell is visible. Do not hold the first frame on the session bus.
    return result;
  }

  static Future<void> stopCoreServices() async {
    if (!Platform.isLinux) return;
    await _summonSubscription?.cancel();
    _summonSubscription = null;
    try {
      await HotkeyService.instance.unregisterGlobal();
    } catch (_) {}
    try {
      await ClipboardService.instance.stop();
    } catch (_) {}
    _clipboardStarted = false;
    _summonRegistered = false;
    _summonResult = null;
    await refreshCapabilities();
  }

  static Future<PlatformCapabilities> refreshCapabilities() async {
    if (!Platform.isLinux) return PlatformCapabilities.current;
    try {
      _capabilitySnapshot = await channel.refreshCapabilities();
    } catch (_) {
      _capabilitySnapshot = const LinuxCapabilitySnapshot.unknown();
    }
    final PlatformCapabilities capabilities = PlatformCapabilities(
      globalHotkeys: _summonRegistered && _capabilitySnapshot.globalHotkeys,
      windowEnumeration: _capabilitySnapshot.windowEnumeration,
      windowActivation: _capabilitySnapshot.windowActivation,
      inputInjection: false,
      clipboardMonitoring: _clipboardStarted && _capabilitySnapshot.clipboardMonitoring,
      richClipboard: false,
      screenCapture: false,
      ocr: false,
      screenRecording: false,
      systemNotifications: _capabilitySnapshot.notifications,
      audioDeviceControl: AudioSystemService.instance.isAvailable,
      perProcessAudio: AudioSystemService.instance.supportsPerProcessAudio,
      mediaSessions: MediaSessionService.instance.isAvailable,
      secureMachineStorage: SecretStores.instance.isAvailable,
      monitorGeometry: _capabilitySnapshot.monitorGeometry,
      filesystemWatching: LinuxFileWatcher().isAvailable && _capabilitySnapshot.filesystemWatching,
      desktopFileDiscovery: AppCatalogService.instance.isAvailable && _capabilitySnapshot.desktopFileDiscovery,
      x11: _capabilitySnapshot.x11,
      wayland: _capabilitySnapshot.wayland,
    );
    PlatformCapabilities.register(capabilities);
    if (!_capabilityChanges.isClosed) _capabilityChanges.add(_capabilitySnapshot);
    return capabilities;
  }

  static bool get sessionLooksWayland => sessionLooksWaylandFromEnvironment(Platform.environment);

  /// Mirrors the native authority rule: an explicit non-empty session type wins;
  /// otherwise a live Wayland socket is treated as a Wayland boundary.
  static bool sessionLooksWaylandFromEnvironment(Map<String, String> environment) {
    final String session = (environment['XDG_SESSION_TYPE'] ?? '').trim().toLowerCase();
    if (session.isNotEmpty) return session == 'wayland';
    return (environment['WAYLAND_DISPLAY'] ?? '').trim().isNotEmpty;
  }

  static Stream<LinuxCapabilitySnapshot> get capabilityChanges => _capabilityChanges.stream;
  static bool get summonRegistered => _summonRegistered;
  static HotkeyRegistrationResult? get summonResult => _summonResult;
}
