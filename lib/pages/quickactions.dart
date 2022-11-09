import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';
import 'package:win32/win32.dart';

import '../models/classes/boxes.dart';
import '../models/globals.dart';
import '../models/util/quick_action_list.dart';
import '../models/win32/keys.dart';
import '../models/settings.dart';
import '../models/win32/imports.dart';
import '../models/win32/mixed.dart';
import '../models/win32/win32.dart';
import '../models/win32/window.dart';
import '../models/window_watcher.dart';
import '../widgets/widgets/mouse_scroll_widget.dart';

class QuickActionWidget extends StatefulWidget {
  final bool popup;
  const QuickActionWidget({Key? key, this.popup = false}) : super(key: key);
  @override
  QuickActionWidgetState createState() => QuickActionWidgetState();
}

double _currentVolumeLevel = 0;

class QuickActionWidgetState extends State<QuickActionWidget> {
  final List<QuickActions> quickActions = Boxes.quickActions;
  ScrollController controller = ScrollController();
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (quickActions.isEmpty) return Container(child: const Text("No Items, add from Settings!"));
    return Material(
      type: MaterialType.transparency,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 300),
        child: Listener(
          onPointerSignal: (PointerSignalEvent pointerSignal) {
            if (pointerSignal is PointerScrollEvent) {
              if (pointerSignal.scrollDelta.dy < 0) {
                controller.animateTo(controller.offset - 70, duration: const Duration(milliseconds: 200), curve: Curves.ease);
              } else {
                controller.animateTo(controller.offset + 70, duration: const Duration(milliseconds: 200), curve: Curves.ease);
              }
            }
          },
          child: SingleChildScrollView(
            controller: ScrollController(),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                ...List<Widget>.generate(quickActions.length, (int index) {
                  final QuickActions item = quickActions.elementAt(index);
                  if (item.type == "Quick Action") {
                    return InkWell(
                      onTap: () => executeQuickAction(int.tryParse(item.value) ?? 0),
                      child: ListItem(title: item.name),
                    );
                  } else if (item.type == "Set Volume") {
                    return InkWell(
                      onTap: () {
                        Audio.setVolume((int.tryParse(item.value) ?? 100).toDouble(), AudioDeviceType.output);
                        _currentVolumeLevel = (int.tryParse(item.value) ?? 100) / 100;
                        setState(() {});
                      },
                      child: ListItem(title: item.name),
                    );
                  } else if (item.type == "Send Keys") {
                    return InkWell(
                      onTap: () {
                        FocusScope.of(context).unfocus();
                        SetFocus(GetDesktopWindow());
                        Future<void>.delayed(const Duration(milliseconds: 200), () {
                          WinKeys.send(item.value);
                        });
                      },
                      child: ListItem(title: item.name),
                    );
                  } else if (item.type == "Run Command") {
                    return InkWell(
                      onTap: () async {
                        await WinUtils.runPowerShell(<String>[item.value]);
                      },
                      child: ListItem(title: item.name),
                    );
                  } else if (item.type == "Open") {
                    return InkWell(
                      onTap: () {
                        WinUtils.open(item.value, parseParamaters: true);
                      },
                      child: ListItem(title: item.name),
                    );
                  } else if (item.type == "Run Command") {
                    return InkWell(
                      onTap: () {
                        WinUtils.runPowerShell(<String>[item.value]);
                      },
                      child: ListItem(title: item.name),
                    );
                  } else if (item.type == "Spotify Controls") {
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        InkWell(
                          onTap: () => sendSpotifyMedia(AppCommand.mediaPrevioustrack),
                          child: const Padding(
                            padding: EdgeInsets.all(3.5),
                            child: SizedBox(width: 20, child: Icon(Icons.skip_previous_rounded, size: 22)),
                          ),
                        ),
                        InkWell(
                          onTap: () => sendSpotifyMedia(AppCommand.mediaPlayPause),
                          child: const Padding(
                            padding: EdgeInsets.all(3.5),
                            child: SizedBox(width: 20, child: Icon(Icons.play_arrow_rounded, size: 22)),
                          ),
                        ),
                        InkWell(
                          onTap: () => sendSpotifyMedia(AppCommand.mediaNexttrack),
                          child: const Padding(
                            padding: EdgeInsets.all(3.5),
                            child: SizedBox(width: 20, child: Icon(Icons.skip_next_rounded, size: 22)),
                          ),
                        ),
                        ListItem(title: item.name)
                      ],
                    );
                  } else if (item.type == "Audio Output Devices" || item.type == "Audio Input Devices") {
                    return QuickActionAudioDevice(item: item);
                  } else if (item.type == "Volume Slider") {
                    return VolumeSlider(
                      name: item.name,
                    );
                  }

                  return Container();
                }),
                if (!widget.popup) const ShowStandardQuickActions()
              ],
            ),
          ),
        ),
      ),
    );
  }

  sendSpotifyMedia(int type) {
    final List<int> spotify = WindowWatcher.getSpotify();
    if (spotify[0] != 0) {
      if (IsWindow(spotify[0]) != 0) {
        SendMessage(spotify[0], AppCommand.appCommand, 0, type);
      }
    } else {
      final List<int> winHWNDS = enumWindows();
      final List<int> allHWNDs = <int>[];
      if (winHWNDS.isEmpty) print("ENUM WINDS IS EMPTY");

      for (int hWnd in winHWNDS) {
        if (Win32.isWindowOnDesktop(hWnd) && Win32.getTitle(hWnd).isNotEmpty && hWnd != Win32.getMainHandle() && !<String>["PopupHost"].contains(Win32.getTitle(hWnd))) {
          allHWNDs.add(hWnd);
        }
      }
      for (int element in allHWNDs) {
        final Window winInfo = Window(element);

        if (winInfo.process.exe == "Spotify.exe") {
          SendMessage(winInfo.hWnd, AppCommand.appCommand, 0, type);
          break;
        }
      }
    }
  }

  executeQuickAction(int value) {
    switch (value) {
      case 0:
        WinUtils.moveDesktop(DesktopDirection.right);
        break;
      case 1:
        WinUtils.moveDesktop(DesktopDirection.left);
        break;
      case 2:
        WinUtils.toggleTaskbar();
        break;
      case 3:
        WinKeys.single(VK.VOLUME_MUTE, KeySentMode.normal);
        break;
      case 4:
        Audio.getMuteAudioDevice(AudioDeviceType.input).then((bool value) => Audio.setMuteAudioDevice(!value, AudioDeviceType.input));
        break;
      case 5:
        Globals.alwaysAwake = !Globals.alwaysAwake;
        WinUtils.alwaysAwakeRun(Globals.alwaysAwake);
        break;
      case 6:
        WinUtils.toggleDesktopFiles();
        break;
      case 7:
        WinUtils.toggleHiddenFiles();
        break;
      case 8:
        QuickMenuFunctions.toggleQuickMenu(visible: false);
        WinUtils.screenCapture().then((bool value) => WinUtils.startTabame(closeCurrent: false, arguments: "-interface -fancyshot"));
        break;
      default:
        break;
    }
  }
}

