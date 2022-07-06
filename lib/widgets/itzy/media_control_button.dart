import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../models/keys.dart';

class MediaControlButton extends StatelessWidget {
  const MediaControlButton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (PointerDownEvent event) {
        if (event.kind == PointerDeviceKind.mouse) {
          final events = <int, String>{
            kPrimaryMouseButton: VK.MEDIA_PLAY_PAUSE,
            kSecondaryMouseButton: VK.MEDIA_NEXT_TRACK,
            kMiddleMouseButton: VK.MEDIA_PREV_TRACK,
          };
          if (events.containsKey(event.buttons)) {
            WinKeys.single(events[event.buttons]!, KeySentMode.normal);
          }
        }
      },
      onPointerSignal: (PointerSignalEvent event) {
        if (event is PointerScrollEvent) {
          if (event.scrollDelta.dy < 0) {
            WinKeys.single(VK.VOLUME_UP, KeySentMode.normal);
          } else {
            WinKeys.single(VK.VOLUME_DOWN, KeySentMode.normal);
          }
        }
      },
      child: InkWell(
        onTap: () {},
        child: Icon(Icons.play_arrow, color: Colors.white),
      ),
    );
  }
}
