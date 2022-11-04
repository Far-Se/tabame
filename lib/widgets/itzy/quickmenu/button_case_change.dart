import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/classes/saved_maps.dart';
import '../../../models/settings.dart';

class CaseChangeButton extends StatefulWidget {
  const CaseChangeButton({Key? key}) : super(key: key);
  @override
  CaseChangeButtonState createState() => CaseChangeButtonState();
}

class CaseChangeButtonState extends State<CaseChangeButton> {
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
    return SizedBox(
      width: 20,
      height: double.maxFinite,
      child: InkWell(
        child: const Tooltip(message: "Case Change", child: Icon(Icons.text_fields_rounded)),
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
      ),
    );
  }
}

class TimersWidget extends StatefulWidget {
  const TimersWidget({Key? key}) : super(key: key);
  @override
  TimersWidgetState createState() => TimersWidgetState();
}

enum Case {
  camel,
  pascal,
  snake,
  kebab,
  title,
  upper,
  lower,
}

class TimersWidgetState extends State<TimersWidget> {
  final List<BookmarkGroup> bookmarks = Boxes().bookmarks;

  String info = "";
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
          child: SingleChildScrollView(
            controller: ScrollController(),
            child: Material(
              type: MaterialType.transparency,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: FutureBuilder<ClipboardData?>(
                    future: Clipboard.getData("text/plain"),
                    builder: (BuildContext context, AsyncSnapshot<ClipboardData?> snapshot) {
                      if (!snapshot.hasData) return Container(child: const Text("Clipboard is empty, copy some text first!"));
                      if (snapshot.data == null) return Container(child: const Text("Clipboard is empty, copy some text first!"));
                      final String clipboard = snapshot.data?.text ?? "";
                      if (clipboard.isEmpty) return Container(child: const Text("Clipboard is empty, copy some text first!"));
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          TextButton(onPressed: () => convertTo(Case.camel), child: const Text("Convert to camelCase")),
                          TextButton(onPressed: () => convertTo(Case.pascal), child: const Text("Convert to PascalCase")),
                          TextButton(onPressed: () => convertTo(Case.snake), child: const Text("Convert to snake_case")),
                          TextButton(onPressed: () => convertTo(Case.kebab), child: const Text("Convert to kebab-case")),
                          TextButton(onPressed: () => convertTo(Case.title), child: const Text("Convert to Title Case")),
                          TextButton(onPressed: () => convertTo(Case.upper), child: const Text("Convert to UPPERCASE")),
                          TextButton(onPressed: () => convertTo(Case.lower), child: const Text("Convert to lowercase")),
                          Text(info),
                          TextField(
                            maxLines: null,
                            controller: TextEditingController(text: clipboard),
                          )
                        ],
                      );
                    }),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> convertTo(Case type) async {
    final String text = (await Clipboard.getData("text/plain"))?.text ?? "";
    if (text.isEmpty) return;
    const String regex = r"([\w_-]{2,})";
    if (!RegExp(regex).hasMatch(text)) {
      info = "No matches!";
      if (!mounted) return;
      setState(() {});
      return;
    }

    final Iterable<RegExpMatch> matches = RegExp(regex).allMatches(text);
    for (RegExpMatch x in matches) {
      print(x.group(1));
      // switch (type) {
      //   case Case.camel:
      // }
    }
  }
}
