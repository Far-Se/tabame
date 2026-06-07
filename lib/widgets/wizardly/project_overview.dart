// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';
import 'dart:io';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:zip_flutter/zip_flutter.dart';

import '../../models/classes/boxes.dart';
import '../../models/settings.dart';
import '../../models/win32/win_utils.dart';
import '../widgets/checkbox_widget.dart';
import '../widgets/custom_text_field.dart';
import '../widgets/custom_tooltip.dart';
import '../widgets/popup_dialog.dart';

// -----------------------------------------
// DATA CLASSES
// -----------------------------------------

class ProjectAnalysisArgs {
  final String folder;
  final String included;
  final String excluded;
  final bool useGitIgnore;
  final bool useCloc;

  ProjectAnalysisArgs({
    required this.folder,
    required this.included,
    required this.excluded,
    required this.useGitIgnore,
    required this.useCloc,
  });
}

class ProjectAnalysisResult {
  final List<ProjectFile> files;
  final int totalLines;
  final int totalCode;
  final int totalComments;
  final int totalEmpty;
  final int totalNonCode;
  final int totalChars;
  final List<List<String>> programmingLanguages;

  ProjectAnalysisResult({
    required this.files,
    required this.totalLines,
    required this.totalCode,
    required this.totalComments,
    required this.totalEmpty,
    required this.totalNonCode,
    required this.totalChars,
    required this.programmingLanguages,
  });

  double get commentDensity => totalLines > 0 ? (totalComments / totalLines) * 100 : 0;
  double get codeIntensity => totalLines > 0 ? totalChars / totalLines : 0;
  double get avgLinesPerFile => files.isNotEmpty ? totalLines / files.length : 0;
  double get compactedLines => totalChars / 70;
}

class TotalCode {
  int lines = 0;
  int comments = 0;
  int code = 0;
  int empty = 0;
  int nonCode = 0;
  int characters = 0;
  double get compactedLines => characters / 70;
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
  "htm": MultiLineComment("<!--", "-->"),
  "html": MultiLineComment("<!--", "-->"),
  "ruby": MultiLineComment("=begin", "=end"),
  "ps1": MultiLineComment("<#", "#>"),
  "hs": MultiLineComment("{-", "-}"),
  "lhs": MultiLineComment("{-", "-}"),
  "pas": MultiLineComment("(*", "*)"),
  "cpp": MultiLineComment("/*", "*/"),
  "dart": MultiLineComment("/*", "*/"),
  "js": MultiLineComment("/*", "*/"),
  "css": MultiLineComment("/*", "*/"),
  "java": MultiLineComment("/*", "*/"),
  "go": MultiLineComment("/*", "*/"),
  "rs": MultiLineComment("/*", "*/"),
};

extension DecimalFormat on int {
  String get decimal => NumberFormat.decimalPattern().format(this);
}

List<String> _parseCsvRow(String line) {
  final List<String> values = <String>[];
  final StringBuffer current = StringBuffer();
  bool inQuotes = false;

  for (int i = 0; i < line.length; i++) {
    final String char = line[i];
    if (char == '"') {
      if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
        current.write('"');
        i++;
      } else {
        inQuotes = !inQuotes;
      }
    } else if (char == ',' && !inQuotes) {
      values.add(current.toString());
      current.clear();
    } else {
      current.write(char);
    }
  }

  values.add(current.toString());
  return values;
}

