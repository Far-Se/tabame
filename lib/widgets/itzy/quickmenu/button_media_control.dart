import 'dart:async';

import 'package:flutter/material.dart';

import '../../../platform/audio_system_service.dart';
import '../../widgets/quick_actions_item.dart';

class MediaControlButton extends StatefulWidget {
  const MediaControlButton({super.key});

  @override
  State<MediaControlButton> createState() => _MediaControlButtonState();
}

class _MediaControlButtonState extends State<MediaControlButton> {
  IconData icon = Icons.play_arrow;
  int _timers = 0;
  double _dragAccumulator = 0;

  void _applyCommand(PlatformMediaCommand command, IconData feedbackIcon) {
    if (!MediaSessionService.instance.isAvailable) return;
    MediaSessionService.instance.sendGlobalCommand(command);
    setState(() => icon = feedbackIcon);
    _timers++;
    Timer(const Duration(seconds: 1), () {
      _timers--;
      if (_timers <= 0 && mounted) {
        setState(() => icon = Icons.play_arrow);
      }
    });
  }

  void _setVolumeFeedback(IconData feedbackIcon) {
    setState(() => icon = feedbackIcon);
    _timers++;
    Timer(const Duration(seconds: 1), () {
      _timers--;
      if (_timers <= 0 && mounted) {
        setState(() => icon = Icons.play_arrow);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message:
          MediaSessionService.instance.isAvailable ? "Media Control" : MediaSessionService.instance.unavailableReason,
      icon: Icon(icon, size: 16),
      onTap: MediaSessionService.instance.isAvailable
          ? () => _applyCommand(PlatformMediaCommand.playPause, Icons.play_circle_outline)
          : null,
      onSecondaryTap: MediaSessionService.instance.isAvailable
          ? () => _applyCommand(PlatformMediaCommand.next, Icons.fast_forward)
          : null,
      onTertiaryTapDown: MediaSessionService.instance.isAvailable
          ? (_) => _applyCommand(PlatformMediaCommand.previous, Icons.fast_rewind)
          : null,
      onVerticalDragStart: (_) => _dragAccumulator = 0,
      onVerticalDragUpdate: (DragUpdateDetails details) {
        _dragAccumulator -= details.delta.dy;
        if (_dragAccumulator.abs() > 10 && AudioSystemService.instance.isAvailable) {
          if (_dragAccumulator > 0) {
            AudioSystemService.instance.adjustVolume(AudioDeviceType.output, 0.05);
            _setVolumeFeedback(Icons.volume_up);
          } else {
            AudioSystemService.instance.adjustVolume(AudioDeviceType.output, -0.05);
            _setVolumeFeedback(Icons.volume_down);
          }
          _dragAccumulator = 0;
        }
      },
      onVerticalDragEnd: (_) => _dragAccumulator = 0,
    );
  }
}
