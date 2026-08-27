import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../../../platform/file_picker_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../../models/settings.dart';
import '../../../platform/app_catalog_service.dart';
import '../../../widgets/widgets/windows_scroll.dart';
import 'plugin_icons.dart';
import 'plugin_protocol.dart';

/// Renders a plugin's `form` view: a titled stack of dense inputs (text /
/// password / textarea / dropdown / checkbox / number / date / file / folder /
/// tags) with one or more submit CTAs.
///
/// Focus lives inside the form while it is shown (the launcher releases its
/// search-field focus grab). Ctrl+Enter submits; plain Enter remains available
/// for multiline fields. Escape cancels via [onCancel]. Field state survives
/// re-rendered frames as long as the field ids stay the same, so a plugin can
/// refresh other parts of the frame (e.g. attach an `error` to a field) without
/// wiping the user's input.
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
    this.onValidate,
    this.onOpenActions,
    this.initialValues = const <String, Object?>{},
    this.onStateChanged,
    this.scrollController,
    this.draggable = false,
  });

  final PluginForm form;

  /// The user submitted with these values; [button] is the pressed
  /// `form.buttons` id (null for the default single CTA).
  final void Function(Map<String, Object?> values, {String? button}) onSubmit;

  /// Escape.
  final VoidCallback onCancel;

  /// A `watch: true` field changed.
  final void Function(String fieldId, Map<String, Object?> values)? onChanged;

  /// A field with `validate:true` settled after its debounce window.
  final void Function(String fieldId, Map<String, Object?> values)? onValidate;

  /// Ctrl+K — the launcher opens the frame-level actions palette.
  final VoidCallback? onOpenActions;

  /// Page-state restoration values supplied by [PluginView]. Plugin-declared
  /// field values remain the fallback for keys that are absent here.
  final Map<String, Object?> initialValues;
  final ValueChanged<Map<String, Object?>>? onStateChanged;
  final ScrollController? scrollController;
  final bool draggable;

  @override
  State<PluginFormView> createState() => _PluginFormViewState();
}

class _PluginFormViewState extends State<PluginFormView> {
  final Map<String, TextEditingController> _textControllers = <String, TextEditingController>{};
  final Map<String, bool> _checkboxValues = <String, bool>{};
  final Map<String, String?> _dropdownValues = <String, String?>{};
  final Map<String, String?> _comboboxValues = <String, String?>{};
  final Map<String, String> _pathValues = <String, String>{};
  final Map<String, String> _dateValues = <String, String>{};
  final Map<String, Set<String>> _tagValues = <String, Set<String>>{};
  final Map<String, List<String>> _fileListValues = <String, List<String>>{};
  final Map<String, double> _sliderValues = <String, double>{};
  final Map<String, String> _colorValues = <String, String>{};
  final Map<String, String> _appValues = <String, String>{};
  final Map<String, String> _shortcutValues = <String, String>{};
  final Map<String, FocusNode> _comboboxFocusNodes = <String, FocusNode>{};
  final Map<String, bool> _sectionExpanded = <String, bool>{};
  final Map<String, Timer> _validationTimers = <String, Timer>{};

  /// Host-side validation errors, keyed by field id. Cleared per-field on edit.
  final Map<String, String> _localErrors = <String, String>{};

