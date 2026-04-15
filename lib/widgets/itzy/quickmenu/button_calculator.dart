import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:math_parser/math_parser.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../widgets/quick_actions_item.dart';

class CalculatorButton extends StatefulWidget {
  const CalculatorButton({super.key});
  @override
  CalculatorButtonState createState() => CalculatorButtonState();
}

class CalculatorButtonState extends State<CalculatorButton> {
  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message: "Calculator",
      icon: const Icon(Icons.functions),
      onTap: () async {
        showModalBottomSheet<void>(
          context: context,
          anchorPoint: const Offset(100, 200),
          elevation: 0,
          backgroundColor: Colors.transparent,
          barrierColor: Colors.transparent,
          constraints: const BoxConstraints(maxWidth: 320),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          enableDrag: true,
          isScrollControlled: true,
          builder: (BuildContext context) {
            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: FractionallySizedBox(
                heightFactor: 0.85,
                child: Listener(
                  onPointerDown: (PointerDownEvent event) {
                    if (event.kind == PointerDeviceKind.mouse && event.buttons == kSecondaryMouseButton) {
                      Navigator.pop(context);
                    }
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: CalculatorWidget(),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class CalcEntry {
  String name;
  String expression;
  double value;
  CalcEntry({required this.name, required this.expression, required this.value});

  Map<String, dynamic> toMap() => <String, dynamic>{
        'name': name,
        'expression': expression,
        'value': value,
      };

  factory CalcEntry.fromMap(Map<String, dynamic> map) => CalcEntry(
        name: (map['name'] as String?) ?? '',
        expression: (map['expression'] as String?) ?? '',
        value: (map['value'] as num?)?.toDouble() ?? 0.0,
      );
}

class CalculatorWidget extends StatefulWidget {
  const CalculatorWidget({super.key});
  @override
  CalculatorWidgetState createState() => CalculatorWidgetState();
}

class CalculatorWidgetState extends State<CalculatorWidget> {
  final List<CalcEntry> _history = <CalcEntry>[];
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String _previewResult = "";
  String _errorMessage = "";
  String? _statusMessage;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  void _loadHistory() {
    final String saved = Boxes.pref.getString("calculatorEntries") ?? "";
    if (saved.isNotEmpty) {
      final List<dynamic> list = jsonDecode(saved) as List<dynamic>;
      _history.addAll(list.map((dynamic e) => CalcEntry.fromMap(e as Map<String, dynamic>)));
      _recalculateAll();
    }
  }

  void _saveHistory() {
    Boxes.updateSettings("calculatorEntries", jsonEncode(_history.map((CalcEntry e) => e.toMap()).toList()));
  }

  String _preprocess(String exp) {
    return exp.replaceAll('%', '*0.01');
  }

  void _recalculateAll() {
    final Map<String, double> vars = <String, double>{};
    for (int i = 0; i < _history.length; i++) {
      try {
        final String preprocessed = _preprocess(_history[i].expression);
        final MathNode node = MathNodeExpression.fromString(preprocessed, variableNames: vars.keys.toSet());
        final double result = node.calc(MathVariableValues(vars)).toDouble();
        _history[i].value = result;
        vars[_history[i].name] = result;
      } catch (e) {
        // Keep previous value or mark error
      }
    }
    setState(() {});
  }

  void _evaluatePreview(String val) {
    if (val.isEmpty) {
      setState(() {
        _previewResult = "";
        _errorMessage = "";
      });
      return;
    }

    try {
      final Map<String, double> vars = <String, double>{for (CalcEntry e in _history) e.name: e.value};
      String mathPart = val;
      if (val.contains('=')) {
        final List<String> parts = val.split('=');
        if (parts.length == 2) {
          mathPart = parts[1].trim();
        }
      }
      if (mathPart.isEmpty) {
        setState(() {
          _previewResult = "";
          _errorMessage = "";
        });
        return;
      }
      final String preprocessed = _preprocess(mathPart);
      final MathNode node = MathNodeExpression.fromString(preprocessed, variableNames: vars.keys.toSet());
      final double result = node.calc(MathVariableValues(vars)).toDouble();
      setState(() {
        _previewResult = result.formatNum2();
        _errorMessage = "";
      });
    } catch (e) {
      setState(() {
        _previewResult = "";
        _errorMessage = "Invalid expression";
      });
    }
  }

  void _submit() {
    final String val = _controller.text.trim();
    if (val.isEmpty) return;

    // Check if it's an assignment (e.g., a=50)
    if (val.contains('=')) {
      final List<String> parts = val.split('=');
      if (parts.length == 2) {
        final String name = parts[0].trim();
        final String exp = parts[1].trim();
        final int index = _history.indexWhere((CalcEntry e) => e.name == name);
        if (index > -1) {
          _history[index].expression = exp;
          _recalculateAll();
          _saveHistory();
          _controller.clear();
          _evaluatePreview("");
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _focusNode.requestFocus();
          });
          return;
        }
      }
    }

    // Otherwise, create new variable
    try {
      final Map<String, double> vars = <String, double>{for (CalcEntry e in _history) e.name: e.value};
      final String preprocessed = _preprocess(val);
      final MathNode node = MathNodeExpression.fromString(preprocessed, variableNames: vars.keys.toSet());
      final double result = node.calc(MathVariableValues(vars)).toDouble();

      final String nextName = String.fromCharCode('a'.codeUnitAt(0) + (_history.length % 26)).toLowerCase();
      // If we go beyond z, we might need a different naming scheme, but 26 vars is usually enough for quick menu
      _history.add(CalcEntry(name: nextName, expression: val, value: result));
      _recalculateAll();
      _saveHistory();
      _controller.clear();
      _evaluatePreview("");
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNode.requestFocus();
      });
    } catch (e) {
      setState(() {
        _errorMessage = "Error: Check your formula";
      });
    }
  }

  void _clearAll() {
    setState(() {
      _history.clear();
      _saveHistory();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNode.requestFocus();
      });
    });
  }

  void _copyToClipboard(String value) {
    Clipboard.setData(ClipboardData(text: value));
    setState(() {
      _statusMessage = "Copied";
    });
    _statusTimer?.cancel();
    _statusTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _statusMessage = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final Color surface = Theme.of(context).colorScheme.surface;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final Color accent = Color(globalSettings.themeColors.accentColor);

    return Material(
      type: MaterialType.transparency,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: surface.withAlpha(216),
          border: Border.all(color: onSurface.withAlpha(25), width: 1),
        ),
        child: Column(
          children: <Widget>[
            _buildHeader(accent, onSurface),
            const Divider(height: 1),
            Expanded(child: _buildHistoryList(accent, onSurface)),
            const Divider(height: 1),
            _buildInputArea(accent, onSurface),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(Color accent, Color onSurface) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: <Widget>[
          Icon(Icons.calculate_outlined, size: 20, color: accent),
          const SizedBox(width: 8),
          const Text("Calculator", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          if (_statusMessage != null) ...<Widget>[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: accent.withAlpha(40),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _statusMessage!,
                style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w500),
              ),
            ),
          ],
          const Spacer(),
          if (_history.isNotEmpty)
            IconButton(
              onPressed: _clearAll,
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              tooltip: "Clear All",
              color: onSurface.withAlpha(120),
            ),
        ],
      ),
    );
  }

  Widget _buildHistoryList(Color accent, Color onSurface) {
    if (_history.isEmpty) {
      return Center(
        child: Text(
          "No calculations yet\nType something like 10+20",
          textAlign: TextAlign.center,
          style: TextStyle(color: onSurface.withAlpha(100), fontSize: 13),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _history.length,
      itemBuilder: (BuildContext context, int index) {
        final CalcEntry entry = _history.elementAt(_history.length - index - 1);
        return _HistoryTile(
          entry: entry,
          accent: accent,
          onSurface: onSurface,
          onEdit: (String newExp) {
            setState(() {
              entry.expression = newExp;
              _recalculateAll();
              _saveHistory();
            });
          },
          onCopy: (String val) => _copyToClipboard(val),
        );
      },
    );
  }

  Widget _buildInputArea(Color accent, Color onSurface) {
    return Padding(
      padding: const EdgeInsets.all(16).copyWith(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // if (_previewResult.isNotEmpty || _errorMessage.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 4),
            child: Text(
              _errorMessage.isNotEmpty
                  ? _errorMessage
                  : _previewResult.isNotEmpty
                      ? "= $_previewResult"
                      : "",
              style: TextStyle(
                color: _errorMessage.isNotEmpty ? Colors.redAccent.withAlpha(200) : accent,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: onSurface.withAlpha(15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              onChanged: _evaluatePreview,
              onSubmitted: (_) => _submit(),
              textInputAction: TextInputAction.none,
              style: const TextStyle(fontSize: 15),
              decoration: InputDecoration(
                hintText: "Enter math problem...",
                hintStyle: TextStyle(color: onSurface.withAlpha(80)),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(12),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Press Enter to save as a variable",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, color: onSurface.withAlpha(80)),
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatefulWidget {
  final CalcEntry entry;
  final Color accent;
  final Color onSurface;
  final Function(String) onEdit;
  final Function(String) onCopy;

  const _HistoryTile({
    required this.entry,
    required this.accent,
    required this.onSurface,
    required this.onEdit,
    required this.onCopy,
  });

  @override
  State<_HistoryTile> createState() => _HistoryTileState();
}

class _HistoryTileState extends State<_HistoryTile> {
  bool _isHovered = false;
  bool _isEditing = false;
  late TextEditingController _editController;

  @override
  void initState() {
    super.initState();
    _editController = TextEditingController(text: widget.entry.expression);
  }

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (PointerEnterEvent _) => setState(() => _isHovered = true),
      onExit: (PointerExitEvent _) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: _isHovered ? widget.accent.withAlpha(20) : widget.onSurface.withAlpha(10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _isHovered ? widget.accent.withAlpha(40) : Colors.transparent),
        ),
        child: Row(
          children: <Widget>[
            // Variable name
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: widget.accent.withAlpha(40),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                widget.entry.name,
                style: TextStyle(color: widget.accent, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            const SizedBox(width: 8),
            // Expression area (Click to edit)
            Expanded(
              child: _isEditing
                  ? TextField(
                      controller: _editController,
                      autofocus: true,
                      onSubmitted: (String val) {
                        widget.onEdit(val);
                        setState(() => _isEditing = false);
                      },
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    )
                  : InkWell(
                      onTap: () => setState(() => _isEditing = true),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Flexible(
                              child: Text(
                                widget.entry.expression,
                                style: TextStyle(color: widget.onSurface.withAlpha(150), fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (_isHovered) ...<Widget>[
                              const SizedBox(width: 6),
                              Icon(Icons.edit_rounded, size: 10, color: widget.accent.withAlpha(150)),
                            ],
                          ],
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 8),
            // Result area (Click to copy)
            InkWell(
              onTap: () => widget.onCopy(widget.entry.value.toString()),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  children: <Widget>[
                    Text(
                      " = ",
                      style: TextStyle(color: widget.onSurface.withAlpha(80), fontSize: 13),
                    ),
                    Text(
                      widget.entry.value.formatNum2(),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
