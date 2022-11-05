import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:win32/win32.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/classes/saved_maps.dart';
import '../../../models/settings.dart';
import '../../../models/win32/window.dart';
import '../../../models/window_watcher.dart';
import '../../widgets/quick_actions_item.dart';

class WorkSpaceButton extends StatefulWidget {
  const WorkSpaceButton({Key? key}) : super(key: key);
  @override
  WorkSpaceButtonState createState() => WorkSpaceButtonState();
}

class WorkSpaceButtonState extends State<WorkSpaceButton> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message: "Workspaces",
      icon: const Icon(Icons.workspaces),
      onTap: () async {
        showModalBottomSheet<void>(
          context: context,
          anchorPoint: const Offset(100, 200),
          elevation: 0,
          backgroundColor: Colors.transparent,
          barrierColor: Colors.transparent,
          constraints: const BoxConstraints(maxWidth: 280),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          enableDrag: true,
          isScrollControlled: true,
          builder: (BuildContext context) {
            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: FractionallySizedBox(
                heightFactor: 0.85,
                child: Listener(
                  onPointerDown: (PointerDownEvent event) {
                    if (event.kind == PointerDeviceKind.mouse) {
                      if (event.buttons == kSecondaryMouseButton) {
                        Navigator.pop(context);
                      }
                    }
                  },
                  child: const Padding(padding: EdgeInsets.all(2.0), child: WorkspacesWidget()),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class WorkspacesWidget extends StatefulWidget {
  const WorkspacesWidget({Key? key}) : super(key: key);
  @override
  WorkspacesWidgetState createState() => WorkspacesWidgetState();
}

class WorkspacesWidgetState extends State<WorkspacesWidget> {
  final List<Workspaces> workspaces = Boxes.workspaces;
  final List<int> selectedWins = <int>[];
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          // height: MediaQuery.of(context).size.height,
          height: double.infinity,
          width: 280,
          constraints: const BoxConstraints(maxWidth: 280, maxHeight: 350),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            // border: Border.all(color: Theme.of(context).backgroundColor.withOpacity(0.5), width: 1),
            gradient: LinearGradient(
              colors: <Color>[
                Theme.of(context).backgroundColor,
                Theme.of(context).backgroundColor.withAlpha(globalSettings.themeColors.gradientAlpha),
                Theme.of(context).backgroundColor,
              ],
              stops: <double>[0, 0.4, 1],
              end: Alignment.bottomRight,
            ),
            boxShadow: <BoxShadow>[
              const BoxShadow(color: Colors.black26, offset: Offset(3, 5), blurStyle: BlurStyle.inner),
            ],
            color: Theme.of(context).backgroundColor,
          ),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Container(
              height: 350,
              child: workspaces.isEmpty
                  ? Text("\nYou do not have any Workspaces. Open Settings, go to Views and create one!", style: Theme.of(context).textTheme.titleMedium)
                  : SingleChildScrollView(
                      child: Material(
                        type: MaterialType.transparency,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: List<Widget>.generate(workspaces.length, (int index) {
                            final Workspaces workspace = workspaces.elementAt(index);
                            int totalFound = 0;
                            for (WorkspaceWindow win in workspace.windows) {
                              for (Window wWatch in WindowWatcher.list) {
                                if (win.exe == wWatch.process.exe) {
                                  if (win.title.isNotEmpty) {
                                    if (RegExp(win.title, caseSensitive: false).hasMatch(wWatch.title)) {
                                      totalFound++;
                                      break;
                                    }
                                  } else {
                                    totalFound++;
                                    break;
                                  }
                                }
                              }
                            }
                            return ListTile(
                              minVerticalPadding: 0,
                              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                              visualDensity: VisualDensity.compact,
                              onTap: () {
                                for (WorkspaceWindow win in workspace.windows) {
                                  for (Window wWatch in WindowWatcher.list) {
                                    if (win.exe == wWatch.process.exe) {
                                      if (win.title.isNotEmpty) {
                                        if (RegExp(win.title, caseSensitive: false).hasMatch(wWatch.title)) {
                                          SetWindowPos(wWatch.hWnd, HWND_TOPMOST, win.posX, win.posY, win.width, win.height, SWP_NOACTIVATE);
                                          SetWindowPos(wWatch.hWnd, HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOACTIVATE | SWP_NOMOVE | SWP_NOSIZE);
                                          break;
                                        }
                                      } else {
                                        SetWindowPos(wWatch.hWnd, HWND_TOPMOST, win.posX, win.posY, win.width, win.height, SWP_NOACTIVATE);
                                        SetWindowPos(wWatch.hWnd, HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOACTIVATE | SWP_NOMOVE | SWP_NOSIZE);
                                        break;
                                      }
                                    }
                                  }
                                }
                              },
                              title: Text(workspace.name),
                              subtitle: totalFound == workspace.windows.length
                                  ? const Text("All Windows Present")
                                  : Text("${workspace.windows.length - totalFound} windows missing"),
                            );
                          }),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
