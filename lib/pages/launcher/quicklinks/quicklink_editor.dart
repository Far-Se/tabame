part of 'quicklink_ui.dart';

class _QuicklinkEditor extends StatefulWidget {
  const _QuicklinkEditor({this.link, this.duplicate = false});
  final Quicklink? link;
  final bool duplicate;

  @override
  State<_QuicklinkEditor> createState() => _QuicklinkEditorState();
}

class _QuicklinkEditorState extends State<_QuicklinkEditor> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _link = TextEditingController();
  final TextEditingController _alias = TextEditingController();
  final TextEditingController _tags = TextEditingController();
  final TextEditingController _openWith = TextEditingController();
  late final String _id;
  String _icon = 'link';
  String? _error;
  bool _pinned = false;
  bool _hidden = false;
  bool _saving = false;

  bool get _isExisting => widget.link != null && widget.link!.id.isNotEmpty && !widget.duplicate;

  @override
  void initState() {
    super.initState();
    final Quicklink? link = widget.link;
    _id = _isExisting ? link!.id : const Uuid().v4();
    if (link != null) {
      _name.text = widget.duplicate && link.id.isNotEmpty ? '${link.name} Copy' : link.name;
      _link.text = link.link;
      _alias.text = widget.duplicate && link.id.isNotEmpty ? '' : link.alias;
      _tags.text = link.tags.join(', ');
      _openWith.text = link.openWith;
      _icon = QuicklinkUi.icons.containsKey(link.iconName) ? link.iconName : 'link';
      _pinned = link.pinned;
      _hidden = link.hidden;
    } else {
      unawaited(_autofill());
    }
  }

  @override
  void dispose() {
    for (final TextEditingController controller in <TextEditingController>[_name, _link, _alias, _tags, _openWith]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _autofill({bool replace = false}) async {
    try {
      final String value = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim() ?? '';
      if (!mounted || (!replace && _link.text.isNotEmpty) || value.isEmpty) return;
      QuicklinkTemplate(value).validate();
      setState(() {
        _link.text = value;
        if (_name.text.isEmpty) {
          _name.text =
              QuicklinkTemplate.isLocalPath(value) ? p.windows.basename(value) : Uri.tryParse(value)?.host ?? '';
        }
      });
    } catch (_) {
      // The clipboard commonly holds prose; leave the new editor empty.
      if (replace && mounted) setState(() => _error = 'Copy a URL or an absolute file or folder path first.');
    }
  }

  void _save() {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final Quicklink link = Quicklink(
        id: _id,
        name: _name.text.trim(),
        link: _link.text.trim(),
        alias: _alias.text.trim(),
        tags: _tags.text
            .split(',')
            .map((String tag) => tag.trim())
            .where((String tag) => tag.isNotEmpty)
            .toSet()
            .toList(),
        openWith: _openWith.text.trim(),
        iconName: _icon,
        pinned: _pinned,
        hidden: _hidden,
      );
      if (link.openWith.contains(RegExp(r'["\r\n\x00]')))
        throw const FormatException('Enter the application path without quotes or arguments.');
      if (link.alias.isNotEmpty && PluginRegistry.matchKeyword('${link.alias} ') != null) {
        throw const FormatException('That alias belongs to a launcher plugin.');
      }
      QuicklinkStore.save(link);
      Navigator.pop(context);
    } catch (error) {
      setState(() {
        _error = error is FormatException ? error.message : error.toString();
        _saving = false;
      });
    }
  }

  void _insert(String placeholder) {
    final TextSelection selection = _link.selection;
    final int start = selection.isValid ? selection.start : _link.text.length;
    final int end = selection.isValid ? selection.end : start;
    _link.value = TextEditingValue(
      text: _link.text.replaceRange(start, end, placeholder),
      selection: TextSelection.collapsed(offset: start + placeholder.length),
    );
    setState(() {});
  }

  Widget _field(TextEditingController controller, String label,
          {String? hint, String? helper, bool autofocus = false, int maxLines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextField(
          controller: controller,
          autofocus: autofocus,
          maxLines: maxLines,
          onChanged: (_) => setState(() => _error = null),
          decoration: InputDecoration(labelText: label, hintText: hint, helperText: helper, helperMaxLines: 3),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return _QuicklinkDialog(
      title: _isExisting ? 'Edit Quicklink' : 'Create Quicklink',
      subtitle: 'Open your everyday destinations from the launcher.',
      onSave: _save,
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Save Quicklink · Ctrl+Enter')),
      ],
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _field(_name, 'Name', hint: 'Search Google', autofocus: true),
            _field(_link, 'Link', hint: 'https://www.google.com/search?q={argument}', maxLines: 3),
            Wrap(spacing: 8, runSpacing: 4, children: <Widget>[
              TextButton.icon(
                  onPressed: () => _autofill(replace: true),
                  icon: const Icon(Icons.content_paste_rounded, size: 16),
                  label: const Text('Paste link')),
              TextButton.icon(
                  onPressed: () => _insert('{argument name="Query"}'),
                  icon: const Icon(Icons.input_rounded, size: 16),
                  label: const Text('Add argument')),
              TextButton.icon(
                  onPressed: () => QuicklinkUi._guard(context, () async {
                        final File? file = await (OpenFilePicker()..title = 'Link to File').getFileAsync();
                        if (file != null && mounted)
                          setState(() {
                            _link.text = file.path;
                            _icon = 'file';
                          });
                      }),
                  icon: const Icon(Icons.insert_drive_file_outlined, size: 16),
                  label: const Text('File')),
              TextButton.icon(
                  onPressed: () => QuicklinkUi._guard(context, () async {
                        final Directory? folder =
                            await (DirectoryPicker()..title = 'Link to Folder').getDirectoryAsync();
                        if (folder != null && mounted)
                          setState(() {
                            _link.text = folder.path;
                            _icon = 'folder';
                          });
                      }),
                  icon: const Icon(Icons.folder_outlined, size: 16),
                  label: const Text('Folder')),
            ]),
            const SizedBox(height: 12),
            _field(_alias, 'Alias (optional)',
                hint: 'google', helper: 'Type the alias followed by text to fill the first argument.'),
            _field(_tags, 'Tags (optional)', hint: 'work, research', helper: 'Separate tags with commas.'),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Expanded(
                  child: _field(_openWith, 'Open With (optional)',
                      hint: r'C:\Apps\Browser\browser.exe', helper: 'Leave empty to use the default app.')),
              IconButton(
                  tooltip: 'Choose application',
                  icon: const Icon(Icons.folder_open_rounded),
                  onPressed: () => QuicklinkUi._guard(context, () async {
                        final String? app = await QuicklinkUi._pickApplication();
                        if (app != null && mounted) setState(() => _openWith.text = app);
                      })),
            ]),
            DropdownButtonFormField<String>(
              key: ValueKey<String>(_icon),
              initialValue: _icon,
              decoration: const InputDecoration(labelText: 'Icon'),
              items: QuicklinkUi.icons.entries
                  .map((MapEntry<String, IconData> entry) => DropdownMenuItem<String>(
                        value: entry.key,
                        child: Row(children: <Widget>[
                          Icon(entry.value, size: 18),
                          const SizedBox(width: 10),
                          Text(entry.key[0].toUpperCase() + entry.key.substring(1)),
                        ]),
                      ))
                  .toList(),
              onChanged: (String? value) {
                if (value != null) setState(() => _icon = value);
              },
            ),
            CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Pin in Quicklinks'),
                value: _pinned,
                onChanged: (bool? value) => setState(() => _pinned = value ?? false)),
            CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Show in root search'),
                value: !_hidden,
                onChanged: (bool? value) => setState(() => _hidden = !(value ?? true))),
            const ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('Arguments and placeholders'),
              childrenPadding: EdgeInsets.only(bottom: 12),
              children: <Widget>[
                SelectableText('Use up to three inputs. Repeating a name reuses its value.\n\n'
                    '{argument name="Query"}\n'
                    '{argument name="Language" default="en"}\n'
                    '{argument name="Sort" options="newest,oldest"}\n\n'
                    'Also available: {clipboard}, {date}, {time}, {datetime}, {day}, {uuid}.\n'
                    'Custom date: {date format="yyyy-MM-dd" offset="+1d"}.\n'
                    'Modifiers: trim, uppercase, lowercase, percent-encode, json-stringify, raw.\n\n'
                    'URL arguments are encoded automatically. Use {clipboard | raw} to insert an existing URL unchanged.'),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
    );
  }
}

