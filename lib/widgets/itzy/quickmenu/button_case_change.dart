import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/classes/saved_maps.dart';
import '../../../models/settings.dart';
import '../../widgets/quick_actions_item.dart';

class CaseChangeButton extends StatefulWidget {
  const CaseChangeButton({super.key});
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
    return QuickActionItem(
      message: "Case Change",
      icon: const Icon(Icons.text_fields_rounded),
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

enum Case {
  camel,
  pascal,
  snake,
  kebab,
  title,
  upper,
  lower,
}

class StringUtils {
  static bool isLowerCase(String s) {
    return s == s.toLowerCase();
  }

  ///
  /// Checks if the given string [s] is upper case
  ///
  static bool isUpperCase(String s) {
    return s == s.toUpperCase();
  }

  static String camelCaseToUpperUnderscore(String s) {
    StringBuffer sb = StringBuffer();
    bool first = true;
    for (int rune in s.runes) {
      String char = String.fromCharCode(rune);
      if (isUpperCase(char) && !first) {
        sb.write('_');
        sb.write(char.toUpperCase());
      } else {
        first = false;
        sb.write(char.toUpperCase());
      }
    }
    return sb.toString();
  }

  ///
  /// Transfers the given String [s] from camcelCase to lowerCaseUnderscore
  /// Example : helloWorld => hello_world
  ///
  static String camelCaseToLowerUnderscore(String s) {
    StringBuffer sb = StringBuffer();
    bool first = true;
    for (int rune in s.runes) {
      String char = String.fromCharCode(rune);
      if (isUpperCase(char) && !first) {
        if (char != '_') {
          sb.write('_');
        }
        sb.write(char.toLowerCase());
      } else {
        first = false;
        sb.write(char.toLowerCase());
      }
    }
    return sb.toString();
  }

  static String capitalize(String s, {bool allWords = false}) {
    if (s.isEmpty) {
      return '';
    }
    s = s.trim();
    if (allWords) {
      List<String> words = s.split(' ');
      List<String> capitalized = <String>[];
      for (String w in words) {
        capitalized.add(capitalize(w));
      }
      return capitalized.join(' ');
    } else {
      return s.substring(0, 1).toUpperCase() + s.substring(1).toLowerCase();
    }
  }

  static String toPascalCase(String s) {
    final List<String> separatedWords = s.split(RegExp(r'[!@#<>?":`~;[\]\\|=+)(*&^%-\s_]+'));
    String newString = '';

    for (final String word in separatedWords) {
      newString += word[0].toUpperCase() + word.substring(1).toLowerCase();
    }

    return newString;
  }
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
                          Center(child: Text(info)),
                          TextField(maxLines: null, controller: TextEditingController(text: clipboard))
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

  Future<String> convertTo(Case type) async {
    String text = (await Clipboard.getData("text/plain"))?.text ?? "";
    if (text.isEmpty) return "";
    const String regex = r"([\w_-]{2,})";
    if (!RegExp(regex).hasMatch(text)) {
      info = "No matches!";
      if (!mounted) return text;
      setState(() {});
      return text;
    }

    final Iterable<RegExpMatch> matches = RegExp(regex, caseSensitive: false).allMatches(text);
    for (RegExpMatch x in matches) {
      String word = x.group(1)!;
      switch (type) {
        case Case.camel:
          //camelcase
          final RegExpMatch? camelCase = RegExp(r'[a-z][A-Z][a-z]', caseSensitive: true).firstMatch(word);
          if (camelCase != null) {
            word = word.toLowerCase();
            word = word.replaceRange(camelCase.start, camelCase.end, camelCase.group(0)!);
            break;
          }
          //kebab snake
          if (word.contains(RegExp(r'([\-_])([a-z])'))) {
            word = word.toLowerCase();
            word = word.replaceFirstMapped(RegExp(r'([\-_])([a-z])'), (Match match) {
              return match.group(2)!.toUpperCase();
            });
            break;
          }
          //pascal
          if (word.startsWith(RegExp(r'[A-Z][a-z0-9]', caseSensitive: true))) {
            final RegExpMatch? firstCase = RegExp(r'[a-z][A-Z]', caseSensitive: true).firstMatch(word);
            word = word.toLowerCase();
            if (firstCase != null) {
              word = word.replaceRange(firstCase.start, firstCase.end, firstCase.group(0)!);
            }
            break;
          }
          word = word.toLowerCase();
          break;
        case Case.pascal:
          //pascal
          final RegExpMatch? pascalCase = RegExp(r'^[A-Z].*?[a-z][A-Z][a-z]', caseSensitive: true).firstMatch(word);
          if (pascalCase != null) {
            break;
          }
          //camelCase
          final RegExpMatch? camelCase = RegExp(r'[a-z][A-Z][a-z]', caseSensitive: true).firstMatch(word);
          if (camelCase != null) {
            word = word.toUpperCaseFirst();
            word = word.replaceRange(camelCase.start, camelCase.end, camelCase.group(0)!);

            break;
          }
          //kebab snake
          if (word.contains(RegExp(r'([\-_])([a-z])'))) {
            word = word.toLowerCase();
            word = word.toUpperCaseFirst();
            word = word.replaceFirstMapped(RegExp(r'([\-_])([a-z])'), (Match match) {
              return match.group(2)!.toUpperCase();
            });
            break;
          }
          word = word.toUpperCaseFirst();
          break;
        case Case.snake:
          //camelCase pascan
          final RegExpMatch? camelCase = RegExp(r'([a-z])([A-Z][a-z])', caseSensitive: true).firstMatch(word);
          if (camelCase != null) {
            word = '${word.substring(0, camelCase.start)}${camelCase.group(1)!}_${camelCase.group(2)!}${word.substring(camelCase.end)}';
            word = word.toLowerCase();
            break;
          }
          word = word.replaceAll('-', '_');
          word = word.toLowerCase();
          break;
        case Case.kebab:
          //camelCase pascan
          final RegExpMatch? camelCase = RegExp(r'([a-z])([A-Z][a-z])', caseSensitive: true).firstMatch(word);
          if (camelCase != null) {
            word = '${word.substring(0, camelCase.start)}${camelCase.group(1)!}-${camelCase.group(2)!}${word.substring(camelCase.end)}';
            word = word.toLowerCase();
            break;
          }
          word = word.replaceAll('_', '-');
          word = word.toLowerCase();
          break;
        case Case.title:
          word = word.replaceAllMapped(RegExp(r'[A-Z]\w'), (Match e) => ' ${e.group(0)}');
          word = word.replaceAll(RegExp(r'[\-_]'), ' ');
          word = word.toUpperCaseEach();
          word = word.trim();
          break;
        case Case.upper:
          word = word.toUpperCase();
          break;
        case Case.lower:
          word = word.toLowerCase();
          break;
      }
      text = text.replaceFirst(x.group(1)!, word);
    }
    Clipboard.setData(ClipboardData(text: text));
    info = "💾 Text copied to clipboard";
    setState(() {});
    return text;
  }
}
