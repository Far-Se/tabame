import 'dart:async';

import 'package:flutter/material.dart';
import 'package:win32/win32.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/win32/mixed.dart';
import '../../../models/win32/win32.dart';
import '../../../models/window_watcher.dart';
import '../../quickmenu/task_bar.dart';

class FoobarButton extends StatefulWidget {
  const FoobarButton({super.key});

  @override
  State<FoobarButton> createState() => _FoobarButtonState();
}

final GlobalKey foobarKey = GlobalKey();

class _FoobarButtonState extends State<FoobarButton> {
  int lastAudioCount = 0;
  @override
  void initState() {
    super.initState();
    //timer each 1 second
    Timer.periodic(const Duration(milliseconds: 200), (Timer timer) {
      if (lastAudioCount == Caches.audioMixerExes.length) return;
      lastAudioCount = Caches.audioMixerExes.length;
      //print(Caches.audioMixerExes);
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: double.maxFinite,
      child: GestureDetector(
        onSecondaryTap: () async {
          final List<int> foobar = WindowWatcher.getFoobar();
          if (foobar[0] != 0) {
            SendMessage(foobar[0], AppCommand.appCommand, 0, AppCommand.mediaNexttrack);
          }
        },
        onLongPress: () async {
          final List<int> foobar = WindowWatcher.getFoobar();
          if (foobar[0] != 0) {
            Win32.closeWindow(foobar[0], forced: true);
          }
        },
        onTertiaryTapDown: (TapDownDetails e) async {
          final List<int> foobar = WindowWatcher.getFoobar();
          if (foobar[0] != 0) {
            SendMessage(foobar[0], AppCommand.appCommand, 0, AppCommand.mediaPrevioustrack);
          } else if (Boxes.pref.getString("FoobarLocation") != null) {
            WinUtils.open(Boxes.pref.getString("FoobarLocation") ?? "", userpowerShell: true);
          }
        },
        child: InkWell(
          key: foobarKey,
          onDoubleTap: () {
            if (Boxes.pref.getString("FoobarLocation") != null) {
              WinUtils.open(Boxes.pref.getString("FoobarLocation") ?? "", userpowerShell: true);
            }
          },
          onTap: () async {
            print(<List<Object>>[Caches.audioMixer, Caches.audioMixerExes]);
            final List<int> foobar = WindowWatcher.getFoobar();
            //bool pressed = false;
            if (foobar[0] != 0) {
              if (IsWindow(foobar[0]) != 0) {
                SendMessage(foobar[0], AppCommand.appCommand, 0, AppCommand.mediaPlayPause);
                // pressed = true;
              }
            }
            // if (!pressed && Boxes.pref.getString("FoobarLocation") != null) {
            //   WinUtils.open(Boxes.pref.getString("FoobarLocation") ?? "", userpowerShell: true);
            // }
          },
          child: Tooltip(
            message: "Foobar",
            child: SizedBox(
              width: 20,
              child: Caches.audioMixerExes.contains("foobar2000.exe")
                  ? Icon(Icons.multitrack_audio_sharp, color: Colors.amber[700])
                  : Image.asset('resources/foobar.png', scale: 1.8),
            ),
          ),
        ),
      ),
    );
  }
}
