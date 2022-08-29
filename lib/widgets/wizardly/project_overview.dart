// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';

import '../../models/classes/boxes.dart';
import '../../models/settings.dart';
import '../../models/util/task_runner.dart';
import '../../models/win32/win32.dart';
import '../widgets/checkbox_widget.dart';
import '../widgets/info_text.dart';
import '../widgets/text_input.dart';

class ProjectOverviewWidget extends StatefulWidget {
  const ProjectOverviewWidget({Key? key}) : super(key: key);

  @override
  ProjectOverviewWidgetState createState() => ProjectOverviewWidgetState();
}

class Project {
  List<ProjectFile> projectFiles = <ProjectFile>[];
  int totalComments = -1;
  int totalLines = -1;
  int totalCode = -1;
  int totalEmpty = -1;
  int totalNonCde = -1;
  int totalChars = -1;
  List<List<String>> _langaugeList = <List<String>>[];
  List<List<String>> get programmingLanguages {
    if (_langaugeList.isNotEmpty) return _langaugeList;
    final Map<String, int> exts = <String, int>{};
    for (final ProjectFile file in projectFiles) {
      if (!exts.containsKey(file.ext)) {
        exts[file.ext] = file.total.lines;
      } else {
        exts[file.ext] = exts[file.ext]! + file.total.lines;
      }
    }
    //order exts by value
    final List<MapEntry<String, int>> extsList = exts.entries.toList();
    extsList.sort((MapEntry<String, int> a, MapEntry<String, int> b) => b.value.compareTo(a.value));
    _langaugeList = extsList.map((MapEntry<String, int> entry) => <String>[entry.key, entry.value.toString()]).toList();
    return _langaugeList;
  }
}

class ProjectOverviewWidgetState extends State<ProjectOverviewWidget> {
  Map<String, Color> extColors = <String, Color>{};
  List<String> loadedFiles = <String>[];
  String infoText = "";

  final List<int> extensionColors = <int>[0xff34B7FD, 0xffCB4802, 0xffFFA700, 0xffC3732A, 0xffA4DDED, 0xff922724, 0xff43B3AE, 0xffA020F0];

  Project project = Project();
  String projectFolder = r"";
  String projectIncluded = "";
  String projectExcluded = "";
  bool searchFinished = false;

  int stateFileProcessing = 0;

  bool projectAnalyzed = false;

  bool projectUseGitIgnore = true;

