import 'package:flutter/material.dart';

import '../../models/classes/boxes.dart';
import '../../models/classes/saved_maps.dart';
import '../../models/settings.dart';
import '../widgets/text_input.dart';

class ViewsInterface extends StatefulWidget {
  const ViewsInterface({super.key});

  @override
  ViewsInterfaceState createState() => ViewsInterfaceState();
}

class ViewsInterfaceState extends State<ViewsInterface> {
  final ViewsSettings settings = ViewsSettings();

  @override
  void initState() {
    settings.load();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = Color(globalSettings.theme.accentColor);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 850),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildMainHeader(accent),
              const SizedBox(height: 16),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: globalSettings.views ? 1.0 : 0.5,
                child: IgnorePointer(
                  ignoring: !globalSettings.views,
                  child: Column(
                    children: <Widget>[
                      _buildConfigurationHub(accent),
                      const SizedBox(height: 16),
                      _buildOperationsManual(accent),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 60),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainHeader(Color accent) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  "GRID VIEW EXTENSION",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  "Global window snapping and custom layout control",
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          _toggleChip(
            label: globalSettings.views ? "ACTIVE" : "OFFLINE",
            value: globalSettings.views,
            onChanged: (bool value) {
              setState(() {
                globalSettings.views = value;
                Boxes.updateSettings("views", globalSettings.views);
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildConfigurationHub(Color accent) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildHubHeader("INSTRUMENT PANEL"),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
              final bool isNarrow = constraints.maxWidth < 600;
              return Column(
                children: <Widget>[
                  _buildHubRow(
                    isNarrow: isNarrow,
                    children: <Widget>[
                      Expanded(
                        flex: isNarrow ? 0 : 1,
                        child: _buildInstrumentSection(
                          title: "SNAPPING BEHAVIOR",
                          child: _buildBehaviorContent(accent),
                        ),
                      ),
                      if (!isNarrow) const SizedBox(width: 16),
                      Expanded(
                        flex: isNarrow ? 0 : 1,
                        child: _buildInstrumentSection(
                          title: "SIZE CONSTRAINTS",
                          child: _buildClampContent(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildInstrumentSection(
                    title: "GRID DENSITY & SCALING",
                    child: _buildScaleContent(),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildHubHeader(String title) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
        ),
      ),
    );
  }

  Widget _buildHubRow({required bool isNarrow, required List<Widget> children}) {
    if (isNarrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children.map((Widget w) {
          if (w is Expanded) return w.child;
          return w;
        }).toList(),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _buildInstrumentSection({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildBehaviorContent(Color accent) {
    return Column(
      children: <Widget>[
        _compactToggle(
          title: "Auto-Restore Size",
          value: settings.setPreviousSize,
          onChanged: (bool value) {
            setState(() {
              settings.setPreviousSize = value;
              settings.save();
            });
          },
        ),
        const SizedBox(height: 8),
        _compactAction(
          title: "Overlay Color",
          accent: accent,
          trailing: Container(
            width: 24,
            height: 14,
            decoration: BoxDecoration(
              color: settings.bgColor,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1)),
            ),
          ),
          onTap: () {},
        ),
      ],
    );
  }

  Widget _buildScaleContent() {
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
      final bool isNarrow = constraints.maxWidth < 450;
      return Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _inputGrid(
                  "SUBDIVISION",
                  <Widget>[
                    _gridInput("Rows", settings.scaleW.toString(), (String v) => settings.scaleW = int.tryParse(v) ?? 15),
                    _gridInput("Cols", settings.scaleH.toString(), (String v) => settings.scaleH = int.tryParse(v) ?? 15),
                  ],
                ),
              ),
              if (!isNarrow) const SizedBox(width: 16),
              if (!isNarrow)
                Expanded(
                  child: _inputGrid(
                    "SCROLL STEP",
                    <Widget>[
                      _gridInput("W-Step", settings.scrollStepW.toString(),
                          (String v) => settings.scrollStepW = int.tryParse(v) ?? 1),
                      _gridInput("H-Step", settings.scrollStepH.toString(),
                          (String v) => settings.scrollStepH = int.tryParse(v) ?? 1),
                    ],
                  ),
                ),
            ],
          ),
          if (isNarrow) const SizedBox(height: 12),
          if (isNarrow)
            _inputGrid(
              "SCROLL STEP",
              <Widget>[
                _gridInput("W-Step", settings.scrollStepW.toString(),
                    (String v) => settings.scrollStepW = int.tryParse(v) ?? 1),
                _gridInput("H-Step", settings.scrollStepH.toString(),
                    (String v) => settings.scrollStepH = int.tryParse(v) ?? 1),
              ],
            ),
        ],
      );
    });
  }

  Widget _buildClampContent() {
    return Column(
      children: <Widget>[
        _inputGrid(
          "HORIZONTAL",
          <Widget>[
            _gridInput("Min", settings.minW.toString(), (String v) => settings.minW = int.tryParse(v) ?? 5),
            _gridInput("Max", settings.maxW.toString(), (String v) => settings.maxW = int.tryParse(v) ?? 100),
          ],
        ),
        const SizedBox(height: 12),
        _inputGrid(
          "VERTICAL",
          <Widget>[
            _gridInput("Min", settings.minH.toString(), (String v) => settings.minH = int.tryParse(v) ?? 5),
            _gridInput("Max", settings.maxH.toString(), (String v) => settings.maxH = int.tryParse(v) ?? 100),
          ],
        ),
      ],
    );
  }

  Widget _inputGrid(String label, List<Widget> inputs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label,
            style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3))),
        const SizedBox(height: 6),
        Row(
          children: inputs.map((Widget w) => Expanded(child: Padding(padding: const EdgeInsets.only(right: 8), child: w))).toList(),
        ),
      ],
    );
  }