String _normalizeProjectPath(String folder, String path) {
  String normalized = path.trim().replaceAll('/', r'\');
  final String normalizedFolder = folder.trim().replaceAll('/', r'\');
  if (normalized.startsWith('.\\')) normalized = normalized.substring(2);
  if (normalized.toLowerCase().startsWith(normalizedFolder.toLowerCase())) {
    normalized = normalized.substring(normalizedFolder.length);
  }
  while (normalized.startsWith(r'\')) {
    normalized = normalized.substring(1);
  }
  return normalized;
}

List<String> _splitProjectSetting(String setting) {
  final List<String> caca = setting
      .split(RegExp(r'[;,]+'))
      .map((String value) => value.trim())
      .where((String value) => value.isNotEmpty)
      .toList();
  return caca;
}

bool _isSimpleClocDirExclude(String pattern) {
  return RegExp(r'^[\w .-]+$').hasMatch(pattern) && !pattern.contains('.');
}

bool _isSimpleClocExtension(String pattern) {
  String ext = pattern.trim();
  if (ext.startsWith('.')) ext = ext.substring(1);
  return RegExp(r'^[A-Za-z0-9_+#-]+$').hasMatch(ext);
}

List<String> _buildClocArguments(ProjectAnalysisArgs args) {
  final List<String> arguments = <String>[
    args.folder,
    '--by-file',
    '--csv',
  ];

  final List<String> includeExtensions = _splitProjectSetting(args.included)
      .map((String ext) => ext.startsWith('.') ? ext.substring(1) : ext)
      .where(_isSimpleClocExtension)
      .toList();
  if (includeExtensions.isNotEmpty) {
    arguments.add('--include-ext=${includeExtensions.join(',')}');
  }

  final List<String> excludePatterns = _splitProjectSetting(args.excluded);
  final List<String> excludeDirs = excludePatterns.where(_isSimpleClocDirExclude).toList();
  if (excludeDirs.isNotEmpty) {
    arguments.add('--exclude-dir=${excludeDirs.join(',')}');
  }

  final List<String> notMatchFilePatterns = <String>[r'(test|spec)\.js$'];
  notMatchFilePatterns.addAll(excludePatterns.where((String pattern) => !_isSimpleClocDirExclude(pattern)));
  arguments.add('--not-match-f=${notMatchFilePatterns.join('|')}');

  return arguments;
}

bool _matchesProjectFilters(String folder, String filePath, String includedSetting, String excludedSetting) {
  final String normalizedFolder = folder.replaceAll('/', r'\');
  final String normalizedFile = filePath.replaceAll('/', r'\');
  final String absoluteFile = normalizedFile.toLowerCase().startsWith(normalizedFolder.toLowerCase())
      ? normalizedFile
      : '$normalizedFolder\\$normalizedFile';
  final String fileName = normalizedFile.split(r'\').last;
  final List<String> included = _splitProjectSetting(includedSetting);
  final List<String> excluded = _splitProjectSetting(excludedSetting);

  for (String exclude in excluded) {
    String testExclude = exclude;
    if (testExclude.startsWith('^')) {
      testExclude = testExclude.substring(1);
      if (absoluteFile.contains(RegExp(r"\\" + testExclude + r"[^\\]*\\", caseSensitive: false))) {
        return false;
      }
    } else if (testExclude.startsWith("/") || testExclude.startsWith(r"\\")) {
      testExclude = testExclude.substring(testExclude.startsWith("/") ? 1 : 2);
      if (absoluteFile
          .replaceFirst(normalizedFolder, '')
          .contains(RegExp(r"^\\" + testExclude + r"[^\\]*\\", caseSensitive: false))) {
        return false;
      }
    } else if (absoluteFile.contains(RegExp(r"[^\\]" + testExclude + r"[^\\]*\\", caseSensitive: false))) {
      return false;
    } else if (RegExp(testExclude, caseSensitive: false).hasMatch(absoluteFile)) {
      return false;
    }
  }

  if (included.isEmpty) return true;
  for (final String include in included) {
    if (fileName.contains(RegExp("$include\$", caseSensitive: false))) {
      return true;
    }
  }
  return false;
}

Future<ProjectAnalysisResult> _analyzeProjectWithCloc(ProjectAnalysisArgs args) async {
  final ProcessResult clocResult = await _runCloc(
    args.folder,
    _buildClocArguments(args),
  );

  if (clocResult.exitCode != 0) {
    final String error = clocResult.stderr.toString().trim();
    throw Exception(error.isEmpty ? 'cloc exited with code ${clocResult.exitCode}' : error);
  }

  final List<ProjectFile> projectFiles = <ProjectFile>[];
  final List<String> lines = clocResult.stdout.toString().split(RegExp(r'\r?\n'));

  for (final String line in lines) {
    if (line.trim().isEmpty) continue;
    final List<String> row = _parseCsvRow(line);
    if (row.length < 5) continue;

    final String language = row[0].trim();
    if (language.isEmpty || language.toLowerCase() == 'language' || language.toUpperCase() == 'SUM') continue;

    final int? blank = int.tryParse(row[row.length - 3].trim());
    final int? comments = int.tryParse(row[row.length - 2].trim());
    final int? code = int.tryParse(row[row.length - 1].trim());
    if (blank == null || comments == null || code == null) continue;

    final String filePath = _normalizeProjectPath(args.folder, row.sublist(1, row.length - 3).join(','));
    if (filePath.isEmpty) continue;
    if (!_matchesProjectFilters(args.folder, filePath, args.included, args.excluded)) continue;

    final String fileName = filePath.split(r'\').last;
    final String fileExtension =
        fileName.contains('.') ? fileName.split('.').last.toLowerCase() : language.toLowerCase();
    final TotalCode total = TotalCode()
      ..empty = blank
      ..comments = comments
      ..code = code
      ..lines = blank + comments + code;

    try {
      final File file = File('${args.folder}\\$filePath');
      if (file.existsSync()) {
        total.characters = file.readAsLinesSync().fold<int>(0, (int sum, String line) => sum + line.trim().length);
      }
    } catch (_) {}

    projectFiles.add(ProjectFile(name: fileName, path: filePath, ext: fileExtension, total: total));
  }

  projectFiles.sort((ProjectFile a, ProjectFile b) => b.total.lines.compareTo(a.total.lines));

  int totalComments = 0;
  int totalLines = 0;
  int totalCode = 0;
  int totalEmpty = 0;
  int totalChars = 0;
  final Map<String, int> exts = <String, int>{};

  for (final ProjectFile file in projectFiles) {
    totalComments += file.total.comments;
    totalLines += file.total.lines;
    totalCode += file.total.code;
    totalEmpty += file.total.empty;
    totalChars += file.total.characters;
    exts[file.ext] = (exts[file.ext] ?? 0) + file.total.lines;
  }

  final List<MapEntry<String, int>> extsList = exts.entries.toList();
  extsList.sort((MapEntry<String, int> a, MapEntry<String, int> b) => b.value.compareTo(a.value));

  return ProjectAnalysisResult(
    files: projectFiles,
    totalLines: totalLines,
    totalCode: totalCode,
    totalComments: totalComments,
    totalEmpty: totalEmpty,
    totalNonCode: 0,
    totalChars: totalChars,
    programmingLanguages:
        extsList.map((MapEntry<String, int> entry) => <String>[entry.key, entry.value.toString()]).toList(),
  );
}

Future<ProcessResult> _runCloc(String folder, List<String> arguments) async {
  final List<String> candidates = <String>[];

  try {
    final ProcessResult whereResult = await Process.run('where.exe', <String>['cloc']);
    if (whereResult.exitCode == 0) {
      candidates.addAll(whereResult.stdout
          .toString()
          .split(RegExp(r'\r?\n'))
          .map((String path) => path.trim())
          .where((String path) => path.isNotEmpty));
    }
  } catch (_) {}

  candidates.add('cloc');

  Object? lastError;
  ProcessResult? lastResult;
  for (final String executable in candidates) {
    try {
      final bool needsShell = executable.toLowerCase().endsWith('.cmd') || executable.toLowerCase() == 'cloc';
      final ProcessResult result = await Process.run(
        executable,
        arguments,
        runInShell: needsShell,
      );
      if (result.exitCode == 0) return result;
      lastResult = result;
    } catch (e) {
      lastError = e;
    }
  }

  if (lastResult != null) return lastResult;
  throw Exception('Unable to start cloc for "$folder": $lastError');
}

// -----------------------------------------
// ISOLATE FUNCTION
// -----------------------------------------
Future<ProjectAnalysisResult> _analyzeProjectIsolate(ProjectAnalysisArgs args) async {
  if (args.useCloc) return _analyzeProjectWithCloc(args);

  final File gitignoreFile = File("${args.folder}\\.gitignore");
  final List<String> gitIgnore = <String>[];
  if (args.useGitIgnore && gitignoreFile.existsSync()) {
    try {
      final List<String> lines = gitignoreFile.readAsLinesSync();
      for (String line in lines) {
        if (line.isEmpty) continue;
        line = line.trim();
        if (line.startsWith("#")) continue;
        line = line.replaceAll(RegExp(r'#.*?$'), '').trim();
        line = line.replaceAll('**', '*');
        if (line.startsWith("*")) {
          if (!line.endsWith("/")) line += "/";
          line = line.substring(1);
        } else if (!line.startsWith('/')) {
          line = "/$line";
        }
        line = line.replaceAll('.', r'\.');
        line = line.replaceAll('*', '.*');
        line = line.replaceAll('/', r'\\');
        try {
          RegExp(line).hasMatch("test");
          gitIgnore.add(line);
        } catch (_) {}
      }
    } catch (_) {}
  }

  final List<String> allFiles = <String>[];
  try {
    final List<FileSystemEntity> stream = Directory(args.folder).listSync(recursive: true, followLinks: false);
    for (final FileSystemEntity entity in stream) {
      if (entity is! File) continue;
      bool add = true;
      for (final String gitLine in gitIgnore) {
        if (RegExp(gitLine).hasMatch(entity.path)) {
          add = false;
          break;
        }
      }
      if (add) {
        allFiles.add(entity.path);
      }
    }
  } catch (_) {}

  final List<String> included = args.included.isNotEmpty ? args.included.split(';') : <String>[];
  final List<String> excluded = args.excluded.isNotEmpty ? args.excluded.split(';') : <String>[];
  final List<String> loadedFiles = <String>[];

  for (String file in allFiles) {
    final String fileDirectory = Directory(file).parent.path;
    final String fileName = file.replaceAll("$fileDirectory\\", "");
    final String lowerName = fileName.toLowerCase();

    if (const <String>["svg", "lock", "png", "jpg", "jpeg", "gif", "ico", "exe", "dll", "bin"]
        .any((String ext) => lowerName.endsWith(".$ext"))) {
      continue;
    }
    if (!fileName.contains('.')) continue;

    bool skip = false;
    for (String exclude in excluded) {
      if (exclude.isEmpty) continue;
      String testExclude = exclude;
      if (testExclude.startsWith('^')) {
        testExclude = testExclude.substring(1);
        if (file.contains(RegExp(r"\\" + testExclude + r"[^\\]*\\", caseSensitive: false))) {
          skip = true;
          break;
        }
      } else if (testExclude.startsWith("/") || testExclude.startsWith(r"\\")) {
        testExclude = testExclude.substring(testExclude.startsWith("/") ? 1 : 2);
        if (file
            .replaceFirst(args.folder, '')
            .contains(RegExp(r"^\\" + testExclude + r"[^\\]*\\", caseSensitive: false))) {
          skip = true;
          break;
        }
      } else if (file.contains(RegExp(r"[^\\]" + testExclude + r"[^\\]*\\", caseSensitive: false))) {
        skip = true;
        break;
      } else {
        if (RegExp(testExclude, caseSensitive: false).hasMatch(file)) {
          skip = true;
          break;
        }
      }
    }
    if (skip) continue;

    if (included.isNotEmpty) {
      skip = true;
      for (String include in included) {
        if (include.isEmpty) continue;
        if (fileName.contains(RegExp("$include\$", caseSensitive: false))) {
          skip = false;
          break;
        }
      }
      if (skip) continue;
    }

    loadedFiles.add(file);
  }

  List<ProjectFile> projectFiles = <ProjectFile>[];
  int totalComments = 0;
  int totalLines = 0;
  int totalCode = 0;
  int totalEmpty = 0;
  int totalNonCode = 0;
  int totalChars = 0;

  for (String file in loadedFiles) {
    List<String> fileLines;
    try {
      fileLines = File(file).readAsLinesSync();
    } catch (_) {
      continue;
    }
    if (fileLines.isEmpty) continue;

    final String filePath = file.replaceFirst("${args.folder}\\", "");
    final String fileName = filePath.split(r'\').last;
    final String fileExtension = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : "txt";

    final TotalCode total = TotalCode();
    total.lines = fileLines.length;

    bool inMultiComment = false;
    String multiStart = "/*";
    String multiEnd = "*/";
    String singleComment = "//";

    if (multiLineComment.containsKey(fileExtension)) {
      multiStart = multiLineComment[fileExtension]!.multiCommentStart;
      multiEnd = multiLineComment[fileExtension]!.multiCommentEnd;
    }

    if (const <String>["py", "ps1", "pyi", "pyc", "pyd", "pyo", "pyw", "pyz", "rb", "r", "yaml", "yml", "toml"]
        .contains(fileExtension)) {
      singleComment = "#";
    }

    for (String line in fileLines) {
      final String trimmed = line.trim();
      total.characters += trimmed.length;

      if (inMultiComment) {
        total.comments++;
        if (trimmed.contains(multiEnd)) inMultiComment = false;
      } else if (trimmed.startsWith(multiStart)) {
        total.comments++;
        if (!trimmed.contains(multiEnd)) inMultiComment = true;
      } else if (trimmed.startsWith(singleComment)) {
        total.comments++;
      } else if (trimmed.isEmpty) {
        total.empty++;
      } else if (!RegExp(r'\w').hasMatch(trimmed)) {
        total.nonCode++;
      } else {
        total.code++;
      }
    }

    int categorized = total.code + total.comments + total.nonCode + total.empty;
    if (categorized < total.lines) {
      total.empty += (total.lines - categorized);
    }

    projectFiles.add(ProjectFile(name: fileName, path: filePath, ext: fileExtension, total: total));
  }

  projectFiles.sort((ProjectFile a, ProjectFile b) => b.total.lines.compareTo(a.total.lines));

  for (final ProjectFile file in projectFiles) {
    totalComments += file.total.comments;
    totalLines += file.total.lines;
    totalCode += file.total.code;
    totalEmpty += file.total.empty;
    totalNonCode += file.total.nonCode;
    totalChars += file.total.characters;
  }

  Map<String, int> exts = <String, int>{};
  for (final ProjectFile file in projectFiles) {
    if (!exts.containsKey(file.ext)) {
      exts[file.ext] = file.total.lines;
    } else {
      exts[file.ext] = exts[file.ext]! + file.total.lines;
    }
  }

  final List<MapEntry<String, int>> extsList = exts.entries.toList();
  extsList.sort((MapEntry<String, int> a, MapEntry<String, int> b) => b.value.compareTo(a.value));
  List<List<String>> programmingLanguages =
      extsList.map((MapEntry<String, int> entry) => <String>[entry.key, entry.value.toString()]).toList();

  return ProjectAnalysisResult(
    files: projectFiles,
    totalLines: totalLines,
    totalCode: totalCode,
    totalComments: totalComments,
    totalEmpty: totalEmpty,
    totalNonCode: totalNonCode,
    totalChars: totalChars,
    programmingLanguages: programmingLanguages,
  );
}

// -----------------------------------------
// WIDGET
// -----------------------------------------

class ProjectOverviewWidget extends StatefulWidget {
  const ProjectOverviewWidget({super.key});

  @override
  ProjectOverviewWidgetState createState() => ProjectOverviewWidgetState();
}

class ProjectOverviewWidgetState extends State<ProjectOverviewWidget> {
  final TextEditingController _folderController = TextEditingController();
  String includeFiles = "";
  String excludeFiles = "";
  final TextEditingController _gitLinkController = TextEditingController();

  final List<int> extensionColors = <int>[
    0xff34B7FD,
    0xffCB4802,
    0xffFFA700,
    0xffC3732A,
    0xffA4DDED,
    0xff922724,
    0xff43B3AE,
    0xffA020F0
  ];
  Map<String, Color> extColors = <String, Color>{};

  bool showFilters = true;
  bool showGit = false;
  bool projectUseGitIgnore = true;
  bool projectUseCloc = false;

  bool isAnalyzing = false;
  bool projectAnalyzed = false;

  ProjectAnalysisResult? result;

  int sortColumnIndex = 1; // 1=Lines, 2=Code, 3=Comments, 4=Empty, 5=Chars
  bool sortAscending = false;

  @override
  void initState() {
    super.initState();
    _folderController.text = Boxes.pref.getString("projectOverviewFolder") ?? "";
    includeFiles = Boxes.pref.getString("projectOverviewIncluded") ?? "";
    excludeFiles = Boxes.pref.getString("projectOverviewExcluded") ?? r"^\.[a-z];node_modules;(json|ml)$;\w{5,}$";

    if (userSettings.args.contains("-wizardly")) {
      _folderController.text = userSettings.args[0].replaceAll('"', '');
    }
  }

  @override
  void dispose() {
    _folderController.dispose();
    _gitLinkController.dispose();
    super.dispose();
  }

  void _onAnalyzePressed() async {
    final String folder = _folderController.text;
    if (folder.isEmpty || !Directory(folder).existsSync()) {
      popupDialog(context, "Please select a valid folder");
      return;
    }

    Boxes.updateSettings("projectOverviewIncluded", includeFiles);
    Boxes.updateSettings("projectOverviewExcluded", excludeFiles);

    setState(() {
      isAnalyzing = true;
      projectAnalyzed = false;
      result = null;
    });

    final ProjectAnalysisArgs args = ProjectAnalysisArgs(
      folder: folder,
      included: includeFiles,
      excluded: excludeFiles,
      useGitIgnore: projectUseGitIgnore,
      useCloc: projectUseCloc,
    );

    try {
      final ProjectAnalysisResult res = await compute(_analyzeProjectIsolate, args);

      int i = 0;
      extColors.clear();
      for (List<String> lang in res.programmingLanguages) {
        if (i >= extensionColors.length) break;
        extColors[lang[0]] = Color(extensionColors[i++]);
      }

      setState(() {
        result = res;
        projectAnalyzed = true;
        isAnalyzing = false;
        sortColumnIndex = 1;
        sortAscending = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          isAnalyzing = false;
        });
        popupDialog(context,
            "Analysis failed: $e\n. If you want the cloc command, install it from https://github.com/aldanial/cloc");
      }
    }
  }

  void _pickFolder() async {
    final DirectoryPicker dirPicker = DirectoryPicker()..title = 'Select project folder';
    final Directory? dir = dirPicker.getDirectory();
    if (dir == null) return;
    _folderController.text = dir.path;
    Boxes.updateSettings("projectOverviewFolder", dir.path);
    if (mounted) setState(() {});
  }

  void _sortFiles(int columnIndex) {
    if (result == null) return;
    setState(() {
      if (sortColumnIndex == columnIndex) {
        sortAscending = !sortAscending;
      } else {
        sortColumnIndex = columnIndex;
        sortAscending = false;
      }

      result!.files.sort((ProjectFile a, ProjectFile b) {
        dynamic valA, valB;
        switch (columnIndex) {
          case 1:
            valA = a.total.lines;
            valB = b.total.lines;
            break;
          case 2:
            valA = a.total.code;
            valB = b.total.code;
            break;
          case 3:
            valA = a.total.comments;
            valB = b.total.comments;
            break;
          case 4:
            valA = a.total.empty;
            valB = b.total.empty;
            break;
          case 5:
            valA = a.total.characters;
            valB = b.total.characters;
            break;
          case 6:
            valA = a.total.compactedLines;
            valB = b.total.compactedLines;
            break;
          case 7:
            valA = a.total.nonCode;
            valB = b.total.nonCode;
            break;
          default:
            valA = a.total.lines;
            valB = b.total.lines;
        }
        return sortAscending ? valA.compareTo(valB) : valB.compareTo(valA);
      });
    });
  }

  Widget _buildLoadingOverlay(Color accent, Color onSurface) {
    if (!isAnalyzing) return const SizedBox.shrink();

    return Container(
      color: Colors.black.withValues(alpha: 0.4),
      child: Center(
        child: Container(
          width: 300,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(20),
            boxShadow: <BoxShadow>[
              BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 20, spreadRadius: 5)
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  SizedBox(
                    width: 80,
                    height: 80,
                    child: CircularProgressIndicator(
                      strokeWidth: 6,
                      backgroundColor: accent.withValues(alpha: 0.1),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text("Analyzing Project", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              Text(
                "Running background tasks...",
                style: TextStyle(fontSize: Design.baseFontSize + 2, color: onSurface.withValues(alpha: 0.6)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = userSettings.themeColors.accent;
    final Color background = userSettings.themeColors.background;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Stack(
      children: <Widget>[
        Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildHeader(accent, background, onSurface),
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              child: Column(
                children: <Widget>[
                  if (showGit) _buildGitSection(accent, onSurface),
                  if (showFilters) _buildFilterBar(accent, onSurface),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _buildResultsView(accent, onSurface),
            ),
          ],
        ),
        _buildLoadingOverlay(accent, onSurface),
      ],
    );
  }

  Widget _buildHeader(Color accent, Color background, Color onSurface) {
    return Padding(
      padding: const EdgeInsets.all(12),
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
                    Icon(Icons.folder_open_rounded, color: accent, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text("Target Folder", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text(
                            _folderController.text.isEmpty
                                ? "No folder selected"
                                : _folderController.text.truncate(60, suffix: "..."),
                            style:
                                TextStyle(fontSize: Design.baseFontSize + 2, color: onSurface.withValues(alpha: 0.6)),
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
          const SizedBox(width: 8),
          _buildIconButton(
            icon: Icons.settings_rounded,
            isSelected: showFilters,
            onPressed: () => setState(() => showFilters = !showFilters),
            tooltip: "Filters & Options",
            onSurface: onSurface,
          ),
          _buildIconButton(
            icon: Icons.cloud_download_rounded,
            isSelected: showGit,
            onPressed: () => setState(() => showGit = !showGit),
            tooltip: "Load from Git",
            onSurface: onSurface,
          ),
          const SizedBox(width: 8),
          _buildAnalyzeControls(accent, background),
        ],
      ),
    );
  }

  Widget _buildAnalyzeControls(Color accent, Color background) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildActionButton(accent, background),
        const SizedBox(height: 8),
        SizedBox(
          width: 150,
          child: CheckBoxWidget(
            value: projectUseCloc,
            onChanged: (bool e) => setState(() => projectUseCloc = e),
            text: 'Use cloc cmd',
          ),
        ),
      ],
    );
  }

  Widget _buildIconButton(
      {required IconData icon,
      required bool isSelected,
      required VoidCallback onPressed,
      required String tooltip,
      required Color onSurface}) {
    return CustomTooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 20),
        tooltip: "",
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: isSelected ? userSettings.themeColors.accent.withValues(alpha: 0.1) : Colors.transparent,
          foregroundColor: isSelected ? userSettings.themeColors.accent : onSurface.withValues(alpha: 0.6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  Widget _buildActionButton(Color accent, Color background) {
    return ElevatedButton.icon(
      icon: isAnalyzing
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : Icon(Icons.analytics_rounded, color: background),
      label:
          Text(isAnalyzing ? "Scanning" : "Analyze", style: TextStyle(color: background, fontWeight: FontWeight.bold)),
      onPressed: isAnalyzing ? null : _onAnalyzePressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: isAnalyzing ? Colors.grey : accent,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildFilterBar(Color accent, Color onSurface) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: onSurface.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: onSurface.withValues(alpha: 0.1)),
        ),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: _buildFilterInput("Include Extensions", includeFiles, (String string) {
                    includeFiles = string;
                    // setState(() {});
                  }, "dart;js;css"),
                ),
                const SizedBox(width: 16),
                Expanded(
                    child: _buildFilterInput("Exclude Patterns", excludeFiles, (String string) {
                  excludeFiles = string;
                  // setState(() {});
                }, "node_modules;build")),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                SizedBox(
                  width: 200,
                  child: CheckBoxWidget(
                    value: projectUseGitIgnore,
                    onChanged: (bool e) => setState(() => projectUseGitIgnore = e),
                    text: 'Respect .gitignore',
                  ),
                ),
                const Spacer(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterInput(String label, String value, Function(String val) onChanged, String hintText) {
    return CustomTextField(
      labelText: label,
      onChanged: onChanged,
      hintText: hintText,
      value: value,
    );
  }

  Widget _buildGitSection(Color accent, Color onSurface) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withValues(alpha: 0.2)),
        ),
        child: LoadFromGitWidget(
          onSelected: (String folder) {
            _folderController.text = folder;
            setState(() => showGit = false);
            _onAnalyzePressed();
          },
        ),
      ),
    );
  }

  Widget _buildResultsView(Color accent, Color onSurface) {
    if (!projectAnalyzed || result == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.insert_chart_outlined_rounded, size: 64, color: onSurface.withValues(alpha: 0.1)),
            const SizedBox(height: 16),
            Text("Select a folder to analyze your project", style: TextStyle(color: onSurface.withValues(alpha: 0.4))),
          ],
        ),
      );
    }

    if (result!.files.isEmpty) {
      return const Center(child: Text("No files found that match your criteria."));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _buildStatsDashboard(accent, onSurface),
        const SizedBox(height: 24),
        _buildOverviewSummary(onSurface),
        const SizedBox(height: 24),
        _buildVisualSection(accent, onSurface),
        const SizedBox(height: 24),
        _buildFilesSection(accent, onSurface),
      ],
    );
  }

  Widget _buildOverviewSummary(Color onSurface) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: onSurface.withValues(alpha: 0.1)),
      ),
      child: MarkdownBody(
        selectable: true,
        data: '''
**${result!.files.length.decimal}** files found with **${result!.totalLines.decimal}** lines in total, of these, **${result!.totalCode.decimal}** are code lines, **${result!.totalNonCode.decimal}** are non-code lines, **${result!.totalComments.decimal}** are comments, and **${result!.totalEmpty.decimal}** are empty lines.

There is a total of **${result!.totalChars.decimal}** characters.
That's roughly **${result!.compactedLines.floor().decimal} compacted lines** (70 chars each), **${((result!.totalChars / 250).floor()).decimal} pages** or **${(result!.totalChars / 250 / 400).toStringAsFixed(1)} books**!
''',
        styleSheet: MarkdownStyleSheet(
          h3: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          p: TextStyle(fontSize: 14, color: onSurface.withValues(alpha: 0.8), height: 1.5),
        ),
      ),
    );
  }

  Widget _buildStatsDashboard(Color accent, Color onSurface) {
    return SizedBox(
      height: 90,
      child: GridView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(0),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          mainAxisExtent: 60,
        ),
        children: <Widget>[
          _buildMetricCard("Total Lines", result!.totalLines.decimal, Icons.reorder_rounded, accent, onSurface),
          CustomTooltip(
            message: "All characters divided by 70",
            child: _buildMetricCard("Compacted Lns", result!.compactedLines.floor().decimal, Icons.compress_rounded,
                Colors.purple, onSurface),
          ),
          CustomTooltip(
            message: "${result!.totalComments.formatNum()} Comment Lines",
            child: _buildMetricCard("Comment Density", "${result!.commentDensity.toStringAsFixed(1)}%",
                Icons.comment_bank_rounded, Colors.green, onSurface),
          ),
          _buildMetricCard("Code Intensity", "${result!.codeIntensity.toStringAsFixed(1)} ch/ln", Icons.bolt_outlined,
              Colors.orange, onSurface),
          _buildMetricCard("Avg. File Length", "${result!.avgLinesPerFile.floor().decimal} lns",
              Icons.file_present_rounded, Colors.blue, onSurface),
        ],
      ),
    );
  }

  Widget _buildMetricCard(String label, String value, IconData icon, Color color, Color onSurface) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: onSurface.withValues(alpha: 0.05)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(value,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis),
                Text(
                  label,
                  style: TextStyle(fontSize: 9, color: onSurface.withValues(alpha: 0.5), height: 1.0),
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVisualSection(Color accent, Color onSurface) {
    return Container(
      height: 220,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: onSurface.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: onSurface.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 2,
            child: PieChart(
              PieChartData(
                sectionsSpace: 4,
                centerSpaceRadius: 40,
                sections: List<PieChartSectionData>.generate(result!.programmingLanguages.length, (int index) {
                  final String lang = result!.programmingLanguages[index][0];
                  final double percentage =
                      (int.parse(result!.programmingLanguages[index][1]) / result!.totalLines) * 100;
                  return PieChartSectionData(
                    title: percentage > 10 ? "$lang\n${percentage.toStringAsFixed(0)}%" : "",
                    value: percentage,
                    color: extColors[lang] ?? Colors.grey,
                    radius: 50,
                    titleStyle:
                        TextStyle(fontSize: Design.baseFontSize, fontWeight: FontWeight.bold, color: Colors.white),
                  );
                }),
              ),
            ),
          ),
          const VerticalDivider(width: 40),
          Expanded(
            flex: 3,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: result!.programmingLanguages.take(12).map((List<String> langData) {
                final String lang = langData[0];
                final int lines = int.parse(langData[1]);
                return _buildLanguageChip(lang, lines, extColors[lang] ?? Colors.grey, onSurface);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageChip(String lang, int lines, Color color, Color onSurface) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(lang, style: TextStyle(fontWeight: FontWeight.bold, fontSize: Design.baseFontSize + 2)),
          const SizedBox(width: 6),
          Text(lines.decimal,
              style: TextStyle(fontSize: Design.baseFontSize + 1, color: onSurface.withValues(alpha: 0.6))),
        ],
      ),
    );
  }

  Widget _buildFilesSection(Color accent, Color onSurface) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Text("File Breakdown", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Spacer(),
            Text("${result!.files.length} files tracked",
                style: TextStyle(fontSize: Design.baseFontSize + 2, color: onSurface.withValues(alpha: 0.5))),
          ],
        ),
        const SizedBox(height: 12),
        _buildFileTableHeader(onSurface),

        // Ensure infinite lists are responsive without restricting to 150 items.
        // We use shrinkWrap since it's inside a ListView, but ideally,
        // a large chunk of files should be virtualized properly.
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: result!.files.length,
          itemBuilder: (BuildContext context, int index) {
            final ProjectFile file = result!.files[index];
            return _buildFileRow(file, index, accent, onSurface);
          },
        ),
      ],
    );
  }

  Widget _buildFileTableHeader(Color onSurface) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
              flex: 4,
              child:
                  Text("File Path", style: TextStyle(fontWeight: FontWeight.bold, fontSize: Design.baseFontSize + 2))),
          _buildSortableHeader("Lines", 1, 70, onSurface, tooltip: "Total Lines"),
          _buildSortableHeader("Code", 2, 70, onSurface, tooltip: "Lines of code"),
          _buildSortableHeader("Comms.", 3, 70, onSurface, tooltip: "Comments"),
          _buildSortableHeader("Empty", 4, 70, onSurface, tooltip: "Empty lines"),
          _buildSortableHeader("Non", 7, 70, onSurface, tooltip: "Non codes such as {});"),
          _buildSortableHeader("Chars", 5, 80, onSurface, tooltip: "Characters"),
          _buildSortableHeader("Comp.", 6, 80, onSurface, tooltip: "Compacted Lines"),
        ],
      ),
    );
  }

  Widget _buildSortableHeader(String label, int index, double width, Color onSurface, {String? tooltip}) {
    final bool isSelected = sortColumnIndex == index;
    return InkWell(
      onTap: () => _sortFiles(index),
      child: CustomTooltip(
        message: tooltip ?? "",
        child: SizedBox(
          width: width,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              Text(label,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: Design.baseFontSize + 2,
                      color: isSelected ? userSettings.themeColors.accent : onSurface.withValues(alpha: 0.5))),
              if (isSelected)
                Icon(sortAscending ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                    size: 16, color: userSettings.themeColors.accent),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFileRow(ProjectFile file, int index, Color accent, Color onSurface) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: onSurface.withValues(alpha: 0.05))),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 4,
            child: Row(
              children: <Widget>[
                Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: extColors[file.ext] ?? Colors.grey, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(
                    child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                      onTap: () {
                        WinUtils.open("${_folderController.text}\\${file.path}");
                      },
                      child: Text(file.path.lastChars(35, addDots: true),
                          style: TextStyle(fontSize: Design.baseFontSize + 2), overflow: TextOverflow.ellipsis)),
                )),
              ],
            ),
          ),
          _buildColText(file.total.lines.decimal, 70, onSurface),
          _buildColText(file.total.code.decimal, 70, onSurface),
          _buildColText(file.total.comments.decimal, 70, onSurface, color: Colors.green),
          _buildColText(file.total.empty.decimal, 70, onSurface, opacity: 0.4),
          _buildColText(file.total.nonCode.decimal, 70, onSurface, opacity: 0.4),
          _buildColText(file.total.characters.decimal, 80, onSurface),
          _buildColText(file.total.compactedLines.floor().decimal, 80, onSurface),
        ],
      ),
    );
  }

  Widget _buildColText(String text, double width, Color onSurface, {Color? color, double opacity = 1.0}) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        textAlign: TextAlign.end,
        style: TextStyle(
            fontSize: Design.baseFontSize + 2,
            fontWeight: FontWeight.w500,
            color: (color ?? onSurface).withValues(alpha: opacity)),
      ),
    );
  }
}

