import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:tabamewin32/tabamewin32.dart';

import '../classes/boxes.dart';
import '../classes/hotkeys.dart';
import '../globals.dart';
import '../settings.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HotkeyHandler
//
// Processes incoming [HotkeyEvent]s from the native hook layer and dispatches
// them to the appropriate [KeyMap] actions based on the configured trigger type.
//
// Trigger types and their dispatch order on button release:
//   1. Mouse-movement (while held)
//   2. Mouse-direction (distance on release)
//   3. Hold-duration
//   4. Region double-press
//   5. Region press
//   6. Global double-press
//   7. Normal press
// ─────────────────────────────────────────────────────────────────────────────

class HotkeyHandler {
  // ── State ──────────────────────────────────────────────────────────────────

  /// Cursor position captured at press time (used as movement baseline).
  Point<int> _mousePressOrigin = const Point<int>(0, 0);

  /// Dominant movement axis detected while the button is held.
  /// 0 = none, 1 = horizontal, 2 = vertical.
  int _movementAxis = 0;

  /// Virtual key code of the currently held keyboard key (kbd-release tracking).
  int _currentVK = -1;

  /// Hotkeys for which a movement action fired during the current press
  /// (prevents the release from also triggering a normal press action).
  final Map<String, int> _firedMovement = <String, int>{};

  /// Timestamp of the first release for hotkeys that have a double-press mapping,
  /// keyed by hotkey string (e.g. "CTRL+ALT+X").
  final Map<String, int> _doublePressTimestamps = <String, int>{};

  // ── Public entry point ────────────────────────────────────────────────────

  Future<void> handle(HotkeyEvent event) async {
    if (!kReleaseMode && !Globals.debugHotkeys) return;

    // Find the hotkey configuration that matches this event.
    final List<Hotkeys> matches = Boxes.remap.where((Hotkeys h) => h.hotkey == event.hotkey).toList();
    if (matches.isEmpty) return;
    final Hotkeys hotkey = matches.first;
    switch (event.action) {
      case 'pressedKbd':
        _handleKbdPress(event, hotkey);
        return;
      case 'releaseKbd':
        await _handleKbdRelease(event);
        return;
      case 'pressed':
        _handlePress(event, hotkey);
        return;
      case 'moved':
        await _handleMoved(event, hotkey);
        return;
      case 'released':
        await _handleRelease(event, hotkey);
        return;
    }
  }

  // ── Action: pressedKbd ────────────────────────────────────────────────────

  void _handleKbdPress(HotkeyEvent event, Hotkeys hotkey) {
    final int vk = Hotkeys.keyToVirtualKey(hotkey.key) ?? -1;
    if (vk == -1) return;
    _currentVK = vk;

    if (hotkey.hasMouseMovementTriggers) {
      _mousePressOrigin = event.mouse.start;
    }
  }

  // ── Action: releaseKbd ────────────────────────────────────────────────────

  Future<void> _handleKbdRelease(HotkeyEvent event) async {
    if (event.vk != _currentVK) return;
    _currentVK = -1;

    // Re-dispatch as a synthetic 'released' for the keyboard listener path.
    final HotkeyEvent syntheticRelease = event..action = 'released';
    for (final TabameListener listener in NativeHooks.listeners) {
      if (!NativeHooks.listenersObv.contains(listener)) continue;
      listener.onHotKeyEvent(syntheticRelease);
    }
  }

  // ── Action: pressed ────────────────────────────────────────────────────────

  void _handlePress(HotkeyEvent event, Hotkeys hotkey) {
    if (hotkey.hasMouseMovementTriggers) {
      _mousePressOrigin = event.mouse.start;
    }
  }

  // ── Action: moved ─────────────────────────────────────────────────────────

  Future<void> _handleMoved(HotkeyEvent event, Hotkeys hotkey) async {
    // Determine the dominant axis once we have moved far enough.
    if (_movementAxis == 0) {
      final Point<int> delta = event.mouse.end - _mousePressOrigin;
      final int totalDist = delta.x.abs() + delta.y.abs();
      if (totalDist > 40) {
        _movementAxis = delta.x.abs() > delta.y.abs() ? 1 : 2;
      }
    }

    if (_movementAxis == 0) return;

    final List<KeyMap> movementStepMaps = hotkey.getHotkeysWithMovementTriggers;
    if (movementStepMaps.isEmpty) return;

    final Point<int> delta = event.mouse.end - _mousePressOrigin;

    for (final KeyMap keyMap in movementStepMaps) {
      if (!keyMap.isMouseInRegion) continue;

      final int dir = keyMap.triggerInfo[0];
      final int threshold = keyMap.triggerInfo[1];

      final bool triggered = (dir == 0 && _movementAxis == 1 && delta.x < 0 && delta.x.abs() > threshold) || // left
          (dir == 1 && _movementAxis == 1 && delta.x > 0 && delta.x.abs() > threshold) || // right
          (dir == 2 && _movementAxis == 2 && delta.y < 0 && delta.y.abs() > threshold) || // up
          (dir == 3 && _movementAxis == 2 && delta.y > 0 && delta.y.abs() > threshold); // down

      if (triggered) {
        _mousePressOrigin = event.mouse.end; // reset baseline so steps feel continuous
        _firedMovement[event.hotkey] = 1;
        await keyMap.applyActions(TriggerType.movement);
      }
    }
  }

