import '../models/classes/hotkeys.dart';
import 'platform_models.dart';

/// Converts persisted hotkey settings into a platform-neutral registration
/// request. Platform adapters decide how that request is encoded natively.
class HotkeyBindingFactory {
  const HotkeyBindingFactory._();

  static List<PlatformHotkeyBinding> fromModels(Iterable<Hotkeys> hotkeys) {
    final List<PlatformHotkeyBinding> bindings = <PlatformHotkeyBinding>[];
    for (final Hotkeys group in hotkeys) {
      final List<KeyMap> keymaps = group.keymaps.toList()
        ..sort((KeyMap a, KeyMap b) {
          if (a.boundToRegion && !b.boundToRegion) return -1;
          if (!a.boundToRegion && b.boundToRegion) return 1;
          return 0;
        });

      for (final KeyMap keymap in keymaps) {
        if (!keymap.enabled) continue;
        bindings.add(
          PlatformHotkeyBinding(
            name: keymap.name,
            key: Hotkeys.normalizeKeyName(group.key),
            modifiers: Hotkeys.normalizeModifiers(group.modifiers),
            hotkey: group.hotkey.toUpperCase(),
            listensToMovement: group.keymaps.any(
              (KeyMap item) => item.triggerType == TriggerType.movement && item.triggerInfo[2] == -1,
            ),
            matchWindowBy: keymap.windowsInfo[0] == 'any' ? '' : keymap.windowsInfo[0],
            matchWindowText: keymap.windowsInfo[1],
            activateWindowUnderCursor: keymap.windowUnderMouse,
            noopScreenBusy: group.noopScreenBusy,
            prohibitedWindows: group.prohibited,
            region: PlatformHotkeyRegion(
              asPercentage: keymap.region.asPercentage,
              onScreen: keymap.regionOnScreen,
              x1: keymap.region.x1,
              x2: keymap.region.x2,
              y1: keymap.region.y1,
              y2: keymap.region.y2,
              anchorType: keymap.boundToRegion ? keymap.region.anchorType.index + 1 : 0,
            ),
          ),
        );
      }
    }
    return bindings;
  }
}