  Widget _buildOperationsManual(Color accent) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            "OPERATIONS MANUAL",
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
              color: Color(0xFF888888),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              _guideChip(Icons.mouse_outlined, "Right Click", "Start Snapping"),
              _guideChip(Icons.swap_calls_outlined, "Scroll Wheel", "Adjust Density"),
              _guideChip(Icons.pinch_outlined, "Hold RC + Drag", "Select Area"),
              _guideChip(Icons.touch_app_outlined, "Release", "Snap Window"),
            ],
          ),
        ],
      ),
    );
  }

  Widget _compactToggle({required String title, required bool value, required ValueChanged<bool> onChanged}) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: Row(
          children: <Widget>[
            Expanded(child: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
            Transform.scale(
              scale: 0.7,
              child: Switch(
                value: value,
                onChanged: onChanged,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _compactAction({required String title, required Color accent, required Widget trailing, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: <Widget>[
            Expanded(child: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
            trailing,
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 14, color: Theme.of(context).hintColor.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }

  Widget _toggleChip({required String label, required bool value, required ValueChanged<bool> onChanged}) {
    final Color accent = Color(globalSettings.theme.accentColor);
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: value ? accent.withValues(alpha: 0.1) : Theme.of(context).dividerColor.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: value ? accent.withValues(alpha: 0.3) : Theme.of(context).dividerColor.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: value ? accent : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: value ? accent : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _guideChip(IconData icon, String key, String action) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: onSurface.withValues(alpha: 0.05)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: onSurface.withValues(alpha: 0.5)),
          const SizedBox(width: 8),
          Text(
            key,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: onSurface.withValues(alpha: 0.8)),
          ),
          const SizedBox(width: 4),
          Text(
            action,
            style: TextStyle(fontSize: 11, color: onSurface.withValues(alpha: 0.4)),
          ),
        ],
      ),
    );
  }

  Widget _gridInput(String label, String value, Function(String) onChanged) {
    return TextInput(
      key: UniqueKey(),
      labelText: label,
      value: value,
      onChanged: (String e) {
        onChanged(e);
        settings.save();
      },
    );
  }
}
