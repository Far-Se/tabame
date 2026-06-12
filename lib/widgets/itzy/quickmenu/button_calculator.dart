import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:math_parser/math_parser.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/converter.dart';
import '../../../models/settings.dart';
import '../../../models/util/quickmenu_modal.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/panel_header.dart';
import 'button_currency_converter.dart';

class CalculatorButton extends StatelessWidget {
  const CalculatorButton({super.key});
  @override
  Widget build(BuildContext context) {
    return ModalButton(
        actionName: "Calculator", icon: const Icon(Icons.functions), child: () => const CalculatorWidget());
  }
}

class CalcEntry {
  String name;
  String expression;
  double value;
  String? displayResult;
  CalcEntry({required this.name, required this.expression, required this.value, this.displayResult});

  Map<String, dynamic> toMap() => <String, dynamic>{
        'name': name,
        'expression': expression,
        'value': value,
        'displayResult': displayResult,
      };

  factory CalcEntry.fromMap(Map<String, dynamic> map) => CalcEntry(
        name: (map['name'] as String?) ?? '',
        expression: (map['expression'] as String?) ?? '',
        value: (map['value'] as num?)?.toDouble() ?? 0.0,
        displayResult: map['displayResult'] as String?,
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
  int _previewToken = 0;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _loadHistory() async {
    final String saved = Boxes.pref.getString("calculatorEntries") ?? "";
    if (saved.isNotEmpty) {
      final List<dynamic> list = jsonDecode(saved) as List<dynamic>;
      _history.clear();
      _history.addAll(list.map((dynamic e) => CalcEntry.fromMap(e as Map<String, dynamic>)));
      await _recalculateAll();
    }
  }

  void _saveHistory() {
    Boxes.updateSettings("calculatorEntries", jsonEncode(_history.map((CalcEntry e) => e.toMap()).toList()));
  }

  String _preprocess(String exp) {
    return exp.replaceAll('%', '*0.01');
  }

  String _replaceVariables(String input, Map<String, double> vars) {
    String result = input;
    vars.forEach((String name, double value) {
      result = result.replaceAll('\$${name.toLowerCase()}', value.toString());
    });
    return result;
  }

  Future<({double value, String display})?> _runConverter(String expression, Map<String, double> vars) async {
    if (!expression.startsWith('/')) return null;
    final String input = _replaceVariables(expression.substring(1).trim(), vars);
    if (input.isEmpty) return null;

    try {
      if (input.startsWith('c ') || input.startsWith('currency ') || input.startsWith('cur ')) {
        final String cmd = input.replaceFirst(RegExp(r'^currency\s+|^c\s+|^cur\s+'), '');
        final String target = Boxes.pref.getString(CurrencyConverterService.toKey) ?? 'usd';
        final CurrencyConversionResult res =
            await CurrencyConverterService().convert(cmd, defaultTargetCurrency: target);
        return (value: res.convertedAmount, display: res.convertedLabel);
      } else if (input.startsWith('unit ') || input.startsWith('u ')) {
        final String cmd = input.replaceFirst(RegExp(r'^unit\s+|^u\s+'), '');
        final ParserResult res = await Parsers().unit(cmd);
        if (res.results.isNotEmpty) {
          final double? val = double.tryParse(res.results.first.split(' ').first.replaceAll(',', ''));
          if (val != null) {
            return (value: val, display: res.results.first);
          }
        }
      } else if (input == "clear") {
        _clearAll();
        setState(() => _controller.text = "");
      } else {
        String cmd = input;
        if (input.startsWith('c ')) cmd = input.substring(2);
        if (input.startsWith('calc ')) cmd = input.substring(5);

        final ParserResult res = await Parsers().calculator(cmd);
        if (res.results.isNotEmpty) {
          final String first = res.results.first;
          double? val;
          if (first.contains('=')) {
            val = double.tryParse(first.split('=').last.trim().replaceAll(',', ''));
          } else {
            val = double.tryParse(first.replaceAll(',', ''));
          }
          if (val != null) {
            return (value: val, display: first);
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _recalculateAll() async {
    final Map<String, double> vars = <String, double>{};
    for (int i = 0; i < _history.length; i++) {
      final CalcEntry entry = _history[i];
      try {
        if (entry.expression.startsWith('/')) {
          final ({double value, String display})? res = await _runConverter(entry.expression, vars);
          if (res != null) {
            entry.value = res.value;
            entry.displayResult = res.display;
          }
        } else {
          final String preprocessed = _preprocess(entry.expression);
          final MathNode node = MathNodeExpression.fromString(preprocessed, variableNames: vars.keys.toSet());
          final double result = node.calc(MathVariableValues(vars)).toDouble();
          entry.value = result;
          entry.displayResult = null;
        }
        vars[entry.name] = entry.value;
      } catch (e) {
        // Keep previous value
      }
    }
    if (mounted) setState(() {});
  }

  void _evaluatePreview(String val) async {
    final int token = ++_previewToken;
    if (val.isEmpty) {
      setState(() {
        _previewResult = "";
        _errorMessage = "";
      });
      return;
    }

    final Map<String, double> vars = <String, double>{for (CalcEntry e in _history) e.name: e.value};

    if (val.startsWith('/')) {
      final ({double value, String display})? res = await _runConverter(val, vars);
      if (token != _previewToken) return;
      if (res != null) {
        setState(() {
          _previewResult = res.display;
          _errorMessage = "";
        });
      } else {
        setState(() {
          _previewResult = "";
          _errorMessage = "Invalid converter command";
        });
      }
      return;
    }

    try {
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
      if (token != _previewToken) return;
      setState(() {
        _previewResult = result.formatNum2();
        _errorMessage = "";
      });
    } catch (e) {
      if (token != _previewToken) return;
      setState(() {
        _previewResult = "";
        _errorMessage = "Invalid expression";
      });
    }
  }

  void _submit() async {
    final String val = _controller.text.trim();
    if (val.isEmpty) return;

    final Map<String, double> vars = <String, double>{for (CalcEntry e in _history) e.name: e.value};

    // Check for assignment (e.g., a = /c 100 USD to EUR or a = 10 + 20)
    String? assignedName;
    String finalExpression = val;

    if (val.contains('=')) {
      final List<String> parts = val.split('=');
      if (parts.length == 2) {
        assignedName = parts[0].trim();
        finalExpression = parts[1].trim();
      }
    }

    try {
      double? result;
      String? display;

      if (finalExpression.startsWith('/')) {
        final ({double value, String display})? res = await _runConverter(finalExpression, vars);
        if (res != null) {
          result = res.value;
          display = res.display;
        }
      } else {
        final String preprocessed = _preprocess(finalExpression);
        final MathNode node = MathNodeExpression.fromString(preprocessed, variableNames: vars.keys.toSet());
        result = node.calc(MathVariableValues(vars)).toDouble();
      }

      if (result == null) throw Exception("Could not calculate result");

      if (assignedName != null) {
        final int index = _history.indexWhere((CalcEntry e) => e.name == assignedName);
        if (index > -1) {
          _history[index].expression = finalExpression;
          _history[index].value = result;
          _history[index].displayResult = display;
          await _recalculateAll();
          _saveHistory();
          _controller.clear();
          _evaluatePreview("");
          _focusNode.requestFocus();
          return;
        }
      }

      // Otherwise, create new variable
      final String nextName = String.fromCharCode('a'.codeUnitAt(0) + (_history.length % 26)).toLowerCase();
      _history.add(CalcEntry(name: nextName, expression: finalExpression, value: result, displayResult: display));
      await _recalculateAll();
      _saveHistory();
      _controller.clear();
      _evaluatePreview("");
      _focusNode.requestFocus();
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
        if (!mounted) return;
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

  void _showInfo() {
    final Color accent = userSettings.themeColors.accent;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    showQuickMenuModal(
      context: context,
      sigmaX: 8,
      sigmaY: 8,
      heightFactor: 0.96,
      child: Column(
        children: <Widget>[
          const PanelHeader(
            title: "Calculator Guide",
            icon: Icons.help_outline_rounded,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                _buildInfoSection(
                  "Math & Variables",
                  "Use variables like 'a', 'b', etc., in your expressions. "
                      "Each line you submit creates a new variable automatically.",
                  <String>["10 + 20", "a * 3", "b / 2"],
                  accent,
                  onSurface,
                ),
                const SizedBox(height: 16),
                _buildInfoSection(
                  "Advanced Converters",
                  "Start with '/' to use unit or currency converters. "
                      "Use '\$var' to reference your variables.",
                  <String>["/c 100 USD to EUR", "/c \$a RON to USD", "/unit 10 km to miles", "/u \$b kg to g"],
                  accent,
                  onSurface,
                ),
                const SizedBox(height: 16),
                _buildInfoSection(
                  "Management",
                  "Assign or update variables manually by writing '[a-z]=expression'. "
                      "Click on any history entry's expression to edit it.",
                  <String>["a = 50", "a = b * 10", "Click entry to edit", "/clear - clears the history"],
                  accent,
                  onSurface,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(String title, String description, List<String> examples, Color accent, Color onSurface) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: TextStyle(color: onSurface.withAlpha(180), fontSize: Design.baseFontSize + 2),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: onSurface.withAlpha(15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: onSurface.withAlpha(20)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: examples.map((String e) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  "• $e",
                  style: TextStyle(
                    color: onSurface.withAlpha(220),
                    fontFamily: 'monospace',
                    fontSize: Design.baseFontSize + 1,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color surface = Theme.of(context).colorScheme.surface;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final Color accent = userSettings.themeColors.accent;

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
            PanelHeader(
              title: "Calculator",
              icon: Icons.calculate_outlined,
              extraActions: <Widget>[
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
                      style: TextStyle(color: accent, fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
                IconButton(
                  onPressed: _showInfo,
                  icon: const Icon(Icons.info_outline_rounded, size: 18),
                  tooltip: "How to use",
                  color: onSurface.withAlpha(120),
                ),
                IconButton(
                  onPressed: _clearAll,
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  tooltip: "Clear All",
                  color: onSurface.withAlpha(120),
                ),
              ],
            ),
            Expanded(child: _buildHistoryList(accent, onSurface)),
            const Divider(height: 1),
            _buildInputArea(accent, onSurface),
          ],
        ),
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
          key: ValueKey<String>(entry.name),
          entry: entry,
          accent: accent,
          onSurface: onSurface,
          onEdit: (String newExp) async {
            entry.expression = newExp;
            await _recalculateAll();
            _saveHistory();
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
            style: TextStyle(fontSize: Design.baseFontSize, color: onSurface.withAlpha(80)),
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
    super.key,
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
  void didUpdateWidget(_HistoryTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.entry.expression != oldWidget.entry.expression && !_isEditing) {
      _editController.text = widget.entry.expression;
    }
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
          color: _isHovered ? userSettings.themeColors.accent.withAlpha(20) : widget.onSurface.withAlpha(10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _isHovered ? userSettings.themeColors.accent.withAlpha(40) : Colors.transparent),
        ),
        child: Row(
          children: <Widget>[
            // Variable name
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: userSettings.themeColors.accent.withAlpha(40),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                widget.entry.name,
                style: TextStyle(color: userSettings.themeColors.accent, fontWeight: FontWeight.bold, fontSize: 13),
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
                      onTapOutside: (_) {
                        widget.onEdit(_editController.text);
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
                              Icon(Icons.edit_rounded, size: 10, color: userSettings.themeColors.accent.withAlpha(150)),
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
                      widget.entry.displayResult ?? widget.entry.value.formatNum2(),
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
