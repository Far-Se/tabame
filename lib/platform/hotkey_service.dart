import 'platform_models.dart';

/// Global shortcut registration without exposing native key constants.
abstract class HotkeyService {
  static HotkeyService _instance = const UnavailableHotkeyService();

  static HotkeyService get instance => _instance;

  static void register(HotkeyService service) {
    _instance = service;
  }

  const HotkeyService();

  bool get isAvailable;
  bool get supportsConfiguredBindings => false;
  bool get supportsInputEvents => false;
  String get unavailableReason;
  Stream<PlatformHotkeyEvent> get events;

  Future<HotkeyRegistrationResult> registerGlobal({
    required String key,
    required List<String> modifiers,
    String name = 'summon',
  });

  /// Registers the persisted hotkey bindings for the active platform.
  ///
  /// Adapters may support only a subset of the neutral request. They must
  /// return an explicit unavailable/conflict result rather than silently
  /// dropping bindings.
  Future<HotkeyRegistrationResult> registerBindings(Iterable<PlatformHotkeyBinding> bindings) async {
    return const HotkeyRegistrationResult(
      registered: false,
      permissionRequired: false,
      reason: 'Configured global hotkeys are unavailable on this platform.',
    );
  }

  Future<void> unregisterGlobal();

  Future<void> unregisterBindings() => unregisterGlobal();
}

class UnavailableHotkeyService extends HotkeyService {
  const UnavailableHotkeyService();

  @override
  bool get isAvailable => false;

  @override
  String get unavailableReason => 'Global hotkeys are unavailable; use the visible Tabame window instead.';

  @override
  Stream<PlatformHotkeyEvent> get events => const Stream<PlatformHotkeyEvent>.empty();

  @override
  Future<HotkeyRegistrationResult> registerGlobal({
    required String key,
    required List<String> modifiers,
    String name = 'summon',
  }) async {
    return const HotkeyRegistrationResult(
      registered: false,
      permissionRequired: true,
      reason: 'Global hotkeys are unavailable on this platform.',
    );
  }

  @override
  Future<void> unregisterGlobal() async {}
}
