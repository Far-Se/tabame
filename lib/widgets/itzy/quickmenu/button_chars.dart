import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../widgets/quick_actions_item.dart';

class CustomCharsButton extends StatefulWidget {
  const CustomCharsButton({Key? key}) : super(key: key);
  @override
  CustomCharsButtonState createState() => CustomCharsButtonState();
}

final Map<String, List<String>> customChars = <String, List<String>>{
  "Currency": <String>['฿', 'в', '¢', '₡', 'č', '₫', '€', 'ƒ', '₴', '₭', 'ł', 'л', '₼', '£', '₽', '₹', '៛', '﷼', r'$', '₪', '₮', '₺', '₩', '¥', 'z'],
  "Math": <String>['₀', '⁰', '₁', '¹', '₂', '²', '₃', '³', '₄', '⁴', '₅', '⁵', '₆', '⁶', '₇', '⁷', '₈', '⁸', '₉', '⁹', 'π', 'ú', '≤', '≥', '≠', '≈', '≙', '±', '₊', '⁺'],
  "French": <String>['à', 'â', 'á', 'ä', 'ã', 'æ', 'ç', 'é', 'è', 'ê', 'ë', '€', 'î', 'ï', 'í', 'ì', 'ô', 'ö', 'ó', 'ò', 'õ', 'œ', 'û', 'ù', 'ü', 'ú', 'ÿ', 'ý'],
  "Iceland": <String>['á', 'æ', 'ð', 'é', 'ó', 'ö', 'ú', 'ý', 'þ'],
  "Spain": <String>['á', 'é', '€', 'í', 'ñ', 'ó', 'ú', 'ü', '¿', '?'],
  "Maori": <String>['ā', 'ē', 'ī', 'ō', r'$', 'ū'],
  "Pinyin": <String>[
    'ā',
    'á',
    'ǎ',
    'à',
    'a',
    'ē',
    'é',
    'ě',
    'è',
    'e',
    'ī',
    'í',
    'ǐ',
    'ì',
    'i',
    'ō',
    'ó',
    'ǒ',
    'ò',
    'o',
    'ū',
    'ú',
    'ǔ',
    'ù',
    'u',
    'ǖ',
    'ǘ',
    'ǚ',
    'ǜ',
    'ü'
  ],
  "Turkish": <String>['â', 'ç', 'ë', '€', 'ğ', 'ı', 'İ', 'î', 'ö', 'ô', 'ş', '₺', 'ü', 'û'],
  "Polish": <String>['ą', 'ć', 'ę', '€', 'ł', 'ń', 'ó', 'ś', 'ż', 'ź'],
  "Portuguese": <String>['á', 'à', 'â', 'ã', 'ç', 'é', 'ê', '€', 'í', 'ô', 'ó', 'õ'],
  "Slovak": <String>['á', 'ä', 'č', 'ď', 'é', '€', 'í', 'ľ', 'ĺ', 'ň', 'ó', 'ô', 'ŕ', 'š', 'ť', 'ú', 'ý', 'ž'],
  "Czech": <String>['á', 'č', 'ď', 'ě', 'é', 'í', 'ň', 'ó', 'ř', 'š', 'ť', 'ů', 'ú', 'ý', 'ž'],
  "German": <String>['ä', '€', 'ö', 'ß', 'ü'],
  "Hungarian": <String>['á', 'é', 'í', 'ó', 'ő', 'ö', 'ú', 'ű', 'ü'],
  "Romanian": <String>['ă', 'â', 'î', 'ș', 'ț'],
  "Italian": <String>['à', 'è', 'é', '€', 'ì', 'í', 'ò', 'ó', 'ù', 'ú'],
};