  @override
  void initState() {
    projectFolder = Boxes.pref.getString("projectOverviewFolder") ?? "";
    projectIncluded = Boxes.pref.getString("projectOverviewIncluded") ?? "";
    projectExcluded = Boxes.pref.getString("projectOverviewExcluded") ?? r"^\.[a-z];node_modules;(json|ml)$;\w{4,}$";

    if (globalSettings.args.contains("-wizardly")) {
      projectFolder = globalSettings.args[0].replaceAll('"', '');
    }
    super.initState();
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
              flex: 4,
              fit: FlexFit.tight,
              child: ListTile(
                onTap: () async {
                  infoText = "";
                  stateFileProcessing = 0;
                  projectAnalyzed = false;
                  project = Project();

                  if (mounted) setState(() {});

                  final DirectoryPicker dirPicker = DirectoryPicker()..title = 'Select any folder';
                  final Directory? dir = dirPicker.getDirectory();
                  if (dir == null) return;
                  // loadedFiles.clear();
                  projectFolder = dir.path;
                  Boxes.updateSettings("projectOverviewFolder", projectFolder);

                  if (!Directory(projectFolder).existsSync()) return;
                  if (mounted) setState(() {});
                },
                leading: const Icon(Icons.folder_copy_sharp),
                title: const Text("Pick a folder"),
                subtitle: projectFolder.isEmpty ? const InfoText("-") : InfoText(projectFolder.truncate(50, suffix: "...")),
              ),
            ),
            Flexible(
              fit: FlexFit.loose,
              child: Column(
                children: <Widget>[
                  ElevatedButton(
                    onPressed: () async {
                      if (stateFileProcessing == 1) {
                        stateFileProcessing = 2;
                        return;
                      }
                      stateFileProcessing = 1;
                      setState(() {});
                      await loadFiles();
                      projectAnalyzed = false;
                      getCode();
                      setState(() {});
                    },
                    child: Text(stateFileProcessing == 0 ? "Generate" : "Cancel", style: TextStyle(color: Color(globalSettings.theme.background))),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () async {
                      showDialog(
                        context: context,
                        builder: (BuildContext context) {
                          return AlertDialog(
                            content: LoadFromGitWidget(onSelected: (String folder) {
                              Navigator.of(context).pop();
                              projectFolder = folder;
                              if (!Directory(projectFolder).existsSync()) return;
                              if (mounted) setState(() {});
                            }),
                            actions: <Widget>[
                              ElevatedButton(
                                  onPressed: () => Navigator.of(context).pop(), child: Text("Cancel", style: TextStyle(color: Theme.of(context).backgroundColor))),
                            ],
                          );
                        },
                      ).then((_) {});
                      setState(() {});
                    },
                    child: const Text("Load from Git"),
                  )
                ],
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 5),
          child: Row(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10.0),
                child: Column(
                  children: <Widget>[],
                ),
              ),
              Expanded(
                flex: 3,
                child: TextInput(
                    key: UniqueKey(),
                    hintText: "Separated by ';' ex: cpp;dart;js",
                    labelText: "Include files with extension",
                    value: projectIncluded,
                    onChanged: (String e) {
                      if (stateFileProcessing != 0) return;
                      Boxes.updateSettings("projectOverviewIncluded", e);
                      loadedFiles.clear();
                      projectIncluded = e;
                      setState(() {});
                    }),
              ),
              Expanded(
                flex: 3,
                child: TextInput(
                    key: UniqueKey(),
                    labelText: "Ignore these files/folders",
                    value: projectExcluded,
                    onChanged: (String e) {
                      if (stateFileProcessing != 0) return;
                      Boxes.updateSettings("projectOverviewExcluded", e);
                      loadedFiles.clear();
                      projectExcluded = e;
                      setState(() {});
                    }),
              )
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 20.0),
          child: SizedBox(
            width: 130,
            child: CheckBoxWidget(
              value: projectUseGitIgnore,
              onChanged: (bool e) async {
                projectUseGitIgnore = e;
                loadedFiles.clear();
                if (mounted) setState(() {});
              },
              text: 'Use .gitignore',
            ),
          ),
        ),
        if (projectAnalyzed && project.totalLines <= 1) const Center(child: Text("No files found!")),
        if (projectAnalyzed && project.totalLines > 1)
          ...List<Widget>.from(
            <Widget>[
              Markdown(
                selectable: true,
                controller: ScrollController(),
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                data: '''
This project has a total of ${project.projectFiles.length} files with a total of **${project.totalLines.decimal} lines**, from which:
- ${project.totalCode.decimal} are code lines
- ${project.totalNonCde.decimal} are non code lines `()[]{}` 
- ${project.totalComments.decimal} are comment lines *
- ${project.totalEmpty.decimal} are empty

Summing **${project.totalChars.decimal}** characters! An average book has 250 characters per page with a total of 400 pages.
That means this project has **${((project.totalChars / 250).floor()).decimal} pages** divided in **${(project.totalChars / 250 / 400).toStringAsFixed(1)} books**!
''',
              ),
              Container(
                height: 150,
                width: 500,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: PieChart(
                        PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: 30,
                          pieTouchData: PieTouchData(enabled: true),
                          sections: List<PieChartSectionData>.generate(project.programmingLanguages.length, (int index) {
                            final double percentage = (int.parse(project.programmingLanguages[index][1]) / project.totalLines) * 100;
                            return PieChartSectionData(
                                title: project.programmingLanguages[index][0],
                                value: percentage,
                                color: extColors.containsKey(project.programmingLanguages[index][0]) ? extColors[project.programmingLanguages[index][0]] : Colors.grey,
                                showTitle: (int.parse(project.programmingLanguages[index][1]) / project.totalLines) * 100 < 10 ? false : true);
                          }),
                        ),
                        swapAnimationDuration: const Duration(milliseconds: 150),
                        swapAnimationCurve: Curves.linear,
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                          itemCount: project.programmingLanguages.length,
                          controller: ScrollController(),
                          itemBuilder: (BuildContext context, int index) {
                            return InkWell(
                              onTap: () {},
                              child: Text("${project.programmingLanguages[index][0]}: ${int.parse(project.programmingLanguages[index][1]).decimal} lines"),
                            );
                          }),
                    )
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const SizedBox(height: 20),
                    const Align(
                      alignment: Alignment.centerRight,
                      child: InfoText("You can sort by column"),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(child: Text(project.projectFiles.length > 150 ? "First 150 files" : "File")),
                        InkWell(
                            onTap: () {
                              project.projectFiles.sort((ProjectFile a, ProjectFile b) => a.total.lines > b.total.lines ? -1 : 1);
                              setState(() {});
                            },
                            child: SizedBox(width: 70, child: Text("Lines", style: Theme.of(context).textTheme.button))),
                        InkWell(
                            onTap: () {
                              project.projectFiles.sort((ProjectFile a, ProjectFile b) => a.total.code > b.total.code ? -1 : 1);
                              setState(() {});
                            },
                            child: SizedBox(width: 70, child: Text("Code", style: Theme.of(context).textTheme.button))),
                        InkWell(
                            onTap: () {
                              project.projectFiles.sort((ProjectFile a, ProjectFile b) => a.total.nonCode > b.total.nonCode ? -1 : 1);
                              setState(() {});
                            },
                            child: SizedBox(width: 70, child: Text("NonCode", style: Theme.of(context).textTheme.button))),
                        InkWell(
                          onTap: () {
                            project.projectFiles.sort((ProjectFile a, ProjectFile b) => a.total.comments > b.total.comments ? -1 : 1);
                            setState(() {});
                          },
                          child: SizedBox(
                              width: 70,
                              child: Tooltip(
                                  message: "For common programming languages it works well\nIf you have bad comment formats it might break.",
                                  child: Text("Comm*", style: Theme.of(context).textTheme.button))),
                        ),
                        InkWell(
                            onTap: () {
                              project.projectFiles.sort((ProjectFile a, ProjectFile b) => a.total.empty > b.total.empty ? -1 : 1);
                              setState(() {});
                            },
                            child: SizedBox(width: 70, child: Text("Empty", style: Theme.of(context).textTheme.button))),
                        InkWell(
                            onTap: () {
                              project.projectFiles.sort((ProjectFile a, ProjectFile b) => a.total.characters > b.total.characters ? -1 : 1);
                              setState(() {});
                            },
                            child: SizedBox(width: 70, child: Text("Chars", style: Theme.of(context).textTheme.button))),
                      ],
                    ),
                    ...List<Widget>.generate(
                      project.projectFiles.length.clamp(0, 150),
                      (int index) => InkWell(
                        onTap: () {},
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.start,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Expanded(
                                    child: Row(
                                      children: <Widget>[
                                        Center(
                                          child: Padding(
                                            padding: const EdgeInsets.only(top: 2.0),
                                            child: Container(
                                              width: 10,
                                              height: 10,
                                              color: extColors.containsKey(project.projectFiles[index].ext) ? extColors[project.projectFiles[index].ext] : Colors.grey,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                        Expanded(
                                          child: Text(
                                            project.projectFiles[index].name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            // style: const TextStyle(height: 1.001),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(width: 70, child: Text(project.projectFiles[index].total.lines.decimal)),
                            SizedBox(width: 70, child: Text(project.projectFiles[index].total.code.decimal)),
                            SizedBox(width: 70, child: Text(project.projectFiles[index].total.nonCode.decimal)),
                            SizedBox(width: 70, child: Text(project.projectFiles[index].total.comments.decimal)),
                            SizedBox(width: 70, child: Text(project.projectFiles[index].total.empty.decimal)),
                            SizedBox(width: 70, child: Text(project.projectFiles[index].total.characters.decimal)),
                          ],
                        ),
                      ),
                    )
                  ],
                ),
              ),
            ],
          ),
        const SizedBox(height: 20),
      ],
    );
  }

  Future<void> getCode() async {
    project.programmingLanguages.clear();
    project.projectFiles.clear();
    final List<String> auxFiles = <String>[...loadedFiles];
    Future<bool> getFileInfo(String file) async {
      final Future<List<String>> futureLines = File(file).readAsLines().catchError((_) {
        return <String>[];
      });
      List<String> fileLines = await futureLines;
      if (fileLines.isEmpty) {
        loadedFiles.remove(file);
        return true;
      }
      final String filePath = file.replaceFirst("$projectFolder\\", "");
      final String fileName = filePath.split(r'\').last;
      final String fileExtension = filePath.split('.').last;
      final TotalCode total = TotalCode();
      total.lines = fileLines.length;
      bool inComment = false;
      String commentStart = "/*";
      String commentEnd = "*/";
      String comment = "//";
      if (multiLineComment.keys.contains(fileExtension)) {
        commentStart = multiLineComment[fileExtension]!.multiCommentStart;
        commentEnd = multiLineComment[fileExtension]!.multiCommentEnd;
      }

      if (<String>["py", "ps1", "py", "pyi", "pyc", "pyd", "pyo", "pyw", "pyz", "rb", "ps1", "r"].contains("fileExtension")) comment = "#";

      for (String line in fileLines) {
        total.characters += line.trim().length;
        //? comment section
        if (line.contains(commentStart)) {
          bool hascode = false;
          if (line.contains(commentEnd) && RegExp(r'[^\w]+?' + commentStart).hasMatch(line)) {
            if (!RegExp(r'^\w.*?' + commentStart).hasMatch(line)) {
              total.comments++;
              continue;
            }
            hascode = true;
          } else if (!RegExp(r"\w").hasMatch(line)) {
            total.comments++;
          } else {
            total.code++;
          }
          if (!hascode) {
            inComment = true;
            continue;
          }
        } else if (line.contains(commentEnd)) {
          inComment = false;
          total.comments++;
          continue;
        } else if (inComment) {
          total.comments++;
          continue;
        } else if (line.contains(comment)) {
          if (line.startsWith('//') || RegExp(r'^[ \t]+?' + comment).hasMatch(line)) {
            total.comments++;
            continue;
          } else {
            line = line.replaceFirst(RegExp(r'//*.*?$'), '');
          }
        }
        //? code lines
        if (line.isEmpty) {
          total.empty++;
        } else if (RegExp(r'^\s+$', multiLine: true).hasMatch(line)) {
          total.empty++;
        } else if (!RegExp(r'\w').hasMatch(line)) {
          total.nonCode++;
        } else {
          total.code++;
        }
      }
      total.empty += total.lines - (total.code + total.comments + total.nonCode + total.empty);
      project.projectFiles.add(ProjectFile(name: fileName, path: filePath, ext: fileExtension, total: total));
      return true;
    }

    final TaskRunner<String, bool> runner = TaskRunner<String, bool>(getFileInfo, maxConcurrentTasks: 30);
    for (String file in auxFiles) {
      if (stateFileProcessing == 2) {
        stateFileProcessing = 0;
        if (mounted) setState(() {});
        return;
      }
      runner.add(file);
    }
    runner.startExecution();
    int totalProcessed = 0;
    runner.stream.forEach((bool listOfString) {
      totalProcessed++;
      if (totalProcessed >= auxFiles.length) {
        stateFileProcessing = 0;
        projectAnalyzed = true;
        project.projectFiles.sort((ProjectFile a, ProjectFile b) => b.total.lines.compareTo(a.total.lines));
        project.totalComments = project.projectFiles.fold(0, (int previousValue, ProjectFile element) => previousValue + element.total.comments);
        project.totalLines = project.projectFiles.fold(0, (int previousValue, ProjectFile element) => previousValue + element.total.lines);
        project.totalCode = project.projectFiles.fold(0, (int previousValue, ProjectFile element) => previousValue + element.total.code);
        project.totalEmpty = project.projectFiles.fold(0, (int previousValue, ProjectFile element) => previousValue + element.total.empty);
        project.totalNonCde = project.projectFiles.fold(0, (int previousValue, ProjectFile element) => previousValue + element.total.nonCode);
        project.totalChars = project.projectFiles.fold(0, (int previousValue, ProjectFile element) => previousValue + element.total.characters);

        int i = 0;
        for (List<String> x in project.programmingLanguages) {
          if (i >= extensionColors.length) break;
          extColors[x[0]] = Color(extensionColors[i]);
          i++;
        }
        if (mounted) setState(() {});
      }
    });
  }

  Future<void> loadFiles() async {
    final File gitignoreFile = File("$projectFolder\\.gitignore");
    final List<String> gitIgnore = <String>[];
    if (gitignoreFile.existsSync() && projectUseGitIgnore) {
      final List<String> lines = gitignoreFile.readAsLinesSync();
      for (String line in lines) {
        if (line.isEmpty) continue;
        line = line.trim();
        if (line[0] == "#") continue;
        line = line.replaceAll(RegExp(r'#.*?$'), '');
        line = line.trim();
        line.replaceAll('**', '*');
        if (line[0] == "*") {
          if (line.characters.last != "/") line += "/";
          line = line.substring(1);
        } else if (line[0] != '/') {
          line = "/$line";
        }
        line = line.replaceAll('.', r'\.');
        line = line.replaceAll('*', '.*');
        line = line.replaceAll('/', r'\\');
        bool regexWorked = true;
        try {
          RegExp(line).hasMatch("ciulama");
        } catch (e) {
          regexWorked = false;
        }
        if (regexWorked) {
          gitIgnore.add(line);
        }
      }
    }
    final List<String> allFiles = <String>[];
    Stream<FileSystemEntity> stream =
        Directory(projectFolder).list(recursive: true, followLinks: false).handleError((dynamic e) => null, test: (dynamic e) => e is FileSystemException);
    await for (FileSystemEntity entity in stream) {
      bool add = true;
      for (String gitLine in gitIgnore) {
        if (RegExp(gitLine).hasMatch(entity.path)) {
          add = false;
        }
      }
      if (add) {
        allFiles.add(entity.path);
      }
    }
    final List<String> included = projectIncluded.isNotEmpty ? projectIncluded.split(';') : <String>[];
    final List<String> excluded = projectExcluded.isNotEmpty ? projectExcluded.split(';') : <String>[];
    loadedFiles.clear();
    for (String file in allFiles) {
      final String fileDirectory = Directory(file).parent.path;
      final String fileName = file.replaceAll("$fileDirectory\\", "");
      if (fileName.endsWith(".svg")) continue;
      if (fileName.endsWith(".lock")) continue;
      if (fileName.indexOf('.') < 1) continue;
      bool skip = false;

      for (String exclude in excluded) {
        if (exclude == "") continue;
        if (exclude[0] == '^') {
          exclude = exclude.substring(1);
          if (file.contains(RegExp(r"\\" + exclude + r"[^\\]*\\", caseSensitive: false))) {
            skip = true;
            break;
          }
        } else if (exclude[0] == "/" || exclude[0] == r"\\") {
          exclude = exclude.substring(exclude[0] == "/" ? 1 : 2);
          if (file.replaceFirst(projectFolder, '').contains(RegExp(r"^\\" + exclude + r"[^\\]*\\", caseSensitive: false))) {
            skip = true;
            break;
          }
        } else if (file.contains(RegExp(r"[^\\]" + exclude + r"[^\\]*\\", caseSensitive: false))) {
          skip = true;
          break;
        } else {
          if (RegExp(exclude, caseSensitive: false).hasMatch(file)) {
            skip = true;
            break;
          }
        }
      }
      if (skip) continue;

      if (included.isNotEmpty) {
        skip = true;
        for (String include in included) {
          if (include == "") continue;
          if (fileName.contains(RegExp("$include\$", caseSensitive: false))) {
            skip = false;
          }
        }
        if (skip) continue;
      }

      loadedFiles.add(file);
    }
    // return newFileList;
  }
}

