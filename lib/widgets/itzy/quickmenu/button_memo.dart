import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/mouse_scroll_widget.dart';

class MemosButton extends StatelessWidget {
  const MemosButton({super.key});
  @override
  Widget build(BuildContext context) {
    return const ModalButton(actionName: "Memos", icon: Icon(Icons.note_alt_outlined), child: MemosWidget());
  }
}

class MemosWidget extends StatefulWidget {
  const MemosWidget({super.key});
  @override
  MemosWidgetState createState() => MemosWidgetState();
}

class MemosWidgetState extends State<MemosWidget> {
  final List<List<String>> memos = Boxes().runMemos;
  final TextEditingController titleController = TextEditingController();
  final TextEditingController messageController = TextEditingController();

  int memoSelected = -1;

  @override
  void dispose() {
    titleController.dispose();
    messageController.dispose();
    super.dispose();
  }

  void _saveMemo() {
    if (memoSelected != -1) {
      memos[memoSelected][0] = titleController.text;
      memos[memoSelected][1] = messageController.text;
      Boxes().runMemos = List<List<String>>.from(memos);
      setState(() => memoSelected = -1);
    }
  }

  void _deleteMemo() {
    if (memoSelected != -1) {
      memos.removeAt(memoSelected);
      Boxes().runMemos = List<List<String>>.from(memos);
      setState(() => memoSelected = -1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color surface = Theme.of(context).colorScheme.surface;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final Color accent = Color(globalSettings.themeColors.accentColor);

    return Material(
      type: MaterialType.transparency,
      child: Align(
        alignment: Alignment.topCenter,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          width: 280,
          constraints: const BoxConstraints(maxHeight: 500),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: surface.withAlpha(216), // 0.85 * 255
            border: Border.all(color: onSurface.withAlpha(25), width: 1), // 0.1 * 255
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withAlpha(51), // 0.2 * 255
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Text(
                      memoSelected == -1 ? "Memos" : "Edit Memo",
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    if (memoSelected == -1)
                      IconButton(
                        onPressed: () {
                          memos.add(<String>["", ""]);
                          memoSelected = memos.length - 1;
                          titleController.text = "";
                          messageController.text = "";
                          setState(() {});
                        },
                        icon: Icon(Icons.add_circle_outline, color: accent),
                        tooltip: "Add Memo",
                      )
                    else
                      IconButton(
                        onPressed: () => setState(() => memoSelected = -1),
                        icon: const Icon(Icons.close),
                        tooltip: "Close",
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Body
              Flexible(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: memoSelected == -1 ? _buildList(accent, onSurface) : _buildEditor(accent, onSurface),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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

    return MouseScrollWidget(
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
            onTap: () {
              titleController.text = memo[0];
              messageController.text = memo[1];
              setState(() => memoSelected = index);
            },
          );
        },
      ),
    );
  }

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
            decoration: _inputDecoration("Message", accent),
            maxLines: 8,
            minLines: 3,
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

class _MemoCard extends StatefulWidget {
  final String title;
  final String message;
  final Color accent;
  final Color onSurface;
  final VoidCallback onTap;

  const _MemoCard({
    required this.title,
    required this.message,
    required this.accent,
    required this.onSurface,
    required this.onTap,
  });

  @override
  State<_MemoCard> createState() => _MemoCardState();
}

class _MemoCardState extends State<_MemoCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (PointerEnterEvent _) => setState(() => _isHovered = true),
      onExit: (PointerExitEvent _) => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: _isHovered ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _isHovered ? widget.accent.withAlpha(60) : widget.onSurface.withAlpha(10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isHovered ? widget.accent.withAlpha(150) : widget.onSurface.withAlpha(12),
                width: 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(Icons.push_pin_outlined, size: 14, color: widget.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (widget.message.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    widget.message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: widget.onSurface.withAlpha(153),
                      height: 1.3,
                    ),
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
