import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tabamewin32/tabamewin32.dart';
import 'package:win32/win32.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/classes/hotkeys.dart';
import '../../../models/classes/saved_maps.dart';
import '../../../models/globals.dart';
import '../../../models/settings.dart';
import '../../../models/tray_watcher.dart';
import '../../../models/util/quick_action_list.dart';
import '../../../models/util/quick_actions.dart';
import '../../../models/win32/keys.dart';
import '../../../models/win32/win_utils.dart';
import '../../../models/win32/window.dart';
import '../../../models/window_watcher.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/mouse_scroll_widget.dart';
import '../../widgets/quick_menu_panel.dart';

class QuickActionsMenuButton extends StatelessWidget {
  const QuickActionsMenuButton({super.key});
  @override
  Widget build(BuildContext context) {
    return ModalButton(
      actionName: "Quick Actions",
      icon: const Icon(Icons.app_registration_rounded),
      child: () => const QuickActionWidget(popup: false),
    );
  }
}

class QuickActionWidget extends StatefulWidget {
  final bool popup;
  const QuickActionWidget({super.key, this.popup = false});
  @override
  QuickActionWidgetState createState() => QuickActionWidgetState();
}

double _currentVolumeLevel = 0;

class QuickActionMenuEntry {
  const QuickActionMenuEntry({
    required this.id,
    required this.title,
    required this.searchTerms,
    required this.builder,
    this.onExecute,
    this.allowRenderedFallbackExecute = true,
  });

  final String id;
  final String title;
  final List<String> searchTerms;
  final WidgetBuilder builder;
  final VoidCallback? onExecute;
  final bool allowRenderedFallbackExecute;

  bool matches(String query) {
    final String normalizedQuery = query.toLowerCase().trim();
    if (normalizedQuery.isEmpty) return false;
    return searchTerms.any((String term) => term.toLowerCase().contains(normalizedQuery));
  }
}

List<QuickActionMenuEntry> buildQuickActionMenuEntries(
  BuildContext context, {
  VoidCallback? onStateChanged,
}) {
  final ThemeData theme = Theme.of(context);
  final Color accent = userSettings.themeColors.accentColor;
  final Color onSurface = theme.colorScheme.onSurface;
  final List<QuickActionMenuEntry> entries = <QuickActionMenuEntry>[];
  for (int index = 0; index < Boxes.quickActions.length; index++) {
    final QuickActions item = Boxes.quickActions[index];
    final QuickActionMenuEntry? entry = _buildCustomQuickActionEntry(
      context: context,
      item: item,
      index: index,
      accent: accent,
      onSurface: onSurface,
      onStateChanged: onStateChanged,
    );
    if (entry != null) {
      entries.add(entry);
    }
  }
  entries.addAll(
    <QuickActionMenuEntry>[
      QuickActionMenuEntry(
        id: "OpenFancyShotFolder",
        title: "Open FancyShot Screenshots folder",
        searchTerms: <String>["fancyshot", "screenshot"],
        onExecute: () => WinUtils.open('${WinUtils.getTabameAppDataFolder()}\\screenshots'),
        builder: (BuildContext context) {
          return _QuickActionListItem(
            name: "Open FancyShot Screenshots folder",
            accent: accent,
            onSurface: onSurface,
            leading: SizedBox(
              width: 18,
              child: Icon(Icons.open_in_browser, size: 14, color: onSurface),
            ),
            onTap: () => WinUtils.open('${WinUtils.getTabameAppDataFolder()}\\screenshots'),
          );
        },
      ),
    ],
  );
  entries.addAll(
    HotKeyInfo.tabameFunctionsMap.entries.where((MapEntry<String, dynamic> e) {
      return <String>[
        // "SwitchDesktopToRight",
        // "SwitchDesktopToLeft",
        "SwitchAudioOutput",
        // "ShowSecondWindowUnderCursor",
        // "ShowLastActiveWindow",
      ].contains(e.key);
    }).map((MapEntry<String, dynamic> e) {
      final String displayName =
          e.key.replaceAllMapped(RegExp(r"([A-Z])", caseSensitive: true), (Match m) => " ${m.group(1)}").trim();
      return QuickActionMenuEntry(
        id: "hotkey-${e.key}",
        title: displayName,
        searchTerms: <String>[displayName, e.key],
        onExecute: () => e.value(),
        builder: (BuildContext context) {
          return _QuickActionListItem(
            name: displayName,
            accent: accent,
            onSurface: onSurface,
            leading: SizedBox(
              width: 18,
              child: Icon(Icons.arrow_forward, size: 14, color: onSurface),
            ),
            onTap: () => e.value(),
          );
        },
      );
    }),
  );

  entries.addAll(_buildAppAudioControlEntries(accent: accent, onSurface: onSurface));
  entries.addAll(_buildStandardQuickActionEntries(accent: accent, onSurface: onSurface));
  return entries;
}

