import '../hotkey_service.dart';
import '../platform_models.dart';
import 'macos_platform_channel.dart';

class MacOSHotkeyService extends HotkeyService {
  MacOSHotkeyService({MacOSPlatformChannel? channel}) : channel = channel ?? MacOSPlatformChannel.instance;

  final MacOSPlatformChannel channel;

  @override
  bool get isAvailable => channel.isAvailable;

  @override
  bool get supportsConfiguredBindings => isAvailable;

  @override
  String get unavailableReason => isAvailable
      ? 'The requested macOS global shortcut is not registered; use the visible Tabame window instead.'
      : 'The macOS global shortcut service is unavailable.';

  @override
  Stream<PlatformHotkeyEvent> get events {
    return channel.events
        .where((Map<String, dynamic> event) => event['type'] == 'hotkey')
        .map((Map<String, dynamic> event) {
      final PlatformHotkeyEvent parsed = PlatformHotkeyEvent.fromMap(event);
      // Carbon exposes a reliable global press but not the low-level key-up
      // stream used by the shared dispatcher. Treat this supported press-only
      // event as the logical release of a simple press mapping; movement and
      // duration mappings are filtered before registration.
      return parsed.action == 'pressed' ? parsed.copyWith(action: 'released') : parsed;
    });
  }

  @override
  Future<HotkeyRegistrationResult> registerGlobal({
    required String key,
    required List<String> modifiers,
    String name = 'summon',
  }) {
    return channel.registerGlobalHotkey(key: key, modifiers: modifiers, name: name);
  }

  @override
  Future<HotkeyRegistrationResult> registerBindings(Iterable<PlatformHotkeyBinding> bindings) {
    return channel.registerGlobalHotkeys(bindings);
  }

  @override
  Future<void> unregisterGlobal() => channel.unregisterGlobalHotkey();
}
