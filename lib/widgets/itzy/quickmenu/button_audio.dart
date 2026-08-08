import 'dart:async';

import 'package:flutter/material.dart';

import '../../../platform/audio_system_service.dart';
import '../../../models/classes/boxes.dart';
import '../../../models/globals.dart';
import '../../../models/settings.dart';
import '../../../models/util/quickmenu_modal.dart';
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
      unawaited(AudioSystemService.instance.adjustVolume(AudioDeviceType.output, isUp ? 0.05 : -0.05));
      _dragAccumulator = 0;
      _setFeedbackIcon(isUp ? Icons.volume_up : Icons.volume_down);
    }
  }

  Future<void> _handleMute() async {
    final bool success =
        await AudioOrchestrator(service: AudioSystemService.instance).toggleMute(AudioDeviceType.output);
    if (!success || !mounted) return;
    muteState = !muteState;
    _setFeedbackIcon(muteState ? Icons.volume_off : Icons.volume_up);
    setState(() {});
  }

  Future<void> _handleSwitchDevice() async {
    await AudioSystemService.instance.switchDefaultDevice(
      AudioDeviceType.output,
      targeting: AudioDeviceTargeting(
        console: user.audioConsole,
        multimedia: user.audioMultimedia,
        communications: user.audioCommunications,
      ),
    );
    if (!mounted) return;
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
    unawaited(_initializeAudio());
    Debug.add("QuickMenu: Topbar: AudioButton");
  }

  Future<void> _initializeAudio() async {
    await AudioSystemService.instance.initialize();
    if (mounted) setState(() {});
  }

  @override
  Future<void> onQuickMenuVisible(QuickMenuPage type, bool center) async {
    await AudioSystemService.instance.initialize();
    muteState = await AudioSystemService.instance.getMute(AudioDeviceType.output);
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
    final AudioSystemService service = AudioSystemService.instance;
    if (!service.isAvailable) {
      return QuickActionItem(
        message: service.unavailableReason,
        icon: const Icon(Icons.volume_off_rounded, size: 16),
      );
    }

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
