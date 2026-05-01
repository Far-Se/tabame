import 'dart:async';
import 'dart:io';

import 'package:tabamewin32/tabamewin32.dart';

import '../models/classes/boxes/boxes_base.dart';
import '../models/classes/saved_maps.dart';
import '../models/win32/mixed.dart';
import '../models/win32/win_utils.dart';

class WallpaperService {
  WallpaperService._();
  static final WallpaperService instance = WallpaperService._();

  Timer? _timer;

  void init() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (Timer timer) {
      _checkSchedules();
    });
    // Initial check on startup
    _checkSchedules();
  }

  void _checkSchedules({bool force = false}) async {
    final List<WallpaperSchedule> schedules = Boxes.wallpaperSchedules;
    if (schedules.isEmpty) return;
    if (WinUtils.getDesktopBackgroundType() != DesktopBackgroundType.wallpaper) return;
    final DateTime now = DateTime.now();
    final int currentTotalMinutes = now.hour * 60 + now.minute;

    // Filter enabled and active schedules
    final List<WallpaperSchedule> activeSchedules = schedules.where((WallpaperSchedule s) {
      if (!s.enabled) return false;

      final int start = s.startHour * 60 + s.startMinute;
      final int end = s.endHour * 60 + s.endMinute;

      if (start <= end) {
        return currentTotalMinutes >= start && currentTotalMinutes <= end;
      } else {
        // Over-midnight schedule
        return currentTotalMinutes >= start || currentTotalMinutes <= end;
      }
    }).toList();

    if (activeSchedules.isEmpty) return;

    // Group schedules by monitor
    // monitorIndex -1 means all monitors.
    // If a monitor has multiple active schedules, the one that appears LATER in the list (higher index) wins.
    final Map<int, WallpaperSchedule> monitorAssignments = <int, WallpaperSchedule>{};

    // We assume Monitor.list gives us the available monitor handles/indices
    final int monitorCount = Monitor.list.length;

    for (final WallpaperSchedule s in activeSchedules) {
      if (s.monitorIndex == -1) {
        for (int i = 0; i < monitorCount; i++) {
          monitorAssignments[i] = s;
        }
      } else if (s.monitorIndex >= 0 && s.monitorIndex < monitorCount) {
        monitorAssignments[s.monitorIndex] = s;
      }
    }

    final int nowTimestamp = DateTime.now().millisecondsSinceEpoch;

    // Process each monitor assignment
    for (final int monitorIdx in monitorAssignments.keys) {
      final WallpaperSchedule s = monitorAssignments[monitorIdx]!;

      // Check if it's time to change
      final bool needsChange = force ||
          s.lastChangeTimestamp == 0 ||
          (nowTimestamp - s.lastChangeTimestamp) >= (s.shuffleDelayMinutes * 60 * 1000);

      if (needsChange) {
        await _applyWallpaperForSchedule(s, monitorIdx);
      }
    }
  }

  Future<void> _applyWallpaperForSchedule(WallpaperSchedule s, int monitorIdx) async {
    List<String> imagePaths = <String>[];

    if (s.folderPath != null && s.folderPath!.isNotEmpty) {
      final Directory dir = Directory(s.folderPath!);
      if (dir.existsSync()) {
        imagePaths =
            dir.listSync().whereType<File>().where((File f) => _isImage(f.path)).map((File f) => f.path).toList();
      }
    } else {
      imagePaths = s.images;
    }

    if (imagePaths.isEmpty) return;

    final DesktopBackgroundType state = WinUtils.getDesktopBackgroundType();

    if (state != DesktopBackgroundType.wallpaper) return;
    // Pick next image
    // If shuffleDelayMinutes is 0, maybe just keep the same?
    // But usually we want to cycle.
    int nextIndex = s.currentImageIndex;
    if (s.lastChangeTimestamp != 0) {
      // If we have multiple images, pick a different one (random or sequential)
      if (imagePaths.length > 1) {
        nextIndex = (s.currentImageIndex + 1) % imagePaths.length;
        // Alternatively, random:
        // nextIndex = Random().nextInt(imagePaths.length);
      }
    }

    final String imagePath = imagePaths[nextIndex];
    final WallpaperFillMode fillMode = WallpaperFillMode.values[s.fillMode];

    final bool ok = await WinUtils.setWallpaper(File(imagePath), monitorIdx, fillMode);

    if (ok) {
      s.lastChangeTimestamp = DateTime.now().millisecondsSinceEpoch;
      s.currentImageIndex = nextIndex;
      // Save updated schedule state back to boxes
      _saveScheduleUpdate(s);
    }
  }

  bool _isImage(String path) {
    final String ext = path.split('.').last.toLowerCase();
    return const <String>['jpg', 'jpeg', 'png', 'bmp', 'gif', 'webp'].contains(ext);
  }

  void _saveScheduleUpdate(WallpaperSchedule updated) async {
    final List<WallpaperSchedule> current = Boxes.wallpaperSchedules;
    final int idx = current.indexWhere((WallpaperSchedule s) => s.id == updated.id);
    if (idx != -1) {
      current[idx] = updated;
      await Boxes.updateSettings("wallpaperSchedules", current);
    }
  }

  void forceUpdate() {
    _checkSchedules(force: true);
  }
}
