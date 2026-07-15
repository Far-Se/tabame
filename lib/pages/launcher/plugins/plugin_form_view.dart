import 'dart:io';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/settings.dart';
import '../../../widgets/widgets/windows_scroll.dart';
import 'plugin_icons.dart';
import 'plugin_protocol.dart';

/// Renders a plugin's `form` view: a titled stack of dense inputs (text /
/// password / textarea / dropdown / checkbox / number / date / file / folder /
/// tags) with one or more submit CTAs.
///
/// Focus lives inside the form while it is shown (the launcher releases its
/// search-field focus grab). Enter in a single-line field submits; Escape
/// cancels via [onCancel]. Field state survives re-rendered frames as long as
/// the field ids stay the same, so a plugin can refresh other parts of the
/// frame (e.g. attach an `error` to a field) without wiping the user's input.
///
/// `required` fields are validated host-side before [onSubmit] fires; fields
/// with `watch: true` report every change through [onChanged] so plugins can
/// re-render dependent inputs.
class PluginFormView extends StatefulWidget {
  const PluginFormView({
    super.key,
    required this.form,
    required this.onSubmit,
    required this.onCancel,
    this.onChanged,
    this.onOpenActions,
  });

  final PluginForm form;

  /// The user submitted with these values; [button] is the pressed
  /// `form.buttons` id (null for the default single CTA).
  final void Function(Map<String, Object?> values, {String? button}) onSubmit;

  /// Escape.
  final VoidCallback onCancel;

  /// A `watch: true` field changed.
  final void Function(String fieldId, Map<String, Object?> values)? onChanged;

  /// Ctrl+K — the launcher opens the frame-level actions palette.
  final VoidCallback? onOpenActions;

  @override
  State<PluginFormView> createState() => _PluginFormViewState();
}

class _PluginFormViewState extends State<PluginFormView> {
  final Map<String, TextEditingController> _textControllers = <String, TextEditingController>{};
  final Map<String, bool> _checkboxValues = <String, bool>{};
  final Map<String, String?> _dropdownValues = <String, String?>{};
  final Map<String, String> _pathValues = <String, String>{};
  final Map<String, String> _dateValues = <String, String>{};
  final Map<String, Set<String>> _tagValues = <String, Set<String>>{};

  /// Host-side validation errors, keyed by field id. Cleared per-field on edit.
  final Map<String, String> _localErrors = <String, String>{};

