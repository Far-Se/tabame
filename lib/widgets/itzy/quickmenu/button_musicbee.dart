import 'package:flutter/material.dart';
import 'package:win32/win32.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/win32/mixed.dart';
import '../../../models/win32/win32.dart';
import '../../../models/window_watcher.dart';

class MusicBeeButton extends StatefulWidget {
  const MusicBeeButton({super.key});

  @override
  State<MusicBeeButton> createState() => _MusicBeeButtonState();
}

final GlobalKey musicBeeKey = GlobalKey();

class _MusicBeeButtonState extends State<MusicBeeButton> {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: double.maxFinite,
      child: GestureDetector(
        onSecondaryTap: () async {
          final List<int> musicBee = WindowWatcher.getMusicBee();
          if (musicBee[0] != 0) {
            SendMessage(musicBee[0], AppCommand.appCommand, 0, AppCommand.mediaNexttrack);
          }
        },
        onLongPress: () async {
          final List<int> musicBee = WindowWatcher.getMusicBee();
          if (musicBee[0] != 0) {
            Win32.closeWindow(musicBee[0], forced: true);
          }
        },
        onTertiaryTapDown: (TapDownDetails e) async {
          final List<int> musicBee = WindowWatcher.getMusicBee();
          if (musicBee[0] != 0) {
            SendMessage(musicBee[0], AppCommand.appCommand, 0, AppCommand.mediaPrevioustrack);
          }
        },
        child: InkWell(
          key: musicBeeKey,
          onDoubleTap: () {
            if (Boxes.pref.getString("MusicBeeLocation") != null) {
              WinUtils.open(Boxes.pref.getString("MusicBeeLocation") ?? "", userpowerShell: true);
            }
          },
          onTap: () async {
            final List<int> musicBee = WindowWatcher.getMusicBee();
            bool pressed = false;
            if (musicBee[0] != 0) {
              if (IsWindow(musicBee[0]) != 0) {
                SendMessage(musicBee[0], AppCommand.appCommand, 0, AppCommand.mediaPlayPause);
                pressed = true;
              }
            }
            if (!pressed && Boxes.pref.getString("MusicBeeLocation") != null) {
              WinUtils.open(Boxes.pref.getString("MusicBeeLocation") ?? "", userpowerShell: true);
            }
          },
          child: Tooltip(message: "MusicBee", child: Image.asset('resources/musicbee.png', scale: 1.8)),
        ),
      ),
    );
  }
}
