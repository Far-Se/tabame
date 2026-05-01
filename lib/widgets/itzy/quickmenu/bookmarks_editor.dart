import 'dart:io';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';

import '../../../models/classes/saved_maps.dart';
import '../../../models/settings.dart';
import '../../widgets/emoji_picker_modal.dart';
import '../../widgets/inkwell_button.dart';
import '../../widgets/mouse_scroll_widget.dart';

class BookmarkEditor extends StatefulWidget {
  const BookmarkEditor({
    super.key,
    this.group,
    this.bookmark,
    this.parentGroup,
    required this.accent,
    required this.onSaveGroup,
    required this.onSaveBookmark,
    required this.onCancel,
    this.onDelete,
    required this.isNew,
  });

  final BookmarkGroup? group;
  final BookmarkInfo? bookmark;
  final BookmarkGroup? parentGroup;
  final Color accent;
  final Function(String title, String emoji, String viewMode) onSaveGroup;
  final Function(String title, String emoji, String target, bool preferInputIcon) onSaveBookmark;
  final VoidCallback onCancel;
  final VoidCallback? onDelete;
  final bool isNew;

  @override
  State<BookmarkEditor> createState() => _BookmarkEditorState();
}

class _BookmarkEditorState extends State<BookmarkEditor> {
  late final TextEditingController _emojiCtrl;
  late final TextEditingController _titleCtrl;
  late final TextEditingController _pathCtrl;
  late String _viewMode;
  late bool _preferInputIcon;

  @override
  void initState() {
    super.initState();
    final bool isBookmark = widget.bookmark != null;
    _emojiCtrl = TextEditingController(text: isBookmark ? widget.bookmark!.emoji : (widget.group?.emoji ?? ""));
    _titleCtrl = TextEditingController(text: isBookmark ? widget.bookmark!.title : (widget.group?.title ?? ""));
    _pathCtrl = TextEditingController(text: isBookmark ? widget.bookmark!.stringToExecute : "");
    _viewMode = widget.group?.viewMode ?? 'list';
    _preferInputIcon = isBookmark ? (widget.bookmark?.preferInputIcon ?? false) : false;
  }

  @override
  void dispose() {
    _emojiCtrl.dispose();
    _titleCtrl.dispose();
    _pathCtrl.dispose();
    super.dispose();
  }

