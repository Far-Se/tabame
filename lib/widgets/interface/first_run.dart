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
import '../widgets/windows_scroll.dart';

class FirstRun extends StatefulWidget {
  const FirstRun({super.key});
  @override
  FirstRunState createState() => FirstRunState();
}

class FirstRunState extends State<FirstRun> {
  FocusNode focusNode = FocusNode();
  final WizardlyContextMenu wizardlyContextMenu = WizardlyContextMenu();
  final PageController pageController = PageController();
  final List<Hotkeys> hokeyObj = <Hotkeys>[];

  int currentStep = 0;
  List<String> modifiers = <String>[];
  String hotkey = "";
  bool listeningToHotkey = false;
  final List<String> hotkeyTips = <String>[
    "The hotkey starts working after you finish setup.",
    "Mouse side buttons are great choices if your mouse has them.",
    "Mouse software can also remap a spare button to a rarer shortcut like CTRL+ALT+SHIFT+F9.",
    "If you do not have extra mouse buttons, WIN+SHIFT+A is a comfortable keyboard option.",
  ];
  final List<String> hotkeyActions = <String>[
    "Press once to open QuickMenu.",
    "Hold to open Start.",
    "Double press to focus the previous active window.",
    "Hold and move up or down to change volume.",
    "Hold and move left or right to switch virtual desktops.",
    "Near screen corners it can also toggle Start, Desktop, or the taskbar depending on position.",
    "On Chrome and Firefox tab bars, press to close the hovered tab or hold to open a new one.",
    "Many more features you can check in Settings -> Hotkeys.",
  ];

  final List<String> mouseButtons = <String>[
    Hotkeys.mouseButton4Key,
    Hotkeys.mouseButton5Key,
    Hotkeys.doubleAltKey,
  ];
  int sizeIncrement = 1;
  @override
  void initState() {
    super.initState();
    for (Map<String, dynamic> x in mainHotkeyData) {
      hokeyObj.add(Hotkeys.fromMap(x));
    }
    WinUtils.setStartUpShortcut(true);
    // Future<void>.delayed(const Duration(seconds: 1), () => downloadTabame());

    WinUtils.fixDrawBug();
  }

