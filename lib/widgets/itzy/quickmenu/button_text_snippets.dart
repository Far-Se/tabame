import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/classes/hotkeys.dart';
import '../../../models/classes/text_snippet.dart';
import '../../../models/settings.dart';
import '../../widgets/mini_switch.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/panel_header.dart';
import '../../widgets/windows_scroll.dart';

class TextSnippetsButton extends StatelessWidget {
  const TextSnippetsButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ModalButton(
      actionName: "Text Snippets",
      icon: const Icon(Icons.short_text_rounded),
      child: () => const TextSnippetsPanel(),
    );
  }
}

class TextSnippetsPanel extends StatefulWidget {
  const TextSnippetsPanel({super.key});

  @override
  State<TextSnippetsPanel> createState() => _TextSnippetsPanelState();
}

class _TextSnippetsPanelState extends State<TextSnippetsPanel> {
  late List<TextSnippet> _snippets;

  /// -1 = list view, -2 = adding a new snippet, >= 0 = editing that index.
  int _editing = -1;
  final TextEditingController _triggerController = TextEditingController();
  final TextEditingController _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _snippets = TextSnippetsManager.load();
  }

  @override
  void dispose() {
    _triggerController.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _persist() async {
    await TextSnippetsManager.save(_snippets);
  }

  /// The trigger key label the user bound in Interface → Hotkeys, or "" if none.
  String _boundHotkeyLabel() {
    for (final Hotkeys h in Boxes.remap) {
      for (final KeyMap k in h.keymaps) {
        for (final KeyAction a in k.actions) {
          if (a.type == ActionType.tabameFunction && a.value == "ExpandSnippet") {
            return h.hotkey.isEmpty ? "" : h.displayHotkey;
          }
        }
      }
    }
    return "";
  }

  void _startAdd() {
    _triggerController.clear();
    _textController.clear();
    setState(() => _editing = -2);
  }

  void _startEdit(int index) {
    _triggerController.text = _snippets[index].trigger;
    _textController.text = _snippets[index].text;
    setState(() => _editing = index);
  }

  void _cancelEdit() {
    setState(() => _editing = -1);
  }

  Future<void> _saveEdit() async {
    final String trigger = _triggerController.text.trim();
    final String text = _textController.text;
    if (trigger.isEmpty || text.isEmpty) return;

    if (_editing == -2) {
      _snippets.add(TextSnippet(trigger: trigger, text: text));
    } else if (_editing >= 0 && _editing < _snippets.length) {
      _snippets[_editing]
        ..trigger = trigger
        ..text = text;
    }
    await _persist();
    setState(() => _editing = -1);
  }

  Future<void> _delete(int index) async {
    setState(() => _snippets.removeAt(index));
    await _persist();
  }

  Future<void> _toggle(int index, bool enabled) async {
    setState(() => _snippets[index].enabled = enabled);
    await _persist();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PanelHeader(
          title: _editing == -1 ? "Text Snippets" : (_editing == -2 ? "New Snippet" : "Edit Snippet"),
          icon: Icons.short_text_rounded,
          buttonPressed: _editing == -1 ? _startAdd : null,
          buttonIcon: _editing == -1 ? Icons.add : null,
        ),
        Flexible(
          child: Material(
            type: MaterialType.transparency,
            child: _editing == -1 ? _buildList() : _buildEditor(),
          ),
        ),
      ],
    );
  }

  Widget _buildList() {
    final String hotkey = _boundHotkeyLabel();

    return WindowsScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildHotkeyBanner(hotkey),
            const SizedBox(height: 10),
            if (_snippets.isEmpty)
              _buildEmptyState()
            else
              ...List<Widget>.generate(_snippets.length, (int i) => _buildRow(i)),
          ],
        ),
      ),
    );
  }

  Widget _buildHotkeyBanner(String hotkey) {
    final bool hasHotkey = hotkey.isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: Design.accent.withAlpha(hasHotkey ? 12 : 10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Design.accent.withAlpha(hasHotkey ? 30 : 22)),
      ),
      child: Row(
        children: <Widget>[
          Icon(hasHotkey ? Icons.keyboard_rounded : Icons.warning_amber_rounded,
              size: 15, color: Design.accent),
          const SizedBox(width: 8),
          Expanded(
            child: hasHotkey
                ? Text.rich(
                    TextSpan(
                      style: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text.withAlpha(200)),
                      children: <InlineSpan>[
                        const TextSpan(text: "Type a trigger, then press "),
                        TextSpan(
                          text: hotkey.toUpperCase(),
                          style: TextStyle(fontWeight: FontWeight.w700, color: Design.accent),
                        ),
                        const TextSpan(text: " to expand it."),
                      ],
                    ),
                  )
                : Text(
                    "Set the insert hotkey in Interface → Hotkeys → Insert snippet.",
                    style: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text.withAlpha(190)),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(int index) {
    final TextSnippet snippet = _snippets[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        color: Design.text.withAlpha(7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Design.text.withAlpha(16)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Design.accent.withAlpha(snippet.enabled ? 22 : 10),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              snippet.trigger,
              style: TextStyle(
                fontSize: Design.baseFontSize + 1,
                fontWeight: FontWeight.w700,
                fontFamily: "monospace",
                color: snippet.enabled ? Design.accent : Design.text.withAlpha(120),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              snippet.text.replaceAll("\n", " "),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: Design.baseFontSize + 1,
                color: Design.text.withAlpha(snippet.enabled ? 190 : 110),
              ),
            ),
          ),
          MiniToggleSwitch(
            value: snippet.enabled,
            onChanged: (bool v) => _toggle(index, v),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            splashRadius: 16,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            padding: EdgeInsets.zero,
            onPressed: () => _startEdit(index),
            icon: Icon(Icons.edit_rounded, size: 15, color: Design.text.withAlpha(160)),
            tooltip: "Edit",
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            splashRadius: 16,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            padding: EdgeInsets.zero,
            onPressed: () => _delete(index),
            icon: Icon(Icons.close_rounded, size: 15, color: Design.text.withAlpha(150)),
            tooltip: "Delete",
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.short_text_rounded, size: 44, color: Design.text.withAlpha(45)),
          const SizedBox(height: 12),
          Text(
            "No snippets yet",
            style: TextStyle(fontSize: Design.baseFontSize + 2.5, fontWeight: FontWeight.w700, color: Design.text),
          ),
          const SizedBox(height: 4),
          Text(
            "Add a trigger like \"brb\" → \"be right back\".",
            style: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text.withAlpha(140)),
          ),
        ],
      ),
    );
  }

  Widget _buildEditor() {
    return WindowsScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildFieldLabel("Trigger"),
            const SizedBox(height: 6),
            _buildField(
              controller: _triggerController,
              hint: "e.g. brb",
              maxLines: 1,
            ),
            const SizedBox(height: 14),
            _buildFieldLabel("Expands to"),
            const SizedBox(height: 6),
            _buildField(
              controller: _textController,
              hint: "e.g. be right back",
              maxLines: 6,
              minLines: 3,
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: _cancelEdit,
                    child: const Text("Cancel"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _saveEdit,
                    style: FilledButton.styleFrom(backgroundColor: Design.accent),
                    child: Text(_editing == -2 ? "Add" : "Save"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String label) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: Design.baseFontSize,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: Design.text.withAlpha(150),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
    int minLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      minLines: minLines,
      style: TextStyle(fontSize: Design.baseFontSize + 2, color: Design.text),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: TextStyle(fontSize: Design.baseFontSize + 2, color: Design.text.withAlpha(90)),
        filled: true,
        fillColor: Design.accent.withAlpha(10),
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
          borderSide: BorderSide(color: Design.accent.withAlpha(100), width: 1),
        ),
      ),
    );
  }
}