class ShowStandardQuickActions extends StatefulWidget {
  const ShowStandardQuickActions({Key? key}) : super(key: key);

  @override
  State<ShowStandardQuickActions> createState() => _ShowStandardQuickActionsState();
}

class _ShowStandardQuickActionsState extends State<ShowStandardQuickActions> {
  List<Widget> showWidgets = <Widget>[];
  Map<String, Widget> widgets = <String, Widget>{};
  @override
  void initState() {
    super.initState();
    widgets.addAll(quickActionsMap.map((String key, QuickAction value) => MapEntry<String, Widget>("$key", value.widget)));
    final List<String> showWidgetsNames = Boxes().topBarWidgets;
    final List<String> forbiddenButtons = <String>[
      "TaskManagerButton",
      "SpotifyButton",
      "MicMuteButton",
    ];
    for (String x in showWidgetsNames) {
      // if (x == "Deactivated:") break;
      if (forbiddenButtons.contains(x)) continue;
      if (widgets.containsKey(x)) {
        showWidgets.add(widgets[x]!);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: IconTheme(
        data: IconThemeData(
          size: 16,
          color: Theme.of(context).iconTheme.color,
        ),
        child: Column(
            children: List<Widget>.generate(showWidgets.length, (int i) {
          Debug.add(
              "QuickMenu: Topbar: ${widgets.entries.firstWhere((MapEntry<String, Widget> element) => element.value == showWidgets[i], orElse: () => MapEntry<String, Widget>("Null", Container())).key}");
          return Container(constraints: const BoxConstraints(maxWidth: 280, minHeight: 25), child: showWidgets[i]);
        })),
      ),
    );
  }
}

class QuickActionAudioDevice extends StatefulWidget {
  final QuickActions item;
  const QuickActionAudioDevice({Key? key, required this.item}) : super(key: key);
  @override
  QuickActionAudioDeviceState createState() => QuickActionAudioDeviceState();
}

class QuickActionAudioDeviceState extends State<QuickActionAudioDevice> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
        future: Future.wait(widget.item.type == "Audio Output Devices"
            ? <Future<dynamic>>[Audio.enumDevices(AudioDeviceType.output), Audio.getDefaultDevice(AudioDeviceType.output)]
            : <Future<dynamic>>[Audio.enumDevices(AudioDeviceType.input), Audio.getDefaultDevice(AudioDeviceType.input)]),
        builder: (BuildContext context, AsyncSnapshot<List<dynamic>> out) {
          if (!out.hasData) return Container();
          final List<AudioDevice>? devices = out.data![0];
          final AudioDevice defaultDevice = out.data![1];
          if (devices?.isEmpty ?? false) return Container();
          return Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ListItem(title: widget.item.name),
              const Divider(height: 1, thickness: 1),
              ...List<Widget>.generate(devices?.length ?? 0, (int index) {
                final AudioDevice device = devices!.elementAt(index);
                return InkWell(
                  onTap: () {
                    Audio.setDefaultDevice(
                      device.id,
                      console: globalSettings.audioConsole,
                      multimedia: globalSettings.audioMultimedia,
                      communications: globalSettings.audioCommunications,
                    ).then((int value) {
                      if (mounted) {
                        setState(() {});
                      }
                    });
                  },
                  child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      child: Row(
                        children: <Widget>[
                          if (defaultDevice.id == device.id) const Icon(Icons.check_rounded, size: 16),
                          Container(width: 230, child: Text(device.name, overflow: TextOverflow.fade, maxLines: 1, softWrap: false)),
                        ],
                      )),
                );
              }),
              const Divider(height: 1, thickness: 1),
            ],
          );
        });
  }
}

