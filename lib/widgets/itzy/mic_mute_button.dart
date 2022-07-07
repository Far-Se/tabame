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
      builder: (context, snapshot) => Align(
        child: SizedBox(
          width: 25,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: () async {
                await Audio.setMuteAudioDevice(!(snapshot.data!), AudioDeviceType.input);
                await Audio.getMuteAudioDevice(AudioDeviceType.input);
                setState(() {});
              },
              child: Icon(
                snapshot.data! == true ? Icons.mic_off : Icons.mic,
                color: snapshot.data! == true ? Colors.deepOrange : Colors.white,
                // shadows: [Shadow(blurRadius: 0, color: Colors.white, offset: Offset(0.2, 0.2))],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