extension DecimalFormat on int {
  String get decimal => NumberFormat.decimalPattern().format(this);
}

class TotalCode {
  int lines = 0;
  int comments = 0;
  int code = 0;
  int empty = 0;
  int nonCode = 0;
  int characters = 0;
  @override
  String toString() {
    return 'TotalCode(lines: $lines, comments: $comments, code: $code, empty: $empty, nonCode: $nonCode, characters: $characters)';
  }
}

class ProjectFile {
  String path;
  String name;
  String ext;
  TotalCode total;
  ProjectFile({
    required this.path,
    required this.name,
    required this.ext,
    required this.total,
  });

  @override
  String toString() => 'ProjectFile(path: $path, name: $name, total: $total)';
}

class MultiLineComment {
  String multiCommentStart;
  String multiCommentEnd;
  MultiLineComment(this.multiCommentStart, this.multiCommentEnd);
}

Map<String, MultiLineComment> multiLineComment = <String, MultiLineComment>{
  "htm": MultiLineComment("<!--", "--!>"),
  "html": MultiLineComment("<!--", "--!>"),
  "ruby": MultiLineComment("=begin", "=end"),
  "ps1": MultiLineComment("<#", "#>"),
  "hs": MultiLineComment("{-", "-}"),
  "lhs": MultiLineComment("{-", "-}"),
  "pas": MultiLineComment("(*", "*)"),
};

