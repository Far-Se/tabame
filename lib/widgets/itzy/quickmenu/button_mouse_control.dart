import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/classes/hotkeys.dart';
import '../../../models/classes/saved_maps.dart';
import '../../../models/settings.dart';
import '../../../services/mouse_gestures_service.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/panel_header.dart';
import '../../widgets/windows_scroll.dart';

class MouseControlButton extends StatelessWidget {
  const MouseControlButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ModalButton(
      actionName: 'Hot Corners & Gestures',
      icon: const Icon(Icons.gesture),
      child: () => const MouseControlPanel(),
    );
  }
}

class MouseControlPanel extends StatefulWidget {
  const MouseControlPanel({super.key});

  @override
  State<MouseControlPanel> createState() => _MouseControlPanelState();
}

class _MouseControlPanelState extends State<MouseControlPanel> {
  static const Map<String, String> _cornerNames = <String, String>{
    'tl': 'Top Left',
    'tr': 'Top Right',
    'bl': 'Bottom Left',
    'br': 'Bottom Right',
  };
  static const Map<String, IconData> _cornerIcons = <String, IconData>{
    'tl': Icons.north_west_rounded,
    'tr': Icons.north_east_rounded,
    'bl': Icons.south_west_rounded,
    'br': Icons.south_east_rounded,
  };
  static const List<String> _patternOptions = <String>[
    'R', 'L', 'U', 'D', //
    'RD', 'RU', 'RL', 'LD', 'LU', 'LR', 'UD', 'UR', 'UL', 'DR', 'DL', 'DU',
  ];

  late MouseControlConfig _config;
  String _expandedCorner = '';
  String _newPattern = 'R';
  GestureAction _newAction = GestureAction();

  @override
  void initState() {
    super.initState();
    _config = Boxes.mouseControl.copyWith();
  }

  void _save() {
    Boxes.mouseControl = _config;
    MouseGesturesService.instance.applyConfig();
    setState(() {});
  }

  static String _arrows(String pattern) {
    const Map<String, String> map = <String, String>{'L': '←', 'R': '→', 'U': '↑', 'D': '↓'};
    return pattern.split('').map((String t) => map[t] ?? t).join(' ');
  }

