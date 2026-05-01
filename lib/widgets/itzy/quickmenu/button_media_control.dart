import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/win32/keys.dart';
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

  void _applyKey(String key, IconData feedbackIcon) {
    WinKeys.single(key, KeySentMode.normal);
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
      message: "Media Control",
      icon: Icon(icon, size: 16),
      onTap: () => _applyKey(VK.MEDIA_PLAY_PAUSE, Icons.play_circle_outline),
      onSecondaryTap: () => _applyKey(VK.MEDIA_NEXT_TRACK, Icons.fast_forward),
      onTertiaryTapDown: (_) => _applyKey(VK.MEDIA_PREV_TRACK, Icons.fast_rewind),
      onVerticalDragStart: (_) => _dragAccumulator = 0,
      onVerticalDragUpdate: (DragUpdateDetails details) {
        _dragAccumulator -= details.delta.dy;
        if (_dragAccumulator.abs() > 10) {
          if (_dragAccumulator > 0) {
            _applyKey(VK.VOLUME_UP, Icons.volume_up);
          } else {
            _applyKey(VK.VOLUME_DOWN, Icons.volume_down);
          }
          _dragAccumulator = 0;
        }
      },
      onVerticalDragEnd: (_) => _dragAccumulator = 0,
    );
  }
}
