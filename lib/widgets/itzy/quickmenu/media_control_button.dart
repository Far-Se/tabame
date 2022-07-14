import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../models/keys.dart';

class MediaControlButton extends StatefulWidget {
  const MediaControlButton({Key? key}) : super(key: key);

  @override
  State<MediaControlButton> createState() => _MediaControlButtonState();
}

class _MediaControlButtonState extends State<MediaControlButton> {
  IconData icon = Icons.play_arrow;
  int timers = 0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: double.maxFinite,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () {},
          child: Listener(
            onPointerDown: (PointerDownEvent event) {
              if (event.kind == PointerDeviceKind.mouse) {
                final Map<int, String> events = <int, String>{
                  kPrimaryMouseButton: VK.MEDIA_PLAY_PAUSE,
                  kSecondaryMouseButton: VK.MEDIA_NEXT_TRACK,
                  kMiddleMouseButton: VK.MEDIA_PREV_TRACK,
                };
                final Map<int, IconData> iconButton = <int, IconData>{
                  kPrimaryMouseButton: Icons.skip_next,
                  kSecondaryMouseButton: Icons.fast_forward,
                  kMiddleMouseButton: Icons.fast_rewind
                };
                if (events.containsKey(event.buttons)) {
                  WinKeys.single(events[event.buttons]!, KeySentMode.normal);
                  icon = iconButton[event.buttons]!;
                }
                timers++;
                setState(() {});
                Timer(const Duration(seconds: 1), () {
                  timers--;
                  if (timers > 0) return;
                  setState(() {
                    icon = Icons.play_arrow;
                  });
                });
              }
            },
            onPointerSignal: (PointerSignalEvent event) {
              if (event is PointerScrollEvent) {
                if (event.scrollDelta.dy < 0) {
                  WinKeys.single(VK.VOLUME_UP, KeySentMode.normal);
                  icon = Icons.volume_up;
                } else {
                  WinKeys.single(VK.VOLUME_DOWN, KeySentMode.normal);
                  icon = Icons.volume_down;
                }
                setState(() {});
                Timer(const Duration(seconds: 1), () {
                  setState(() {
                    icon = Icons.play_arrow;
                  });
                });
              }
            },
            child: Tooltip(message: "Media Control", child: Icon(icon)),
          ),
        ),
      ),
    );
  }
}
