import 'package:flutter/material.dart';

import '../../../models/utils.dart';

class QuickmenuTopbar extends StatefulWidget {
  const QuickmenuTopbar({Key? key}) : super(key: key);

  @override
  QuickmenuTopbarState createState() => QuickmenuTopbarState();
}

class QuickmenuTopbarState extends State<QuickmenuTopbar> {
  List<String> topBarItems = Boxes().topBarWidgets;
  final Map<String, IconData> icons = <String, IconData>{
    "TaskManagerButton": Icons.app_registration,
    "VirtualDesktopButton": Icons.display_settings_outlined,
    "ToggleTaskbarButton": Icons.call_to_action_outlined,
    "PinWindowButton": Icons.pin_end,
    "MicMuteButton": Icons.mic,
    "AlwaysAwakeButton": Icons.running_with_errors,
    "ChangeThemeButton": Icons.theater_comedy_sharp,
    "Deactivated:": Icons.do_disturb,
  };
  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 200, minHeight: 100),
      child: ListTileTheme(
        dense: true,
        style: ListTileStyle.drawer,
        contentPadding: const EdgeInsets.only(left: 10),
        minVerticalPadding: 0,
        minLeadingWidth: 10,
        child: ReorderableListView.builder(
          header: ListTile(title: Text("QuickActions Order", style: Theme.of(context).textTheme.headline6)),
          scrollController: ScrollController(),
          itemBuilder: (BuildContext context, int index) {
            if (topBarItems[index] == "Deactivated:") {
              return ListTile(
                leading: Icon(icons[topBarItems[index]], size: 17),
                // tileColor: Colors.black,
                key: ValueKey<int>(index),
                title: Text(
                  topBarItems[index].toUperCaseAll(),
                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                ),
              );
            }
            return ListTile(leading: Icon(icons[topBarItems[index]], size: 17), key: ValueKey<int>(index), title: Text(topBarItems[index]));
          },
          itemCount: topBarItems.length,
          onReorder: (int oldIndex, int newIndex) {
            if (oldIndex < newIndex) newIndex -= 1;
            final String item = topBarItems.removeAt(oldIndex);
            topBarItems.insert(newIndex, item);
            setState(() {});
            Boxes.updateSettings("topBarWidgets", topBarItems);
          },
        ),
      ),
    );
  }
}