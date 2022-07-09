import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';

class MicMuteButton extends StatefulWidget {
  const MicMuteButton({Key? key}) : super(key: key);

  @override
  State<MicMuteButton> createState() => _MicMuteButtonState();
}

class _MicMuteButtonState extends State<MicMuteButton> {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: Audio.getMuteAudioDevice(AudioDeviceType.input),
      initialData: false,
      builder: (context, snapshot) => SizedBox(
        width: 20,
        height: double.maxFinite,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () async {
              await Audio.setMuteAudioDevice(!(snapshot.data!), AudioDeviceType.input);
              setState(() {});
            },
            child: Tooltip(
              message: "Toggle Mic Mute",
              child: Icon(
                snapshot.data! == true ? Icons.mic_off : Icons.mic,
                color: snapshot.data! == true ? Colors.deepOrange : Theme.of(context).iconTheme.color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
