import 'dart:async';
import 'dart:io';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';

import '../../models/classes/boxes/boxes_base.dart';
import '../../models/classes/saved_maps.dart';
import '../../models/settings.dart';
import '../../models/win32/mixed.dart';
import '../../services/wallpaper_service.dart';
import '../widgets/mini_switch.dart';
import '../widgets/modern_dropdown.dart';

class WallpaperScheduler extends StatefulWidget {
  const WallpaperScheduler({super.key});

  @override
  State<WallpaperScheduler> createState() => _WallpaperSchedulerState();
}

class _WallpaperSchedulerState extends State<WallpaperScheduler> {
  List<WallpaperSchedule> _schedules = <WallpaperSchedule>[];
  WallpaperSchedule? _editingSchedule;

  Timer? _debounceTimer;
  late final TextEditingController _nameController;
  late final TextEditingController _delayController;

  @override
  void initState() {
    super.initState();
    _schedules = List<WallpaperSchedule>.from(Boxes.wallpaperSchedules);
    _nameController = TextEditingController();
    _delayController = TextEditingController();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _nameController.dispose();
    _delayController.dispose();
    super.dispose();
  }

  void _onEditingScheduleChanged(WallpaperSchedule? s) {
    _debounceTimer?.cancel();
    setState(() {
      _editingSchedule = s;
      if (s != null) {
        _nameController.text = s.name;
        _nameController.selection = TextSelection.collapsed(offset: s.name.length);
        _delayController.text = s.shuffleDelayMinutes.toString();
        _delayController.selection = TextSelection.collapsed(offset: _delayController.text.length);
      } else {
        _nameController.clear();
        _delayController.clear();
      }
    });
  }

