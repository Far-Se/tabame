import 'dart:async';
import 'dart:io';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/classes/saved_maps.dart';
import '../../../models/settings.dart';
import '../../../models/win32/win32.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/mouse_scroll_widget.dart';
import '../../widgets/panel_header.dart';

class CliBookButton extends StatelessWidget {
  const CliBookButton({super.key});
  @override
  Widget build(BuildContext context) {
    return const ModalButton(actionName: "Cli Book", icon: Icon(Icons.terminal_rounded), child: CliBookWidget());
  }
}

class CliBookWidget extends StatefulWidget {
  const CliBookWidget({super.key});
  @override
  CliBookWidgetState createState() => CliBookWidgetState();
}

class CliBookWidgetState extends State<CliBookWidget> {
  List<CliBookItem> cliBook = Boxes().cliBook;
  TextEditingController titleController = TextEditingController();
  TextEditingController messageController = TextEditingController();

  int memoSelected = -1;
  int runSelected = -1;
  final Map<String, TextEditingController> _variableControllers = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _disposeVariableControllers();
    titleController.dispose();
    messageController.dispose();
    super.dispose();
  }

  void _disposeVariableControllers() {
    for (final TextEditingController controller in _variableControllers.values) {
      controller.dispose();
    }
    _variableControllers.clear();
  }

  List<String> _extractVariables(String command) {
    final RegExp variableRegex = RegExp(r'\$\{([^}]+)\}');
    final Set<String> seen = <String>{};
    final List<String> variables = <String>[];

    for (final RegExpMatch match in variableRegex.allMatches(command)) {
      final String variable = (match.group(1) ?? "").trim();
      if (variable.isEmpty || seen.contains(variable)) continue;
      seen.add(variable);
      variables.add(variable);
    }

    return variables;
  }

  void _openEditor(int index) {
    runSelected = -1;
    _disposeVariableControllers();
    memoSelected = index;
    titleController.text = cliBook.elementAt(memoSelected).key;
    messageController.text = cliBook.elementAt(memoSelected).value;
    setState(() {});
  }

  void _closeEditor() {
    titleController.clear();
    messageController.clear();
    if (memoSelected != -1 && cliBook.elementAt(memoSelected).key.isEmpty) {
      cliBook.removeAt(memoSelected);
      Boxes().cliBook = <CliBookItem>[...cliBook];
    }
    memoSelected = -1;
  }

  void _openRunView(int index) {
    memoSelected = -1;
    titleController.clear();
    messageController.clear();
    _disposeVariableControllers();
    runSelected = index;

    for (final String variable in _extractVariables(cliBook[index].value)) {
      _variableControllers[variable] = TextEditingController();
    }

    setState(() {});
  }

  void _closeRunView() {
    runSelected = -1;
    _disposeVariableControllers();
    setState(() {});
  }

  String _resolveVariables(String command) {
    return command.replaceAllMapped(
      RegExp(r'\$\{([^}]+)\}'),
      (Match match) {
        final String variable = (match.group(1) ?? "").trim();
        return _variableControllers[variable]?.text ?? "";
      },
    );
  }

  Future<void> _pickVariableFile(String variableName) async {
    final OpenFilePicker file = OpenFilePicker()
      ..filterSpecification = <String, String>{'All Files': '*.*'}
      ..defaultFilterIndex = 0
      ..title = 'Select any file';
    final File? result = file.getFile();
    if (result == null) return;

    _variableControllers[variableName]?.text = result.path;
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _pickVariableFolder(String variableName) async {
    final DirectoryPicker dirPicker = DirectoryPicker()..title = 'Select any folder';
    final Directory? dir = dirPicker.getDirectory();
    if (dir == null || dir.path.isEmpty) return;

    _variableControllers[variableName]?.text = dir.path;
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _runSelectedItem() async {
    if (runSelected == -1) return;
    final String resolvedCommand = _resolveVariables(cliBook[runSelected].value);
    if (resolvedCommand.trim().isEmpty) return;

    final DirectoryPicker dirPicker = DirectoryPicker()..title = 'Working Directory';
    final Directory? dir = dirPicker.getDirectory();
    if (dir == null || dir.path.isEmpty) return;
    WinUtils.runPowerShellDetachedVisible(resolvedCommand, workingDirectory: dir.path, keepOpen: true);
  }

  Widget _buildInputDecorationField({
    required TextEditingController controller,
    required String hintText,
    required Color accent,
    required Color onSurface,
    int maxLines = 1,
    int minLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      minLines: minLines,
      style: TextStyle(fontSize: 13, color: onSurface),
      decoration: InputDecoration(
        isDense: true,
        hintText: hintText,
        hintStyle: TextStyle(fontSize: 13, color: onSurface.withAlpha(100)),
        filled: true,
        fillColor: accent.withAlpha(10),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: accent.withAlpha(100), width: 1),
        ),
      ),
    );
  }

  Widget _buildRunView(Color accent, Color onSurface) {
    final CliBookItem item = cliBook[runSelected];
    final List<String> variables = _extractVariables(item.value);
    final String resolvedCommand = _resolveVariables(item.value);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (variables.isEmpty)
            Text(
              "This item does not use variables.",
              style: TextStyle(fontSize: 12, color: onSurface.withAlpha(140)),
            )
          else
            ...variables.map(
              (String variable) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    Widget variableField = TextField(
                      controller: _variableControllers[variable],
                      onChanged: (_) => setState(() {}),
                      style: TextStyle(fontSize: 13, color: onSurface),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: variable,
                        hintStyle: TextStyle(fontSize: 13, color: onSurface.withAlpha(100)),
                        filled: true,
                        fillColor: accent.withAlpha(10),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: accent.withAlpha(100), width: 1),
                        ),
                      ),
                    );

                    Widget actionButtons = Wrap(
                      spacing: 2,
                      runSpacing: 6,
                      children: <Widget>[
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _pickVariableFile(variable),
                          icon: const Icon(Icons.file_open_rounded, size: 14),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _pickVariableFolder(variable),
                          icon: const Icon(Icons.folder_open_rounded, size: 14),
                        ),
                      ],
                    );

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        Expanded(flex: 10, child: variableField),
                        const SizedBox(width: 8),
                        Expanded(flex: 4, child: actionButtons),
                      ],
                    );
                  },
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            "Preview",
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: onSurface),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(25),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: onSurface.withAlpha(20)),
            ),
            child: SelectableText(
              resolvedCommand,
              style: TextStyle(fontSize: 12, height: 1.45, color: onSurface.withAlpha(200)),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Clipboard.setData(ClipboardData(text: resolvedCommand)),
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text("Copy"),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _runSelectedItem,
                  style: Theme.of(context).elevatedButtonTheme.style?.copyWith(
                        backgroundColor: WidgetStateProperty.all(accent),
                        foregroundColor: WidgetStateProperty.all(Theme.of(context).colorScheme.surface),
                      ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 16),
                  label: const Text("Run"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = Color(globalSettings.themeColors.accentColor);
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // ── Header ──────────────────────────────────────────────
        if (runSelected != -1)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: accent.withAlpha(40),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: <Widget>[
                InkWell(
                  onTap: _closeRunView,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: accent.withAlpha(30),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.arrow_back_rounded, size: 14, color: accent),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "Run ${cliBook[runSelected].key}",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          )
        else if (memoSelected != -1)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: accent.withAlpha(40),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: <Widget>[
                InkWell(
                  onTap: () => setState(_closeEditor),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: accent.withAlpha(30),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.arrow_back_rounded, size: 14, color: accent),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    cliBook.elementAt(memoSelected).key.isEmpty ? "New Item" : "Edit Item",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: onSurface,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    cliBook.removeAt(memoSelected);
                    memoSelected = -1;
                    Boxes().cliBook = <CliBookItem>[...cliBook];
                    setState(() {});
                  },
                  icon: Icon(Icons.delete_outline_rounded, size: 18, color: onSurface.withAlpha(150)),
                  splashRadius: 20,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          )
        else
          PanelHeader(
            title: "CliBook",
            accent: accent,
            boldFont: true,
            icon: Icons.bookmark_rounded,
            buttonPressed: () {
              cliBook.add(CliBookItem(key: "", value: ""));
              _openEditor(cliBook.length - 1);
            },
            buttonIcon: Icons.add,
          ),
        // ── Scrollable Body ─────────────────────────────────────
        Flexible(
          child: MouseScrollWidget(
            scrollDirection: Axis.vertical,
            child: Material(
              type: MaterialType.transparency,
              child: runSelected != -1
                  ? _buildRunView(accent, onSurface)
                  : memoSelected != -1
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              _buildInputDecorationField(
                                controller: titleController,
                                hintText: "Title",
                                accent: accent,
                                onSurface: onSurface,
                              ),
                              const SizedBox(height: 12),
                              _buildInputDecorationField(
                                controller: messageController,
                                hintText: "Message / Command",
                                accent: accent,
                                onSurface: onSurface,
                                maxLines: 5,
                                minLines: 3,
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: accent.withAlpha(10),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: accent.withAlpha(30)),
                                ),
                                child: Text(
                                  r"Use ${varName} inside the command if this item needs values at run time. Example: cd ${projectFolder}",
                                  style: TextStyle(fontSize: 12, color: onSurface.withAlpha(160)),
                                ),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: () {
                                  cliBook[memoSelected].key = titleController.text;
                                  cliBook[memoSelected].value = messageController.text;
                                  Boxes().cliBook = <CliBookItem>[...cliBook];
                                  memoSelected = -1;
                                  setState(() {});
                                },
                                style: Theme.of(context).elevatedButtonTheme.style?.copyWith(
                                      backgroundColor: WidgetStateProperty.all(accent),
                                      foregroundColor: WidgetStateProperty.all(Colors.white),
                                    ),
                                child: Text("Save Changes",
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(context).colorScheme.surface)),
                              ),
                            ],
                          ),
                        )
                      : cliBook.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32.0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Icon(Icons.terminal_rounded, size: 48, color: onSurface.withAlpha(51)),
                                    const SizedBox(height: 16),
                                    Text(
                                      "No CLI Items",
                                      style: TextStyle(
                                          fontSize: 15, fontWeight: FontWeight.bold, color: onSurface.withAlpha(200)),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      "Store your frequently used CLI commands and snippets here for quick access.",
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontSize: 12, color: onSurface.withAlpha(128)),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                ...List<Widget>.generate(
                                  cliBook.length,
                                  (int index) => Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    child: _CliBookItem(
                                      name: cliBook.elementAt(index).key,
                                      accent: accent,
                                      onSurface: onSurface,
                                      boldFont: true,
                                      onTap: () {
                                        Clipboard.setData(ClipboardData(text: cliBook.elementAt(index).value));
                                      },
                                      onEdit: () => _openEditor(index),
                                      onRun: () => _openRunView(index),
                                    ),
                                  ),
                                ),
                              ],
                            ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CliBookItem extends StatefulWidget {
  const _CliBookItem({
    required this.name,
    required this.accent,
    required this.onSurface,
    required this.boldFont,
    required this.onTap,
    required this.onEdit,
    required this.onRun,
  });
  final String name;
  final Color accent;
  final Color onSurface;
  final bool boldFont;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onRun;

  @override
  State<_CliBookItem> createState() => _CliBookItemState();
}

