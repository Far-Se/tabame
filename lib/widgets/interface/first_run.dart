import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:tabamewin32/tabamewin32.dart';

import '../../models/classes/boxes.dart';
import '../../models/classes/hotkeys.dart';
import '../../models/globals.dart';
import '../../models/settings.dart';
import '../../models/util/main_hotkey.dart';
import '../../models/win32/win32.dart';
import '../../models/win32/win_utils.dart';
import '../widgets/info_widget.dart';
import '../widgets/mini_switch.dart';
import '../widgets/windows_scroll.dart';

class FirstRun extends StatefulWidget {
  const FirstRun({super.key});
  @override
  FirstRunState createState() => FirstRunState();
}

class FirstRunState extends State<FirstRun> {
  final WizardlyContextMenu wizardlyContextMenu = WizardlyContextMenu();
  final PageController pageController = PageController();
  final List<Hotkeys> hokeyObj = <Hotkeys>[];

  int currentStep = 0;

  // ── Modal State Setter ──
  StateSetter? _activeModalState;

  // ── QuickMenu ──
  final FocusNode quickMenuFocus = FocusNode();
  List<String> quickMenuModifiers = <String>[];
  String quickMenuHotkey = "";
  bool quickMenuListening = false;

  // ── Launcher ──
  final FocusNode launcherFocus = FocusNode();
  List<String> launcherModifiers = <String>["WIN", "SHIFT"];
  String launcherHotkey = "A";
  bool launcherListening = false;

  // ── QuickClick ──
  final FocusNode quickClickFocus = FocusNode();
  List<String> quickClickModifiers = <String>[];
  String quickClickHotkey = "";
  bool quickClickListening = false;

  // ── QuickSnap (toggle only) ──
  bool quickSnapEnabled = true;

  // ── Fancyshot ──
  final FocusNode fancyshotFocus = FocusNode();
  List<String> fancyshotModifiers = <String>[];
  String fancyshotHotkey = "";
  bool fancyshotListening = false;

  // ── EmojiPicker ──
  final FocusNode emojiPickerFocus = FocusNode();
  List<String> emojiPickerModifiers = <String>["WIN", "SHIFT"];
  String emojiPickerHotkey = "E";
  bool emojiPickerListening = false;

  // ── Color Picker ──
  final FocusNode colorPickerFocus = FocusNode();
  List<String> colorPickerModifiers = <String>["WIN", "SHIFT"];
  String colorPickerHotkey = "C";
  bool colorPickerListening = false;

  final List<String> quickMenuActions = <String>[
    "Press once to open QuickMenu right next to your mouse cursor.",
    "Hold to open Start.",
    "Double press to focus the previous active window.",
    "Hold and move up or down to change volume.",
    "Hold and move left or right to switch virtual desktops.",
    "Near screen corners it can also toggle Start, Desktop, or the taskbar depending on position.",
    "On Chrome and Firefox tab bars, press to close the hovered tab or hold to open a new one.",
    "Many more features you can check in Settings → Hotkeys.",
  ];

  @override
  void initState() {
    super.initState();
    for (Map<String, dynamic> x in mainHotkeyData) {
      hokeyObj.add(Hotkeys.fromMap(x));
    }
    WinUtils.setStartUpShortcut(true);
    WinUtils.fixDrawBug();
  }

  @override
  void dispose() {
    quickMenuFocus.dispose();
    launcherFocus.dispose();
    quickClickFocus.dispose();
    fancyshotFocus.dispose();
    emojiPickerFocus.dispose();
    colorPickerFocus.dispose();
    pageController.dispose();
    super.dispose();
  }

  // ─────────────────────────── MUTUAL EXCLUSION ──────────────────────────

  List<String> _getAvailableSpecialKeys(String currentAssignedKey) {
    const List<String> allKeys = Hotkeys.specialBindingKeys;
    final List<String> currentlyUsed = <String>[
      quickMenuHotkey,
      launcherHotkey,
      quickClickHotkey,
      fancyshotHotkey,
      emojiPickerHotkey,
      colorPickerHotkey,
    ].where((String k) => Hotkeys.isSpecialBindingKey(k)).toList();

    return allKeys.where((String k) => k == currentAssignedKey || !currentlyUsed.contains(k)).toList();
  }

  // ─────────────────────────── MODAL CONTROLLER ──────────────────────────

