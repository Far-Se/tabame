import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/classes/saved_maps.dart';
import '../../../models/settings.dart';
import '../../../models/win32/win32.dart';
import '../../widgets/quick_actions_item.dart';

class BookmarksButton extends StatefulWidget {
  const BookmarksButton({super.key});
  @override
  BookmarksButtonState createState() => BookmarksButtonState();
}

class BookmarksButtonState extends State<BookmarksButton> {
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
      message: "Bookmarks",
      icon: const Icon(Icons.folder_copy_outlined),
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
                  child: const Padding(
                    padding: EdgeInsets.all(2.0),
                    child: TimersWidget(),
                  ),
                ),
              ),
            );
          },
        );
        return;
      },
    );
  }
}

class TimersWidget extends StatefulWidget {
  const TimersWidget({super.key});
  @override
  TimersWidgetState createState() => TimersWidgetState();
}

class TimersWidgetState extends State<TimersWidget> {
  final List<BookmarkGroup> bookmarks = Boxes().bookmarks;
  @override
  void initState() {
    bookmarks;
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
          height: double.infinity,
          width: 280,
          constraints: const BoxConstraints(maxWidth: 280, maxHeight: 350),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            gradient: LinearGradient(
              colors: <Color>[
                Theme.of(context).colorScheme.surface,
                Theme.of(context).colorScheme.surface.withAlpha(globalSettings.themeColors.gradientAlpha),
                Theme.of(context).colorScheme.surface,
              ],
              stops: <double>[0, 0.4, 1],
              end: Alignment.bottomRight,
            ),
            boxShadow: <BoxShadow>[
              const BoxShadow(color: Colors.black26, offset: Offset(3, 5), blurStyle: BlurStyle.inner),
            ],
            color: Theme.of(context).colorScheme.surface,
          ),
          child: SingleChildScrollView(
            controller: ScrollController(),
            child: Material(
              type: MaterialType.transparency,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: bookmarks.isEmpty
                    ? const Text("You have no bookmarks")
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          ...List<Widget>.generate(
                            bookmarks.length,
                            (int index) => Column(
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 5),
                                  child: Text(
                                    "${bookmarks[index].emoji} ${bookmarks[index].title} (${bookmarks[index].bookmarks.length})",
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                ...List<Widget>.generate(
                                    bookmarks[index].bookmarks.length,
                                    (int mark) => InkWell(
                                          onTap: () {
                                            WinUtils.open(bookmarks[index].bookmarks[mark].stringToExecute, parseParamaters: true);
                                            QuickMenuFunctions.toggleQuickMenu(visible: false);
                                            // Navigator.of(context).pop();
                                          },
                                          child: Text(
                                            "${bookmarks[index].bookmarks[mark].emoji} ${bookmarks[index].bookmarks[mark].title}",
                                            style: const TextStyle(fontSize: 16),
                                          ),
                                        )),
                                const SizedBox(height: 10),
                                const Divider(height: 3, thickness: 1),
                              ],
                            ),
                          )
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