  static String _actionSummary(GestureAction action) {
    switch (action.type) {
      case 'function':
        return action.value;
      case 'popup':
        return 'Open ${action.value}';
      case 'command':
        return action.value;
      case 'keys':
        return action.value;
      default:
        return 'Not set';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const PanelHeader(title: 'Hot Corners & Gestures', icon: Icons.gesture),
        Flexible(
          child: Material(
            type: MaterialType.transparency,
            child: WindowsScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _buildSectionLabel(
                      label: 'Hot Corners',
                      icon: Icons.crop_free_rounded,
                      enabled: _config.hotCornersEnabled,
                      onToggle: (bool value) {
                        _config.hotCornersEnabled = value;
                        _save();
                      },
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Park the cursor in a corner of the primary display to trigger an action.',
                      style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(120)),
                    ),
                    const SizedBox(height: 8),
                    for (final String corner in _cornerNames.keys) ...<Widget>[
                      _buildCornerRow(corner),
                      const SizedBox(height: 6),
                    ],
                    _buildDwellCard(),
                    const SizedBox(height: 14),
                    _buildSectionLabel(
                      label: 'Mouse Gestures',
                      icon: Icons.gesture,
                      enabled: _config.gesturesEnabled,
                      onToggle: (bool value) {
                        _config.gesturesEnabled = value;
                        _save();
                      },
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Hold the right mouse button and draw a stroke. Plain right-clicks are untouched.',
                      style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(120)),
                    ),
                    const SizedBox(height: 8),
                    if (_config.gestures.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          'No gestures yet — add one below.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: Design.baseFontSize + 0.5, color: Design.text.withAlpha(110)),
                        ),
                      )
                    else
                      for (final MouseGestureBinding binding in _config.gestures) ...<Widget>[
                        _buildGestureRow(binding),
                        const SizedBox(height: 6),
                      ],
                    const SizedBox(height: 4),
                    _buildAddGestureCard(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionLabel({
    required String label,
    required IconData icon,
    required bool enabled,
    required ValueChanged<bool> onToggle,
  }) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 14, color: Design.accent),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: Design.baseFontSize + 1,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: Design.text,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Divider(height: 1, color: Design.text.withAlpha(20))),
        const SizedBox(width: 8),
        SizedBox(
          height: 22,
          child: Transform.scale(
            scale: 0.65,
            child: Switch(
              value: enabled,
              activeThumbColor: Design.accent,
              onChanged: onToggle,
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Hot corners
  // ---------------------------------------------------------------------------

  Widget _buildCornerRow(String corner) {
    final GestureAction action = _config.corners[corner] ?? GestureAction();
    final bool expanded = _expandedCorner == corner;
    final bool isSet = action.isSet;

    return Container(
      decoration: BoxDecoration(
        color: isSet ? Design.accent.withAlpha(10) : Design.text.withAlpha(7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: expanded ? Design.accent.withAlpha(70) : (isSet ? Design.accent.withAlpha(30) : Design.text.withAlpha(16))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            onTap: () => setState(() => _expandedCorner = expanded ? '' : corner),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Row(
                children: <Widget>[
                  Icon(_cornerIcons[corner], size: 15, color: isSet ? Design.accent : Design.text.withAlpha(110)),
                  const SizedBox(width: 8),
                  Text(
                    _cornerNames[corner]!,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _actionSummary(action),
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: Design.baseFontSize + 0.5,
                        color: isSet ? Design.accent : Design.text.withAlpha(100),
                        fontWeight: isSet ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    size: 15,
                    color: Design.text.withAlpha(110),
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 9),
              child: _ActionEditor(
                action: action,
                onChanged: (GestureAction updated) {
                  _config.corners[corner] = updated;
                  _save();
                },
                onClear: !isSet
                    ? null
                    : () {
                        _config.corners.remove(corner);
                        _save();
                      },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDwellCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 4),
      decoration: BoxDecoration(
        color: Design.text.withAlpha(7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Design.text.withAlpha(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Trigger delay',
                  style: TextStyle(fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Design.accent.withAlpha(22),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${_config.cornerDwellMs} ms',
                  style: TextStyle(
                    fontSize: Design.baseFontSize,
                    fontWeight: FontWeight.w700,
                    color: Design.accent,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(
            height: 20,
            child: Slider(
              value: _config.cornerDwellMs.toDouble().clamp(100, 1000),
              min: 100,
              max: 1000,
              divisions: 18,
              onChanged: (double value) => setState(() => _config.cornerDwellMs = value.round()),
              onChangeEnd: (double _) => _save(),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Gestures
  // ---------------------------------------------------------------------------

  Widget _buildGestureRow(MouseGestureBinding binding) {
    final bool enabled = binding.enabled;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: enabled ? Design.accent.withAlpha(10) : Design.text.withAlpha(7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: enabled ? Design.accent.withAlpha(30) : Design.text.withAlpha(16)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Design.accent.withAlpha(enabled ? 24 : 12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _arrows(binding.pattern),
              style: TextStyle(
                fontSize: Design.baseFontSize + 2,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: Design.accent.withAlpha(enabled ? 255 : 150),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _actionSummary(binding.action),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: Design.baseFontSize + 1,
                fontWeight: FontWeight.w600,
                color: Design.text.withAlpha(enabled ? 220 : 130),
              ),
            ),
          ),
          SizedBox(
            height: 24,
            child: Transform.scale(
              scale: 0.6,
              child: Switch(
                value: enabled,
                activeThumbColor: Design.accent,
                onChanged: (bool value) {
                  binding.enabled = value;
                  _save();
                },
              ),
            ),
          ),
          Tooltip(
            message: 'Delete gesture',
            waitDuration: const Duration(milliseconds: 400),
            child: InkWell(
              onTap: () {
                _config.gestures.removeWhere((MouseGestureBinding g) => g.id == binding.id);
                _save();
              },
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Icon(Icons.delete_outline_rounded, size: 15, color: Design.text.withAlpha(120)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddGestureCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: Design.text.withAlpha(7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Design.text.withAlpha(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                'ADD GESTURE',
                style: TextStyle(
                  fontSize: Design.baseFontSize,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: Design.text.withAlpha(150),
                ),
              ),
              const Spacer(),
              DropdownButton<String>(
                value: _newPattern,
                isDense: true,
                underline: const SizedBox.shrink(),
                style: TextStyle(
                  fontSize: Design.baseFontSize + 2,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: Design.accent,
                ),
                items: <DropdownMenuItem<String>>[
                  for (final String pattern in _patternOptions)
                    DropdownMenuItem<String>(value: pattern, child: Text(_arrows(pattern))),
                ],
                onChanged: (String? value) => setState(() => _newPattern = value ?? 'R'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _ActionEditor(
            action: _newAction,
            onChanged: (GestureAction updated) => setState(() => _newAction = updated),
          ),
          const SizedBox(height: 8),
          Center(
            child: InkWell(
              onTap: !_newAction.isSet
                  ? null
                  : () {
                      _config.gestures.add(MouseGestureBinding(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        pattern: _newPattern,
                        action: _newAction.copyWith(),
                      ));
                      _newAction = GestureAction();
                      _save();
                    },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 26),
                decoration: BoxDecoration(
                  color: Design.accent.withAlpha(_newAction.isSet ? 28 : 10),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Design.accent.withAlpha(_newAction.isSet ? 80 : 30)),
                ),
                child: Text(
                  'ADD',
                  style: TextStyle(
                    fontSize: Design.baseFontSize + 0.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: Design.accent.withAlpha(_newAction.isSet ? 255 : 130),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Inline editor for a [GestureAction]: pick the action type, then the value
/// (function name, popup name, or a command/path to open).
class _ActionEditor extends StatefulWidget {
  const _ActionEditor({required this.action, required this.onChanged, this.onClear});

  final GestureAction action;
  final ValueChanged<GestureAction> onChanged;
  final VoidCallback? onClear;

  @override
  State<_ActionEditor> createState() => _ActionEditorState();
}

class _ActionEditorState extends State<_ActionEditor> {
  late final TextEditingController _commandController = TextEditingController(
    text: widget.action.type == 'command' ? widget.action.value : '',
  );
  late final TextEditingController _keysController = TextEditingController(
    text: widget.action.type == 'keys' ? widget.action.value : '',
  );

  @override
  void dispose() {
    _commandController.dispose();
    _keysController.dispose();
    super.dispose();
  }

  void _setType(String type) {
    String value = '';
    if (type == 'function') value = HotKeyInfo.tabameFunctionsMap.keys.first;
    if (type == 'popup') value = HotKeyInfo.quickMenuPopups.first;
    if (type == 'command') value = _commandController.text.trim();
    if (type == 'keys') value = _keysController.text.trim();
    widget.onChanged(GestureAction(type: type, value: value));
  }

  @override
  Widget build(BuildContext context) {
    final String type = widget.action.type;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            _typeChip('Function', 'function'),
            const SizedBox(width: 5),
            _typeChip('Popup', 'popup'),
            const SizedBox(width: 5),
            _typeChip('Command', 'command'),
            const SizedBox(width: 5),
            _typeChip('Keys', 'keys'),
            const Spacer(),
            if (widget.onClear != null)
              InkWell(
                onTap: widget.onClear,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text(
                    'CLEAR',
                    style: TextStyle(
                      fontSize: Design.baseFontSize - 0.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: Design.text.withAlpha(120),
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (type == 'function' || type == 'popup') ...<Widget>[
          const SizedBox(height: 7),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: Design.text.withAlpha(8),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Design.text.withAlpha(20)),
            ),
            child: DropdownButton<String>(
              value: widget.action.value.isEmpty ? null : widget.action.value,
              isDense: true,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              hint: Text('Pick…', style: TextStyle(fontSize: Design.baseFontSize + 1)),
              style: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text),
              items: <DropdownMenuItem<String>>[
                for (final String option in type == 'function'
                    ? HotKeyInfo.tabameFunctionsMap.keys.toList()
                    : HotKeyInfo.quickMenuPopups)
                  DropdownMenuItem<String>(value: option, child: Text(option)),
              ],
              onChanged: (String? value) {
                if (value == null) return;
                widget.onChanged(GestureAction(type: type, value: value));
              },
            ),
          ),
        ],
        if (type == 'command') ...<Widget>[
          const SizedBox(height: 7),
          TextField(
            controller: _commandController,
            style: TextStyle(fontSize: Design.baseFontSize + 1),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Path, URL or command',
              hintStyle: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text.withAlpha(90)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Design.text.withAlpha(30)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Design.text.withAlpha(30)),
              ),
            ),
            onChanged: (String value) => widget.onChanged(GestureAction(type: 'command', value: value.trim())),
          ),
        ],
        if (type == 'keys') ...<Widget>[
          const SizedBox(height: 7),
          TextField(
            controller: _keysController,
            style: TextStyle(fontSize: Design.baseFontSize + 1),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'e.g. {CTRL}C or {#WIN}{^WIN}',
              hintStyle: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text.withAlpha(90)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Design.text.withAlpha(30)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Design.text.withAlpha(30)),
              ),
            ),
            onChanged: (String value) => widget.onChanged(GestureAction(type: 'keys', value: value.trim())),
          ),
        ],
      ],
    );
  }

  Widget _typeChip(String label, String value) {
    final bool selected = widget.action.type == value;
    return InkWell(
      onTap: () => _setType(value),
      borderRadius: BorderRadius.circular(7),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? Design.accent.withAlpha(18) : Design.text.withAlpha(7),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: selected ? Design.accent.withAlpha(70) : Design.text.withAlpha(16)),
        ),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: Design.baseFontSize - 0.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: selected ? Design.accent : Design.text.withAlpha(140),
          ),
        ),
      ),
    );
  }
}
