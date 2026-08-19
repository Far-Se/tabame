import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../platform/audio_system_service.dart';
import '../../../models/classes/boxes.dart';
import '../../../models/classes/saved_maps.dart';
import '../../widgets/quick_actions_item.dart';

bool isAppAudioControlConfigured(int index) {
  if (index < 0 || index >= Boxes.appAudioControls.length) return false;
  final AppAudioControl control = Boxes.appAudioControls[index];
  return control.exe.trim().isNotEmpty || control.path.trim().isNotEmpty;
}

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

  /// Checks the current session state through the platform media adapter.
  void _checkForAppPlaying(Timer timer) {
    if (!QuickMenuFunctions.isQuickMenuVisible) return;
    if (!mounted) return;
    final AppAudioControl? ctl = _control;
    if (ctl == null ||
        !isAppAudioControlConfigured(widget.index) ||
        !ctl.showAnimation ||
        !MediaSessionService.instance.isAvailable) {
      return;
    }
    unawaited(_refreshAppPlaying(ctl));
  }

  Future<void> _refreshAppPlaying(AppAudioControl ctl) async {
    final bool isActuallyRunning = await MediaSessionService.instance.isApplicationPlaying(_binding(ctl));

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

  PlatformMediaBinding _binding(AppAudioControl ctl) {
    return PlatformMediaBinding(
      applicationId: ctl.exe.isNotEmpty ? ctl.exe : ctl.name,
      applicationPath: ctl.path,
      hotkeyForward: ctl.hotkeyForward,
      hotkeyRewind: ctl.hotkeyRewind,
      hotkeyNext: ctl.hotkeyNext,
      hotkeyPrevious: ctl.hotkeyPrev,
      hotkeyPlayPause: ctl.hotkeyPause,
    );
  }

  Future<void> _launchApp() async {
    final AppAudioControl? ctl = _control;
    if (ctl == null) return;
    await MediaSessionService.instance.launchApplication(_binding(ctl));
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

    unawaited(
      MediaSessionService.instance.sendApplicationCommand(
        _binding(ctl),
        isUp ? PlatformMediaCommand.seekForward : PlatformMediaCommand.seekBackward,
      ),
    );
  }

  void _handleNextTrack() {
    final AppAudioControl? ctl = _control;
    if (ctl == null) return;
    unawaited(MediaSessionService.instance.sendApplicationCommand(_binding(ctl), PlatformMediaCommand.next));
    _setFeedbackIcon(Icons.fast_forward);
  }

  void _handlePrevTrack() {
    final AppAudioControl? ctl = _control;
    if (ctl == null) return;
    unawaited(MediaSessionService.instance.sendApplicationCommand(_binding(ctl), PlatformMediaCommand.previous));
    _setFeedbackIcon(Icons.fast_rewind);
  }

  void _handlePlayPause() {
    final AppAudioControl? ctl = _control;
    if (ctl == null) return;
    unawaited(MediaSessionService.instance.sendApplicationCommand(_binding(ctl), PlatformMediaCommand.playPause));
    _setFeedbackIcon(Icons.play_circle_outline);
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    final AppAudioControl? ctl = _control;
    if (ctl == null || !isAppAudioControlConfigured(widget.index)) return const SizedBox.shrink();

    Widget content;

    if (_feedbackIcon != null) {
      content = Icon(_feedbackIcon, color: Colors.amber[700]);
    } else if (_isAppPlaying) {
      content = Icon(Icons.multitrack_audio_sharp, color: Colors.amber[700]);
    } else {
      if (ctl.iconPath.isNotEmpty && File(ctl.iconPath).existsSync()) {
        content = Image.file(File(ctl.iconPath), width: 16, height: 16);
      } else {
        // ignore: non_const_argument_for_const_parameter
        content = Icon(IconData(ctl.iconCodePoint, fontFamily: 'MaterialIcons'), size: 16);
      }
    }

    final bool mediaAvailable = MediaSessionService.instance.isAvailable;
    return QuickActionItem(
      onVerticalDragStart: mediaAvailable ? (_) => _lastDragPosition = 0 : null,
      onVerticalDragEnd: mediaAvailable ? (_) => _lastDragPosition = 0 : null,
      onVerticalDragUpdate: mediaAvailable ? _handleVolumeDrag : null,
      onSecondaryTap: mediaAvailable ? _handleNextTrack : null,
      onTertiaryTapDown: mediaAvailable ? (_) => _handlePrevTrack() : null,
      onTap: mediaAvailable ? _handlePlayPause : null,
      onDoubleTap: mediaAvailable ? _launchApp : null,
      message: mediaAvailable ? ctl.name : MediaSessionService.instance.unavailableReason,
      icon: content,
    );
  }
}
