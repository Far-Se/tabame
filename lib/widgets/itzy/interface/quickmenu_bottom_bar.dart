import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/gestures.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/classes/saved_maps.dart';
import '../../../models/win32/win32.dart';
import '../../../models/tray_watcher.dart';
import '../../../models/settings.dart';
import '../../widgets/windows_scroll.dart';
import 'package:tabame/widgets/widgets/custom_tooltip.dart';

enum BottomBarSection { all, trayOnly, weatherSystemOnly }

class QuickmenuBottomBar extends StatefulWidget {
  final BottomBarSection section;
  const QuickmenuBottomBar({super.key, this.section = BottomBarSection.all});

  @override
  QuickmenuBottomBarState createState() => QuickmenuBottomBarState();
}

class QuickmenuBottomBarState extends State<QuickmenuBottomBar> {
  List<PowerShellScript> powerShellScripts = Boxes().powerShellScripts;
  List<String> pinnedApps = <String>[];
  final Map<String, Uint8List> pinnedAppsIcons = <String, Uint8List>{};
  final List<TextEditingController> powerShellNameController = <TextEditingController>[];
  late Future<void> pinnedAppsLoader;

  final TextEditingController cityLatLong = TextEditingController();

  @override
  void initState() {
    super.initState();
    pinnedApps = List<String>.from(Boxes().pinnedApps);
    pinnedAppsLoader = _loadPinnedAppsIcons();

    for (final PowerShellScript item in powerShellScripts) {
      powerShellNameController.add(TextEditingController(text: item.name));
    }
  }

