// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../models/utils.dart';
import '../../models/win32/win32.dart';
import '../widgets/info_text.dart';
import '../widgets/mouse_scroll_widget.dart';

class FileSizeWidget extends StatefulWidget {
  const FileSizeWidget({Key? key}) : super(key: key);

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
}

bool percentageOfMainFolder = false;
bool deleteWithoutConfirmation = false;
ValueNotifier<bool>? recalculate;

class FileSizeWidgetState extends State<FileSizeWidget> {
  String currentFolder = r"E:\Playground\CPP";

  String processedFiles = "";

  bool finishedProcessing = false;
  Timer? timerCheckHeight;
  double lastHeight = 0;

  @override
  void initState() {
    recalculate = ValueNotifier<bool>(false);
    super.initState();
    timerCheckHeight = Timer.periodic(const Duration(milliseconds: 10), (Timer timer) {
      double newheight = MediaQuery.of(context).size.height;
      if (newheight != lastHeight) {
        lastHeight = newheight;
        if (mounted) setState(() {});
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
    recalculate?.dispose();
    timerCheckHeight?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      clipBehavior: Clip.hardEdge,
      child: Column(
        mainAxisAlignment: Maa.start,
        // crossAxisAlignment: Caa.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: Maa.start,
            children: <Widget>[
              const SizedBox(width: 20),
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
                    currentFolder = await WinUtils.folderPicker();
                    WinUtils.toggleHiddenFiles(visible: false);
                    if (mounted) setState(() {});
                  },
                  leading: const Icon(Icons.folder_copy_sharp),
                  title: const Text("Pick a folder"),
                  subtitle: currentFolder.isEmpty ? const Text("-") : InfoText(currentFolder.truncate(50, suffix: "...")),
                ),
              ),
              Flexible(
                fit: FlexFit.loose,
                child: ElevatedButton(
                  onPressed: () async {
                    finishedProcessing = false;
                    setState(() {});
                    if (currentFolder.isEmpty) return;
                    //!HERE
                    final Map<String, int> allDirs = await listDirectoriesSizes(currentFolder, (int total) {
                      processedFiles = "Processed $total files ...";
                      if (mounted) setState(() {});
                    });
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

                    DirectoryScan.main = DirectoryScan.dirs[DirectoryScan.names[currentFolder]!];
                    finishedProcessing = true;
                    processedFiles = " ${DirectoryScan.dirs.length} directories in total of  ${getFileSize(DirectoryScan.main.size, 1)}!";
                    if (mounted) setState(() {});
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
              child: Container(
                height: lastHeight - 400,
                child: ValueListenableBuilder<bool>(
                  valueListenable: recalculate!,
                  builder: (BuildContext context, Object? snapshot, Widget? e) {
                    return SingleChildScrollView(
                        controller: AdjustableScrollController(), child: FolderInfo(key: UniqueKey(), directory: currentFolder, parentSize: DirectoryScan.main.size));
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class FolderInfo extends StatefulWidget {
  final String directory;
  final int parentSize;
  const FolderInfo({
    Key? key,
    required this.directory,
    required this.parentSize,
  }) : super(key: key);

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
    final List<MapEntry<String, int>> list = DirectoryScan.getSubFolders(widget.directory);

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
        Column(
          mainAxisAlignment: Maa.center,
          children: <Widget>[
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
                    child: Column(
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            SizedBox(width: barWidth, child: Icon(!DirectoryScan.unfoldedDirectories.contains(dir.path) ? Icons.expand_more : Icons.expand_less)),
                            SizedBox(width: 70, child: Text(getFileSize(dir.size, 1))),
                            PercentageBar(percent: percent, barWidth: barWidth),
                            Expanded(child: MouseScrollWidget(child: Text(dir.path.replaceFirst("${widget.directory}\\", '')))),
                            InkWell(onTap: () => WinUtils.open(dir.path), child: const SizedBox(width: 25, child: Icon(Icons.folder))),
                            SizedBox(
                              width: 25,
                              child: InkWell(
                                  onTap: () {
                                    if (deleteWithoutConfirmation) {
                                      final int dirSize = dir.size;
                                      File(dir.path).deleteSync(recursive: true); //! delete file
                                      dir.deleted = true;
                                      Directory dirPath = Directory(dir.path);
                                      int ticks = 0;
                                      do {
                                        ticks++;
                                        if (ticks > 1000) {
                                          break;
                                        }
                                        if (DirectoryScan.names.containsKey(dirPath.path)) {
                                          DirectoryScan.dirs[DirectoryScan.names[dirPath.path]!].size -= dirSize;
                                        } else {}
                                        if (dirPath.path == DirectoryScan.main.path) break;
                                        dirPath = dirPath.parent;
                                      } while (true);
                                      recalculate!.value = !recalculate!.value;
                                    } else {
                                      final int dirSize = dir.size;
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
                                                  style: ElevatedButton.styleFrom(primary: Colors.red),
                                                  onPressed: () {
                                                    File(dir.path).deleteSync(recursive: true); //! delete file
                                                    dir.deleted = true;
                                                    Directory dirPath = Directory(dir.path);
                                                    int ticks = 0;
                                                    do {
                                                      ticks++;
                                                      if (ticks > 1000) {
                                                        break;
                                                      }
                                                      if (DirectoryScan.names.containsKey(dirPath.path)) {
                                                        DirectoryScan.dirs[DirectoryScan.names[dirPath.path]!].size -= dirSize;
                                                      }
                                                      if (dirPath.path == DirectoryScan.main.path) break;
                                                      dirPath = dirPath.parent;
                                                    } while (true);
                                                    Navigator.of(context).pop();
                                                    recalculate!.value = !recalculate!.value;
                                                    // setState(() {});
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
                      ],
                    ),
                  ),
                ),
              ],
            )
          ],
        ),
      );

      if (DirectoryScan.unfoldedDirectories.contains(dir.path)) {
        rows.add(Padding(padding: const EdgeInsets.only(left: 5.0), child: FolderInfo(key: UniqueKey(), directory: dir.path, parentSize: dir.size)));
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
          future: listFilesSizes(widget.directory),
          builder: (_, AsyncSnapshot<Map<String, int>> snapshot) {
            if (!snapshot.hasData) return Container();
            if (snapshot.data!.isEmpty) return Container();

            final List<Widget> filesWidget = <Widget>[];
            final Map<String, int> data = snapshot.data!;

            for (MapEntry<String, int> file in data.entries) {
              final double percent = ((file.value / widget.parentSize) * 100);

              filesWidget.add(InkWell(
                onTap: () {},
                child: Row(children: <Widget>[
                  const SizedBox(width: barWidth, child: Icon(Icons.description, size: 15)),
                  SizedBox(width: 70, child: Text(getFileSize(file.value, 1))),
                  PercentageBar(percent: percent, barWidth: barWidth),
                  Expanded(child: MouseScrollWidget(child: Text(file.key.replaceFirst("${widget.directory}\\", "")))),
                  SizedBox(
                    width: 25,
                    child: InkWell(
                        onTap: () {
                          if (deleteWithoutConfirmation) {
                            final int dirSize = file.value;
                            File(file.key).deleteSync(); //! delete file
                            Directory dirPath = Directory(file.key);
                            int ticks = 0;
                            do {
                              ticks++;
                              if (ticks > 1000) break;

                              if (DirectoryScan.names.containsKey(dirPath.path)) {
                                DirectoryScan.dirs[DirectoryScan.names[dirPath.path]!].size -= dirSize;
                              }
                              if (dirPath.path == DirectoryScan.main.path) break;
                              dirPath = dirPath.parent;
                            } while (true);
                            recalculate!.value = !recalculate!.value;
                          } else {
                            final int dirSize = file.value;
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
                                        style: ElevatedButton.styleFrom(primary: Colors.red),
                                        onPressed: () {
                                          File(file.key).deleteSync(); //! delete file
                                          Directory dirPath = Directory(file.key);
                                          int ticks = 0;
                                          do {
                                            ticks++;
                                            if (ticks > 1000) break;

                                            if (DirectoryScan.names.containsKey(dirPath.path)) {
                                              DirectoryScan.dirs[DirectoryScan.names[dirPath.path]!].size -= dirSize;
                                            }
                                            if (dirPath.path == DirectoryScan.main.path) break;
                                            dirPath = dirPath.parent;
                                          } while (true);
                                          Navigator.of(context).pop();
                                          recalculate!.value = !recalculate!.value;
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

class PercentageBar extends StatelessWidget {
  const PercentageBar({
    Key? key,
    required this.percent,
    required this.barWidth,
  }) : super(key: key);

  final double percent;
  final double barWidth;

  @override
  Widget build(BuildContext context) {
    double percent2 = percent;
    if (percent2.isNaN) percent2 = 0;
    double bar = percent / (100 / barWidth);
    if (bar.isNaN) bar = 0;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Tooltip(
        message: "${percent2.toStringAsFixed(2)}%",
        child: SizedBox(
            width: barWidth,
            height: 10,
            child: Stack(
              children: <Widget>[
                Container(width: barWidth, height: 30, color: Color(globalSettings.theme.textColor).withOpacity(0.2)),
                Positioned(top: 0, left: 0, child: Container(width: bar, height: 30, color: Color(globalSettings.theme.accentColor))),
              ],
            )),
      ),
    );
  }
}

Future<Map<String, int>> listDirectoriesSizes(String dirPath, Function(int) ping) async {
  int fileNum = 0;

  dirPath.replaceAll('/', '\\');
  if (dirPath.endsWith('\\')) dirPath = dirPath.substring(dirPath.length - 1);
  Directory dir = Directory(dirPath);
  final Map<String, int> totalFiles = <String, int>{};

  if (dir.existsSync()) {
    Stream<FileSystemEntity> stream =
        dir.list(recursive: true, followLinks: false).handleError((dynamic e) => print('Ignoring error: $e'), test: (dynamic e) => e is FileSystemException);
    await for (FileSystemEntity entity in stream) {
      if (entity is File) {
        fileNum++;
        if (fileNum % 1000 == 0) ping(fileNum);
        final int fileSize = entity.lengthSync();
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
    }
  }

  if (totalFiles.isEmpty) {
    totalFiles["Empty"] = 0;
    return totalFiles;
  }
  return totalFiles;
}

Future<Map<String, int>> listFilesSizes(String dirPath) async {
  dirPath.replaceAll('/', '\\');
  if (dirPath.endsWith('\\')) dirPath = dirPath.substring(dirPath.length - 1);
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
  // if (totalFiles.isEmpty) {
  //   totalFiles["Empty"] = 0;
  //   return totalFiles;
  // }
  return totalFiles;
}

// https://dailydevsblog.com/troubleshoot/resolved-dart-exception-in-directory-list-121748/
getFileSize(int bytes, int decimals) {
  if (bytes <= 0) return "0 B";
  const List<String> suffixes = <String>["B", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"];
  int i = (log(bytes) / log(1024)).floor();
  return '${(bytes / pow(1024, i)).toStringAsFixed(decimals)} ${suffixes[i]}';
}