  void _debounceSave() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _saveSchedules();
    });
  }

  void _saveSchedules() async {
    Boxes.wallpaperSchedules = _schedules;
    await Boxes.updateSettings("wallpaperSchedules", _schedules);
    WallpaperService.instance.forceUpdate();
    if (mounted) setState(() {});
  }

  void _addSchedule() {
    final WallpaperSchedule newSchedule = WallpaperSchedule(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: "New Schedule",
      startHour: 9,
      startMinute: 0,
      endHour: 17,
      endMinute: 0,
      images: <String>[],
      shuffleDelayMinutes: 30,
    );
    _schedules.add(newSchedule);
    _onEditingScheduleChanged(newSchedule);
    _saveSchedules();
  }

  void _deleteSchedule(String id) {
    setState(() {
      _schedules.removeWhere((WallpaperSchedule s) => s.id == id);
      if (_editingSchedule?.id == id) _editingSchedule = null;
    });
    _saveSchedules();
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = userSettings.themeColors.accent;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildTopSection(accent, onSurface),
          const SizedBox(height: 20),
          if (_editingSchedule == null)
            Expanded(child: _buildScheduleList(accent))
          else
            Expanded(child: _buildEditArea(accent, showBack: true)),
        ],
      ),
    );
  }

  Widget _buildTopSection(Color accent, Color onSurface) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _editingSchedule == null ? "Wallpaper Scheduler" : "Edit Schedule",
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20, letterSpacing: -0.5),
                  ),
                  if (_editingSchedule != null)
                    Text(_editingSchedule!.name, style: TextStyle(fontSize: Design.baseFontSize + 2, color: accent.withAlpha(180))),
                ],
              ),
            ),
            if (_editingSchedule == null)
              ElevatedButton(
                onPressed: _addSchedule,
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text("NEW", style: TextStyle(fontWeight: FontWeight.bold, fontSize: Design.baseFontSize + 1)),
              )
            else
              IconButton(
                onPressed: () => _onEditingScheduleChanged(null),
                icon: const Icon(Icons.close_rounded),
                tooltip: "Back to List",
              ),
          ],
        ),
        const SizedBox(height: 16),
        _buildTimeline(accent, onSurface),
      ],
    );
  }

  Widget _buildTimeline(Color accent, Color onSurface) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          height: 12,
          child: CustomPaint(
            painter: _TimelinePainter(
              schedules: _schedules,
              accent: accent,
              onSurface: onSurface,
            ),
            child: const SizedBox.expand(),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            for (int i = 0; i <= 24; i += 6)
              Text(
                "${i.toString().padLeft(2, '0')}:00",
                style: TextStyle(fontSize: 9, color: onSurface.withAlpha(80), fontWeight: FontWeight.w500),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildScheduleList(Color accent) {
    if (_schedules.isEmpty) return _buildEmptyState(accent);
    return ListView.builder(
      itemCount: _schedules.length,
      padding: EdgeInsets.zero,
      itemBuilder: (BuildContext context, int index) {
        final WallpaperSchedule s = _schedules[index];
        final bool isSelected = _editingSchedule?.id == s.id;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: isSelected ? accent.withAlpha(20) : Theme.of(context).colorScheme.onSurface.withAlpha(10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? accent.withAlpha(80) : Theme.of(context).colorScheme.onSurface.withAlpha(20),
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: MiniToggleSwitch(
              value: s.enabled,
              activeThumbColor: accent,
              onChanged: (bool val) {
                setState(() => s.enabled = val);
                _saveSchedules();
              },
            ),
            title: Text(
              s.name,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isSelected ? accent : null,
              ),
            ),
            subtitle: Text(
              "${s.startHour.toString().padLeft(2, '0')}:${s.startMinute.toString().padLeft(2, '0')} - "
              "${s.endHour.toString().padLeft(2, '0')}:${s.endMinute.toString().padLeft(2, '0')}",
              style: TextStyle(fontSize: Design.baseFontSize + 2, color: Theme.of(context).hintColor),
            ),
            onTap: () => _onEditingScheduleChanged(s),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (s.monitorIndex != -1)
                  Icon(Icons.monitor_rounded, size: 14, color: Theme.of(context).hintColor.withAlpha(150)),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  color: Theme.of(context).hintColor.withAlpha(150),
                  onPressed: () => _deleteSchedule(s.id),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(Color accent) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: accent.withAlpha(10),
              shape: BoxShape.circle,
              border: Border.all(color: accent.withAlpha(20)),
            ),
            child: Icon(Icons.wallpaper_rounded, size: 40, color: accent.withAlpha(100)),
          ),
          const SizedBox(height: 20),
          Text(
            "Select or create a schedule to edit",
            style: TextStyle(
              color: Theme.of(context).hintColor,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _addSchedule,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text("Create First Schedule"),
            style: ElevatedButton.styleFrom(
              backgroundColor: accent.withAlpha(40),
              foregroundColor: accent,
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditArea(Color accent, {bool showBack = false}) {
    final WallpaperSchedule s = _editingSchedule!;

    return SingleChildScrollView(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildSection(
            title: "SITUATION",
            icon: Icons.badge_outlined,
            accent: accent,
            child: _buildTextField("Schedule Label", _nameController, (String val) {
              s.name = val;
              _debounceSave();
            }, noBorder: true),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                flex: 2,
                child: _buildSection(
                  title: "TIME WINDOW",
                  icon: Icons.timer_outlined,
                  accent: accent,
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: _buildTimePicker("Start", s.startHour, s.startMinute, (int h, int m) {
                          setState(() {
                            s.startHour = h;
                            s.startMinute = m;
                          });
                          _saveSchedules();
                        }),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Icon(Icons.arrow_forward_rounded, size: 14, color: Colors.grey),
                      ),
                      Expanded(
                        child: _buildTimePicker("End", s.endHour, s.endMinute, (int h, int m) {
                          setState(() {
                            s.endHour = h;
                            s.endMinute = m;
                          });
                          _saveSchedules();
                        }),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 1,
                child: _buildSection(
                  title: "FILL MODE",
                  icon: Icons.fit_screen_outlined,
                  accent: accent,
                  child: _buildFillModeSelection(accent, s),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: "TARGET MONITOR",
            icon: Icons.monitor_outlined,
            accent: accent,
            child: _buildMonitorSelection(accent, s),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: _buildSection(
                  title: "IMAGE COLLECTION",
                  icon: Icons.folder_copy_outlined,
                  accent: accent,
                  child: _buildFolderFilesSelection(accent, s),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildSection(
                  title: "ROTATION",
                  icon: Icons.shuffle_rounded,
                  accent: accent,
                  child: _buildShuffleSettings(accent, s),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: () => WallpaperService.instance.forceUpdate(),
              icon: const Icon(Icons.play_circle_filled_rounded, size: 20),
              label: const Text("APPLY CHANGES NOW", style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
              style: ElevatedButton.styleFrom(
                backgroundColor: accent.withAlpha(40),
                foregroundColor: accent,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: accent.withAlpha(60)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required Widget child,
    required Color accent,
    IconData? icon,
  }) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: onSurface.withAlpha(12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: onSurface.withAlpha(15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 12, color: accent.withAlpha(180)),
                const SizedBox(width: 6),
              ],
              Text(
                title,
                style: TextStyle(
                  fontSize: Design.baseFontSize,
                  fontWeight: FontWeight.w900,
                  color: onSurface.withAlpha(150),
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, Function(String) onChanged,
      {bool noBorder = false}) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: Design.baseFontSize + 2, color: Theme.of(context).hintColor),
        isDense: true,
        counterText: "",
        border: noBorder
            ? InputBorder.none
            : UnderlineInputBorder(borderSide: BorderSide(color: Theme.of(context).dividerColor.withAlpha(50))),
        enabledBorder: noBorder
            ? InputBorder.none
            : UnderlineInputBorder(borderSide: BorderSide(color: Theme.of(context).dividerColor.withAlpha(50))),
        focusedBorder: noBorder
            ? InputBorder.none
            : UnderlineInputBorder(borderSide: BorderSide(color: userSettings.themeColors.accent)),
      ),
      maxLength: 50,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      onChanged: onChanged,
      onSubmitted: (String val) {
        _debounceTimer?.cancel();
        _saveSchedules();
      },
      textInputAction: TextInputAction.next,
    );
  }

  Widget _buildTimePicker(String label, int hour, int minute, Function(int, int) onTimePicked) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final TimeOfDay? picked = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(hour: hour, minute: minute),
        );
        if (picked != null) onTimePicked(picked.hour, picked.minute);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurface.withAlpha(15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label.toUpperCase(),
                style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.grey.withAlpha(200))),
            const SizedBox(height: 2),
            Text(
              "${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: userSettings.themeColors.accent),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonitorSelection(Color accent, WallpaperSchedule s) {
    final List<int> monitorList = Monitor.list;
    if (monitorList.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            ChoiceChip(
              label: Text("All Monitors", style: TextStyle(fontSize: Design.baseFontSize + 1)),
              selected: s.monitorIndex == -1,
              onSelected: (bool sel) {
                if (sel) {
                  setState(() => s.monitorIndex = -1);
                  _saveSchedules();
                }
              },
              selectedColor: accent.withAlpha(50),
              backgroundColor: Colors.transparent,
              side: BorderSide(
                  color: s.monitorIndex == -1 ? accent.withAlpha(100) : Theme.of(context).dividerColor.withAlpha(50)),
            ),
            const SizedBox(width: 12),
            Text(
              s.monitorIndex == -1 ? "Global schedule" : "Monitor ${s.monitorIndex + 1}",
              style: TextStyle(fontSize: Design.baseFontSize + 1, color: Theme.of(context).hintColor),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 120,
          child: _MonitorLayoutPicker(
            accent: accent,
            selectedIndex: s.monitorIndex,
            onSelect: (int monitorIndex) {
              setState(() => s.monitorIndex = monitorIndex);
              _saveSchedules();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFolderFilesSelection(Color accent, WallpaperSchedule s) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withAlpha(10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  s.folderPath != null && s.folderPath!.isNotEmpty ? "DIRECTORY" : "COLLECTION",
                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: accent.withAlpha(150)),
                ),
                const SizedBox(height: 2),
                Text(
                  s.folderPath != null && s.folderPath!.isNotEmpty
                      ? s.folderPath!
                      : s.images.isNotEmpty
                          ? "${s.images.length} images"
                          : "Empty",
                  style: TextStyle(fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _pickFolder(s),
            icon: const Icon(Icons.folder_open_rounded, size: 18),
            color: accent,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: "Change Source",
          ),
        ],
      ),
    );
  }

  Future<void> _pickFolder(WallpaperSchedule s) async {
    try {
      final DirectoryPicker dirPicker = DirectoryPicker()..title = 'Select wallpapers folder';
      final Directory? dir = dirPicker.getDirectory();
      if (dir == null || dir.path.isEmpty) return;

      setState(() {
        s.folderPath = dir.path;
        s.images = <String>[];
      });
      _saveSchedules();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to open folder picker: $e")),
        );
      }
    }
  }

  Widget _buildShuffleSettings(Color accent, WallpaperSchedule s) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withAlpha(10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text("INTERVAL",
                    style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: accent.withAlpha(150))),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Container(
                      width: 50,
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: accent.withAlpha(20),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: accent.withAlpha(40)),
                      ),
                      child: TextField(
                        keyboardType: TextInputType.number,
                        controller: _delayController,
                        textAlign: TextAlign.center,
                        maxLength: 4,
                        decoration: const InputDecoration(
                          isDense: true,
                          counterText: "",
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: accent),
                        onChanged: (String val) {
                          final int? minutes = int.tryParse(val);
                          if (minutes != null) {
                            setState(() => s.shuffleDelayMinutes = minutes.clamp(0, 9999));
                            _debounceSave();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "MINUTES",
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.onSurface.withAlpha(100),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFillModeSelection(Color accent, WallpaperSchedule s) {
    return ModernDropdown<int>(
      value: s.fillMode,
      items: <ModernDropdownItem<int>>[
        for (int i = 0; i < WallpaperFillMode.values.length; i++)
          ModernDropdownItem<int>(
            value: i,
            label: WallpaperFillMode.values[i].name.toUpperCase(),
          ),
      ],
      onChanged: (int? val) {
        if (val != null) {
          setState(() => s.fillMode = val);
          _saveSchedules();
        }
      },
    );
  }
}

class _TimelinePainter extends CustomPainter {
  final List<WallpaperSchedule> schedules;
  final Color accent;
  final Color onSurface;

  _TimelinePainter({
    required this.schedules,
    required this.accent,
    required this.onSurface,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint bgPaint = Paint()..color = onSurface.withAlpha(20);
    final Paint accentPaint = Paint()..color = accent.withAlpha(180);

    // Draw background bar
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width, 10), const Radius.circular(2)), bgPaint);

    // Draw schedule blocks
    for (final WallpaperSchedule s in schedules) {
      if (!s.enabled) continue;

      final double start = (s.startHour + (s.startMinute / 60.0)) / 24.0;
      final double end = (s.endHour + (s.endMinute / 60.0)) / 24.0;

      if (end >= start) {
        final double x = start * size.width;
        final double w = (end - start) * size.width;
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x, 0, w.clamp(2, size.width), 10), const Radius.circular(2)),
          accentPaint,
        );
      } else {
        // Spans across midnight
        final double xStart = start * size.width;
        final double wStart = size.width - xStart;
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(xStart, 0, wStart, 10), const Radius.circular(2)),
          accentPaint,
        );

        final double wEnd = end * size.width;
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, wEnd, 10), const Radius.circular(2)),
          accentPaint,
        );
      }
    }

    // Draw current time marker
    final DateTime now = DateTime.now();
    final double nowPos = (now.hour + (now.minute / 60.0)) / 24.0;
    final double x = nowPos * size.width;

    canvas.drawRect(
      Rect.fromLTWH(x - 1, -2, 2, 14),
      Paint()..color = Colors.redAccent,
    );
  }

  @override
  bool shouldRepaint(_TimelinePainter oldDelegate) => true;
}

