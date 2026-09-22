import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../models/globals.dart';
import '../../../models/settings.dart';
import '../../../models/classes/boxes/quick_menu_box.dart';
import '../../../platform/file_picker_service.dart';
import '../../launcher_actions_panel.dart';
import '../core/launcher_result.dart';
import '../launcher_modal_theme.dart';
import '../plugins/plugin_registry.dart';
import '../result/result_row.dart';
import 'quicklink.dart';
import 'quicklink_runner.dart';
import 'quicklink_search.dart';
import 'quicklink_store.dart';
import 'quicklink_template.dart';

part 'quicklink_editor.dart';
part 'quicklink_manager.dart';

class QuicklinkUi {
  QuicklinkUi._();
  static bool _opening = false;

  static const Map<String, IconData> icons = <String, IconData>{
    'link': Icons.link_rounded,
    'search': Icons.search_rounded,
    'folder': Icons.folder_outlined,
    'file': Icons.insert_drive_file_outlined,
    'code': Icons.code_rounded,
    'book': Icons.menu_book_rounded,
    'video': Icons.play_circle_outline_rounded,
    'music': Icons.music_note_outlined,
    'translate': Icons.translate_rounded,
    'star': Icons.star_outline_rounded,
  };

  static IconData iconFor(LauncherQuicklinkResult result) => result.quicklink != null
      ? icons[result.quicklink!.iconName] ?? Icons.link_rounded
      : switch (result.command!) {
          QuicklinkCommand.create => Icons.add_link_rounded,
          QuicklinkCommand.search => Icons.link_rounded,
          QuicklinkCommand.importFile => Icons.file_download_outlined,
          QuicklinkCommand.exportFile => Icons.file_upload_outlined,
        };

  static Future<void> execute(BuildContext context, LauncherQuicklinkResult result) async {
    await _guard(context, () async {
      if (result.quicklink != null) {
        await open(context, result.quicklink!, argument: result.argument);
        return;
      }
      switch (result.command!) {
        case QuicklinkCommand.create:
          await edit(context);
        case QuicklinkCommand.search:
          await showManager(context);
        case QuicklinkCommand.importFile:
          await importLinks(context);
        case QuicklinkCommand.exportFile:
          await exportLinks(context);
      }
    });
  }

  static Future<void> showManager(BuildContext context) =>
      showDialog<void>(context: context, builder: (_) => const _QuicklinkManager());

  static Future<void> edit(BuildContext context, {Quicklink? link, bool duplicate = false}) => showDialog<void>(
      context: context, barrierDismissible: false, builder: (_) => _QuicklinkEditor(link: link, duplicate: duplicate));

  static Future<void> _guard(BuildContext context, FutureOr<void> Function() operation) async {
    try {
      await operation();
    } catch (error) {
      if (context.mounted)
        await _message(context, 'Quicklinks', error is FormatException ? error.message : error.toString());
    }
  }

