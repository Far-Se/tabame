import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../widgets/mouse_scroll_widget.dart';
import '../../widgets/quick_actions_item.dart';

class MemosButton extends StatefulWidget {
  const MemosButton({Key? key}) : super(key: key);
  @override
  MemosButtonState createState() => MemosButtonState();
}

class MemosButtonState extends State<MemosButton> {
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
      message: "Memos",
      icon: const Icon(Icons.note_alt_outlined),
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
  const TimersWidget({Key? key}) : super(key: key);
  @override
  TimersWidgetState createState() => TimersWidgetState();
}

class TimersWidgetState extends State<TimersWidget> {
  final List<List<String>> memos = Boxes().runMemos;
  TextEditingController titleController = TextEditingController();
  TextEditingController messageController = TextEditingController();

  int memoSelected = -1;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
    titleController.dispose();
    messageController.dispose();
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
          constraints: const BoxConstraints(maxWidth: 280, maxHeight: 300),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
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
          child: MouseScrollWidget(
            scrollDirection: Axis.vertical,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Material(
                type: MaterialType.transparency,
                child: memoSelected != -1
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          MouseScrollWidget(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: <Widget>[
                                SizedBox(
                                    width: 40,
                                    child: IconButton(splashRadius: 15, icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => memoSelected = -1))),
                                Text(memos.elementAt(memoSelected)[0].isEmpty ? "New Item" : memos.elementAt(memoSelected)[0],
                                    style: Theme.of(context).textTheme.headline6?.copyWith(height: 1))
                              ],
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    memos.removeAt(memoSelected);
                                    memoSelected = -1;
                                    Boxes().runMemos = <List<String>>[...memos];
                                    setState(() {});
                                  },
                                  icon: const Icon(Icons.delete),
                                  label: const Text("Delete", style: TextStyle(height: 1)),
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    memos.elementAt(memoSelected)[0] = titleController.text;
                                    memos.elementAt(memoSelected)[1] = messageController.text;
                                    Boxes().runMemos = <List<String>>[...memos];
                                    memoSelected = -1;
                                    setState(() {});
                                  },
                                  icon: const Icon(Icons.save),
                                  label: const Text("Save", style: TextStyle(height: 1)),
                                ),
                              )
                            ],
                          ),
                          TextField(
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                              hintText: "Title",
                              labelText: "Title",
                              hintStyle: const TextStyle(fontSize: 12),
                              border: UnderlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            controller: titleController,
                          ),
                          TextField(
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                              hintText: "Message",
                              labelText: "Message",
                              hintStyle: const TextStyle(fontSize: 12),
                              border: UnderlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            maxLines: null,
                            controller: messageController,
                          )
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const Text("Memos:", style: TextStyle(fontSize: 17)),
                              SizedBox(
                                width: 100,
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    memos.add(<String>["", ""]);
                                    memoSelected = memos.length - 1;
                                    titleController.text = memos.elementAt(memoSelected)[0];
                                    messageController.text = memos.elementAt(memoSelected)[1];
                                    setState(() {});
                                  },
                                  icon: const Icon(Icons.add),
                                  label: const Text("Create", style: TextStyle(height: 1)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          ...List<Widget>.generate(
                            memos.length,
                            (int index) => SizedBox(
                              width: 280,
                              // height: 300,
                              child: InkWell(
                                onTap: () {
                                  memoSelected = index;
                                  titleController.text = memos.elementAt(memoSelected)[0];
                                  messageController.text = memos.elementAt(memoSelected)[1];
                                  setState(() {});
                                },
                                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5), child: Text("${memos.elementAt(index)[0]}")),
                              ),
                            ),
                          ),
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