class _MonitorLayoutPicker extends StatelessWidget {
  const _MonitorLayoutPicker({
    required this.accent,
    required this.onSelect,
    required this.selectedIndex,
  });

  final Color accent;
  final Function(int) onSelect;
  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    final List<int> monitorList = Monitor.list;
    if (monitorList.isEmpty) return const SizedBox.shrink();

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    final Map<int, Square> sizes = Monitor.monitorSizes;
    for (final int handle in monitorList) {
      final Square size = sizes[handle]!;
      if (size.x < minX) minX = size.x.toDouble();
      if (size.y < minY) minY = size.y.toDouble();
      if (size.x + size.width > maxX) maxX = (size.x + size.width).toDouble();
      if (size.y + size.height > maxY) maxY = (size.y + size.height).toDouble();
    }

    final double totalWidth = maxX - minX;
    final double totalHeight = maxY - minY;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double scaleX = constraints.maxWidth / totalWidth;
        final double scaleY = constraints.maxHeight / totalHeight;
        final double scale = (scaleX < scaleY ? scaleX : scaleY) * 0.9;

        final double offsetX = (constraints.maxWidth - totalWidth * scale) / 2;
        final double offsetY = (constraints.maxHeight - totalHeight * scale) / 2;

        return Stack(
          children: <Widget>[
            for (int i = 0; i < monitorList.length; i++) ...<Widget>[
              (() {
                final int handle = monitorList[i];
                final Square size = sizes[handle]!;
                final double left = (size.x - minX) * scale + offsetX;
                final double top = (size.y - minY) * scale + offsetY;
                final double width = size.width * scale;
                final double height = size.height * scale;
                final bool isSelected = selectedIndex == i;

                return Positioned(
                  left: left,
                  top: top,
                  width: width,
                  height: height,
                  child: _MonitorItem(
                    index: i,
                    accent: accent,
                    isSelected: isSelected,
                    onTap: () => onSelect(i),
                  ),
                );
              })(),
            ],
          ],
        );
      },
    );
  }
}

