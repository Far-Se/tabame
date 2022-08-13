import 'package:flutter/material.dart';

import '../../models/win32/win32.dart';
import 'info_widget.dart';
import 'text_input.dart';

class RunShortCutInfo extends StatelessWidget {
  final Function(String newVal) onChanged;

  final String title;
  final String value;
  final String link;
  final String tooltip;
  final String info;
  final List<String> example;
  const RunShortCutInfo({
    Key? key,
    required this.onChanged,
    required this.title,
    required this.value,
    required this.link,
    required this.tooltip,
    required this.info,
    required this.example,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ListTile(onTap: () {}, title: Text(title, style: Theme.of(context).textTheme.titleLarge)),
        Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ListTile(
              title: TextInput(
                value: value,
                labelText: "Shortcuts",
                onChanged: (String newVal) {
                  if (newVal.isEmpty) return;
                  final List<String> listTriggers = newVal.split(';');
                  if (listTriggers.length > 1) {
                    bool worked = true;
                    try {
                      RegExp(listTriggers.last, caseSensitive: false).hasMatch("Ciulama");
                    } catch (e) {
                      worked = false;
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text("Error: Regex Failed!\n$e"), duration: const Duration(seconds: 4), backgroundColor: Colors.red.shade600));
                    }
                    if (!worked) return;
                  }
                  onChanged(newVal);
                },
              ),
              leading: InfoWidget(tooltip, onTap: () => link.isEmpty ? null : WinUtils.open(link, userpowerShell: true)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text("$info"),
                  const SizedBox(height: 5),
                  Wrap(
                      alignment: WrapAlignment.start,
                      children: List<Widget>.generate(
                          example.length,
                          (int index) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              child: TextSelectionTheme(
                                data: Theme.of(context).textSelectionTheme.copyWith(selectionColor: Colors.red),
                                child: SelectableText(
                                  example[index],
                                  toolbarOptions: const ToolbarOptions(copy: true, cut: true, paste: true, selectAll: true),
                                  style: TextStyle(color: Theme.of(context).backgroundColor, fontSize: 12, height: 1.00001),
                                ),
                              )))),
                ],
              ),
            ),
            const Divider(height: 10, thickness: 1)
          ],
        ),
      ],
    );
  }
}
