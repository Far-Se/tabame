import '../hotkey_service.dart';
import '../platform_models.dart';
import 'linux_platform_channel.dart';

class LinuxHotkeyService extends HotkeyService {
  LinuxHotkeyService({LinuxPlatformChannel? channel}) : channel = channel ?? LinuxPlatformChannel.instance;

  final LinuxPlatformChannel channel;

  @override
  bool get isAvailable => channel.cachedCapabilities.globalHotkeys;

  @override
  bool get supportsConfiguredBindings => false;

  @override
  String get unavailableReason {
    if (isAvailable) return '';
    final String probedReason = channel.cachedCapabilities.reasonFor('globalHotkeys');
    if (probedReason.isNotEmpty) return probedReason;
    if (channel.cachedCapabilities.isWaylandOnly) {
      return 'Global X11 hotkeys are unavailable in a Wayland session; use the visible Tabame window instead.';
    }
    return 'The Linux X11 global hotkey service is unavailable; use the visible Tabame window instead.';
  }

  @override
  Stream<PlatformHotkeyEvent> get events {
    return channel.events
        .where((Map<String, dynamic> event) => event['type'] == 'hotkey')
        .map(PlatformHotkeyEvent.fromMap);
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
  Future<HotkeyRegistrationResult> registerBindings(Iterable<PlatformHotkeyBinding> bindings) async {
    return const HotkeyRegistrationResult(
      registered: false,
      permissionRequired: false,
      reason: 'Configured Linux low-level hotkeys are deferred; use the visible Tabame window instead.',
    );
  }

  @override
  Future<void> unregisterGlobal() => channel.unregisterGlobalHotkey();
}
