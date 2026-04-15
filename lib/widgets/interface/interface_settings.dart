// ignore_for_file: public_member_api_docs, sort_constructors_first

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'package:win32/win32.dart';

import '../../models/classes/boxes.dart';
import '../../models/globals.dart';
import '../../models/settings.dart';
import '../../models/win32/win32.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  SettingsPageState createState() => SettingsPageState();
}

class SettingsPageState extends State<SettingsPage> {
  final WizardlyContextMenu wizardlyContextMenu = WizardlyContextMenu();

  String updateResponse = "Check for Updates";
  bool showUpdateButtons = false;

  @override
  Widget build(BuildContext context) {
    final bool runOnStartup = WinUtils.checkIfRegisterAsStartup();
    if (!runOnStartup) globalSettings.runAsAdministrator = false;
    final Color accent = Color(globalSettings.theme.accentColor);
    final Color background = Color(globalSettings.theme.background);
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool stacked = constraints.maxWidth < 950;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              SizedBox(
                width: stacked ? double.infinity : (constraints.maxWidth - 12) / 2,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _buildUpdateCard(accent, background, onSurface),
                    const SizedBox(height: 12),
                    _buildGeneralCard(runOnStartup, accent, onSurface),
                  ],
                ),
              ),
              SizedBox(
                width: stacked ? double.infinity : (constraints.maxWidth - 12) / 2,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _buildThemeCard(accent, onSurface),
                    const SizedBox(height: 12),
                    _buildMaintenanceCard(accent, onSurface),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildUpdateCard(Color accent, Color background, Color onSurface) {
    return _settingsCard(
      title: "Version & Updates",
      subtitle: "Keep Tabame current and manage release behavior.",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withAlpha(80),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.system_update_rounded, color: accent, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text("Current Version: v${Globals.version}",
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 2),
                      Text(updateResponse, style: TextStyle(fontSize: 12, color: onSurface.withValues(alpha: 0.7))),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _checkForUpdates,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: background,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text("Check"),
                ),
              ],
            ),
          ),
          if (showUpdateButtons) ...<Widget>[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: accent.withValues(alpha: 0.15)),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        if (Boxes.updateDownloadLink != null && Boxes.updateVersion != null) {
                          Boxes.installUpdate(Boxes.updateDownloadLink!, Boxes.updateVersion!);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: background,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.bolt_rounded, size: 18),
                      label: const Text("Install (PowerShell)"),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => WinUtils.open("https://github.com/Far-Se/tabame/releases/"),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        side: BorderSide(color: onSurface.withValues(alpha: 0.2)),
                      ),
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text("Download from Releases"),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          _toggleTile(
            title: "Auto Update",
            subtitle: "Download new releases automatically when available.",
            value: globalSettings.autoUpdate,
            onChanged: (bool value) async {
              setState(() => globalSettings.autoUpdate = value);
              Boxes.updateSettings("autoUpdate", globalSettings.autoUpdate);
            },
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => WinUtils.open("https://github.com/Far-Se/tabame/releases/"),
              child: const Text("Open Repository"),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGeneralCard(bool runOnStartup, Color accent, Color onSurface) {
    return _settingsCard(
      title: "Startup & System",
      subtitle: "Control how Tabame launches and interacts with Windows.",
      child: Column(
        children: <Widget>[
          _toggleTile(
            title: "Run on Startup",
            subtitle: "Launch Tabame automatically when Windows starts.",
            value: runOnStartup,
            onChanged: (bool value) async {
              if (value) {
                await WinUtils.setStartUpShortcut(true);
              } else {
                await WinUtils.setStartUpShortcut(false);
                globalSettings.runAsAdministrator = false;
                await Boxes.updateSettings("runAsAdministrator", false);
              }
              if (!mounted) return;
              setState(() {});
            },
          ),
          if (runOnStartup) ...<Widget>[
            const SizedBox(height: 8),
            _toggleTile(
              title: "Run as Administrator",
              subtitle: "Needed for some focus, close, and tray-control actions.",
              value: globalSettings.runAsAdministrator,
              trailing: !globalSettings.runAsAdministrator || WinUtils.isAdministrator()
                  ? null
                  : Tooltip(
                      message: "Restart as Admin",
                      child: InkWell(
                        onTap: () {
                          WinUtils.runAsAdmin(Platform.resolvedExecutable);
                          final int hWnd = Win32.findWindow("Tabame");
                          if (hWnd != 0) Win32.closeWindow(hWnd);
                          Future<void>.delayed(const Duration(milliseconds: 300), () => exit(0));
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.replay_outlined, size: 16, color: accent),
                        ),
                      ),
                    ),
              onChanged: (bool value) async {
                globalSettings.runAsAdministrator = value;
                await Boxes.updateSettings("runAsAdministrator", value);
                if (!mounted) return;
                setState(() {});
              },
            ),
          ],
          const SizedBox(height: 8),
          _toggleTile(
            title: "Hide Taskbar on Startup",
            subtitle: "Apply your taskbar visibility preference immediately.",
            value: globalSettings.hideTaskbarOnStartup,
            onChanged: (bool value) async {
              globalSettings.hideTaskbarOnStartup = value;
              Boxes.updateSettings("hideTaskbarOnStartup", globalSettings.hideTaskbarOnStartup);
              if (!mounted) return;
              setState(() {});
            },
          ),
        ],
      ),
    );
  }

  Widget _buildThemeCard(Color accent, Color onSurface) {
    return _settingsCard(
      title: "Appearance",
      subtitle: "Pick the theme behavior that feels right for your setup.",
      child: RadioGroup<ThemeType>(
        onChanged: setThemeType,
        groupValue: globalSettings.themeType,
        child: Column(
          children: <Widget>[
            _radioTile("System Theme", ThemeType.system),
            const SizedBox(height: 8),
            _radioTile("Light Theme", ThemeType.light),
            const SizedBox(height: 8),
            _radioTile("Dark Theme", ThemeType.dark),
            const SizedBox(height: 8),
            _radioTile("Schedule Light", ThemeType.schedule),
            if (globalSettings.themeType == ThemeType.schedule) ...<Widget>[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: accent.withValues(alpha: 0.12)),
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(child: _timeChip("From", globalSettings.themeScheduleMin.formatTime(), _pickThemeStart)),
                    const SizedBox(width: 10),
                    Expanded(child: _timeChip("To", globalSettings.themeScheduleMax.formatTime(), _pickThemeEnd)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMaintenanceCard(Color accent, Color onSurface) {
    return _settingsCard(
      title: "Integration & Maintenance",
      subtitle: "Manage shell integration and locate your data quickly.",
      child: Column(
        children: <Widget>[
          _toggleTile(
            title: "Add Wizardly in Folder Context Menu",
            subtitle: "Show Wizardly directly from the Windows folder menu.",
            value: wizardlyContextMenu.isWizardlyInstalledInContextMenu(),
            onChanged: (bool value) async {
              wizardlyContextMenu.toggleWizardlyToContextMenu();
              if (!mounted) return;
              setState(() {});
            },
          ),
          const SizedBox(height: 12),
          _markdownCard(
            onSurface,
            '''
To export settings, open [this](this) folder and copy *settings.json*. To import, exit Tabame and replace that file with your saved copy.
''',
            () {
              final String path = WinUtils.getKnownFolder(FOLDERID_LocalAppData);
              WinUtils.open("$path\\Tabame\\");
            },
          ),
          const SizedBox(height: 10),
          _markdownCard(
            onSurface,
            '''
To uninstall, open [this](this) folder and delete it. No other app data is stored elsewhere.
''',
            () {
              final String exePath = Platform.resolvedExecutable;
              final String exeFolder = exePath.substring(0, exePath.lastIndexOf("\\"));
              WinUtils.open(exeFolder, parseParamaters: true);
            },
          ),
        ],
      ),
    );
  }

  Widget _settingsCard({required String title, required String subtitle, required Widget child}) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withAlpha(80),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: onSurface.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(fontSize: 12, color: onSurface.withValues(alpha: 0.65))),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _toggleTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    Widget? trailing,
  }) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: onSurface.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 3),
                Text(subtitle, style: TextStyle(fontSize: 11, color: onSurface.withValues(alpha: 0.62))),
              ],
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: 10),
            trailing,
          ],
          const SizedBox(width: 10),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _radioTile(String label, ThemeType value) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final bool selected = globalSettings.themeType == value;
    return Container(
      decoration: BoxDecoration(
        color: selected
            ? Color(globalSettings.theme.accentColor).withValues(alpha: 0.06)
            : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected
              ? Color(globalSettings.theme.accentColor).withValues(alpha: 0.16)
              : onSurface.withValues(alpha: 0.06),
        ),
      ),
      child: RadioListTile<ThemeType>(
        dense: true,
        value: value,
        title: Text(label, style: const TextStyle(fontSize: 13)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      ),
    );
  }

  Widget _timeChip(String label, String value, Future<void> Function() onTap) {
    final Color accent = Color(globalSettings.theme.accentColor);
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.schedule_rounded, size: 18, color: accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(label, style: TextStyle(fontSize: 11, color: onSurface.withValues(alpha: 0.62))),
                  Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _markdownCard(Color onSurface, String data, VoidCallback onTap) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: onSurface.withValues(alpha: 0.06)),
      ),
      child: MarkdownBody(
        shrinkWrap: true,
        data: data,
        onTapLink: (String s, String? s2, String s3) => onTap(),
      ),
    );
  }

  Future<void> _checkForUpdates() async {
    final int r = await Boxes.checkForUpdates(autoInstall: false);
    if (r == -1) {
      updateResponse = "Failed to fetch updates.";
      showUpdateButtons = false;
      setState(() {});
      // WinUtils.open("https://github.com/Far-Se/tabame/releases/");
      return;
    }
    if (r == 0) {
      updateResponse = "Latest version installed!";
      showUpdateButtons = false;
    } else {
      updateResponse = "New version ${Boxes.updateVersion} detected!";
      showUpdateButtons = true;
    }
    setState(() {});
  }

  Future<void> _pickThemeStart() async {
    final int hour = (globalSettings.themeScheduleMin ~/ 60);
    final int minute = (globalSettings.themeScheduleMin % 60);
    final TimeOfDay? timePicker = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: hour, minute: minute),
      initialEntryMode: TimePickerEntryMode.dial,
      builder: (BuildContext context, Widget? child) {
        return MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child ?? Container());
      },
    );
    if (timePicker == null) return;
    globalSettings.themeScheduleMin = (timePicker.hour) * 60 + (timePicker.minute);
    await Boxes.updateSettings("themeScheduleMin", globalSettings.themeScheduleMin);
    Globals.themeChangeNotifier.value = !Globals.themeChangeNotifier.value;
    setState(() {});
  }

  Future<void> _pickThemeEnd() async {
    final int hour = (globalSettings.themeScheduleMax ~/ 60);
    final int minute = (globalSettings.themeScheduleMax % 60);
    final TimeOfDay? timePicker = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: hour, minute: minute),
      initialEntryMode: TimePickerEntryMode.dial,
      builder: (BuildContext context, Widget? child) {
        return MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child ?? Container());
      },
    );
    if (timePicker == null) return;
    final int newTime = (timePicker.hour) * 60 + (timePicker.minute);
    if (newTime < globalSettings.themeScheduleMin) return;
    globalSettings.themeScheduleMax = newTime;
    await Boxes.updateSettings("themeScheduleMax", globalSettings.themeScheduleMax);
    Globals.themeChangeNotifier.value = !Globals.themeChangeNotifier.value;
    setState(() {});
  }

  Future<void> setThemeType(ThemeType? value) async {
    globalSettings.themeType = value ?? ThemeType.system;
    await Boxes.updateSettings("themeType", globalSettings.themeType.index);
    Globals.themeChangeNotifier.value = !Globals.themeChangeNotifier.value;
    setState(() {});
  }
}
