import 'dart:async';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';

import '../../../models/globals.dart';
import '../../../models/keys.dart';
import 'audio_box.dart';

class AudioButton extends StatefulWidget {
  const AudioButton({Key? key}) : super(key: key);

  @override
  State<AudioButton> createState() => _AudioButtonState();
}

class _AudioButtonState extends State<AudioButton> {
  late Timer timer;
  bool muteState = false;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(milliseconds: 1000), (Timer timer) async {
      muteState = await Audio.getMuteAudioDevice(AudioDeviceType.output);
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: double.maxFinite,
      child: Material(
        type: MaterialType.transparency,
        child: Listener(
          onPointerSignal: (PointerSignalEvent event) {
            if (event is PointerScrollEvent) {
              if (event.scrollDelta.dy < 0) {
                WinKeys.single(VK.VOLUME_UP, KeySentMode.normal);
              } else {
                WinKeys.single(VK.VOLUME_DOWN, KeySentMode.normal);
              }
            }
          },
          onPointerDown: (PointerDownEvent event) {
            if (event.kind == PointerDeviceKind.mouse) {
              if (event.buttons == kMiddleMouseButton) {
                WinKeys.single(VK.VOLUME_MUTE, KeySentMode.normal);
                muteState = !muteState;
                setState(() {});
              }
              if (event.buttons == kSecondaryMouseButton) {
                Audio.switchDefaultDevice(AudioDeviceType.output);
              } else if (event.buttons == kPrimaryMouseButton) {
                Globals.audioBoxVisible = true;
                showModalBottomSheet<void>(
                  context: context,
                  anchorPoint: const Offset(100, 200),
                  elevation: 0,
                  backgroundColor: Colors.transparent,
                  barrierColor: Colors.transparent,
                  constraints: const BoxConstraints(maxWidth: 280),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  enableDrag: true,
                  isScrollControlled: true,
                  builder: (BuildContext context) {
                    return BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                      child: FractionallySizedBox(
                        heightFactor: 0.85,
                        child: Listener(
                          onPointerDown: (PointerDownEvent event) {
                            if (event.kind == PointerDeviceKind.mouse) {
                              if (event.buttons == kSecondaryMouseButton) {
                                Navigator.pop(context);
                              }
                            }
                          },
                          child: const Padding(
                            padding: EdgeInsets.all(2.0),
                            child: AudioBox(),
                          ),
                        ),
                      ),
                    );
                  },
                ).whenComplete(() {
                  Globals.audioBoxVisible = false;
                });
              }
            }
          },
          child: InkWell(
            child: Tooltip(message: "Audio Control", child: Icon(muteState == false ? Icons.volume_up : Icons.volume_off)),
            onTap: () {},
          ),
        ),
      ),
    );
  }
}