class CustomCharsButtonState extends State<CustomCharsButton> {
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
      message: "Custom Chars",
      icon: const Icon(Icons.format_quote),
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
              child: const FractionallySizedBox(
                heightFactor: 0.85,
                child: Padding(
                  padding: EdgeInsets.all(2.0),
                  child: TimersWidget(),
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
  final TextEditingController textField = TextEditingController();
  List<String> savedChars = <String>[];
  List<String> disabledSets = <String>[];
  @override
  void initState() {
    super.initState();
    savedChars = Boxes.pref.getStringList("savedChars") ?? <String>[];
    disabledSets = Boxes.pref.getStringList("disabledSets") ?? <String>[];
  }

  @override
  void dispose() {
    super.dispose();
    textField.dispose();
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
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text("Saved", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                hintText: "New Character",
                                hintStyle: TextStyle(fontSize: 12),
                                border: InputBorder.none),
                            controller: textField,
                          ),
                        ),
                        OutlinedButton.icon(
                            onPressed: () {
                              savedChars.add(textField.text);
                              Boxes.pref.setStringList("savedChars", savedChars);
                              setState(() {});
                            },
                            icon: const Icon(Icons.add),
                            label: const Text("Save", style: TextStyle(height: 1)))
                      ],
                    ),
                    Wrap(
                      children: List<Widget>.generate(
                          savedChars.length,
                          (int index) => Listener(
                                onPointerDown: (PointerDownEvent event) {
                                  if (event.kind == PointerDeviceKind.mouse) {
                                    if (event.buttons == kSecondaryMouseButton) {
                                      savedChars.removeAt(index);
                                      Boxes.pref.setStringList("savedChars", savedChars);
                                      setState(() {});
                                    }
                                  }
                                },
                                child: InkWell(
                                  onTap: () {
                                    Clipboard.setData(ClipboardData(text: savedChars.elementAt(index)));
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                      content: Text("Copied ${savedChars.elementAt(index)}"),
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                      margin: EdgeInsets.only(bottom: MediaQuery.of(context).size.height - 70, right: 20, left: 20),
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                                      duration: const Duration(seconds: 1),
                                    ));
                                    setState(() {});
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                                    child: Text(savedChars.elementAt(index)),
                                  ),
                                ),
                              )),
                    ),
                    const Divider(height: 10, thickness: 1),
                    ...List<Widget>.generate(
                      customChars.length,
                      (int index) {
                        final String name = customChars.keys.elementAt(index);
                        if (disabledSets.contains(name)) return Container();
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            InkWell(
                                onTap: () {
                                  disabledSets.toggle(name);
                                  Boxes.pref.setStringList("disabledSets", disabledSets);
                                  print(disabledSets);
                                  setState(() {});
                                },
                                child: Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
                            Wrap(
                              children: List<Widget>.generate(
                                  customChars.values.elementAt(index).length,
                                  (int i) => InkWell(
                                        onTap: () {
                                          Clipboard.setData(ClipboardData(text: customChars.values.elementAt(index).elementAt(i)));
                                          Navigator.pop(context);
                                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                            content: Text("Copied ${customChars.values.elementAt(index).elementAt(i)}"),
                                            behavior: SnackBarBehavior.floating,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(24),
                                            ),
                                            margin: EdgeInsets.only(bottom: MediaQuery.of(context).size.height - 70, right: 20, left: 20),
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                                            duration: const Duration(seconds: 1),
                                          ));
                                          setState(() {});
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                                          child: Text(customChars.values.elementAt(index).elementAt(i)),
                                        ),
                                      )),
                            )
                          ],
                        );
                      },
                    ),
                    if (disabledSets.isNotEmpty)
                      Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Divider(height: 10, thickness: 1),
                          const Text("Disabled:", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                          ...List<Widget>.generate(
                            disabledSets.length,
                            (int index) {
                              final String name = disabledSets.elementAt(index);
                              return Column(
                                mainAxisAlignment: MainAxisAlignment.start,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: <Widget>[
                                  InkWell(
                                      onTap: () {
                                        print("xxx");
                                        disabledSets.toggle(name);
                                        Boxes.pref.setStringList("disabledSets", disabledSets);
                                        setState(() {});
                                      },
                                      child: Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
                                ],
                              );
                            },
                          )
                        ],
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
