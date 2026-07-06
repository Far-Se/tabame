import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' hide TextInput;

import '../../../models/classes/boxes.dart';
import '../../../models/classes/hotkeys.dart';
import '../../../models/settings.dart';
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
  final List<String> specialBindings = <String>[];
  FocusNode focusNode = FocusNode();
  bool listeningToHotkey = false;
  late Hotkeys hotkey;

  // Live interaction state
  final Set<String> _pressedModifiers = <String>{};
  String? _conflictMessage;
  bool _exported = false;

  @override
  void initState() {
    super.initState();
    hotkey = remap[widget.hotkeyIndex];

    _updateSpecialBindings();
  }

  void _updateSpecialBindings() {
    specialBindings.clear();
    final Set<String> usedSpecialBindings = remap
        .where((Hotkeys h) => !identical(h, hotkey) && Hotkeys.isSpecialBindingKey(h.key))
        .map((Hotkeys h) => h.key)
        .toSet();

    for (final String binding in Hotkeys.specialBindingKeys) {
      if (!usedSpecialBindings.contains(binding) || hotkey.key == binding) {
        specialBindings.add(binding);
      }
    }
  }

  @override
  void dispose() {
    focusNode.dispose();
    super.dispose();
  }

  String get _selectedHotkeyLabel {
    if (hotkey.key.isEmpty) return "Press here to set your shortcut";
    return hotkey.displayHotkey;
  }

  void _startHotkeyListening() {
    setState(() {
      listeningToHotkey = true;
      _pressedModifiers.clear();
      _conflictMessage = null;
    });
    focusNode.requestFocus();
  }

  KeyEventResult _handleHotkeyKeyEvent(FocusNode node, KeyEvent event) {
    if (!listeningToHotkey) return KeyEventResult.ignored;

    setState(() {
      _pressedModifiers.clear();
      if (HardwareKeyboard.instance.isControlPressed) _pressedModifiers.add("CTRL");
      if (HardwareKeyboard.instance.isAltPressed) _pressedModifiers.add("ALT");
      if (HardwareKeyboard.instance.isShiftPressed) _pressedModifiers.add("SHIFT");
      if (HardwareKeyboard.instance.isMetaPressed) _pressedModifiers.add("WIN");
    });

    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        setState(() => listeningToHotkey = false);
        return KeyEventResult.handled;
      }

      // If it's a modifier itself, we don't finalize yet, but we've updated _pressedModifiers above
      if (event.logicalKey.synonyms.isNotEmpty ||
          event.logicalKey == LogicalKeyboardKey.controlLeft ||
          event.logicalKey == LogicalKeyboardKey.controlRight ||
          event.logicalKey == LogicalKeyboardKey.altLeft ||
          event.logicalKey == LogicalKeyboardKey.altRight ||
          event.logicalKey == LogicalKeyboardKey.shiftLeft ||
          event.logicalKey == LogicalKeyboardKey.shiftRight ||
          event.logicalKey == LogicalKeyboardKey.metaLeft ||
          event.logicalKey == LogicalKeyboardKey.metaRight) {
        return KeyEventResult.handled;
      }

      // Finalize capture
      final String keyName = Hotkeys.keyFromLogicalKey(event.logicalKey);
      setState(() {
        hotkey.modifiers = Hotkeys.normalizeModifiers(_pressedModifiers.toList());
        hotkey.key = keyName;
        listeningToHotkey = false;
        _conflictMessage = _getConflictMessage(keyName, _pressedModifiers.toList());
        _updateSpecialBindings();
      });
      FocusScope.of(context).unfocus();
      return KeyEventResult.handled;
    }

    return KeyEventResult.handled;
  }

  void _selectSpecialBinding(String binding) {
    setState(() {
      hotkey.modifiers.clear();
      hotkey.key = binding;
      _conflictMessage = _getConflictMessage(binding, <String>[]);
      _updateSpecialBindings();
    });
  }

  String? _getConflictMessage(String key, List<String> modifiers) {
    final String normalizedMods = Hotkeys.normalizeModifiers(modifiers).join("+");
    for (int i = 0; i < remap.length; i++) {
      if (i == widget.hotkeyIndex) continue;
      final Hotkeys other = remap[i];
      if (other.modifiers.join("+") == normalizedMods && other.key == key) {
        return other.key;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme texts = Theme.of(context).textTheme;

    return Column(
      children: <Widget>[
        _buildTechnicalHeader(colors, texts),
        Expanded(
          child: MouseScrollWidget(
            scrollDirection: Axis.vertical,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // --- TRIGGER SECTION ---
                  _buildSectionLabel(
                    label: "Input Trigger",
                    icon: Icons.sensors_rounded,
                    count: 1,
                    colors: colors,
                  ),
                  const SizedBox(height: 10),
                  _buildHotkeyMonitor(colors, texts),

                  if (specialBindings.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 20),
                    _buildSectionLabel(
                      label: "Special Bindings",
                      icon: Icons.mouse_rounded,
                      count: specialBindings.length,
                      colors: colors,
                    ),
                    const SizedBox(height: 10),
                    _buildSpecialBindingsRadioList(colors, texts),
                  ],

                  const SizedBox(height: 24),

                  // --- RULES SECTION ---
                  _buildSectionLabel(
                    label: "Execution Filters",
                    icon: Icons.filter_alt_rounded,
                    count: 2,
                    colors: colors,
                  ),
                  const SizedBox(height: 10),
                  _buildInstrumentCard(
                    colors: colors,
                    child: Column(
                      children: <Widget>[
                        _buildTechnicalToggle(
                          colors: colors,
                          texts: texts,
                          label: "Suppress while gaming",
                          description: "Ignore trigger when full-screen apps are active.",
                          icon: Icons.sports_esports_rounded,
                          value: hotkey.noopScreenBusy,
                          onChanged: (bool e) => setState(() => hotkey.noopScreenBusy = e),
                        ),
                        const SizedBox(height: 12),
                        _buildTechnicalToggle(
                          colors: colors,
                          texts: texts,
                          label: "Wait for double press",
                          description: "It will not trigger normal press instantly.",
                          icon: Icons.timer,
                          value: hotkey.waitForDoublePress,
                          onChanged: (bool e) => setState(() => hotkey.waitForDoublePress = e),
                        ),
                        const SizedBox(height: 12),
                        CustomTextInput(
                          value: hotkey.prohibited.join(';'),
                          labelText: "Excluded Window Titles",
                          hintText: "regex1;regex2;...",
                          onChanged: (String e) => setState(
                              () => hotkey.prohibited = e.split(';').where((String s) => s.isNotEmpty).toList()),
                        ),
                        const SizedBox(height: 8),
                        _buildHelpText(colors, texts),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // --- OPERATIONS ---
                  if (hotkey.hotkey.toUpperCase() != "NOKEY") ...<Widget>[
                    _buildSectionLabel(
                      label: "Operations",
                      icon: Icons.settings_rounded,
                      count: 1,
                      colors: colors,
                    ),
                    const SizedBox(height: 10),
                    _buildInstrumentCard(
                      colors: colors,
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: <Widget>[
                          InkWell(
                            onTap: () {
                              remap.add(hotkey.copyWith(key: 'N', modifiers: <String>["CTRL", "ALT", "SHIFT"]));
                              Boxes.updateSettings("remap", jsonEncode(remap));
                              Navigator.of(context).pop();
                              widget.refresh();
                            },
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              child: Row(
                                children: <Widget>[
                                  Icon(Icons.copy_all_rounded, size: 16, color: colors.onSurfaceVariant),
                                  const SizedBox(width: 10),
                                  Text(
                                    "CLONE CONFIGURATION",
                                    style: texts.labelMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Divider(height: 1, color: colors.onSurface.withAlpha(12)),
                          InkWell(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: hotkey.toJson()));
                              setState(() => _exported = true);
                              Future<void>.delayed(const Duration(seconds: 2), () {
                                if (mounted) setState(() => _exported = false);
                              });
                            },
                            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              child: Row(
                                children: <Widget>[
                                  Icon(_exported ? Icons.check_rounded : Icons.ios_share_rounded,
                                      size: 16, color: _exported ? Design.accent : colors.onSurfaceVariant),
                                  const SizedBox(width: 10),
                                  Text(
                                    _exported ? "COPIED TO CLIPBOARD" : "EXPORT CONFIGURATION",
                                    style: texts.labelMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                      color: _exported ? Design.accent : colors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
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
        _buildStickyFooter(colors),
      ],
    );
  }

  Widget _buildSectionLabel({
    required String label,
    required IconData icon,
    required int count,
    required ColorScheme colors,
  }) {
    final Color accent = Design.accent;
    return Row(
      children: <Widget>[
        Icon(icon, size: 14, color: accent),
        const SizedBox(width: 8),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: Design.baseFontSize + 1,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: colors.onSurface.withAlpha(180),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
          decoration: BoxDecoration(
            color: accent.withAlpha(25),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            "$count",
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: accent),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Divider(height: 1, color: colors.outlineVariant.withAlpha(40))),
      ],
    );
  }

  Widget _buildInstrumentCard({
    required ColorScheme colors,
    required Widget child,
    EdgeInsets? padding,
  }) {
    return Container(
      padding: padding ?? const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: colors.onSurface.withAlpha(8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.onSurface.withAlpha(16)),
      ),
      child: child,
    );
  }

  Widget _buildTechnicalHeader(ColorScheme colors, TextTheme texts) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.outlineVariant.withAlpha(60))),
      ),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: colors.secondaryContainer.withAlpha(40),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.tune_rounded, size: 16, color: colors.secondary),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                "HOTKEY SETTINGS",
                style: texts.labelMedium?.copyWith(
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w900,
                  color: colors.onSurface,
                ),
              ),
              Text(
                "MANUAL_TRIGGER_CALIBRATION",
                style: TextStyle(
                  fontSize: 9,
                  fontFamily: "monospace",
                  color: colors.onSurfaceVariant.withAlpha(120),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            onPressed: () {
              remap.removeAt(widget.hotkeyIndex);
              Boxes.updateSettings("remap", jsonEncode(remap));
              Navigator.of(context).pop();
              widget.refresh();
            },
            icon: Icon(Icons.delete_sweep_rounded, color: colors.error.withAlpha(180), size: 20),
            tooltip: "Delete Hotkey",
          ),
        ],
      ),
    );
  }

  Widget _buildHotkeyMonitor(ColorScheme colors, TextTheme texts) {
    final Color accent = Design.accent;

    return _buildInstrumentCard(
      colors: colors,
      padding: EdgeInsets.zero,
      child: Column(
        children: <Widget>[
          InkWell(
            onTap: _startHotkeyListening,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: listeningToHotkey ? accent.withAlpha(15) : Colors.transparent,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                border: Border(
                  bottom: BorderSide(color: colors.onSurface.withAlpha(12)),
                ),
              ),
              child: Row(
                children: <Widget>[
                  // Status Signal
                  _buildStatusSignal(accent, listeningToHotkey),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Focus(
                      focusNode: focusNode,
                      onKeyEvent: _handleHotkeyKeyEvent,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            listeningToHotkey ? "ARMED // RECORDING" : "TRIGGER INPUT",
                            style: TextStyle(
                              fontSize: 9,
                              fontFamily: "monospace",
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2,
                              color: listeningToHotkey ? accent : colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            listeningToHotkey ? "WAITING FOR INPUT SIGNAL..." : _selectedHotkeyLabel,
                            style: texts.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: listeningToHotkey ? colors.onSurface : colors.onSurface.withAlpha(200),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!listeningToHotkey)
                    Icon(Icons.keyboard_outlined, color: colors.onSurfaceVariant.withAlpha(60), size: 18),
                ],
              ),
            ),
          ),
          // Live Technical Rail
          Padding(
            padding: const EdgeInsets.all(10),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: listeningToHotkey ? 1.0 : 0.5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      for (int i = 0; i < Hotkeys.modifierFamilies.length; i++) ...<Widget>[
                        if (i > 0) const SizedBox(width: 6),
                        _modifierStatusTile(Hotkeys.modifierFamilies[i]),
                      ],
                    ],
                  ),
                  if (!listeningToHotkey) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(
                      "TAP TO CYCLE: EITHER → LEFT → RIGHT SIDE",
                      style: TextStyle(
                        fontSize: 8,
                        fontFamily: "monospace",
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: colors.onSurfaceVariant.withAlpha(110),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_conflictMessage != null) _buildConflictWarning(colors, texts),
        ],
      ),
    );
  }

  Widget _buildStatusSignal(Color accent, bool active) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? accent : Colors.transparent,
        border: Border.all(color: active ? accent : accent.withAlpha(100), width: 1.5),
        boxShadow: active
            ? <BoxShadow>[
                BoxShadow(color: accent.withAlpha(100), blurRadius: 8, spreadRadius: 1),
                BoxShadow(color: accent.withAlpha(150), blurRadius: 2, spreadRadius: 0),
              ]
            : null,
      ),
    );
  }

  Widget _buildConflictWarning(ColorScheme colors, TextTheme texts) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.error.withAlpha(15),
        border: Border(top: BorderSide(color: colors.error.withAlpha(30))),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.warning_amber_rounded, color: colors.error, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "CONFLICT DETECTED: Assigned to '$_conflictMessage'",
              style: texts.labelSmall?.copyWith(
                color: colors.error,
                fontWeight: FontWeight.w800,
                fontSize: Design.baseFontSize,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Cycles a modifier family through its states on tap:
  //   Off -> Either -> Left -> Right -> Off  (Left/Right only for sided families).
  void _cycleModifierFamily(String family) {
    final List<String> variants = Hotkeys.modifierVariants[family] ?? <String>[family];
    final String? current = Hotkeys.activeModifierForFamily(hotkey.modifiers, family);
    hotkey.modifiers.removeWhere((String modifier) => variants.contains(modifier.toUpperCase()));

    final bool sided = Hotkeys.sidedModifierFamilies.contains(family);
    int nextSide;
    if (current == null) {
      nextSide = 0; // Off -> Either
    } else if (!sided) {
      nextSide = -1; // Either -> Off
    } else {
      nextSide = Hotkeys.modifierSideOf(current) + 1; // Either -> Left -> Right -> Off
      if (nextSide > 2) nextSide = -1;
    }

    if (nextSide >= 0) hotkey.modifiers.add(Hotkeys.modifierWithSide(family, nextSide));
    setState(() {});
  }

  Widget _modifierStatusTile(String family) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color accent = Design.accent;

    final String? token = listeningToHotkey ? null : Hotkeys.activeModifierForFamily(hotkey.modifiers, family);
    final bool isActive = listeningToHotkey ? _pressedModifiers.contains(family) : token != null;
    final int side = token == null ? 0 : Hotkeys.modifierSideOf(token);
    final String sidePrefix = side == 1 ? "L·" : (side == 2 ? "R·" : "");

    return Expanded(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            if (listeningToHotkey) return;
            _cycleModifierFamily(family);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
            decoration: BoxDecoration(
              color: isActive ? accent.withAlpha(25) : colors.onSurface.withAlpha(10),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isActive ? accent.withAlpha(180) : colors.onSurface.withAlpha(12),
                width: 1,
              ),
            ),
            alignment: Alignment.center,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                "$sidePrefix$family",
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                  color: isActive ? accent : colors.onSurfaceVariant.withAlpha(80),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSpecialBindingsRadioList(ColorScheme colors, TextTheme texts) {
    return Column(
      children: specialBindings
          .map((String binding) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _buildSpecialBindingRadioRow(colors, texts, binding),
              ))
          .toList(),
    );
  }

  Widget _buildSpecialBindingRadioRow(ColorScheme colors, TextTheme texts, String binding) {
    final Color accent = Design.accent;
    final bool selected = hotkey.key == binding;

    return InkWell(
      onTap: () => _selectSpecialBinding(binding),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: selected ? accent.withAlpha(15) : colors.onSurface.withAlpha(6),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? accent.withAlpha(60) : colors.onSurface.withAlpha(14),
          ),
        ),
        child: Row(
          children: <Widget>[
            // Radio Indicator
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? accent : colors.onSurfaceVariant.withAlpha(100),
                  width: selected ? 5 : 1.5,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    Hotkeys.displayKey(binding),
                    style: texts.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: selected ? accent : colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _specialBindingDescription(binding),
                    style: texts.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant.withAlpha(180),
                      fontSize: Design.baseFontSize + 0.5,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _specialBindingDescription(String binding) {
    switch (binding) {
      case Hotkeys.mouseButton4Key:
        return "Back thumb button (Mouse Button 4).";
      case Hotkeys.mouseButton5Key:
        return "Forward thumb button (Mouse Button 5).";
      case Hotkeys.doubleAltKey:
        return "Tap Alt once, then press again within 100ms.";
      case Hotkeys.leftAltKey:
        return "Press the Left Alt key to trigger this action.";
      case Hotkeys.rightAltKey:
        return "Press the Right Alt key to trigger this action.";
      case Hotkeys.leftControlKey:
        return "Press the Left Control key to trigger this action.";
      case Hotkeys.rightControlKey:
        return "Press the Right Control key to trigger this action.";
      case Hotkeys.leftShiftKey:
        return "Press the Left Shift key to trigger this action.";
      case Hotkeys.rightShiftKey:
        return "Press the Right Shift key to trigger this action.";
      case Hotkeys.leftWinKey:
        return "Press the Left Windows key to trigger this action.";
      case Hotkeys.rightWinKey:
        return "Press the Right Windows key to trigger this action.";
      default:
        return "Custom hardware trigger for this remapping.";
    }
  }

  Widget _buildStickyFooter(ColorScheme colors) {
    final Color accent = Design.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.outlineVariant.withAlpha(60))),
      ),
      child: Center(
        child: InkWell(
          onTap: () {
            Boxes.updateSettings("remap", jsonEncode(remap));
            Navigator.of(context).pop();
            widget.refresh();
          },
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 48),
            decoration: BoxDecoration(
              color: accent.withAlpha(25),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: accent.withAlpha(80), width: 1),
            ),
            child: Text(
              "SAVE CHANGES",
              style: TextStyle(
                fontSize: Design.baseFontSize + 1,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: accent,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHelpText(ColorScheme colors, TextTheme texts) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.onSurface.withAlpha(8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.info_outline_rounded, size: 12, color: colors.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                "MATCHING SYNTAX",
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  color: colors.onSurfaceVariant,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          RichText(
            text: TextSpan(
              style:
                  texts.bodySmall?.copyWith(color: colors.onSurfaceVariant, fontSize: Design.baseFontSize, height: 1.4),
              children: const <InlineSpan>[
                TextSpan(text: "Use semicolon regex for "),
                TextSpan(text: "class, exe, or title.", style: TextStyle(fontWeight: FontWeight.bold)),
                TextSpan(text: "\ne.g. "),
                TextSpan(
                  text: "class:.*?D3D.*?;exe:PUBG",
                  style: TextStyle(fontFamily: "monospace", fontSize: 9.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTechnicalToggle({
    required ColorScheme colors,
    required TextTheme texts,
    required String label,
    required String description,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final Color accent = Design.accent;

    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: value ? accent.withAlpha(20) : colors.onSurface.withAlpha(10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                size: 16,
                color: value ? accent : colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    style: texts.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: value ? colors.onSurface : colors.onSurface.withAlpha(180),
                    ),
                  ),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: Design.baseFontSize,
                      color: colors.onSurfaceVariant.withAlpha(140),
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Technical Switch
            Container(
              width: 32,
              height: 18,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: value ? accent.withAlpha(40) : colors.onSurface.withAlpha(20),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: value ? accent.withAlpha(100) : colors.outlineVariant.withAlpha(40),
                ),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 150),
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: value ? accent : colors.onSurfaceVariant.withAlpha(100),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
