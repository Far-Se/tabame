import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:tabamewin32/tabamewin32.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../../models/win32/win_utils.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/mouse_scroll_widget.dart';
import '../../widgets/panel_header.dart';

// ---------------------------------------------------------------------------
// Enum to track which of the three pages is active.
// ---------------------------------------------------------------------------
enum _MemoPage { list, edit, preview }

// ---------------------------------------------------------------------------
// Entry-point button
// ---------------------------------------------------------------------------
class MemosButton extends StatelessWidget {
  const MemosButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ModalButton(
      actionName: "Memos",
      icon: const Icon(Icons.note_alt_outlined),
      child: () => const MemosWidget(),
    );
  }
}

// ---------------------------------------------------------------------------
// Root stateful widget
// ---------------------------------------------------------------------------
class MemosWidget extends StatefulWidget {
  const MemosWidget({super.key});

  @override
  MemosWidgetState createState() => MemosWidgetState();
}

class MemosWidgetState extends State<MemosWidget> {
  final List<List<String>> memos = Boxes().runMemos;
  final TextEditingController titleController = TextEditingController();
  final TextEditingController messageController = TextEditingController();
  final FocusNode _listFocusNode = FocusNode();

  _MemoPage _page = _MemoPage.list;
  int _selectedIndex = -1;
  int _hoveredIndex = -1;

  // ---- lifecycle -----------------------------------------------------------

  @override
  void dispose() {
    titleController.dispose();
    messageController.dispose();
    _listFocusNode.dispose();
    super.dispose();
  }

  // ---- actions -------------------------------------------------------------

  void _openEdit(int index) {
    titleController.text = memos[index][0];
    messageController.text = memos[index][1];
    setState(() {
      _selectedIndex = index;
      _hoveredIndex = index;
      _page = _MemoPage.edit;
    });
  }

  void _openPreview(int index) {
    setState(() {
      _selectedIndex = index;
      _page = _MemoPage.preview;
    });
  }

  void _saveMemo() {
    if (_selectedIndex != -1) {
      memos[_selectedIndex][0] = titleController.text;
      memos[_selectedIndex][1] = messageController.text;
      Boxes().runMemos = List<List<String>>.from(memos);
      setState(() {
        _selectedIndex = -1;
        _page = _MemoPage.list;
      });
    }
  }

  void _deleteMemo() {
    if (_selectedIndex != -1) {
      memos.removeAt(_selectedIndex);
      Boxes().runMemos = List<List<String>>.from(memos);
      setState(() {
        _selectedIndex = -1;
        _page = _MemoPage.list;
      });
    }
  }

  Future<void> _onTapLink(String text, String? href, String title) async {
    if (href == null) return;
    // final Uri uri = Uri.parse(href);
    WinUtils.open(href);
  }

  // ---- keyboard navigation (list page only) --------------------------------

