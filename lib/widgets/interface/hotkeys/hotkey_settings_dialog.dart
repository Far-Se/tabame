import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' hide TextInput;

import '../../../models/classes/boxes.dart';
import '../../../models/classes/hotkeys.dart';
import '../../widgets/checkbox_widget.dart';
import '../../widgets/mouse_scroll_widget.dart';
import '../../widgets/text_input.dart';

class HotKeySettings extends StatefulWidget {
  final int hotkeyIndex;
  final void Function() refresh;

  const HotKeySettings({
    super.key,
    required this.hotkeyIndex,
    required this.refresh,
  });
  @override
  HotKeySettingsState createState() => HotKeySettingsState();
}

class HotKeySettingsState extends State<HotKeySettings> {
  final List<Hotkeys> remap = Boxes.remap;
  final List<String> mouseButtons = <String>[];
  FocusNode focusNode = FocusNode();
  bool listeningToHotkey = false;
  late Hotkeys hotkey;

  @override
  void initState() {
    super.initState();
    hotkey = remap[widget.hotkeyIndex];

    // Refresh the available mouse buttons list
    _updateMouseButtons();
  }

  void _updateMouseButtons() {
    mouseButtons.clear();
    bool mouseButton4 = true;
    bool mouseButton5 = true;
    for (Hotkeys h in remap) {
      if (h.key == "MouseButton4") mouseButton4 = false;
      if (h.key == "MouseButton5") mouseButton5 = false;
    }
    // Only allow selecting it if it's either available OR currently assigned to THIS hotkey
    if (mouseButton4 || hotkey.key == "MouseButton4") mouseButtons.add("MouseButton4");
    if (mouseButton5 || hotkey.key == "MouseButton5") mouseButtons.add("MouseButton5");
  }

