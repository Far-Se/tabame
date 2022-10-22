import 'dart:io';
import 'dart:typed_data';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';
import '../../../models/classes/boxes.dart';
import '../../../models/win32/win32.dart';
import '../../../pages/interface.dart';

class QuickmenuPinnedApps extends StatefulWidget {
  const QuickmenuPinnedApps({Key? key}) : super(key: key);

  @override
  QuickmenuPinnedAppsState createState() => QuickmenuPinnedAppsState();
}

List<String> pinnedApps = Boxes().pinnedApps;
Map<String, Uint8List> pinnedAppsIcons = <String, Uint8List>{};
Future<int> getAllIcons() async {
  for (String app in pinnedApps) {
    pinnedAppsIcons[Win32.getExe(app)] = (await getExecutableIcon(app))!;
  }
  return 0;
}

final Future<int> _getAllIcons = getAllIcons();

class QuickmenuPinnedAppsState extends State<QuickmenuPinnedApps> {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: _getAllIcons,
      builder: (BuildContext context, AsyncSnapshot<Object?> snapshot) {
        if (!snapshot.hasData) return const SizedBox();
        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 200, minHeight: 100),
          child: Column(
            children: <Widget>[
              Center(
                child: ListTile(
                  title: Text("Pinned Files", style: Theme.of(context).textTheme.headline6),
                  trailing: IconButton(
                    icon: const Icon(Icons.add),
                    splashRadius: 20,
                    onPressed: () async {
                      final OpenFilePicker file = OpenFilePicker()
                        ..filterSpecification = <String, String>{'All Files': '*.*', 'Executable (*.exe;*.ps1;*.sh;*.bat)': '*.exe;*.ps1;*.sh;*.bat'}
                        ..defaultFilterIndex = 0
                        ..defaultExtension = 'exe'
                        ..title = 'Select any file';

                      final File? result = file.getFile();
                      if (result != null) {
                        if (Win32.getExe(result.path).contains(".dll")) return;
                        pinnedApps.add(result.path);
                        pinnedAppsIcons[Win32.getExe(result.path)] = (await getExecutableIcon(result.path))!;
                        await Boxes.updateSettings("pinnedApps", pinnedApps);
                        if (!mounted) return;
                        setState(() {});
                      }
                    },
                  ),
                ),
              ),
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
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shrinkWrap: true,
                      dragStartBehavior: DragStartBehavior.down,
                      physics: const AlwaysScrollableScrollPhysics(),
                      scrollController: ScrollController(),
                      itemBuilder: (BuildContext context, int index) {
                        return ListTile(
                          minLeadingWidth: 10,
                          dense: true,
                          style: ListTileStyle.drawer,
                          isThreeLine: false,
                          minVerticalPadding: 0,

                          contentPadding: const EdgeInsets.fromLTRB(20, 0, 30, 0),
                          //
                          key: ValueKey<int>(index),
                          title: Text(Win32.getExe(pinnedApps[index])),
                          leading: Image.memory(pinnedAppsIcons[Win32.getExe(pinnedApps[index])]!,
                              width: 20,
                              errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) => const Icon(
                                    Icons.check_box_outline_blank,
                                    size: 16,
                                  )),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, size: 18),
                            tooltip: "Remove",
                            splashRadius: 20,
                            onPressed: () async {
                              pinnedApps.removeAt(index);
                              await Boxes.updateSettings("pinnedApps", pinnedApps);
                              // pinnedAppsIcons.remove(index);
                              if (!mounted) return;
                              setState(() {});
                            },
                          ),
                        );
                      },
                      itemCount: pinnedApps.length,
                      onReorder: (int oldIndex, int newIndex) {
                        if (oldIndex < newIndex) newIndex -= 1;
                        final String item = pinnedApps.removeAt(oldIndex);
                        pinnedApps.insert(newIndex, item);

                        setState(() {});
                        Boxes.updateSettings("pinnedApps", pinnedApps);
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