  final FocusNode _firstFieldFocus = FocusNode();
  bool _pathPickerWasAlwaysOnTop = true;

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
    for (final FocusNode node in _comboboxFocusNodes.values) {
      node.dispose();
    }
    for (final Timer timer in _validationTimers.values) {
      timer.cancel();
    }
    _firstFieldFocus.dispose();
    super.dispose();
  }

  /// Identity of the form's field set — id+type pairs. When it changes the
  /// plugin is showing a different form, so typed state is discarded.
  String _signature(PluginForm form) => form.fields.map((PluginFormField f) => '${f.id}:${f.type}').join('|');

  bool _isNumber(PluginFormField field) => field.type == 'number';
  bool _isPath(PluginFormField field) =>
      field.type == 'filepicker' || field.type == 'folderpicker' || field.type == 'dropzone';

  PluginFormOption? _optionForValue(PluginFormField field, String value) {
    for (final PluginFormOption option in field.options) {
      if (option.value == value) return option;
    }
    return null;
  }

  PluginFormOption? _optionForLabel(PluginFormField field, String label) {
    for (final PluginFormOption option in field.options) {
      if (option.label == label) return option;
    }
    return null;
  }

  Object? _initialValue(PluginFormField field) =>
      widget.initialValues.containsKey(field.id) ? widget.initialValues[field.id] : field.value;

  void _syncFieldState({required bool resetAll}) {
    if (resetAll) {
      for (final TextEditingController controller in _textControllers.values) {
        controller.dispose();
      }
      _textControllers.clear();
      _checkboxValues.clear();
      _dropdownValues.clear();
      _comboboxValues.clear();
      _pathValues.clear();
      _dateValues.clear();
      _tagValues.clear();
      _fileListValues.clear();
      _sliderValues.clear();
      _colorValues.clear();
      _appValues.clear();
      _shortcutValues.clear();
      for (final FocusNode node in _comboboxFocusNodes.values) {
        node.dispose();
      }
      _comboboxFocusNodes.clear();
      _sectionExpanded.clear();
      _localErrors.clear();
    }
    for (final PluginFormField field in widget.form.fields) {
      if (field.isTextLike || _isNumber(field)) {
        _textControllers.putIfAbsent(field.id, () {
          final Object? value = _initialValue(field);
          final String text = value is String ? value : (value is num ? '$value' : '');
          return TextEditingController(text: text);
        });
      } else if (field.type == 'checkbox') {
        _checkboxValues.putIfAbsent(field.id, () => _initialValue(field) == true);
      } else if (field.type == 'dropdown' || field.type == 'radio') {
        final Object? rawInitial = _initialValue(field);
        final String? initial = rawInitial is String ? rawInitial : null;
        _dropdownValues.putIfAbsent(
          field.id,
          () => field.options.any((PluginFormOption o) => o.value == initial)
              ? initial
              : (field.options.isEmpty ? null : field.options.first.value),
        );
      } else if (field.type == 'combobox') {
        final Object? rawInitial = _initialValue(field);
        final String initial = rawInitial is String ? rawInitial : '';
        _comboboxValues.putIfAbsent(field.id, () => initial);
        _textControllers.putIfAbsent(field.id, () {
          final PluginFormOption? selected = _optionForValue(field, initial);
          return TextEditingController(text: selected?.label ?? initial);
        });
      } else if (_isPath(field)) {
        final Object? initial = _initialValue(field);
        if (field.multiple || field.type == 'dropzone') {
          _fileListValues.putIfAbsent(
            field.id,
            () => initial is List ? initial.whereType<String>().toList(growable: true) : <String>[],
          );
        } else {
          _pathValues.putIfAbsent(field.id, () => initial is String ? initial : '');
        }
      } else if (field.type == 'date' || field.type == 'time' || field.type == 'datetime') {
        final Object? initial = _initialValue(field);
        _dateValues.putIfAbsent(field.id, () => initial is String ? initial : '');
      } else if (field.type == 'tags' || field.type == 'multiselect') {
        _tagValues.putIfAbsent(field.id, () {
          final Object? value = _initialValue(field);
          return value is List ? value.whereType<String>().toSet() : <String>{};
        });
      } else if (field.type == 'slider') {
        final Object? initial = _initialValue(field);
        final double min = field.min?.toDouble() ?? 0;
        final double max = field.max?.toDouble() ?? 100;
        _sliderValues.putIfAbsent(
          field.id,
          () => (initial is num ? initial.toDouble() : min).clamp(min, max).toDouble(),
        );
      } else if (field.type == 'color') {
        final Object? initial = _initialValue(field);
        _colorValues.putIfAbsent(
            field.id,
            () => initial is String
                ? initial
                : '#${Design.accent.toARGB32().toRadixString(16).substring(2).toUpperCase()}');
      } else if (field.type == 'apppicker') {
        final Object? initial = _initialValue(field);
        _appValues.putIfAbsent(field.id, () => initial is String ? initial : '');
      } else if (field.type == 'shortcut') {
        final Object? initial = _initialValue(field);
        _shortcutValues.putIfAbsent(field.id, () => initial is String ? initial : '');
      }
    }
    for (final PluginFormSection section in widget.form.sections) {
      _sectionExpanded.putIfAbsent(section.id, () => true);
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
      } else if (field.type == 'dropdown' || field.type == 'radio') {
        values[field.id] = _dropdownValues[field.id];
      } else if (field.type == 'combobox') {
        values[field.id] =
            _comboboxValues[field.id] ?? (field.allowCustom ? _textControllers[field.id]?.text ?? '' : null);
      } else if (_isPath(field)) {
        values[field.id] = field.multiple || field.type == 'dropzone'
            ? List<String>.of(_fileListValues[field.id] ?? const <String>[])
            : _pathValues[field.id] ?? '';
      } else if (field.type == 'date' || field.type == 'time' || field.type == 'datetime') {
        values[field.id] = _dateValues[field.id] ?? '';
      } else if (field.type == 'tags' || field.type == 'multiselect') {
        values[field.id] = (_tagValues[field.id] ?? <String>{}).toList(growable: false);
      } else if (field.type == 'slider') {
        values[field.id] = _sliderValues[field.id];
      } else if (field.type == 'color') {
        values[field.id] = _colorValues[field.id] ?? '';
      } else if (field.type == 'apppicker') {
        values[field.id] = _appValues[field.id] ?? '';
      } else if (field.type == 'shortcut') {
        values[field.id] = _shortcutValues[field.id] ?? '';
      }
    }
    return values;
  }

  /// A change to [field]: clears its stale error and reports watched fields.
  void _fieldChanged(PluginFormField field) {
    _localErrors.remove(field.id);
    final Map<String, Object?> values = _collectValues();
    setState(() {});
    widget.onStateChanged?.call(values);
    if (field.watch) widget.onChanged?.call(field.id, values);
    if (field.validate && widget.onValidate != null) {
      _validationTimers.remove(field.id)?.cancel();
      _validationTimers[field.id] = Timer(Duration(milliseconds: field.validationDebounceMs), () {
        if (!mounted) return;
        widget.onValidate!(field.id, _collectValues());
      });
    }
  }

  /// Host-side validation. Returns true when the form may submit.
  bool _validate() {
    final Map<String, Object?> values = _collectValues();
    _localErrors.clear();
    for (final PluginFormField field in widget.form.fields) {
      if (!_isVisible(field, values) || !_isEnabled(field, values)) continue;
      final Object? value = values[field.id];
      if (field.validating) {
        _localErrors[field.id] = 'Validation is still in progress';
        continue;
      }
      if (field.error != null || field.valid == false) {
        _localErrors[field.id] = field.error ?? field.validationMessage ?? 'Invalid value';
        continue;
      }
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
      if (value is String) {
        if (field.type == 'json' && value.trim().isNotEmpty) {
          try {
            jsonDecode(value);
          } on FormatException catch (error) {
            _localErrors[field.id] = 'Invalid JSON at character ${error.offset ?? 0}';
            continue;
          }
        }
        if (field.minLength != null && value.length < field.minLength!) {
          _localErrors[field.id] = field.validationMessage ?? 'Must be at least ${field.minLength} characters';
          continue;
        }
        if (field.maxLength != null && value.length > field.maxLength!) {
          _localErrors[field.id] = field.validationMessage ?? 'Must be at most ${field.maxLength} characters';
          continue;
        }
        if (field.pattern != null) {
          try {
            if (!RegExp(field.pattern!).hasMatch(value)) {
              _localErrors[field.id] = field.validationMessage ?? 'Invalid format';
              continue;
            }
          } on FormatException {
            _localErrors[field.id] = 'Invalid validation pattern';
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

  bool _isVisible(PluginFormField field, Map<String, Object?> values) => field.visibleWhen?.matches(values) ?? true;

  bool _isEnabled(PluginFormField field, Map<String, Object?> values) => field.enabledWhen?.matches(values) ?? true;

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
    if ((event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) &&
        HardwareKeyboard.instance.isControlPressed) {
      _submit();
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
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: BorderSide(color: Design.text.withAlpha(16)),
      ),
      suffixIcon: field.validating
          ? Padding(
              padding: const EdgeInsets.all(10),
              child: SizedBox(
                  width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: Design.accent)),
            )
          : field.valid == true && !hasError
              ? const Icon(Icons.check_circle_rounded, size: 15, color: Color(0xFF4FB477))
              : null,
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
                  style: TextStyle(
                      fontSize: 10.5, fontWeight: FontWeight.w700, color: const Color(0xFFE5534B).withAlpha(200))),
            ),
        ],
      ),
    );
  }

  /// Error + description lines rendered under a field's input.
  List<Widget> _fieldFooter(PluginFormField field) {
    final String? error = _errorFor(field);
    return <Widget>[
      if (field.validating)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
            SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.4, color: Design.accent)),
            const SizedBox(width: 5),
            Text('Checkingâ€¦', style: TextStyle(fontSize: 10, color: Design.text.withAlpha(105))),
          ]),
        )
      else if (field.valid == true && error == null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
            const Icon(Icons.check_circle_rounded, size: 11, color: Color(0xFF4FB477)),
            const SizedBox(width: 4),
            Text('Valid', style: TextStyle(fontSize: 10, color: Design.text.withAlpha(105))),
          ]),
        ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(error,
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFFE5534B))),
        ),
      if (field.description.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(field.description,
              style: TextStyle(fontSize: 10.5, color: Design.text.withAlpha(100), height: 1.35)),
        ),
    ];
  }

  /// A read-only "value + trailing button" shell shared by date/file/folder
  /// pickers, styled like the text fields.
  Widget _pickerShell(PluginFormField field,
      {required String value, required IconData icon, required VoidCallback? onPick}) {
    final bool hasError = _errorFor(field) != null;
    return MouseRegion(
      cursor: onPick == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onPick,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: Design.text.withAlpha(10),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: hasError ? const Color(0xFFE5534B).withAlpha(150) : Design.text.withAlpha(24)),
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

  Future<void> _pickTime(PluginFormField field, {required bool includeDate}) async {
    final DateTime now = DateTime.now();
    DateTime date = DateTime.tryParse(_dateValues[field.id] ?? '') ?? now;
    if (includeDate) {
      final DateTime? pickedDate = await showDatePicker(
        context: context,
        initialDate: date,
        firstDate: DateTime(now.year - 100),
        lastDate: DateTime(now.year + 100),
      );
      if (pickedDate == null) return;
      date = pickedDate;
    }
    if (!mounted) return;
    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: date.hour, minute: date.minute),
    );
    if (pickedTime == null) return;
    final String time = '${pickedTime.hour.toString().padLeft(2, '0')}:${pickedTime.minute.toString().padLeft(2, '0')}';
    final String value = includeDate ? '${date.toIso8601String().substring(0, 10)}T$time' : time;
    setState(() => _dateValues[field.id] = value);
    _fieldChanged(field);
  }

  Color _parseColor(String value) {
    String hex = value.trim().replaceFirst('#', '');
    if (hex.length == 3) hex = hex.split('').map((String part) => '$part$part').join();
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.tryParse(hex, radix: 16) ?? Design.accent.toARGB32());
  }

  Future<void> _pickColor(PluginFormField field) async {
    Color selected = _parseColor(_colorValues[field.id] ?? '');
    final Color? result = await showDialog<Color>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(field.label),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: selected,
            enableAlpha: false,
            displayThumbColor: true,
            labelTypes: const <ColorLabelType>[ColorLabelType.hex, ColorLabelType.rgb],
            onColorChanged: (Color value) => selected = value,
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, selected), child: const Text('Use color')),
        ],
      ),
    );
    if (result == null) return;
    final String hex = '#${(result.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
    setState(() => _colorValues[field.id] = hex);
    _fieldChanged(field);
  }

  // @override
  // void onWindowFocus() {
  //   if (_pathPickerOpen) {
  //     unawaited(WindowManager.instance.setAlwaysOnTop(_pathPickerWasAlwaysOnTop));
  //   }
  // }

  Future<void> _pickPath(PluginFormField field) async {
    List<String>? results;
    try {
      _pathPickerWasAlwaysOnTop = await WindowManager.instance.isAlwaysOnTop();
      await WindowManager.instance.setAlwaysOnTop(false);
      if (field.type == 'folderpicker') {
        final DirectoryPicker picker = DirectoryPicker()..title = field.label;
        final String? path = picker.getDirectory()?.path;
        if (path != null) results = <String>[path];
      } else {
        final OpenFilePicker picker = OpenFilePicker()..title = field.label;
        if (field.multiple || field.type == 'dropzone') {
          results = picker.getFiles().map((File file) => file.path).toList(growable: false);
        } else {
          final File? file = picker.getFile();
          if (file != null) results = <String>[file.path];
        }
      }
    } finally {
      await WindowManager.instance.setAlwaysOnTop(_pathPickerWasAlwaysOnTop);
    }
    if (results == null || results.isEmpty) return;
    _acceptPaths(field, results);
  }

  bool _pathAccepted(PluginFormField field, String path) {
    if (field.extensions.isEmpty || Directory(path).existsSync()) return true;
    final String lower = path.toLowerCase();
    return field.extensions.any((String extension) {
      final String normalized = extension.startsWith('.') ? extension : '.$extension';
      return lower.endsWith(normalized);
    });
  }

  void _acceptPaths(PluginFormField field, Iterable<String> incoming) {
    final List<String> accepted = incoming.where((String path) => _pathAccepted(field, path)).toList(growable: false);
    if (accepted.isEmpty) {
      setState(() => _localErrors[field.id] = 'No accepted files were dropped');
      return;
    }
    setState(() {
      if (field.type == 'dropzone' && !field.multiple) {
        _fileListValues[field.id] = <String>[accepted.first];
      } else if (field.multiple || field.type == 'dropzone') {
        _fileListValues[field.id] = <String>{...?_fileListValues[field.id], ...accepted}.toList(growable: true);
      } else {
        _pathValues[field.id] = accepted.first;
      }
    });
    _fieldChanged(field);
  }

  Future<void> _pickApp(PluginFormField field) async {
    final AppCatalogSnapshot snapshot = await AppCatalogService.instance.discover();
    if (!mounted) return;
    if (!snapshot.complete && snapshot.records.isEmpty) {
      setState(() => _localErrors[field.id] = snapshot.error ?? AppCatalogService.instance.unavailableReason);
      return;
    }
    final AppCatalogRecord? selected = await showDialog<AppCatalogRecord>(
      context: context,
      builder: (BuildContext context) => _PluginAppPickerDialog(apps: snapshot.records, title: field.label),
    );
    if (selected == null) return;
    setState(() => _appValues[field.id] = selected.launchTarget);
    _fieldChanged(field);
  }

  Future<void> _recordShortcut(PluginFormField field) async {
    final String? shortcut = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => _PluginShortcutRecorderDialog(title: field.label),
    );
    if (shortcut == null) return;
    setState(() => _shortcutValues[field.id] = shortcut);
    _fieldChanged(field);
  }

  Widget _buildField(PluginFormField field, {required bool autofocus, required bool enabled}) {
    final TextStyle valueStyle = TextStyle(fontSize: 12.5, color: Design.text);
    final bool interactive = enabled && !field.readOnly;

    Widget input;
    if (field.isTextLike || _isNumber(field)) {
      final bool codeEditor = field.type == 'code' || field.type == 'json';
      input = TextField(
        controller: _textControllers[field.id],
        focusNode: autofocus ? _firstFieldFocus : null,
        obscureText: field.type == 'password',
        enabled: enabled,
        readOnly: field.readOnly,
        maxLines: codeEditor ? field.rows : (field.type == 'textarea' ? 4 : 1),
        minLines: codeEditor ? field.rows.clamp(3, 8).toInt() : null,
        keyboardType: _isNumber(field) ? const TextInputType.numberWithOptions(decimal: true, signed: true) : null,
        inputFormatters:
            _isNumber(field) ? <TextInputFormatter>[FilteringTextInputFormatter.allow(RegExp(r'[0-9eE+\-.]'))] : null,
        style: codeEditor
            ? TextStyle(fontFamily: 'Consolas', fontSize: 11.5, height: 1.35, color: Design.text)
            : valueStyle,
        decoration: _decoration(field),
        onChanged: interactive ? (_) => _fieldChanged(field) : null,
        onSubmitted: field.type == 'textarea' || codeEditor || !interactive ? null : (_) => _submit(),
      );
    } else if (field.type == 'dropdown') {
      input = DropdownButtonFormField<String>(
        initialValue: _dropdownValues[field.id],
        focusNode: autofocus ? _firstFieldFocus : null,
        isDense: true,
        style: valueStyle,
        decoration: _decoration(field),
        disabledHint: _dropdownValues[field.id] == null
            ? null
            : Text(
                field.options
                    .firstWhere((PluginFormOption option) => option.value == _dropdownValues[field.id],
                        orElse: () =>
                            PluginFormOption(value: _dropdownValues[field.id]!, label: _dropdownValues[field.id]!))
                    .label,
              ),
        items: <DropdownMenuItem<String>>[
          for (final PluginFormOption option in field.options)
            DropdownMenuItem<String>(value: option.value, child: Text(option.label)),
        ],
        onChanged: interactive
            ? (String? value) {
                setState(() => _dropdownValues[field.id] = value);
                _fieldChanged(field);
              }
            : null,
      );
    } else if (field.type == 'combobox') {
      final FocusNode focusNode = autofocus
          ? _firstFieldFocus
          : _comboboxFocusNodes.putIfAbsent(field.id, () => FocusNode(debugLabel: 'plugin-form-${field.id}'));
      input = RawAutocomplete<PluginFormOption>(
        textEditingController: _textControllers[field.id],
        focusNode: focusNode,
        displayStringForOption: (PluginFormOption option) => option.label,
        optionsBuilder: (TextEditingValue value) {
          final String query = value.text.trim().toLowerCase();
          if (!interactive) return const Iterable<PluginFormOption>.empty();
          return field.options.where((PluginFormOption option) =>
              query.isEmpty ||
              option.label.toLowerCase().contains(query) ||
              option.value.toLowerCase().contains(query));
        },
        onSelected: (PluginFormOption option) {
          _comboboxValues[field.id] = option.value;
          _fieldChanged(field);
        },
        fieldViewBuilder:
            (BuildContext context, TextEditingController controller, FocusNode node, VoidCallback onFieldSubmitted) {
          return TextField(
            controller: controller,
            focusNode: node,
            enabled: enabled,
            readOnly: field.readOnly,
            style: valueStyle,
            decoration: _decoration(field).copyWith(
              suffixIcon: field.optionsLoading
                  ? Padding(
                      padding: const EdgeInsets.all(9),
                      child: SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.5, color: Design.accent),
                      ),
                    )
                  : const Icon(Icons.expand_more_rounded, size: 16),
            ),
            onChanged: interactive
                ? (String value) {
                    final PluginFormOption? exact = _optionForLabel(field, value);
                    _comboboxValues[field.id] = exact?.value ?? (field.allowCustom ? value : null);
                    _fieldChanged(field);
                  }
                : null,
            onSubmitted: interactive ? (_) => onFieldSubmitted() : null,
          );
        },
        optionsViewBuilder: (BuildContext context, AutocompleteOnSelected<PluginFormOption> onSelected,
            Iterable<PluginFormOption> options) {
          final List<PluginFormOption> visible = options.take(8).toList(growable: false);
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 8,
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(7),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420, maxHeight: 240),
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  shrinkWrap: true,
                  itemCount: visible.length,
                  itemBuilder: (BuildContext context, int index) => InkWell(
                    onTap: () => onSelected(visible[index]),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      child: Text(visible[index].label, style: valueStyle),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    } else if (field.type == 'date') {
      input = _pickerShell(
        field,
        value: _dateValues[field.id] ?? '',
        icon: Icons.calendar_month_rounded,
        onPick: interactive ? () => _pickDate(field) : null,
      );
    } else if (field.type == 'time' || field.type == 'datetime') {
      input = _pickerShell(
        field,
        value: _dateValues[field.id] ?? '',
        icon: field.type == 'datetime' ? Icons.event_rounded : Icons.schedule_rounded,
        onPick: interactive ? () => _pickTime(field, includeDate: field.type == 'datetime') : null,
      );
    } else if (_isPath(field)) {
      final List<String> paths = _fileListValues[field.id] ?? const <String>[];
      final Widget picker = field.multiple || field.type == 'dropzone'
          ? _PluginFileDropField(
              field: field,
              paths: paths,
              enabled: interactive,
              onBrowse: () => _pickPath(field),
              onDropped: (List<String> values) => _acceptPaths(field, values),
              onRemove: (String path) {
                setState(() => _fileListValues[field.id]?.remove(path));
                _fieldChanged(field);
              },
            )
          : _pickerShell(
              field,
              value: _pathValues[field.id] ?? '',
              icon: field.type == 'folderpicker' ? Icons.folder_open_rounded : Icons.file_open_rounded,
              onPick: interactive ? () => _pickPath(field) : null,
            );
      input = picker;
    } else if (field.type == 'tags' || field.type == 'multiselect') {
      final Set<String> selected = _tagValues[field.id] ?? <String>{};
      input = Wrap(
        spacing: 5,
        runSpacing: 5,
        children: <Widget>[
          for (final PluginFormOption option in field.options)
            _TagChip(
              label: option.label,
              selected: selected.contains(option.value),
              onTap: interactive
                  ? () {
                      setState(() {
                        selected.contains(option.value) ? selected.remove(option.value) : selected.add(option.value);
                        _tagValues[field.id] = selected;
                      });
                      _fieldChanged(field);
                    }
                  : null,
            ),
        ],
      );
    } else if (field.type == 'radio') {
      final String? selected = _dropdownValues[field.id];
      input = Wrap(
        spacing: 6,
        runSpacing: 6,
        children: <Widget>[
          for (final PluginFormOption option in field.options)
            ChoiceChip(
              label: Text(option.label),
              selected: selected == option.value,
              onSelected: interactive
                  ? (_) {
                      setState(() => _dropdownValues[field.id] = option.value);
                      _fieldChanged(field);
                    }
                  : null,
            ),
        ],
      );
    } else if (field.type == 'slider') {
      final double min = field.min?.toDouble() ?? 0;
      final double max = field.max?.toDouble() ?? 100;
      final double value = (_sliderValues[field.id] ?? min).clamp(min, max).toDouble();
      final double step = (field.step?.toDouble() ?? 1).clamp(0.0001, (max - min).abs()).toDouble();
      input = Row(children: <Widget>[
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: max > min ? ((max - min) / step).round().clamp(1, 1000).toInt() : null,
            onChanged: interactive
                ? (double next) {
                    setState(() => _sliderValues[field.id] = next);
                    _fieldChanged(field);
                  }
                : null,
          ),
        ),
        SizedBox(
          width: 58,
          child: Text(value.toStringAsFixed(step < 1 ? 2 : 0), textAlign: TextAlign.right, style: valueStyle),
        ),
      ]);
    } else if (field.type == 'color') {
      final String value = _colorValues[field.id] ?? '';
      input = _pickerShell(
        field,
        value: value,
        icon: Icons.palette_rounded,
        onPick: interactive ? () => _pickColor(field) : null,
      );
      input = Row(children: <Widget>[
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: _parseColor(value),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Design.text.withAlpha(35)),
          ),
        ),
        const SizedBox(width: 7),
        Expanded(child: input),
      ]);
    } else if (field.type == 'apppicker') {
      input = _pickerShell(
        field,
        value: _appValues[field.id] ?? '',
        icon: Icons.apps_rounded,
        onPick: interactive ? () => _pickApp(field) : null,
      );
    } else if (field.type == 'shortcut') {
      input = _pickerShell(
        field,
        value: _shortcutValues[field.id] ?? '',
        icon: Icons.keyboard_rounded,
        onPick: interactive ? () => _recordShortcut(field) : null,
      );
    } else {
      // checkbox
      final bool checked = _checkboxValues[field.id] ?? false;
      input = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: interactive
              ? () {
                  setState(() => _checkboxValues[field.id] = !checked);
                  _fieldChanged(field);
                }
              : null,
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 18,
                height: 18,
                child: Checkbox(
                  value: checked,
                  focusNode: autofocus ? _firstFieldFocus : null,
                  activeColor: Design.accent,
                  onChanged: interactive
                      ? (bool? value) {
                          setState(() => _checkboxValues[field.id] = value ?? false);
                          _fieldChanged(field);
                        }
                      : null,
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

  List<Widget> _buildFormFields(Map<String, Object?> values) {
    final Map<String, PluginFormSection> sections = <String, PluginFormSection>{
      for (final PluginFormSection section in widget.form.sections) section.id: section,
    };
    final Set<String> renderedSections = <String>{};
    final List<Widget> children = <Widget>[];
    bool assignedAutofocus = false;

    for (final PluginFormField field in widget.form.fields) {
      if (!_isVisible(field, values)) continue;
      final PluginFormSection? section = field.section == null ? null : sections[field.section];
      if (section != null && renderedSections.add(section.id)) {
        final bool expanded = _sectionExpanded[section.id] ?? true;
        children.add(
          Padding(
            padding: EdgeInsets.only(top: children.isEmpty ? 0 : 5, bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(5),
              onTap: section.collapsible ? () => setState(() => _sectionExpanded[section.id] = !expanded) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: <Widget>[
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                      Text(section.title,
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Design.text)),
                      if (section.description.isNotEmpty)
                        Text(section.description,
                            style: TextStyle(fontSize: 10.5, height: 1.3, color: Design.text.withAlpha(100))),
                    ]),
                  ),
                  if (section.collapsible)
                    Icon(expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                        size: 16, color: Design.text.withAlpha(120)),
                ]),
              ),
            ),
          ),
        );
      }
      if (section != null && !(_sectionExpanded[section.id] ?? true)) continue;
      final bool autofocus = !assignedAutofocus;
      assignedAutofocus = true;
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _buildField(field, autofocus: autofocus, enabled: _isEnabled(field, values)),
        ),
      );
    }
    return children;
  }

  @override
  Widget build(BuildContext context) {
    final PluginForm form = widget.form;
    final Map<String, Object?> values = _collectValues();
    return Focus(
      onKeyEvent: _onKey,
      child: WindowsScrollView(
        controller: widget.scrollController,
        draggable: widget.draggable,
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
              if (form.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5534B).withAlpha(18),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFE5534B).withAlpha(70)),
                    ),
                    child: Text(form.error!,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFE5534B))),
                  ),
                ),
              ..._buildFormFields(values),
              const SizedBox(height: 2),
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
                    'Ctrl+Enter to submit · Esc to cancel',
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