  // ── Action: released ──────────────────────────────────────────────────────

  Future<void> _handleRelease(HotkeyEvent event, Hotkeys hotkey) async {
    _movementAxis = 0;
    // If a movement action was triggered during this press, skip normal release handling.
    if (_firedMovement.remove(event.hotkey) != null) return;
    // 1. Mouse-direction (distance-based movement on release).
    if (await _tryDispatchDirectionRelease(event, hotkey)) return;
    // 2. Hold-duration.
    if (await _tryDispatchDuration(event, hotkey)) return;
    // 3. Region-bound double-press.
    if (await _tryDispatchRegionDoublePress(event, hotkey)) return;
    // 4. Region-bound normal press.
    if (await _tryDispatchRegionPress(event, hotkey)) return;
    // 5. Global double-press.
    if (await _tryDispatchDoublePress(event, hotkey)) return;
    // 6. Normal press (last resort).
    if (await _dispatchNormalPress(event, hotkey)) return;
    // 7. Double-press-only mappings still need a first release to compare against.
    _primeDoublePressOnlyMapping(event, hotkey);
  }

  // ── Release sub-dispatchers ───────────────────────────────────────────────

  /// Returns `true` if a direction-based release action fired.
  Future<bool> _tryDispatchDirectionRelease(HotkeyEvent event, Hotkeys hotkey) async {
    final List<KeyMap> directionMaps = _sortedByRegionFirst(hotkey.getHotkeysWithMovement);
    if (directionMaps.isEmpty) return false;

    final Point<int> diff = event.mouse.diff;
    final int diffX = diff.x.abs();
    final int diffY = diff.y.abs();

    for (final KeyMap keyMap in directionMaps) {
      if (!keyMap.isMouseInRegion) continue;

      final int dir = keyMap.triggerInfo[0];
      final int minDist = keyMap.triggerInfo[1];
      final int maxDist = keyMap.triggerInfo[2];

      final bool triggered = (dir == 0 && diff.x < 0 && diffX.isBetweenEqual(minDist, maxDist)) || // left
          (dir == 1 && diff.x > 0 && diffX.isBetweenEqual(minDist, maxDist)) || // right
          (dir == 2 && diff.y < 0 && diffY.isBetweenEqual(minDist, maxDist)) || // up
          (dir == 3 && diff.y > 0 && diffY.isBetweenEqual(minDist, maxDist)); // down

      if (triggered) {
        await keyMap.applyActions(TriggerType.movement);
        return true;
      }
    }
    return false;
  }

  /// Returns `true` if a duration-based action fired.
  Future<bool> _tryDispatchDuration(HotkeyEvent event, Hotkeys hotkey) async {
    final List<KeyMap> durationMaps = _sortedByRegionFirst(hotkey.getDurationKeys);
    if (durationMaps.isEmpty) return false;

    final int heldMs = event.time.duration;

    for (final KeyMap keyMap in durationMaps) {
      if (!keyMap.isMouseInRegion) continue;
      if (heldMs.isBetweenEqual(keyMap.triggerInfo[0], keyMap.triggerInfo[1])) {
        await keyMap.applyActions(TriggerType.duration);
        return true;
      }
    }
    return false;
  }

  /// Returns `true` if a region-bound double-press action fired.
  Future<bool> _tryDispatchRegionDoublePress(HotkeyEvent event, Hotkeys hotkey) async {
    if (!_doublePressTimestamps.containsKey(hotkey.hotkey)) return false;
    if (event.name.isEmpty) return false;

    final List<KeyMap> regionDoublePressKeys = hotkey.keymaps
        .where((KeyMap km) => km.boundToRegion && km.triggerType == TriggerType.doublePress && km.enabled)
        .toList();

    for (final KeyMap keyMap in regionDoublePressKeys) {
      if (!keyMap.isMouseInRegion) continue;

      final int elapsed = event.time.end - _doublePressTimestamps[hotkey.hotkey]!;
      if (elapsed < 300) {
        await keyMap.applyActions(TriggerType.doublePress);
        _doublePressTimestamps.remove(hotkey.hotkey);
        return true;
      } else {
        _doublePressTimestamps.remove(hotkey.hotkey);
      }
    }
    return false;
  }

