import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' hide TextInput;

import '../../../models/classes/hotkeys.dart';
import '../../../models/settings.dart';
import '../../widgets/checkbox_widget.dart';
import '../../widgets/custom_tooltip.dart';
import '../../widgets/mini_switch.dart';
import '../../widgets/modern_dropdown.dart';
import '../../widgets/mouse_scroll_widget.dart';
import '../../widgets/text_input.dart';
import '../../widgets/windows_scroll.dart';
import 'mouse_info_panel.dart';

class HotKeyAction extends StatefulWidget {
  final KeyMap hotkey;
  final void Function(KeyMap hotkey) onSaved;
  final void Function() onCloned;
  const HotKeyAction({
    super.key,
    required this.hotkey,
    required this.onSaved,
    required this.onCloned,
  });
  @override
  HotKeyActionState createState() => HotKeyActionState();
}

class HotKeyActionState extends State<HotKeyAction> {
  FocusNode focusNode = FocusNode();
  bool variableCheck = false;
  bool _showUtilities = true;

  @override
  void initState() {
    variableCheck = widget.hotkey.variableCheck[0].isNotEmpty;
    super.initState();
  }

  @override
  void dispose() {
    focusNode.dispose();
    super.dispose();
  }

  String _generateDynamicFallbackName() {
    String actionDescription = "Empty Action";

    if (widget.hotkey.actions.isNotEmpty) {
      final KeyAction firstAction = widget.hotkey.actions.first;
      final String typeName = firstAction.type.name.splitAndUpcase;

      // Customize context based on what the action actually is
      if (firstAction.type == ActionType.hotkey) {
        actionDescription = "$typeName: ${firstAction.value.toUpperCase()}";
      } else if (firstAction.type == ActionType.sendClick && firstAction.value.isNotEmpty) {
        try {
          final ClickAction click = ClickAction.fromJson(firstAction.value);
          actionDescription = "$typeName: ${click.x}, ${click.y}";
        } catch (_) {
          actionDescription = typeName;
        }
      } else if (firstAction.value.isNotEmpty) {
        // General fallback for simple text/string parameters
        actionDescription = "$typeName: ${firstAction.value}";
      } else {
        actionDescription = typeName;
      }
    }

    // Grab the trigger mechanism string
    final String triggerMechanism = HotKeyInfo.triggers[widget.hotkey.triggerType.index];

    return "$actionDescription Via $triggerMechanism";
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 850),
        child: Material(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.12), width: 1.5),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: <Widget>[
                // Main Configuration Area
                Expanded(
                  child: Column(
                    children: <Widget>[
                      // Pinned Header
                      _buildPinnedHeader(colorScheme, textTheme),

                      // Scrollable Content
                      Expanded(
                        child: WindowsScrollView(
                          scrollDirection: Axis.vertical,
                          friction: 0.76,
                          scrollSpeed: 12,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                // Section 1: Conditions
                                _buildSectionHeader("CONDITIONS", Icons.radar_rounded, colorScheme, textTheme),
                                const SizedBox(height: 12),
                                _buildContextCard(colorScheme),
                                const SizedBox(height: 32),

                                // Section 2: Execution Logic
                                _buildSectionHeader(
                                    "EXECUTION LOGIC", Icons.auto_awesome_motion_rounded, colorScheme, textTheme),
                                const SizedBox(height: 12),
                                _buildTriggerRulesCard(colorScheme),
                                const SizedBox(height: 32),

                                // Section 3: Action Sequence
                                _buildSectionHeader(
                                    "ACTION SEQUENCE", Icons.account_tree_rounded, colorScheme, textTheme),
                                const SizedBox(height: 12),
                                _buildActionsTimeline(colorScheme, textTheme),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Persistent Footer
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLowest.withValues(alpha: 0.5),
                          border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.12))),
                        ),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () {
                                  // Validate name criteria: change if empty or matches "Default Shortcut"
                                  final String trimmedName = widget.hotkey.name.trim();
                                  if (trimmedName.isEmpty || trimmedName.toLowerCase() == "default shortcut") {
                                    widget.hotkey.name = _generateDynamicFallbackName();
                                  }

                                  widget.onSaved(widget.hotkey);
                                  Navigator.of(context).pop();
                                },
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(double.infinity, 48),
                                  backgroundColor: colorScheme.primary,
                                  foregroundColor: colorScheme.onPrimary,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  elevation: 0,
                                ),
                                icon: const Icon(Icons.check_circle_rounded, size: 18),
                                label: const Text("APPLY CHANGES",
                                    style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.1, fontSize: 13)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Utility Sidebar (Collapsible)
                if (_showUtilities) ...<Widget>[
                  Container(
                    width: 280,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLow,
                      border: Border(left: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.12))),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 22, 12, 18),
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text("UTILITIES",
                                        style: textTheme.labelLarge?.copyWith(
                                          color: colorScheme.primary,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 1.5,
                                          fontSize: Design.baseFontSize,
                                        )),
                                    Text("Developer tools",
                                        style: textTheme.labelSmall?.copyWith(
                                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                                          fontSize: 9,
                                        )),
                                  ],
                                ),
                              ),
                              _HotKeyHeaderButton(
                                tooltip: "Hide Utilities",
                                onPressed: () => setState(() => _showUtilities = false),
                                icon: Icons.close_fullscreen_rounded,
                              ),
                            ],
                          ),
                        ),
                        Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.08)),
                        Expanded(
                          child: MouseScrollWidget(
                            child: MouseInfoWidget(
                              onAnchorTypeChanged: (AnchorType anchor) => setState(() {}),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: OutlinedButton.icon(
                            onPressed: () {
                              widget.onCloned();
                              Navigator.of(context).pop();
                            },
                            icon: const Icon(Icons.copy_all_rounded, size: 16),
                            label: const Text("CLONE CONFIG"),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 44),
                              side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.2)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
    );
  }

  Widget _buildPinnedHeader(ColorScheme colors, TextTheme texts) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.12))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          InkWell(
            onTap: () => setState(() => widget.hotkey.enabled = !widget.hotkey.enabled),
            borderRadius: BorderRadius.circular(20),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: widget.hotkey.enabled ? colors.primary.withValues(alpha: 0.1) : colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: widget.hotkey.enabled ? colors.primary.withValues(alpha: 0.2) : Colors.transparent),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: widget.hotkey.enabled ? colors.primary : colors.onSurfaceVariant.withValues(alpha: 0.4),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.hotkey.enabled ? "LIVE" : "BYPASS",
                      style: texts.labelSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        fontSize: 9,
                        letterSpacing: 1.0,
                        color: widget.hotkey.enabled ? colors.primary : colors.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 20),
          // Name Input - Technical
          Expanded(
            child: CustomTextInput(
              labelText: "ACTION NAME",
              value: widget.hotkey.name,
              onChanged: (String e) => setState(() => widget.hotkey.name = e),
            ),
          ),
          const SizedBox(width: 16),
          if (!_showUtilities)
            _HotKeyHeaderButton(
              tooltip: "Mouse Utilities",
              onPressed: () => setState(() => _showUtilities = !_showUtilities),
              icon: _showUtilities ? Icons.visibility_off_rounded : Icons.mouse_rounded,
              isActive: _showUtilities,
            ),
          const SizedBox(width: 4),
          _HotKeyHeaderButton(
            tooltip: "Close Editor",
            onPressed: () => Navigator.of(context).pop(),
            icon: Icons.close_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, ColorScheme colors, TextTheme texts) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 14, color: colors.primary.withValues(alpha: 0.5)),
          const SizedBox(width: 8),
          Text(
            title.toUpperCase(),
            style: texts.labelLarge?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
              fontSize: Design.baseFontSize,
              color: colors.primary.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Divider(color: colors.outlineVariant.withValues(alpha: 0.08))),
        ],
      ),
    );
  }

  Widget _buildContextCard(ColorScheme colors) {
    return _buildCompactCard(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildActionItem(
            icon: Icons.mouse_rounded,
            title: "Focus Mouse",
            subtitle: "Activate window under cursor",
            trailing: MiniToggleSwitch(
              value: widget.hotkey.windowUnderMouse,
              onChanged: (bool e) => setState(() => widget.hotkey.windowUnderMouse = e),
            ),
          ),
          const Divider(height: 32),
          _buildTargetWindowSelector(colors),
          const SizedBox(height: 20),
          _buildRegionSettings(colors),
        ],
      ),
    );
  }

  Widget _buildTriggerRulesCard(ColorScheme colors) {
    return _buildCompactCard(
      colors: colors,
      child: Column(
        children: <Widget>[
          _buildVariableCheck(colors),
          const Divider(height: 32),
          _buildTriggerTypeSelector(colors),
        ],
      ),
    );
  }

  Widget _buildCompactCard({required Widget child, required ColorScheme colors}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.1)),
      ),
      child: child,
    );
  }

  Widget _buildActionsTimeline(ColorScheme colors, TextTheme texts) {
    return Column(
      children: <Widget>[
        if (widget.hotkey.actions.isEmpty)
          _buildEmptySteps(colors)
        else
          ...List<Widget>.generate(widget.hotkey.actions.length, (int index) {
            final KeyAction action = widget.hotkey.actions[index];
            return Column(
              key: ValueKey<KeyAction>(action),
              children: <Widget>[
                _ActionStepCard(
                  index: index,
                  action: action,
                  onDelete: () => setState(() => widget.hotkey.actions.removeAt(index)),
                  onChanged: () => setState(() {}),
                ),
                if (index < widget.hotkey.actions.length - 1)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Container(height: 12, width: 1.5, color: colors.primary.withValues(alpha: 0.1)),
                  ),
              ],
            );
          }),
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: () =>
              setState(() => widget.hotkey.actions.add(KeyAction(type: ActionType.hotkey, value: "ALT+SHIFT+F"))),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text("ADD ACTION STEP"),
          style: TextButton.styleFrom(
            minimumSize: const Size(double.infinity, 44),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            foregroundColor: colors.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptySteps(ColorScheme colors) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.info_outline_rounded, color: colors.primary.withValues(alpha: 0.4), size: 16),
          const SizedBox(width: 8),
          Text("No actions defined yet",
              style:
                  TextStyle(color: colors.onSurfaceVariant.withValues(alpha: 0.7), fontSize: Design.baseFontSize + 2)),
        ],
      ),
    );
  }

  Widget _buildLabel(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }

  Widget _buildTargetWindowSelector(ColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ModernDropdown<String>(
          labelText: "Target Window",
          value: widget.hotkey.windowsInfo[0],
          prefixIcon: const Icon(Icons.window_rounded, size: 20),
          onChanged: (String? newValue) => setState(() => widget.hotkey.windowsInfo = <String>[newValue ?? "any", ""]),
          items: HotKeyInfo.windowInfoNames.entries.map((MapEntry<String, String> entry) {
            return ModernDropdownItem<String>(
              value: entry.key,
              label: entry.value,
            );
          }).toList(),
        ),
        if (HotKeyInfo.windowInfo.indexOf(widget.hotkey.windowsInfo[0]) > 0)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: TextField(
              onChanged: (String e) => widget.hotkey.windowsInfo[1] = e,
              controller: TextEditingController(text: widget.hotkey.windowsInfo[1]),
              decoration: const InputDecoration(
                hintText: "Regex pattern...",
                labelText: "Window Match Pattern",
                prefixIcon: Icon(Icons.search, size: 20),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRegionSettings(ColorScheme colors) {
    return Column(
      children: <Widget>[
        _buildActionItem(
          icon: Icons.fullscreen_exit_rounded,
          title: "Screen Region",
          subtitle: "Restrict hotkey to area",
          trailing: MiniToggleSwitch(
            onChanged: (bool e) => setState(() => widget.hotkey.boundToRegion = !widget.hotkey.boundToRegion),
            value: widget.hotkey.boundToRegion,
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.fastOutSlowIn,
          child: widget.hotkey.boundToRegion
              ? Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Column(
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: ModernDropdown<String>(
                              labelText: "Anchor Point",
                              value: widget.hotkey.region.anchorType.name,
                              onChanged: (String? newValue) => setState(() => widget.hotkey.region.anchorType =
                                  AnchorType.values.firstWhere((AnchorType element) => element.name == newValue)),
                              items: AnchorType.values.map((AnchorType v) {
                                return ModernDropdownItem<String>(
                                  value: v.name,
                                  label: v.name,
                                );
                              }).toList(),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Column(
                            children: <Widget>[
                              _buildLabel(context, "Unit"),
                              CheckBoxWidget(
                                key: UniqueKey(),
                                onChanged: (bool e) => setState(
                                    () => widget.hotkey.region.asPercentage = !widget.hotkey.region.asPercentage),
                                value: widget.hotkey.region.asPercentage,
                                text: "% Pos",
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: <Widget>[
                          Expanded(
                              child: CustomTextInput(
                                  labelText: "X1",
                                  value: widget.hotkey.region.x1.toString(),
                                  keyboardType: TextInputType.number,
                                  onChanged: (String e) =>
                                      setState(() => widget.hotkey.region.x1 = int.tryParse(e) ?? 0))),
                          const SizedBox(width: 8),
                          Expanded(
                              child: CustomTextInput(
                                  labelText: "Y1",
                                  value: widget.hotkey.region.y1.toString(),
                                  keyboardType: TextInputType.number,
                                  onChanged: (String e) =>
                                      setState(() => widget.hotkey.region.y1 = int.tryParse(e) ?? 0))),
                          const SizedBox(width: 8),
                          Expanded(
                              child: CustomTextInput(
                                  labelText: "X2",
                                  value: widget.hotkey.region.x2.toString(),
                                  keyboardType: TextInputType.number,
                                  onChanged: (String e) =>
                                      setState(() => widget.hotkey.region.x2 = int.tryParse(e) ?? 0))),
                          const SizedBox(width: 8),
                          Expanded(
                              child: CustomTextInput(
                                  labelText: "Y2",
                                  value: widget.hotkey.region.y2.toString(),
                                  keyboardType: TextInputType.number,
                                  onChanged: (String e) =>
                                      setState(() => widget.hotkey.region.y2 = int.tryParse(e) ?? 0))),
                        ],
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildVariableCheck(ColorScheme colors) {
    return Column(
      children: <Widget>[
        _buildActionItem(
          icon: Icons.tune_rounded,
          title: "Variable Dependency",
          subtitle: "Trigger if variable matches",
          trailing: MiniToggleSwitch(
            onChanged: (bool e) => setState(() => variableCheck = e),
            value: variableCheck,
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.fastOutSlowIn,
          child: variableCheck
              ? Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                          child: CustomTextInput(
                              labelText: "Var Name",
                              value: widget.hotkey.variableCheck[0],
                              onChanged: (String e) => widget.hotkey.variableCheck[0] = e)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: CustomTextInput(
                              labelText: "Target Value",
                              value: widget.hotkey.variableCheck[1],
                              onChanged: (String e) => widget.hotkey.variableCheck[1] = e)),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildTriggerTypeSelector(ColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ModernDropdown<String>(
          labelText: "Trigger Mechanism",
          value: HotKeyInfo.triggers[widget.hotkey.triggerType.index],
          prefixIcon: const Icon(Icons.bolt_rounded, size: 20),
          onChanged: (String? n) => setState(() {
            widget.hotkey.triggerType = TriggerType.values[HotKeyInfo.triggers.indexOf(n ?? "Press")];
            widget.hotkey.triggerInfo = <int>[0, 0, 0];
          }),
          items: HotKeyInfo.triggers.map((String v) {
            return ModernDropdownItem<String>(
              value: v,
              label: v,
            );
          }).toList(),
        ),
        if (widget.hotkey.triggerType == TriggerType.duration)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Row(
              children: <Widget>[
                Expanded(
                    child: CustomTextInput(
                        labelText: "Min Delay (ms)",
                        value: widget.hotkey.triggerInfo[0].toString(),
                        keyboardType: TextInputType.number,
                        onChanged: (String e) => setState(() => widget.hotkey.triggerInfo[0] = int.tryParse(e) ?? 0))),
                const SizedBox(width: 12),
                Expanded(
                    child: CustomTextInput(
                        labelText: "Max Duration (ms)",
                        value: widget.hotkey.triggerInfo[1].toString(),
                        keyboardType: TextInputType.number,
                        onChanged: (String e) => setState(() => widget.hotkey.triggerInfo[1] = int.tryParse(e) ?? 0))),
              ],
            ),
          ),
        if (widget.hotkey.triggerType == TriggerType.movement)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Column(
              children: <Widget>[
                ModernDropdown<String>(
                  labelText: "Motion Direction",
                  value: HotKeyInfo.mouseDirections[widget.hotkey.triggerInfo[0]],
                  onChanged: (String? n) =>
                      setState(() => widget.hotkey.triggerInfo[0] = HotKeyInfo.mouseDirections.indexOf(n ?? "Right")),
                  items: HotKeyInfo.mouseDirections.map((String v) {
                    return ModernDropdownItem<String>(
                      value: v,
                      label: v,
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                _buildActionItem(
                  icon: Icons.gesture_rounded,
                  title: "Real-time Tracking",
                  subtitle: "Execute continuously on movement",
                  trailing: MiniToggleSwitch(
                    onChanged: (bool e) => setState(() => widget.hotkey.triggerInfo[2] = e ? -1 : 0),
                    value: widget.hotkey.triggerInfo[2] == -1,
                  ),
                ),
                const SizedBox(height: 16),
                if (widget.hotkey.triggerInfo[2] != -1)
                  Row(
                    children: <Widget>[
                      Expanded(
                          child: CustomTextInput(
                              labelText: "Min Distance (px)",
                              value: widget.hotkey.triggerInfo[1].toString(),
                              keyboardType: TextInputType.number,
                              onChanged: (String e) =>
                                  setState(() => widget.hotkey.triggerInfo[1] = int.tryParse(e) ?? 0))),
                      const SizedBox(width: 12),
                      Expanded(
                          child: CustomTextInput(
                              labelText: "Max Threshold (px)",
                              value: widget.hotkey.triggerInfo[2].toString(),
                              keyboardType: TextInputType.number,
                              onChanged: (String e) =>
                                  setState(() => widget.hotkey.triggerInfo[2] = int.tryParse(e) ?? 0))),
                    ],
                  )
                else
                  CustomTextInput(
                      labelText: "Target Distance (px)",
                      value: widget.hotkey.triggerInfo[1].toString(),
                      keyboardType: TextInputType.number,
                      onChanged: (String e) => setState(() => widget.hotkey.triggerInfo[1] = int.tryParse(e) ?? 0)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildActionContent(KeyAction action, ColorScheme colors) {
    if (action.type == ActionType.sendClick) {
      final ClickAction click = action.value.isNotEmpty
          ? ClickAction.fromJson(action.value)
          : ClickAction(anchorType: AnchorType.topLeft, currentWindow: true, x: 50, y: 50);
      return Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: ModernDropdown<String>(
                  labelText: "Anchor",
                  value: click.anchorType.name,
                  onChanged: (String? n) => setState(() {
                    click.anchorType = AnchorType.values.firstWhere((AnchorType e) => e.name == n);
                    action.value = click.toJson();
                  }),
                  items: AnchorType.values.map((AnchorType v) {
                    return ModernDropdownItem<String>(
                      value: v.name,
                      label: v.name,
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(width: 16),
              _buildActionItem(
                icon: Icons.window_rounded,
                title: "Active Only",
                subtitle: "",
                trailing: MiniToggleSwitch(
                    value: click.currentWindow,
                    onChanged: (bool v) {
                      click.currentWindow = v;
                      action.value = click.toJson();
                      setState(() {});
                    }),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                  child: CustomTextInput(
                      labelText: "X offset",
                      value: click.x.toString(),
                      keyboardType: TextInputType.number,
                      onChanged: (String v) {
                        click.x = int.tryParse(v) ?? 0;
                        action.value = click.toJson();
                      })),
              const SizedBox(width: 8),
              Expanded(
                  child: CustomTextInput(
                      labelText: "Y offset",
                      value: click.y.toString(),
                      keyboardType: TextInputType.number,
                      onChanged: (String v) {
                        click.y = int.tryParse(v) ?? 0;
                        action.value = click.toJson();
                      })),
            ],
          ),
        ],
      );
    }
    if (action.type == ActionType.setVar) {
      final List<dynamic> varInfo = action.value.isNotEmpty ? jsonDecode(action.value) : <dynamic>["var", "value"];
      return Row(
        children: <Widget>[
          Expanded(
              child: CustomTextInput(
                  labelText: "Variable",
                  value: varInfo[0],
                  onChanged: (String e) {
                    varInfo[0] = e;
                    action.value = jsonEncode(varInfo);
                  })),
          const SizedBox(width: 12),
          Expanded(
              child: CustomTextInput(
                  labelText: "New Value",
                  value: varInfo[1],
                  onChanged: (String e) {
                    varInfo[1] = e;
                    action.value = jsonEncode(varInfo);
                  })),
        ],
      );
    }
    if (action.type == ActionType.hotkey) {
      return Focus(
        onFocusChange: (bool focused) => setState(() {}),
        onKeyEvent: (FocusNode f, KeyEvent k) {
          if (k is KeyDownEvent && k.logicalKey.keyId < 0x100000000) {
            List<String> mods = <String>[];
            if (HardwareKeyboard.instance.isControlPressed) mods.add("CTRL");
            if (HardwareKeyboard.instance.isAltPressed) mods.add("ALT");
            if (HardwareKeyboard.instance.isShiftPressed) mods.add("SHIFT");
            if (HardwareKeyboard.instance.isMetaPressed) mods.add("WIN");
            if (mods.isNotEmpty) {
              action.value = "${mods.join("+")}+${k.logicalKey.keyLabel.toUpperCase()}";
              f.unfocus();
              setState(() {});
            }
          }
          return KeyEventResult.handled;
        },
        child: Builder(builder: (BuildContext context) {
          final bool isFocused = Focus.of(context).hasFocus;
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            tileColor: isFocused ? colors.primary.withValues(alpha: 0.15) : colors.primary.withAlpha(10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: isFocused ? colors.primary.withValues(alpha: 0.5) : Colors.transparent,
                width: 1.5,
              ),
            ),
            title: Row(
              children: <Widget>[
                Icon(
                  isFocused ? Icons.radio_button_checked_rounded : Icons.keyboard_rounded,
                  size: 18,
                  color: isFocused ? colors.error : colors.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  "KEY SEQUENCE:  ${action.value.toUpperCase()}",
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                    color: isFocused ? colors.primary : colors.onSurface,
                  ),
                ),
              ],
            ),
            subtitle: Text(
              isFocused ? "LISTENING FOR INPUT... PRESS KEYS" : "Click to record sequence...",
              style: TextStyle(
                fontSize: Design.baseFontSize,
                fontWeight: isFocused ? FontWeight.bold : FontWeight.normal,
                color: isFocused ? colors.error : colors.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
            onTap: () {
              if (isFocused) {
                Focus.of(context).unfocus();
              } else {
                Focus.of(context).requestFocus();
              }
            },
          );
        }),
      );
    } else if (action.type == ActionType.tabameFunction) {
      return ModernDropdown<String>(
        value: HotKeyInfo.tabameFunctions.contains(action.value) ? action.value : HotKeyInfo.tabameFunctions[0],
        onChanged: (String? newValue) => setState(() => action.value = newValue ?? HotKeyInfo.tabameFunctions[0]),
        items: HotKeyInfo.tabameFunctions
            .map((String v) => ModernDropdownItem<String>(value: v, label: v.splitAndUpcase))
            .toList(),
      );
    } else if (action.type == ActionType.openQuickMenuPage) {
      return Material(
        type: MaterialType.transparency,
        child: ModernDropdown<String>(
          value: HotKeyInfo.quickMenuPopups.contains(action.value) ? action.value : HotKeyInfo.quickMenuPopups[0],
          onChanged: (String? newValue) => setState(() => action.value = newValue ?? HotKeyInfo.quickMenuPopups[0]),
          items: HotKeyInfo.quickMenuPopups.map((String v) => ModernDropdownItem<String>(value: v, label: v)).toList(),
        ),
      );
    } else if (action.type == ActionType.wait) {
      return CustomTextInput(
        labelText: "Wait (ms)",
        value: action.value,
        onChanged: (String v) => action.value = v,
        keyboardType: TextInputType.number,
      );
    } else if (action.type == ActionType.openLauncherWithPrefix) {
      return CustomTextInput(
        labelText: "Pretext",
        value: action.value,
        onChanged: (String v) => action.value = v,
      );
    }
    return CustomTextInput(
        labelText: "Parameter / Path / Command", value: action.value, onChanged: (String v) => action.value = v);
  }

  Widget _buildActionItem({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
  }) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme texts = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 16, color: colors.primary.withValues(alpha: 0.8)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: texts.bodyMedium?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.2)),
                if (subtitle != null && subtitle.isNotEmpty)
                  Text(subtitle,
                      style: texts.labelSmall
                          ?.copyWith(color: colors.onSurfaceVariant.withValues(alpha: 0.5), height: 1.2)),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }
}

class _HotKeyHeaderButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool isActive;

  const _HotKeyHeaderButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isActive = false,
  });

  @override
  State<_HotKeyHeaderButton> createState() => _HotKeyHeaderButtonState();
}

class _HotKeyHeaderButtonState extends State<_HotKeyHeaderButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool active = widget.isActive || _isHovered;

    return CustomTooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: active ? colors.primary.withValues(alpha: 0.08) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              widget.icon,
              size: 20,
              color: active ? colors.primary : colors.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionStepCard extends StatefulWidget {
  final int index;
  final KeyAction action;
  final VoidCallback onDelete;
  final VoidCallback onChanged;

  const _ActionStepCard({
    required this.index,
    required this.action,
    required this.onDelete,
    required this.onChanged,
  });

  @override
  State<_ActionStepCard> createState() => _ActionStepCardState();
}

class _ActionStepCardState extends State<_ActionStepCard> with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late final AnimationController _entranceController;
  late final Animation<double> _entranceOpacity;
  late final Animation<double> _entranceSlide;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 400 + (widget.index * 60).clamp(0, 400)),
    );

    _entranceOpacity = Tween<double>(begin: 0.9, end: 1.0).animate(CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.0, 1.0, curve: Curves.easeOut),
    ));

    _entranceSlide = Tween<double>(begin: 1.0, end: 0.0).animate(CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.0, 1.0, curve: Curves.easeOutCubic),
    ));

    _entranceController.forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: _entranceController,
      builder: (BuildContext context, Widget? child) {
        // Base opacity from entrance animation (0.9 -> 1.0)
        // Multiplied by hover state (Dimmed 0.85 if not hovered, 1.0 if hovered)
        final double currentTargetOpacity = _isHovered ? 1.0 : 0.85;
        final double finalOpacity = _entranceOpacity.value * currentTargetOpacity;

        return Opacity(
          opacity: finalOpacity,
          child: Transform.translate(
            offset: Offset(0, 15 * _entranceSlide.value),
            child: child,
          ),
        );
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Container(
          decoration: BoxDecoration(
            color: _isHovered ? colors.surfaceContainerHigh : colors.surfaceContainer,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isHovered ? colors.primary.withValues(alpha: 0.2) : colors.outlineVariant.withValues(alpha: 0.12),
            ),
            boxShadow: <BoxShadow>[
              if (_isHovered)
                BoxShadow(
                  color: colors.shadow.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: <Widget>[
                // Step Indicator Strip
                Positioned.fill(
                  right: null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 44,
                    color: _isHovered ? colors.primary.withValues(alpha: 0.12) : colors.primary.withValues(alpha: 0.08),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 18),
                      child: Text(
                        "${widget.index + 1}",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: _isHovered ? colors.primary : colors.primary.withValues(alpha: 0.8),
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
                // Content Row
                Row(
                  children: <Widget>[
                    const SizedBox(width: 44),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Column(
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: ModernDropdown<String>(
                                    value: widget.action.type.index.toString(),
                                    onChanged: (String? newValue) {
                                      widget.action.type = ActionType.values[int.tryParse(newValue ?? "0") ?? 0];
                                      if (widget.action.type == ActionType.sendClick) {
                                        widget.action.value = ClickAction(
                                                anchorType: AnchorType.topLeft, currentWindow: true, x: 50, y: 50)
                                            .toJson();
                                      } else if (widget.action.type == ActionType.setVar) {
                                        widget.action.value = jsonEncode(<String>["var", "value"]);
                                      } else if (widget.action.type == ActionType.hotkey) {
                                        widget.action.value = "ALT+F";
                                      } else if (widget.action.type == ActionType.sendKeys) {
                                        widget.action.value = "{#CTRL}A{^CTRL}deleted";
                                      } else if (widget.action.type == ActionType.tabameFunction) {
                                        widget.action.value = HotKeyInfo.tabameFunctions[0];
                                      } else if (widget.action.type == ActionType.openQuickMenuPage) {
                                        widget.action.value = HotKeyInfo.quickMenuPopups[0];
                                      } else if (widget.action.type == ActionType.wait) {
                                        widget.action.value = "1000";
                                      } else if (widget.action.type == ActionType.openLauncherWithPrefix) {
                                        widget.action.value = "";
                                      }
                                      widget.onChanged();
                                    },
                                    items: ActionType.values.map((ActionType v) {
                                      return ModernDropdownItem<String>(
                                        value: v.index.toString(),
                                        label: v.name.splitAndUpcase,
                                      );
                                    }).toList(),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  onPressed: widget.onDelete,
                                  icon: Icon(Icons.delete_sweep_rounded,
                                      color: colors.error.withValues(alpha: 0.8), size: 20),
                                  tooltip: "Delete Step",
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Builder(builder: (BuildContext context) {
                              return (context
                                  .findAncestorStateOfType<HotKeyActionState>()!
                                  ._buildActionContent(widget.action, colors));
                            }),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