class LoadFromGitWidget extends StatefulWidget {
  final void Function(String folder) onSelected;
  const LoadFromGitWidget({Key? key, required this.onSelected}) : super(key: key);
  @override
  LoadFromGitWidgetState createState() => LoadFromGitWidgetState();
}

class LoadFromGitWidgetState extends State<LoadFromGitWidget> {
  final String dir = "${WinUtils.getTabameSettingsFolder()}\\projectOverview";
  String downloadMessage = "Download";

  String headerMsg = "Works only with GitHub and GitLab!";
  final List<String> allDirs = <String>[];
  @override
  void initState() {
    super.initState();
    loadProjects();
  }

  @override
  void dispose() {
    super.dispose();
  }

  void downloadProject(String link) async {
    downloadMessage = "Downloading";
    headerMsg = "Works only with GitHub and GitLab!";
    setState(() {});
    String repo = "";
    if (link.contains("github.com")) {
      final RegExpMatch? reg = RegExp(r'github\.com/(.*?/.*?)$', caseSensitive: false).firstMatch(link);
      if (reg != null) {
        repo = "https://github.com/${reg[1]!}/archive/refs/heads/master.zip";
      } else {
        final RegExpMatch? reg = RegExp(r':(.*?/.*?)\.git').firstMatch(link);
        if (reg != null) {
          repo = "https://github.com/${reg[1]!}/archive/refs/heads/master.zip";
        }
      }
    } else if (link.contains("gitlab.com")) {
      final RegExpMatch? reg = RegExp(r'gitlab\.com/(.*?/.*?)$', caseSensitive: false).firstMatch(link);
      if (reg != null) {
        final String repName = reg[1]!.split('/').last;
        repo = "https://gitlab.com/${reg[1]!}/-/archive/master/$repName.zip";
      }
    }
    if (repo.isEmpty) {
      downloadMessage = "Download";
      headerMsg = "Suports only GitHub and GitLab";
      setState(() {});
      return;
    }
    final String zipFile = "$dir\\archived.zip";
    downloadFile(repo, zipFile, () async {
      downloadMessage = "Extracting";
      if (!mounted) return;
      setState(() {});
      await WinUtils.runPowerShell(<String>['Expand-Archive -LiteralPath "$zipFile" -DestinationPath "$dir" -Force']);
      downloadMessage = "Download";
      if (!mounted) return;
      File(zipFile).deleteSync();
      setState(() {});
      loadProjects();
    });

    return;
  }