class _PluginFileDropField extends StatefulWidget {
  const _PluginFileDropField({
    required this.field,
    required this.paths,
    required this.enabled,
    required this.onBrowse,
    required this.onDropped,
    required this.onRemove,
  });

  final PluginFormField field;
  final List<String> paths;
  final bool enabled;
  final VoidCallback onBrowse;
  final ValueChanged<List<String>> onDropped;
  final ValueChanged<String> onRemove;

  @override
  State<_PluginFileDropField> createState() => _PluginFileDropFieldState();
}

class _PluginFileDropFieldState extends State<_PluginFileDropField> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      enable: widget.enabled,
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (DropDoneDetails details) {
        setState(() => _dragging = false);
        widget.onDropped(details.files.map((DropItem file) => file.path).toList(growable: false));
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: _dragging ? Design.accent.withAlpha(24) : Design.text.withAlpha(8),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: _dragging ? Design.accent.withAlpha(150) : Design.text.withAlpha(28)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Row(children: <Widget>[
            Icon(Icons.attach_file_rounded, size: 15, color: _dragging ? Design.accent : Design.text.withAlpha(125)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _dragging
                    ? 'Release to attach'
                    : (widget.field.placeholder.isEmpty ? 'Drop files here' : widget.field.placeholder),
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Design.text.withAlpha(180)),
              ),
            ),
            TextButton.icon(
              onPressed: widget.enabled ? widget.onBrowse : null,
              icon: const Icon(Icons.folder_open_rounded, size: 13),
              label: const Text('Browse', style: TextStyle(fontSize: 10.5)),
            ),
          ]),
          if (widget.paths.isNotEmpty)
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: <Widget>[
                for (final String path in widget.paths)
                  InputChip(
                    visualDensity: VisualDensity.compact,
                    label: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Text(
                        path.replaceAll('\\', '/').split('/').last,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    onDeleted: widget.enabled ? () => widget.onRemove(path) : null,
                  ),
              ],
            ),
        ]),
      ),
    );
  }
}