  @override
  void dispose() {
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Column(
      children: <Widget>[
        // Header
        _buildHeader(colorScheme, textTheme),

        // Scrollable Content
        Expanded(
          child: MouseScrollWidget(
            scrollDirection: Axis.vertical,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // Section 1: Hotkey Capture
                  _buildSectionCard(
                    title: "Hotkey Trigger",
                    icon: Icons.keyboard_outlined,
                    colorScheme: colorScheme,
                    children: <Widget>[
                      _buildHotkeyCapture(colorScheme, textTheme),
                      if (mouseButtons.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 16),
                        _buildMouseButtonSelectors(colorScheme, textTheme),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Section 2: Global Constraints
                  _buildSectionCard(
                    title: "Execution Rules",
                    icon: Icons.do_not_disturb_on_outlined,
                    colorScheme: colorScheme,
                    children: <Widget>[
                      CheckBoxWidget(
                        onChanged: (bool e) => setState(() => hotkey.noopScreenBusy = e),
                        value: hotkey.noopScreenBusy,
                        text: "Suppress while gaming/full-screen",
                        padding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: 20),
                      TextInput(
                        value: hotkey.prohibited.join(';'),
                        labelText: "Excluded Window Titles",
                        hintText: "regex1;regex2;...",
                        onChanged: (String e) =>
                            setState(() => hotkey.prohibited = e.split(';').where((String s) => s.isNotEmpty).toList()),
                      ),
                      const SizedBox(height: 8),
                      _buildHelpText(colorScheme, textTheme),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Section 3: Management
                  _buildSectionCard(
                    title: "Operations",
                    icon: Icons.settings_outlined,
                    colorScheme: colorScheme,
                    children: <Widget>[
                      TextButton.icon(
                        onPressed: () {
                          remap.add(hotkey.copyWith(key: 'N', modifiers: <String>["CTRL", "ALT", "SHIFT"]));
                          Boxes.updateSettings("remap", jsonEncode(remap));
                          Navigator.of(context).pop();
                          widget.refresh();
                        },
                        icon: const Icon(Icons.copy_all, size: 18),
                        label: const Text("CLONE CONFIGURATION"),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          alignment: Alignment.centerLeft,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),

        // Footer Actions
        _buildFooter(colorScheme),
      ],
    );
  }

  Widget _buildHeader(ColorScheme colors, TextTheme texts) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.outlineVariant.withAlpha(80))),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.tune, color: colors.secondary),
          const SizedBox(width: 12),
          Text("HOTKEY SETTINGS", style: texts.labelLarge?.copyWith(letterSpacing: 1.5, fontWeight: FontWeight.bold)),
          const Spacer(),
          IconButton(
            onPressed: () {
              remap.removeAt(widget.hotkeyIndex);
              Boxes.updateSettings("remap", jsonEncode(remap));
              Navigator.of(context).pop();
              widget.refresh();
            },
            icon: Icon(Icons.delete_outline, color: colors.error),
            tooltip: "Delete Hotkey",
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(ColorScheme colors) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.outlineVariant.withAlpha(80))),
      ),
      child: ElevatedButton.icon(
        onPressed: () {
          Boxes.updateSettings("remap", jsonEncode(remap));
          Navigator.of(context).pop();
          widget.refresh();
        },
        style: Theme.of(context).elevatedButtonTheme.style?.copyWith(
              backgroundColor: WidgetStateProperty.all(colors.primary),
              foregroundColor: WidgetStateProperty.all(colors.onPrimary),
            ),
        icon: const Icon(Icons.check),
        label: const Text("SAVE CHANGES", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required ColorScheme colorScheme,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface.withAlpha(80),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withAlpha(100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 18, color: colorScheme.primary),
              const SizedBox(width: 10),
              Text(title.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                    color: colorScheme.onSurfaceVariant,
                  )),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildHotkeyCapture(ColorScheme colors, TextTheme texts) {
    return InkWell(
      onTap: () {
        setState(() => listeningToHotkey = true);
        FocusScope.of(context).requestFocus(focusNode);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: listeningToHotkey ? colors.primaryContainer.withAlpha(80) : colors.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: listeningToHotkey ? colors.primary : colors.outlineVariant.withAlpha(100)),
        ),
        child: Column(
          children: <Widget>[
            Focus(
              focusNode: focusNode,
              onKeyEvent: (FocusNode node, KeyEvent event) {
                if (event is KeyDownEvent) {
                  List<String> modifiers = <String>[];
                  if (HardwareKeyboard.instance.isControlPressed) modifiers.add("CTRL");
                  if (HardwareKeyboard.instance.isAltPressed) modifiers.add("ALT");
                  if (HardwareKeyboard.instance.isShiftPressed) modifiers.add("SHIFT");
                  if (HardwareKeyboard.instance.isMetaPressed) modifiers.add("WIN");

                  // Ignore if only modifiers are pressed
                  if (event.logicalKey.synonyms.isNotEmpty ||
                      <LogicalKeyboardKey>[
                        LogicalKeyboardKey.controlLeft,
                        LogicalKeyboardKey.controlRight,
                        LogicalKeyboardKey.altLeft,
                        LogicalKeyboardKey.altRight,
                        LogicalKeyboardKey.shiftLeft,
                        LogicalKeyboardKey.shiftRight,
                        LogicalKeyboardKey.metaLeft,
                        LogicalKeyboardKey.metaRight
                      ].contains(event.logicalKey)) {
                    return KeyEventResult.handled;
                  }

                  String keyLabel = event.logicalKey.keyLabel;

                  // Check uniqueness
                  final String fullKey = Hotkeys.formatHotkey(key: keyLabel, modifiers: modifiers);
                  bool exists = remap.any((Hotkeys h) => h != hotkey && h.hotkey == fullKey);

                  if (exists) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Shortcut $fullKey already exists!")),
                    );
                    return KeyEventResult.handled;
                  }

                  setState(() {
                    hotkey.modifiers = modifiers;
                    hotkey.key = keyLabel;
                    listeningToHotkey = false;
                  });
                  FocusScope.of(context).unfocus();
                }
                return KeyEventResult.handled;
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(listeningToHotkey ? Icons.gesture : Icons.keyboard,
                      color: listeningToHotkey ? colors.primary : colors.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Text(
                    listeningToHotkey ? "PRESS YOUR HOTKEY..." : hotkey.hotkey.toUpperCase(),
                    style: texts.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: listeningToHotkey ? colors.primary : colors.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            if (!listeningToHotkey)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text("Click to change combination", style: texts.bodySmall?.copyWith(color: colors.secondary)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMouseButtonSelectors(ColorScheme colors, TextTheme texts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text("MOUSE BINDINGS", style: texts.labelSmall?.copyWith(color: colors.secondary, letterSpacing: 1)),
        const SizedBox(height: 8),
        Row(
          children: mouseButtons
              .map((String btn) => Expanded(
                    child: CheckBoxWidget(
                      text: btn,
                      value: hotkey.key == btn,
                      onChanged: (bool e) {
                        setState(() {
                          hotkey.modifiers.clear();
                          hotkey.key = btn;
                          _updateMouseButtons();
                        });
                      },
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }

  Widget _buildHelpText(ColorScheme colors, TextTheme texts) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withAlpha(50),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant.withAlpha(50)),
      ),
      child: RichText(
        text: TextSpan(
          style: texts.bodySmall?.copyWith(color: colors.onSurfaceVariant, height: 1.4),
          children: const <InlineSpan>[
            TextSpan(text: "TIP: ", style: TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: "Use semicolon-separated regex to match class, exe, or title.\n"),
            TextSpan(text: "e.g., ", style: TextStyle(fontStyle: FontStyle.italic)),
            TextSpan(
                text: "class:.*?D3D.*?;exe:PUBG;title:D3D", style: TextStyle(fontFamily: "monospace", fontSize: 10)),
          ],
        ),
      ),
    );
  }
}