bool triggerFirstTappableDescendant(BuildContext? context) {
  if (context is! Element) return false;

  bool found = false;
  void search(Element element) {
    if (found) return;

    final Widget widget = element.widget;
    if (widget is InkWell && widget.onTap != null) {
      widget.onTap!.call();
      found = true;
      return;
    }
    if (widget is InkResponse && widget.onTap != null) {
      widget.onTap!.call();
      found = true;
      return;
    }
    if (widget is GestureDetector && widget.onTap != null) {
      widget.onTap!.call();
      found = true;
      return;
    }

    element.visitChildren(search);
  }

  search(context);
  return found;
}

QuickActionMenuEntry? _buildCustomQuickActionEntry({
  required BuildContext context,
  required QuickActions item,
  required int index,
  required Color accent,
  required Color onSurface,
  VoidCallback? onStateChanged,
}) {
  final List<String> searchTerms = <String>[item.name, item.type, item.value];
  if (item.type == "Quick Action") {
    final int actionIndex = int.tryParse(item.value) ?? 0;
    if (actionIndex >= 0 && actionIndex < quickActionsList.length) {
      searchTerms.add(quickActionsList[actionIndex]);
    }
    return QuickActionMenuEntry(
      id: "custom-$index",
      title: item.name,
      searchTerms: searchTerms,
      onExecute: () => executeQuickActionValue(actionIndex),
      builder: (BuildContext context) {
        return _QuickActionListItem(
          name: item.name,
          accent: accent,
          onSurface: onSurface,
          onTap: () => executeQuickActionValue(actionIndex),
        );
      },
    );
  } else if (item.type == "Set Volume") {
    return QuickActionMenuEntry(
      id: "custom-$index",
      title: item.name,
      searchTerms: searchTerms,
      onExecute: () {
        final double volume = (int.tryParse(item.value) ?? 100).toDouble();
        Audio.setVolume(volume, AudioDeviceType.output);
        _currentVolumeLevel = volume / 100;
        onStateChanged?.call();
      },
      builder: (BuildContext context) {
        return _QuickActionListItem(
          name: item.name,
          accent: accent,
          onSurface: onSurface,
          onTap: () {
            final double volume = (int.tryParse(item.value) ?? 100).toDouble();
            Audio.setVolume(volume, AudioDeviceType.output);
            _currentVolumeLevel = volume / 100;
            onStateChanged?.call();
          },
        );
      },
    );
  } else if (item.type == "Send Keys") {
    return QuickActionMenuEntry(
      id: "custom-$index",
      title: item.name,
      searchTerms: searchTerms,
      onExecute: () {
        FocusScope.of(context).unfocus();
        SetFocus(GetDesktopWindow());
        Future<void>.delayed(const Duration(milliseconds: 200), () {
          WinKeys.send(item.value);
        });
      },
      builder: (BuildContext context) {
        return _QuickActionListItem(
          name: item.name,
          accent: accent,
          onSurface: onSurface,
          onTap: () {
            FocusScope.of(context).unfocus();
            SetFocus(GetDesktopWindow());
            Future<void>.delayed(const Duration(milliseconds: 200), () {
              WinKeys.send(item.value);
            });
          },
        );
      },
    );
  } else if (item.type == "Run Command") {
    return QuickActionMenuEntry(
      id: "custom-$index",
      title: item.name,
      searchTerms: searchTerms,
      onExecute: () {
        WinUtils.runPowerShell(<String>[item.value]);
      },
      builder: (BuildContext context) {
        return _QuickActionListItem(
          name: item.name,
          accent: accent,
          onSurface: onSurface,
          onTap: () {
            WinUtils.runPowerShell(<String>[item.value]);
          },
        );
      },
    );
  } else if (item.type == "Open") {
    return QuickActionMenuEntry(
      id: "custom-$index",
      title: item.name,
      searchTerms: searchTerms,
      onExecute: () => WinUtils.open(item.value, parseParamaters: true),
      builder: (BuildContext context) {
        return _QuickActionListItem(
          name: item.name,
          accent: accent,
          onSurface: onSurface,
          onTap: () => WinUtils.open(item.value, parseParamaters: true),
        );
      },
    );
  } else if (item.type == "Audio Output Devices" || item.type == "Audio Input Devices") {
    return QuickActionMenuEntry(
      id: "custom-$index",
      title: item.name,
      searchTerms: searchTerms,
      allowRenderedFallbackExecute: false,
      builder: (BuildContext context) => QuickActionAudioDevice(item: item),
    );
  } else if (item.type == "Volume Slider") {
    return QuickActionMenuEntry(
      id: "custom-$index",
      title: item.name,
      searchTerms: <String>[...searchTerms, "volume", "slider"],
      allowRenderedFallbackExecute: false,
      builder: (BuildContext context) => VolumeSlider(name: item.name),
    );
  }

  return null;
}