  void _handleSave() {
    if (widget.bookmark != null) {
      widget.onSaveBookmark(_titleCtrl.text, _emojiCtrl.text, _pathCtrl.text, _preferInputIcon);
    } else {
      widget.onSaveGroup(_titleCtrl.text, _emojiCtrl.text, _viewMode);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final bool isBookmark = widget.bookmark != null;

    return Column(
      children: <Widget>[
        Expanded(
          child: MouseScrollWidget(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _buildSectionLabel(
                    label: "IDENTITY",
                    accent: globalSettings.themeColors.accentColor,
                    onSurface: onSurface,
                    icon: Icons.badge_outlined,
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: onSurface.withAlpha(8),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: onSurface.withAlpha(16)),
                    ),
                    child: Row(
                      children: <Widget>[
                        _preferInputIcon
                            ? const SizedBox()
                            : InkWell(
                                onTap: () async {
                                  final String? emoji = await showEmojiPickerModal(
                                    context,
                                    title: isBookmark ? "Bookmark Emoji" : "Category Emoji",
                                    initialValue: _emojiCtrl.text,
                                    barrierColor: Colors.transparent,
                                  );
                                  if (emoji != null) {
                                    setState(() {
                                      _emojiCtrl.text = emoji;
                                    });
                                  }
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  width: 45,
                                  height: 45,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: onSurface.withAlpha(12),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: onSurface.withAlpha(25)),
                                  ),
                                  child: Text(
                                    _emojiCtrl.text.isNotEmpty ? _emojiCtrl.text : "📂",
                                    style: const TextStyle(fontSize: 20),
                                  ),
                                ),
                              ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 48),
                            child: TextField(
                              controller: _titleCtrl,
                              autofocus: true,
                              textCapitalization: TextCapitalization.words,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                              decoration: _inputDecoration(context, isBookmark ? "Label" : "Category Name",
                                  globalSettings.themeColors.accentColor),
                              onSubmitted: (_) => _handleSave(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isBookmark) ...<Widget>[
                    const SizedBox(height: 18),
                    _buildSectionLabel(
                      label: "OPTIONS",
                      accent: globalSettings.themeColors.accentColor,
                      onSurface: onSurface,
                      icon: Icons.auto_awesome_rounded,
                    ),
                    const SizedBox(height: 10),
                    InkWellButton(
                      onTap: () => setState(() => _preferInputIcon = !_preferInputIcon),
                      color: _preferInputIcon
                          ? globalSettings.themeColors.accentColor.withAlpha(20)
                          : onSurface.withAlpha(10),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            Icons.auto_awesome_rounded,
                            size: 16,
                            color: _preferInputIcon ? globalSettings.themeColors.accentColor : onSurface.withAlpha(150),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  "Prefer Input Icons",
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: _preferInputIcon
                                        ? globalSettings.themeColors.accentColor
                                        : onSurface.withAlpha(200),
                                  ),
                                ),
                                Text(
                                  "USE FAVICON OR FILE ICON OVER EMOJI",
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.3,
                                    color: _preferInputIcon
                                        ? globalSettings.themeColors.accentColor.withAlpha(180)
                                        : onSurface.withAlpha(100),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _preferInputIcon,
                            onChanged: (bool val) => setState(() => _preferInputIcon = val),
                            activeThumbColor: globalSettings.themeColors.accentColor,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (!isBookmark) ...<Widget>[
                    const SizedBox(height: 18),
                    _buildSectionLabel(
                      label: "LAYOUT",
                      accent: globalSettings.themeColors.accentColor,
                      onSurface: onSurface,
                      icon: Icons.grid_view_rounded,
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: onSurface.withAlpha(8),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: onSurface.withAlpha(16)),
                      ),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: _buildLayoutOption(
                              label: "LIST",
                              icon: Icons.view_list_rounded,
                              isSelected: _viewMode == 'list',
                              onTap: () => setState(() => _viewMode = 'list'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildLayoutOption(
                              label: "GRID",
                              icon: Icons.grid_view_rounded,
                              isSelected: _viewMode == 'grid',
                              onTap: () => setState(() => _viewMode = 'grid'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (isBookmark) ...<Widget>[
                    const SizedBox(height: 18),
                    _buildSectionLabel(
                      label: "EXECUTION",
                      accent: globalSettings.themeColors.accentColor,
                      onSurface: onSurface,
                      icon: Icons.terminal_outlined,
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: onSurface.withAlpha(8),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: onSurface.withAlpha(16)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Container(
                            constraints: const BoxConstraints(minHeight: 40),
                            child: TextField(
                              controller: _pathCtrl,
                              maxLines: null,
                              style: const TextStyle(fontSize: 11, letterSpacing: 0.2),
                              decoration: _inputDecoration(
                                      context, "Target Path / URL / Command", globalSettings.themeColors.accentColor)
                                  .copyWith(
                                isDense: false,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            children: <Widget>[
                              InkWellButton(
                                icon: Icons.file_open_rounded,
                                label: "Pick File",
                                color: globalSettings.themeColors.accentColor,
                                fontSize: 9,
                                mainAxisSize: MainAxisSize.max,
                                fontWeight: FontWeight.w800,
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                onTap: () {
                                  final OpenFilePicker file = OpenFilePicker()
                                    ..filterSpecification = <String, String>{'All Files': '*.*'}
                                    ..defaultFilterIndex = 0
                                    ..title = 'Select any file';
                                  final File? result = file.getFile();
                                  if (result != null) _pathCtrl.text = result.path;
                                },
                              ),
                              const SizedBox(width: 8, height: 8),
                              InkWellButton(
                                icon: Icons.folder_open_rounded,
                                label: "Pick Folder",
                                mainAxisSize: MainAxisSize.max,
                                color: globalSettings.themeColors.accentColor,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                onTap: () {
                                  final DirectoryPicker dirPicker = DirectoryPicker()..title = 'Select any folder';
                                  final Directory? dir = dirPicker.getDirectory();
                                  if (dir != null && dir.path.isNotEmpty) _pathCtrl.text = dir.path;
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Text(
                              "ENTER PATH, URL, OR CLI COMMAND (E.G. 'CODE .')",
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                                color: onSurface.withAlpha(100),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        _buildFixedBottomBar(context, isBookmark),
      ],
    );
  }

  Widget _buildFixedBottomBar(BuildContext context, bool isBookmark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withAlpha(100),
        border: Border(top: BorderSide(color: Theme.of(context).colorScheme.onSurface.withAlpha(15))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (!widget.isNew && widget.onDelete != null) ...<Widget>[
            InkWellButton(
              onTap: widget.onDelete!,
              label: "DELETE",
              icon: Icons.delete_outline_rounded,
              color: Colors.red,
              padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 16),
            ),
            const SizedBox(width: 12),
          ],
          InkWellButton(
            onTap: _handleSave,
            label: (widget.isNew ? (isBookmark ? "Add Bookmark" : "Create Category") : "Save"),
            icon: Icons.save_rounded,
            color: globalSettings.themeColors.accentColor,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel({
    required String label,
    required Color accent,
    required Color onSurface,
    required IconData icon,
  }) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 13, color: accent.withAlpha(220)),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.7,
            color: onSurface.withAlpha(180),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Divider(height: 1, color: onSurface.withAlpha(25))),
      ],
    );
  }

  Widget _buildLayoutOption({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? globalSettings.themeColors.accentColor.withAlpha(40) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? globalSettings.themeColors.accentColor.withAlpha(80) : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              icon,
              size: 14,
              color: isSelected ? globalSettings.themeColors.accentColor : onSurface.withAlpha(120),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                color: isSelected ? globalSettings.themeColors.accentColor : onSurface.withAlpha(120),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(BuildContext context, String label, Color accent) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    return InputDecoration(
      labelText: label.toUpperCase(),
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: onSurface.withAlpha(25), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: accent.withAlpha(180), width: 1),
      ),
      hoverColor: Colors.transparent,
      filled: true,
      fillColor: onSurface.withAlpha(12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      labelStyle: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
        color: onSurface.withAlpha(130),
      ),
    );
  }
}
