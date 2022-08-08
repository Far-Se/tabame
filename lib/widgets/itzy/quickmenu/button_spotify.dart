import 'package:flutter/material.dart';
import 'package:win32/win32.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/win32/mixed.dart';
import '../../../models/win32/win32.dart';
import '../../../models/window_watcher.dart';

class SpotifyButton extends StatefulWidget {
  const SpotifyButton({Key? key}) : super(key: key);

  @override
  State<SpotifyButton> createState() => _SpotifyButtonState();
}

final GlobalKey spotifyKey = GlobalKey();

class _SpotifyButtonState extends State<SpotifyButton> {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: double.maxFinite,
      child: GestureDetector(
        onSecondaryTap: () async {
          final List<int> spotify = WindowWatcher.getSpotify();
          if (spotify[0] != 0) {
            SendMessage(spotify[0], AppCommand.appCommand, 0, AppCommand.mediaNexttrack);
            RenderBox box = spotifyKey.currentContext?.findRenderObject() as RenderBox;
            Offset position = box.localToGlobal(Offset.zero);

            WidgetsBinding.instance.handlePointerEvent(PointerDownEvent(
              pointer: 0,
              position: position,
            ));
            WidgetsBinding.instance.handlePointerEvent(PointerUpEvent(
              pointer: 0,
              position: position,
            ));
            SendMessage(spotify[0], AppCommand.appCommand, 0, AppCommand.mediaPlay);
          }
        },
        onTertiaryTapUp: (TapUpDetails e) async {
          final List<int> spotify = WindowWatcher.getSpotify();
          if (spotify[0] != 0) {
            Win32.closeWindow(spotify[0], forced: true);
          }
        },
        child: InkWell(
          key: spotifyKey,
          onTap: () async {
            final List<int> spotify = WindowWatcher.getSpotify();
            bool pressed = false;
            if (spotify[0] != 0) {
              if (IsWindow(spotify[0]) != 0) {
                SendMessage(spotify[0], AppCommand.appCommand, 0, AppCommand.mediaPlayPause);
                pressed = true;
              }
            }
            if (!pressed && Boxes.pref.getString("SpotifyLocation") != null) {
              WinUtils.open(Boxes.pref.getString("SpotifyLocation") ?? "");
            }
          },
          child: const Tooltip(message: "Spotify", child: Icon(Icons.music_note)),
        ),
      ),
    );
  }
}