List<QuickActionMenuEntry> _buildStandardQuickActionEntries({
  required Color accent,
  required Color onSurface,
}) {
  final Map<String, QuickAction> widgets = <String, QuickAction>{}..addAll(quickActionsMap);
  final List<String> showWidgetsNames = Boxes().topBarWidgets;
  final List<String> forbiddenButtons = <String>[
    "QuickActionsMenuButton",
    "AppAudioControl1",
    "AppAudioControl2",
    "AppAudioControl3",
    "AppAudioControl4",
    "AppAudioControl5",
  ];
  final List<QuickActionMenuEntry> entries = <QuickActionMenuEntry>[];

  for (final String widgetName in showWidgetsNames) {
    if (forbiddenButtons.contains(widgetName)) continue;
    final QuickAction? action = widgets[widgetName];
    if (action == null) continue;

    final String displayName =
        action.name.replaceAll("Button", "").replaceAllMapped(RegExp(r"([A-Z])"), (Match m) => " ${m.group(1)}").trim();
    entries.add(
      QuickActionMenuEntry(
        id: "standard-$widgetName",
        title: displayName,
        searchTerms: <String>[displayName, action.name, widgetName],
        builder: (BuildContext context) {
          final GlobalKey buttonKey = GlobalKey();
          return _QuickActionListItem(
            name: displayName,
            accent: accent,
            onSurface: onSurface,
            onTap: () {
              triggerFirstTappableDescendant(buttonKey.currentContext);
              if (displayName == "Quick Menu Design") {
                Globals.quickMenuPage = QuickMenuPage.quickMenu;
                QuickMenuFunctions.refreshQuickMenu();
              }
            },
            leading: SizedBox(
              width: 20,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: <Widget>[
                  Offstage(
                    offstage: true,
                    child: KeyedSubtree(
                      key: buttonKey,
                      child: IgnorePointer(child: action.widget()),
                    ),
                  ),
                  Icon(action.icon, size: 16, color: onSurface.withAlpha(190)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  return entries;
}

List<QuickActionMenuEntry> _buildAppAudioControlEntries({
  required Color accent,
  required Color onSurface,
}) {
  final List<QuickActionMenuEntry> entries = <QuickActionMenuEntry>[];
  for (int index = 0; index < Boxes.appAudioControls.length && index < 5; index++) {
    final AppAudioControl control = Boxes.appAudioControls[index];
    if (!_isConfiguredAppAudioControl(control)) continue;

    entries.add(
      QuickActionMenuEntry(
        id: "app-audio-$index",
        title: control.name.isEmpty ? "App Audio Control ${index + 1}" : control.name,
        searchTerms: <String>[
          control.name,
          control.exe,
          control.path,
          "App Audio Control ${index + 1}",
          "app audio",
          "media",
          "play",
          "pause",
        ],
        onExecute: () => handleAppAudioPlayPause(index),
        builder: (BuildContext context) {
          return _QuickActionListItem(
            name: control.name.isEmpty ? "App Audio Control ${index + 1}" : control.name,
            accent: accent,
            onSurface: onSurface,
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _CompactIconButton(
                  icon: Icons.skip_previous_rounded,
                  onTap: () => handleAppAudioPrevious(index),
                ),
                _CompactIconButton(
                  icon: Icons.play_arrow_rounded,
                  onTap: () => handleAppAudioPlayPause(index),
                ),
                _CompactIconButton(
                  icon: Icons.skip_next_rounded,
                  onTap: () => handleAppAudioNext(index),
                ),
                const SizedBox(width: 6),
              ],
            ),
            onTap: () => handleAppAudioPlayPause(index),
          );
        },
      ),
    );
  }
  return entries;
}

bool _isConfiguredAppAudioControl(AppAudioControl control) {
  return control.exe.trim().isNotEmpty || control.path.trim().isNotEmpty;
}

({int pid, int hWnd})? _getAppAudioWindow(int index) {
  if (index >= Boxes.appAudioControls.length) return null;
  final AppAudioControl control = Boxes.appAudioControls[index];

  for (final Window win in WindowWatcher.list) {
    if (win.process.exe == control.exe) {
      return (hWnd: win.hWnd, pid: win.process.pId);
    }
  }

  for (final TrayBarInfo tray in Tray.trayList) {
    if (tray.processExe == control.exe) {
      return (hWnd: tray.hWnd, pid: tray.processID);
    }
  }
  return null;
}

void handleAppAudioNext(int index) {
  if (index >= Boxes.appAudioControls.length) return;
  final AppAudioControl control = Boxes.appAudioControls[index];
  final ({int hWnd, int pid})? window = _getAppAudioWindow(index);
  if (window == null) {
    WinKeys.single(VK.MEDIA_NEXT_TRACK, KeySentMode.normal);
  } else {
    WinKeys.send(control.hotkeyNext);
  }
}

void handleAppAudioPrevious(int index) {
  if (index >= Boxes.appAudioControls.length) return;
  final AppAudioControl control = Boxes.appAudioControls[index];
  final ({int hWnd, int pid})? window = _getAppAudioWindow(index);
  if (window == null) {
    WinKeys.single(VK.MEDIA_PREV_TRACK, KeySentMode.normal);
  } else {
    WinKeys.send(control.hotkeyPrev);
  }
}

void handleAppAudioPlayPause(int index) {
  if (index >= Boxes.appAudioControls.length) return;
  final AppAudioControl control = Boxes.appAudioControls[index];
  final ({int hWnd, int pid})? window = _getAppAudioWindow(index);
  if (window == null) {
    WinKeys.single(VK.MEDIA_PLAY_PAUSE, KeySentMode.normal);
  } else {
    WinKeys.send(control.hotkeyPause);
  }
}

void executeQuickActionValue(int value) {
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
      Audio.getMuteAudioDevice(AudioDeviceType.input)
          .then((bool value) => Audio.setMuteAudioDevice(!value, AudioDeviceType.input));
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
      WinUtils.screenCapture()
          .then((bool value) => WinUtils.startTabame(closeCurrent: false, arguments: "-interface -fancyshot"));
      break;
    default:
      break;
  }
}

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
    final ThemeData theme = Theme.of(context);
    final Color accent = userSettings.themeColors.accentColor;

    final List<QuickActionMenuEntry> entries = buildQuickActionMenuEntries(
      context,
      onStateChanged: () {
        if (mounted) {
          setState(() {});
        }
      },
    );

    return QuickMenuPanel(
      title: "Quick Actions",
      accent: accent,
      icon: Icons.grid_view_rounded,
      body: entries.isEmpty
          ? Container(
              constraints: const BoxConstraints(maxHeight: 200, minWidth: 260),
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(Icons.grid_off_rounded, size: 32, color: accent.withAlpha(100)),
                  const SizedBox(height: 12),
                  Text(
                    "No items yet. Add them from Settings.",
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              controller: controller,
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  ...entries.map((QuickActionMenuEntry entry) => entry.builder(context)),
                ],
              ),
            ),
    );
  }
}

class ShowStandardQuickActions extends StatefulWidget {
  const ShowStandardQuickActions({super.key, required this.accent, required this.onSurface});

  final Color accent;
  final Color onSurface;

  @override
  State<ShowStandardQuickActions> createState() => _ShowStandardQuickActionsState();
}

class _ShowStandardQuickActionsState extends State<ShowStandardQuickActions> {
  List<QuickAction> activeActions = <QuickAction>[];
  Map<String, QuickAction> widgets = <String, QuickAction>{};
  @override
  void initState() {
    super.initState();
    widgets.addAll(quickActionsMap);
    final List<String> showWidgetsNames = Boxes().topBarWidgets;
    final List<String> forbiddenButtons = <String>[
      "QuickActionsMenuButton",
      "AppAudioControl1",
      "AppAudioControl2",
      "AppAudioControl3",
      "AppAudioControl4",
      "AppAudioControl5",
    ];
    for (String x in showWidgetsNames) {
      if (forbiddenButtons.contains(x)) continue;
      if (widgets.containsKey(x)) {
        activeActions.add(widgets[x]!);
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
          color: Theme.of(context).colorScheme.onSurface,
        ),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            children: List<Widget>.generate(activeActions.length, (int i) {
              final QuickAction action = activeActions[i];
              String displayName = action.name
                  .replaceAll("Button", "")
                  .replaceAllMapped(RegExp(r"([A-Z])"), (Match m) => " ${m.group(1)}")
                  .trim();
              final GlobalKey buttonKey = GlobalKey();
              return _QuickActionListItem(
                name: displayName,
                accent: userSettings.themeColors.accentColor,
                onSurface: widget.onSurface,
                onTap: () {
                  triggerFirstTappableDescendant(buttonKey.currentContext);
                },
                leading: Container(
                  constraints: const BoxConstraints(maxWidth: 30, maxHeight: 30),
                  child: KeyedSubtree(
                    key: buttonKey,
                    child: IgnorePointer(child: action.widget()),
                  ),
                ),
              );
            })),
      ),
    );
  }
}

