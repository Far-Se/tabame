// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tabamewin32/tabamewin32.dart';

import '../../models/classes/boxes.dart';
import '../../models/classes/hotkeys.dart';
import '../../models/classes/screen_draw_hotkeys.dart';
import '../../models/settings.dart';
import '../../models/util/main_hotkey.dart';
import '../../models/win32/keys.dart';
import '../widgets/custom_tooltip.dart';
import '../widgets/info_text.dart';
import '../widgets/mini_switch.dart';
import '../widgets/text_input.dart';
import 'hotkeys/hotkey_action_editor.dart';
import 'hotkeys/hotkey_settings_dialog.dart';

class HotkeysInterface extends StatefulWidget {
  const HotkeysInterface({super.key});
  @override
  HotkeysInterfaceState createState() => HotkeysInterfaceState();
}

class HotkeysInterfaceState extends State<HotkeysInterface> {
  final List<Hotkeys> remap = Boxes.remap;
  final List<String> mouseButtons = <String>[];
  FocusNode focusNode = FocusNode();

  bool listeningToHotkey = false;
  bool _showScreenDrawHotkeys = false;
  bool _showQuickClickHotkeys = false;

  List<int> unfolded = <int>[];
  @override
  void initState() {
    super.initState();
    bool mouseButton4 = true;
    bool mouseButton5 = true;
    for (Hotkeys hotkey in remap) {
      if (hotkey.key == "MouseButton4") mouseButton4 = false;
      if (hotkey.key == "MouseButton5") mouseButton5 = false;
    }
    if (mouseButton4) mouseButtons.add("MouseButton4");
    if (mouseButton5) mouseButtons.add("MouseButton5");
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme texts = Theme.of(context).textTheme;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: _showScreenDrawHotkeys
          ? KeyedSubtree(
              key: const ValueKey<String>("screen-draw-hotkeys"),
              child: _buildScreenDrawHotkeysSubPage(colors, texts),
            )
          : _showQuickClickHotkeys
              ? KeyedSubtree(
                  key: const ValueKey<String>("quickClick-hotkeys"),
                  child: _buildQuickClickHotkeysSubPage(colors, texts),
                )
              : KeyedSubtree(
                  key: const ValueKey<String>("global-hotkeys"),
                  child: _buildGlobalHotkeysPage(colors, texts),
                ),
    );
  }

  Widget _buildGlobalHotkeysPage(ColorScheme colors, TextTheme texts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildInterfaceHeader(context, colors, texts),
        Row(
          children: <Widget>[
            Expanded(child: _buildScreenDrawHotkeysTile(colors, texts)),
            Expanded(child: _buildQuickClickHotkeysTile(colors, texts)),
          ],
        ),
        Expanded(
          child: remap.isEmpty ? _buildEmptyState(colors, texts) : _buildHotkeyContent(colors, texts),
        ),
      ],
    );
  }

  Widget _buildScreenDrawHotkeysSubPage(ColorScheme colors, TextTheme texts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _HotkeysSubPageHeader(
          title: "Misc Hotkeys",
          subtitle: "Screen Draw and Spotlight runtime bindings",
          icon: Icons.draw_outlined,
          onBack: () => setState(() => _showScreenDrawHotkeys = false),
        ),
        const Expanded(child: ScreenDrawHotkeysPage()),
      ],
    );
  }

  Widget _buildQuickClickHotkeysSubPage(ColorScheme colors, TextTheme texts) {
    // Find or lazily create the QuickClick trigger hotkey entry.
    int quickClickIndex = remap.indexWhere(
      (Hotkeys h) => h.keymaps.isNotEmpty && h.keymaps[0].name == "QuickClick",
    );
    if (quickClickIndex == -1) {
      remap.add(Hotkeys(
        key: "",
        modifiers: <String>[],
        prohibited: <String>[],
        noopScreenBusy: false,
        waitForDoublePress: false,
        keymaps: <KeyMap>[
          KeyMap(
            name: "QuickClick",
            enabled: true,
            boundToRegion: false,
            windowUnderMouse: false,
            region: Region(),
            windowsInfo: <String>["any"],
            triggerInfo: <int>[],
            actions: <KeyAction>[
              KeyAction(type: ActionType.tabameFunction, value: "OpenQuickClick"),
            ],
            triggerType: TriggerType.press,
            variableCheck: <String>["", ""],
          ),
        ],
      ));
      Boxes.updateSettings("remap", jsonEncode(remap));
      quickClickIndex = remap.length - 1;
    }
    final Hotkeys quickClickHotkey = remap[quickClickIndex];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _HotkeysSubPageHeader(
          title: "QuickClick Hotkeys",
          subtitle: "Navigate Windows without a mouse",
          icon: Icons.mouse_outlined,
          onBack: () => setState(() => _showQuickClickHotkeys = false),
        ),
        Expanded(
          child: QuickClickHotkeysPage(
            quickClickHotkey: quickClickHotkey,
            onTapTrigger: () => _openHotkeySettings(quickClickIndex),
          ),
        ),
      ],
    );
  }

  Widget _buildScreenDrawHotkeysTile(ColorScheme colors, TextTheme texts) {
    final Color accent = userSettings.themeColors.accentColor;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: InkWell(
        onTap: _openScreenDrawHotkeys,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: colors.onSurface.withAlpha(8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.onSurface.withAlpha(18)),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent.withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.draw_outlined, size: 18, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      "Misc hotkeys",
                      style: texts.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Screen Draw and Spotlight shortcuts",
                      style: texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 22, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickClickHotkeysTile(ColorScheme colors, TextTheme texts) {
    final Color accent = userSettings.themeColors.accentColor;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: InkWell(
        onTap: _openQuickClickHotkeys,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: colors.onSurface.withAlpha(8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.onSurface.withAlpha(18)),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent.withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.mouse_outlined, size: 18, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      "QuickClick hotkeys",
                      style: texts.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Control mouse cursor using keyboard",
                      style: texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 22, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInterfaceHeader(BuildContext context, ColorScheme colors, TextTheme texts) {
    return Container(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text("GLOBAL HOTKEYS",
                    style: texts.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold, letterSpacing: 1.2, color: colors.primary)),
                const SizedBox(height: 4),
                Text("Manage keyboard shortcuts and workflows that automate your desktop.",
                    style: texts.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
                const SizedBox(height: 12),
                const InfoText("Hotkeys sync after interface restart."),
              ],
            ),
          ),
          Column(
            children: <Widget>[
              FilledButton.icon(
                onPressed: _addNewHotkey,
                icon: const Icon(Icons.add, size: 20),
                label: const Text("ADD HOTKEY", style: TextStyle(fontWeight: FontWeight.bold)),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _restoreDefaultHotkey,
                icon: const Icon(Icons.history, size: 16),
                label: const Text("RESTORE DEFAULT"),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: colors.secondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colors, TextTheme texts) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.keyboard_outlined, size: 64, color: colors.outline.withAlpha(50)),
          const SizedBox(height: 16),
          Text("No hotkeys configured", style: texts.titleMedium?.copyWith(color: colors.onSurfaceVariant)),
          const SizedBox(height: 8),
          Text("Tap 'Add Hotkey' to get started", style: texts.bodySmall?.copyWith(color: colors.outline)),
        ],
      ),
    );
  }

  Widget _buildHotkeyContent(ColorScheme colors, TextTheme texts) {
    return ReorderableListView.builder(
      physics: const ClampingScrollPhysics(),
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: remap.length,
      itemBuilder: (BuildContext context, int index) {
        final Hotkeys keymap = remap[index];
        final bool isUnfolded = unfolded.contains(index);

        return _HotkeyCard(
          key: ValueKey<int>(index),
          index: index,
          keymap: keymap,
          colors: colors,
          texts: texts,
          isExpanded: isUnfolded,
          onToggleExpand: () {
            setState(() {
              if (isUnfolded) {
                unfolded.remove(index);
              } else {
                unfolded.add(index);
              }
            });
          },
          onDeleteHotkey: () => _deleteHotkey(index),
          onOpenSettings: () => _openHotkeySettings(index),
          onAddAction: () => _addAction(index),
          onEditAction: (int actionIndex) => _editAction(index, actionIndex),
          onDeleteAction: (int actionIndex) => _deleteAction(index, actionIndex),
          onReorderActions: (int old, int neu) => _onReorderActions(keymap, old, neu),
        );
      },
      onReorder: (int oldIndex, int newIndex) {
        setState(() {
          if (oldIndex < newIndex) newIndex -= 1;
          final Hotkeys item = remap.removeAt(oldIndex);
          remap.insert(newIndex, item);
          // Update unfolded indices if necessary or just clear them
          unfolded.clear();
        });
        Boxes.updateSettings("remap", jsonEncode(remap));
      },
    );
  }
  // --- Logic Helpers ---

  void _addNewHotkey() {
    remap.add(Hotkeys(
      key: "",
      modifiers: <String>[],
      prohibited: <String>[],
      noopScreenBusy: false,
      waitForDoublePress: false,
      keymaps: <KeyMap>[
        KeyMap(
          name: "Default Shortcut",
          enabled: true,
          boundToRegion: false,
          windowUnderMouse: false,
          region: Region(),
          windowsInfo: <String>["any"],
          triggerInfo: <int>[],
          actions: <KeyAction>[],
          triggerType: TriggerType.press,
          variableCheck: <String>["", ""],
        )
      ],
    ));
    Boxes.updateSettings("remap", jsonEncode(remap));
    setState(() => unfolded.add(remap.length - 1));
    _openHotkeySettings(remap.length - 1);
  }

  void _restoreDefaultHotkey() {
    remap.add(Hotkeys.fromMap(mainHotkeyData[0])
      ..key = "NoKey"
      ..modifiers = <String>[]);
    Boxes.updateSettings("remap", jsonEncode(remap));
    setState(() {});
  }

  void _deleteHotkey(int index) {
    setState(() {
      remap.removeAt(index);
      unfolded.remove(index);
    });
    Boxes.updateSettings("remap", jsonEncode(remap));
  }

  void _openHotkeySettings(int index) {
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        content: SizedBox(
          width: 450,
          height: 700,
          child: HotKeySettings(hotkeyIndex: index, refresh: () => setState(() {})),
        ),
      ),
    );
  }

  void _openScreenDrawHotkeys() {
    setState(() => _showScreenDrawHotkeys = true);
  }

  void _openQuickClickHotkeys() {
    setState(() => _showQuickClickHotkeys = true);
  }

  void _editAction(int hotkeyIndex, int actionIndex) {
    showDialog(
      context: context,
      builder: (BuildContext context) => Dialog(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 850),
        insetPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: HotKeyAction(
          hotkey: remap[hotkeyIndex].keymaps[actionIndex].copyWith(),
          onSaved: (KeyMap updated) {
            remap[hotkeyIndex].keymaps[actionIndex] = updated.copyWith();
            Boxes.updateSettings("remap", jsonEncode(remap));
            setState(() {});
          },
          onCloned: () {
            remap[hotkeyIndex].keymaps.add(remap[hotkeyIndex]
                .keymaps[actionIndex]
                .copyWith(name: "${remap[hotkeyIndex].keymaps[actionIndex].name} Copy"));
            Boxes.updateSettings("remap", jsonEncode(remap));
            setState(() {});
          },
        ),
      ),
    );
  }

  void _addAction(int index) {
    setState(() {
      remap[index].keymaps.add(KeyMap(
            enabled: true,
            windowUnderMouse: false,
            name: "New Action Step",
            windowsInfo: <String>["any"],
            boundToRegion: false,
            region: Region(),
            triggerType: TriggerType.press,
            triggerInfo: <int>[],
            actions: <KeyAction>[],
            variableCheck: <String>["", ""],
          ));
    });
    Boxes.updateSettings("remap", jsonEncode(remap));
    _editAction(index, remap[index].keymaps.length - 1);
  }

  void _deleteAction(int hotkeyIndex, int actionIndex) {
    setState(() => remap[hotkeyIndex].keymaps.removeAt(actionIndex));
    Boxes.updateSettings("remap", jsonEncode(remap));
  }

  void _onReorderActions(Hotkeys keymap, int oldIndex, int newIndex) {
    setState(() {
      if (oldIndex < newIndex) newIndex -= 1;
      final KeyMap item = keymap.keymaps.removeAt(oldIndex);
      keymap.keymaps.insert(newIndex, item);
    });
    Boxes.updateSettings("remap", jsonEncode(remap));
  }
}