class _QuicklinkArguments extends StatefulWidget {
  const _QuicklinkArguments(
      {required this.link, required this.template, required this.initial, required this.clipboard});
  final Quicklink link;
  final QuicklinkTemplate template;
  final Map<String, String> initial;
  final String clipboard;

  @override
  State<_QuicklinkArguments> createState() => _QuicklinkArgumentsState();
}

class _QuicklinkArgumentsState extends State<_QuicklinkArguments> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _controllers = <String, TextEditingController>{
    for (final QuicklinkArgument argument in widget.template.arguments)
      argument.key: TextEditingController(text: widget.initial[argument.key] ?? argument.defaultValue ?? ''),
  };

  Map<String, String> get _values =>
      _controllers.map((String key, TextEditingController value) => MapEntry<String, String>(key, value.text));

  @override
  void dispose() {
    for (final TextEditingController controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (_form.currentState!.validate()) Navigator.pop(context, _values);
  }

  @override
  Widget build(BuildContext context) {
    String preview;
    try {
      preview = widget.template.resolve(values: _values, clipboard: widget.clipboard);
    } catch (_) {
      preview = widget.link.link;
    }
    final List<QuicklinkArgument> arguments = widget.template.arguments;
    final int missingIndex =
        arguments.indexWhere((QuicklinkArgument argument) => argument.error(_controllers[argument.key]!.text) != null);
    return _QuicklinkDialog(
      title: widget.link.name,
      subtitle: 'Fill in the arguments to open this quicklink.',
      onSave: _submit,
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Open Quicklink')),
      ],
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _form,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            for (final (int index, QuicklinkArgument argument) in arguments.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: argument.options.isNotEmpty
                    ? DropdownButtonFormField<String>(
                        initialValue: argument.options.contains(_controllers[argument.key]!.text)
                            ? _controllers[argument.key]!.text
                            : null,
                        autofocus: index == missingIndex,
                        decoration: InputDecoration(labelText: argument.name),
                        items: argument.options
                            .map((String option) => DropdownMenuItem<String>(value: option, child: Text(option)))
                            .toList(),
                        validator: (String? value) => argument.error(value ?? ''),
                        onChanged: (String? value) => setState(() => _controllers[argument.key]!.text = value ?? ''),
                      )
                    : TextFormField(
                        controller: _controllers[argument.key],
                        autofocus: index == missingIndex,
                        decoration: InputDecoration(
                            labelText: argument.name,
                            helperText: argument.defaultValue == null ? null : 'Default: ${argument.defaultValue}'),
                        validator: (String? value) => argument.error(value ?? ''),
                        onChanged: (_) => setState(() {}),
                        onFieldSubmitted: (_) => _submit(),
                      ),
              ),
            Text('Destination', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            SelectableText(preview, style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ),
    );
  }
}
