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

import '../../models/classes/boxes.dart';
import '../../models/settings.dart';
import '../../models/win32/win32.dart';
import '../widgets/checkbox_widget.dart';
import '../widgets/popup_dialog.dart';

// -----------------------------------------
// DATA CLASSES
// -----------------------------------------

class ProjectAnalysisArgs {
  final String folder;
  final String included;
  final String excluded;
  final bool useGitIgnore;

  ProjectAnalysisArgs({
    required this.folder,
    required this.included,
    required this.excluded,
    required this.useGitIgnore,
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

// -----------------------------------------
// ISOLATE FUNCTION
// -----------------------------------------
Future<ProjectAnalysisResult> _analyzeProjectIsolate(ProjectAnalysisArgs args) async {
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

    if (const <String>["svg", "lock", "png", "jpg", "jpeg", "gif", "ico", "exe", "dll", "bin"].any((String ext) => lowerName.endsWith(".$ext"))) continue;
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
        if (file.replaceFirst(args.folder, '').contains(RegExp(r"^\\" + testExclude + r"[^\\]*\\", caseSensitive: false))) {
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

    if (const <String>["py", "ps1", "pyi", "pyc", "pyd", "pyo", "pyw", "pyz", "rb", "r", "yaml", "yml", "toml"].contains(fileExtension)) {
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
  List<List<String>> programmingLanguages = extsList.map((MapEntry<String, int> entry) => <String>[entry.key, entry.value.toString()]).toList();

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
  final TextEditingController _includeController = TextEditingController();
  final TextEditingController _excludeController = TextEditingController();
  final TextEditingController _gitLinkController = TextEditingController();

  final List<int> extensionColors = <int>[0xff34B7FD, 0xffCB4802, 0xffFFA700, 0xffC3732A, 0xffA4DDED, 0xff922724, 0xff43B3AE, 0xffA020F0];
  Map<String, Color> extColors = <String, Color>{};

  bool showFilters = false;
  bool showGit = false;
  bool projectUseGitIgnore = true;

  bool isAnalyzing = false;
  bool projectAnalyzed = false;

  ProjectAnalysisResult? result;

  int sortColumnIndex = 1; // 1=Lines, 2=Code, 3=Comments, 4=Empty, 5=Chars
  bool sortAscending = false;

  @override
  void initState() {
    super.initState();
    _folderController.text = Boxes.pref.getString("projectOverviewFolder") ?? "";
    _includeController.text = Boxes.pref.getString("projectOverviewIncluded") ?? "";
    _excludeController.text = Boxes.pref.getString("projectOverviewExcluded") ?? r"^\.[a-z];node_modules;(json|ml)$;\w{4,}$";

    if (globalSettings.args.contains("-wizardly")) {
      _folderController.text = globalSettings.args[0].replaceAll('"', '');
    }
  }

  @override
  void dispose() {
    _folderController.dispose();
    _includeController.dispose();
    _excludeController.dispose();
    _gitLinkController.dispose();
    super.dispose();
  }

  void _onAnalyzePressed() async {
    final String folder = _folderController.text;
    if (folder.isEmpty || !Directory(folder).existsSync()) {
      popupDialog(context, "Please select a valid folder");
      return;
    }

    Boxes.updateSettings("projectOverviewIncluded", _includeController.text);
    Boxes.updateSettings("projectOverviewExcluded", _excludeController.text);

    setState(() {
      isAnalyzing = true;
      projectAnalyzed = false;
      result = null;
    });

    final ProjectAnalysisArgs args = ProjectAnalysisArgs(
      folder: folder,
      included: _includeController.text,
      excluded: _excludeController.text,
      useGitIgnore: projectUseGitIgnore,
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
        popupDialog(context, "Analysis failed: $e");
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
            boxShadow: <BoxShadow>[BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 20, spreadRadius: 5)],
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
                style: TextStyle(fontSize: 12, color: onSurface.withValues(alpha: 0.6)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = Color(globalSettings.theme.accentColor);
    final Color background = Color(globalSettings.theme.background);
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
                            _folderController.text.isEmpty ? "No folder selected" : _folderController.text.truncate(60, suffix: "..."),
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
          _buildActionButton(accent, background),
        ],
      ),
    );
  }

  Widget _buildIconButton({required IconData icon, required bool isSelected, required VoidCallback onPressed, required String tooltip, required Color onSurface}) {
    return IconButton(
      icon: Icon(icon, size: 20),
      onPressed: onPressed,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: isSelected ? Color(globalSettings.theme.accentColor).withValues(alpha: 0.1) : Colors.transparent,
        foregroundColor: isSelected ? Color(globalSettings.theme.accentColor) : onSurface.withValues(alpha: 0.6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildActionButton(Color accent, Color background) {
    return ElevatedButton.icon(
      icon: isAnalyzing
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : Icon(Icons.analytics_rounded, color: background),
      label: Text(isAnalyzing ? "Scanning" : "Analyze", style: TextStyle(color: background, fontWeight: FontWeight.bold)),
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
                Expanded(child: _buildFilterInput("Include Extensions", _includeController, "dart;js;css", onSurface)),
                const SizedBox(width: 16),
                Expanded(child: _buildFilterInput("Exclude Patterns", _excludeController, "node_modules;build", onSurface)),
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

  Widget _buildFilterInput(String label, TextEditingController controller, String hint, Color onSurface) {
    return TextField(
      controller: controller,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        floatingLabelStyle: TextStyle(color: Color(globalSettings.theme.accentColor)),
      ),
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
*That's roughly **${((result!.totalChars / 250).floor()).decimal} pages** or **${(result!.totalChars / 250 / 400).toStringAsFixed(1)} books**!*
''',
        styleSheet: MarkdownStyleSheet(
          h3: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          p: TextStyle(fontSize: 14, color: onSurface.withValues(alpha: 0.8), height: 1.5),
        ),
      ),
    );
  }

  Widget _buildStatsDashboard(Color accent, Color onSurface) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 4,
      padding: const EdgeInsets.all(0),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 2.2,
      children: <Widget>[
        _buildMetricCard("Lines of Code", result!.totalLines.decimal, Icons.reorder_rounded, accent, onSurface),
        _buildMetricCard("Comment Density", "${result!.commentDensity.toStringAsFixed(1)}%", Icons.comment_bank_rounded, Colors.green, onSurface),
        _buildMetricCard("Code Intensity", "${result!.codeIntensity.toStringAsFixed(1)} ch/ln", Icons.bolt_outlined, Colors.orange, onSurface),
        _buildMetricCard("Avg. File Length", "${result!.avgLinesPerFile.floor().decimal} lns", Icons.file_present_rounded, Colors.blue, onSurface),
      ],
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
                Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis),
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
                  final double percentage = (int.parse(result!.programmingLanguages[index][1]) / result!.totalLines) * 100;
                  return PieChartSectionData(
                    title: percentage > 10 ? "$lang\n${percentage.toStringAsFixed(0)}%" : "",
                    value: percentage,
                    color: extColors[lang] ?? Colors.grey,
                    radius: 50,
                    titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
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
              children: result!.programmingLanguages.map((List<String> langData) {
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
          Text(lang, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(width: 6),
          Text(lines.decimal, style: TextStyle(fontSize: 11, color: onSurface.withValues(alpha: 0.6))),
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
            Text("${result!.files.length} files tracked", style: TextStyle(fontSize: 12, color: onSurface.withValues(alpha: 0.5))),
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
          const Expanded(flex: 4, child: Text("File Path", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
          _buildSortableHeader("Lines", 1, 70, onSurface),
          _buildSortableHeader("Code", 2, 70, onSurface),
          _buildSortableHeader("Comments", 3, 70, onSurface),
          _buildSortableHeader("Empty", 4, 70, onSurface),
          _buildSortableHeader("Chars", 5, 80, onSurface),
        ],
      ),
    );
  }

  Widget _buildSortableHeader(String label, int index, double width, Color onSurface) {
    final bool isSelected = sortColumnIndex == index;
    return InkWell(
      onTap: () => _sortFiles(index),
      child: SizedBox(
        width: width,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            Text(label,
                style:
                    TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isSelected ? Color(globalSettings.theme.accentColor) : onSurface.withValues(alpha: 0.5))),
            if (isSelected) Icon(sortAscending ? Icons.arrow_drop_up : Icons.arrow_drop_down, size: 16, color: Color(globalSettings.theme.accentColor)),
          ],
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
                Container(width: 8, height: 8, decoration: BoxDecoration(color: extColors[file.ext] ?? Colors.grey, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(child: Text(file.path, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
          _buildColText(file.total.lines.decimal, 70, onSurface),
          _buildColText(file.total.code.decimal, 70, onSurface),
          _buildColText(file.total.comments.decimal, 70, onSurface, color: Colors.green),
          _buildColText(file.total.empty.decimal, 70, onSurface, opacity: 0.4),
          _buildColText(file.total.characters.decimal, 80, onSurface),
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
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: (color ?? onSurface).withValues(alpha: opacity)),
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

    final String zipFile = "$baseDir\\temp_archive.zip";
    try {
      await _downloadFile(repoUrl, zipFile, () async {
        setState(() => downloadMessage = "Extracting...");
        WinUtils.open("powershell.exe", arguments: '-Command "Expand-Archive -LiteralPath \'$zipFile\' -DestinationPath \'$baseDir\' -Force; Remove-Item \'$zipFile\'"');
        await Future<void>.delayed(const Duration(seconds: 2));
        _loadLocalSaves();
        setState(() {
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
    final Color accent = Color(globalSettings.theme.accentColor);
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(headerMsg, style: TextStyle(fontSize: 12, color: onSurface.withValues(alpha: 0.6))),
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
          const Text("Locally Saved Projects", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: allDirs.length,
              itemBuilder: (BuildContext context, int index) {
                final String path = allDirs[index];
                final String name = path.split(r'\').last;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    avatar: const Icon(Icons.folder_zip_rounded, size: 16),
                    label: Text(name, style: const TextStyle(fontSize: 12)),
                    onPressed: () => widget.onSelected(path),
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
