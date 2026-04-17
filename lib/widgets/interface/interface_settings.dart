// ignore_for_file: public_member_api_docs, sort_constructors_first

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'package:win32/win32.dart';

import '../../models/classes/boxes.dart';
import '../../models/globals.dart';
import '../../models/settings.dart';
import '../../models/win32/win32.dart';
import 'package:tabame/widgets/widgets/custom_tooltip.dart';

class _AppOpacity {
  static const double subtle = 0.06;
  static const double border = 0.08;
  static const double borderEmphasis = 0.15;
  static const double surfaceOverlay = 0.31; // ~80/255
  static const double accentFaint = 0.14;
  static const double textSecondary = 0.65;
}

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

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool stacked = constraints.maxWidth < 950;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // --- HERO: Status & Updates ---
                _buildSectionTitle("System Status"),
                _buildUpdateCard(accent, background, onSurface),
                const SizedBox(height: 24),

                // --- MAIN GRID ---
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: <Widget>[
                    _responsiveCard(
                      stacked,
                      constraints,
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _buildSectionTitle("Configuration"),
                          _buildGeneralCard(runOnStartup, accent, onSurface),
                          const SizedBox(height: 16),
                          _buildSectionTitle("Shell Integrations"),
                          _buildWizardlyCard(accent, onSurface),
                        ],
                      ),
                    ),
                    _responsiveCard(
                      stacked,
                      constraints,
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _buildSectionTitle("Visuals & Theme"),
                          _buildThemeCard(accent, onSurface),
                          const SizedBox(height: 16),
                          _buildSectionTitle("Data & Tools"),
                          _buildMaintenanceCard(accent, onSurface),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 80),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.1,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: _AppOpacity.textSecondary),
        ),
      ),
    );
  }

  Widget _responsiveCard(bool stacked, BoxConstraints constraints, Widget child) {
    return SizedBox(
      width: stacked ? double.infinity : (constraints.maxWidth - 16) / 2,
      child: child,
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
              color: Theme.of(context).colorScheme.surface.withValues(alpha: _AppOpacity.surfaceOverlay),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: _AppOpacity.accentFaint),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.system_update_rounded,
                    color: accent,
                    size: 18,
                    semanticLabel: "Update Status",
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text("Current Version: v${Globals.version}",
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 2),
                      Text(updateResponse,
                          style:
                              TextStyle(fontSize: 12, color: onSurface.withValues(alpha: _AppOpacity.textSecondary))),
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
                  label: const Text("Check for Updates"),
                ),
              ],
            ),
          ),
          if (showUpdateButtons) ...<Widget>[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: _AppOpacity.subtle),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: accent.withValues(alpha: _AppOpacity.borderEmphasis)),
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
                      label: const Text("View on GitHub"),
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
            title: "Launch at Startup",
            subtitle: "Start Tabame automatically when you log in to Windows.",
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
                  : CustomTooltip(
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
                            color: accent.withValues(alpha: _AppOpacity.subtle),
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
                  color: accent.withValues(alpha: _AppOpacity.subtle),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: accent.withValues(alpha: _AppOpacity.border)),
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
          _markdownCard(
            onSurface,
            '''
To export settings, copy *settings.json* from [this folder](data). To import, exit Tabame and replace the file with your copy.
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
To uninstall, open [this folder](uninstall) and delete it. No other app data is stored elsewhere.
''',
            () {
              final String exeFolder = File(Platform.resolvedExecutable).parent.path;
              WinUtils.open(exeFolder, parseParamaters: true);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildWizardlyCard(Color accent, Color onSurface) {
    return _settingsCard(
      title: "Wizardly",
      subtitle: "Windows Explorer right-click integration.",
      child: Column(
        children: <Widget>[
          _toggleTile(
            title: "Wizardly in Explorer Menu",
            subtitle: "Access Wizardly directly from the Windows right-click folder menu.",
            value: wizardlyContextMenu.isWizardlyInstalledInContextMenu(),
            onChanged: (bool value) async {
              wizardlyContextMenu.toggleWizardlyToContextMenu();
              setState(() {});
            },
          ),
        ],
      ),
    );
  }

  Widget _settingsCard({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: _AppOpacity.surfaceOverlay),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: onSurface.withValues(alpha: _AppOpacity.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, letterSpacing: -0.4)),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(fontSize: 12, color: onSurface.withValues(alpha: _AppOpacity.textSecondary))),
          const SizedBox(height: 16),
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
        border: Border.all(color: onSurface.withValues(alpha: _AppOpacity.subtle)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 3),
                Text(subtitle,
                    style: TextStyle(fontSize: 11, color: onSurface.withValues(alpha: _AppOpacity.textSecondary))),
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
            ? Color(globalSettings.theme.accentColor).withValues(alpha: _AppOpacity.subtle)
            : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected
              ? Color(globalSettings.theme.accentColor).withValues(alpha: _AppOpacity.borderEmphasis)
              : onSurface.withValues(alpha: _AppOpacity.subtle),
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
          border: Border.all(color: accent.withValues(alpha: _AppOpacity.border)),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.schedule_rounded, size: 18, color: accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(label,
                      style: TextStyle(fontSize: 11, color: onSurface.withValues(alpha: _AppOpacity.textSecondary))),
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
        border: Border.all(color: onSurface.withValues(alpha: _AppOpacity.subtle)),
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