class _MonitorItem extends StatefulWidget {
  const _MonitorItem({
    required this.index,
    required this.accent,
    required this.onTap,
    required this.isSelected,
  });

  final int index;
  final Color accent;
  final VoidCallback onTap;
  final bool isSelected;

  @override
  State<_MonitorItem> createState() => _MonitorItemState();
}

class _MonitorItemState extends State<_MonitorItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? widget.accent.withAlpha(40)
                  : _hovered
                      ? widget.accent.withAlpha(20)
                      : onSurface.withAlpha(15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: widget.isSelected
                    ? widget.accent
                    : _hovered
                        ? widget.accent.withAlpha(150)
                        : onSurface.withAlpha(50),
                width: widget.isSelected || _hovered ? 2 : 1,
              ),
              boxShadow: widget.isSelected || _hovered
                  ? <BoxShadow>[
                      BoxShadow(
                        color: widget.accent.withAlpha(40),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.monitor_rounded,
                  size: 20,
                  color: widget.isSelected || _hovered ? widget.accent : onSurface.withAlpha(180),
                ),
                const SizedBox(height: 4),
                Text(
                  "${widget.index + 1}",
                  style: TextStyle(
                    fontSize: Design.baseFontSize + 2,
                    fontWeight: FontWeight.bold,
                    color: widget.isSelected || _hovered ? widget.accent : onSurface.withAlpha(180),
                  ),
                ),
              ],
            ),
          ),
        ));
  }
}
