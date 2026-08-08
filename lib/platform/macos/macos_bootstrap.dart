import 'dart:async';
import 'dart:io';

import '../../models/classes/hotkeys.dart';
import '../../models/util/hotkey_handler.dart';
import '../app_catalog_service.dart';
import '../audio_system_service.dart';
import '../clipboard_service.dart';
import '../hotkey_action_service.dart';
import '../hotkey_coordinator.dart';
import '../hotkey_service.dart';
import '../input_service.dart';
import '../monitor_service.dart';
import '../notification_service.dart';
import '../platform_capabilities.dart';
import '../platform_models.dart';
import '../quick_snap_service.dart';
import '../screen_capture_service.dart';
import '../secret_store_registry.dart';
import '../window_service.dart';
import '../macos_app_catalog_provider.dart';
import 'macos_clipboard_service.dart';
import 'macos_hotkey_service.dart';
import 'macos_input_service.dart';
import 'macos_monitor_service.dart';
import 'macos_notification_service.dart';
import 'macos_permission_service.dart';
import 'macos_platform_channel.dart';
import 'macos_quick_snap_service.dart';
import 'macos_secret_store.dart';
import 'macos_window_service.dart';
import '../portable_hotkey_action_service.dart';
import '../portable_hotkey_configuration.dart';

/// Registers all Phase 5 services without making macOS permissions a startup
/// requirement. Every native call has a reduced-mode fallback in its adapter.
class MacOSBootstrap {
  MacOSBootstrap._();

  static bool _initialized = false;
  static bool _summonRegistered = false;
  static bool _clipboardStarted = false;
  static StreamSubscription<PlatformHotkeyEvent>? _summonSubscription;
  static HotkeyCoordinator? _configuredHotkeyCoordinator;
  static List<Hotkeys> _configuredHotkeys = const <Hotkeys>[];
  static final StreamController<PlatformCapabilities> _capabilityChanges =
      StreamController<PlatformCapabilities>.broadcast();

  static MacOSPlatformChannel get channel => MacOSPlatformChannel.instance;

  static Future<void> initialize() async {
    if (!Platform.isMacOS) return;
    if (_initialized) return;
    _initialized = true;

    AppCatalogService.register(
      PortableAppCatalogService(
        MacOSAppCatalogProvider(platform: channel),
      ),
    );
    WindowService.register(MacOSWindowService(channel: channel));
    MonitorService.register(MacOSMonitorService(channel: channel));
    QuickSnapService.register(MacOSQuickSnapService(channel: channel));
    HotkeyService.register(MacOSHotkeyService(channel: channel));
    InputService.register(const MacOSInputService());
    ClipboardService.register(MacOSClipboardService(channel: channel));
    ScreenCaptureService.register(const UnavailableScreenCaptureService(
      reason: 'macOS screen capture and OCR are deferred; Screen Recording permission alone does not enable them.',
    ));
    OcrService.register(const UnavailableOcrService(
      reason: 'macOS OCR is deferred in the current capture/OCR migration.',
    ));
    NotificationService.register(MacOSNotificationService(channel: channel));
    AudioSystemService.register(const UnavailableAudioSystemService());
    MediaSessionService.register(const UnavailableMediaSessionService());

    final MacOSSecretStore secretStore = MacOSSecretStore.instance;
    SecretStores.register(secretStore);
    // A Keychain failure only disables machine-bound secrets. It must never
    // prevent the launcher shell from starting.
    try {
      await secretStore.initialize();
    } catch (_) {}

    await refreshCapabilities();
  }

