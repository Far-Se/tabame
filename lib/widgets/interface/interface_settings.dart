// ignore_for_file: public_member_api_docs, sort_constructors_first

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:win32/win32.dart';

import '../../models/classes/boxes.dart';
import '../../models/globals.dart';
import '../../models/settings.dart';
import '../../models/util/solar_calculator.dart';
import '../../models/win32/win32.dart';
import '../../models/win32/win_utils.dart';
import '../widgets/custom_tooltip.dart';
import '../widgets/mini_switch.dart';
import '../widgets/windows_scroll.dart';

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
  final Set<String> _expandedCards = <String>{"maintenance"};

  @override
  Widget build(BuildContext context) {
    final bool runOnStartup = WinUtils.checkIfRegisterAsStartup();
    if (!runOnStartup) user.runAsAdministrator = false;
    final Color accent = Design.accent;
    final Color background = Design.background;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return WindowsScrollView(
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
                          _buildSectionTitle("Light Switch"),
                          _buildLightSwitchCard(accent, background, onSurface),
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
          fontSize: Design.baseFontSize,
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
      subtitle: "Check the status of Tabame and install the latest improvements.",
      alwaysExpanded: true,
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
                      Text("Current Version: ${Globals.version}",
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 2),
                      Text(updateResponse,
                          style: TextStyle(
                              fontSize: Design.baseFontSize + 2,
                              color: onSurface.withValues(alpha: _AppOpacity.textSecondary))),
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
                        if (Boxes.updateDownloadLink != null && user.newVersion != Globals.version) {
                          Boxes.installUpdate(Boxes.updateDownloadLink!, user.newVersion);
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
            value: user.autoCheckForUpdates,
            onChanged: (bool value) async {
              setState(() => user.autoCheckForUpdates = value);
              Boxes.updateSettings("autoUpdate", user.autoCheckForUpdates);
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
      id: "general",
      title: "Configuration",
      subtitle: "Set up the basic behavior and system level integrations.",
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
                user.runAsAdministrator = false;
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
              value: user.runAsAdministrator,
              trailing: !user.runAsAdministrator || WinUtils.isAdministrator()
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
                user.runAsAdministrator = value;
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
            value: user.hideTaskbarOnStartup,
            onChanged: (bool value) async {
              user.hideTaskbarOnStartup = value;
              Boxes.updateSettings("hideTaskbarOnStartup", user.hideTaskbarOnStartup);
              if (!mounted) return;
              setState(() {});
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMaintenanceCard(Color accent, Color onSurface) {
    return _settingsCard(
      id: "maintenance",
      title: "Integration & Maintenance",
      subtitle: "Manage shell integration and locate your data quickly.",
      child: Column(
        children: <Widget>[
          _markdownCard(
            onSurface,
            '''
To export settings, copy *settings.json* from [this folder](data). To import, exit Tabame and replace the file with your copy.
''',
            ({String? s, String? s2, String? s3}) {
              final String path = WinUtils.getKnownFolder(FOLDERID_LocalAppData);
              WinUtils.open("$path\\Tabame\\");
            },
          ),
          const SizedBox(height: 10),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showUninstallConfirmation(accent, onSurface),
              icon: const Icon(Icons.delete_forever_rounded, size: 18),
              label: const Text("UNINSTALL TABAME"),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.3)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showUninstallConfirmation(Color accent, Color onSurface) {
    final TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text("Uninstall Tabame?", style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text("This will permanently remove your settings, local data, and the application itself."),
            const SizedBox(height: 20),
            Text("Type 'MeNoGusta' to confirm:",
                style: TextStyle(fontSize: Design.baseFontSize + 2, color: onSurface.withValues(alpha: 0.6))),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              autofocus: true,
              style: const TextStyle(fontFamily: 'Consolas'),
              decoration: InputDecoration(
                hintText: "MeNoGusta",
                filled: true,
                fillColor: onSurface.withValues(alpha: 0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("CANCEL", style: TextStyle(color: onSurface.withValues(alpha: 0.5))),
          ),
          TextButton(
            onPressed: () {
              if (controller.text == "MeNoGusta") {
                Navigator.pop(context);
                _handleUninstall();
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text("CONFIRM UNINSTALL", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleUninstall() async {
    if (!kReleaseMode) return;

    // 1. Disable startup entries
    await WinUtils.setStartUpShortcut(false);

    // 2. Remove Wizardly context menu integration
    if (wizardlyContextMenu.isWizardlyInstalledInContextMenu()) {
      wizardlyContextMenu.toggleWizardlyToContextMenu();
    }

    // 3. Launch detached cleanup script
    final String exeDir = Directory(Platform.resolvedExecutable).parent.path;
    final String appData = WinUtils.getTabameAppDataFolder();
    WinUtils.toggleTaskbar(visible: true);
    final String psCommand =
        'Start-Sleep -Seconds 2; Remove-Item -Recurse -Force "$appData"; Remove-Item -Recurse -Force "$exeDir" -ErrorAction SilentlyContinue';

    await Process.start(
      'powershell.exe',
      <String>['-NoProfile', '-WindowStyle', 'Hidden', '-Command', psCommand],
      mode: ProcessStartMode.detached,
    );

    // 4. Close all Tabame windows and exit
    WinUtils.closeAllTabameExProcesses();
    exit(0);
  }

  Widget _buildWizardlyCard(Color accent, Color onSurface) {
    return _settingsCard(
      id: "wizardly",
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

  Widget _buildLightSwitchCard(Color accent, Color background, Color onSurface) {
    return _settingsCard(
      id: "lightSwitch",
      title: "Light Switch",
      subtitle: "Automate system theme transitions based on clock or sun position.",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          RadioGroup<LightSwitchMode>(
            onChanged: (LightSwitchMode? val) async {
              user.lightSwitchMode = val ?? LightSwitchMode.off;
              await Boxes.updateSettings("lightSwitchMode", user.lightSwitchMode.index);
              if (user.lightSwitchMode == LightSwitchMode.sunrise) {
                await SolarCalculator.updateSolarData(force: true);
              }
              user.setScheduleThemeChange();
              setState(() {});
            },
            groupValue: user.lightSwitchMode,
            child: Column(
              children: <Widget>[
                _radioTileGeneric("Off", LightSwitchMode.off, (LightSwitchMode mode) => user.lightSwitchMode == mode),
                const SizedBox(height: 8),
                _radioTileGeneric(
                    "Fixed Hours", LightSwitchMode.fixed, (LightSwitchMode mode) => user.lightSwitchMode == mode),
                const SizedBox(height: 8),
                _radioTileGeneric("Sunrise to Sundown", LightSwitchMode.sunrise,
                    (LightSwitchMode mode) => user.lightSwitchMode == mode),
              ],
            ),
          ),
          if (user.lightSwitchMode != LightSwitchMode.off) ...<Widget>[
            const SizedBox(height: 20),
            if (user.lightSwitchMode == LightSwitchMode.fixed) ...<Widget>[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: _AppOpacity.subtle),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: accent.withValues(alpha: _AppOpacity.border)),
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(child: _timeChip("Light Mode", user.themeScheduleMin.formatTime(), _pickThemeStart)),
                    const SizedBox(width: 10),
                    Expanded(child: _timeChip("Dark Mode", user.themeScheduleMax.formatTime(), _pickThemeEnd)),
                  ],
                ),
              ),
            ],
            if (user.lightSwitchMode == LightSwitchMode.sunrise) ...<Widget>[
              _buildSunCycleVisualizer(accent, onSurface),
              const SizedBox(height: 16),
              _buildOffsetSliders(accent, onSurface),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildSunCycleVisualizer(Color accent, Color onSurface) {
    final int sunrise = user.lightSwitchSunrise + user.lightSwitchSunriseOffset;
    final int sunset = user.lightSwitchSunset + user.lightSwitchSunsetOffset;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            _miniInfo("SUNRISE", user.lightSwitchSunrise.formatTime()),
            _miniInfo("SUNSET", user.lightSwitchSunset.formatTime()),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 60,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: onSurface.withValues(alpha: 0.05)),
          ),
          child: CustomPaint(
            painter: SunCyclePainter(
              sunriseMin: sunrise,
              sunsetMin: sunset,
              accent: accent,
              onSurface: onSurface,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOffsetSliders(Color accent, Color onSurface) {
    return Column(
      children: <Widget>[
        _singleOffsetSlider(
          title: "Morning Offset",
          icon: Icons.wb_sunny_rounded,
          value: user.lightSwitchSunriseOffset,
          onChanged: (int val) async {
            setState(() => user.lightSwitchSunriseOffset = val);
            await Boxes.updateSettings("lightSwitchSunriseOffset", user.lightSwitchSunriseOffset);
            user.setScheduleThemeChange();
          },
          accent: accent,
          onSurface: onSurface,
        ),
        const SizedBox(height: 12),
        _singleOffsetSlider(
          title: "Evening Offset",
          icon: Icons.nights_stay_rounded,
          value: user.lightSwitchSunsetOffset,
          onChanged: (int val) async {
            setState(() => user.lightSwitchSunsetOffset = val);
            await Boxes.updateSettings("lightSwitchSunsetOffset", user.lightSwitchSunsetOffset);
            user.setScheduleThemeChange();
          },
          accent: accent,
          onSurface: onSurface,
        ),
      ],
    );
  }

  Widget _singleOffsetSlider({
    required String title,
    required IconData icon,
    required int value,
    required Function(int) onChanged,
    required Color accent,
    required Color onSurface,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(icon, size: 14, color: accent.withValues(alpha: 0.7)),
                  const SizedBox(width: 8),
                  Text(title,
                      style: TextStyle(
                          fontSize: Design.baseFontSize + 1,
                          fontWeight: FontWeight.bold,
                          color: onSurface.withValues(alpha: 0.7))),
                ],
              ),
              Text("${value >= 0 ? '+' : ''}$value min",
                  style: TextStyle(fontSize: Design.baseFontSize + 1, fontFamily: 'Consolas', color: accent)),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: value.toDouble(),
              min: -120,
              max: 120,
              divisions: 48,
              activeColor: accent,
              inactiveColor: onSurface.withValues(alpha: 0.1),
              onChanged: (double val) => onChanged(val.toInt()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniInfo(String label, String value) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label,
            style: TextStyle(
                fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5, color: onSurface.withValues(alpha: 0.4))),
        Text(value,
            style: TextStyle(fontSize: Design.baseFontSize + 2, fontWeight: FontWeight.bold, fontFamily: 'Consolas')),
      ],
    );
  }

  Widget _radioTileGeneric<T>(String label, T value, bool Function(T) isSelected) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final bool selected = isSelected(value);
    final Color accent = Design.accent;

    return Container(
      decoration: BoxDecoration(
        color: selected ? accent.withValues(alpha: _AppOpacity.subtle) : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected
              ? accent.withValues(alpha: _AppOpacity.borderEmphasis)
              : onSurface.withValues(alpha: _AppOpacity.subtle),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: RadioListTile<T>(
          dense: true,
          value: value,
          title: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          activeColor: accent,
        ),
      ),
    );
  }

  Widget _settingsCard({
    String? id,
    required String title,
    required String subtitle,
    required Widget child,
    bool alwaysExpanded = true,
  }) {
    final bool expanded = alwaysExpanded || (id != null && _expandedCards.contains(id));
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: _AppOpacity.surfaceOverlay),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: onSurface.withValues(alpha: _AppOpacity.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            onTap: alwaysExpanded || id == null
                ? null
                : () {
                    setState(() {
                      if (_expandedCards.contains(id)) {
                        _expandedCards.remove(id);
                      } else {
                        _expandedCards.add(id);
                      }
                    });
                  },
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(title,
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, letterSpacing: -0.4)),
                        if (!expanded) ...<Widget>[
                          const SizedBox(height: 4),
                          Text(subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: Design.baseFontSize + 2,
                                  color: onSurface.withValues(alpha: _AppOpacity.textSecondary))),
                        ],
                      ],
                    ),
                  ),
                  if (!alwaysExpanded && id != null) ...<Widget>[
                    const SizedBox(width: 8),
                    Icon(
                      expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      color: onSurface.withAlpha(100),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (expanded) ...<Widget>[
            Padding(
              padding: const EdgeInsets.all(16).copyWith(top: 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: Design.baseFontSize + 2,
                          color: onSurface.withValues(alpha: _AppOpacity.textSecondary))),
                  const SizedBox(height: 16),
                  child,
                ],
              ),
            ),
          ],
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
                    style: TextStyle(
                        fontSize: Design.baseFontSize + 1,
                        color: onSurface.withValues(alpha: _AppOpacity.textSecondary))),
              ],
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: 10),
            trailing,
          ],
          const SizedBox(width: 10),
          MiniToggleSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _timeChip(String label, String value, Future<void> Function() onTap) {
    final Color accent = Design.accent;
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
                      style: TextStyle(
                          fontSize: Design.baseFontSize + 1,
                          color: onSurface.withValues(alpha: _AppOpacity.textSecondary))),
                  Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _markdownCard(Color onSurface, String data, Function({String? s, String? s2, String? s3}) onTap) {
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
        onTapLink: (String s, String? s2, String s3) => onTap(s: s, s2: s2, s3: s3),
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
      updateResponse = "New version ${user.newVersion} detected!";
      showUpdateButtons = true;
    }
    setState(() {});
  }

  Future<void> _pickThemeStart() async {
    final int hour = (user.themeScheduleMin ~/ 60);
    final int minute = (user.themeScheduleMin % 60);
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
    user.themeScheduleMin = (timePicker.hour) * 60 + (timePicker.minute);
    await Boxes.updateSettings("themeScheduleMin", user.themeScheduleMin);
    user.setScheduleThemeChange();
    Globals.themeChangeNotifier.value = !Globals.themeChangeNotifier.value;
    setState(() {});
  }

  Future<void> _pickThemeEnd() async {
    final int hour = (user.themeScheduleMax ~/ 60);
    final int minute = (user.themeScheduleMax % 60);
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
    if (newTime < user.themeScheduleMin) return;
    user.themeScheduleMax = newTime;
    await Boxes.updateSettings("themeScheduleMax", user.themeScheduleMax);
    user.setScheduleThemeChange();
    Globals.themeChangeNotifier.value = !Globals.themeChangeNotifier.value;
    setState(() {});
  }
}

class SunCyclePainter extends CustomPainter {
  final int sunriseMin;
  final int sunsetMin;
  final Color accent;
  final Color onSurface;

  SunCyclePainter({
    required this.sunriseMin,
    required this.sunsetMin,
    required this.accent,
    required this.onSurface,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    // Normalize minutes to width (1440 mins in a day)
    double x(int mins) => mins * w / 1440;

    final Paint dayPaint = Paint()
      ..shader = LinearGradient(
        colors: <Color>[accent.withValues(alpha: 0.05), accent.withValues(alpha: 0.2), accent.withValues(alpha: 0.05)],
      ).createShader(Rect.fromLTWH(x(sunriseMin), 0, x(sunsetMin) - x(sunriseMin), h));

    final Paint nightPaint = Paint()..color = onSurface.withValues(alpha: 0.03);

    // Draw background zones
    // Before sunrise (Night)
    canvas.drawRect(Rect.fromLTWH(0, 0, x(sunriseMin), h), nightPaint);
    // Between sunrise and sunset (Day)
    canvas.drawRect(Rect.fromLTWH(x(sunriseMin), 0, x(sunsetMin) - x(sunriseMin), h), dayPaint);
    // After sunset (Night)
    canvas.drawRect(Rect.fromLTWH(x(sunsetMin), 0, w - x(sunsetMin), h), nightPaint);

    // Draw Grid (every 6 hours)
    final Paint gridPaint = Paint()
      ..color = onSurface.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    for (int i = 1; i < 4; i++) {
      double gx = i * 6 * 60 * w / 1440;
      canvas.drawLine(Offset(gx, 0), Offset(gx, h), gridPaint);
    }

    // Draw Solar Markers
    final Paint markerPaint = Paint()
      ..color = accent
      ..strokeWidth = 2;
    canvas.drawLine(Offset(x(sunriseMin), 0), Offset(x(sunriseMin), h), markerPaint);
    canvas.drawLine(Offset(x(sunsetMin), 0), Offset(x(sunsetMin), h), markerPaint);

    // Current time indicator
    final int now = DateTime.now().hour * 60 + DateTime.now().minute;
    final Paint nowPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..strokeWidth = 2;
    canvas.drawLine(Offset(x(now), 0), Offset(x(now), h), nowPaint);

    // Circle at top of current time
    canvas.drawCircle(Offset(x(now), 0), 3, nowPaint);
  }

  @override
  bool shouldRepaint(covariant SunCyclePainter oldDelegate) =>
      oldDelegate.sunriseMin != sunriseMin || oldDelegate.sunsetMin != sunsetMin;
}