class _PluginAppPickerDialog extends StatefulWidget {
  const _PluginAppPickerDialog({required this.apps, required this.title});

  final List<AppCatalogRecord> apps;
  final String title;

  @override
  State<_PluginAppPickerDialog> createState() => _PluginAppPickerDialogState();
}

class _PluginAppPickerDialogState extends State<_PluginAppPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final String query = _query.trim().toLowerCase();
    final List<AppCatalogRecord> apps = widget.apps
        .where((AppCatalogRecord app) => query.isEmpty || '${app.name} ${app.subtitle}'.toLowerCase().contains(query))
        .take(100)
        .toList(growable: false);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 460,
        height: 420,
        child: Column(children: <Widget>[
          TextField(
            autofocus: true,
            decoration:
                const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search applicationsâ€¦'),
            onChanged: (String value) => setState(() => _query = value),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: apps.length,
              itemBuilder: (BuildContext context, int index) {
                final AppCatalogRecord app = apps[index];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.apps_rounded, size: 18),
                  title: Text(app.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle:
                      app.subtitle.isEmpty ? null : Text(app.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => Navigator.pop(context, app),
                );
              },
            ),
          ),
        ]),
      ),
      actions: <Widget>[TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
    );
  }
}

class _PluginShortcutRecorderDialog extends StatelessWidget {
  const _PluginShortcutRecorderDialog({required this.title});

