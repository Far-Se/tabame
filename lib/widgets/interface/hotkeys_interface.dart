// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../models/classes/boxes.dart';
import '../../models/classes/hotkeys.dart';
import '../../models/settings.dart';
import '../../models/util/main_hotkey.dart';
import '../widgets/info_text.dart';
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

    return Column(
      children: <Widget>[
        // Enhanced Header Section
        _buildInterfaceHeader(context, colors, texts),

        // Scrollable List of Hotkeys
        remap.isEmpty ? _buildEmptyState(colors, texts) : _buildHotkeyContent(colors, texts),
      ],
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
                label: const Text("ADD HOTKEY"),
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
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
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

  void _editAction(int hotkeyIndex, int actionIndex) {
    showDialog(
      context: context,
      builder: (BuildContext context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
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
                                        : widget.keymap.hotkey.toUpperCase(),
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
        widget.keymap.key.startsWith("MouseButton") ? Icons.mouse_rounded : Icons.keyboard_rounded,
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
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onEdit,
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: _hovered ? widget.accent.withAlpha(12) : widget.onSurface.withAlpha(5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _hovered ? widget.accent.withAlpha(40) : Colors.transparent),
          ),
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
                    child: Icon(Icons.drag_indicator_rounded, size: 16, color: widget.onSurface.withAlpha(80)),
                  ),
                ),
                // Action Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        widget.keyInfo.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: widget.keyInfo.enabled
                              ? (_hovered ? widget.accent : widget.onSurface)
                              : widget.onSurface.withAlpha(120),
                        ),
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
    );
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
              return _buildBadge(a.type.name.splitAndUpcase, HotKeyInfo.actionTypeIcons[a.type]!, colors);
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
