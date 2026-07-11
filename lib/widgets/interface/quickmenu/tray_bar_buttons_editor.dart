import 'package:flutter/material.dart';

import '../../../models/classes/saved_maps.dart';
import '../../../models/settings.dart';
import '../../widgets/text_input.dart';

/// Curated set of icons offered when picking a tray bar button's glyph.
const List<int> trayBarButtonIconChoices = <int>[
  0xe870, // apps
  0xe5d2, // touch_app
  0xe30a, // keyboard
  0xe89e, // open_in_new
  0xe8b8, // settings
  0xe3ae, // desktop_windows
  0xe1a7, // volume_up
  0xe30d, // language
  0xe3af, // wallpaper
  0xe8f5, // terminal / power
  0xe1c1, // videocam
  0xe873, // archive
];

/// Opens the edit dialog for a single [TrayBarButton], calling [onSaved] with
/// the updated copy if the user confirms.
Future<void> editTrayBarButton(
  BuildContext context, {
  required TrayBarButton button,
  required void Function(TrayBarButton updated) onSaved,
}) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext context) => _TrayBarButtonEditDialog(button: button.copyWith(), onSaved: onSaved),
  );
}

class _TrayBarButtonEditDialog extends StatefulWidget {
  const _TrayBarButtonEditDialog({required this.button, required this.onSaved});

  final TrayBarButton button;
  final void Function(TrayBarButton updated) onSaved;

  @override
  State<_TrayBarButtonEditDialog> createState() => _TrayBarButtonEditDialogState();
}

class _TrayBarButtonEditDialogState extends State<_TrayBarButtonEditDialog> {
  late TrayBarButton button = widget.button;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text("Edit Tray Bar Button",
                  style: TextStyle(fontSize: Design.baseFontSize + 4, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              CustomTextInput(
                labelText: "Display Name",
                value: button.name,
                onChanged: (String v) => setState(() => button.name = v),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  for (final int codePoint in trayBarButtonIconChoices)
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(() => button.iconCodePoint = codePoint),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: button.iconCodePoint == codePoint
                              ? Design.accent.withAlpha(40)
                              : Design.text.withAlpha(10),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: button.iconCodePoint == codePoint
                                ? Design.accent.withAlpha(120)
                                : Design.text.withAlpha(20),
                          ),
                        ),
                        // ignore: non_const_argument_for_const_parameter
                        child: Icon(IconData(codePoint, fontFamily: 'MaterialIcons'), size: 18, color: Design.text),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(
                  color: Design.text.withAlpha(10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Design.text.withAlpha(20)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    value: button.type,
                    onChanged: (String? v) => setState(() => button.type = v ?? "Hotkey"),
                    items: trayBarButtonTypes
                        .map((String t) => DropdownMenuItem<String>(value: t, child: Text(t)))
                        .toList(),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              CustomTextInput(
                labelText: button.type == "Open" ? "Path / URL / Command" : "Key sequence",
                hintText: button.type == "Open" ? "e.g. https://example.com" : "e.g. {#WIN}A{^WIN}",
                value: button.value,
                onChanged: (String v) => setState(() => button.value = v),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("Cancel")),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      widget.onSaved(button);
                      Navigator.of(context).pop();
                    },
                    child: const Text("Save"),
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