class QuickActionAudioDevice extends StatefulWidget {
  final QuickActions item;
  const QuickActionAudioDevice({super.key, required this.item});
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
            ? <Future<dynamic>>[
                Audio.enumDevices(AudioDeviceType.output),
                Audio.getDefaultDevice(AudioDeviceType.output)
              ]
            : <Future<dynamic>>[
                Audio.enumDevices(AudioDeviceType.input),
                Audio.getDefaultDevice(AudioDeviceType.input)
              ]),
        builder: (BuildContext context, AsyncSnapshot<List<dynamic>> out) {
          if (!out.hasData) return Container();
          final Color accent = userSettings.themeColors.accentColor;
          final Color onSurface = Theme.of(context).colorScheme.onSurface;
          final List<AudioDevice>? devices = out.data![0];
          final AudioDevice defaultDevice = out.data![1];
          if (devices?.isEmpty ?? false) return Container();
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _QuickActionListItem(
                name: widget.item.name,
                accent: accent,
                onSurface: onSurface,
              ),
              ...List<Widget>.generate(devices?.length ?? 0, (int index) {
                final AudioDevice device = devices!.elementAt(index);
                return _QuickActionListItem(
                  name: device.name,
                  accent: accent,
                  onSurface: onSurface,
                  dense: true,
                  leading: SizedBox(
                    width: 18,
                    child: defaultDevice.id == device.id ? Icon(Icons.check_rounded, size: 14, color: accent) : null,
                  ),
                  onTap: () {
                    Audio.setDefaultDevice(
                      device.id,
                      console: userSettings.audioConsole,
                      multimedia: userSettings.audioMultimedia,
                      communications: userSettings.audioCommunications,
                    ).then((int value) {
                      if (mounted) {
                        setState(() {});
                      }
                    });
                  },
                );
              }),
            ],
          );
        });
  }
}