class VolumeSlider extends StatefulWidget {
  final String name;
  const VolumeSlider({Key? key, required this.name}) : super(key: key);
  @override
  VolumeSliderState createState() => VolumeSliderState();
}

class VolumeSliderState extends State<VolumeSlider> {
  @override
  void initState() {
    super.initState();
    Audio.getVolume(AudioDeviceType.output).then((double value) {
      _currentVolumeLevel = value;
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseScrollWidget(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
        child: Row(
          children: <Widget>[
            Text("${widget.name}: ${((_currentVolumeLevel * 100).toStringAsFixed(0)).padLeft(2, '0')}"),
            SliderTheme(
                data: Theme.of(context).sliderTheme.copyWith(
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7, elevation: 0),
                      minThumbSeparation: 0,
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 5.0),
                    ),
                child: Slider(
                    value: _currentVolumeLevel,
                    min: 0,
                    max: 1,
                    onChanged: (double e) {
                      Audio.setVolume(e, AudioDeviceType.output);
                      _currentVolumeLevel = e;
                      setState(() {});
                    })),
          ],
        ),
      ),
    );
  }
}

class ListItem extends StatelessWidget {
  const ListItem({
    Key? key,
    required this.title,
  }) : super(key: key);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4), child: Text(title));
  }
}