// =======================================================================
// Modern Hotkey Card Component
// =======================================================================

class _HotkeyCard extends StatefulWidget {
  const _HotkeyCard({
    required super.key,
    required this.index,
    required this.keymap,
    required this.colors,
    required this.texts,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.onDeleteHotkey,
    required this.onOpenSettings,
    required this.onAddAction,
    required this.onEditAction,
    required this.onDeleteAction,
    required this.onReorderActions,
  });

  final int index;
  final Hotkeys keymap;
  final ColorScheme colors;
  final TextTheme texts;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final VoidCallback onDeleteHotkey;
  final VoidCallback onOpenSettings;
  final VoidCallback onAddAction;
  final void Function(int) onEditAction;
  final void Function(int) onDeleteAction;
  final void Function(int, int) onReorderActions;

  @override
  State<_HotkeyCard> createState() => _HotkeyCardState();
}

class _HotkeyCardState extends State<_HotkeyCard> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final Color accent = widget.colors.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: widget.colors.surface.withAlpha(80),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withAlpha(widget.isExpanded ? 60 : 20), width: 1),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Column(
            children: <Widget>[
              // Header
              Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: widget.onToggleExpand,
                  child: Container(
                    // Header
                    child: MouseRegion(
                      onEnter: (_) => setState(() => _isHovering = true),
                      onExit: (_) => setState(() => _isHovering = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: widget.isExpanded
                              ? accent.withAlpha(15)
                              : (_isHovering ? accent.withAlpha(8) : Colors.transparent),
                          border:
                              Border(bottom: BorderSide(color: accent.withAlpha(widget.isExpanded ? 40 : 0), width: 1)),
                        ),
                        child: Row(
                          children: <Widget>[
                            // Drag Handle
                            ReorderableDragStartListener(
                              index: widget.index,
                              child: Container(
                                padding: const EdgeInsets.only(right: 12.0),
                                child: Icon(Icons.drag_indicator_rounded,
                                    size: 20, color: widget.colors.onSurface.withAlpha(100)),
                              ),
                            ),
                            // Visual Icon
                            _buildHotkeyVisual(),
                            const SizedBox(width: 12),
                            // Trigger Info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    widget.keymap.hotkey.isEmpty
                                        ? "No Trigger Defined"
                                        : widget.keymap.displayHotkey.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                      color: widget.isExpanded ? accent : widget.colors.onSurface,
                                    ),
                                  ),
                                  widget.keymap.keymaps.length == 1
                                      ? Text(
                                          "${widget.keymap.keymaps[0].name}",
                                          style: TextStyle(fontSize: 12, color: widget.colors.onSurface.withAlpha(150)),
                                        )
                                      : Text(
                                          "${widget.keymap.keymaps.length} automated actions",
                                          style: TextStyle(fontSize: 12, color: widget.colors.onSurface.withAlpha(150)),
                                        ),
                                ],
                              ),
                            ),
                            // Quick Actions
                            IconButton(
                              tooltip: "Settings",
                              icon: Icon(Icons.tune_rounded, size: 18, color: widget.colors.onSurface.withAlpha(180)),
                              onPressed: widget.onOpenSettings,
                              splashRadius: 20,
                            ),
                            IconButton(
                              tooltip: "Delete Hotkey",
                              icon: Icon(Icons.delete_outline_rounded,
                                  size: 18, color: widget.colors.error.withAlpha(200)),
                              onPressed: widget.onDeleteHotkey,
                              splashRadius: 20,
                            ),
                            const SizedBox(width: 6),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: accent.withAlpha(30),
                                foregroundColor: accent,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                              ),
                              icon: const Icon(Icons.add_rounded, size: 16),
                              label: const Text("Action", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                              onPressed: widget.onAddAction,
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              widget.isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                              color: widget.colors.onSurface.withAlpha(150),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Actions List
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                child: widget.isExpanded
                    ? Container(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        color: widget.colors.surface.withAlpha(80),
                        child: widget.keymap.keymaps.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Center(
                                  child: Text("No actions defined for this hotkey.",
                                      style: TextStyle(
                                          color: widget.colors.onSurface.withAlpha(100), fontStyle: FontStyle.italic)),
                                ),
                              )
                            : ReorderableListView.builder(
                                shrinkWrap: true,
                                buildDefaultDragHandles: false,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: widget.keymap.keymaps.length,
                                itemBuilder: (BuildContext context, int actionIndex) {
                                  final KeyMap keyInfo = widget.keymap.keymaps[actionIndex];
                                  return _HotkeyActionRow(
                                    key: ValueKey<String>("${widget.index}_$actionIndex"),
                                    index: actionIndex,
                                    keyInfo: keyInfo,
                                    accent: accent,
                                    onSurface: widget.colors.onSurface,
                                    colors: widget.colors,
                                    onEdit: () => widget.onEditAction(actionIndex),
                                    onDelete: () => widget.onDeleteAction(actionIndex),
                                  );
                                },
                                onReorder: widget.onReorderActions,
                              ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHotkeyVisual() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: widget.colors.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        widget.keymap.key.startsWith("MouseButton")
            ? Icons.mouse_rounded
            : (widget.keymap.key == Hotkeys.doubleAltKey || widget.keymap.key == Hotkeys.rightAltKey)
                ? Icons.keyboard_option_key_rounded
                : (widget.keymap.key == Hotkeys.rightControlKey)
                    ? Icons.keyboard_control_key_rounded
                    : Icons.keyboard_rounded,
        color: widget.colors.onPrimaryContainer,
        size: 20,
      ),
    );
  }
}

