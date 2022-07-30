import 'package:flutter/material.dart';

import '../../models/classes/boxes.dart';
import '../../models/settings.dart';
import '../widgets/run_shortcut_widget.dart';
import '../widgets/text_box.dart';

class InterfaceRunProcessors extends StatefulWidget {
  const InterfaceRunProcessors({Key? key}) : super(key: key);

  @override
  InterfaceRunProcessorsState createState() => InterfaceRunProcessorsState();
}

class InterfaceRunProcessorsState extends State<InterfaceRunProcessors> {
  final List<List<String>> runShortcuts = Boxes().runShortcuts;
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.start, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            const Divider(height: 10, thickness: 1),
            RunShortCutInfo(
                value: globalSettings.run.regex,
                onChanged: (String newStr) {
                  globalSettings.run.regex = newStr;
                  globalSettings.run.save();
                  setState(() {});
                },
                title: "Regex",
                link: "https://regex101.com",
                tooltip: "Website to test regex skills",
                info: "Default shortcut is rgx. It has 3 sub commands: setText, match, replace. Default is case insensitive.",
                example: <String>["rgx setText This project has 10 bugs", r"rgx match (\d+) bugs", r"rgx replace /(\d+) bugs/ /0 bugs, $1 fixed/"]),
            RunShortCutInfo(
                value: globalSettings.run.lorem,
                onChanged: (String newStr) {
                  globalSettings.run.lorem = newStr;
                  globalSettings.run.save();
                  setState(() {});
                },
                title: "Lorem Ipsum Generator",
                link: "https://loripsum.net/",
                tooltip: "It uses loripsum.net.",
                info: "Default Shortcut is lorem. You can specify number of pharagraphs and the length: short, medium, long, verylong",
                example: <String>["3 short", "3 long headers", "3 short plaintext"]),
            RunShortCutInfo(
                value: globalSettings.run.encoders,
                onChanged: (String newStr) {
                  globalSettings.run.encoders = newStr;
                  globalSettings.run.save();
                  setState(() {});
                },
                title: "Encoders",
                link: "https://multiencoder.com/",
                tooltip: "For more encoders",
                info: "Default is enc. You can use ! to encode and @ to decode, you can serialize them in [].\n Encoders are: url,base,rot13,hex,bin,ascii,@html",
                example: <String>["!base test", "@url %20", "[@base,@rot13,!url] Z25vbnpy"]),
          ]),
        ),
        Expanded(
            child: Column(
          children: <Widget>[
            const Divider(height: 10, thickness: 1),
            RunShortCutInfo(
                value: globalSettings.run.shortcut,
                onChanged: (String newStr) {
                  globalSettings.run.shortcut = newStr;
                  globalSettings.run.save();
                  setState(() {});
                },
                title: "Shortcuts",
                link: "https://github.com/far-se/tabame/",
                tooltip: "No link",
                info: "Default is s. Sub-commands are add/remove. You can add {params} to modify link.",
                example: <String>["s add pub https://pub.dev/packages?q={params}", "s pub win32", "s remove pub"]),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text("Add Shortcut"),
              onTap: () => setState(() => runShortcuts.add(<String>["name", "linl"])),
            ),
            ...List<Widget>.generate(runShortcuts.length, (int index) {
              return Row(
                children: <Widget>[
                  const SizedBox(width: 17),
                  SizedBox(
                    child: InkWell(
                      child: const Icon(Icons.delete),
                      onTap: () {
                        runShortcuts.removeAt(index);
                        Boxes().runShortcuts = <List<String>>[...runShortcuts];
                        setState(() {});
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 1,
                    child: TextInput(
                      labelText: "shortcut",
                      value: runShortcuts[index][0],
                      onChanged: (String e) {
                        if (e.isEmpty) return;
                        runShortcuts[index][0] = e;
                        Boxes().runShortcuts = <List<String>>[...runShortcuts];
                        setState(() {});
                      },
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: TextInput(
                      value: runShortcuts[index][1],
                      labelText: "link",
                      onChanged: (String e) {
                        if (e.isEmpty) return;
                        runShortcuts[index][1] = e;
                        Boxes().runShortcuts = <List<String>>[...runShortcuts];
                        setState(() {});
                      },
                    ),
                  )
                ],
              );
            })
          ],
        ))
      ],
    );
  }
}
