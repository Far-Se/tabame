import 'dart:async';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/globals.dart';
import '../../../models/win32/keys.dart';
import '../../../models/settings.dart';
import 'widget_audio.dart';

class AudioButton extends StatefulWidget {
  const AudioButton({Key? key}) : super(key: key);

  @override
  State<AudioButton> createState() => _AudioButtonState();
}

class _AudioButtonState extends State<AudioButton> with QuickMenuTriggers {
  bool muteState = false;

  bool switchedDefaultDevice = false;

  @override
  void initState() {
    super.initState();
    QuickMenuFunctions.addListener(this);
    Debug.add("QuickMenu: Topbar: AudioButton");
  }

  @override
  Future<void> onQuickMenuShown(int type) async {
    muteState = await Audio.getMuteAudioDevice(AudioDeviceType.output);
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
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
                Audio.switchDefaultDevice(
                  AudioDeviceType.output,
                  console: globalSettings.audioConsole,
                  multimedia: globalSettings.audioMultimedia,
                  communications: globalSettings.audioCommunications,
                );
                switchedDefaultDevice = true;
                setState(() {});
                Timer(const Duration(milliseconds: 1000), () {
                  switchedDefaultDevice = false;
                  if (!mounted) return;
                  setState(() {});
                });
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
            child: switchedDefaultDevice
                ? const Tooltip(message: "Audio Channel Changed", child: Icon(Icons.published_with_changes))
                : Tooltip(message: "Audio Control", child: Icon(muteState == false ? Icons.volume_up : Icons.volume_off)),
            onTap: () {},
          ),
        ),
      ),
    );
  }
}