  @override
  void dispose() {
    for (TextEditingController item in powerShellNameController) {
      item.dispose();
    }
    cityLatLong.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WindowsScrollView(
      controller: ScrollController(),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (widget.section == BottomBarSection.all || widget.section == BottomBarSection.trayOnly)
              _buildBottomBarCard(),
            const SizedBox(height: 20),
            if (widget.section == BottomBarSection.all) _buildPinnedAppsCard(),
            const SizedBox(height: 20),
            if (widget.section == BottomBarSection.all || widget.section == BottomBarSection.weatherSystemOnly)
              _buildWeatherCard(),
            const SizedBox(height: 20),
            if (widget.section == BottomBarSection.all) _buildPowerShellCard(),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBarCard() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: <Widget>[
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              minLeadingWidth: 28,
              horizontalTitleGap: 14,
              leading:
                  Icon(Icons.widgets_outlined, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7)),
              title: const Text("Bottom Bar & System", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              subtitle: const Text("Configure tray icons and system info display"),
            ),
            const Divider(),
            SwitchListTile(
              title: const Text("Show System Usage", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              subtitle: const Text("Display RAM and CPU usage in the quick menu", style: TextStyle(fontSize: 12)),
              secondary: const Icon(Icons.speed, size: 20),
              value: globalSettings.showSystemUsage,
              onChanged: (bool newValue) async {
                globalSettings.showSystemUsage = newValue;
                await Boxes.updateSettings("showSystemUsage", globalSettings.showSystemUsage);
                if (mounted) setState(() {});
              },
            ),
            SwitchListTile(
              title: const Text("Tray Bar", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              subtitle: const Text("Show system tray icons in the bottom bar", style: TextStyle(fontSize: 12)),
              secondary: const Icon(Icons.expand_less, size: 20),
              value: globalSettings.showTrayBar,
              onChanged: (bool newValue) async {
                globalSettings.showTrayBar = newValue;
                await Boxes.updateSettings("showTrayBar", globalSettings.showTrayBar);
                if (mounted) setState(() {});
              },
            ),
            if (globalSettings.showTrayBar)
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 16),
                child: _buildTrayList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPinnedAppsCard() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: <Widget>[
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              minLeadingWidth: 28,
              horizontalTitleGap: 14,
              leading:
                  Icon(Icons.push_pin_outlined, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7)),
              title: const Text("Pinned Files", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              subtitle: const Text("Manage the pinned apps shown in the quick menu"),
              trailing: IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 22),
                tooltip: "Add pinned file",
                onPressed: _addPinnedApp,
              ),
            ),
            const Divider(),
            FutureBuilder<void>(
              future: pinnedAppsLoader,
              builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  );
                }
                if (pinnedApps.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.1),
                        border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        "No pinned files yet. Add an executable or script to show it in the quick menu.",
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13),
                      ),
                    ),
                  );
                }
                return ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                  shrinkWrap: true,
                  buildDefaultDragHandles: false,
                  physics: const NeverScrollableScrollPhysics(),
                  dragStartBehavior: DragStartBehavior.down,
                  itemCount: pinnedApps.length,
                  onReorder: _reorderPinnedApps,
                  itemBuilder: (BuildContext context, int index) => _buildPinnedAppItem(index),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPinnedAppItem(int index) {
    final String path = pinnedApps[index];
    final Uint8List? iconData = pinnedAppsIcons[path];
    return LayoutBuilder(
        key: ValueKey<String>(path),
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool isNarrow = constraints.maxWidth < 400;

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: <Widget>[
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Icon(Icons.drag_indicator_rounded,
                        size: 20, color: Theme.of(context).colorScheme.onSurface.withAlpha(60)),
                  ),
                ),
                if (iconData != null)
                  Image.memory(
                    iconData,
                    width: 24,
                    errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) =>
                        const Icon(Icons.check_box_outline_blank, size: 20),
                  )
                else
                  const Icon(Icons.check_box_outline_blank, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        Win32.getExe(path),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      if (!isNarrow)
                        Text(
                          path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                  tooltip: "Remove",
                  onPressed: () => _removePinnedApp(index),
                ),
              ],
            ),
          );
        });
  }

  Widget _buildTrayList() {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: <Widget>[
              Text("MANAGED TRAY ICONS",
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                      )),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, size: 16),
                tooltip: "Reload Tray List",
                style: IconButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: () {
                  globalSettings.showTrayBar = false;
                  setState(() {});
                  globalSettings.showTrayBar = true;
                  setState(() {});
                },
              ),
            ],
          ),
        ),
        FutureBuilder<bool>(
          future: Tray.fetchTray(sort: false),
          builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
            if (!snapshot.hasData) {
              return const Center(
                  child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(strokeWidth: 2)));
            }
            final List<TrayBarInfo> trayList =
                Tray.trayList.where((TrayBarInfo element) => element.processExe != "explorer.exe").toList();
            return Container(
              constraints: const BoxConstraints(maxHeight: 250),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: trayList.length,
                separatorBuilder: (BuildContext context, int index) => const SizedBox(height: 8),
                itemBuilder: (BuildContext context, int index) {
                  final TrayBarInfo item = trayList[index];
                  return _buildTrayItem(item);
                },
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildTrayItem(TrayBarInfo item) {
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
      final bool isNarrow = constraints.maxWidth < 450;
      final Color borderColor = Theme.of(context).dividerColor.withValues(alpha: 0.12);

      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                const SizedBox(width: 4),
                Image.memory(
                  item.iconData,
                  width: 22,
                  height: 22,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) =>
                      const Icon(Icons.check_box_outline_blank, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.processExe.isEmpty ? "Permission denied" : item.processExe,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      fontStyle: item.processExe.isEmpty ? FontStyle.italic : FontStyle.normal,
                      color: item.processExe.isEmpty ? Theme.of(context).hintColor : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!isNarrow) _buildTrayActions(item),
              ],
            ),
            if (isNarrow)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 34),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: _buildTrayActions(item),
                ),
              ),
          ],
        ),
      );
    });
  }

  Widget _buildTrayActions(TrayBarInfo item) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const SizedBox(width: 8),
        ToggleButtons(
          constraints: const BoxConstraints(minHeight: 28, minWidth: 28),
          borderRadius: BorderRadius.circular(8),
          isSelected: <bool>[item.isPinned, !item.isVisible],
          onPressed: (int index) async {
            final List<String> pinned = Boxes.pref.getStringList("pinnedTray") ?? <String>[];
            final List<String> hidden = Boxes.pref.getStringList("hiddenTray") ?? <String>[];
            if (index == 0) {
              if (pinned.contains(item.processExe)) {
                pinned.remove(item.processExe);
              } else {
                pinned.add(item.processExe);
                hidden.remove(item.processExe);
              }
            } else {
              if (hidden.contains(item.processExe)) {
                hidden.remove(item.processExe);
              } else {
                hidden.add(item.processExe);
                pinned.remove(item.processExe);
              }
            }
            await Boxes.updateSettings("pinnedTray", pinned);
            await Boxes.updateSettings("hiddenTray", hidden);
            setState(() {});
          },
          children: const <Widget>[
            CustomTooltip(message: "Pin to bar", child: Icon(Icons.push_pin, size: 14)),
            CustomTooltip(message: "Hide icon", child: Icon(Icons.visibility_off, size: 14)),
          ],
        ),
        const SizedBox(width: 8),
        ToggleButtons(
          constraints: const BoxConstraints(minHeight: 28, minWidth: 32),
          borderRadius: BorderRadius.circular(8),
          isSelected: <bool>[!item.clickOpensExe, item.clickOpensExe],
          onPressed: (int index) async {
            final List<String> action = Boxes.pref.getStringList("actionTray") ?? <String>[];
            if (index == 1) {
              if (!action.contains(item.processExe)) action.add(item.processExe);
            } else {
              action.remove(item.processExe);
            }
            await Boxes.updateSettings("actionTray", action);
            setState(() {});
          },
          children: const <Widget>[
            CustomTooltip(message: "Simulate Click", child: Icon(Icons.mouse, size: 14)),
            CustomTooltip(message: "Open / Close executable", child: Icon(Icons.open_in_new, size: 14)),
          ],
        ),
      ],
    );
  }

  Widget _buildWeatherCard() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: <Widget>[
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              minLeadingWidth: 28,
              horizontalTitleGap: 14,
              leading: Icon(Icons.cloud_outlined, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7)),
              title: const Text("Weather Settings", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              subtitle: const Text("Configuration for the weather widget"),
            ),
            const Divider(),
            SwitchListTile(
              title: const Text("Show Weather", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              subtitle: const Text("Display local weather in the bottom bar", style: TextStyle(fontSize: 12)),
              secondary: const Icon(Icons.wb_sunny_outlined, size: 20),
              value: globalSettings.showWeather,
              onChanged: (bool newValue) async {
                globalSettings.showWeather = newValue;
                await Boxes.updateSettings("showWeather", globalSettings.showWeather);
                if (mounted) setState(() {});
              },
            ),
            if (globalSettings.showWeather)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
                  final bool isNarrow = constraints.maxWidth < 450;
                  return Column(
                    children: <Widget>[
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text("Use Celsius", style: TextStyle(fontSize: 13)),
                        secondary: const Icon(Icons.thermostat, size: 20),
                        value: globalSettings.weatherUnit == "m",
                        onChanged: (bool newValue) async {
                          globalSettings.weatherUnit = newValue ? "m" : "u";
                          await Boxes.updateSettings("weather", globalSettings.weather);
                          if (mounted) setState(() {});
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        decoration: InputDecoration(
                          labelText: "LATITUDE & LONGITUDE",
                          labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
                          isDense: true,
                          prefixIcon: const Icon(Icons.location_on_outlined, size: 18),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          helperText: "Format: 52.52, 13.41",
                          helperStyle: const TextStyle(fontSize: 10),
                        ),
                        style: const TextStyle(fontSize: 13),
                        controller: TextEditingController(text: globalSettings.weatherLatLong),
                        onSubmitted: (String value) async {
                          if (value.isEmpty) return;
                          globalSettings.weatherLatLong = value;
                          await Boxes.updateSettings("weather", globalSettings.weather);
                          if (mounted) setState(() {});
                        },
                      ),
                      const SizedBox(height: 20),
                      if (isNarrow) ...<Widget>[
                        TextField(
                          controller: cityLatLong,
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            labelText: "SEARCH BY CITY",
                            labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
                            isDense: true,
                            prefixIcon: const Icon(Icons.search, size: 18),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: <Widget>[
                            Expanded(child: _buildWeatherAction("Search", Icons.my_location, _searchCity)),
                            const SizedBox(width: 12),
                            Expanded(
                                child: _buildWeatherAction("From IP", Icons.network_ping, _searchByIP, isText: true)),
                          ],
                        ),
                      ] else
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(
                              child: TextField(
                                controller: cityLatLong,
                                style: const TextStyle(fontSize: 13),
                                decoration: InputDecoration(
                                  labelText: "SEARCH BY CITY",
                                  labelStyle:
                                      const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
                                  isDense: true,
                                  prefixIcon: const Icon(Icons.search, size: 18),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            _buildWeatherAction("Search", Icons.my_location, _searchCity),
                            const SizedBox(width: 8),
                            _buildWeatherAction("From IP", Icons.network_ping, _searchByIP, isText: true),
                          ],
                        ),
                    ],
                  );
                }),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeatherAction(String label, IconData icon, VoidCallback onPressed, {bool isText = false}) {
    if (isText) {
      return TextButton.icon(
        icon: Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        onPressed: onPressed,
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
      );
    }
    return ElevatedButton.icon(
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 16),
      ),
    );
  }

  Future<void> _searchCity() async {
    final http.Response response =
        await http.get(Uri.parse("https://geocoding-api.open-meteo.com/v1/search?name=${cityLatLong.text}"));
    if (response.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(response.body) as Map<String, dynamic>;
      if (data.containsKey("results")) {
        final Map<String, dynamic> res = (data["results"] as List<dynamic>)[0] as Map<String, dynamic>;
        if (res.containsKey("latitude") && res.containsKey("longitude")) {
          final String e = "${res["latitude"]}, ${res["longitude"]}";
          globalSettings.weatherLatLong = e;
          await Boxes.updateSettings("weather", globalSettings.weather);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Location set to ${res["name"]}, ${res["country"]}"),
            backgroundColor: Colors.green,
          ));
          setState(() {});
        }
      }
    }
  }

  Future<void> _searchByIP() async {
    final http.Response ip = await http.get(Uri.parse("http://ifconfig.me/ip"));
    if (ip.statusCode == 200) {
      final http.Response response = await http.get(Uri.parse("http://ip-api.com/json/${ip.body}"));
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body) as Map<String, dynamic>;
        if (data.containsKey("lat") && data.containsKey("lon")) {
          final String e = "${data["lat"]}, ${data["lon"]}";
          globalSettings.weatherLatLong = e;
          await Boxes.updateSettings("weather", globalSettings.weather);
          if (mounted) setState(() {});
        }
      }
    }
  }

  Future<void> _addPinnedApp() async {
    final OpenFilePicker file = OpenFilePicker()
      ..filterSpecification = <String, String>{
        'All Files': '*.*',
        'Executable (*.exe;*.ps1;*.sh;*.bat)': '*.exe;*.ps1;*.sh;*.bat'
      }
      ..defaultFilterIndex = 0
      ..defaultExtension = 'exe'
      ..title = 'Select any file';

    final File? result = file.getFile();
    if (result == null || Win32.getExe(result.path).contains(".dll")) return;

    pinnedApps.add(result.path);
    final Uint8List? icon = WinUtils.extractIcon(result.path);
    if (icon != null) pinnedAppsIcons[result.path] = icon;
    await Boxes.updateSettings("pinnedApps", pinnedApps);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _removePinnedApp(int index) async {
    final String removedPath = pinnedApps.removeAt(index);
    pinnedAppsIcons.remove(removedPath);
    await Boxes.updateSettings("pinnedApps", pinnedApps);
    if (!mounted) return;
    setState(() {});
  }

  void _reorderPinnedApps(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) newIndex -= 1;
    final String item = pinnedApps.removeAt(oldIndex);
    pinnedApps.insert(newIndex, item);
    setState(() {});
    Boxes.updateSettings("pinnedApps", pinnedApps);
  }

  Future<void> _loadPinnedAppsIcons() async {
    pinnedAppsIcons.clear();
    for (final String app in pinnedApps) {
      final Uint8List? icon = WinUtils.extractIcon(app);
      if (icon != null) pinnedAppsIcons[app] = icon;
    }
  }

  Widget _buildPowerShellCard() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: <Widget>[
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              minLeadingWidth: 28,
              horizontalTitleGap: 14,
              leading:
                  Icon(Icons.terminal_outlined, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7)),
              title: const Text("PowerShell Automation", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              subtitle: const Text("Run custom scripts from the quick menu"),
              trailing: IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 22),
                onPressed: () async {
                  powerShellScripts.add(PowerShellScript(command: "dir", name: "New Script", showTerminal: true));
                  powerShellNameController.add(TextEditingController(text: "New Script"));
                  await Boxes.updateSettings("powerShellScripts", jsonEncode(powerShellScripts));
                  if (mounted) setState(() {});
                },
              ),
            ),
            const Divider(),
            SwitchListTile(
              title:
                  const Text("Enable PowerShell Scripts", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              value: globalSettings.showPowerShell,
              onChanged: (bool newValue) async {
                globalSettings.showPowerShell = newValue;
                await Boxes.updateSettings("showPowerShell", globalSettings.showPowerShell);
                if (mounted) setState(() {});
              },
            ),
            if (globalSettings.showPowerShell && powerShellScripts.isNotEmpty)
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                itemCount: powerShellScripts.length,
                separatorBuilder: (BuildContext context, int index) => const SizedBox(height: 12),
                itemBuilder: (BuildContext context, int index) => _buildPowerShellItem(index),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPowerShellItem(int index) {
    final PowerShellScript script = powerShellScripts[index];
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
      final bool isNarrow = constraints.maxWidth < 450;
      final Color borderColor = Theme.of(context).dividerColor.withValues(alpha: 0.12);

      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Column(
                  children: <Widget>[
                    SizedBox(
                      height: 32,
                      width: 32,
                      child: Checkbox(
                        value: !script.disabled,
                        onChanged: (bool? value) async {
                          script.disabled = !(value ?? true);
                          await Boxes.updateSettings("powerShellScripts", jsonEncode(powerShellScripts));
                          setState(() {});
                        },
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.terminal,
                        color: script.showTerminal ? Theme.of(context).colorScheme.primary : Colors.grey.withAlpha(100),
                        size: 20,
                      ),
                      onPressed: () async {
                        script.showTerminal = !script.showTerminal;
                        await Boxes.updateSettings("powerShellScripts", jsonEncode(powerShellScripts));
                        setState(() {});
                      },
                      tooltip: "Show Terminal",
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: <Widget>[
                      TextField(
                        controller: powerShellNameController[index],
                        decoration: const InputDecoration(
                          labelText: "NAME",
                          labelStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                          isDense: true,
                          border: UnderlineInputBorder(),
                        ),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        onChanged: (String value) => script.name = value,
                        onSubmitted: (String value) async {
                          script.name = value;
                          await Boxes.updateSettings("powerShellScripts", jsonEncode(powerShellScripts));
                        },
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: TextEditingController(text: script.command),
                        decoration: const InputDecoration(
                          labelText: "COMMAND",
                          labelStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                          isDense: true,
                          border: InputBorder.none,
                        ),
                        maxLines: null,
                        style: const TextStyle(fontFamily: "monospace", fontSize: 12),
                        onSubmitted: (String value) async {
                          script.command = value;
                          await Boxes.updateSettings("powerShellScripts", jsonEncode(powerShellScripts));
                          if (mounted) setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
                if (!isNarrow)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                    onPressed: () async {
                      powerShellScripts.removeAt(index);
                      powerShellNameController.removeAt(index);
                      await Boxes.updateSettings("powerShellScripts", jsonEncode(powerShellScripts));
                      setState(() {});
                    },
                  ),
              ],
            ),
            if (isNarrow)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton.icon(
                    onPressed: () async {
                      powerShellScripts.removeAt(index);
                      powerShellNameController.removeAt(index);
                      await Boxes.updateSettings("powerShellScripts", jsonEncode(powerShellScripts));
                      setState(() {});
                    },
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text("Remove"),
                    style:
                        TextButton.styleFrom(foregroundColor: Colors.redAccent, visualDensity: VisualDensity.compact),
                  ),
                ],
              ),
          ],
        ),
      );
    });
  }
}