  final String title;

  bool _isModifier(LogicalKeyboardKey key) => <LogicalKeyboardKey>{
        LogicalKeyboardKey.control,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.controlRight,
        LogicalKeyboardKey.shift,
        LogicalKeyboardKey.shiftLeft,
        LogicalKeyboardKey.shiftRight,
        LogicalKeyboardKey.alt,
        LogicalKeyboardKey.altLeft,
        LogicalKeyboardKey.altRight,
        LogicalKeyboardKey.meta,
        LogicalKeyboardKey.metaLeft,
        LogicalKeyboardKey.metaRight,
      }.contains(key);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: Focus(
        autofocus: true,
        onKeyEvent: (_, KeyEvent event) {
          if (event is! KeyDownEvent || _isModifier(event.logicalKey)) return KeyEventResult.handled;
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.pop(context);
            return KeyEventResult.handled;
          }
          final HardwareKeyboard keyboard = HardwareKeyboard.instance;
          final List<String> parts = <String>[
            if (keyboard.isControlPressed) 'Ctrl',
            if (keyboard.isAltPressed) 'Alt',
            if (keyboard.isShiftPressed) 'Shift',
            if (keyboard.isMetaPressed) 'Win',
            event.logicalKey.keyLabel.isEmpty ? event.logicalKey.debugName ?? 'Key' : event.logicalKey.keyLabel,
          ];
          Navigator.pop(context, parts.join('+'));
          return KeyEventResult.handled;
        },
        child: Container(
          width: 360,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
          decoration: BoxDecoration(
            color: Design.text.withAlpha(8),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Design.accent.withAlpha(70)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Icon(Icons.keyboard_rounded, size: 28, color: Design.accent),
            const SizedBox(height: 10),
            Text('Press the shortcut now',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Design.text)),
            const SizedBox(height: 4),
            Text('Escape cancels', style: TextStyle(fontSize: 10.5, color: Design.text.withAlpha(100))),
          ]),
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
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? Design.accent.withAlpha(onTap == null ? 22 : 40) : Design.text.withAlpha(10),
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
