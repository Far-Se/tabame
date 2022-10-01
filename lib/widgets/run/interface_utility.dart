import 'package:flutter/material.dart';

import '../../models/classes/boxes.dart';
import '../../models/settings.dart';
import '../widgets/run_shortcut_widget.dart';
import '../widgets/text_input.dart';

class InterfaceRunUtility extends StatefulWidget {
  const InterfaceRunUtility({Key? key}) : super(key: key);

  @override
  InterfaceRunUtilityState createState() => InterfaceRunUtilityState();
}

class InterfaceRunUtilityState extends State<InterfaceRunUtility> {
  List<List<String>> runKeys = Boxes().runKeys;

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Expanded(
        child: Column(mainAxisAlignment: MainAxisAlignment.start, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          const Divider(height: 10, thickness: 1),
          RunShortCutInfo(
              value: globalSettings.run.bookmarks,
              onChanged: (String newStr) {
                globalSettings.run.bookmarks = newStr;
                globalSettings.run.save();
                setState(() {});
              },
              title: "Bookmarks",
              link: "",
              tooltip: "Quickly access bookmarks",
              info: "Open links, folders, files and commands",
              example: <String>["b tabame"]),
          RunShortCutInfo(
              value: globalSettings.run.timer,
              onChanged: (String newStr) {
                globalSettings.run.timer = newStr;
                globalSettings.run.save();
                setState(() {});
              },
              title: "Set a Timer",
              link: "",
              tooltip: "Sets Timer",
              info:
                  "Sets a timer in minutes. Parameters: t [minutes] message. you can `t remove message`.\nAlso you can set which type of notification to receive:\na:a for Audio(default), m:MessageBox, n:Notification",
              example: <String>["t 5 a:tea", "t 10 n:shower", "t remove shower", "t 1 m:call somebody", "t 2 reminder"]),
          RunShortCutInfo(
              value: globalSettings.run.setvar,
              onChanged: (String newStr) {
                globalSettings.run.setvar = newStr;
                globalSettings.run.save();
                setState(() {});
              },
              title: "Set Variable",
              link: "",
              tooltip: "Sets Unique Var",
              info: "Sets a unique var, this can be used with Remap keys.",
              example: <String>["v vscode false", r"$vscode false"]),
        ]),
      ),
      Expanded(
          child: Column(children: <Widget>[
        const Divider(height: 10, thickness: 1),
        RunShortCutInfo(
            value: globalSettings.run.keys,
            onChanged: (String newStr) {
              globalSettings.run.keys = newStr;
              globalSettings.run.save();
              setState(() {});
            },
            title: "Send Keys",
            link: "https://docs.microsoft.com/en-us/windows/win32/inputdev/virtual-key-codes",
            tooltip: "Special Key list, without VK_",
            info:
                "Default trigger is k.Sends Input as you saved below. You can use # to press down and ^ to release a key, to trigger special keys put them in {}. to release all use {|}",
            example: <String>["{MEDIA_NEXT_TRACK}", "{#CTRL}{#SHIFT}W", "{#CTRL}A{|}deleted.", "{#CTRL}{#SHIFT}A{^SHIFT}C{|}{ESCAPE}"]),
        ListTile(
          leading: const Icon(Icons.add),
          title: const Text("Add Key Shortcut"),
          onTap: () => setState(() => runKeys.add(<String>["name", "keys"])),
        ),
        ...List<Widget>.generate(runKeys.length, (int index) {
          return Row(
            children: <Widget>[
              const SizedBox(width: 17),
              SizedBox(
                child: InkWell(
                  child: const Icon(Icons.delete),
                  onTap: () {
                    runKeys.removeAt(index);
                    Boxes().runKeys = <List<String>>[...runKeys];
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 1,
                child: TextInput(
                  labelText: "name",
                  value: runKeys[index][0],
                  onChanged: (String e) {
                    if (e.isEmpty) return;
                    runKeys[index][0] = e;
                    Boxes().runKeys = <List<String>>[...runKeys];
                    setState(() {});
                  },
                ),
              ),
              Expanded(
                flex: 3,
                child: TextInput(
                  value: runKeys[index][1],
                  labelText: "Keys",
                  onChanged: (String e) {
                    if (e.isEmpty) return;
                    runKeys[index][1] = e;
                    Boxes().runKeys = <List<String>>[...runKeys];
                    setState(() {});
                  },
                ),
              )
            ],
          );
        })
      ]))
    ]);
  }
}
