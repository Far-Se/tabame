import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' hide TextInput;

import '../../../models/classes/hotkeys.dart';
import '../../../models/settings.dart';
import '../../widgets/checkbox_widget.dart';
import '../../widgets/modern_dropdown.dart';
import '../../widgets/mouse_scroll_widget.dart';
import '../../widgets/text_input.dart';
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

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Row(
        children: <Widget>[
          // Main Configuration Area
          Expanded(
            child: Column(
              children: <Widget>[
                // Pinned Header
                _buildPinnedHeader(colorScheme, textTheme),
                const Divider(height: 1),

                // Scrollable Content
                Expanded(
                  child: MouseScrollWidget(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          // Section 1: Context & Conditions
                          _buildSectionHeader("Conditions", Icons.radar_rounded, colorScheme, textTheme),
                          const SizedBox(height: 16),
                          _buildContextCard(colorScheme),
                          const SizedBox(height: 24),

                          // Section 2: Trigger Timing & Rules
                          _buildSectionHeader(
                              "Execution Logic", Icons.auto_awesome_motion_rounded, colorScheme, textTheme),
                          const SizedBox(height: 16),
                          _buildTriggerRulesCard(colorScheme),
                          const SizedBox(height: 24),

                          // Section 3: The Workflow
                          _buildSectionHeader("Action Sequence", Icons.account_tree_rounded, colorScheme, textTheme),
                          const SizedBox(height: 16),
                          _buildActionsTimeline(colorScheme, textTheme),
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ),
                ),

                // Persistent Footer
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: SizedBox(
                    height: 56,
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        widget.onSaved(widget.hotkey);
                        Navigator.of(context).pop();
                      },
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.check_circle_rounded),
                      label: const Text("SAVE AND FINISH",
                          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Utility Sidebar (Collapsible)
          if (_showUtilities) ...<Widget>[
            const VerticalDivider(width: 1),
            Container(
              width: 320,
              color: colorScheme.surfaceContainerLowest,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text("UTILITIES",
                            style: textTheme.labelLarge?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2.0,
                            )),
                        IconButton(
                          icon: const Icon(Icons.close_fullscreen_rounded, size: 20),
                          onPressed: () => setState(() => _showUtilities = false),
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  Expanded(
                    child: MouseScrollWidget(
                      child: MouseInfoWidget(
                        onAnchorTypeChanged: (AnchorType anchor) => setState(() {}),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: OutlinedButton.icon(
                      onPressed: () {
                        widget.onCloned();
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.copy_all_rounded, size: 18),
                      label: const Text("CLONE SETUP"),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
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
    );
  }

  Widget _buildPinnedHeader(ColorScheme colors, TextTheme texts) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surface.withAlpha(200),
      ),
      child: Row(
        children: <Widget>[
          // Enabled Switch with Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: widget.hotkey.enabled ? colors.primary.withAlpha(20) : colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  height: 24,
                  width: 38,
                  child: Switch(
                    value: widget.hotkey.enabled,
                    onChanged: (bool e) => setState(() => widget.hotkey.enabled = e),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.hotkey.enabled ? "ACTIVE" : "DISABLED",
                  style: texts.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: widget.hotkey.enabled ? colors.primary : colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          // Name Input
          Expanded(
            child: TextInput(
              labelText: "Workflow Label",
              value: widget.hotkey.name,
              onChanged: (String e) => setState(() => widget.hotkey.name = e),
            ),
          ),
          const SizedBox(width: 16),
          // Tool Toggle
          IconButton.filledTonal(
            tooltip: "Mouse Utilities",
            onPressed: () => setState(() => _showUtilities = !_showUtilities),
            icon: Icon(_showUtilities ? Icons.visibility_off_rounded : Icons.mouse_rounded, size: 20),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: "Close",
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, ColorScheme colors, TextTheme texts) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: colors.primary.withAlpha(180)),
        const SizedBox(width: 12),
        Text(
          title.toUpperCase(),
          style: texts.labelLarge?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: colors.primary.withAlpha(200),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(child: Divider(color: colors.outlineVariant.withAlpha(100))),
      ],
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
            subtitle: "Automatically activate the window precisely under the cursor position.",
            trailing: Switch(
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
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant.withAlpha(120)),
      ),
      child: child,
    );
  }

  Widget _buildActionItem(
      {required IconData icon, required String title, required String subtitle, required Widget trailing}) {
    return Row(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withAlpha(20),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Text(subtitle, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
        trailing,
      ],
    );
  }

  Widget _buildActionsTimeline(ColorScheme colors, TextTheme texts) {
    return Column(
      children: <Widget>[
        if (widget.hotkey.actions.isEmpty)
          _buildEmptySteps(colors)
        else
          ...List<Widget>.generate(widget.hotkey.actions.length, (int index) {
            return Column(
              children: <Widget>[
                _buildActionStep(index, colors, texts),
                if (index < widget.hotkey.actions.length - 1)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Container(height: 20, width: 2, color: colors.primary.withAlpha(50)),
                  ),
              ],
            );
          }),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () =>
              setState(() => widget.hotkey.actions.add(KeyAction(type: ActionType.hotkey, value: "ALT+SHIFT+F"))),
          icon: const Icon(Icons.add_task_rounded, size: 18),
          label: const Text("ADD NEW STEP"),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 54),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            side: BorderSide(color: colors.primary.withAlpha(80)),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptySteps(ColorScheme colors) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant.withAlpha(100), style: BorderStyle.none),
      ),
      child: Column(
        children: <Widget>[
          Icon(Icons.format_list_bulleted_rounded, color: colors.outline.withAlpha(100), size: 32),
          const SizedBox(height: 12),
          Text("Assign actions to this hotkey", style: TextStyle(color: colors.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildActionStep(int index, ColorScheme colors, TextTheme texts) {
    final KeyAction action = widget.hotkey.actions[index];
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.1)),
      ),
      child: Stack(
        children: <Widget>[
          // Sidebar Background Stretch
          Positioned.fill(
            child: Row(
              children: <Widget>[
                Container(
                  width: 50,
                  decoration: BoxDecoration(
                    color: colors.primary.withAlpha(15),
                    borderRadius:
                        const BorderRadius.only(topLeft: Radius.circular(16), bottomLeft: Radius.circular(16)),
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
          // Content Row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Step Number Indicator
              SizedBox(
                width: 50,
                height: 56, // Fixed height area for the number to center it at the top
                child: Center(
                  child: Text("${index + 1}",
                      style: TextStyle(fontWeight: FontWeight.w900, color: colors.primary, fontSize: 18)),
                ),
              ),
              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: ModernDropdown<String>(
                              value: action.type.index.toString(),
                              onChanged: (String? newValue) => setState(() {
                                action.type = ActionType.values[int.tryParse(newValue ?? "0") ?? 0];
                                // Initial values logic...
                                if (action.type == ActionType.sendClick) {
                                  action.value =
                                      ClickAction(anchorType: AnchorType.topLeft, currentWindow: true, x: 50, y: 50)
                                          .toJson();
                                } else if (action.type == ActionType.setVar) {
                                  action.value = jsonEncode(<String>["var", "value"]);
                                } else if (action.type == ActionType.hotkey) {
                                  action.value = "ALT+F";
                                } else if (action.type == ActionType.sendKeys) {
                                  action.value = "{#CTRL}A{^CTRL}deleted";
                                } else if (action.type == ActionType.tabameFunction) {
                                  action.value = HotKeyInfo.tabameFunctions[0];
                                }
                              }),
                              items: ActionType.values.map((ActionType v) {
                                return ModernDropdownItem<String>(
                                  value: v.index.toString(),
                                  label: v.name.splitAndUpcase,
                                );
                              }).toList(),
                            ),
                          ),
                          IconButton(
                            onPressed: () => setState(() => widget.hotkey.actions.removeAt(index)),
                            icon: Icon(Icons.delete_sweep_rounded, color: colors.error.withAlpha(200), size: 22),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      _buildActionContent(action, colors),
                    ],
                  ),
                ),
              ),
            ],
          ),
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
          subtitle: "Restrict this hotkey to a specific area of the screen.",
          trailing: Switch(
            onChanged: (bool e) => setState(() => widget.hotkey.boundToRegion = !widget.hotkey.boundToRegion),
            value: widget.hotkey.boundToRegion,
          ),
        ),
        if (widget.hotkey.boundToRegion)
          Padding(
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
                          onChanged: (bool e) =>
                              setState(() => widget.hotkey.region.asPercentage = !widget.hotkey.region.asPercentage),
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
                        child: TextInput(
                            labelText: "X1",
                            value: widget.hotkey.region.x1.toString(),
                            onChanged: (String e) => setState(() => widget.hotkey.region.x1 = int.tryParse(e) ?? 0))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: TextInput(
                            labelText: "Y1",
                            value: widget.hotkey.region.y1.toString(),
                            onChanged: (String e) => setState(() => widget.hotkey.region.y1 = int.tryParse(e) ?? 0))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: TextInput(
                            labelText: "X2",
                            value: widget.hotkey.region.x2.toString(),
                            onChanged: (String e) => setState(() => widget.hotkey.region.x2 = int.tryParse(e) ?? 0))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: TextInput(
                            labelText: "Y2",
                            value: widget.hotkey.region.y2.toString(),
                            onChanged: (String e) => setState(() => widget.hotkey.region.y2 = int.tryParse(e) ?? 0))),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildVariableCheck(ColorScheme colors) {
    return Column(
      children: <Widget>[
        _buildActionItem(
          icon: Icons.vibration_rounded,
          title: "Variable Dependency",
          subtitle: "Only trigger if a specific system variable matches a value.",
          trailing: Switch(
            onChanged: (bool e) => setState(() => variableCheck = e),
            value: variableCheck,
          ),
        ),
        if (variableCheck)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Row(
              children: <Widget>[
                Expanded(
                    child: TextInput(
                        labelText: "Var Name",
                        value: widget.hotkey.variableCheck[0],
                        onChanged: (String e) => widget.hotkey.variableCheck[0] = e)),
                const SizedBox(width: 12),
                Expanded(
                    child: TextInput(
                        labelText: "Target Value",
                        value: widget.hotkey.variableCheck[1],
                        onChanged: (String e) => widget.hotkey.variableCheck[1] = e)),
              ],
            ),
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
          onChanged: (String? n) =>
              setState(() => widget.hotkey.triggerType = TriggerType.values[HotKeyInfo.triggers.indexOf(n ?? "Press")]),
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
                    child: TextInput(
                        labelText: "Min Delay (ms)",
                        value: widget.hotkey.triggerInfo[0].toString(),
                        onChanged: (String e) => setState(() => widget.hotkey.triggerInfo[0] = int.tryParse(e) ?? 0))),
                const SizedBox(width: 12),
                Expanded(
                    child: TextInput(
                        labelText: "Max Duration (ms)",
                        value: widget.hotkey.triggerInfo[1].toString(),
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
                  subtitle: "Execute actions continuously as the mouse moves.",
                  trailing: Switch(
                    onChanged: (bool e) => setState(() => widget.hotkey.triggerInfo[2] = e ? -1 : 0),
                    value: widget.hotkey.triggerInfo[2] == -1,
                  ),
                ),
                const SizedBox(height: 16),
                if (widget.hotkey.triggerInfo[2] != -1)
                  Row(
                    children: <Widget>[
                      Expanded(
                          child: TextInput(
                              labelText: "Min Distance (px)",
                              value: widget.hotkey.triggerInfo[1].toString(),
                              onChanged: (String e) =>
                                  setState(() => widget.hotkey.triggerInfo[1] = int.tryParse(e) ?? 0))),
                      const SizedBox(width: 12),
                      Expanded(
                          child: TextInput(
                              labelText: "Max Threshold (px)",
                              value: widget.hotkey.triggerInfo[2].toString(),
                              onChanged: (String e) =>
                                  setState(() => widget.hotkey.triggerInfo[2] = int.tryParse(e) ?? 0))),
                    ],
                  )
                else
                  TextInput(
                      labelText: "Target Distance (px)",
                      value: widget.hotkey.triggerInfo[1].toString(),
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
                trailing: Switch(
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
                  child: TextInput(
                      labelText: "X offset",
                      value: click.x.toString(),
                      onChanged: (String v) {
                        click.x = int.tryParse(v) ?? 0;
                        action.value = click.toJson();
                      })),
              const SizedBox(width: 8),
              Expanded(
                  child: TextInput(
                      labelText: "Y offset",
                      value: click.y.toString(),
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
              child: TextInput(
                  labelText: "Variable",
                  value: varInfo[0],
                  onChanged: (String e) {
                    varInfo[0] = e;
                    action.value = jsonEncode(varInfo);
                  })),
          const SizedBox(width: 12),
          Expanded(
              child: TextInput(
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
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        tileColor: colors.primary.withAlpha(10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Focus(
          focusNode: focusNode,
          onKeyEvent: (FocusNode f, KeyEvent k) {
            if (k is KeyDownEvent && k.logicalKey.keyId < 0x100000000) {
              List<String> mods = <String>[];
              if (HardwareKeyboard.instance.isControlPressed) mods.add("CTRL");
              if (HardwareKeyboard.instance.isAltPressed) mods.add("ALT");
              if (HardwareKeyboard.instance.isShiftPressed) mods.add("SHIFT");
              if (HardwareKeyboard.instance.isMetaPressed) mods.add("WIN");
              if (mods.isNotEmpty) {
                action.value = "${mods.join("+")}+${k.logicalKey.keyLabel.toUpperCase()}";
                FocusScope.of(context).unfocus();
                setState(() {});
              }
            }
            return KeyEventResult.handled;
          },
          child: Row(
            children: <Widget>[
              Icon(Icons.keyboard_rounded, size: 18, color: colors.primary),
              const SizedBox(width: 12),
              Text(
                "KEY SEQUENCE:  ${action.value.toUpperCase()}",
                style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.1),
              ),
            ],
          ),
        ),
        subtitle: const Text("Click to record sequence...", style: TextStyle(fontSize: 10)),
        onTap: () => FocusScope.of(context).requestFocus(focusNode),
      );
    }
    if (action.type == ActionType.tabameFunction) {
      return ModernDropdown<String>(
        value: HotKeyInfo.tabameFunctions.contains(action.value) ? action.value : HotKeyInfo.tabameFunctions[0],
        onChanged: (String? newValue) => setState(() => action.value = newValue ?? HotKeyInfo.tabameFunctions[0]),
        items: HotKeyInfo.tabameFunctions.map((String v) {
          return ModernDropdownItem<String>(
            value: v,
            label: v.splitAndUpcase,
          );
        }).toList(),
      );
    }
    return TextInput(
        labelText: "Parameter / Path / Command", value: action.value, onChanged: (String v) => action.value = v);
  }
}
