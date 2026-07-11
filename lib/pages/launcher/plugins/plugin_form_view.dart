import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/settings.dart';
import '../../../widgets/widgets/windows_scroll.dart';
import 'plugin_icons.dart';
import 'plugin_protocol.dart';

/// Renders a plugin's `form` view: a titled stack of dense inputs (text /
/// password / textarea / dropdown / checkbox) with a submit CTA.
///
/// Focus lives inside the form while it is shown (the launcher releases its
/// search-field focus grab). Enter in a single-line field submits; Escape
/// cancels via [onCancel]. Field state survives re-rendered frames as long as
/// the field ids stay the same, so a plugin can refresh other parts of the
/// frame without wiping the user's input.
class PluginFormView extends StatefulWidget {
  const PluginFormView({
    super.key,
    required this.form,
    required this.onSubmit,
    required this.onCancel,
  });

  final PluginForm form;
  final void Function(Map<String, Object?> values) onSubmit;
  final VoidCallback onCancel;

  @override
  State<PluginFormView> createState() => _PluginFormViewState();
}

class _PluginFormViewState extends State<PluginFormView> {
  final Map<String, TextEditingController> _textControllers = <String, TextEditingController>{};
  final Map<String, bool> _checkboxValues = <String, bool>{};
  final Map<String, String?> _dropdownValues = <String, String?>{};
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

  void _syncFieldState({required bool resetAll}) {
    if (resetAll) {
      for (final TextEditingController controller in _textControllers.values) {
        controller.dispose();
      }
      _textControllers.clear();
      _checkboxValues.clear();
      _dropdownValues.clear();
    }
    for (final PluginFormField field in widget.form.fields) {
      if (field.isTextLike) {
        _textControllers.putIfAbsent(
            field.id, () => TextEditingController(text: field.value is String ? field.value as String? : ''));
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
      }
    }
  }

  void _submit() {
    final Map<String, Object?> values = <String, Object?>{};
    for (final PluginFormField field in widget.form.fields) {
      if (field.isTextLike) {
        values[field.id] = _textControllers[field.id]?.text ?? '';
      } else if (field.type == 'checkbox') {
        values[field.id] = _checkboxValues[field.id] ?? false;
      } else if (field.type == 'dropdown') {
        values[field.id] = _dropdownValues[field.id];
      }
    }
    widget.onSubmit(values);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onCancel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  InputDecoration _decoration(PluginFormField field) {
    return InputDecoration(
      hintText: field.placeholder,
      hintStyle: TextStyle(fontSize: 12, color: Design.text.withAlpha(80)),
      isDense: true,
      filled: true,
      fillColor: Design.text.withAlpha(10),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: BorderSide(color: Design.text.withAlpha(24)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: BorderSide(color: Design.accent.withAlpha(160)),
      ),
    );
  }

  Widget _fieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          color: Design.text.withAlpha(140),
        ),
      ),
    );
  }

  Widget _buildField(PluginFormField field, {required bool autofocus}) {
    final TextStyle valueStyle = TextStyle(fontSize: 12.5, color: Design.text);

    if (field.isTextLike) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _fieldLabel(field.label),
          TextField(
            controller: _textControllers[field.id],
            focusNode: autofocus ? _firstFieldFocus : null,
            obscureText: field.type == 'password',
            maxLines: field.type == 'textarea' ? 4 : 1,
            style: valueStyle,
            decoration: _decoration(field),
            onSubmitted: field.type == 'textarea' ? null : (_) => _submit(),
          ),
        ],
      );
    }

    if (field.type == 'dropdown') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _fieldLabel(field.label),
          DropdownButtonFormField<String>(
            initialValue: _dropdownValues[field.id],
            focusNode: autofocus ? _firstFieldFocus : null,
            isDense: true,
            style: valueStyle,
            decoration: _decoration(field),
            items: <DropdownMenuItem<String>>[
              for (final PluginFormOption option in field.options)
                DropdownMenuItem<String>(value: option.value, child: Text(option.label)),
            ],
            onChanged: (String? value) => setState(() => _dropdownValues[field.id] = value),
          ),
        ],
      );
    }

    // checkbox
    final bool checked = _checkboxValues[field.id] ?? false;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => setState(() => _checkboxValues[field.id] = !checked),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 18,
              height: 18,
              child: Checkbox(
                value: checked,
                focusNode: autofocus ? _firstFieldFocus : null,
                activeColor: Design.accent,
                onChanged: (bool? value) => setState(() => _checkboxValues[field.id] = value ?? false),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              field.label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Design.text.withAlpha(200)),
            ),
          ],
        ),
      ),
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
                  _SubmitButton(label: form.submitLabel, onTap: _submit),
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

/// The form's primary CTA — the one place a subtle accent gradient is allowed
/// per the design language.
class _SubmitButton extends StatelessWidget {
  const _SubmitButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: <Color>[Design.accent.withAlpha(230), Design.accent.withAlpha(180)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: Design.accent.withAlpha(120)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(PluginIcons.resolve('check'), size: 13, color: Colors.white),
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
