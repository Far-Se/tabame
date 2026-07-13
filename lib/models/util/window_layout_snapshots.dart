import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../../logic/error_handler.dart';
import '../classes/boxes.dart';
import '../classes/saved_maps.dart';
import '../settings.dart';
import '../win32/mixed.dart';
import '../win32/window.dart';
import '../window_watcher.dart';

/// Captures and restores the placement of every open top-level window.
///
/// Placement round-trips through GetWindowPlacement/SetWindowPlacement, so the
/// normal rect, maximized and minimized states survive exactly — a maximized
/// window re-maximizes on the monitor its normal rect belongs to. Snapshots
/// carry a monitor-arrangement fingerprint so a snapshot marked auto-restore
/// re-applies itself when its display setup comes back (dock/undock).
class WindowLayoutSnapshots {
  WindowLayoutSnapshots._();

  static String? _signatureAtLastEvent;

  /// Fingerprint of the current monitor arrangement, e.g. "0,0,2560x1440|2560,0,1920x1080".
  static String monitorSignature() {
    Monitor.fetchMonitors();
    final List<Square> sizes = Monitor.monitorSizes.values.toList()
      ..sort((Square a, Square b) => a.x != b.x ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
    return sizes.map((Square s) => '${s.x},${s.y},${s.width}x${s.height}').join('|');
  }

  /// Remembers the current arrangement so the first real display change can be
  /// told apart from spurious WM_DISPLAYCHANGE events (bit-depth, wallpaper span…).
  static void rememberCurrentSignature() {
    _signatureAtLastEvent = monitorSignature();
  }

  static Future<WindowLayoutSnapshot> capture(String name) async {
    await WindowWatcher.fetchWindows();
    final List<WindowLayoutEntry> entries = <WindowLayoutEntry>[];
    // Parallel to [entries]: the hWnd each entry was captured from, so the
    // runtime hook relationships can be resolved to persistent entry indices.
    final List<int> entryHandles = <int>[];

    for (final Window window in WindowWatcher.list) {
      final Pointer<WINDOWPLACEMENT> placement = calloc<WINDOWPLACEMENT>();
      placement.ref.length = sizeOf<WINDOWPLACEMENT>();
      if (GetWindowPlacement(window.hWnd, placement) != 0) {
        final RECT rect = placement.ref.rcNormalPosition;
        final int width = rect.right - rect.left;
        final int height = rect.bottom - rect.top;
        if (width > 0 && height > 0) {
          entries.add(WindowLayoutEntry(
            exePath: '${window.process.path}${window.process.exe}',
            exe: window.process.exe,
            title: window.title,
            x: rect.left,
            y: rect.top,
            width: width,
            height: height,
            showCmd: placement.ref.showCmd,
          ));
          entryHandles.add(window.hWnd);
        }
      }
      free(placement);
    }

    _captureHooks(entries, entryHandles);

    return WindowLayoutSnapshot(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      monitorSignature: monitorSignature(),
      entries: entries,
    );
  }

  /// Translates the live `user.hookedWins` map (master hWnd → hooked child
  /// hWnds) into entry-index relationships stored on the snapshot entries, so
  /// the hooks persist across restarts where the hWnds no longer exist.
  static void _captureHooks(List<WindowLayoutEntry> entries, List<int> entryHandles) {
    if (user.hookedWins.isEmpty) return;
    final Map<int, int> handleToIndex = <int, int>{};
    for (int i = 0; i < entryHandles.length; i++) {
      handleToIndex[entryHandles[i]] = i;
    }

    user.hookedWins.forEach((int masterHwnd, List<int> childHandles) {
      final int? masterIndex = handleToIndex[masterHwnd];
      if (masterIndex == null) return;
      for (final int childHwnd in childHandles) {
        final int? childIndex = handleToIndex[childHwnd];
        if (childIndex != null && childIndex != masterIndex) {
          entries[masterIndex].hookedEntries.add(childIndex);
        }
      }
    });
  }

  /// Repositions every window that can be matched to a snapshot entry.
  /// Returns how many entries were restored and how many had no match.
  static Future<({int restored, int missing})> restore(WindowLayoutSnapshot snapshot) async {
    await WindowWatcher.fetchWindows();
    final List<Window> windows = List<Window>.from(WindowWatcher.list);
    final Set<int> usedHandles = <int>{};
    // Parallel to snapshot.entries: the hWnd each entry matched to (0 = none),
    // used to re-establish the hooks after all windows are placed.
    final List<int> matchedHandles = List<int>.filled(snapshot.entries.length, 0);
    int restored = 0;
    int missing = 0;

    for (int i = 0; i < snapshot.entries.length; i++) {
      final WindowLayoutEntry entry = snapshot.entries[i];
      final Window? match = _bestMatch(entry, windows, usedHandles);
      if (match == null) {
        missing++;
        continue;
      }
      usedHandles.add(match.hWnd);
      matchedHandles[i] = match.hWnd;
      if (_applyEntry(match.hWnd, entry)) {
        restored++;
      } else {
        missing++;
      }
    }

    _restoreHooks(snapshot, matchedHandles);

    return (restored: restored, missing: missing);
  }

  /// Rebuilds the live `user.hookedWins` map from the snapshot's persisted
  /// hook relationships, mapping stored entry indices back to the hWnds they
  /// matched to this session. Only entries whose master and at least one child
  /// were both matched produce a live hook.
  static void _restoreHooks(WindowLayoutSnapshot snapshot, List<int> matchedHandles) {
    for (int i = 0; i < snapshot.entries.length; i++) {
      final List<int> hooked = snapshot.entries[i].hookedEntries;
      if (hooked.isEmpty) continue;
      final int masterHwnd = matchedHandles[i];
      if (masterHwnd == 0) continue;

      final List<int> childHandles = <int>[];
      for (final int childIndex in hooked) {
        if (childIndex < 0 || childIndex >= matchedHandles.length) continue;
        final int childHwnd = matchedHandles[childIndex];
        if (childHwnd != 0 && childHwnd != masterHwnd && !childHandles.contains(childHwnd)) {
          childHandles.add(childHwnd);
        }
      }
      if (childHandles.isEmpty) continue;

      final List<int> existing = user.hookedWins[masterHwnd] ??= <int>[];
      for (final int childHwnd in childHandles) {
        if (!existing.contains(childHwnd)) existing.add(childHwnd);
      }
    }
  }

  static bool _applyEntry(int hWnd, WindowLayoutEntry entry) {
    if (IsWindow(hWnd) == 0) return false;

    final Pointer<WINDOWPLACEMENT> placement = calloc<WINDOWPLACEMENT>();
    placement.ref.length = sizeOf<WINDOWPLACEMENT>();
    GetWindowPlacement(hWnd, placement);

    placement.ref.rcNormalPosition.left = entry.x;
    placement.ref.rcNormalPosition.top = entry.y;
    placement.ref.rcNormalPosition.right = entry.x + entry.width;
    placement.ref.rcNormalPosition.bottom = entry.y + entry.height;
    // Don't steal focus while sweeping through windows.
    placement.ref.showCmd = switch (entry.showCmd) {
      SW_SHOWMAXIMIZED => SW_SHOWMAXIMIZED,
      SW_SHOWMINIMIZED => SW_SHOWMINNOACTIVE,
      _ => SW_SHOWNOACTIVATE,
    };

    bool applied = SetWindowPlacement(hWnd, placement) != 0;
    if (applied && entry.showCmd == SW_SHOWMAXIMIZED) {
      // A window maximized on a different monitor needs a second pass: the first
      // call moves its normal rect to the target monitor, the second maximizes there.
      applied = SetWindowPlacement(hWnd, placement) != 0;
    }

    free(placement);
    return applied;
  }

  static Window? _bestMatch(WindowLayoutEntry entry, List<Window> windows, Set<int> usedHandles) {
    Window? bestMatch;
    int bestScore = 0;
    final String entryPath = entry.exePath.toLowerCase();
    final String entryExe = entry.exe.toLowerCase();
    final String entryTitle = entry.title.toLowerCase();

    for (final Window window in windows) {
      if (usedHandles.contains(window.hWnd)) continue;

      final String windowPath = '${window.process.path}${window.process.exe}'.toLowerCase();
      final String windowExe = window.process.exe.toLowerCase();
      int score = 0;
      if (windowPath == entryPath) {
        score += 40;
      } else if (windowExe.isNotEmpty && windowExe == entryExe) {
        score += 25;
      } else {
        continue;
      }

      final String windowTitle = window.title.toLowerCase();
      if (entryTitle.isNotEmpty && windowTitle.isNotEmpty) {
        if (windowTitle == entryTitle) {
          score += 20;
        } else if (windowTitle.contains(entryTitle) || entryTitle.contains(windowTitle)) {
          score += 10;
        }
      }

      if (score > bestScore) {
        bestScore = score;
        bestMatch = window;
      }
    }

    return bestMatch;
  }

  // --------------------------------------------------------------------------
  // Auto-restore on display change
  // --------------------------------------------------------------------------

  static Timer? _autoRestoreDebounce;

  /// Called from the QuickMenu's WM_DISPLAYCHANGE handler. Waits for the
  /// monitor topology to settle, then re-applies the first auto-restore
  /// snapshot whose fingerprint matches the new arrangement.
  static void onDisplayChanged() {
    _autoRestoreDebounce?.cancel();
    _autoRestoreDebounce = Timer(const Duration(milliseconds: 2500), () async {
      try {
        final String signature = monitorSignature();
        if (signature == _signatureAtLastEvent) return;
        _signatureAtLastEvent = signature;

        WindowLayoutSnapshot? match;
        for (final WindowLayoutSnapshot snapshot in Boxes.windowLayouts) {
          if (snapshot.autoRestore && snapshot.monitorSignature == signature) {
            match = snapshot;
            break;
          }
        }
        if (match == null) return;
        await restore(match);
      } catch (e, s) {
        await ErrorLogger.log('WindowLayoutSnapshots.onDisplayChanged', e.toString(), s);
      }
    });
  }
}