  static Future<void> _message(BuildContext context, String title, String message) => showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(child: SelectableText(message)),
            actions: <Widget>[TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('OK'))],
          ));

  static Future<bool> open(BuildContext context, Quicklink link, {String argument = '', String? openWith}) async {
    if (_opening) return false;
    _opening = true;
    try {
      final QuicklinkTemplate template = link.template;
      final String clipboard =
          template.usesClipboard ? (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '' : '';
      if (!context.mounted) return false;
      Map<String, String> values = <String, String>{
        if (template.arguments.isNotEmpty && argument.isNotEmpty) template.arguments.first.key: argument,
      };
      if (template.arguments.any((QuicklinkArgument item) => item.error(values[item.key] ?? '') != null)) {
        final Map<String, String>? entered = await showDialog<Map<String, String>>(
          context: context,
          builder: (_) => _QuicklinkArguments(link: link, template: template, initial: values, clipboard: clipboard),
        );
        if (entered == null || !context.mounted) return false;
        values = entered;
      }
      final String target = template.resolve(values: values, clipboard: clipboard);
      await QuicklinkRunner.open(link, target, openWith: openWith);
      if (Globals.quickMenuPage == QuickMenuPage.launcher) {
        user.launcherSearchText = '';
        await QuickMenuFunctions.hideQuickMenu(launcherActivateLastWin: false);
      }
      return true;
    } catch (error) {
      if (context.mounted)
        await _message(
            context, 'Could not open quicklink', error is FormatException ? error.message : error.toString());
      return false;
    } finally {
      _opening = false;
    }
  }

  static Future<void> importLinks(BuildContext context) async {
    final OpenFilePicker picker = OpenFilePicker()
      ..title = 'Import Quicklinks'
      ..filterSpecification = <String, String>{'Quicklinks JSON': '*.json'};
    if (!FilePickerService.instance.isAvailable) throw UnsupportedError(FilePickerService.instance.unavailableReason);
    final File? file = await picker.getFileAsync();
    if (file == null) return;
    final String contents = await file.readAsString();
    final ({int added, int skipped}) result = QuicklinkStore.importJson(contents);
    if (context.mounted)
      await _message(context, 'Quicklinks imported', '${result.added} added · ${result.skipped} duplicates skipped.');
  }

  static Future<void> exportLinks(BuildContext context) async {
    final String contents = QuicklinkStore.encode(QuicklinkStore.load(force: true));
    final SaveFilePicker picker = SaveFilePicker()
      ..title = 'Export Quicklinks'
      ..fileName = 'quicklinks.json'
      ..defaultExtension = 'json'
      ..filterSpecification = <String, String>{'Quicklinks JSON': '*.json'};
    if (!FilePickerService.instance.isAvailable) throw UnsupportedError(FilePickerService.instance.unavailableReason);
    final File? file = await picker.getFileAsync();
    if (file == null) return;
    await file.writeAsString(contents, flush: true);
    if (context.mounted) await _message(context, 'Quicklinks exported', 'Saved to ${file.path}');
  }

  static Future<void> showLibrary(BuildContext context) async {
    final Quicklink? template = await showDialog<Quicklink>(
      context: context,
      builder: (BuildContext dialogContext) => _QuicklinkDialog(
        title: 'Add from Library',
        subtitle: 'Choose a search, then customize it before saving.',
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: quicklinkLibrary.length,
          itemBuilder: (_, int index) {
            final Quicklink link = quicklinkLibrary[index];
            return ListTile(
              leading: Icon(icons[link.iconName]),
              title: Text(link.name),
              subtitle: Text(link.alias),
              onTap: () => Navigator.pop(dialogContext, link),
            );
          },
        ),
      ),
    );
    if (template != null && context.mounted) await edit(context, link: template, duplicate: true);
  }

  static Future<bool> showActions(BuildContext context, LauncherQuicklinkResult result) async {
    final Quicklink? link = result.quicklink;
    bool opened = false;
    final List<LauncherAction> actions = <LauncherAction>[
      LauncherAction(
          label: link == null ? result.title : 'Open Quicklink',
          icon: Icons.open_in_new_rounded,
          onExecute: (_) async {
            if (link == null) {
              await execute(context, result);
            } else {
              opened = await open(context, link, argument: result.argument);
            }
          }),
      if (link != null) ...<LauncherAction>[
        LauncherAction(
            label: 'Open With…',
            icon: Icons.apps_rounded,
            onExecute: (_) async {
              final String? app = await _pickApplication();
              if (app != null && context.mounted)
                opened = await open(context, link, argument: result.argument, openWith: app);
            }),
        LauncherAction(label: 'Edit Quicklink', icon: Icons.edit_outlined, onExecute: (_) => edit(context, link: link)),
        LauncherAction(
            label: 'Duplicate Quicklink',
            icon: Icons.copy_rounded,
            onExecute: (_) => edit(context, link: link, duplicate: true)),
        LauncherAction(
            label: link.pinned ? 'Unpin Quicklink' : 'Pin Quicklink',
            icon: Icons.push_pin_outlined,
            onExecute: (_) => QuicklinkStore.save(link.copyWith(pinned: !link.pinned))),
        LauncherAction(
            label: link.hidden ? 'Show in Root Search' : 'Hide in Root Search',
            icon: Icons.visibility_outlined,
            onExecute: (_) => QuicklinkStore.save(link.copyWith(hidden: !link.hidden))),
        LauncherAction(
            label: 'Copy Name',
            icon: Icons.text_fields_rounded,
            onExecute: (_) => Clipboard.setData(ClipboardData(text: link.name))),
        LauncherAction(
            label: 'Copy Link',
            icon: Icons.link_rounded,
            onExecute: (_) => Clipboard.setData(ClipboardData(text: link.link))),
        LauncherAction(
            label: 'Delete Quicklink',
            icon: Icons.delete_outline_rounded,
            isDestructive: true,
            onExecute: (_) async {
              final bool? confirmed = await showDialog<bool>(
                  context: context,
                  builder: (BuildContext dialogContext) => AlertDialog(
                        title: const Text('Delete Quicklink?'),
                        content: Text('Remove "${link.name}" from your library?'),
                        actions: <Widget>[
                          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
                          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete')),
                        ],
                      ));
              if (confirmed == true) QuicklinkStore.delete(link.id);
            }),
      ],
      LauncherAction(label: 'Create Quicklink', icon: Icons.add_link_rounded, onExecute: (_) => edit(context)),
      LauncherAction(
          label: 'Add from Library', icon: Icons.library_add_outlined, onExecute: (_) => showLibrary(context)),
    ];
    LauncherAction? selected;
    // Let the existing keyboard-driven action panel select an action, then run
    // it from the still-mounted parent after that panel has closed.
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      builder: (_) => ActionsPanelScaffold(
        item: result,
        hideLauncherAfterAction: false,
        actions: actions
            .map((LauncherAction action) => LauncherAction(
                  label: action.label,
                  icon: action.icon,
                  isDestructive: action.isDestructive,
                  onExecute: (_) {
                    selected = action;
                  },
                ))
            .toList(),
      ),
    );
    if (selected != null && context.mounted) await _guard(context, () => selected!.onExecute(context));
    return opened;
  }

  static Future<String?> _pickApplication() async {
    if (!FilePickerService.instance.isAvailable) throw UnsupportedError(FilePickerService.instance.unavailableReason);
    final OpenFilePicker picker = OpenFilePicker()
      ..title = 'Open With'
      ..filterSpecification = <String, String>{'Applications': '*.exe'};
    return (await picker.getFileAsync())?.path;
  }
}