class VolumeSlider extends StatefulWidget {
  final String name;
  const VolumeSlider({super.key, required this.name});
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
    final ThemeData theme = Theme.of(context);
    final Color accent = userSettings.themeColors.accentColor;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    return MouseScrollWidget(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: accent.withAlpha(10),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: <Widget>[
                Text(
                  "${widget.name}: ${((_currentVolumeLevel * 100).toStringAsFixed(0)).padLeft(2, '0')}",
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: onSurface.withAlpha(205),
                  ),
                ),
                SliderTheme(
                    data: Theme.of(context).sliderTheme.copyWith(
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7, elevation: 0),
                          minThumbSeparation: 0,
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 5.0),
                          trackHeight: 3,
                          activeTrackColor: accent,
                          thumbColor: accent,
                        ),
                    child: Expanded(
                      child: Slider(
                          value: _currentVolumeLevel,
                          min: 0,
                          max: 1,
                          onChanged: (double e) {
                            Audio.setVolume(e, AudioDeviceType.output);
                            _currentVolumeLevel = e;
                            setState(() {});
                          }),
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ListItem extends StatelessWidget {
  const ListItem({
    super.key,
    required this.title,
  });

  final String title;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color onSurface = theme.colorScheme.onSurface;
    return Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodyMedium?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.1,
        color: onSurface.withAlpha(200),
      ),
    );
  }
}