  /// Returns `true` if a region-bound normal press action fired.
  Future<bool> _tryDispatchRegionPress(HotkeyEvent event, Hotkeys hotkey) async {
    if (event.name.isEmpty) return false;

    final List<KeyMap> regionPressKeys = hotkey.keymaps
        .where((KeyMap km) => km.boundToRegion && km.triggerType == TriggerType.press && km.enabled)
        .toList();

    for (final KeyMap keyMap in regionPressKeys) {
      if (!keyMap.isMouseInRegion) continue;

      if (hotkey.hasDoublePress) {
        _doublePressTimestamps[hotkey.hotkey] = event.time.end;
      }
      await keyMap.applyActions(TriggerType.press);
      return true;
    }
    return false;
  }

  final Map<String, Timer> _pendingPressTimers = <String, Timer>{};

  /// Returns `true` if a global double-press action fired.
  Future<bool> _tryDispatchDoublePress(HotkeyEvent event, Hotkeys hotkey) async {
    if (!_doublePressTimestamps.containsKey(hotkey.hotkey)) return false;

    final List<KeyMap> doublePressKeys = hotkey.getDoublePress;
    final int elapsed = event.time.end - _doublePressTimestamps[hotkey.hotkey]!;

    for (final KeyMap keyMap in doublePressKeys) {
      if (!keyMap.isMouseInRegion) continue;
      if (elapsed < 300) {
        // Cancel pending single press
        _pendingPressTimers[hotkey.hotkey]?.cancel();
        _pendingPressTimers.remove(hotkey.hotkey);

        _doublePressTimestamps.remove(hotkey.hotkey);

        await keyMap.applyActions(TriggerType.doublePress);
        return true;
      }
    }

    return false;
  }

  /// Dispatches the first matching normal press action.
  Future<bool> _dispatchNormalPress(HotkeyEvent event, Hotkeys hotkey) async {
    final List<KeyMap> pressKeys = hotkey.getPress;

    for (final KeyMap keyMap in pressKeys) {
      if (!keyMap.isMouseInRegion) continue;
      if (event.name.isNotEmpty && keyMap.name != event.name) continue;

      // OLD BEHAVIOR:
      // Execute immediately even if double-press exists.
      if (!hotkey.waitForDoublePress) {
        if (hotkey.hasDoublePress) {
          _doublePressTimestamps[hotkey.hotkey] = event.time.end;
        }

        await keyMap.applyActions(TriggerType.press);
        return true;
      }

      // NEW BEHAVIOR:
      // Wait briefly to determine if this becomes a double press.
      if (hotkey.hasDoublePress) {
        _doublePressTimestamps[hotkey.hotkey] = event.time.end;

        // Cancel previous pending single-press timer.
        _pendingPressTimers[hotkey.hotkey]?.cancel();

        _pendingPressTimers[hotkey.hotkey] = Timer(
          const Duration(milliseconds: 300),
          () async {
            // No second press happened.
            if (_doublePressTimestamps.containsKey(hotkey.hotkey)) {
              _doublePressTimestamps.remove(hotkey.hotkey);

              await keyMap.applyActions(TriggerType.press);
            }

            _pendingPressTimers.remove(hotkey.hotkey);
          },
        );

        return true;
      }

      // No double-press mappings -> execute immediately.
      await keyMap.applyActions(TriggerType.press);
      return true;
    }

    return false;
  }

  void _primeDoublePressOnlyMapping(HotkeyEvent event, Hotkeys hotkey) {
    if (!hotkey.hasDoublePress) return;

    final List<KeyMap> doublePressKeys = _sortedByRegionFirst(hotkey.getDoublePress);
    for (final KeyMap keyMap in doublePressKeys) {
      if (keyMap.boundToRegion && event.name.isEmpty) continue;
      if (!keyMap.isMouseInRegion) continue;
      _doublePressTimestamps[hotkey.hotkey] = event.time.end;
      return;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Returns a copy of [keymaps] sorted so that region-bound maps come first.
  /// Region-aware checks should always be evaluated before fallback (any-window) ones.
  List<KeyMap> _sortedByRegionFirst(List<KeyMap> keymaps) {
    return keymaps.toList()
      ..sort((KeyMap a, KeyMap b) {
        if (a.boundToRegion && !b.boundToRegion) return -1;
        if (!a.boundToRegion && b.boundToRegion) return 1;
        return 0;
      });
  }
}
