import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';

class MicMuteButton extends StatefulWidget {
  const MicMuteButton({Key? key}) : super(key: key);

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
  Future<void> onQuickMenuShown(int type) async {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: Audio.getMuteAudioDevice(AudioDeviceType.input),
      initialData: false,
      builder: (BuildContext context, AsyncSnapshot<bool> snapshot) => SizedBox(
        width: 20,
        height: double.maxFinite,
        child: Material(
          type: MaterialType.transparency,
          child: GestureDetector(
            onSecondaryTap: () async {
              await Audio.switchDefaultDevice(
                AudioDeviceType.input,
                console: globalSettings.audioConsole,
                multimedia: globalSettings.audioMultimedia,
                communications: globalSettings.audioCommunications,
              );
              switchedDefaultDevice = true;
              setState(() {});
              Future<void>.delayed(const Duration(milliseconds: 1000), () {
                switchedDefaultDevice = false;
                if (!mounted) return;
                setState(() {});
              });
            },
            child: InkWell(
              onTap: () async {
                await Audio.setMuteAudioDevice(!(snapshot.data!), AudioDeviceType.input);
                setState(() {});
              },
              child: Tooltip(
                message: "Toggle Mic Mute",
                child: Icon(
                  switchedDefaultDevice ? Icons.published_with_changes : (snapshot.data! == true ? Icons.mic_off : Icons.mic),
                  color: snapshot.data! == true ? Colors.deepOrange : Theme.of(context).iconTheme.color,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
