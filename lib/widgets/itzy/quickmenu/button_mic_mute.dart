import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/globals.dart';
import '../../../models/settings.dart';
import '../../widgets/quick_actions_item.dart';

class MicMuteButton extends StatefulWidget {
  const MicMuteButton({super.key});

  @override
  State<MicMuteButton> createState() => MicMuteButtonState();
}

class MicMuteButtonState extends State<MicMuteButton> with QuickMenuTriggers {
  bool switchedDefaultDevice = false;
  @override
  void initState() {
    super.initState();
    QuickMenuFunctions.addListener(this);
  }

  @override
  void dispose() {
    QuickMenuFunctions.removeListener(this);
    super.dispose();
  }

  @override
  Future<void> onQuickMenuVisible(QuickMenuPage type, bool center) async {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: Audio.getMuteAudioDevice(AudioDeviceType.input),
      initialData: false,
      builder: (BuildContext context, AsyncSnapshot<bool> snapshot) => QuickActionItem(
        message: "Mic Mute",
        icon: Icon(
          switchedDefaultDevice ? Icons.published_with_changes : (snapshot.data! == true ? Icons.mic_off : Icons.mic),
          color: snapshot.data! == true ? Colors.deepOrange : Theme.of(context).iconTheme.color,
        ),
        onSecondaryTap: () async {
          await Audio.switchDefaultDevice(
            AudioDeviceType.input,
            console: userSettings.audioConsole,
            multimedia: userSettings.audioMultimedia,
            communications: userSettings.audioCommunications,
          );
          switchedDefaultDevice = true;
          setState(() {});
          Future<void>.delayed(const Duration(milliseconds: 1000), () {
            switchedDefaultDevice = false;
            if (!mounted) return;
            setState(() {});
          });
        },
      ),
    );
  }
}
