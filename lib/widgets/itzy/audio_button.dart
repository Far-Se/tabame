import 'dart:ui';

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
                if (event.buttons == kMiddleMouseButton) {
                  WinKeys.single(VK.VOLUME_MUTE, KeySentMode.normal);
                }
                if (event.buttons == kSecondaryMouseButton) {
                  // WinKeys.single(VK.VOLUME_MUTE, KeySentMode.normal);
                  Audio.switchDefaultDevice(AudioDeviceType.output);
                } else if (event.buttons == kPrimaryMouseButton) {
                  showModalBottomSheet<void>(
                    context: context,
                    anchorPoint: Offset(100, 200),
                    elevation: 0,
                    backgroundColor: Colors.transparent,
                    barrierColor: Colors.transparent,
                    constraints: BoxConstraints(maxWidth: 280),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    enableDrag: true,
                    isScrollControlled: true,
                    builder: (context) {
                      return BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                        child: FractionallySizedBox(
                          // padding: const EdgeInsets.only(top: 10),
                          heightFactor: 0.9,
                          child: Listener(
                            onPointerDown: (event) {
                              if (event.kind == PointerDeviceKind.mouse) {
                                if (event.buttons == kSecondaryMouseButton) {
                                  Navigator.pop(context);
                                }
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(2.0),
                              child: AudioBox(),
                            ),
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