// =======================================================================
// Individual Hotkey Action Row
// =======================================================================

class _HotkeyActionRow extends StatefulWidget {
  const _HotkeyActionRow({
    required super.key,
    required this.index,
    required this.keyInfo,
    required this.accent,
    required this.onSurface,
    required this.colors,
    required this.onEdit,
    required this.onDelete,
  });

  final int index;
  final KeyMap keyInfo;
  final Color accent;
  final Color onSurface;
  final ColorScheme colors;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_HotkeyActionRow> createState() => _HotkeyActionRowState();
}

class _HotkeyActionRowState extends State<_HotkeyActionRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bool isEnabled = widget.keyInfo.enabled;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onEdit,
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: isEnabled
                ? (_hovered ? userSettings.themeColors.accentColor.withAlpha(12) : widget.onSurface.withAlpha(5))
                : widget.onSurface.withAlpha(2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isEnabled
                  ? (_hovered ? userSettings.themeColors.accentColor.withAlpha(40) : Colors.transparent)
                  : (_hovered ? widget.onSurface.withAlpha(20) : Colors.transparent),
            ),
          ),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: isEnabled ? 1.0 : 0.45,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: <Widget>[
                  // Drag Handle
                  ReorderableDragStartListener(
                    index: widget.index,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
                      color: Colors.transparent,
                      child: Icon(
                        Icons.drag_indicator_rounded,
                        size: 16,
                        color: widget.onSurface.withAlpha(80),
                      ),
                    ),
                  ),
                  // Action Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            if (!isEnabled)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Icon(
                                  Icons.visibility_off_outlined,
                                  size: 14,
                                  color: widget.onSurface.withAlpha(120),
                                ),
                              ),
                            Expanded(
                              child: Text(
                                widget.keyInfo.name + (isEnabled ? "" : " (Disabled)"),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: isEnabled ? FontWeight.w500 : FontWeight.w400,
                                  fontStyle: isEnabled ? FontStyle.normal : FontStyle.italic,
                                  color: isEnabled
                                      ? (_hovered ? userSettings.themeColors.accentColor : widget.onSurface)
                                      : widget.onSurface.withAlpha(150),
                                ),
                              ),
                            ),
                          ],
                        ),
                        _buildActionBadges(widget.keyInfo, widget.colors),
                      ],
                    ),
                  ),
                  // Hover Actions
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: _hovered ? 1.0 : 0.0,
                    child: Row(
                      children: <Widget>[
                        IconButton(
                          tooltip: "Edit Action",
                          icon: Icon(Icons.settings_rounded, size: 16, color: widget.onSurface.withAlpha(200)),
                          onPressed: widget.onEdit,
                          splashRadius: 18,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          padding: EdgeInsets.zero,
                        ),
                        IconButton(
                          tooltip: "Delete Action",
                          icon: Icon(Icons.close_rounded, size: 16, color: widget.colors.error.withAlpha(200)),
                          onPressed: widget.onDelete,
                          splashRadius: 18,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 44),
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _getActionLabel(KeyAction a) {
    switch (a.type) {
      case ActionType.hotkey:
        return "Hotkey: ${a.value}";
      case ActionType.sendKeys:
        return "Keys: ${a.value}";
      case ActionType.tabameFunction:
        return "Func: ${a.value}";
      case ActionType.setVar:
        try {
          final List<dynamic> varInfo = jsonDecode(a.value);
          return "Set: ${varInfo[0]}";
        } catch (_) {
          return "Set: ${a.value}";
        }
      case ActionType.sendClick:
        try {
          final ClickAction click = ClickAction.fromJson(a.value);
          return "Click: (${click.x}, ${click.y})";
        } catch (_) {
          return "Click";
        }
      case ActionType.openQuickMenuPage:
        return "Open: ${a.value}";
      case ActionType.wait:
        return "Wait: ${a.value}ms";
      case ActionType.openLauncherWithPrefix:
        return "Launcher: ${a.value}";
      // ignore: unreachable_switch_default
      default:
        return a.type.name.splitAndUpcase;
    }
  }

  Widget _buildActionBadges(KeyMap keyInfo, ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: <Widget>[
          if (HotKeyInfo.triggerTypeIcons.containsKey(keyInfo.triggerType))
            _buildBadge(
                keyInfo.triggerType.name.splitAndUpcase, HotKeyInfo.triggerTypeIcons[keyInfo.triggerType]!, colors),
          if (keyInfo.windowsInfo.isNotEmpty && keyInfo.windowsInfo[0] != "any")
            _buildBadge("Window Match", Icons.pageview_rounded, colors),
          if (keyInfo.boundToRegion) _buildBadge("Region Only", Icons.location_on_rounded, colors),
          ...keyInfo.actions.map((KeyAction a) {
            if (HotKeyInfo.actionTypeIcons.containsKey(a.type)) {
              return _buildBadge(_getActionLabel(a), HotKeyInfo.actionTypeIcons[a.type]!, colors);
            }
            return const SizedBox();
          }),
        ],
      ),
    );
  }

  Widget _buildBadge(String label, IconData icon, ColorScheme colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration:
          BoxDecoration(color: colors.surfaceContainerHighest.withAlpha(120), borderRadius: BorderRadius.circular(4)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 10, color: colors.secondary),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 9, color: colors.onSurfaceVariant, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _HotkeysSubPageHeader extends StatefulWidget {
  const _HotkeysSubPageHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onBack;

  @override
  State<_HotkeysSubPageHeader> createState() => _HotkeysSubPageHeaderState();
}

class _HotkeysSubPageHeaderState extends State<_HotkeysSubPageHeader> {
  bool _backHovered = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color onSurface = theme.colorScheme.onSurface;
    final Color primary = theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Row(
        children: <Widget>[
          MouseRegion(
            onEnter: (_) => setState(() => _backHovered = true),
            onExit: (_) => setState(() => _backHovered = false),
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: widget.onBack,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _backHovered ? primary.withAlpha(25) : onSurface.withAlpha(10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _backHovered ? primary.withAlpha(76) : onSurface.withAlpha(20)),
                ),
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 16,
                  color: _backHovered ? primary : onSurface.withAlpha(150),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Container(
            height: 24,
            width: 1.5,
            decoration: BoxDecoration(
              color: onSurface.withAlpha(28),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primary.withAlpha(20),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(widget.icon, size: 18, color: primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      "HOTKEYS / ",
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: onSurface.withAlpha(76),
                        letterSpacing: 1,
                      ),
                    ),
                    Text(
                      widget.title.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: primary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  widget.subtitle,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: onSurface.withAlpha(150)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ScreenDrawHotkeysPage extends StatefulWidget {
  const ScreenDrawHotkeysPage({super.key});

  @override
  State<ScreenDrawHotkeysPage> createState() => _ScreenDrawHotkeysPageState();
}

class _ScreenDrawHotkeysPageState extends State<ScreenDrawHotkeysPage> {
  late List<ScreenDrawHotkeyBinding> _bindings;

  @override
  void initState() {
    super.initState();
    _bindings = Boxes.screenDrawHotkeys;
  }

  Future<void> _save() async {
    Boxes.screenDrawHotkeys = _bindings;
    await Boxes.updateSettings(
      "screenDrawHotkeys",
      jsonEncode(_bindings.map((ScreenDrawHotkeyBinding binding) => binding.toMap()).toList()),
    );
  }

  Future<void> _restoreDefaults() async {
    setState(() => _bindings = ScreenDrawHotkeyBinding.defaults());
    await _save();
  }

  void _updateBinding(int index, ScreenDrawHotkeyBinding binding) {
    setState(() => _bindings[index] = binding);
    _save();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme texts = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 36),
      children: <Widget>[
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: colors.onSurface.withAlpha(8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.onSurface.withAlpha(18)),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      "MISC HOTKEYS",
                      style: texts.labelMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Stored separately from global workflow hotkeys. Spotlight shortcuts work only while Spotlight is running.",
                      style: texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: _restoreDefaults,
                icon: const Icon(Icons.history_rounded, size: 16),
                label: const Text("Restore default"),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ...List<Widget>.generate(
          _bindings.length,
          (int index) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ScreenDrawHotkeyRow(
              binding: _bindings[index],
              allBindings: _bindings,
              onChanged: (ScreenDrawHotkeyBinding binding) => _updateBinding(index, binding),
            ),
          ),
        ),
      ],
    );
  }
}

class _ScreenDrawHotkeyRow extends StatefulWidget {
  const _ScreenDrawHotkeyRow({
    required this.binding,
    required this.allBindings,
    required this.onChanged,
  });

  final ScreenDrawHotkeyBinding binding;
  final List<ScreenDrawHotkeyBinding> allBindings;
  final ValueChanged<ScreenDrawHotkeyBinding> onChanged;

  @override
  State<_ScreenDrawHotkeyRow> createState() => _ScreenDrawHotkeyRowState();
}

class _ScreenDrawHotkeyRowState extends State<_ScreenDrawHotkeyRow> {
  final FocusNode _focusNode = FocusNode();
  final Set<String> _pressedModifiers = <String>{};
  bool _listening = false;
  String? _conflictMessage;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  ScreenDrawHotkeyBinding get _binding => widget.binding;

  String get _actionLabel => _binding.action?.label ?? _binding.actionId;

  void _startListening() {
    setState(() {
      _listening = true;
      _pressedModifiers.clear();
      _conflictMessage = null;
    });
    _focusNode.requestFocus();
  }

  KeyEventResult _handleHotkeyKeyEvent(FocusNode node, KeyEvent event) {
    if (!_listening) return KeyEventResult.ignored;

    setState(() {
      _pressedModifiers.clear();
      if (HardwareKeyboard.instance.isControlPressed) _pressedModifiers.add("CTRL");
      if (HardwareKeyboard.instance.isAltPressed) _pressedModifiers.add("ALT");
      if (HardwareKeyboard.instance.isShiftPressed) _pressedModifiers.add("SHIFT");
      if (HardwareKeyboard.instance.isMetaPressed) _pressedModifiers.add("WIN");
    });

    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        setState(() => _listening = false);
        return KeyEventResult.handled;
      }

      if (_isModifier(event.logicalKey)) return KeyEventResult.handled;

      final List<String> modifiers = Hotkeys.normalizeModifiers(_pressedModifiers);
      final ScreenDrawHotkeyBinding updated = ScreenDrawHotkeyBinding(
        actionId: _binding.actionId,
        key: Hotkeys.keyFromLogicalKey(event.logicalKey),
        modifiers: modifiers,
        enabled: _binding.enabled,
      );

      setState(() {
        _listening = false;
        _conflictMessage = _getConflictMessage(updated);
      });
      widget.onChanged(updated);
      FocusScope.of(context).unfocus();
      return KeyEventResult.handled;
    }

    return KeyEventResult.handled;
  }

  bool _isModifier(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight ||
        key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight ||
        key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight;
  }

  String? _getConflictMessage(ScreenDrawHotkeyBinding updated) {
    for (final ScreenDrawHotkeyBinding other in widget.allBindings) {
      if (identical(other, _binding)) continue;
      if (!other.enabled) continue;
      if (other.key == updated.key &&
          Hotkeys.normalizeModifiers(other.modifiers).join("+") == updated.modifiers.join("+")) {
        return other.action?.label ?? other.actionId;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme texts = Theme.of(context).textTheme;
    final Color accent = userSettings.themeColors.accentColor;

    return Container(
      decoration: BoxDecoration(
        color: colors.onSurface.withAlpha(8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.onSurface.withAlpha(18)),
      ),
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: <Widget>[
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: accent.withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    switch (_binding.action) {
                      ScreenDrawHotkeyAction.toggleDrawing => Icons.draw_outlined,
                      ScreenDrawHotkeyAction.closeScreenDraw => Icons.draw_outlined,
                      ScreenDrawHotkeyAction.toggleVisibility => Icons.draw_outlined,
                      _ => Icons.no_flash,
                    },
                    size: 18,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(_actionLabel, style: texts.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(
                        _binding.enabled ? _binding.displayHotkey : "Disabled",
                        style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                MiniToggleSwitch(
                  value: _binding.enabled,
                  onChanged: (bool enabled) {
                    widget.onChanged(ScreenDrawHotkeyBinding(
                      actionId: _binding.actionId,
                      key: _binding.key,
                      modifiers: _binding.modifiers,
                      enabled: enabled,
                    ));
                  },
                ),
                const SizedBox(width: 8),
                Focus(
                  focusNode: _focusNode,
                  onKeyEvent: _handleHotkeyKeyEvent,
                  child: OutlinedButton.icon(
                    onPressed: _startListening,
                    icon: Icon(_listening ? Icons.sensors_rounded : Icons.edit_rounded, size: 16),
                    label: Text(_listening ? "Listening..." : "Set hotkey"),
                  ),
                ),
              ],
            ),
          ),
          if (_listening)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Row(
                children: <Widget>[
                  _modifierChip("CTRL", _pressedModifiers.contains("CTRL")),
                  const SizedBox(width: 6),
                  _modifierChip("ALT", _pressedModifiers.contains("ALT")),
                  const SizedBox(width: 6),
                  _modifierChip("SHIFT", _pressedModifiers.contains("SHIFT")),
                  const SizedBox(width: 6),
                  _modifierChip("WIN", _pressedModifiers.contains("WIN")),
                ],
              ),
            ),
          if (_conflictMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: colors.error.withAlpha(15),
                border: Border(top: BorderSide(color: colors.error.withAlpha(30))),
              ),
              child: Text(
                "Conflict with $_conflictMessage",
                style: texts.labelSmall?.copyWith(color: colors.error, fontWeight: FontWeight.w800),
              ),
            ),
        ],
      ),
    );
  }

  Widget _modifierChip(String label, bool active) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color accent = userSettings.themeColors.accentColor;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(
          color: active ? accent.withAlpha(25) : colors.onSurface.withAlpha(10),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? accent.withAlpha(180) : colors.onSurface.withAlpha(12)),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w900,
            color: active ? accent : colors.onSurfaceVariant.withAlpha(80),
          ),
        ),
      ),
    );
  }
}