  void loadProjects() {
    if (!Directory(dir).existsSync()) Directory(dir).createSync();
    final List<FileSystemEntity> dirs = Directory(dir).listSync(followLinks: false);
    allDirs.clear();
    for (FileSystemEntity x in dirs) {
      if (x is! File) allDirs.add(x.path);
    }
    if (mounted) setState(() {});
  }

  Future<void> downloadFile(String url, String filename, Function callback) async {
    int downloaded = 0;
    int skipten = 0;
    http.Client httpClient = http.Client();
    http.Request request = http.Request('GET', Uri.parse(url));
    Future<http.StreamedResponse> response = httpClient.send(request);

    List<List<int>> chunks = <List<int>>[];
    response.asStream().listen((http.StreamedResponse r) {
      r.stream.listen((List<int> chunk) {
        chunks.add(chunk);
        skipten++;
        if (skipten == 10) {
          downloadMessage = "${getFileSize(downloaded, 2)}";
          if (mounted) setState(() {});
          skipten = 0;
        }
        downloaded += chunk.length;
      }, onDone: () async {
        File file = File('$filename');
        final Uint8List bytes = Uint8List(downloaded);
        int offset = 0;
        for (List<int> chunk in chunks) {
          bytes.setRange(offset, offset + chunk.length, chunk);
          offset += chunk.length;
        }
        await file.writeAsBytes(bytes);
        callback();
        return;
      });
    });
  }