class _CliBookItemState extends State<_CliBookItem> {
  bool _hovered = false;
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _copied = false;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: _hovered ? widget.accent.withAlpha(60) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            widget.onTap();
            _copied = true;
            Timer(const Duration(seconds: 2), () {
              _copied = false;
              if (mounted) setState(() {});
            });
            if (mounted) setState(() {});
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: <Widget>[
                // Left accent bar
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: _hovered ? 2.5 : 0,
                  height: 14,
                  margin: EdgeInsets.only(right: _hovered ? 7 : 0),
                  decoration: BoxDecoration(
                    color: widget.accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Duration pill

                const SizedBox(width: 8),
                // Name
                Expanded(
                  child: Text(
                    widget.name,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: widget.boldFont ? FontWeight.w500 : FontWeight.w300,
                      color: _hovered ? widget.onSurface : widget.onSurface.withAlpha(200),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Copy icon on hover
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: _hovered ? 1.0 : 0.0,
                  child: _copied
                      ? Text("Copied!", style: TextStyle(fontSize: 12, color: widget.accent.withAlpha(170)))
                      : Icon(Icons.copy, size: 13, color: widget.accent.withAlpha(170)),
                ),
                const SizedBox(width: 2),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: _hovered ? 0.85 : 0.25,
                  child: InkWell(
                    onTap: widget.onRun,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: Icon(Icons.play_arrow_rounded, size: 13, color: widget.accent.withAlpha(220)),
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                // Edit
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: _hovered ? 0.7 : 0.25,
                  child: InkWell(
                    onTap: widget.onEdit,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: Icon(Icons.edit, size: 12, color: widget.onSurface.withAlpha(160)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