  void _showFeatureModal(ThemeData theme, Color accent, String title, Widget Function() contentBuilder) {
    showDialog(
      context: context,
      anchorPoint: const Offset(100, 200),
      builder: (BuildContext ctx) {
        return Material(
          type: MaterialType.transparency,
          child: SafeArea(
            child: AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: Design.accent.withAlpha(40),
                  width: 1,
                ),
              ),
              shadowColor: Design.accent.withValues(alpha: 0.3),
              backgroundColor: Design.background,
              title: Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              actions: <Widget>[
                ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text("OK"),
                ),
              ],
              content: StatefulBuilder(
                builder: (BuildContext context, StateSetter setModalState) {
                  _activeModalState = setModalState;
                  return SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const SizedBox(height: 16),
                        contentBuilder(),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    ).whenComplete(() {
      _activeModalState = null;
      quickMenuListening = false;
      launcherListening = false;
      quickClickListening = false;
      fancyshotListening = false;
      emojiPickerListening = false;
      colorPickerListening = false;
      setState(() {});
    });
  }

  // ─────────────────────────── BUILD ────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = Design.accent;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildHero(theme, accent),
          const SizedBox(height: 14),
          Expanded(
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: PageView(
                    controller: pageController,
                    allowImplicitScrolling: false,
                    physics: const NeverScrollableScrollPhysics(),
                    onPageChanged: (int index) => setState(() => currentStep = index),
                    children: <Widget>[
                      _buildHotkeysPage(theme, accent),
                      _buildSetupPage(theme, accent),
                      _buildSettingsOutroPage(theme, accent),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildStickyFooter(theme, accent),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────── HERO ────────────────────────────

  Widget _buildHero(ThemeData theme, Color accent) {
    const List<_StepMeta> steps = <_StepMeta>[
      _StepMeta(0, "Hotkeys"),
      _StepMeta(1, "Preferences"),
      _StepMeta(2, "Settings"),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            accent.withValues(alpha: 0.01),
            theme.colorScheme.surface.withValues(alpha: 0.3),
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            _heroTitle,
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            _heroSubtitle,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor, height: 1.4),
          ),
          const SizedBox(height: 14),
          Row(
            children: steps.map((_StepMeta s) {
              final bool isLast = s == steps.last;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: isLast ? 0 : 8),
                  child: _buildStepChip(theme, accent, s.index, s.label),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  String get _heroTitle {
    switch (currentStep) {
      case 0:
        return "Welcome to Tabame";
      case 1:
        return "A few helpful defaults";
      case 2:
        return "One more thing";
      default:
        return "Welcome to Tabame";
    }
  }

  String get _heroSubtitle {
    switch (currentStep) {
      case 0:
        return "Set up your hotkeys — tap any item to configure its shortcut.";
      case 1:
        return "These settings cover startup behavior, admin access, updates, privacy-sensitive tracking, and extra tools.";
      case 2:
        return "Settings is where the real power lives — every feature has its own dedicated page.";
      default:
        return "";
    }
  }

  Widget _buildStepChip(ThemeData theme, Color accent, int step, String label) {
    final bool active = currentStep == step;
    final bool done = currentStep > step;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _goToStep(step),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: active ? accent.withValues(alpha: 0.15) : theme.colorScheme.surface.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: active ? accent.withValues(alpha: 0.28) : theme.dividerColor.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              CircleAvatar(
                radius: 11,
                backgroundColor: done
                    ? accent.withValues(alpha: 0.55)
                    : active
                        ? accent
                        : theme.colorScheme.surfaceContainerHighest,
                child: done
                    ? const Icon(Icons.check_rounded, size: 12, color: Colors.white)
                    : Text(
                        "${step + 1}",
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: active ? Colors.white : theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: active ? theme.colorScheme.onSurface : theme.hintColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────── PAGE 0: HOTKEYS ─────────────────────────

  Widget _buildHotkeysPage(ThemeData theme, Color accent) {
    return WindowsScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text("Configure hotkeys", style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            "Tap any item to set its shortcut. All hotkeys can be changed later in Settings → Hotkeys.",
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor, height: 1.4),
          ),
          const SizedBox(height: 16),

          // ── QuickMenu ──
          _buildFeatureRow(
            theme,
            accent,
            icon: Icons.rocket_launch_rounded,
            title: "QuickMenu Hotkey",
            subtitle: "Opens QuickMenu right next to your cursor.",
            currentHotkey: quickMenuHotkey,
            currentModifiers: quickMenuModifiers,
            onTap: () {
              _showFeatureModal(theme, accent, "QuickMenu Hotkey", () {
                return _buildQuickMenuExpanded(theme, accent);
              });
            },
          ),
          const SizedBox(height: 10),

          // ── Launcher ──
          _buildFeatureRow(
            theme,
            accent,
            icon: Icons.search_rounded,
            title: "Launcher",
            subtitle: "Full-screen launcher in the center of the screen.",
            currentHotkey: launcherHotkey,
            currentModifiers: launcherModifiers,
            onTap: () {
              _showFeatureModal(theme, accent, "Launcher", () {
                return _buildGenericHotkeyExpanded(
                  theme,
                  accent,
                  description:
                      "Opens a full-screen launcher in the center of the screen — search apps, files, and commands. "
                      "For file search to work, add Watched Folders in Settings → Launcher.\n"
                      "Suggested hotkey: Win+Shift+A, or double Alt.",
                  focusNode: launcherFocus,
                  listening: launcherListening,
                  hotkey: launcherHotkey,
                  modifiers: launcherModifiers,
                  onStartListening: () {
                    launcherListening = !launcherListening;
                    launcherFocus.requestFocus(launcherFocus);
                    setState(() {});
                    _activeModalState?.call(() {});
                  },
                  onKeyEvent: _handleLauncherKeyEvent,
                  onSelectMouse: _selectLauncherMouseButton,
                );
              });
            },
          ),
          const SizedBox(height: 10),

          // ── QuickClick ──
          _buildFeatureRow(
            theme,
            accent,
            icon: Icons.open_with_rounded,
            title: "QuickClick",
            subtitle: "Move the mouse with the keyboard.",
            currentHotkey: quickClickHotkey,
            currentModifiers: quickClickModifiers,
            onTap: () {
              _showFeatureModal(theme, accent, "QuickClick", () {
                return _buildGenericHotkeyExpanded(
                  theme,
                  accent,
                  description:
                      "Move your cursor precisely using only the keyboard — navigate any UI without touching the mouse.\n"
                      "Suggested hotkey: Right Alt (rarely conflicts with other shortcuts).",
                  focusNode: quickClickFocus,
                  listening: quickClickListening,
                  hotkey: quickClickHotkey,
                  modifiers: quickClickModifiers,
                  onStartListening: () {
                    quickClickListening = !quickClickListening;
                    quickClickFocus.requestFocus(quickClickFocus);
                    setState(() {});
                    _activeModalState?.call(() {});
                  },
                  onKeyEvent: _handleQuickClickKeyEvent,
                  onSelectMouse: _selectQuickClickMouseButton,
                );
              });
            },
          ),
          const SizedBox(height: 10),

          // ── QuickSnap ──
          _buildFeatureRow(
            theme,
            accent,
            icon: Icons.grid_view_rounded,
            title: "QuickSnap",
            subtitle: "Snap windows by dragging then right-clicking.",
            currentHotkey: "",
            currentModifiers: const <String>[],
            isToggle: true,
            toggleValue: quickSnapEnabled,
            onTap: () {
              _showFeatureModal(theme, accent, "QuickSnap", () {
                return _buildQuickSnapExpanded(theme, accent);
              });
            },
          ),
          const SizedBox(height: 10),

          // ── Fancyshot ──
          _buildFeatureRow(
            theme,
            accent,
            icon: Icons.camera_alt_rounded,
            title: "Fancyshot",
            subtitle: "Screen capture with directional modes.",
            currentHotkey: fancyshotHotkey,
            currentModifiers: fancyshotModifiers,
            onTap: () {
              _showFeatureModal(theme, accent, "Fancyshot", () {
                return _buildFancyshotExpanded(theme, accent);
              });
            },
          ),
          const SizedBox(height: 10),

          // ── EmojiPicker ──
          _buildFeatureRow(
            theme,
            accent,
            icon: Icons.emoji_emotions_rounded,
            title: "EmojiPicker",
            subtitle: "Opens an emoji picker next to your cursor.",
            currentHotkey: emojiPickerHotkey,
            currentModifiers: emojiPickerModifiers,
            onTap: () {
              _showFeatureModal(theme, accent, "EmojiPicker", () {
                return _buildGenericHotkeyExpanded(
                  theme,
                  accent,
                  description:
                      "Opens a searchable emoji picker right next to your cursor — just pick and it's inserted instantly.\n"
                      "Suggested hotkey: Win+Shift+E.",
                  focusNode: emojiPickerFocus,
                  listening: emojiPickerListening,
                  hotkey: emojiPickerHotkey,
                  modifiers: emojiPickerModifiers,
                  onStartListening: () {
                    emojiPickerListening = !emojiPickerListening;
                    emojiPickerFocus.requestFocus(emojiPickerFocus);
                    setState(() {});
                    _activeModalState?.call(() {});
                  },
                  onKeyEvent: _handleEmojiPickerKeyEvent,
                  onSelectMouse: _selectEmojiPickerMouseButton,
                );
              });
            },
          ),
          const SizedBox(height: 10),
          // ── Color Picker ──
          _buildFeatureRow(
            theme,
            accent,
            icon: Icons.colorize_rounded,
            title: "Color Picker",
            subtitle: "Pick any color from your screen.",
            currentHotkey: colorPickerHotkey,
            currentModifiers: colorPickerModifiers,
            onTap: () {
              _showFeatureModal(theme, accent, "Color Picker", () {
                return _buildGenericHotkeyExpanded(
                  theme,
                  accent,
                  description: "Instantly grab any color from your screen and copy its hex code to your clipboard.\n"
                      "Suggested hotkey: Win+Shift+C.",
                  focusNode: colorPickerFocus,
                  listening: colorPickerListening,
                  hotkey: colorPickerHotkey,
                  modifiers: colorPickerModifiers,
                  onStartListening: () {
                    colorPickerListening = !colorPickerListening;
                    colorPickerFocus.requestFocus(colorPickerFocus);
                    setState(() {});
                    _activeModalState?.call(() {});
                  },
                  onKeyEvent: _handleColorPickerKeyEvent,
                  onSelectMouse: _selectColorPickerMouseButton,
                );
              });
            },
          ),
        ],
      ),
    );
  }

  // ── Feature row: Tap to open modal ──
  Widget _buildFeatureRow(
    ThemeData theme,
    Color accent, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String currentHotkey,
    required List<String> currentModifiers,
    required VoidCallback onTap,
    bool isToggle = false,
    bool toggleValue = false,
  }) {
    final String badgeLabel = isToggle
        ? (toggleValue ? "Enabled" : "Disabled")
        : (currentHotkey.isEmpty
            ? "Not set"
            : Hotkeys.formatHotkeyLabel(key: currentHotkey, modifiers: currentModifiers));

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.12)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: accent, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor, height: 1.3)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Badge showing current hotkey / status
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: currentHotkey.isNotEmpty || (isToggle && toggleValue)
                        ? accent.withValues(alpha: 0.12)
                        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    badgeLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: currentHotkey.isNotEmpty || (isToggle && toggleValue) ? accent : theme.hintColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.edit_rounded, color: theme.hintColor, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── QuickMenu expanded panel ──
  Widget _buildQuickMenuExpanded(ThemeData theme, Color accent) {
    final List<String> availableSpecialKeys = _getAvailableSpecialKeys(quickMenuHotkey);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _infoBox(
          theme,
          accent,
          icon: Icons.mouse_rounded,
          text: "This opens QuickMenu right next to your cursor — so pick something instant. "
              "If your mouse has extra buttons, open your mouse software and bind one to an obscure combo "
              "like Ctrl+Shift+Alt+Win+F8, then press it in the listener below. "
              "No extra buttons? Try Alt+Z.",
        ),
        const SizedBox(height: 14),
        _inputChoiceCard(
          theme,
          accent: accent,
          icon: quickMenuListening ? Icons.keyboard_command_key_rounded : Icons.keyboard_alt_outlined,
          title: "Keyboard shortcut",
          subtitle: "Capture a keyboard combo to trigger QuickMenu.",
          selected: !Hotkeys.isSpecialBindingKey(quickMenuHotkey),
          child: _buildOriginalHotkeyListener(
            theme,
            accent,
            focusNode: quickMenuFocus,
            listening: quickMenuListening,
            label: quickMenuHotkey.isEmpty
                ? "Press here to set your shortcut"
                : Hotkeys.formatHotkeyLabel(key: quickMenuHotkey, modifiers: quickMenuModifiers),
            onTap: () {
              quickMenuListening = !quickMenuListening;
              quickMenuFocus.requestFocus();
              setState(() {});
              _activeModalState?.call(() {});
            },
            onKeyEvent: _handleQuickMenuKeyEvent,
          ),
        ),
        const SizedBox(height: 10),
        _buildOrDivider(theme, accent),
        const SizedBox(height: 10),
        _inputChoiceCard(
          theme,
          accent: accent,
          icon: Icons.mouse_rounded,
          title: "Special triggers",
          subtitle: "Pick a side button or the Double Alt trigger.",
          selected: Hotkeys.isSpecialBindingKey(quickMenuHotkey),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                Hotkeys.isSpecialBindingKey(quickMenuHotkey)
                    ? "Current shortcut: ${Hotkeys.displayKey(quickMenuHotkey)}"
                    : "No special trigger selected",
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text("Best for quick access if your mouse has extra thumb buttons.",
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor, height: 1.4)),
              const SizedBox(height: 12),
              availableSpecialKeys.isEmpty
                  ? Text("All special triggers are currently assigned to other features.",
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor, fontStyle: FontStyle.italic))
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: availableSpecialKeys
                          .map((String b) => _mouseButtonChip(
                                theme,
                                accent,
                                b,
                                selected: quickMenuHotkey == b,
                                onTap: () => _selectQuickMenuMouseButton(b),
                                description: _specialBindingDescription(b),
                              ))
                          .toList(),
                    ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _tipsBlock(theme, "What this hotkey can do", quickMenuActions),
      ],
    );
  }

  // ── Generic keyboard + special-triggers expanded panel ──
  Widget _buildGenericHotkeyExpanded(
    ThemeData theme,
    Color accent, {
    required String description,
    required FocusNode focusNode,
    required bool listening,
    required String hotkey,
    required List<String> modifiers,
    required VoidCallback onStartListening,
    required KeyEventResult Function(FocusNode, KeyEvent) onKeyEvent,
    required void Function(String) onSelectMouse,
  }) {
    final List<String> availableSpecialKeys = _getAvailableSpecialKeys(hotkey);
    final String label = hotkey.isEmpty
        ? "Press here to set your shortcut"
        : Hotkeys.formatHotkeyLabel(key: hotkey, modifiers: modifiers);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(description, style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor, height: 1.4)),
        const SizedBox(height: 14),
        _inputChoiceCard(
          theme,
          accent: accent,
          icon: listening ? Icons.keyboard_command_key_rounded : Icons.keyboard_alt_outlined,
          title: "Keyboard shortcut",
          subtitle: "Capture a keyboard combo.",
          selected: !Hotkeys.isSpecialBindingKey(hotkey),
          child: _buildOriginalHotkeyListener(
            theme,
            accent,
            focusNode: focusNode,
            listening: listening,
            label: label,
            onTap: onStartListening,
            onKeyEvent: onKeyEvent,
          ),
        ),
        const SizedBox(height: 10),
        _buildOrDivider(theme, accent),
        const SizedBox(height: 10),
        _inputChoiceCard(
          theme,
          accent: accent,
          icon: Icons.mouse_rounded,
          title: "Special triggers",
          subtitle: "Pick a side button or the Double Alt trigger.",
          selected: Hotkeys.isSpecialBindingKey(hotkey),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                Hotkeys.isSpecialBindingKey(hotkey)
                    ? "Current shortcut: ${Hotkeys.displayKey(hotkey)}"
                    : "No special trigger selected",
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text("Best for quick access if your mouse has extra thumb buttons.",
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor, height: 1.4)),
              const SizedBox(height: 12),
              availableSpecialKeys.isEmpty
                  ? Text("All special triggers are currently assigned to other features.",
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor, fontStyle: FontStyle.italic))
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: availableSpecialKeys
                          .map((String b) => _mouseButtonChip(
                                theme,
                                accent,
                                b,
                                selected: hotkey == b,
                                onTap: () => onSelectMouse(b),
                                description: _specialBindingDescription(b),
                              ))
                          .toList(),
                    ),
            ],
          ),
        ),
      ],
    );
  }

  // ── QuickSnap expanded panel (toggle only) ──
  Widget _buildQuickSnapExpanded(ThemeData theme, Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                "Drag a window's title bar, then right-click — QuickSnap intercepts the right-click and shows snapping zones. "
                "Toggle off if you prefer default Windows snapping behavior. More settings and Zones Creator in QuickSnap Settings",
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor, height: 1.4),
              ),
            ),
            const SizedBox(width: 14),
            MiniToggleSwitch(
              value: quickSnapEnabled,
              activeThumbColor: accent,
              onChanged: (bool v) {
                quickSnapEnabled = v;
                setState(() {});
                _activeModalState?.call(() {});
              },
            ),
          ],
        ),
      ],
    );
  }

  // ── Fancyshot expanded panel ──
  Widget _buildFancyshotExpanded(ThemeData theme, Color accent) {
    final List<_FancyshotAction> actions = <_FancyshotAction>[
      const _FancyshotAction(Icons.touch_app_rounded, "Just press", "Frozen Screen Capture"),
      const _FancyshotAction(Icons.arrow_back_rounded, "Hold + move Left", "Live Screen Capture"),
      const _FancyshotAction(Icons.arrow_upward_rounded, "Hold + move Up", "Screen Recorder"),
      const _FancyshotAction(Icons.arrow_downward_rounded, "Hold + move Down", "Screen Draw"),
      const _FancyshotAction(Icons.arrow_forward_rounded, "Hold + move Right", "Spotlight"),
    ];
    final List<String> availableSpecialKeys = _getAvailableSpecialKeys(fancyshotHotkey);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          "Hold the hotkey and move the mouse to pick a capture mode. Release to activate. You can create different hotkeys for each from Hotkeys Settings",
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor, height: 1.4),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: actions
              .map((_FancyshotAction a) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: theme.dividerColor.withValues(alpha: 0.12)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(a.icon, size: 13, color: accent),
                        const SizedBox(width: 6),
                        Text(a.direction, style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor)),
                        const SizedBox(width: 4),
                        Text("→", style: TextStyle(color: theme.hintColor, fontSize: Design.baseFontSize + 1)),
                        const SizedBox(width: 4),
                        Text(a.action, style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 14),
        _inputChoiceCard(
          theme,
          accent: accent,
          icon: fancyshotListening ? Icons.keyboard_command_key_rounded : Icons.keyboard_alt_outlined,
          title: "Keyboard shortcut",
          subtitle: "Capture a keyboard combo.",
          selected: !Hotkeys.isSpecialBindingKey(fancyshotHotkey),
          child: _buildOriginalHotkeyListener(
            theme,
            accent,
            focusNode: fancyshotFocus,
            listening: fancyshotListening,
            label: fancyshotHotkey.isEmpty
                ? "Press here to set your shortcut"
                : Hotkeys.formatHotkeyLabel(key: fancyshotHotkey, modifiers: fancyshotModifiers),
            onTap: () {
              fancyshotListening = !fancyshotListening;
              launcherFocus.requestFocus();
              setState(() {});
              _activeModalState?.call(() {});
            },
            onKeyEvent: _handleFancyshotKeyEvent,
          ),
        ),
        const SizedBox(height: 10),
        _buildOrDivider(theme, accent),
        const SizedBox(height: 10),
        _inputChoiceCard(
          theme,
          accent: accent,
          icon: Icons.mouse_rounded,
          title: "Special triggers",
          subtitle: "Pick a side button or the Double Alt trigger.",
          selected: Hotkeys.isSpecialBindingKey(fancyshotHotkey),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                Hotkeys.isSpecialBindingKey(fancyshotHotkey)
                    ? "Current shortcut: ${Hotkeys.displayKey(fancyshotHotkey)}"
                    : "No special trigger selected",
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text("Best for quick access if your mouse has extra thumb buttons.",
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor, height: 1.4)),
              const SizedBox(height: 12),
              availableSpecialKeys.isEmpty
                  ? Text("All special triggers are currently assigned to other features.",
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor, fontStyle: FontStyle.italic))
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: availableSpecialKeys
                          .map((String b) => _mouseButtonChip(
                                theme,
                                accent,
                                b,
                                selected: fancyshotHotkey == b,
                                onTap: () => _selectFancyshotMouseButton(b),
                                description: _specialBindingDescription(b),
                              ))
                          .toList(),
                    ),
            ],
          ),
        ),
      ],
    );
  }

  // ─────────────────────── PAGE 1: PREFERENCES ─────────────────────────

  Widget _buildSetupPage(ThemeData theme, Color accent) {
    return WindowsScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text("Recommended setup", style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            "These defaults help Tabame feel more complete on day one, but every option can be changed later.",
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor, height: 1.4),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: <Widget>[
              SizedBox(
                child: Column(
                  children: <Widget>[
                    _toggleCard(
                      theme,
                      accent: accent,
                      title: "Run on startup",
                      description: "Launch Tabame with Windows so your hotkey is available immediately.",
                      value: WinUtils.checkIfRegisterAsStartup(),
                      onChanged: (bool value) async {
                        await WinUtils.setStartUpShortcut(value);
                        if (!mounted) return;
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 14),
                    _toggleCard(
                      theme,
                      accent: accent,
                      title: "Run as administrator",
                      description: "Recommended. This helps Tabame focus and manage elevated windows more reliably.",
                      value: user.runAsAdministrator,
                      onChanged: (bool value) async {
                        user.runAsAdministrator = value;
                        await Boxes.updateSettings("runAsAdministrator", value);
                        if (!mounted) return;
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 14),
                    _toggleCard(
                      theme,
                      accent: accent,
                      title: "Auto check for updates",
                      description:
                          "Tabame will check for new versions on startup and notify you if an update is available.",
                      value: user.autoCheckForUpdates,
                      onChanged: (bool value) async {
                        user.autoCheckForUpdates = value;
                        await Boxes.updateSettings("autoUpdate", value);
                        if (!mounted) return;
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ),
              SizedBox(
                child: Column(
                  children: <Widget>[
                    _toggleCard(
                      theme,
                      accent: accent,
                      title: "Hide taskbar on startup",
                      description: "Useful if you want QuickMenu to be the main launcher and keep the desktop calmer."
                          "\nAtention: You can show the taskbar by moving the mouse at the bottom of the screen then pressing the selected hotkey",
                      value: user.hideTaskbarOnStartup,
                      onChanged: (bool value) async {
                        user.hideTaskbarOnStartup = value;
                        await Boxes.updateSettings("hideTaskbarOnStartup", value);
                        if (!mounted) return;
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 14),
                    _toggleCard(
                      theme,
                      accent: accent,
                      title: "Enable Trktivity",
                      description:
                          "Stores activity history locally, including keystrokes, mouse movement, and active window titles.",
                      value: user.trktivityEnabled,
                      trailing: InfoWidget("Open saved data folder", onTap: () {
                        WinUtils.open(WinUtils.getTabameAppDataFolder());
                      }),
                      onChanged: (bool value) {
                        setState(() {
                          user.trktivityEnabled = value;
                          Boxes.updateSettings("trktivityEnabled", value);
                          enableTrcktivity(value);
                        });
                      },
                    ),
                    const SizedBox(height: 14),
                    _toggleCard(
                      theme,
                      accent: accent,
                      title: "Add Wizardly to folder context menu",
                      description:
                          "Adds quick file and folder tools like search, rename helpers, project overview, and folder-size scanning.",
                      value: wizardlyContextMenu.isWizardlyInstalledInContextMenu(),
                      onChanged: (bool value) async {
                        wizardlyContextMenu.toggleWizardlyToContextMenu();
                        if (!mounted) return;
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _card(
            theme,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text("Almost there!", style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                  "One last page to go — it covers Settings, where you can fully customize every feature.",
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────── PAGE 2: SETTINGS OUTRO ─────────────────────────

  Widget _buildSettingsOutroPage(ThemeData theme, Color accent) {
    return WindowsScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text("Explore Settings to make Tabame yours",
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            "Every feature in Tabame has its own settings page. Open Settings from the QuickMenu or tray icon.",
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor, height: 1.4),
          ),
          const SizedBox(height: 18),
          _card(
            theme,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(Icons.settings_rounded, color: accent, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Text("What you can customize",
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  "Settings is divided into sections — here's what you'll find inside:",
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
                ),
                const SizedBox(height: 12),
                _settingsSectionPlaceholder(theme, accent),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _card(
            theme,
            child: Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.tips_and_updates_rounded, color: accent, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    "You can return to this setup wizard any time from Settings → About → Run First-Run Wizard.",
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _card(
            theme,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text("You're all set!", style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                  "Press Save and launch — your hotkeys will be active immediately.",
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingsSectionPlaceholder(ThemeData theme, Color accent) {
    const List<String> sections = <String>[
      "Hotkeys — Remap every action, add new ones, and fine-tune gesture behavior.",
      "QuickMenu — Choose which items appear and reorder them.",
      "Launcher — Add watched folders, change appearance, and set search preferences.",
      "Fancyshot — Set default capture mode, output folder, and image format.",
      "QuickSnap — Define snap zones and grid layout.",
      "Appearance — Switch themes, accent colors, and font size.",
      "Privacy & Data — Manage Trktivity logs and reset all stored data.",
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: sections.map((String s) => _bulletItem(theme, s)).toList(),
    );
  }

  // ─────────────────────── FOOTER ─────────────────────────

  Widget _buildStickyFooter(ThemeData theme, Color accent) {
    final bool isFirstStep = currentStep == 0;
    final bool isLastStep = currentStep == 2;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: accent.withValues(alpha: 0.16)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: <Widget>[
            if (!isFirstStep)
              OutlinedButton.icon(
                onPressed: () => _goToStep(currentStep - 1),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text("Back"),
              )
            else
              Expanded(
                child: Text(
                  quickMenuHotkey.isEmpty
                      ? "Set the QuickMenu hotkey to continue."
                      : "QuickMenu: ${Hotkeys.formatHotkeyLabel(key: quickMenuHotkey, modifiers: quickMenuModifiers)}",
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: quickMenuHotkey.isEmpty ? theme.hintColor : theme.colorScheme.onSurface,
                    fontWeight: quickMenuHotkey.isEmpty ? FontWeight.w500 : FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (!isFirstStep) const Spacer(),
            FilledButton.icon(
              onPressed: isFirstStep
                  ? (quickMenuHotkey.isEmpty ? null : _continueSetup)
                  : isLastStep
                      ? _finishSetup
                      : () => _goToStep(currentStep + 1),
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Theme.of(context).colorScheme.surface,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              icon: Icon(isLastStep ? Icons.restart_alt_rounded : Icons.arrow_forward_rounded),
              label: Text(isFirstStep
                  ? "Continue"
                  : isLastStep
                      ? "Save and launch"
                      : "Next"),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────── SHARED WIDGETS ─────────────────────────

  /// The original hotkey listener widget, exactly as in the original code.
  Widget _buildOriginalHotkeyListener(
    ThemeData theme,
    Color accent, {
    required FocusNode focusNode,
    required bool listening,
    required String label,
    required VoidCallback onTap,
    required KeyEventResult Function(FocusNode, KeyEvent) onKeyEvent,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: listening ? accent.withValues(alpha: 0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: listening ? accent.withValues(alpha: 0.28) : theme.dividerColor.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Focus(
                focusNode: focusNode,
                onKeyEvent: onKeyEvent,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      listening ? "Listening now" : "Current keyboard shortcut",
                      style: theme.textTheme.labelLarge?.copyWith(color: accent, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      label,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.tonal(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                foregroundColor: accent,
                backgroundColor: accent.withValues(alpha: 0.12),
              ),
              child: Text(listening ? "Press keys" : "Capture"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoBox(ThemeData theme, Color accent, {required IconData icon, required String text}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: accent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: theme.textTheme.bodyMedium?.copyWith(height: 1.45)),
          ),
        ],
      ),
    );
  }

  Widget _card(ThemeData theme, {required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.12)),
      ),
      child: child,
    );
  }

  Widget _buildOrDivider(ThemeData theme, Color accent) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[
                  Colors.transparent,
                  accent.withValues(alpha: 0.18),
                  accent.withValues(alpha: 0.08),
                ],
              ),
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 14),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: accent.withValues(alpha: 0.14)),
          ),
          child: Text(
            "Or",
            style: theme.textTheme.labelLarge?.copyWith(
              color: accent,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[
                  accent.withValues(alpha: 0.08),
                  accent.withValues(alpha: 0.18),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _inputChoiceCard(
    ThemeData theme, {
    required Color accent,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool selected,
    required Widget child,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: selected ? accent.withValues(alpha: 0.05) : theme.colorScheme.surface.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? accent.withValues(alpha: 0.22) : theme.dividerColor.withValues(alpha: 0.10),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: selected
                      ? accent.withValues(alpha: 0.12)
                      : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor, height: 1.35)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _mouseButtonChip(
    ThemeData theme,
    Color accent,
    String button, {
    required bool selected,
    required VoidCallback onTap,
    required String description,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.14) : theme.colorScheme.surface.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? accent.withValues(alpha: 0.30) : theme.dividerColor.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                color: selected ? accent : theme.hintColor,
                size: 15,
              ),
              const SizedBox(width: 7),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(Hotkeys.displayKey(button),
                      style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                  Text(description, style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tipsBlock(ThemeData theme, String title, List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        ...items.map((String text) => _bulletItem(theme, text)),
      ],
    );
  }

  Widget _bulletItem(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(top: 7),
            decoration: const BoxDecoration(
              color: Color(0xffCE3F00),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: theme.textTheme.bodyMedium?.copyWith(height: 1.45)),
          ),
        ],
      ),
    );
  }

  Widget _toggleCard(
    ThemeData theme, {
    required Color accent,
    required String title,
    required String description,
    required bool value,
    required ValueChanged<bool> onChanged,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.12)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          // Inverts the current boolean value when the card is tapped
          onTap: () => onChanged(!value),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child:
                                Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                          ),
                          if (trailing != null) trailing,
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(description,
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor, height: 1.4)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                MiniToggleSwitch(
                  value: value,
                  activeThumbColor: accent,
                  // The switch itself also continues to handle its own tap events
                  onChanged: onChanged,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────── KEY EVENT HANDLERS ─────────────────────────

  KeyEventResult _handleQuickMenuKeyEvent(FocusNode e, KeyEvent k) {
    final List<String> modifier = <String>[];
    if (HardwareKeyboard.instance.isControlPressed) modifier.add("CTRL");
    if (HardwareKeyboard.instance.isAltPressed) modifier.add("ALT");
    if (HardwareKeyboard.instance.isShiftPressed) modifier.add("SHIFT");
    if (HardwareKeyboard.instance.isMetaPressed) modifier.add("WIN");
    if (k.logicalKey.synonyms.isNotEmpty) return KeyEventResult.handled;

    quickMenuHotkey = Hotkeys.keyFromLogicalKey(k.logicalKey);
    quickMenuModifiers = Hotkeys.normalizeModifiers(modifier);
    FocusScope.of(context).unfocus();
    quickMenuListening = false;
    setState(() {});
    _activeModalState?.call(() {});
    return KeyEventResult.handled;
  }

  KeyEventResult _handleLauncherKeyEvent(FocusNode e, KeyEvent k) {
    final List<String> modifier = <String>[];
    if (HardwareKeyboard.instance.isControlPressed) modifier.add("CTRL");
    if (HardwareKeyboard.instance.isAltPressed) modifier.add("ALT");
    if (HardwareKeyboard.instance.isShiftPressed) modifier.add("SHIFT");
    if (HardwareKeyboard.instance.isMetaPressed) modifier.add("WIN");
    if (k.logicalKey.synonyms.isNotEmpty) return KeyEventResult.handled;

    launcherHotkey = Hotkeys.keyFromLogicalKey(k.logicalKey);
    launcherModifiers = Hotkeys.normalizeModifiers(modifier);
    FocusScope.of(context).unfocus();
    launcherListening = false;
    setState(() {});
    _activeModalState?.call(() {});
    return KeyEventResult.handled;
  }

  KeyEventResult _handleQuickClickKeyEvent(FocusNode e, KeyEvent k) {
    final List<String> modifier = <String>[];
    if (HardwareKeyboard.instance.isControlPressed) modifier.add("CTRL");
    if (HardwareKeyboard.instance.isAltPressed) modifier.add("ALT");
    if (HardwareKeyboard.instance.isShiftPressed) modifier.add("SHIFT");
    if (HardwareKeyboard.instance.isMetaPressed) modifier.add("WIN");
    if (k.logicalKey.synonyms.isNotEmpty) return KeyEventResult.handled;

    quickClickHotkey = Hotkeys.keyFromLogicalKey(k.logicalKey);
    quickClickModifiers = Hotkeys.normalizeModifiers(modifier);
    FocusScope.of(context).unfocus();
    quickClickListening = false;
    setState(() {});
    _activeModalState?.call(() {});
    return KeyEventResult.handled;
  }

  KeyEventResult _handleFancyshotKeyEvent(FocusNode e, KeyEvent k) {
    final List<String> modifier = <String>[];
    if (HardwareKeyboard.instance.isControlPressed) modifier.add("CTRL");
    if (HardwareKeyboard.instance.isAltPressed) modifier.add("ALT");
    if (HardwareKeyboard.instance.isShiftPressed) modifier.add("SHIFT");
    if (HardwareKeyboard.instance.isMetaPressed) modifier.add("WIN");
    if (k.logicalKey.synonyms.isNotEmpty) return KeyEventResult.handled;

    fancyshotHotkey = Hotkeys.keyFromLogicalKey(k.logicalKey);
    fancyshotModifiers = Hotkeys.normalizeModifiers(modifier);
    FocusScope.of(context).unfocus();
    fancyshotListening = false;
    setState(() {});
    _activeModalState?.call(() {});
    return KeyEventResult.handled;
  }

  KeyEventResult _handleEmojiPickerKeyEvent(FocusNode e, KeyEvent k) {
    final List<String> modifier = <String>[];
    if (HardwareKeyboard.instance.isControlPressed) modifier.add("CTRL");
    if (HardwareKeyboard.instance.isAltPressed) modifier.add("ALT");
    if (HardwareKeyboard.instance.isShiftPressed) modifier.add("SHIFT");
    if (HardwareKeyboard.instance.isMetaPressed) modifier.add("WIN");
    if (k.logicalKey.synonyms.isNotEmpty) return KeyEventResult.handled;

    emojiPickerHotkey = Hotkeys.keyFromLogicalKey(k.logicalKey);
    emojiPickerModifiers = Hotkeys.normalizeModifiers(modifier);
    FocusScope.of(context).unfocus();
    emojiPickerListening = false;
    setState(() {});
    _activeModalState?.call(() {});
    return KeyEventResult.handled;
  }

  KeyEventResult _handleColorPickerKeyEvent(FocusNode e, KeyEvent k) {
    final List<String> modifier = <String>[];
    if (HardwareKeyboard.instance.isControlPressed) modifier.add("CTRL");
    if (HardwareKeyboard.instance.isAltPressed) modifier.add("ALT");
    if (HardwareKeyboard.instance.isShiftPressed) modifier.add("SHIFT");
    if (HardwareKeyboard.instance.isMetaPressed) modifier.add("WIN");
    if (k.logicalKey.synonyms.isNotEmpty) return KeyEventResult.handled;

    colorPickerHotkey = Hotkeys.keyFromLogicalKey(k.logicalKey);
    colorPickerModifiers = Hotkeys.normalizeModifiers(modifier);
    FocusScope.of(context).unfocus();
    colorPickerListening = false;
    setState(() {});
    _activeModalState?.call(() {});
    return KeyEventResult.handled;
  }

  void _selectColorPickerMouseButton(String button) {
    colorPickerModifiers.clear();
    colorPickerHotkey = button;
    setState(() {});
    _activeModalState?.call(() {});
  }
  // ── Mouse button selectors ──

  void _selectQuickMenuMouseButton(String button) {
    quickMenuModifiers.clear();
    quickMenuHotkey = button;
    setState(() {});
    _activeModalState?.call(() {});
  }

  void _selectLauncherMouseButton(String button) {
    launcherModifiers.clear();
    launcherHotkey = button;
    setState(() {});
    _activeModalState?.call(() {});
  }

  void _selectQuickClickMouseButton(String button) {
    quickClickModifiers.clear();
    quickClickHotkey = button;
    setState(() {});
    _activeModalState?.call(() {});
  }

  void _selectFancyshotMouseButton(String button) {
    fancyshotModifiers.clear();
    fancyshotHotkey = button;
    setState(() {});
    _activeModalState?.call(() {});
  }

  void _selectEmojiPickerMouseButton(String button) {
    emojiPickerModifiers.clear();
    emojiPickerHotkey = button;
    setState(() {});
    _activeModalState?.call(() {});
  }

  String _specialBindingDescription(String binding) {
    switch (binding) {
      case Hotkeys.mouseButton4Key:
        return "Usually the back thumb button.";
      case Hotkeys.mouseButton5Key:
        return "Usually the forward thumb button.";
      case Hotkeys.doubleAltKey:
        return "Tap Alt once, then press Alt again within 100ms.";
      default:
        return "Use this special input as a hotkey.";
    }
  }

  // ─────────────────────── NAVIGATION ─────────────────────────

  Future<void> _goToStep(int step) async {
    if (step == currentStep) return;
    await pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _continueSetup() async {
    final List<String> savedModifiers = Hotkeys.normalizeModifiers(quickMenuModifiers);
    if (!kReleaseMode) {
      hokeyObj.first.key = quickMenuHotkey;
      hokeyObj.first.modifiers = savedModifiers;
      Boxes.updateSettings("remap", jsonEncode(hokeyObj));
    }
    Boxes.updateSettings("justInstalled", true);
    Boxes.pref.setInt("installDate", DateTime.now().millisecondsSinceEpoch);
    await _goToStep(1);
  }

  Future<void> _finishSetup() async {
    if (kReleaseMode) {
      final List<String> savedModifiers = Hotkeys.normalizeModifiers(quickMenuModifiers);
      hokeyObj.first.key = quickMenuHotkey;
      hokeyObj.first.modifiers = savedModifiers;
      Boxes.updateSettings("remap", jsonEncode(hokeyObj));
      WinUtils.reloadTabameQuickMenu();
      Future<void>.delayed(const Duration(milliseconds: 200), () => exit(0));
    } else {
      Globals.changingPages = true;
      setState(() {});
      Globals.mainPageViewController.jumpToPage(Pages.quickmenu.index);
    }
  }

  void downloadTabame() async {
    final http.Response response = await http.get(Uri.parse("https://api.github.com/repos/far-se/tabame/releases"));
    if (response.statusCode != 200) return;
    final List<dynamic> json = jsonDecode(response.body);
    if (json.isEmpty) return;
    final Map<String, dynamic> lastVersion = json[0];
    String downloadLink = "";
    for (Map<String, dynamic> x in lastVersion["assets"]) {
      if (!x["name"].endsWith("zip")) continue;
      if (x.containsKey("browser_download_url")) {
        downloadLink = x["browser_download_url"];
        break;
      }
    }
    final String fileName = "${WinUtils.getTempFolder()}\\tabame_${lastVersion["tag_name"]}.zip";
    await WinUtils.downloadFile(downloadLink, fileName, () {
      final String dir = "${WinUtils.getTabameAppDataFolder()}";
      WinUtils.runPowerShell(<String>[
        'Expand-Archive -LiteralPath "$fileName" -DestinationPath "$dir" -Force;',
        'Remove-Item -LiteralPath "$fileName" -Force;',
      ]);
    });
  }
}

// ─────────────────────── DATA CLASSES ─────────────────────────

class _StepMeta {
  const _StepMeta(this.index, this.label);
  final int index;
  final String label;
}

class _FancyshotAction {
  const _FancyshotAction(this.icon, this.direction, this.action);
  final IconData icon;
  final String direction;
  final String action;
}