// -----------------------------------------
// LoadFromGitWidget
// -----------------------------------------
class LoadFromGitWidget extends StatefulWidget {
  final void Function(String folder) onSelected;
  const LoadFromGitWidget({super.key, required this.onSelected});
  @override
  LoadFromGitWidgetState createState() => LoadFromGitWidgetState();
}

class LoadFromGitWidgetState extends State<LoadFromGitWidget> {
  final String baseDir = "${WinUtils.getTabameAppDataFolder()}\\projectOverview";
  String downloadMessage = "Download Project";
  bool isDownloading = false;
  String headerMsg = "Fetch repository content from GitHub or GitLab";
  final List<String> allDirs = <String>[];
  final TextEditingController _linkController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadLocalSaves();
  }

  @override
  void dispose() {
    _linkController.dispose();
    super.dispose();
  }

  void _loadLocalSaves() {
    if (!Directory(baseDir).existsSync()) Directory(baseDir).createSync(recursive: true);
    final List<FileSystemEntity> dirs = Directory(baseDir).listSync(followLinks: false);
    allDirs.clear();
    for (FileSystemEntity x in dirs) {
      if (x is Directory) allDirs.add(x.path);
    }
    if (mounted) setState(() {});
  }

  Stream<double> extractWithProgress({
    required String zipPath,
    required String destinationPath,
  }) async* {
    // 1. Open the zip file in read-only mode
    final ZipFile zip = ZipFile.open(zipPath, mode: ZipOpenMode.readonly);

    try {
      // 2. Fetch all entries to know the total count
      final List<ZipEntry> entries = zip.getAllEntries();
      final int totalFiles = entries.length;

      if (totalFiles == 0) {
        yield 1.0;
        return;
      }

      // 3. Ensure the destination directory exists
      final Directory destDir = Directory(destinationPath);
      if (!await destDir.exists()) {
        await destDir.create(recursive: true);
      }

      // 4. Extract each entry sequentially and yield progress// 4. Extract each entry sequentially and yield progress
      for (int i = 0; i < totalFiles; i++) {
        final ZipEntry entry = entries[i];

        // Construct the absolute output path for this file/directory
        final String outputPath = '$destinationPath/${entry.name}';

        // Check if the entry represents a directory
        if (entry.name.endsWith('/')) {
          await Directory(outputPath).create(recursive: true);
        } else {
          // Ensure parent directory exists for the file
          final File file = File(outputPath);
          await file.parent.create(recursive: true);

          // Write the decompressed bytes to disk
          await file.writeAsBytes(entry.read());
        }

        // 5. Calculate and yield progress (0.0 to 1.0)
        double progress = (i + 1) / totalFiles;
        yield progress;
      }
    } finally {
      // Always close the zip handle to prevent memory leaks or file locking
      zip.close();
    }
  }

  void _startDownload() async {
    final String link = _linkController.text.trim();
    if (link.isEmpty) return;

    setState(() {
      isDownloading = true;
      downloadMessage = "Connecting...";
    });

    String repoUrl = "";
    if (link.contains("github.com")) {
      final RegExpMatch? reg = RegExp(r'github\.com/(.*?/.*?)(?:\.git|/|$)', caseSensitive: false).firstMatch(link);
      if (reg != null) repoUrl = "https://github.com/${reg[1]!}/archive/refs/heads/master.zip";
    } else if (link.contains("gitlab.com")) {
      final RegExpMatch? reg = RegExp(r'gitlab\.com/(.*?/.*?)(?:\.git|/|$)', caseSensitive: false).firstMatch(link);
      if (reg != null) {
        final String repName = reg[1]!.split('/').last;
        repoUrl = "https://gitlab.com/${reg[1]!}/-/archive/master/$repName.zip";
      }
    }

    if (repoUrl.isEmpty) {
      setState(() {
        isDownloading = false;
        headerMsg = "Invalid or unsupported repository link";
      });
      return;
    }

    final String zipFileName = "$baseDir\\temp_archive.zip";
    try {
      await _downloadFile(repoUrl, zipFileName, () async {
        setState(() => downloadMessage = "Extracting...");
        final Stream<double> extractionStream = extractWithProgress(
          zipPath: zipFileName,
          destinationPath: baseDir,
        );
        double lastUpdatedProgress = 0.0;
        await for (final double progress in extractionStream) {
          if (progress - lastUpdatedProgress >= 0.005 || progress == 1.0) {
            lastUpdatedProgress = progress;
            setState(() {
              downloadMessage = 'Extracting: ${(progress * 100).toStringAsFixed(1)}%';
            });
          }
        }

        _loadLocalSaves();
        setState(() {
          if (File(zipFileName).existsSync()) File(zipFileName).deleteSync();
          isDownloading = false;
          downloadMessage = "Download Project";
        });
      });
    } catch (e) {
      setState(() {
        isDownloading = false;
        headerMsg = "Download failed: $e";
      });
    }
  }

  Future<void> _downloadFile(String url, String filename, VoidCallback onDone) async {
    final http.Client client = http.Client();
    final http.Request request = http.Request('GET', Uri.parse(url));
    final http.StreamedResponse response = await client.send(request);

    final List<int> bytes = <int>[];
    int total = 0;
    response.stream.listen(
      (List<int> chunk) {
        bytes.addAll(chunk);
        total += chunk.length;
        if (mounted) {
          setState(() => downloadMessage = "Downloading: ${(total / 1024 / 1024).toStringAsFixed(1)} MB");
        }
      },
      onDone: () async {
        await File(filename).writeAsBytes(bytes);
        onDone();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = userSettings.themeColors.accent;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(headerMsg, style: TextStyle(fontSize: Design.baseFontSize + 2, color: onSurface.withValues(alpha: 0.6))),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _linkController,
                decoration: InputDecoration(
                  hintText: "GitHub or GitLab repository link",
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                style: const TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: isDownloading ? null : _startDownload,
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(downloadMessage, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        if (allDirs.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          Text("Locally Saved Projects",
              style: TextStyle(fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SizedBox(
            height: 50,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: allDirs.length,
              itemBuilder: (BuildContext context, int index) {
                final String path = allDirs[index];
                final String name = path.split(r'\').last;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: CustomTooltip(
                    message: "Right Click to Delete",
                    child: GestureDetector(
                      onSecondaryTapUp: (TapUpDetails e) {
                        if (!Directory('$baseDir\\$name').existsSync()) return;
                        Directory('$baseDir\\$name').deleteSync(recursive: true);
                        setState(() {
                          allDirs.remove(path);
                        });
                      },
                      child: ActionChip(
                        avatar: const Icon(Icons.folder_zip_rounded, size: 16),
                        label: Text(name, style: TextStyle(fontSize: Design.baseFontSize + 2)),
                        onPressed: () => widget.onSelected(path),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}
