import 'dart:async';

import 'package:flutter/material.dart';
import 'package:win32/win32.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/win32/mixed.dart';
import '../../../models/win32/win32.dart';
import '../../../models/window_watcher.dart';
import '../../quickmenu/task_bar.dart';
import 'package:tabame/widgets/widgets/custom_tooltip.dart';

class SpotifyButton extends StatefulWidget {
  const SpotifyButton({super.key});

  @override
  State<SpotifyButton> createState() => _SpotifyButtonState();
}

final GlobalKey spotifyKey = GlobalKey();

class _SpotifyButtonState extends State<SpotifyButton> with QuickMenuTriggers {
  int lastAudioCount = 0;
  @override
  void initState() {
    super.initState();
    QuickMenuFunctions.addListener(this);
    //timer each 1 second
    Timer.periodic(const Duration(milliseconds: 200), (Timer timer) {
      if (lastAudioCount == Caches.audioMixerExes.length) return;
      lastAudioCount = Caches.audioMixerExes.length;
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    QuickMenuFunctions.removeListener(this);
    super.dispose();
  }

  @override
  void onQuickActionExecute(String actionName) {
    if (actionName == "SpotifyButton") {
      _handleTap();
    }
  }

  Future<void> _handleTap() async {
    final List<int> spotify = WindowWatcher.getSpotify();
    if (spotify[0] != 0) {
      if (IsWindow(spotify[0]) != 0) {
        SendMessage(spotify[0], AppCommand.appCommand, 0, AppCommand.mediaPlayPause);
      }
    }
    if (mounted) setState(() {});
  }

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
          }
        },
        onLongPress: () async {
          final List<int> spotify = WindowWatcher.getSpotify();
          if (spotify[0] != 0) {
            Win32.closeWindow(spotify[0], forced: true);
          }
        },
        onTertiaryTapDown: (TapDownDetails e) async {
          final List<int> spotify = WindowWatcher.getSpotify();
          if (spotify[0] != 0) {
            SendMessage(spotify[0], AppCommand.appCommand, 0, AppCommand.mediaPrevioustrack);
          }
        },
        child: InkWell(
          key: spotifyKey,
          onDoubleTap: () {
            if (Boxes.pref.getString("SpotifyLocation") != null) {
              WinUtils.open(Boxes.pref.getString("SpotifyLocation") ?? "");
            }
          },
          onTap: _handleTap,
          child: CustomTooltip(
            message: "Spotify",
            child: SizedBox(
                width: 20,
                child: Caches.audioMixerExes.contains("Spotify.exe")
                    ? Icon(Icons.multitrack_audio_sharp, color: Colors.amber[700])
                    : const Icon(Icons.music_note)),
          ),
        ),
      ),
    );
  }
}
