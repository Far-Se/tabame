// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';

import '../../models/settings.dart';
import '../../models/util/task_runner.dart';
import '../../models/win32/win32.dart';
import '../widgets/mouse_scroll_widget.dart';
import '../widgets/percentage_bar.dart';
import 'package:tabame/widgets/widgets/custom_tooltip.dart';

class FileSizeWidget extends StatefulWidget {
  const FileSizeWidget({super.key});

  @override
  FileSizeWidgetState createState() => FileSizeWidgetState();
}

class DirectoryInfo {
  String path;
  int size;
  bool deleted = false;
  DirectoryInfo({
    required this.path,
    required this.size,
  });
  @override
  String toString() => 'DirectoryInfo(path: $path, size: $size)';

  @override
  bool operator ==(covariant DirectoryInfo other) {
    if (identical(this, other)) return true;

    return other.path == path && other.size == size;
  }

  @override
  int get hashCode => path.hashCode ^ size.hashCode;
}

class DirectoryScan {
  static DirectoryInfo main = DirectoryInfo(path: "", size: 0);
  static List<DirectoryInfo> dirs = <DirectoryInfo>[];
  static Map<String, int> names = <String, int>{};
  static List<String> unfoldedDirectories = <String>[];

  @override
  String toString() => 'DirectoryScan(dirs: $dirs, names: $names,)';

  static List<MapEntry<String, int>> getSubFolders(String folder) => DirectoryScan.names.entries
      .where((MapEntry<String, int> element) => element.key.replaceFirst("$folder\\", '').contains(RegExp(r'^[^\\]*$')))
      .toList();
  static void clear() {
    dirs = <DirectoryInfo>[];
    names = <String, int>{};
    unfoldedDirectories = <String>[];
    main = DirectoryInfo(path: "", size: 0);
  }

  static void deleteDir(String deletedDir, [int? size]) {
    Directory dirPath = Directory(deletedDir);
    int removeSize = 0;
    if (size == null) {
      final DirectoryInfo dir = DirectoryScan.dirs[DirectoryScan.names[deletedDir]!];

      removeSize = dir.size;
      dir.deleted = true;
    } else {
      removeSize = size;
    }
    DirectoryScan.main.size -= removeSize;
    int ticks = 0;
    do {
      ticks++;
      if (ticks > 1000) break;

      if (DirectoryScan.names.containsKey(dirPath.path)) {
        DirectoryScan.dirs[DirectoryScan.names[dirPath.path]!].size -= removeSize;
      }
      if (dirPath.path == DirectoryScan.main.path) break;
      dirPath = dirPath.parent;
    } while (true);
  }
}

bool percentageOfMainFolder = false;
bool deleteWithoutConfirmation = false;
ValueNotifier<bool>? redrawWidget;

const bool actuallyDeleteFiles = true; //!change if testing.

class FileSizeWidgetState extends State<FileSizeWidget> {
  String currentFolder = "";

  String processedFiles = "";

  bool finishedProcessing = false;
  double lastHeight = 0;

