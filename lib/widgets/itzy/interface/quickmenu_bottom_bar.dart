import 'dart:convert';
import 'dart:io';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../../models/tray_watcher.dart';
import '../../../models/win32/win32.dart';
import '../../../models/win32/win_utils.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/custom_tooltip.dart';
import '../../widgets/extracted_icon.dart';
import '../../widgets/windows_scroll.dart';

enum BottomBarSection { all, trayOnly, weatherSystemOnly }

class QMBottomBar extends StatefulWidget {
  final BottomBarSection section;
  const QMBottomBar({super.key, this.section = BottomBarSection.all});

  @override
  QMBottomBarState createState() => QMBottomBarState();
}

class QMBottomBarState extends State<QMBottomBar> {
  List<String> pinnedApps = <String>[];
  final Map<String, ExtractedIcon> pinnedAppsIcons = <String, ExtractedIcon>{};
  late Future<void> pinnedAppsLoader;

  final TextEditingController cityLatLong = TextEditingController();

  @override
  void initState() {
    super.initState();
    pinnedApps = List<String>.from(Boxes.pinnedApps);
    pinnedAppsLoader = _loadPinnedAppsIcons();
  }

  @override
  void dispose() {
    cityLatLong.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: WindowsScrollView(
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
              const SizedBox(height: 100),
            ],
          ),
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
              subtitle: Text("Display RAM and CPU usage in the quick menu",
                  style: TextStyle(fontSize: Design.baseFontSize + 2)),
              secondary: const Icon(Icons.speed, size: 20),
              value: user.showSystemUsage,
              onChanged: (bool newValue) async {
                user.showSystemUsage = newValue;
                await Boxes.updateSettings("showSystemUsage", user.showSystemUsage);
                if (mounted) setState(() {});
              },
            ),
            SwitchListTile(
              title: const Text("Show LibreHardwareMonitor Data",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              subtitle: Text("It will show CPU/GPU/RAM Usage and CPU/GPU Temp. Must run Tabame as admin!",
                  style: TextStyle(fontSize: Design.baseFontSize + 2)),
              secondary: const Icon(Icons.insights, size: 20),
              value: user.libreStats,
              onChanged: (bool newValue) async {
                user.libreStats = newValue;
                await Boxes.updateSettings("libreStats", user.libreStats);
                if (newValue == true) {
                  user.taskManagerStats = false;
                  user.autoOpenTaskManager = false;
                  await Boxes.updateSettings("taskManagerStats", user.taskManagerStats);
                  await Boxes.updateSettings("autoOpenTaskManager", user.autoOpenTaskManager);
                }
                if (mounted) setState(() {});
              },
            ),
            if (user.libreStats) ...<Widget>[
              ListTile(
                title: CustomTextField(
                  labelText: "URL",
                  hintText: "Options->Remote Server->Run then Interface",
                  value: Boxes.pref.getString('libreUrl'),
                  onChanged: (String e) {
                    Boxes.pref.setString("libreUrl", e);
                  },
                ),
              ),
              ListTile(
                leading: const Icon(Icons.open_in_browser),
                dense: true,
                title: const Text("Install LibreHardwareMonitor if you dont have it already",
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                subtitle: Text("It must be always open and Remote Server running.",
                    style: TextStyle(fontSize: Design.baseFontSize + 2)),
                onTap: () {
                  WinUtils.open(
                      "https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/releases/latest#:~:text=7%20other%20contributors-,Assets,-4");
                },
                trailing: const Icon(Icons.open_in_new),
              ),
            ],
            SwitchListTile(
              title: const Text("Show TaskManager System Usage",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              subtitle: Text("If TaskManger is open, put it on at the bottom of the screen",
                  style: TextStyle(fontSize: Design.baseFontSize + 2)),
              secondary: const Icon(Icons.query_stats, size: 20),
              value: user.taskManagerStats,
              onChanged: (bool newValue) async {
                user.taskManagerStats = newValue;
                await Boxes.updateSettings("taskManagerStats", user.taskManagerStats);
                if (newValue == false) {
                  user.autoOpenTaskManager = false;
                  await Boxes.updateSettings("autoOpenTaskManager", user.autoOpenTaskManager);
                } else {
                  user.libreStats = false;
                  await Boxes.updateSettings("libreStats", user.libreStats);
                }
                if (mounted) setState(() {});
              },
            ),
            if (user.taskManagerStats)
              SwitchListTile(
                title:
                    const Text("Auto start TaskManager", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                subtitle: Text("Open TaskManager on startup so you can always see PC stats",
                    style: TextStyle(fontSize: Design.baseFontSize + 2)),
                secondary: const Icon(Icons.dataset_linked, size: 20),
                value: user.autoOpenTaskManager,
                onChanged: (bool newValue) async {
                  user.autoOpenTaskManager = newValue;
                  await Boxes.updateSettings("autoOpenTaskManager", user.autoOpenTaskManager);
                  if (mounted) setState(() {});
                },
              ),
            SwitchListTile(
              title: const Text("Tray Bar", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              subtitle:
                  Text("Show system tray icons in the bottom bar", style: TextStyle(fontSize: Design.baseFontSize + 2)),
              secondary: const Icon(Icons.expand_less, size: 20),
              value: user.showTrayBar,
              onChanged: (bool newValue) async {
                user.showTrayBar = newValue;
                await Boxes.updateSettings("showTrayBar", user.showTrayBar);
                if (mounted) setState(() {});
              },
            ),
            if (user.showTrayBar)
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
                  onReorderItem: _reorderPinnedApps,
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
    final ExtractedIcon iconData = pinnedAppsIcons[path];
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
                buildExtractedIcon(
                  iconData,
                  width: 24,
                  errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) =>
                      const Icon(Icons.check_box_outline_blank, size: 20),
                  fallback: const Icon(Icons.check_box_outline_blank, size: 20),
                ),
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
                  user.showTrayBar = false;
                  setState(() {});
                  user.showTrayBar = true;
                  setState(() {});
                },
              ),
            ],
          ),
        ),
        FutureBuilder<bool>(
          future: TrayWatcher.fetchTray(sort: false),
          builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
            if (!snapshot.hasData) {
              return const Center(
                  child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(strokeWidth: 2)));
            }
            final List<TrayBarInfo> trayList =
                TrayWatcher.trayList.where((TrayBarInfo element) => element.processExe != "explorer.exe").toList();
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
        _infoMessageForTray(
            "You can long press to open .exe if normal click doesn't work. Also double click and Right click might work depends on the app"),
        const SizedBox(height: 8),
        _infoMessageForTray(
            "You need to have \"Always show all icons in the notification area\" enabled in the Windows Taskbar settings"),
        const SizedBox(height: 8),
      ],
    );
  }

  Padding _infoMessageForTray(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.info_outline,
              size: 16,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: Design.baseFontSize + 1,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.9),
                    ),
              ),
            ),
          ],
        ),
      ),
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
              subtitle:
                  Text("Display local weather in the bottom bar", style: TextStyle(fontSize: Design.baseFontSize + 2)),
              secondary: const Icon(Icons.wb_sunny_outlined, size: 20),
              value: user.showWeather,
              onChanged: (bool newValue) async {
                user.showWeather = newValue;
                await Boxes.updateSettings("showWeather", user.showWeather);
                if (mounted) setState(() {});
              },
            ),
            if (user.showWeather)
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
                        value: user.weatherUnit == "m",
                        onChanged: (bool newValue) async {
                          user.weatherUnit = newValue ? "m" : "u";
                          await Boxes.updateSettings("weather", user.weather);
                          if (mounted) setState(() {});
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        decoration: InputDecoration(
                          labelText: "LATITUDE & LONGITUDE",
                          labelStyle: TextStyle(
                              fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.bold, letterSpacing: 1),
                          isDense: true,
                          prefixIcon: const Icon(Icons.location_on_outlined, size: 18),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          helperText: "Format: 52.52, 13.41",
                          helperStyle: TextStyle(fontSize: Design.baseFontSize),
                        ),
                        style: const TextStyle(fontSize: 13),
                        controller: TextEditingController(text: user.weatherLatLong),
                        onSubmitted: (String value) async {
                          if (value.isEmpty) return;
                          user.weatherLatLong = value;
                          await Boxes.updateSettings("weather", user.weather);
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
                            labelStyle: TextStyle(
                                fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.bold, letterSpacing: 1),
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
                                  labelStyle: TextStyle(
                                      fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.bold, letterSpacing: 1),
                                  isDense: true,
                                  prefixIcon: const Icon(Icons.search, size: 18),
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
        label: Text(label, style: TextStyle(fontSize: Design.baseFontSize + 2)),
        onPressed: onPressed,
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
      );
    }
    return ElevatedButton.icon(
      icon: Icon(icon, size: 18),
      label: Text(label, style: TextStyle(fontSize: Design.baseFontSize + 2, fontWeight: FontWeight.w600)),
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
          user.weatherLatLong = e;
          await Boxes.updateSettings("weather", user.weather);
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
          user.weatherLatLong = e;
          await Boxes.updateSettings("weather", user.weather);
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

    if (pinnedApps.contains(result.path)) return;
    pinnedApps.add(result.path);

    final ExtractedIcon icon = WinUtils.extractIcon(result.path);
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
      final ExtractedIcon icon = WinUtils.extractIcon(app);
      if (icon != null) pinnedAppsIcons[app] = icon;
    }
  }
}
