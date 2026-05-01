import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/classes/saved_maps.dart';
import '../../../models/tray_watcher.dart';
import '../../../models/win32/keys.dart';
import '../../../models/win32/win32.dart';
import '../../../models/win32/win_utils.dart';
import '../../../models/win32/window.dart';
import '../../../models/window_watcher.dart';
import '../../quickmenu/task_bar.dart';
import '../../widgets/quick_actions_item.dart';

class AppAudioButton extends StatefulWidget {
  final int index;
  const AppAudioButton({super.key, required this.index});

  @override
  State<AppAudioButton> createState() => _AppAudioButtonState();
}

class _AppAudioButtonState extends State<AppAudioButton> {
  // --- Constants ---
  static const double _kDragThreshold = 15.0;
  static const Duration _kFeedbackDuration = Duration(milliseconds: 1500);
  static const Duration _kMonitorInterval = Duration(milliseconds: 200);

  // --- State ---
  Timer? _monitorTimer;
  Timer? _feedbackTimer; // Handles the visual reset timeout

  double _lastDragPosition = 0;
  bool _isAppPlaying = false;
  IconData? _feedbackIcon; // The temporary icon (Play, Next, etc)

  @override
  void initState() {
    super.initState();
    _monitorTimer = Timer.periodic(_kMonitorInterval, _checkForAppPlaying);
  }

  @override
  void dispose() {
    _monitorTimer?.cancel();
    _feedbackTimer?.cancel();
    super.dispose();
  }

  AppAudioControl? get _control {
    if (widget.index >= Boxes.appAudioControls.length) return null;
    return Boxes.appAudioControls[widget.index];
  }

  /// Checks the actual background process state.
  void _checkForAppPlaying(Timer timer) {
    if (!mounted) return;
    final AppAudioControl? ctl = _control;
    if (ctl == null || !ctl.showAnimation) return;

    final bool isActuallyRunning = Caches.audioMixerExes.contains(ctl.exe);

    // If the state hasn't changed, do nothing.
    if (_isAppPlaying == isActuallyRunning) return;

    setState(() {
      _isAppPlaying = isActuallyRunning;

      // Logic: If the state changed (e.g. we were playing, user clicked pause,
      // and now the system confirms it is NOT playing), we clear the manual
      // feedback icon immediately to show the correct "Idle" state.
      if (_feedbackIcon != null) {
        _feedbackIcon = null;
        _feedbackTimer?.cancel();
      }
    });
  }

  /// Sets a temporary icon. It cancels any previous pending clear actions.
  void _setFeedbackIcon(IconData icon) {
    _feedbackTimer?.cancel(); // Cancel any pending reset

    setState(() {
      _feedbackIcon = icon;
    });

    _feedbackTimer = Timer(_kFeedbackDuration, () {
      if (mounted) {
        setState(() => _feedbackIcon = null);
      }
    });
  }

  ({int pid, int hWnd})? _getAppWindow() {
    final AppAudioControl? ctl = _control;
    if (ctl == null) return null;
    final Window? win = WindowWatcher.list.firstWhereOrNull((Window element) => element.process.exe == ctl.exe);
    if (win != null) {
      return (hWnd: win.hWnd, pid: win.process.pId);
    } else {
      final TrayBarInfo? tray = Tray.trayList.firstWhereOrNull((TrayBarInfo element) => element.processExe == ctl.exe);
      if (tray != null) {
        return (hWnd: tray.hWnd, pid: tray.processID);
      }
    }
    return null;
  }

  void _launchApp() async {
    final AppAudioControl? ctl = _control;
    if (ctl == null) return;
    await WindowWatcher.fetchWindows();
    // 1. Check if the app has a regular window open
    final Window? win = WindowWatcher.list.firstWhereOrNull((Window element) => element.process.exe == ctl.exe);
    if (win != null) {
      Win32.activateWindow(win.hWnd);
      return;
    }

    // 2. Check if the app is in the system tray
    await Tray.fetchTray();
    final TrayBarInfo? tray = Tray.trayList.firstWhereOrNull((TrayBarInfo element) => element.processExe == ctl.exe);
    if (tray != null) {
      WinTray.click(tray, clickType: TrayClickType.left);
      return;
    }

    // 3. Fallback: Launch the app
    if (ctl.path.isNotEmpty) {
      WinUtils.open(ctl.path);
    }
  }

  // --- Actions ---

  void _handleVolumeDrag(DragUpdateDetails details) {
    final AppAudioControl? ctl = _control;
    if (ctl == null) return;
    if (details.delta.direction == 0) return;

    if (_lastDragPosition == 0) {
      _lastDragPosition = details.localPosition.distance;
      return;
    }

    if ((details.localPosition.distance - _lastDragPosition).abs() < _kDragThreshold) {
      return;
    }

    _lastDragPosition = details.localPosition.distance;
    final bool isUp = (details.primaryDelta ?? 0) < 0;

    WinKeys.send(isUp ? ctl.hotkeyRewind : ctl.hotkeyForward);
  }

  void _handleNextTrack() {
    final AppAudioControl? ctl = _control;
    if (ctl == null) return;
    final ({int hWnd, int pid})? window = _getAppWindow();
    if (window == null) {
      WinKeys.single(VK.MEDIA_NEXT_TRACK, KeySentMode.normal);
    } else {
      WinKeys.send(ctl.hotkeyNext);
    }
    _setFeedbackIcon(Icons.fast_forward);
  }

  void _handlePrevTrack() {
    final AppAudioControl? ctl = _control;
    if (ctl == null) return;
    final ({int hWnd, int pid})? window = _getAppWindow();
    if (window == null) {
      WinKeys.single(VK.MEDIA_PREV_TRACK, KeySentMode.normal);
    } else {
      WinKeys.send(ctl.hotkeyPrev);
    }
    _setFeedbackIcon(Icons.fast_rewind);
  }

  void _handlePlayPause() {
    final AppAudioControl? ctl = _control;
    if (ctl == null) return;
    final ({int hWnd, int pid})? window = _getAppWindow();
    if (window == null) {
      WinKeys.single(VK.MEDIA_PLAY_PAUSE, KeySentMode.normal);
    } else {
      WinKeys.send(ctl.hotkeyPause);
    }
    _setFeedbackIcon(Icons.play_circle_outline);
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    final AppAudioControl? ctl = _control;
    if (ctl == null) return const SizedBox.shrink();

    Widget content;

    if (_feedbackIcon != null) {
      content = Icon(_feedbackIcon, color: Colors.amber[700]);
    } else if (_isAppPlaying) {
      content = Icon(Icons.multitrack_audio_sharp, color: Colors.amber[700]);
    } else {
      if (ctl.iconPath.isNotEmpty && File(ctl.iconPath).existsSync()) {
        content = Image.file(File(ctl.iconPath), width: 16, height: 16);
      } else {
        content = Icon(IconData(ctl.iconCodePoint, fontFamily: 'MaterialIcons'), size: 16);
      }
    }

    return QuickActionItem(
      onVerticalDragStart: (_) => _lastDragPosition = 0,
      onVerticalDragEnd: (_) => _lastDragPosition = 0,
      onVerticalDragUpdate: _handleVolumeDrag,
      onSecondaryTap: _handleNextTrack,
      onTertiaryTapDown: (_) => _handlePrevTrack(),
      onTap: _handlePlayPause,
      onDoubleTap: _launchApp,
      message: ctl.name,
      icon: content,
    );
  }
}
