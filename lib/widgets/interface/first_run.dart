import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
import 'hotkeys/hotkey_settings_dialog.dart';

/// Identifies each first-run feature that is backed by a real [Hotkeys] entry
/// in [Boxes.remap]. Each id is matched to its remap entry through the tabame
/// function the entry triggers (see [_FirstRunState._matchValue]).
enum _Feature {
  quickMenu,
  launcher,
  quickClick,
  fancyshot,
  emojiPicker,
  colorPicker,
}

class FirstRun extends StatefulWidget {
  const FirstRun({super.key});
  @override
  FirstRunState createState() => FirstRunState();
}

class FirstRunState extends State<FirstRun> {
  final WizardlyContextMenu wizardlyContextMenu = WizardlyContextMenu();
  final PageController pageController = PageController();

  /// Canonical, persisted list of hotkeys. Every feature row below points at
  /// one entry in here, and edits go through [HotKeySettings] which writes back
  /// to it directly — so nothing depends on a final "save" step anymore.
  final List<Hotkeys> remap = Boxes.remap;

  /// Resolved index of each feature inside [remap]. Recomputed whenever the
  /// hotkey list changes so deletions/reorders from [HotKeySettings] can't
  /// leave us pointing at the wrong entry.
  final Map<_Feature, int> _featureIndex = <_Feature, int>{};

  int currentStep = 0;

  // ── Modal State Setter (QuickSnap toggle modal only) ──
  StateSetter? _activeModalState;

  // ── QuickSnap (toggle only) ──
  bool quickSnapEnabled = true;

  @override
  void initState() {
    super.initState();
    _resolveFeatureIndices();
    _syncQuickClickEnabled();
    WinUtils.setStartUpShortcut(true);
    WinUtils.fixDrawBug();
  }

  @override
  void dispose() {
    pageController.dispose();
    super.dispose();
  }

  // ─────────────────────── FEATURE / HOTKEY REGISTRY ──────────────────────

  /// The tabame function value used to recognise an existing remap entry for a
  /// feature (and the action seeded into a freshly created one).
  String _matchValue(_Feature feature) {
    switch (feature) {
      case _Feature.quickMenu:
        return "ToggleQuickMenu";
      case _Feature.launcher:
        return "OpenLauncher";
      case _Feature.quickClick:
        return "OpenQuickClick";
      case _Feature.fancyshot:
        return "OpenFrozenFancyShot";
      case _Feature.emojiPicker:
        return "OpenEmojiPicker";
      case _Feature.colorPicker:
        return "OpenColorPickerInstant";
    }
  }

  bool _entryHasFunction(Hotkeys hotkey, String value) =>
      hotkey.keymaps.any((KeyMap keyMap) => keyMap.actions.any((KeyAction action) => action.value == value));

  /// Builds the default [Hotkeys] entry seeded the first time the wizard runs.
  /// QuickMenu reuses the rich default bundle (start menu, desktop switching,
  /// volume, …) but starts with no trigger so the user must pick one. The rest
  /// are single-action shortcuts with sensible suggested keys.
  Hotkeys _defaultFor(_Feature feature) {
    switch (feature) {
      case _Feature.quickMenu:
        return Hotkeys.fromMap(mainHotkeyData[0])
          ..key = ""
          ..modifiers = <String>[];
      case _Feature.launcher:
        return _simpleFeature(
            key: "A", modifiers: <String>["WIN", "SHIFT"], name: "Launcher", function: "OpenLauncher");
      case _Feature.quickClick:
        return _simpleFeature(key: "", modifiers: <String>[], name: "QuickClick", function: "OpenQuickClick");
      case _Feature.fancyshot:
        return _fancyshotDefault();
      case _Feature.emojiPicker:
        return _simpleFeature(
            key: "E", modifiers: <String>["WIN", "SHIFT"], name: "EmojiPicker", function: "OpenEmojiPicker");
      case _Feature.colorPicker:
        return _simpleFeature(
            key: "C", modifiers: <String>["WIN", "SHIFT"], name: "Color Picker", function: "OpenColorPickerInstant");
    }
  }