  /// Starts text clipboard polling and a conservative default summon shortcut.
  /// The visible app window remains the fallback when registration is denied or
  /// another application already owns the shortcut.
  static Future<HotkeyRegistrationResult?> startCoreServices({
    required Future<void> Function() onSummon,
    Future<void> Function(String action)? onConfiguredAction,
  }) async {
    if (!Platform.isMacOS) return null;
    await initialize();

    try {
      _clipboardStarted = await ClipboardService.instance.start();
    } catch (_) {
      _clipboardStarted = false;
    }

    await _summonSubscription?.cancel();
    _summonSubscription = HotkeyService.instance.events.listen((PlatformHotkeyEvent event) {
      if (event.name == 'summon' && event.hotkey == 'CTRL+ALT+SPACE') unawaited(onSummon());
    }, onError: (_) {});

    _configuredHotkeys = PortableHotkeyConfiguration.supportedMacOS(
      await PortableHotkeyConfiguration.load(),
    );
    HotkeyActionService.register(
      PortableHotkeyActionService(
        onAction: onConfiguredAction ?? (_) => onSummon(),
      ),
    );
    await _configuredHotkeyCoordinator?.stop();
    _configuredHotkeyCoordinator = null;
    if (_configuredHotkeys.isNotEmpty) {
      final HotkeyHandler handler = HotkeyHandler(
        hotkeys: () => _configuredHotkeys,
        enabled: () => true,
      );
      final HotkeyCoordinator coordinator = HotkeyCoordinator(onEvent: handler.handle);
      _configuredHotkeyCoordinator = coordinator;
      await coordinator.start();
    }

    final List<PlatformHotkeyBinding> bindings = <PlatformHotkeyBinding>[
      const PlatformHotkeyBinding(
        name: 'summon',
        key: 'SPACE',
        modifiers: <String>['CTRL', 'ALT'],
        hotkey: 'CTRL+ALT+SPACE',
      ),
    ];
    final Set<String> registeredHotkeys = <String>{'CTRL+ALT+SPACE'};
    for (final PlatformHotkeyBinding binding in PortableHotkeyConfiguration.macOSBindings(_configuredHotkeys)) {
      final String hotkey = binding.hotkey.toUpperCase();
      if (hotkey.isEmpty || !registeredHotkeys.add(hotkey)) continue;
      bindings.add(binding);
    }

    HotkeyRegistrationResult result;
    try {
      result = await HotkeyService.instance.registerBindings(bindings);
      _summonRegistered = result.registered;
    } catch (error) {
      _summonRegistered = false;
      result = HotkeyRegistrationResult(
        registered: false,
        permissionRequired: true,
        reason: '$error',
      );
    }
    await refreshCapabilities();
    return result;
  }

  static Future<void> stopCoreServices() async {
    if (!Platform.isMacOS) return;
    await _summonSubscription?.cancel();
    _summonSubscription = null;
    await _configuredHotkeyCoordinator?.stop();
    _configuredHotkeyCoordinator = null;
    _configuredHotkeys = const <Hotkeys>[];
    HotkeyActionService.register(const UnavailableHotkeyActionService());
    await HotkeyService.instance.unregisterGlobal();
    await ClipboardService.instance.stop();
    _clipboardStarted = false;
    _summonRegistered = false;
    await refreshCapabilities();
  }

  static Future<PlatformCapabilities> refreshCapabilities() async {
    if (!Platform.isMacOS) return PlatformCapabilities.current;
    final MacOSPermissionSnapshot snapshot = await MacOSPermissionService.instance.refresh();
    final bool accessibility = snapshot.stateFor(MacOSPermission.accessibility).isGranted;
    final bool inputMonitoring = snapshot.stateFor(MacOSPermission.inputMonitoring).isGranted;
    final bool screenRecording = snapshot.stateFor(MacOSPermission.screenRecording).isGranted;
    final bool notifications = snapshot.stateFor(MacOSPermission.notifications).isGranted;
    final PlatformCapabilities capabilities = PlatformCapabilities(
      globalHotkeys: _summonRegistered,
      windowEnumeration: screenRecording,
      windowActivation: accessibility,
      // The permission probe is useful for onboarding, but the low-level input
      // adapter is intentionally deferred for this migration.
      inputInjection: InputService.instance.isAvailable && accessibility && inputMonitoring,
      clipboardMonitoring: _clipboardStarted && ClipboardService.instance.isMonitoringAvailable,
      richClipboard: false,
      // Permission detection is present in Phase 5; the actual capture
      // adapter remains a later feature family.
      screenCapture: false,
      ocr: false,
      screenRecording: screenRecording,
      systemNotifications: notifications,
      audioDeviceControl: AudioSystemService.instance.isAvailable,
      perProcessAudio: AudioSystemService.instance.supportsPerProcessAudio,
      mediaSessions: MediaSessionService.instance.isAvailable,
      secureMachineStorage: SecretStores.instance.isAvailable,
      monitorGeometry: channel.isAvailable,
      quickSnap: channel.isAvailable && screenRecording && accessibility,
      quickSnapDrag: false,
    );
    PlatformCapabilities.register(capabilities);
    if (!_capabilityChanges.isClosed) _capabilityChanges.add(capabilities);
    return capabilities;
  }

  static Stream<PlatformCapabilities> get capabilityChanges => _capabilityChanges.stream;
  static bool get summonRegistered => _summonRegistered;
}
