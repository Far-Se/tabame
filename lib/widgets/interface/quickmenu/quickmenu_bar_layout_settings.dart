import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/quick_menu_bar_layout.dart';
import '../../../models/settings.dart';

class QuickMenuBarLayoutSettings extends StatefulWidget {
  const QuickMenuBarLayoutSettings({super.key});

  @override
  State<QuickMenuBarLayoutSettings> createState() => _QuickMenuBarLayoutSettingsState();
}

class _QuickMenuBarLayoutSettingsState extends State<QuickMenuBarLayoutSettings> {
  Future<void> _save(QuickMenuBarLayout value) async {
    setState(() => user.quickMenuBarLayout = value);
    await Boxes.updateSettings('quickMenuBarLayout', value.toJson());
    await QuickMenuFunctions.refreshQuickMenu();
  }

  @override
  Widget build(BuildContext context) {
    final QuickMenuBarLayout layout = user.quickMenuBarLayout;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: Design.text.withAlpha(7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Design.text.withAlpha(18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'BAR COMPOSITION',
            style: TextStyle(
              color: Design.text,
              fontSize: Design.baseFontSize + 1,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            "Choose which groups share a bar, then set each group's side.",
            style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(165)),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<QuickMenuMergeMode>(
            initialValue: layout.mergeMode,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Merge',
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            ),
            items: <DropdownMenuItem<QuickMenuMergeMode>>[
              for (final QuickMenuMergeMode mode in QuickMenuMergeMode.values)
                DropdownMenuItem<QuickMenuMergeMode>(value: mode, child: Text(mode.label)),
            ],
            onChanged: (QuickMenuMergeMode? mode) {
              if (mode == null || mode == layout.mergeMode) return;
              _save(layout.withMergeMode(mode));
            },
          ),
          const SizedBox(height: 8),
          for (final QuickMenuBarGroup group in layout.groups)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      group.label,
                      style: TextStyle(
                        color: Design.text,
                        fontSize: Design.baseFontSize + 0.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  _positionChip(group, QuickMenuBarPosition.top, 'Top'),
                  const SizedBox(width: 5),
                  _positionChip(group, QuickMenuBarPosition.bottom, 'Bottom'),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _positionChip(QuickMenuBarGroup group, QuickMenuBarPosition position, String label) {
    final bool selected = group.position == position;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      visualDensity: VisualDensity.compact,
      labelStyle: TextStyle(
        color: selected ? Design.accent : Design.text.withAlpha(190),
        fontSize: Design.baseFontSize,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
      selectedColor: Design.accent.withAlpha(18),
      side: BorderSide(color: selected ? Design.accent.withAlpha(75) : Design.text.withAlpha(20)),
      onSelected: (bool value) {
        if (value) _save(user.quickMenuBarLayout.withGroupPosition(group, position));
      },
    );
  }
}
