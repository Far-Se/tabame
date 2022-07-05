import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';

import '../../models/keys.dart';
import 'audio_box.dart';

class AudioButton extends StatelessWidget {
  const AudioButton({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Align(
      child: SizedBox(
        width: 25,
        child: Material(
          type: MaterialType.transparency,
          child: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                if (event.scrollDelta.dy < 0) {
                  WinKeys.single(VK.VOLUME_UP, KeySentMode.normal);
                } else {
                  WinKeys.single(VK.VOLUME_DOWN, KeySentMode.normal);
                }
              }
            },
            onPointerDown: (event) {
              if (event.kind == PointerDeviceKind.mouse) {
                if (event.buttons == kSecondaryMouseButton) {
                  // WinKeys.single(VK.VOLUME_MUTE, KeySentMode.normal);
                  Audio.switchDefaultDevice(AudioDeviceType.output);
                } else if (event.buttons == kPrimaryMouseButton) {
                  showModalBottomSheet<void>(
                    context: context,
                    anchorPoint: Offset(100, 200),
                    elevation: 1,
                    backgroundColor: Colors.transparent,
                    barrierColor: Colors.transparent,
                    constraints: BoxConstraints(maxWidth: 280),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    enableDrag: false,
                    isScrollControlled: true,
                    builder: (context) {
                      return FractionallySizedBox(
                        heightFactor: 0.8,
                        child: Padding(
                          padding: const EdgeInsets.all(2.0),
                          child: Container(
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                            child: AudioBox(),
                          ),
                        ),
                      );
                    },
                  );
                }
              }
            },
            child: InkWell(
              child: Icon(Icons.volume_down, color: Colors.white),
              onTap: () {},
            ),
          ),
        ),
      ),
    );
  }
}
