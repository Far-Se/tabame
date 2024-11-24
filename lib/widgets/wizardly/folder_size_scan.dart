// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';

import '../../models/settings.dart';
import '../../models/util/task_runner.dart';
import '../../models/win32/win32.dart';
import '../widgets/info_text.dart';
import '../widgets/mouse_scroll_widget.dart';
import '../widgets/percentage_bar.dart';

// vscode-fold=2
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

  static List<MapEntry<String, int>> getSubFolders(String folder) =>
      DirectoryScan.names.entries.where((MapEntry<String, int> element) => element.key.replaceFirst("$folder\\", '').contains(RegExp(r'^[^\\]*$'))).toList();
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
    return Column(
      mainAxisAlignment: Maa.start,
      crossAxisAlignment: Caa.stretch,
      children: <Widget>[
        Row(
          mainAxisAlignment: Maa.start,
          children: <Widget>[
            const SizedBox(width: 10),
            Flexible(
              flex: 5,
              fit: FlexFit.tight,
              child: ListTile(
                onTap: () async {
                  processedFiles = "";
                  DirectoryScan.clear();
                  finishedProcessing = false;
                  if (mounted) setState(() {});
                  WinUtils.toggleHiddenFiles(visible: true);
                  // currentFolder = await WinUtils.folderPicker();

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
                          content: Container(height: 100, child: const Text("Can't process Drive, only folders!")),
                          actions: <Widget>[
                            ElevatedButton(
                                onPressed: () => Navigator.of(context).pop(), child: Text("Ok", style: TextStyle(color: Color(globalSettings.theme.background)))),
                          ],
                        );
                      },
                    ).then((_) {});
                    return;
                  }
                  if (mounted) setState(() {});
                },
                leading: const Icon(Icons.folder_copy_sharp),
                title: const Text("Pick a folder"),
                subtitle: currentFolder.isEmpty ? const InfoText("Only folders, can not process Drives") : InfoText(currentFolder.truncate(50, suffix: "...")),
              ),
            ),
            Flexible(
              fit: FlexFit.loose,
              child: ElevatedButton(
                onPressed: () async {
                  if (currentFolder.contains(RegExp(r'^[A-Z]:\\$'))) {
                    currentFolder = "";

                    showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return AlertDialog(
                          content: Container(height: 100, child: const Text("Can't process Drive, only folders!")),
                          actions: <Widget>[
                            ElevatedButton(
                                onPressed: () => Navigator.of(context).pop(), child: Text("Ok", style: TextStyle(color: Color(globalSettings.theme.background)))),
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
                  //!HERE
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
                    processedFiles = " ${DirectoryScan.dirs.length} directories with a total of ${getFileSize(DirectoryScan.main.size, 1)}!";
                    if (mounted) setState(() {});
                  });
                },
                child: Text("Run", style: TextStyle(color: Color(globalSettings.theme.background))),
              ),
            ),
          ],
        ),
        Row(
          children: <Widget>[
            Expanded(
              child: CheckboxListTile(
                  dense: true,
                  value: percentageOfMainFolder,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text("Show Percentage of Main Folder"),
                  onChanged: (bool? newValue) {
                    percentageOfMainFolder = newValue ?? false;
                    setState(() {});
                  }),
            ),
            Expanded(
              child: CheckboxListTile(
                  dense: true,
                  value: deleteWithoutConfirmation,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text("Delete without confirmation"),
                  onChanged: (bool? newValue) {
                    deleteWithoutConfirmation = newValue ?? false;
                    setState(() {});
                  }),
            ),
          ],
        ),
        if (processedFiles.isNotEmpty) ListTile(title: Text(processedFiles)),
        if (finishedProcessing)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: ValueListenableBuilder<bool>(
              valueListenable: redrawWidget!,
              builder: (BuildContext context, Object? snapshot, Widget? e) {
                return Column(
                  children: <Widget>[
                    InkWell(
                      onTap: () {},
                      child: Row(
                        children: <Widget>[
                          const SizedBox(width: 50, child: Icon(Icons.folder, size: 15)),
                          SizedBox(width: 70, child: Text(getFileSize(DirectoryScan.main.size, 1))),
                          const PercentageBar(percent: 100, barWidth: 50),
                          Expanded(child: MouseScrollWidget(child: Text(DirectoryScan.main.path))),
                        ],
                      ),
                    ),
                    FolderInfo(directory: currentFolder, parentSize: DirectoryScan.main.size),
                  ],
                );
              },
            ),
          ),
      ],
    );
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
      final double percent = ((dir.size / (!percentageOfMainFolder ? widget.parentSize : DirectoryScan.main.size)) * 100);

      rows.add(
        Row(
          children: <Widget>[
            Expanded(
              flex: 2,
              child: InkWell(
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
                child: Row(
                  children: <Widget>[
                    SizedBox(
                        width: barWidth,
                        child:
                            !DirectoryScan.unfoldedDirectories.contains(dir.path) ? Icon(Icons.expand_more, color: Colors.grey.shade700) : const Icon(Icons.expand_less)),
                    SizedBox(width: 70, child: Text(getFileSize(dir.size, 1))),
                    PercentageBar(percent: percent, barWidth: barWidth),
                    Expanded(child: MouseScrollWidget(child: Text(dir.path.replaceFirst("$parentDirectory\\", '')))),
                    InkWell(onTap: () => WinUtils.open(dir.path), child: const SizedBox(width: 25, child: Icon(Icons.folder))),
                    SizedBox(
                      width: 25,
                      child: InkWell(
                          onTap: () {
                            if (deleteWithoutConfirmation) {
                              if (actuallyDeleteFiles) File(dir.path).deleteSync(recursive: true); //! delete Directory
                              DirectoryScan.deleteDir(dir.path);
                              redrawWidget!.value = !redrawWidget!.value;
                            } else {
                              showDialog(
                                context: context,
                                builder: (BuildContext context) {
                                  return AlertDialog(
                                    content: Container(height: 100, child: Text("Are you sure you want to delete:\n ${dir.path}")),
                                    actions: <Widget>[
                                      ElevatedButton(
                                          onPressed: () => Navigator.of(context).pop(),
                                          child: Text("Cancel", style: TextStyle(color: Color(globalSettings.theme.background)))),
                                      ElevatedButton(
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                          onPressed: () {
                                            if (actuallyDeleteFiles) File(dir.path).deleteSync(recursive: true); //! delete Directory
                                            DirectoryScan.deleteDir(dir.path);
                                            Navigator.of(context).pop();
                                            redrawWidget!.value = !redrawWidget!.value;
                                          },
                                          child: const Text("Delete")),
                                    ],
                                  );
                                },
                              ).then((_) {});
                            }
                          },
                          child: const Icon(Icons.delete)),
                    ),
                    const SizedBox(width: 10),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

      if (DirectoryScan.unfoldedDirectories.contains(dir.path)) {
        rows.add(Padding(padding: const EdgeInsets.only(left: 5.0), child: FolderInfo(directory: dir.path, parentSize: dir.size)));
      }
    }
    int filesSize = DirectoryScan.dirs[DirectoryScan.names[widget.directory]!].size - totalFolderSize;
    final double percent = ((filesSize / (!percentageOfMainFolder ? widget.parentSize : DirectoryScan.main.size)) * 100);

    return Column(children: <Widget>[
      ...rows,
      Row(children: <Widget>[
        const SizedBox(width: barWidth, child: Icon(Icons.description, size: 15)),
        SizedBox(width: 70, child: Text(getFileSize(filesSize, 1))),
        PercentageBar(percent: percent, barWidth: barWidth),
        const Expanded(child: Text("Files")),
      ]),
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
              final double percent = ((file.value / (!percentageOfMainFolder ? widget.parentSize : DirectoryScan.main.size)) * 100);

              filesWidget.add(InkWell(
                onTap: () {},
                child: Row(children: <Widget>[
                  const SizedBox(width: barWidth, child: Icon(Icons.description, size: 15)),
                  SizedBox(width: 70, child: Text(getFileSize(file.value, 1))),
                  PercentageBar(percent: percent, barWidth: barWidth),
                  Expanded(child: MouseScrollWidget(child: Text(file.key.replaceFirst("$parentDirectory\\", "")))),
                  SizedBox(
                    width: 25,
                    child: InkWell(
                        onTap: () {
                          if (deleteWithoutConfirmation) {
                            if (actuallyDeleteFiles) File(file.key).deleteSync(); //! delete File
                            DirectoryScan.deleteDir(file.key, file.value);
                            redrawWidget!.value = !redrawWidget!.value;
                          } else {
                            showDialog(
                              context: context,
                              builder: (BuildContext context) {
                                return AlertDialog(
                                  content: Container(height: 100, child: Text("Are you sure you want to delete:\n ${file.key}")),
                                  actions: <Widget>[
                                    ElevatedButton(
                                        onPressed: () => Navigator.of(context).pop(),
                                        child: Text("Cancel", style: TextStyle(color: Color(globalSettings.theme.background)))),
                                    ElevatedButton(
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                        onPressed: () {
                                          if (actuallyDeleteFiles) File(file.key).deleteSync(); //! delete file
                                          DirectoryScan.deleteDir(file.key, file.value);
                                          Navigator.of(context).pop();
                                          redrawWidget!.value = !redrawWidget!.value;
                                        },
                                        child: const Text("Delete")),
                                  ],
                                );
                              },
                            ).then((_) {});
                          }
                        },
                        child: const Icon(Icons.delete)),
                  ),
                  const SizedBox(width: 20),
                ]),
              ));
            }
            return Column(children: <Widget>[...filesWidget]);
          }),
      const Divider(height: 5, thickness: 2),
    ]);
  }
}

Future<void> listDirectoriesSizes(String dirPath, Function(int, int) ping, Function(Map<String, int> items) onDone) async {
  int fileNum = 0;

  dirPath.replaceAll('/', '\\');
  // if (dirPath.endsWith('\\')) dirPath = dirPath.substring(dirPath.length - 1);
  Directory dir = Directory(dirPath);
  final Map<String, int> totalFiles = <String, int>{};

  if (!dir.existsSync()) {
    onDone(<String, int>{"Empty": 0});
    return;
  }
  Stream<FileSystemEntity> stream =
      dir.list(recursive: true, followLinks: false).handleError((dynamic e) => print('Ignoring error: $e'), test: (dynamic e) => e is FileSystemException);
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

  final TaskRunner<FileSystemEntity, bool> runner = TaskRunner<FileSystemEntity, bool>(getFileInfo, maxConcurrentTasks: 30);
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
    Stream<FileSystemEntity> stream =
        dir.list(recursive: false, followLinks: false).handleError((dynamic e) => print('Ignoring error: $e'), test: (dynamic e) => e is FileSystemException);
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
getFileSize(int bytes, int decimals) {
  if (bytes <= 0) return "0 B";
  const List<String> suffixes = <String>["B", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"];
  int i = (log(bytes) / log(1024)).floor();
  return '${(bytes / pow(1024, i)).toStringAsFixed(decimals)} ${suffixes[i]}';
}