  Hotkeys _simpleFeature({
    required String key,
    required List<String> modifiers,
    required String name,
    required String function,
  }) {
    return Hotkeys(
      key: key,
      modifiers: Hotkeys.normalizeModifiers(modifiers),
      prohibited: <String>[],
      noopScreenBusy: false,
      waitForDoublePress: false,
      keymaps: <KeyMap>[
        KeyMap(
          enabled: true,
          windowUnderMouse: false,
          name: name,
          windowsInfo: <String>["any", ""],
          boundToRegion: false,
          region: Region(),
          triggerType: TriggerType.press,
          triggerInfo: <int>[0, 0, 0],
          actions: <KeyAction>[KeyAction(type: ActionType.tabameFunction, value: function)],
          variableCheck: <String>["", ""],
        ),
      ],
    );
  }

  /// Fancyshot is gesture-driven: a plain press grabs a frozen screenshot, while
  /// holding the trigger and flicking the mouse in a direction picks a different
  /// capture mode (matching the directions shown in the wizard description).
  Hotkeys _fancyshotDefault() {
    KeyMap movement(String name, int direction, String function) {
      return KeyMap(
        enabled: true,
        windowUnderMouse: false,
        name: name,
        windowsInfo: <String>["any", ""],
        boundToRegion: false,
        region: Region(),
        triggerType: TriggerType.movement,
        // [directionIndex, distMin, distMax] — Left=0, Right=1, Up=2, Down=3.
        triggerInfo: <int>[direction, 100, 9999],
        actions: <KeyAction>[KeyAction(type: ActionType.tabameFunction, value: function)],
        variableCheck: <String>["", ""],
      );
    }

    return Hotkeys(
      key: "",
      modifiers: <String>[],
      prohibited: <String>[],
      noopScreenBusy: false,
      waitForDoublePress: false,
      keymaps: <KeyMap>[
        // Just press → Frozen Screen Capture.
        KeyMap(
          enabled: true,
          windowUnderMouse: false,
          name: "Fancyshot",
          windowsInfo: <String>["any", ""],
          boundToRegion: false,
          region: Region(),
          triggerType: TriggerType.press,
          triggerInfo: <int>[0, 0, 0],
          actions: <KeyAction>[KeyAction(type: ActionType.tabameFunction, value: "OpenFrozenFancyShot")],
          variableCheck: <String>["", ""],
        ),
        movement("Live Screen Capture", 0, "OpenLiveFancyShot"), // Hold + move Left
        movement("Screen Recorder", 2, "OpenScreenRecording"), // Hold + move Up
        movement("Screen Draw", 3, "OpenScreenDraw"), // Hold + move Down
        movement("Spotlight", 1, "OpenSpotlight"), // Hold + move Right
      ],
    );
  }

  /// Finds the remap entry for every feature, lazily creating any that are
  /// missing so all hotkeys are registered (and persisted) from the start.
  void _resolveFeatureIndices() {
    bool seeded = false;
    for (final _Feature feature in _Feature.values) {
      final String matchValue = _matchValue(feature);
      int index = remap.indexWhere((Hotkeys hotkey) => _entryHasFunction(hotkey, matchValue));
      if (index == -1) {
        remap.add(_defaultFor(feature));
        index = remap.length - 1;
        seeded = true;
      }
      _featureIndex[feature] = index;
    }
    if (seeded) Boxes.updateSettings("remap", jsonEncode(remap));
  }

  Hotkeys _hotkeyFor(_Feature feature) => remap[_featureIndex[feature]!];

  /// QuickClick has its own enabled flag separate from the trigger hotkey, so
  /// turn it on automatically as soon as the user assigns it a shortcut.
  void _syncQuickClickEnabled() {
    final Hotkeys quickClick = _hotkeyFor(_Feature.quickClick);
    if (quickClick.key.isNotEmpty && !user.quickClickEnabled) {
      user.quickClickEnabled = true;
      Boxes.updateSettings("quickClickEnabled", true);
    }
  }

  /// Re-runs after every [HotKeySettings] interaction: the dialog can delete or
  /// clone entries, so re-resolve indices, auto-enable QuickClick, and rebuild.
  void _onHotkeysChanged() {
    _resolveFeatureIndices();
    _syncQuickClickEnabled();
    if (mounted) setState(() {});
  }

