import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/globals.dart';
import '../../../models/settings.dart';
import '../../../models/util/quickmenu_modal.dart';
import '../../../models/win32/keys.dart';
import '../../widgets/quick_actions_item.dart';
import 'audio_modal.dart';

class AudioButton extends StatefulWidget {
  const AudioButton({super.key});

  @override
  State<AudioButton> createState() => _AudioButtonState();
}

class _AudioButtonState extends State<AudioButton> with QuickMenuTriggers {
  bool muteState = false;
  bool switchedDefaultDevice = false;

  static const double _kDragThreshold = 10.0;
  double _dragAccumulator = 0;
  IconData? _feedbackIcon;
  Timer? _feedbackTimer;

  void _setFeedbackIcon(IconData icon) {
    _feedbackTimer?.cancel();
    setState(() => _feedbackIcon = icon);
    _feedbackTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _feedbackIcon = null);
    });
  }

  void _handleVolumeDrag(DragUpdateDetails details) {
    _dragAccumulator += details.delta.dy;
    if (_dragAccumulator.abs() >= _kDragThreshold) {
      final bool isUp = _dragAccumulator < 0;
      WinKeys.single(isUp ? VK.VOLUME_UP : VK.VOLUME_DOWN, KeySentMode.normal);
      _dragAccumulator = 0;
      _setFeedbackIcon(isUp ? Icons.volume_up : Icons.volume_down);
    }
  }

  void _handleMute() {
    WinKeys.single(VK.VOLUME_MUTE, KeySentMode.normal);
    muteState = !muteState;
    _setFeedbackIcon(muteState ? Icons.volume_off : Icons.volume_up);
    setState(() {});
  }

  void _handleSwitchDevice() {
    Audio.switchDefaultDevice(
      AudioDeviceType.output,
      console: user.audioConsole,
      multimedia: user.audioMultimedia,
      communications: user.audioCommunications,
    );
    switchedDefaultDevice = true;
    _setFeedbackIcon(Icons.published_with_changes);
    setState(() {});
    Timer(const Duration(milliseconds: 1000), () {
      switchedDefaultDevice = false;
      if (!mounted) return;
      setState(() {});
    });
  }

  void _showAudioBox() {
    Globals.audioBoxVisible = true;
    showQuickMenuModal(
      context: context,
      child: const AudioBox(),
      whenComplete: () => Globals.audioBoxVisible = false,
    );
  }

  @override
  void initState() {
    super.initState();
    QuickMenuFunctions.addListener(this);
    Debug.add("QuickMenu: Topbar: AudioButton");
  }

  @override
  Future<void> onQuickMenuVisible(QuickMenuPage type, bool center) async {
    muteState = await Audio.getMuteAudioDevice(AudioDeviceType.output);
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void onQuickActionExecute(String actionName) {
    if (actionName == "Audio Control") {
      _showAudioBox();
    }
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    QuickMenuFunctions.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    IconData displayIcon;

    if (_feedbackIcon != null) {
      displayIcon = _feedbackIcon!;
    } else if (switchedDefaultDevice) {
      displayIcon = Icons.published_with_changes;
    } else {
      displayIcon = muteState == false ? Icons.volume_up : Icons.volume_off;
    }

    return QuickActionItem(
      message: "Audio Control",
      icon: Icon(displayIcon, size: 16),
      onTap: () {
        Globals.audioBoxVisible = true;
        showQuickMenuModal(
          context: context,
          child: const AudioBox(),
          whenComplete: () => Globals.audioBoxVisible = false,
        );
      },
      hoverColor: Theme.of(context).colorScheme.primary,
      onVerticalDragStart: (_) => _dragAccumulator = 0,
      onVerticalDragEnd: (_) => _dragAccumulator = 0,
      onVerticalDragUpdate: _handleVolumeDrag,
      onSecondaryTap: _handleSwitchDevice,
      onTertiaryTapDown: (_) => _handleMute(),
    );
  }
}