/// Shared compact shell, using the same fonts, surfaces and borders as launcher actions.
class _QuicklinkDialog extends StatelessWidget {
  const _QuicklinkDialog(
      {required this.title, required this.child, this.subtitle = '', this.actions = const <Widget>[], this.onSave});

  final String title;
  final String subtitle;
  final Widget child;
  final List<Widget> actions;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final LauncherModalTokens tokens = LauncherModalTokens.of(context);
    final ThemeData theme = Theme.of(context);
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context),
        if (onSave != null) const SingleActivator(LogicalKeyboardKey.enter, control: true): onSave!,
      },
      child: Center(
        child: Material(
          type: MaterialType.transparency,
          child: LauncherModalFrame(
            tokens: tokens,
            width: 620,
            maxHeight: math.max(180.0, MediaQuery.sizeOf(context).height - 32),
            margin: const EdgeInsets.all(16),
            child: Theme(
              data: theme.copyWith(
                textTheme: theme.textTheme.apply(
                    fontFamily: tokens.text().fontFamily, bodyColor: tokens.onSurface, displayColor: tokens.onSurface),
                inputDecorationTheme: InputDecorationTheme(
                  isDense: true,
                  filled: true,
                  fillColor: tokens.onSurface.withAlpha(8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(tokens.controlRadius)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(children: <Widget>[
                    Expanded(
                        child: LauncherModalHeader(
                            tokens: tokens,
                            icon: Icon(Icons.link_rounded, color: tokens.accent, size: 18),
                            title: title,
                            subtitle: subtitle)),
                    IconButton(
                        tooltip: 'Close (Esc)',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded, size: 18)),
                    const SizedBox(width: 8),
                  ]),
                  Divider(height: 1, color: tokens.onSurface.withAlpha(22)),
                  Flexible(child: child),
                  if (actions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: actions),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