  final FocusNode _firstFieldFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _syncFieldState(resetAll: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _firstFieldFocus.requestFocus();
    });
  }

  @override
  void didUpdateWidget(covariant PluginFormView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFieldState(resetAll: _signature(oldWidget.form) != _signature(widget.form));
  }

  @override
  void dispose() {
    for (final TextEditingController controller in _textControllers.values) {
      controller.dispose();
    }
    _firstFieldFocus.dispose();
    super.dispose();
  }

  /// Identity of the form's field set — id+type pairs. When it changes the
  /// plugin is showing a different form, so typed state is discarded.
  String _signature(PluginForm form) =>
      form.fields.map((PluginFormField f) => '${f.id}:${f.type}').join('|');

  bool _isNumber(PluginFormField field) => field.type == 'number';
  bool _isPath(PluginFormField field) => field.type == 'filepicker' || field.type == 'folderpicker';

  void _syncFieldState({required bool resetAll}) {
    if (resetAll) {
      for (final TextEditingController controller in _textControllers.values) {
        controller.dispose();
      }
      _textControllers.clear();
      _checkboxValues.clear();
      _dropdownValues.clear();
      _pathValues.clear();
      _dateValues.clear();
      _tagValues.clear();
      _localErrors.clear();
    }
    for (final PluginFormField field in widget.form.fields) {
      if (field.isTextLike || _isNumber(field)) {
        _textControllers.putIfAbsent(field.id, () {
          final Object? value = field.value;
          final String text = value is String ? value : (value is num ? '$value' : '');
          return TextEditingController(text: text);
        });
      } else if (field.type == 'checkbox') {
        _checkboxValues.putIfAbsent(field.id, () => field.value == true);
      } else if (field.type == 'dropdown') {
        final String? initial = field.value is String ? field.value as String? : null;
        _dropdownValues.putIfAbsent(
          field.id,
          () => field.options.any((PluginFormOption o) => o.value == initial)
              ? initial
              : (field.options.isEmpty ? null : field.options.first.value),
        );
      } else if (_isPath(field)) {
        _pathValues.putIfAbsent(field.id, () => field.value is String ? field.value as String : '');
      } else if (field.type == 'date') {
        _dateValues.putIfAbsent(field.id, () => field.value is String ? field.value as String : '');
      } else if (field.type == 'tags') {
        _tagValues.putIfAbsent(field.id, () {
          final Object? value = field.value;
          return value is List ? value.whereType<String>().toSet() : <String>{};
        });
      }
    }
  }

  Map<String, Object?> _collectValues() {
    final Map<String, Object?> values = <String, Object?>{};
    for (final PluginFormField field in widget.form.fields) {
      if (field.isTextLike) {
        values[field.id] = _textControllers[field.id]?.text ?? '';
      } else if (_isNumber(field)) {
        values[field.id] = num.tryParse(_textControllers[field.id]?.text.trim() ?? '');
      } else if (field.type == 'checkbox') {
        values[field.id] = _checkboxValues[field.id] ?? false;
      } else if (field.type == 'dropdown') {
        values[field.id] = _dropdownValues[field.id];
      } else if (_isPath(field)) {
        values[field.id] = _pathValues[field.id] ?? '';
      } else if (field.type == 'date') {
        values[field.id] = _dateValues[field.id] ?? '';
      } else if (field.type == 'tags') {
        values[field.id] = (_tagValues[field.id] ?? <String>{}).toList(growable: false);
      }
    }
    return values;
  }

  /// A change to [field]: clears its stale error and reports watched fields.
  void _fieldChanged(PluginFormField field) {
    if (_localErrors.remove(field.id) != null) setState(() {});
    if (field.watch) widget.onChanged?.call(field.id, _collectValues());
  }

  /// Host-side validation. Returns true when the form may submit.
  bool _validate() {
    final Map<String, Object?> values = _collectValues();
    _localErrors.clear();
    for (final PluginFormField field in widget.form.fields) {
      final Object? value = values[field.id];
      if (_isNumber(field)) {
        final String raw = _textControllers[field.id]?.text.trim() ?? '';
        if (raw.isNotEmpty && value == null) {
          _localErrors[field.id] = 'Not a number';
          continue;
        }
        if (value is num) {
          if (field.min != null && value < field.min!) {
            _localErrors[field.id] = 'Must be at least ${field.min}';
            continue;
          }
          if (field.max != null && value > field.max!) {
            _localErrors[field.id] = 'Must be at most ${field.max}';
            continue;
          }
        }
      }
      if (!field.required) continue;
      final bool empty = value == null ||
          (value is String && value.trim().isEmpty) ||
          (value is List && value.isEmpty) ||
          (field.type == 'checkbox' && value != true);
      if (empty) _localErrors[field.id] = 'Required';
    }
    if (_localErrors.isNotEmpty) {
      setState(() {});
      return false;
    }
    return true;
  }

  void _submit({String? button}) {
    if (!_validate()) return;
    widget.onSubmit(_collectValues(), button: button);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onCancel();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyK &&
        HardwareKeyboard.instance.isControlPressed &&
        widget.onOpenActions != null) {
      widget.onOpenActions!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String? _errorFor(PluginFormField field) => _localErrors[field.id] ?? field.error;

  InputDecoration _decoration(PluginFormField field) {
    final bool hasError = _errorFor(field) != null;
    final Color borderColor = hasError ? const Color(0xFFE5534B).withAlpha(150) : Design.text.withAlpha(24);
    return InputDecoration(
      hintText: field.placeholder,
      hintStyle: TextStyle(fontSize: 12, color: Design.text.withAlpha(80)),
      isDense: true,
      filled: true,
      fillColor: Design.text.withAlpha(10),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: BorderSide(color: hasError ? const Color(0xFFE5534B) : Design.accent.withAlpha(160)),
      ),
    );
  }

  Widget _fieldLabel(PluginFormField field) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            field.label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
              color: Design.text.withAlpha(140),
            ),
          ),
          if (field.required)
            Padding(
              padding: const EdgeInsets.only(left: 3),
              child: Text('*',
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: const Color(0xFFE5534B).withAlpha(200))),
            ),
        ],
      ),
    );
  }

  /// Error + description lines rendered under a field's input.
  List<Widget> _fieldFooter(PluginFormField field) {
    final String? error = _errorFor(field);
    return <Widget>[
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(error, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFFE5534B))),
        ),
      if (field.description.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(field.description, style: TextStyle(fontSize: 10.5, color: Design.text.withAlpha(100), height: 1.35)),
        ),
    ];
  }

  /// A read-only "value + trailing button" shell shared by date/file/folder
  /// pickers, styled like the text fields.
  Widget _pickerShell(PluginFormField field, {required String value, required IconData icon, required VoidCallback onPick}) {
    final bool hasError = _errorFor(field) != null;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onPick,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: Design.text.withAlpha(10),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
                color: hasError ? const Color(0xFFE5534B).withAlpha(150) : Design.text.withAlpha(24)),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  value.isEmpty ? (field.placeholder.isEmpty ? 'Choose…' : field.placeholder) : value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: value.isEmpty ? Design.text.withAlpha(80) : Design.text,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(icon, size: 14, color: Design.accent.withAlpha(200)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate(PluginFormField field) async {
    final DateTime now = DateTime.now();
    DateTime initial = now;
    final String current = _dateValues[field.id] ?? '';
    if (current.isNotEmpty) initial = DateTime.tryParse(current) ?? now;
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year + 100),
    );
    if (picked == null) return;
    setState(() => _dateValues[field.id] = picked.toIso8601String().substring(0, 10));
    _fieldChanged(field);
  }

  void _pickPath(PluginFormField field) {
    String? result;
    if (field.type == 'folderpicker') {
      final DirectoryPicker picker = DirectoryPicker()..title = field.label;
      result = picker.getDirectory()?.path;
    } else {
      final OpenFilePicker picker = OpenFilePicker()..title = field.label;
      final File? file = picker.getFile();
      result = file?.path;
    }
    if (result == null) return;
    setState(() => _pathValues[field.id] = result!);
    _fieldChanged(field);
  }

  Widget _buildField(PluginFormField field, {required bool autofocus}) {
    final TextStyle valueStyle = TextStyle(fontSize: 12.5, color: Design.text);

    Widget input;
    if (field.isTextLike || _isNumber(field)) {
      input = TextField(
        controller: _textControllers[field.id],
        focusNode: autofocus ? _firstFieldFocus : null,
        obscureText: field.type == 'password',
        maxLines: field.type == 'textarea' ? 4 : 1,
        keyboardType: _isNumber(field) ? const TextInputType.numberWithOptions(decimal: true, signed: true) : null,
        inputFormatters: _isNumber(field)
            ? <TextInputFormatter>[FilteringTextInputFormatter.allow(RegExp(r'[0-9eE+\-.]'))]
            : null,
        style: valueStyle,
        decoration: _decoration(field),
        onChanged: (_) => _fieldChanged(field),
        onSubmitted: field.type == 'textarea' ? null : (_) => _submit(),
      );
    } else if (field.type == 'dropdown') {
      input = DropdownButtonFormField<String>(
        initialValue: _dropdownValues[field.id],
        focusNode: autofocus ? _firstFieldFocus : null,
        isDense: true,
        style: valueStyle,
        decoration: _decoration(field),
        items: <DropdownMenuItem<String>>[
          for (final PluginFormOption option in field.options)
            DropdownMenuItem<String>(value: option.value, child: Text(option.label)),
        ],
        onChanged: (String? value) {
          setState(() => _dropdownValues[field.id] = value);
          _fieldChanged(field);
        },
      );
    } else if (field.type == 'date') {
      input = _pickerShell(
        field,
        value: _dateValues[field.id] ?? '',
        icon: Icons.calendar_month_rounded,
        onPick: () => _pickDate(field),
      );
    } else if (_isPath(field)) {
      input = _pickerShell(
        field,
        value: _pathValues[field.id] ?? '',
        icon: field.type == 'folderpicker' ? Icons.folder_open_rounded : Icons.file_open_rounded,
        onPick: () => _pickPath(field),
      );
    } else if (field.type == 'tags') {
      final Set<String> selected = _tagValues[field.id] ?? <String>{};
      input = Wrap(
        spacing: 5,
        runSpacing: 5,
        children: <Widget>[
          for (final PluginFormOption option in field.options)
            _TagChip(
              label: option.label,
              selected: selected.contains(option.value),
              onTap: () {
                setState(() {
                  selected.contains(option.value) ? selected.remove(option.value) : selected.add(option.value);
                  _tagValues[field.id] = selected;
                });
                _fieldChanged(field);
              },
            ),
        ],
      );
    } else {
      // checkbox
      final bool checked = _checkboxValues[field.id] ?? false;
      input = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            setState(() => _checkboxValues[field.id] = !checked);
            _fieldChanged(field);
          },
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 18,
                height: 18,
                child: Checkbox(
                  value: checked,
                  focusNode: autofocus ? _firstFieldFocus : null,
                  activeColor: Design.accent,
                  onChanged: (bool? value) {
                    setState(() => _checkboxValues[field.id] = value ?? false);
                    _fieldChanged(field);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Text(
                field.label,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Design.text.withAlpha(200)),
              ),
              if (field.required)
                Padding(
                  padding: const EdgeInsets.only(left: 3),
                  child: Text('*',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFFE5534B).withAlpha(200))),
                ),
            ],
          ),
        ),
      );
      // Checkboxes carry their own label; only append the footer.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[input, ..._fieldFooter(field)],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[_fieldLabel(field), input, ..._fieldFooter(field)],
    );
  }

  @override
  Widget build(BuildContext context) {
    final PluginForm form = widget.form;
    return Focus(
      onKeyEvent: _onKey,
      child: WindowsScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (form.title.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    form.title,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Design.text),
                  ),
                ),
              for (int i = 0; i < form.fields.length; i++)
                Padding(
                  padding: EdgeInsets.only(bottom: i == form.fields.length - 1 ? 12 : 10),
                  child: _buildField(form.fields[i], autofocus: i == 0),
                ),
              Row(
                children: <Widget>[
                  if (form.buttons.isEmpty)
                    _SubmitButton(label: form.submitLabel, destructive: false, onTap: () => _submit())
                  else
                    for (final PluginFormButton button in form.buttons)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _SubmitButton(
                          label: button.label,
                          destructive: button.destructive,
                          onTap: () => _submit(button: button.id),
                        ),
                      ),
                  const SizedBox(width: 10),
                  Text(
                    'Enter to submit · Esc to cancel',
                    style: TextStyle(fontSize: 10, color: Design.text.withAlpha(90)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One selectable chip in a `tags` field.
class _TagChip extends StatelessWidget {
  const _TagChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? Design.accent.withAlpha(40) : Design.text.withAlpha(10),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: selected ? Design.accent.withAlpha(150) : Design.text.withAlpha(26)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (selected) ...<Widget>[
                Icon(Icons.check_rounded, size: 11, color: Design.accent),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: selected ? Design.accent : Design.text.withAlpha(180),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The form's primary CTA — the one place a subtle accent gradient is allowed
/// per the design language. Destructive buttons trade the accent for danger.
class _SubmitButton extends StatelessWidget {
  const _SubmitButton({required this.label, required this.destructive, required this.onTap});

  final String label;
  final bool destructive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color base = destructive ? const Color(0xFFE5534B) : Design.accent;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: <Color>[base.withAlpha(230), base.withAlpha(180)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: base.withAlpha(120)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(PluginIcons.resolve(destructive ? 'delete' : 'check'), size: 13, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