class QuickClickHotkeysPage extends StatefulWidget {
  const QuickClickHotkeysPage({
    super.key,
    required this.quickClickHotkey,
    required this.onTapTrigger,
  });

  final Hotkeys quickClickHotkey;
  final VoidCallback onTapTrigger;

  @override
  State<QuickClickHotkeysPage> createState() => _QuickClickHotkeysPageState();
}

class _QuickClickHotkeysPageState extends State<QuickClickHotkeysPage> {
  late QuickClickConfig _config;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _config = userSettings.quickClickConfig;
    _enabled = userSettings.quickClickEnabled;
  }

  Future<void> _save() async {
    userSettings.quickClickConfig = _config;
    userSettings.quickClickEnabled = _enabled;
    await Boxes.updateSettings("quickClickConfig", jsonEncode(_config.toMap()));
    await Boxes.updateSettings("quickClickEnabled", _enabled);

    // if (_enabled) {
    //   await QuickClick.registerQuickClick(_config);
    //   await QuickClick.enableQuickClick();
    // } else {
    //   await QuickClick.disableQuickClick();
    // }
  }

  void _updateConfig(QuickClickConfig config) {
    setState(() => _config = config);
    _save();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme texts = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 36),
      children: <Widget>[
        // Status Card
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: colors.onSurface.withAlpha(8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.onSurface.withAlpha(18)),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      "QUICKCLICK NAVIGATION",
                      style: texts.labelMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Control your mouse cursor using your keyboard. Perfect for when your mouse is out of reach or you prefer staying on the keyboard.",
                      style: texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              MiniToggleSwitch(
                value: _enabled,
                onChanged: (bool value) {
                  setState(() => _enabled = value);
                  _save();
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Trigger Hotkey field ──────────────────────────────────────
        Builder(
          builder: (BuildContext context) {
            final ColorScheme colors2 = Theme.of(context).colorScheme;
            final TextTheme texts2 = Theme.of(context).textTheme;
            final Color accent = userSettings.themeColors.accentColor;
            final Hotkeys qch = widget.quickClickHotkey;
            return Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: InkWell(
                onTap: widget.onTapTrigger,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colors2.onSurface.withAlpha(8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colors2.onSurface.withAlpha(18)),
                  ),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: accent.withAlpha(20),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.keyboard_rounded, size: 18, color: accent),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              "Trigger hotkey",
                              style: texts2.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              qch.hotkey.isEmpty ? "No hotkey set — tap to configure" : qch.displayHotkey.toUpperCase(),
                              style: texts2.bodySmall?.copyWith(
                                color: qch.hotkey.isEmpty ? colors2.onSurfaceVariant.withAlpha(140) : accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.tune_rounded, size: 18, color: colors2.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
            );
          },
        ),

        _buildSectionHeader(texts, colors, "GENERAL SETTINGS"),
        _buildSettingRow(
          "Horizontal Keys",
          "Keys mapped to horizontal grid positions",
          child: CustomTextInput(
            labelText: "",
            value: _config.horizontalKeys,
            onChanged: (String val) =>
                setState(() => _updateConfig(QuickClickConfig.fromMap(_config.toMap()..['horizontalKeys'] = val))),
          ),
        ),
        _buildSettingRow(
          "Vertical Keys",
          "Keys mapped to vertical grid positions",
          child: CustomTextInput(
            labelText: "",
            value: _config.verticalKeys,
            onChanged: (String val) =>
                setState(() => _updateConfig(QuickClickConfig.fromMap(_config.toMap()..['verticalKeys'] = val))),
          ),
        ),
        _buildSettingRow(
          "Nudge Amount",
          "Pixels to move when using arrow keys / Shift + arrow keys",
          child: Row(
            children: <Widget>[
              Expanded(
                child: CustomTextInput(
                  value: _config.nudgeAmount.toString(),
                  labelText: "Normal",
                  onChanged: (String val) {
                    setState(() => _updateConfig(
                        QuickClickConfig.fromMap(_config.toMap()..['nudgeAmount'] = int.tryParse(val) ?? 3)));
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: CustomTextInput(
                  value: _config.shiftNudgeAmount.toString(),
                  labelText: "Shift",
                  onChanged: (String val) {
                    setState(() => _updateConfig(
                        QuickClickConfig.fromMap(_config.toMap()..['shiftNudgeAmount'] = int.tryParse(val) ?? 25)));
                  },
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),
        _buildSectionHeader(texts, colors, "MOUSE ACTIONS"),
        _buildHotkeyRow(
          "Left Click / Select",
          _config.leftClickKey,
          (int vk) => _updateConfig(QuickClickConfig.fromMap(_config.toMap()..['leftClickKey'] = vk)),
        ),
        _buildHotkeyRow(
          "Right Click / Context",
          _config.rightClickKey,
          (int vk) => _updateConfig(QuickClickConfig.fromMap(_config.toMap()..['rightClickKey'] = vk)),
        ),
        _buildHotkeyRow(
          "Drag / Hold",
          _config.dragKey,
          (int vk) => _updateConfig(QuickClickConfig.fromMap(_config.toMap()..['dragKey'] = vk)),
        ),

        _buildHotkeyRow(
          "Escape / Back",
          _config.escapeKey,
          (int vk) => _updateConfig(QuickClickConfig.fromMap(_config.toMap()..['escapeKey'] = vk)),
        ),
        _buildHotkeyRow(
          "Toggle Zone Mode",
          _config.zoneModeKey,
          (int vk) => _updateConfig(QuickClickConfig.fromMap(_config.toMap()..['zoneModeKey'] = vk)),
        ),
        _buildHotkeyRow(
          "Move to Next Monitor",
          _config.nextMonitorKey,
          (int vk) => _updateConfig(QuickClickConfig.fromMap(_config.toMap()..['nextMonitorKey'] = vk)),
        ),
        _buildHotkeyRow(
          "Move to Previous Monitor",
          _config.prevMonitorKey,
          (int vk) => _updateConfig(QuickClickConfig.fromMap(_config.toMap()..['prevMonitorKey'] = vk)),
        ),
        _buildHotkeyRow(
          "Toggle Overlay",
          _config.toggleOverlayKey,
          (int vk) => _updateConfig(QuickClickConfig.fromMap(_config.toMap()..['toggleOverlayKey'] = vk)),
        ),
        _buildHotkeyRow(
          "Show Info",
          _config.infoKey,
          (int vk) => _updateConfig(QuickClickConfig.fromMap(_config.toMap()..['infoKey'] = vk)),
        ),

        const SizedBox(height: 24),
        _buildSectionHeader(texts, colors, "SCROLLING"),
        _buildHotkeyRow(
          "Scroll Up",
          _config.scrollUpKey,
          (int vk) => _updateConfig(QuickClickConfig.fromMap(_config.toMap()..['scrollUpKey'] = vk)),
        ),
        _buildHotkeyRow(
          "Scroll Down",
          _config.scrollDownKey,
          (int vk) => _updateConfig(QuickClickConfig.fromMap(_config.toMap()..['scrollDownKey'] = vk)),
        ),
        _buildHotkeyRow(
          "Scroll Left",
          _config.scrollLeftKey,
          (int vk) => _updateConfig(QuickClickConfig.fromMap(_config.toMap()..['scrollLeftKey'] = vk)),
        ),
        _buildHotkeyRow(
          "Scroll Right",
          _config.scrollRightKey,
          (int vk) => _updateConfig(QuickClickConfig.fromMap(_config.toMap()..['scrollRightKey'] = vk)),
        ),
        _buildSettingRow(
          "Scroll Amount",
          "Wheel delta per scroll action",
          child: CustomTextInput(
            value: _config.scrollDelta.toString(),
            labelText: "",
            onChanged: (String val) =>
                _updateConfig(QuickClickConfig.fromMap(_config.toMap()..['scrollDelta'] = int.tryParse(val) ?? 3)),
          ),
        ),

        const SizedBox(height: 24),
        _buildSectionHeader(texts, colors, "ARROW BINDINGS"),
        _buildArrowBindingRow("Up Arrow", "up", _config.extraArrowBindings),
        _buildArrowBindingRow("Down Arrow", "down", _config.extraArrowBindings),
        _buildArrowBindingRow("Left Arrow", "left", _config.extraArrowBindings),
        _buildArrowBindingRow("Right Arrow", "right", _config.extraArrowBindings),
      ],
    );
  }

  Widget _buildArrowBindingRow(
    String title,
    String direction,
    Map<String, List<int>> extraArrowBindings,
  ) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme texts = Theme.of(context).textTheme;
    final List<int> currentVks = extraArrowBindings[direction] ?? <int>[];
    final int currentVk = currentVks.isNotEmpty ? currentVks[0] : 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.onSurface.withAlpha(8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.onSurface.withAlpha(18)),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: texts.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                    currentVk == 0 ? "Not set" : WinKeys.vk(currentVk).replaceAll("VK_", ""),
                    style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            _QuickClickHotkeySelector(
              currentVk: currentVk,
              onChanged: (int vk) {
                final Map<String, List<int>> updated = Map<String, List<int>>.from(extraArrowBindings)
                  ..[direction] = vk == 0 ? <int>[] : <int>[vk];
                _updateConfig(QuickClickConfig.fromMap(_config.toMap()..['extraArrowBindings'] = updated));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(TextTheme texts, ColorScheme colors, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(
        title,
        style: texts.labelSmall?.copyWith(
          fontWeight: FontWeight.w900,
          color: colors.onSurface.withAlpha(120),
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildSettingRow(String title, String subtitle, {required Widget child}) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme texts = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.onSurface.withAlpha(8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.onSurface.withAlpha(18)),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: texts.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(width: 200, child: child),
          ],
        ),
      ),
    );
  }

  Widget _buildHotkeyRow(String title, int currentVk, ValueChanged<int> onChanged) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme texts = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.onSurface.withAlpha(8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.onSurface.withAlpha(18)),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: texts.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                    WinKeys.vk(currentVk).replaceAll("VK_", ""),
                    style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            _QuickClickHotkeySelector(
              currentVk: currentVk,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickClickHotkeySelector extends StatefulWidget {
  const _QuickClickHotkeySelector({required this.currentVk, required this.onChanged});
  final int currentVk;
  final ValueChanged<int> onChanged;

  @override
  State<_QuickClickHotkeySelector> createState() => _QuickClickHotkeySelectorState();
}

class _QuickClickHotkeySelectorState extends State<_QuickClickHotkeySelector> {
  bool _listening = false;
  final FocusNode _focusNode = FocusNode();

  // Sorted, deduplicated display names (VK_ stripped)
  static final List<String> _keyNames = () {
    final Map<int, String> seen = <int, String>{};
    for (final MapEntry<String, int> e in keyMap.entries) {
      // Keep the first (shortest / canonical) name per VK value
      if (!seen.containsKey(e.value)) {
        seen[e.value] = e.key.replaceFirst('VK_', '');
      }
    }
    final List<String> names = seen.values.toList()..sort();
    return names;
  }();

  static int _nameToVk(String name) =>
      keyMap['VK_$name'] ??
      keyMap.entries
          .firstWhere((MapEntry<String, int> e) => e.key.replaceFirst('VK_', '') == name,
              orElse: () => const MapEntry<String, int>('', 0))
          .value;

  void _startListening() {
    setState(() => _listening = true);
    _focusNode.requestFocus();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (!_listening) return KeyEventResult.ignored;

    if (event is KeyDownEvent) {
      print(event.logicalKey);
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        setState(() => _listening = false);
        return KeyEventResult.handled;
      }

      int? vk;

      // Explicitly handle modifiers as they often have labels like "Control Left"
      if (event.logicalKey == LogicalKeyboardKey.controlLeft ||
          event.logicalKey == LogicalKeyboardKey.controlRight ||
          event.logicalKey == LogicalKeyboardKey.control) {
        vk = 0x11; // VK_CONTROL
      } else if (event.logicalKey == LogicalKeyboardKey.altLeft ||
          event.logicalKey == LogicalKeyboardKey.altRight ||
          event.logicalKey == LogicalKeyboardKey.alt) {
        vk = 0x12; // VK_MENU (ALT)
      } else if (event.logicalKey == LogicalKeyboardKey.shiftLeft ||
          event.logicalKey == LogicalKeyboardKey.shiftRight ||
          event.logicalKey == LogicalKeyboardKey.shift) {
        vk = 0x10; // VK_SHIFT
      } else {
        final String label = event.logicalKey.keyLabel.toUpperCase().replaceAll(" ", "");

        // Try exact match in keyMap
        vk = keyMap["VK_$label"];

        // Try some common replacements if not found
        if (vk == null) {
          if (label == "CONTROL") vk = 0x11;
          if (label == "ALT") vk = 0x12;
          if (label == "SHIFT") vk = 0x10;
          if (label == "[") vk = 0xDB;
          if (label == "]") vk = 0xDD;
          if (label == ";") vk = 0xBA;
          if (label == "'") vk = 0xDE;
          if (label == "\"") vk = 0xDE;
          if (label == "=") vk = 0xBB;
        }
      }

      if (vk != null) {
        widget.onChanged(vk);
        setState(() => _listening = false);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    // Current display name (stripped of VK_), or null if 0 / unset
    final String? currentName = widget.currentVk == 0 ? null : WinKeys.vk(widget.currentVk).replaceFirst('VK_', '');

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // ── Dropdown picker ───────────────────────────────────────────
        DropdownButton<String>(
          value: _keyNames.contains(currentName) ? currentName : null,
          hint: const Text("—", style: TextStyle(fontSize: 13)),
          isDense: true,
          underline: const SizedBox.shrink(),
          items: <DropdownMenuItem<String>>[
            const DropdownMenuItem<String>(
              value: null,
              child: Text("(none)", style: TextStyle(fontSize: 13)),
            ),
            ..._keyNames.map(
              (String name) => DropdownMenuItem<String>(
                value: name,
                child: Text(name, style: const TextStyle(fontSize: 13)),
              ),
            ),
          ],
          onChanged: (String? name) {
            if (name == null) {
              widget.onChanged(0);
            } else {
              widget.onChanged(_nameToVk(name));
            }
          },
        ),
        const SizedBox(width: 8),
        // ── Press-to-set button ───────────────────────────────────────
        Focus(
          focusNode: _focusNode,
          onKeyEvent: _handleKey,
          child: IconButton(
            onPressed: _startListening,
            icon: CustomTooltip(
              message: _listening ? "Listening..." : "Set key",
              child: Icon(
                Icons.sensors_rounded,
                size: 16,
                color: _listening ? userSettings.themeColors.accentColor : userSettings.themeColors.textColor,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