class _QuickActionListItem extends StatefulWidget {
  const _QuickActionListItem({
    required this.name,
    required this.accent,
    required this.onSurface,
    this.onTap,
    this.leading,
    this.dense = false,
  });

  final String name;
  final Color accent;
  final Color onSurface;
  final VoidCallback? onTap;
  final Widget? leading;
  final bool dense;

  @override
  State<_QuickActionListItem> createState() => _QuickActionListItemState();
}

class _QuickActionListItemState extends State<_QuickActionListItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (PointerHoverEvent event) {
        if (event.delta != Offset.zero) {
          setState(() => _hovered = true);
        }
      },
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: _hovered ? userSettings.themeColors.accentColor.withAlpha(60) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: GestureDetector(
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: widget.onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: widget.dense ? 5 : 6),
              child: Row(
                children: <Widget>[
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: _hovered ? 2.5 : 0,
                    height: 14,
                    margin: EdgeInsets.only(right: _hovered ? 7 : 0),
                    decoration: BoxDecoration(
                      color: userSettings.themeColors.accentColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  if (widget.leading != null) ...<Widget>[
                    widget.leading!,
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      widget.name,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: _hovered ? widget.onSurface : widget.onSurface.withAlpha(200),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactIconButton extends StatelessWidget {
  const _CompactIconButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color accent = userSettings.themeColors.accentColor;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Material(
        color: accent.withAlpha(22),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            width: 28,
            height: 28,
            child: Icon(icon, size: 18, color: onSurface.withAlpha(190)),
          ),
        ),
      ),
    );
  }
}