  KeyEventResult _handleListKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (memos.isEmpty) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() => _hoveredIndex = (_hoveredIndex + 1).clamp(0, memos.length - 1));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() => _hoveredIndex = (_hoveredIndex - 1).clamp(0, memos.length - 1));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.space) {
      if (_hoveredIndex >= 0 && _hoveredIndex < memos.length) {
        _openEdit(_hoveredIndex);
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  // ---- header config per page ----------------------------------------------

  String get _headerTitle {
    switch (_page) {
      case _MemoPage.list:
        return "Memos";
      case _MemoPage.edit:
        return "Edit Memo";
      case _MemoPage.preview:
        return "Preview";
    }
  }

  IconData get _headerButtonIcon {
    switch (_page) {
      case _MemoPage.list:
        return Icons.add_circle_outline;
      case _MemoPage.edit:
        return Icons.visibility_outlined;
      case _MemoPage.preview:
        return Icons.edit_outlined;
    }
  }

  String get _headerButtonTooltip {
    switch (_page) {
      case _MemoPage.list:
        return "Add Memo";
      case _MemoPage.edit:
        return "Preview";
      case _MemoPage.preview:
        return "Edit";
    }
  }

  void _onHeaderButtonPressed() {
    switch (_page) {
      case _MemoPage.list:
        memos.add(<String>["", ""]);
        _selectedIndex = memos.length - 1;
        titleController.text = "";
        messageController.text = "";
        setState(() => _page = _MemoPage.edit);
      case _MemoPage.edit:
        // Save draft in memory then go to preview.
        if (_selectedIndex != -1) {
          memos[_selectedIndex][0] = titleController.text;
          memos[_selectedIndex][1] = messageController.text;
        }
        setState(() => _page = _MemoPage.preview);
      case _MemoPage.preview:
        if (_selectedIndex != -1) {
          titleController.text = memos[_selectedIndex][0];
          messageController.text = memos[_selectedIndex][1];
        }
        setState(() => _page = _MemoPage.edit);
    }
  }

  // ---- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final Color surface = Theme.of(context).colorScheme.surface;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final Color accent = userSettings.themeColors.accent;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      constraints: const BoxConstraints(maxHeight: 500),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: surface.withAlpha(216),
        border: Border.all(color: onSurface.withAlpha(25), width: 1),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withAlpha(51),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // ---- Header ----
          PanelHeader(
            title: _headerTitle,
            accent: accent,
            icon: Icons.notes_rounded,
            buttonIcon: _headerButtonIcon,
            buttonTooltip: _headerButtonTooltip,
            buttonPressed: _onHeaderButtonPressed,
            // Show a back/close button on edit & preview pages.
            extraActions: _page != _MemoPage.list
                ? [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                      tooltip: "Back to list",
                      onPressed: () => setState(() {
                        _selectedIndex = -1;
                        _page = _MemoPage.list;
                      }),
                    )
                  ]
                : null,
          ),

          // ---- Body ----
          Flexible(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: switch (_page) {
                _MemoPage.list => _buildList(accent, onSurface),
                _MemoPage.edit => _buildEditor(accent, onSurface),
                _MemoPage.preview => _buildPreview(accent, onSurface),
              },
            ),
          ),
        ],
      ),
    );
  }

  // ---- page: list ----------------------------------------------------------

  Widget _buildList(Color accent, Color onSurface) {
    if (memos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.notes, size: 48, color: onSurface.withAlpha(51)),
              const SizedBox(height: 16),
              Text(
                "No memos yet.\nClick '+' to add one.",
                textAlign: TextAlign.center,
                style: TextStyle(color: onSurface.withAlpha(128)),
              ),
            ],
          ),
        ),
      );
    }

    return Focus(
      focusNode: _listFocusNode,
      onKeyEvent: _handleListKeyEvent,
      autofocus: true,
      child: MouseScrollWidget(
        child: ListView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.all(12),
          itemCount: memos.length,
          itemBuilder: (BuildContext context, int index) {
            final List<String> memo = memos[index];
            return _MemoCard(
              title: memo[0].isEmpty ? "Untitled Memo" : memo[0],
              message: memo[1],
              accent: accent,
              onSurface: onSurface,
              isKeyboardFocused: _hoveredIndex == index,
              onTapLink: _onTapLink,
              onTap: () => _openPreview(index),
              onLongPress: () => _openEdit(index),
              onHover: (bool hovering) {
                setState(() => _hoveredIndex = hovering ? index : (_hoveredIndex == index ? -1 : _hoveredIndex));
              },
            );
          },
        ),
      ),
    );
  }

  // ---- page: edit ----------------------------------------------------------

  Widget _buildEditor(Color accent, Color onSurface) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            controller: titleController,
            decoration: _inputDecoration("Title", accent),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: messageController,
            decoration: _inputDecoration("Message (supports Markdown)", accent),
            maxLines: 10,
            minLines: 5,
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 20),
          Row(
            children: <Widget>[
              Expanded(
                child: TextButton.icon(
                  onPressed: _deleteMemo,
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                  label: const Text("Delete", style: TextStyle(color: Colors.redAccent)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _saveMemo,
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text("Save"),
                  style: Theme.of(context).elevatedButtonTheme.style?.copyWith(
                        backgroundColor: WidgetStateProperty.all(accent),
                        elevation: WidgetStateProperty.all(0),
                        padding: WidgetStateProperty.all(const EdgeInsets.symmetric(vertical: 12)),
                        shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---- page: preview -------------------------------------------------------

  Widget _buildPreview(Color accent, Color onSurface) {
    final String content = _selectedIndex != -1 ? memos[_selectedIndex][1] : "";
    final String title = _selectedIndex != -1 ? memos[_selectedIndex][0] : "";

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Title row + Copy button
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title.isEmpty ? "Untitled Memo" : title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              _CopyButton(text: content, accent: accent),
            ],
          ),
          const SizedBox(height: 4),
          Divider(color: onSurface.withAlpha(30), thickness: 1),
          const SizedBox(height: 8),

          // Markdown body
          if (content.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Text(
                "Nothing to preview.",
                textAlign: TextAlign.center,
                style: TextStyle(color: onSurface.withAlpha(100), fontSize: 13),
              ),
            )
          else
            MarkdownBody(
              data: content,
              onTapLink: _onTapLink,
              selectable: true,
              styleSheet: MarkdownStyleSheet(
                p: TextStyle(fontSize: 13, color: onSurface, height: 1.5),
                a: TextStyle(
                  fontSize: 13,
                  color: accent,
                  decoration: TextDecoration.underline,
                ),
                h1: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: onSurface),
                h2: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: onSurface),
                h3: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: onSurface),
                code: TextStyle(
                  fontSize: 12,
                  backgroundColor: accent.withAlpha(20),
                  color: accent,
                ),
                blockquoteDecoration: BoxDecoration(
                  border: Border(left: BorderSide(color: accent, width: 3)),
                  color: accent.withAlpha(15),
                ),
              ),
              imageBuilder: (Uri uri, String? title, String? alt) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      uri.toString(),
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Row(
                        children: <Widget>[
                          Icon(Icons.broken_image_outlined, size: 16, color: accent),
                          const SizedBox(width: 6),
                          Text(
                            alt ?? uri.toString(),
                            style: TextStyle(color: accent, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // ---- helpers -------------------------------------------------------------

  InputDecoration _inputDecoration(String label, Color accent) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: accent.withAlpha(178), fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      filled: true,
      fillColor: accent.withAlpha(12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: accent.withAlpha(128), width: 1.5),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Copy button with momentary "Copied!" feedback
// ---------------------------------------------------------------------------
class _CopyButton extends StatefulWidget {
  final String text;
  final Color accent;

  const _CopyButton({required this.text, required this.accent});

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;

  Future<void> _copy() async {
    await ClipboardExtended.copy(widget.text);
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: _copied
          ? Row(
              key: const ValueKey<String>("copied"),
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.check_rounded, size: 14, color: widget.accent),
                const SizedBox(width: 4),
                Text(
                  "Copied!",
                  style: TextStyle(fontSize: 12, color: widget.accent, fontWeight: FontWeight.w600),
                ),
              ],
            )
          : TextButton.icon(
              key: const ValueKey<String>("copy"),
              onPressed: _copy,
              icon: Icon(Icons.copy_outlined, size: 14, color: widget.accent),
              label: Text(
                "Copy",
                style: TextStyle(fontSize: 12, color: widget.accent),
              ),
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: widget.accent.withAlpha(80), width: 1),
                ),
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Memo list card
// ---------------------------------------------------------------------------
class _MemoCard extends StatefulWidget {
  final String title;
  final String message;
  final Color accent;
  final Color onSurface;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final void Function(bool hovering) onHover;
  final bool isKeyboardFocused;
  final void Function(String text, String? href, String title) onTapLink;

  const _MemoCard({
    required this.title,
    required this.message,
    required this.accent,
    required this.onSurface,
    required this.onTap,
    required this.onLongPress,
    required this.onHover,
    required this.isKeyboardFocused,
    required this.onTapLink,
  });

  @override
  State<_MemoCard> createState() => _MemoCardState();
}

class _MemoCardState extends State<_MemoCard> {
  bool _isHovered = false;

  bool get _highlighted => _isHovered || widget.isKeyboardFocused;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (PointerEnterEvent _) {
        setState(() => _isHovered = true);
        widget.onHover(true);
      },
      onExit: (PointerExitEvent _) {
        setState(() => _isHovered = false);
        widget.onHover(false);
      },
      child: AnimatedScale(
        scale: _highlighted ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: GestureDetector(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _highlighted ? userSettings.themeColors.accent.withAlpha(60) : widget.onSurface.withAlpha(10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _highlighted ? userSettings.themeColors.accent.withAlpha(150) : widget.onSurface.withAlpha(12),
                width: 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(Icons.push_pin_outlined, size: 14, color: userSettings.themeColors.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (widget.isKeyboardFocused)
                      Icon(Icons.chevron_right_rounded, size: 18, color: userSettings.themeColors.accent),
                  ],
                ),
                if (widget.message.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    widget.message.truncate(100, suffix: '...'),
                    style: TextStyle(fontSize: 10, color: widget.onSurface.withAlpha(153)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