  void _openHotkeySettings(_Feature feature) {
    final int index = _featureIndex[feature]!;
    showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        contentPadding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: SizedBox(
          width: 450,
          height: 700,
          child: HotKeySettings(hotkeyIndex: index, refresh: _onHotkeysChanged),
        ),
      ),
    ).then((_) => _onHotkeysChanged());
  }

  // ─────────────────────────── QUICKSNAP MODAL ──────────────────────────

  void _showFeatureModal(ThemeData theme, Color accent, String title, Widget Function() contentBuilder) {
    showDialog<void>(
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
      if (mounted) setState(() {});
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
            feature: _Feature.quickMenu,
            icon: Icons.rocket_launch_rounded,
            title: "QuickMenu Hotkey",
            subtitle: "Opens QuickMenu right next to your cursor.",
          ),
          const SizedBox(height: 10),

          // ── Launcher ──
          _buildFeatureRow(
            theme,
            accent,
            feature: _Feature.launcher,
            icon: Icons.search_rounded,
            title: "Launcher",
            subtitle: "Full-screen launcher in the center of the screen.",
          ),
          const SizedBox(height: 10),

          // ── QuickClick ──
          _buildFeatureRow(
            theme,
            accent,
            feature: _Feature.quickClick,
            icon: Icons.open_with_rounded,
            title: "QuickClick",
            subtitle: "Move the mouse with the keyboard. Enables itself once set.",
          ),
          const SizedBox(height: 10),

          // ── QuickSnap (toggle, no hotkey) ──
          _buildFeatureRow(
            theme,
            accent,
            icon: Icons.grid_view_rounded,
            title: "QuickSnap",
            subtitle: "Snap windows by dragging then right-clicking.",
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
            feature: _Feature.fancyshot,
            icon: Icons.camera_alt_rounded,
            title: "Fancyshot",
            subtitle: "Screen capture with directional modes.",
          ),
          const SizedBox(height: 10),

          // ── EmojiPicker ──
          _buildFeatureRow(
            theme,
            accent,
            feature: _Feature.emojiPicker,
            icon: Icons.emoji_emotions_rounded,
            title: "EmojiPicker",
            subtitle: "Opens an emoji picker next to your cursor.",
          ),
          const SizedBox(height: 10),

          // ── Color Picker ──
          _buildFeatureRow(
            theme,
            accent,
            feature: _Feature.colorPicker,
            icon: Icons.colorize_rounded,
            title: "Color Picker",
            subtitle: "Pick any color from your screen.",
          ),
        ],
      ),
    );
  }

  /// Feature row. When [feature] is supplied the badge reflects the live remap
  /// entry and tapping opens the shared [HotKeySettings] editor; otherwise it
  /// behaves as a toggle (QuickSnap) driving the supplied [onTap].
  Widget _buildFeatureRow(
    ThemeData theme,
    Color accent, {
    required IconData icon,
    required String title,
    required String subtitle,
    _Feature? feature,
    VoidCallback? onTap,
    bool isToggle = false,
    bool toggleValue = false,
  }) {
    final Hotkeys? hotkey = feature == null ? null : _hotkeyFor(feature);
    final String currentHotkey = hotkey?.key ?? "";
    final bool hasHotkey = currentHotkey.isNotEmpty;

    final String badgeLabel = isToggle
        ? (toggleValue ? "Enabled" : "Disabled")
        : (hasHotkey ? Hotkeys.formatHotkeyLabel(key: currentHotkey, modifiers: hotkey!.modifiers) : "Not set");

    final bool highlight = hasHotkey || (isToggle && toggleValue);

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
          onTap: onTap ?? (feature == null ? null : () => _openHotkeySettings(feature)),
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
                    color: highlight
                        ? accent.withValues(alpha: 0.12)
                        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    badgeLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: highlight ? accent : theme.hintColor,
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
    final Hotkeys quickMenu = _hotkeyFor(_Feature.quickMenu);
    final bool quickMenuSet = quickMenu.key.isNotEmpty;
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
                  quickMenuSet
                      ? "QuickMenu: ${quickMenu.displayHotkey}"
                      : "Set the QuickMenu hotkey to continue.",
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: quickMenuSet ? theme.colorScheme.onSurface : theme.hintColor,
                    fontWeight: quickMenuSet ? FontWeight.w600 : FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (!isFirstStep) const Spacer(),
            FilledButton.icon(
              onPressed: isFirstStep
                  ? (quickMenuSet ? _continueSetup : null)
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
    // Hotkeys are already persisted live through HotKeySettings; just record the
    // install state and move on.
    Boxes.updateSettings("justInstalled", true);
    Boxes.pref.setInt("installDate", DateTime.now().millisecondsSinceEpoch);
    await _goToStep(1);
  }

  Future<void> _finishSetup() async {
    _syncQuickClickEnabled();
    if (kReleaseMode) {
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