  @override
  void initState() {
    redrawWidget = ValueNotifier<bool>(false);

    if (globalSettings.args.contains("-wizardly")) {
      currentFolder = globalSettings.args[0].replaceAll('"', '');
    }
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
    // redrawWidget?.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = Color(globalSettings.theme.accentColor);
    final Color background = Color(globalSettings.theme.background);
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildHeader(accent, background, onSurface),
          _buildOptionsBar(accent, onSurface),
          if (processedFiles.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            _buildStatusPill(accent),
          ],
          if (finishedProcessing) ...<Widget>[
            const SizedBox(height: 12),
            _buildResultsSection(accent, onSurface),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(Color accent, Color background, Color onSurface) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: InkWell(
              onTap: _pickFolder,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: onSurface.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: onSurface.withValues(alpha: 0.1)),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.manage_search, color: accent, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text("Target Folder", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text(
                            currentFolder.isEmpty
                                ? "Pick a folder to scan storage usage"
                                : currentFolder.truncate(70, suffix: "..."),
                            style: TextStyle(fontSize: 12, color: onSurface.withValues(alpha: 0.6)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: _runScan,
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: background,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            icon: const Icon(Icons.radar_rounded, size: 18),
            label: const Text("SCAN", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.8)),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionsBar(Color accent, Color onSurface) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: onSurface.withValues(alpha: 0.08)),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        children: <Widget>[
          SizedBox(
            width: 250,
            child: CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: percentageOfMainFolder,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text("Show % of main folder", style: TextStyle(fontSize: 13)),
              onChanged: (bool? newValue) {
                percentageOfMainFolder = newValue ?? false;
                setState(() {});
              },
            ),
          ),
          SizedBox(
            width: 250,
            child: CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: deleteWithoutConfirmation,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text("Delete without confirmation", style: TextStyle(fontSize: 13)),
              onChanged: (bool? newValue) {
                deleteWithoutConfirmation = newValue ?? false;
                setState(() {});
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              "Folders only, drives are blocked",
              style: TextStyle(fontSize: 11, color: Colors.orange.shade800, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPill(Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        processedFiles.trim(),
        style: TextStyle(fontSize: 12, color: accent, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildResultsSection(Color accent, Color onSurface) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: onSurface.withValues(alpha: 0.08)),
      ),
      child: ValueListenableBuilder<bool>(
        valueListenable: redrawWidget!,
        builder: (BuildContext context, Object? snapshot, Widget? e) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text("Folder Breakdown", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        SizedBox(height: 4),
                        Text("Inspect the largest folders first and trim files directly from the report.",
                            style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                  _buildStatPill(
                      "Total", getFileSize(DirectoryScan.main.size, 1), Icons.data_usage_rounded, accent, onSurface),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: onSurface.withValues(alpha: 0.08)),
                ),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.folder_rounded, size: 16, color: accent),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                        width: 86,
                        child: Text(getFileSize(DirectoryScan.main.size, 1),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    const PercentageBar(percent: 100, barWidth: 56),
                    const SizedBox(width: 12),
                    Expanded(
                      child: MouseScrollWidget(
                        child: Text(
                          DirectoryScan.main.path,
                          style: TextStyle(fontSize: 12, color: onSurface.withValues(alpha: 0.78)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              FolderInfo(directory: currentFolder, parentSize: DirectoryScan.main.size),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatPill(String label, String value, IconData icon, Color color, Color onSurface) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          RichText(
            text: TextSpan(
              style: TextStyle(color: onSurface, fontSize: 12),
              children: <InlineSpan>[
                TextSpan(text: value, style: const TextStyle(fontWeight: FontWeight.bold)),
                TextSpan(text: " $label", style: TextStyle(color: onSurface.withValues(alpha: 0.65))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFolder() async {
    processedFiles = "";
    DirectoryScan.clear();
    finishedProcessing = false;
    if (mounted) setState(() {});
    WinUtils.toggleHiddenFiles(visible: true);

    final DirectoryPicker dirPicker = DirectoryPicker()..title = 'Select any folder';
    final Directory? dir = dirPicker.getDirectory();
    if (dir == null) return;
    currentFolder = dir.path;
    WinUtils.toggleHiddenFiles(visible: false);

    if (currentFolder.contains(RegExp(r'^[A-Z]:\\$'))) {
      currentFolder = "";

      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            content: const SizedBox(height: 100, child: Text("Can't process Drive, only folders!")),
            actions: <Widget>[
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text("Ok", style: TextStyle(color: Color(globalSettings.theme.background))),
              ),
            ],
          );
        },
      ).then((_) {});
      return;
    }
    if (mounted) setState(() {});
  }

  Future<void> _runScan() async {
    if (currentFolder.contains(RegExp(r'^[A-Z]:\\$'))) {
      currentFolder = "";

      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            content: const SizedBox(height: 100, child: Text("Can't process Drive, only folders!")),
            actions: <Widget>[
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text("Ok", style: TextStyle(color: Color(globalSettings.theme.background))),
              ),
            ],
          );
        },
      ).then((_) {});
      return;
    }
    finishedProcessing = false;
    setState(() {});
    if (currentFolder.isEmpty) return;
    if (!Directory(currentFolder).existsSync()) return;

    await listDirectoriesSizes(currentFolder, (int total, int type) {
      processedFiles = " ${type == 0 ? "Fetched" : "Processed"} $total files ...";
      if (mounted) setState(() {});
    }, (Map<String, int> allDirs) {
      processedFiles = "Formating Directories ...";
      if (mounted) setState(() {});
      if (DirectoryScan.dirs.isNotEmpty) DirectoryScan.dirs.clear();
      if (DirectoryScan.dirs.isNotEmpty) DirectoryScan.names.clear();
      if (DirectoryScan.unfoldedDirectories.isNotEmpty) DirectoryScan.unfoldedDirectories.clear();

      for (MapEntry<String, int> dir in allDirs.entries) {
        DirectoryScan.dirs.add(DirectoryInfo(path: dir.key, size: dir.value));
      }
      DirectoryScan.dirs.sort((DirectoryInfo a, DirectoryInfo b) => b.size.compareTo(a.size));
      int index = 0;
      for (DirectoryInfo item in DirectoryScan.dirs) {
        DirectoryScan.names[item.path] = index;
        index++;
      }
      DirectoryScan.main
        ..size = DirectoryScan.dirs.first.size
        ..path = DirectoryScan.dirs.first.path
        ..deleted = DirectoryScan.dirs.first.deleted;

      if (!DirectoryScan.names.containsKey(currentFolder)) {
        DirectoryScan.dirs.add(DirectoryScan.main);
      }
      finishedProcessing = true;
      processedFiles =
          " ${DirectoryScan.dirs.length} directories with a total of ${getFileSize(DirectoryScan.main.size, 1)}!";
      if (mounted) setState(() {});
    });
  }
}

class FolderInfo extends StatefulWidget {
  final String directory;
  final int parentSize;
  const FolderInfo({
    super.key,
    required this.directory,
    required this.parentSize,
  });

  @override
  State<FolderInfo> createState() => _FolderInfoState();
}

class _FolderInfoState extends State<FolderInfo> {
  int toggled = -1;
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final Color accent = Color(globalSettings.theme.accentColor);
    String parentDirectory = widget.directory;
    if (parentDirectory.endsWith("\\")) parentDirectory = parentDirectory.substring(0, parentDirectory.length - 1);
    final List<MapEntry<String, int>> list = DirectoryScan.getSubFolders(parentDirectory);

    List<DirectoryInfo> dirs = <DirectoryInfo>[];

    for (MapEntry<String, int> e in list) {
      dirs.add(DirectoryScan.dirs[e.value]);
    }

    dirs.sort((DirectoryInfo a, DirectoryInfo b) => b.size.compareTo(a.size));
    final List<Widget> rows = <Widget>[];
    const double barWidth = 50;

    int totalFolderSize = 0;
    for (DirectoryInfo dir in dirs) {
      if (dir.deleted) continue;
      totalFolderSize += dir.size;
      final double percent =
          ((dir.size / (!percentageOfMainFolder ? widget.parentSize : DirectoryScan.main.size)) * 100);
      final String shortName = dir.path.replaceFirst("$parentDirectory\\", '');
      final bool isExpanded = DirectoryScan.unfoldedDirectories.contains(dir.path);

      rows.add(
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: isExpanded ? 0.05 : 0.025),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent.withValues(alpha: 0.1)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              if (DirectoryScan.unfoldedDirectories.contains(dir.path)) {
                for (String i in <String>[...DirectoryScan.unfoldedDirectories]) {
                  if (i.contains(dir.path)) {
                    DirectoryScan.unfoldedDirectories.remove(i);
                  }
                }
              } else {
                DirectoryScan.unfoldedDirectories.add(dir.path);
              }
              setState(() {});
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: barWidth,
                    child: Icon(isExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                        color: onSurface.withValues(alpha: 0.55)),
                  ),
                  SizedBox(
                    width: 86,
                    child: Text(getFileSize(dir.size, 1),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                  PercentageBar(percent: percent, barWidth: barWidth),
                  const SizedBox(width: 12),
                  Expanded(
                    child: MouseScrollWidget(
                      child: Text(
                        shortName,
                        style: TextStyle(fontSize: 12, color: onSurface.withValues(alpha: 0.85)),
                      ),
                    ),
                  ),
                  _ActionIconButton(
                    icon: Icons.folder_open_rounded,
                    color: accent,
                    tooltip: "Open folder",
                    onTap: () => WinUtils.open(dir.path),
                  ),
                  const SizedBox(width: 6),
                  _ActionIconButton(
                    icon: Icons.delete_outline_rounded,
                    color: Colors.redAccent,
                    tooltip: "Delete folder",
                    onTap: () {
                      if (deleteWithoutConfirmation) {
                        if (actuallyDeleteFiles) File(dir.path).deleteSync(recursive: true);
                        DirectoryScan.deleteDir(dir.path);
                        redrawWidget!.value = !redrawWidget!.value;
                      } else {
                        showDialog(
                          context: context,
                          builder: (BuildContext context) {
                            return AlertDialog(
                              content:
                                  SizedBox(height: 100, child: Text("Are you sure you want to delete:\n ${dir.path}")),
                              actions: <Widget>[
                                ElevatedButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child:
                                      Text("Cancel", style: TextStyle(color: Color(globalSettings.theme.background))),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                  onPressed: () {
                                    if (actuallyDeleteFiles) File(dir.path).deleteSync(recursive: true);
                                    DirectoryScan.deleteDir(dir.path);
                                    Navigator.of(context).pop();
                                    redrawWidget!.value = !redrawWidget!.value;
                                  },
                                  child: const Text("Delete"),
                                ),
                              ],
                            );
                          },
                        ).then((_) {});
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      if (isExpanded) {
        rows.add(Padding(
            padding: const EdgeInsets.only(left: 8.0), child: FolderInfo(directory: dir.path, parentSize: dir.size)));
      }
    }
    int filesSize = DirectoryScan.dirs[DirectoryScan.names[widget.directory]!].size - totalFolderSize;
    final double percent =
        ((filesSize / (!percentageOfMainFolder ? widget.parentSize : DirectoryScan.main.size)) * 100);

    return Column(children: <Widget>[
      ...rows,
      Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: onSurface.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: onSurface.withValues(alpha: 0.06)),
        ),
        child: Row(children: <Widget>[
          const SizedBox(width: barWidth, child: Icon(Icons.description_outlined, size: 15)),
          SizedBox(
              width: 86,
              child:
                  Text(getFileSize(filesSize, 1), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
          PercentageBar(percent: percent, barWidth: barWidth),
          const SizedBox(width: 12),
          const Expanded(child: Text("Files", style: TextStyle(fontSize: 12))),
        ]),
      ),
      FutureBuilder<Map<String, int>>(
          future: listFilesSizes(parentDirectory),
          builder: (_, AsyncSnapshot<Map<String, int>> snapshot) {
            if (!snapshot.hasData) return Container();
            if (snapshot.data!.isEmpty) return Container();

            final List<Widget> filesWidget = <Widget>[];
            final Map<String, int> data = snapshot.data!;

            final List<MapEntry<String, int>> dataEntries = data.entries.toList();
            dataEntries.sort((MapEntry<String, int> a, MapEntry<String, int> b) => b.value.compareTo(a.value));
            if (dataEntries.length > 100) dataEntries.removeRange(100, dataEntries.length);

            for (MapEntry<String, int> file in dataEntries) {
              final double percent =
                  ((file.value / (!percentageOfMainFolder ? widget.parentSize : DirectoryScan.main.size)) * 100);

              filesWidget.add(
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: onSurface.withValues(alpha: 0.015),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: onSurface.withValues(alpha: 0.05)),
                  ),
                  child: Row(children: <Widget>[
                    const SizedBox(width: barWidth, child: Icon(Icons.description_outlined, size: 15)),
                    SizedBox(
                        width: 86,
                        child: Text(getFileSize(file.value, 1),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                    PercentageBar(percent: percent, barWidth: barWidth),
                    const SizedBox(width: 12),
                    Expanded(
                      child: MouseScrollWidget(
                        child: Text(
                          file.key.replaceFirst("$parentDirectory\\", ""),
                          style: TextStyle(fontSize: 12, color: onSurface.withValues(alpha: 0.82)),
                        ),
                      ),
                    ),
                    _ActionIconButton(
                      icon: Icons.delete_outline_rounded,
                      color: Colors.redAccent,
                      tooltip: "Delete file",
                      onTap: () {
                        if (deleteWithoutConfirmation) {
                          if (actuallyDeleteFiles) File(file.key).deleteSync();
                          DirectoryScan.deleteDir(file.key, file.value);
                          redrawWidget!.value = !redrawWidget!.value;
                        } else {
                          showDialog(
                            context: context,
                            builder: (BuildContext context) {
                              return AlertDialog(
                                content: SizedBox(
                                    height: 100, child: Text("Are you sure you want to delete:\n ${file.key}")),
                                actions: <Widget>[
                                  ElevatedButton(
                                    onPressed: () => Navigator.of(context).pop(),
                                    child:
                                        Text("Cancel", style: TextStyle(color: Color(globalSettings.theme.background))),
                                  ),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                    onPressed: () {
                                      if (actuallyDeleteFiles) File(file.key).deleteSync();
                                      DirectoryScan.deleteDir(file.key, file.value);
                                      Navigator.of(context).pop();
                                      redrawWidget!.value = !redrawWidget!.value;
                                    },
                                    child: const Text("Delete"),
                                  ),
                                ],
                              );
                            },
                          ).then((_) {});
                        }
                      },
                    ),
                  ]),
                ),
              );
            }
            return Column(children: <Widget>[...filesWidget]);
          }),
      Divider(height: 18, thickness: 1, color: onSurface.withValues(alpha: 0.08)),
    ]);
  }
}

class _ActionIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _ActionIconButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return CustomTooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.18)),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }
}

Future<void> listDirectoriesSizes(
    String dirPath, Function(int, int) ping, Function(Map<String, int> items) onDone) async {
  int fileNum = 0;

  dirPath.replaceAll('/', '\\');
  // if (dirPath.endsWith('\\')) dirPath = dirPath.substring(dirPath.length - 1);
  Directory dir = Directory(dirPath);
  final Map<String, int> totalFiles = <String, int>{};

  if (!dir.existsSync()) {
    onDone(<String, int>{"Empty": 0});
    return;
  }
  Stream<FileSystemEntity> stream = dir
      .list(recursive: true, followLinks: false)
      .handleError((dynamic e) => <dynamic, dynamic>{}, test: (dynamic e) => e is FileSystemException);
  totalFiles[dirPath] = 0;
  Future<bool> getFileInfo(FileSystemEntity entity) async {
    if (entity is File) {
      fileNum++;
      if (fileNum % 1000 == 0) ping(fileNum, 1);
      final int fileSize = await entity.length();
      int ticks = 0;
      Directory currentPath = entity.parent;
      do {
        ticks++;
        if (ticks > 100) break;

        totalFiles[currentPath.path] = (totalFiles[currentPath.path] ?? 0) + fileSize;
        if (currentPath.path == dirPath) break;
        currentPath = currentPath.parent;
      } while (true);
    }
    return true;
  }

  final TaskRunner<FileSystemEntity, bool> runner =
      TaskRunner<FileSystemEntity, bool>(getFileInfo, maxConcurrentTasks: 30);
  int total = 0;
  fileNum = 0;
  await for (FileSystemEntity entity in stream) {
    fileNum++;
    if (fileNum % 1000 == 0) ping(fileNum, 0);
    runner.add(entity);
    total++;
  }
  fileNum = 0;
  runner.startExecution();
  int totalProcessed = 0;
  runner.stream.forEach((bool listOfString) {
    totalProcessed++;
    if (totalProcessed >= total) {
      onDone(totalFiles);
      return;
    }
  });
}

Future<Map<String, int>> listFilesSizes(String dirPath) async {
  dirPath.replaceAll('/', '\\');
  Directory dir = Directory(dirPath);
  final Map<String, int> totalFiles = <String, int>{};

  if (dir.existsSync()) {
    Stream<FileSystemEntity> stream = dir
        .list(recursive: false, followLinks: false)
        .handleError((dynamic e) => <dynamic, dynamic>{}, test: (dynamic e) => e is FileSystemException);
    await for (FileSystemEntity entity in stream) {
      if (entity is File) {
        final int fileSize = entity.lengthSync();
        totalFiles[entity.path] = fileSize;
      }
    }
  }
  return totalFiles;
}

// https://dailydevsblog.com/troubleshoot/resolved-dart-exception-in-directory-list-121748/
String getFileSize(int bytes, int decimals) {
  if (bytes <= 0) return "0 B";
  const List<String> suffixes = <String>["B", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"];
  int i = (log(bytes) / log(1024)).floor();
  return '${(bytes / pow(1024, i)).toStringAsFixed(decimals)} ${suffixes[i]}';
}