  @override
  void dispose() {
    focusNode.dispose();
    pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = userSettings.themeColors.accentColor;

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
                      _buildHotkeyPage(theme, accent),
                      _buildSetupPage(theme, accent),
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

  Widget _buildHero(ThemeData theme, Color accent) {
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
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  currentStep == 0 ? "Welcome to Tabame" : "A few helpful defaults",
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  currentStep == 0
                      ? "Start by choosing the shortcut that should open QuickMenu. You can change it again later."
                      : "These settings cover startup behavior, admin access, updates, privacy-sensitive tracking, and a few extra tools.",
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 180,
            child: Column(
              children: <Widget>[
                _buildStepChip(theme, accent, 0, "Hotkey"),
                const SizedBox(height: 10),
                _buildStepChip(theme, accent, 1, "Preferences"),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepChip(ThemeData theme, Color accent, int step, String label) {
    final bool active = currentStep == step;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _goToStep(step),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: active ? accent.withValues(alpha: 0.15) : theme.colorScheme.surface.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: active ? accent.withValues(alpha: 0.28) : theme.dividerColor.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                radius: 14,
                backgroundColor: active ? accent : theme.colorScheme.surfaceContainerHighest,
                child: Text(
                  "${step + 1}",
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: active ? Colors.white : theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
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

  Widget _buildHotkeyPage(ThemeData theme, Color accent) {
    return WindowsScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text("Choose your main hotkey", style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            "This is the shortcut you will use to open Tabame quickly.",
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: <Widget>[
              SizedBox(
                child: _inputChoiceCard(
                  theme,
                  accent: accent,
                  icon: listeningToHotkey ? Icons.keyboard_command_key_rounded : Icons.keyboard_alt_outlined,
                  title: "Keyboard shortcut",
                  subtitle: "Capture a keyboard combo to trigger QuickMenu.",
                  selected: !_isMouseHotkey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: _startHotkeyListening,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          decoration: BoxDecoration(
                            color: listeningToHotkey ? accent.withValues(alpha: 0.10) : Colors.transparent,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: listeningToHotkey
                                  ? accent.withValues(alpha: 0.28)
                                  : theme.dividerColor.withValues(alpha: 0.12),
                            ),
                          ),
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: Focus(
                                  focusNode: focusNode,
                                  onKeyEvent: _handleHotkeyKeyEvent,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        listeningToHotkey ? "Listening now" : "Current keyboard shortcut",
                                        style: theme.textTheme.labelLarge
                                            ?.copyWith(color: accent, fontWeight: FontWeight.w700),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        _selectedHotkeyLabel,
                                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              FilledButton.tonal(
                                onPressed: _startHotkeyListening,
                                style: FilledButton.styleFrom(
                                  foregroundColor: accent,
                                  backgroundColor: accent.withValues(alpha: 0.12),
                                ),
                                child: Text(listeningToHotkey ? "Press keys" : "Capture"),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: _buildOrDivider(theme, accent),
              ),
              SizedBox(
                child: _inputChoiceCard(
                  theme,
                  accent: accent,
                  icon: Icons.mouse_rounded,
                  title: "Special triggers",
                  subtitle: "Pick a side button or the Double Alt trigger.",
                  selected: _isMouseHotkey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _isMouseHotkey
                            ? "Current shortcut: ${Hotkeys.displayKey(hotkey)}"
                            : "No special trigger selected",
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Best for quick access if your mouse has extra thumb buttons.",
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor, height: 1.4),
                      ),
                      const SizedBox(height: 14),
                      LayoutBuilder(
                        builder: (BuildContext context, BoxConstraints constraints) {
                          final double tileWidth = (constraints.maxWidth - 12) / 2;
                          return Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: Hotkeys.specialBindingKeys
                                .map(
                                  (String binding) => SizedBox(
                                    width: tileWidth,
                                    child: _mouseButtonTile(theme, accent, binding),
                                  ),
                                )
                                .toList(),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: <Widget>[
              SizedBox(
                child: _card(theme, child: _tipsBlock(theme, "Good hotkey choices", hotkeyTips)),
              ),
              SizedBox(
                child: _card(theme, child: _tipsBlock(theme, "What this hotkey can do", hotkeyActions)),
              ),
            ],
          ),
        ],
      ),
    );
  }

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
                      value: userSettings.runAsAdministrator,
                      onChanged: (bool value) async {
                        userSettings.runAsAdministrator = value;
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
                      value: userSettings.autoCheckForUpdates,
                      onChanged: (bool value) async {
                        userSettings.autoCheckForUpdates = value;
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
                      value: userSettings.hideTaskbarOnStartup,
                      onChanged: (bool value) async {
                        userSettings.hideTaskbarOnStartup = value;
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
                      value: userSettings.trktivityEnabled,
                      trailing: InfoWidget("Open saved data folder", onTap: () {
                        WinUtils.open(WinUtils.getTabameAppDataFolder());
                      }),
                      onChanged: (bool value) {
                        setState(() {
                          userSettings.trktivityEnabled = value;
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
                Text("You're ready to go", style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                  "After the app launches, it's worth opening settings and browsing the sidebar once. Tabame has a lot more customization than this first screen shows.",
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStickyFooter(ThemeData theme, Color accent) {
    final bool isHotkeyStep = currentStep == 0;
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
            if (!isHotkeyStep)
              OutlinedButton.icon(
                onPressed: () => _goToStep(0),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text("Back"),
              )
            else
              Expanded(
                child: Text(
                  hotkey.isEmpty ? "Choose a hotkey to continue." : "Hotkey selected: $_selectedHotkeyLabel",
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: hotkey.isEmpty ? theme.hintColor : theme.colorScheme.onSurface,
                    fontWeight: hotkey.isEmpty ? FontWeight.w500 : FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (!isHotkeyStep) const Spacer(),
            FilledButton.icon(
              onPressed: isHotkeyStep ? (hotkey.isEmpty ? null : _continueSetup) : _finishSetup,
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Theme.of(context).colorScheme.surface,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              icon: Icon(isHotkeyStep ? Icons.arrow_forward_rounded : Icons.restart_alt_rounded),
              label: Text(isHotkeyStep ? "Continue to preferences" : "Save and launch"),
            ),
          ],
        ),
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
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor, height: 1.35),
                    ),
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

  Widget _mouseButtonTile(ThemeData theme, Color accent, String button) {
    final bool selected = hotkey == button;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _selectMouseButton(button),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.10) : theme.colorScheme.surface.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? accent.withValues(alpha: 0.22) : theme.dividerColor.withValues(alpha: 0.10),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  color: selected ? accent : theme.hintColor, size: 20),
              const SizedBox(height: 12),
              Text(Hotkeys.displayKey(button),
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                _specialBindingDescription(button),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor, height: 1.35),
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
    return _card(
      theme,
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
                      child: Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                    if (trailing != null) trailing,
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: value,
            activeThumbColor: accent,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  String get _selectedHotkeyLabel {
    if (hotkey.isEmpty) return "Press here to set your shortcut";
    return Hotkeys.formatHotkeyLabel(key: hotkey, modifiers: modifiers);
  }

  bool get _isMouseHotkey => Hotkeys.isSpecialBindingKey(hotkey);

  void _startHotkeyListening() {
    listeningToHotkey = !listeningToHotkey;
    FocusScope.of(context).requestFocus(focusNode);
    setState(() {});
  }

  void _selectMouseButton(String button) {
    modifiers.clear();
    _restoreCurrentSpecialBinding();
    hotkey = button;
    mouseButtons.remove(button);
    setState(() {});
  }

  KeyEventResult _handleHotkeyKeyEvent(FocusNode e, KeyEvent k) {
    final List<String> modifier = <String>[];
    if (HardwareKeyboard.instance.isControlPressed) modifier.add("CTRL");
    if (HardwareKeyboard.instance.isAltPressed) modifier.add("ALT");
    if (HardwareKeyboard.instance.isShiftPressed) modifier.add("SHIFT");
    if (HardwareKeyboard.instance.isMetaPressed) modifier.add("WIN");
    if (k.logicalKey.synonyms.isNotEmpty) return KeyEventResult.handled;
    _restoreCurrentSpecialBinding();

    hotkey = Hotkeys.keyFromLogicalKey(k.logicalKey);
    modifiers = Hotkeys.normalizeModifiers(modifier);
    FocusScope.of(context).unfocus();
    listeningToHotkey = false;
    setState(() {});
    return KeyEventResult.handled;
  }

  void _restoreCurrentSpecialBinding() {
    if (Hotkeys.isSpecialBindingKey(hotkey) && !mouseButtons.contains(hotkey)) {
      mouseButtons.add(hotkey);
    }
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

  Future<void> _goToStep(int step) async {
    if (step == currentStep) return;
    await pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _continueSetup() async {
    final List<String> savedModifiers = Hotkeys.normalizeModifiers(modifiers);
    if (!kReleaseMode) {
      hokeyObj.first.key = hotkey;
      hokeyObj.first.modifiers = savedModifiers;
      Boxes.updateSettings("remap", jsonEncode(hokeyObj));
    }
    Boxes.updateSettings("justInstalled", true);
    Boxes.pref.setInt("installDate", DateTime.now().millisecondsSinceEpoch);
    await _goToStep(1);
  }

  Future<void> _finishSetup() async {
    if (kReleaseMode) {
      final List<String> savedModifiers = Hotkeys.normalizeModifiers(modifiers);
      hokeyObj.first.key = hotkey;
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