  getFileSize(int bytes, int decimals) {
    if (bytes <= 0) return "0 B";
    const List<String> suffixes = <String>["B", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"];
    int i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(decimals)} ${suffixes[i]}';
  }

  String gitlink = "https://github.com/Far-Se/tabame";
  @override
  Widget build(BuildContext context) {
    loadProjects();
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(headerMsg),
        TextField(
          controller: TextEditingController(text: gitlink),
          onChanged: (String e) => gitlink = e,
          decoration: const InputDecoration(
            labelText: "Github/GitLab link",
          ),
        ),
        Row(
          children: <Widget>[
            Expanded(
                child: ElevatedButton(
                    onPressed: () => downloadMessage == "Download" ? downloadProject(gitlink) : null,
                    child: Text(downloadMessage, style: TextStyle(color: Color(globalSettings.theme.background))))),
          ],
        ),
        const SizedBox(height: 20),
        Text("Downloaded Projects:", style: Theme.of(context).textTheme.bodyLarge),
        Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List<Widget>.generate(
                allDirs.length,
                (int index) => ListTile(
                      onTap: () => widget.onSelected(allDirs[index]),
                      title: Text(allDirs[index].split('\\').last),
                      trailing: Container(
                        width: 40,
                        height: double.infinity,
                        child: InkWell(
                          onTap: () {
                            File(allDirs[index]).deleteSync(recursive: true);
                            loadProjects();
                          },
                          child: const Icon(Icons.delete),
                        ),
                      ),
                    ))),
      ],
    );
  }
}
