// ignore_for_file: public_member_api_docs, sort_constructors_first

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'package:tabamewin32/tabamewin32.dart';
import 'package:win32/win32.dart';

import '../../main.dart';
import '../../models/classes/boxes.dart';
import '../../models/settings.dart';
import '../../models/win32/win32.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  SettingsPageState createState() => SettingsPageState();
}

class SettingsPageState extends State<SettingsPage> {
  final WizardlyContextMenu wizardlyContextMenu = WizardlyContextMenu();

  @override
  Widget build(BuildContext context) {
    final bool runOnStartup = WinUtils.checkIfRegisterAsStartup();
    if (!runOnStartup) globalSettings.runAsAdministrator = false;
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(10),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) => ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight,
                maxWidth: constraints.maxWidth,
                minHeight: constraints.minHeight,
                minWidth: constraints.minWidth,
              ),
              child: Material(
                type: MaterialType.transparency,
                child: ListTileTheme(
                  data: Theme.of(context).listTileTheme.copyWith(
                        dense: true,
                        style: ListTileStyle.drawer,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                        minVerticalPadding: 0,
                        visualDensity: VisualDensity.compact,
                        horizontalTitleGap: 0,
                      ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Expanded(
                        flex: 2,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: constraints.maxHeight,
                            maxWidth: constraints.maxWidth,
                            minHeight: constraints.minHeight,
                            minWidth: constraints.minWidth,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              const ListTile(title: Text("General Settings")),
                              CheckboxListTile(
                                controlAffinity: ListTileControlAffinity.leading,
                                title: const Text("Run on Startup"),
                                value: runOnStartup,
                                onChanged: (bool? newValue) async {
                                  if (newValue == true) {
                                    await setStartOnSystemStartup(true);
                                  } else {
                                    await setStartOnSystemStartup(false);
                                    globalSettings.runAsAdministrator = false;
                                    await Boxes.updateSettings("runAsAdministrator", newValue);
                                  }
                                  if (!mounted) return;
                                  setState(() {});
                                },
                              ),
                              if (runOnStartup)
                                CheckboxListTile(
                                  controlAffinity: ListTileControlAffinity.leading,
                                  title: const Text("Run as Administrator"),
                                  subtitle: const Text("Some apps require Admin Privileges to close or focus or to control the TrayIcon"),
                                  contentPadding: const EdgeInsets.all(10) - const EdgeInsets.only(right: 20),
                                  secondary: !globalSettings.runAsAdministrator
                                      ? null
                                      : (WinUtils.isAdministrator()
                                          ? null
                                          : Tooltip(
                                              message: "Restart as Admin",
                                              verticalOffset: 20,
                                              child: SizedBox(
                                                width: 30,
                                                height: double.infinity,
                                                child: InkWell(
                                                  splashColor: Theme.of(context).colorScheme.secondary,
                                                  hoverColor: Theme.of(context).colorScheme.secondary,
                                                  onTap: () {
                                                    WinUtils.run(Platform.resolvedExecutable);
                                                    int hWnd = Win32.findWindow("Tabame");
                                                    if (hWnd != 0) Win32.closeWindow(hWnd);
                                                    Future<void>.delayed(const Duration(milliseconds: 300), () => exit(0));
                                                  },
                                                  child: const Icon(Icons.replay_outlined),
                                                ),
                                              ),
                                            )),
                                  value: globalSettings.runAsAdministrator,
                                  onChanged: (bool? newValue) async {
                                    newValue ??= false;
                                    // await setStartOnStartupAsAdmin(newValue);
                                    await setStartOnSystemStartup(false);
                                    if (newValue == true) {
                                      await setStartOnSystemStartup(true, args: "-strudel");
                                    } else {
                                      await setStartOnSystemStartup(true);
                                    }
                                    globalSettings.runAsAdministrator = newValue;
                                    await Boxes.updateSettings("runAsAdministrator", newValue);
                                    if (!mounted) return;
                                    setState(() {});
                                  },
                                ),
                              CheckboxListTile(
                                controlAffinity: ListTileControlAffinity.leading,
                                title: const Text("Hide Taskbar on Startup"),
                                value: globalSettings.hideTaskbarOnStartup,
                                onChanged: (bool? newValue) async {
                                  globalSettings.hideTaskbarOnStartup = newValue ?? true;
                                  Boxes.updateSettings("hideTaskbarOnStartup", globalSettings.hideTaskbarOnStartup);
                                  if (!mounted) return;
                                  setState(() {});
                                },
                              ),
                              RadioTheme(
                                data: Theme.of(context).radioTheme.copyWith(visualDensity: VisualDensity.compact, splashRadius: 20),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.max,
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: <Widget>[
                                    const ListTile(title: Text("Volume OSD Style")),
                                    RadioListTile<VolumeOSDStyle>(
                                      title: const Text('Normal Volume OSD'),
                                      value: VolumeOSDStyle.normal,
                                      groupValue: globalSettings.volumeOSDStyle,
                                      onChanged: (VolumeOSDStyle? value) => setVolumeOSDStyle(value),
                                    ),
                                    RadioListTile<VolumeOSDStyle>(
                                      title: const Text('Hide Media'),
                                      value: VolumeOSDStyle.media,
                                      groupValue: globalSettings.volumeOSDStyle,
                                      onChanged: (VolumeOSDStyle? value) => setVolumeOSDStyle(value),
                                    ),
                                    RadioListTile<VolumeOSDStyle>(
                                      title: const Text('Thin'),
                                      value: VolumeOSDStyle.thin,
                                      groupValue: globalSettings.volumeOSDStyle,
                                      onChanged: (VolumeOSDStyle? value) => setVolumeOSDStyle(value),
                                    ),
                                    RadioListTile<VolumeOSDStyle>(
                                      title: const Text('Hidden'),
                                      value: VolumeOSDStyle.visible,
                                      groupValue: globalSettings.volumeOSDStyle,
                                      onChanged: (VolumeOSDStyle? value) => setVolumeOSDStyle(value),
                                    ),
                                  ],
                                ),
                              ),
                              ListTile(
                                  leading: Container(height: double.infinity, child: const Icon(Icons.wallpaper)),
                                  title: Text("Wallpaper", style: Theme.of(context).textTheme.bodyMedium),
                                  subtitle: Text(
                                    "This window will freeze for a bit.",
                                    style: TextStyle(fontStyle: FontStyle.italic, color: Theme.of(context).colorScheme.secondary),
                                  )),
                              Flexible(
                                fit: FlexFit.loose,
                                child: Row(
                                  children: <Widget>[
                                    Flexible(
                                      fit: FlexFit.loose,
                                      child: ListTile(
                                        onTap: () async {
                                          await toggleMonitorWallpaper(true);
                                        },
                                        leading: Container(height: double.infinity, child: const Icon(Icons.collections)),
                                        title: Text(
                                          "Enable Wallpaper",
                                          style: TextStyle(color: Theme.of(context).colorScheme.secondary),
                                        ),
                                      ),
                                    ),
                                    Flexible(
                                      fit: FlexFit.loose,
                                      child: ListTile(
                                        onTap: () async {
                                          await toggleMonitorWallpaper(false);
                                          await setWallpaperColor(0x00000000);
                                        },
                                        leading: Container(height: double.infinity, child: const Icon(Icons.format_color_fill)),
                                        title: Text(
                                          "Change to Black",
                                          style: TextStyle(color: Theme.of(context).colorScheme.secondary),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: constraints.maxHeight,
                            maxWidth: constraints.maxWidth,
                            minHeight: constraints.minHeight,
                            minWidth: constraints.minWidth,
                          ),
                          child: Column(
                            children: <Widget>[
                              RadioTheme(
                                data: Theme.of(context).radioTheme.copyWith(visualDensity: VisualDensity.compact, splashRadius: 20),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.max,
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: <Widget>[
                                    const ListTile(title: Text("Set Theme")),
                                    RadioListTile<ThemeType>(
                                      title: const Text("System Theme"),
                                      value: ThemeType.system,
                                      groupValue: globalSettings.themeType,
                                      onChanged: (ThemeType? value) => setThemeType(value),
                                    ),
                                    RadioListTile<ThemeType>(
                                      title: const Text("Light Theme"),
                                      value: ThemeType.light,
                                      groupValue: globalSettings.themeType,
                                      onChanged: (ThemeType? value) => setThemeType(value),
                                    ),
                                    RadioListTile<ThemeType>(
                                      title: const Text("Dark Theme"),
                                      value: ThemeType.dark,
                                      groupValue: globalSettings.themeType,
                                      onChanged: (ThemeType? value) => setThemeType(value),
                                    ),
                                    RadioListTile<ThemeType>(
                                      title: const Text('Schedule Light'),
                                      value: ThemeType.schedule,
                                      groupValue: globalSettings.themeType,
                                      onChanged: (ThemeType? value) => setThemeType(value),
                                    ),
                                    if (globalSettings.themeType == ThemeType.schedule)
                                      Row(
                                        children: <Widget>[
                                          const SizedBox(width: 20),
                                          const SizedBox(width: 40, child: Text("From ")),
                                          InkWell(
                                            onTap: () async {
                                              final int hour = (globalSettings.themeScheduleMin ~/ 60);
                                              final int minute = (globalSettings.themeScheduleMin % 60);
                                              final TimeOfDay? timePicker = await showTimePicker(
                                                context: context,
                                                initialTime: TimeOfDay(hour: hour, minute: minute),
                                                initialEntryMode: TimePickerEntryMode.dial,
                                                builder: (BuildContext context, Widget? child) {
                                                  return MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child ?? Container());
                                                },
                                              );
                                              if (timePicker == null) return;
                                              globalSettings.themeScheduleMin = (timePicker.hour) * 60 + (timePicker.minute);
                                              await Boxes.updateSettings("themeScheduleMin", globalSettings.themeScheduleMin);
                                              themeChangeNotifier.value = !themeChangeNotifier.value;
                                              setState(() {});
                                            },
                                            child: Text(globalSettings.themeScheduleMin.formatTime()),
                                          ),
                                          const SizedBox(width: 30, child: Text(" To")),
                                          InkWell(
                                            onTap: () async {
                                              final int hour = (globalSettings.themeScheduleMax ~/ 60);
                                              final int minute = (globalSettings.themeScheduleMax % 60);
                                              final TimeOfDay? timePicker = await showTimePicker(
                                                context: context,
                                                initialTime: TimeOfDay(hour: hour, minute: minute),
                                                initialEntryMode: TimePickerEntryMode.dial,
                                                builder: (BuildContext context, Widget? child) {
                                                  return MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child ?? Container());
                                                },
                                              );
                                              if (timePicker == null) return;
                                              final int newTime = (timePicker.hour) * 60 + (timePicker.minute);
                                              if (newTime < globalSettings.themeScheduleMin) return;
                                              globalSettings.themeScheduleMax = newTime;
                                              await Boxes.updateSettings("themeScheduleMax", globalSettings.themeScheduleMax);
                                              themeChangeNotifier.value = !themeChangeNotifier.value;
                                              setState(() {});
                                            },
                                            child: Text(globalSettings.themeScheduleMax.formatTime()),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                              // const ListTile(title: Text("Post Styling")),
                              const SizedBox(height: 20),
                              const Divider(height: 10, thickness: 2),
                              CheckboxListTile(
                                controlAffinity: ListTileControlAffinity.leading,
                                title: const Text("Pause Spotify when sound comes from other sources"),
                                value: globalSettings.pauseSpotifyWhenNewSound,
                                onChanged: (bool? newValue) async {
                                  globalSettings.pauseSpotifyWhenNewSound = !globalSettings.pauseSpotifyWhenNewSound;
                                  Boxes.updateSettings("pauseSpotifyWhenNewSound", globalSettings.pauseSpotifyWhenNewSound);
                                  if (!mounted) return;
                                  setState(() {});
                                },
                              ),
                              const Divider(height: 10, thickness: 2),
                              CheckboxListTile(
                                controlAffinity: ListTileControlAffinity.leading,
                                title: const Text("Add Wizardly in Folder Context Menu"),
                                value: wizardlyContextMenu.isWizardlyInstalledInContextMenu(),
                                onChanged: (bool? newValue) async {
                                  wizardlyContextMenu.toggleWizardlyToContextMenu();
                                  if (!mounted) return;
                                  setState(() {});
                                },
                              ),
                              const Divider(height: 10, thickness: 2),
                              Markdown(
                                  shrinkWrap: true,
                                  data: '''
To Export settings, open [this](this) folder and copy the file. To import, exit Tabame and paste in that folder your saved settings.
''',
                                  onTapLink: (String s, String? s2, String s3) {
                                    final String path = WinUtils.getKnownFolder(FOLDERID_LocalAppData);
                                    WinUtils.open("$path\\Tabame\\");
                                  }),
                            ],
                          ),
                        ),
                      )
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void setVolumeOSDStyle(VolumeOSDStyle? value) async {
    globalSettings.volumeOSDStyle = value ?? VolumeOSDStyle.normal;
    WinUtils.setVolumeOSDStyle(type: VolumeOSDStyle.normal, applyStyle: true);
    WinUtils.setVolumeOSDStyle(type: globalSettings.volumeOSDStyle, applyStyle: true);
    await Boxes.updateSettings("volumeOSDStyle", globalSettings.volumeOSDStyle.index);
    setState(() {});
  }

  setThemeType(ThemeType? value) async {
    globalSettings.themeType = value ?? ThemeType.system;
    await Boxes.updateSettings("themeType", globalSettings.themeType.index);
    themeChangeNotifier.value = !themeChangeNotifier.value;
    setState(() {});
  }
}
