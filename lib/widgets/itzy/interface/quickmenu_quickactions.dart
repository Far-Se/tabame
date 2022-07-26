import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/utils.dart';
import '../../../pages/interface.dart';

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
    "HideDesktopFilesButton": Icons.hide_image,
    "ToggleHiddenFilesButton": Icons.folder_off,
    "Deactivated:": Icons.do_disturb,
  };
  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 200, minHeight: 100),
      child: ListTileTheme(
        dense: true,
        style: ListTileStyle.drawer,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
        minVerticalPadding: 0,
        minLeadingWidth: 10,
        child: Column(
          children: <Widget>[
            ListTile(title: Text("QuickActions Order", style: Theme.of(context).textTheme.headline6)),
            Flexible(
              fit: FlexFit.loose,
              child: MouseRegion(
                onEnter: (PointerEnterEvent e) {
                  mainScrollEnabled = false;
                  context.findAncestorStateOfType<InterfaceState>()?.setState(() {});
                },
                onExit: (PointerExitEvent e) {
                  mainScrollEnabled = true;
                  context.findAncestorStateOfType<InterfaceState>()?.setState(() {});
                },
                child: SingleChildScrollView(
                  controller: ScrollController(),
                  child: ReorderableListView.builder(
                    shrinkWrap: true,
                    dragStartBehavior: DragStartBehavior.down,
                    physics: const BouncingScrollPhysics(),
                    scrollController: ScrollController(),
                    itemBuilder: (BuildContext context, int index) {
                      if (topBarItems[index] == "Deactivated:") {
                        return ListTile(
                          leading: Icon(icons[topBarItems[index]], size: 17),
                          key: ValueKey<int>(index),
                          title: Text(
                            topBarItems[index].toUperCaseAll(),
                            style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                          ),
                        );
                      }
                      return ListTile(
                        leading: Icon(icons[topBarItems[index]], size: 17),
                        key: ValueKey<int>(index),
                        title: Text(
                          topBarItems[index].replaceAllMapped(RegExp(r'([A-Z])', caseSensitive: true), (Match match) => ' ${match[0]}'),
                        ),
                      );
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}
