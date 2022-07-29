// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:flutter/material.dart';

import '../../models/settings.dart';
import '../widgets/run_shortcut_widget.dart';

class InterfaceRunConverter extends StatefulWidget {
  const InterfaceRunConverter({Key? key}) : super(key: key);

  @override
  InterfaceRunConverterState createState() => InterfaceRunConverterState();
}

class InterfaceRunConverterState extends State<InterfaceRunConverter> {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Divider(height: 10, thickness: 1),
        Expanded(
          child: Column(
            children: <Widget>[
              RunShortCutInfo(
                  onChanged: (String newStr) {
                    globalSettings.run.calculator = newStr;
                    globalSettings.run.save();
                    setState(() {});
                  },
                  title: "Calculator",
                  value: globalSettings.run.calculator,
                  link: "https://mathjs.org/docs/expressions/syntax.html",
                  tooltip: "It uses mathjs.org",
                  info:
                      "Default shortcut is c , or number and a mathematical symbol. It uses mathjs.org to process query.\nClick on Info Button to see all formats. It can convert units too!",
                  example: <String>["66*20/12", "c 10 inch to cm", "c 2+3*sqrt(4)"]),
              RunShortCutInfo(
                onChanged: (String newStr) {
                  globalSettings.run.currency = newStr;
                  globalSettings.run.save();
                  setState(() {});
                },
                title: "Currency Converter",
                value: globalSettings.run.currency,
                link: "https://github.com/fawazahmed0/currency-api/tree/1/latest/currencies",
                tooltip: "It uses fawazahmed0/currency-api",
                info: "Default shortcut is cur , or Number Currency to Currency. It uses github repo by fawazahmed0 to fetch currency.",
                example: <String>["100 USD TO EUR", "cur 564.23 usd to GBP"],
              ),
            ],
          ),
        ),
        Expanded(
          child: Column(
            children: <Widget>[
              RunShortCutInfo(
                onChanged: (String newStr) {
                  globalSettings.run.color = newStr;
                  globalSettings.run.save();
                  setState(() {});
                },
                title: "Color Converter",
                value: globalSettings.run.color,
                link: "https://www.google.com/search?q=color+picker+online",
                tooltip: "Color picker",
                info: "Default shortcut is col , or common Color prefixes.",
                example: <String>["col #ffffff", "0xfa5b50", "rgba(123,255,44,12)"],
              ),
              RunShortCutInfo(
                onChanged: (String newStr) {
                  globalSettings.run.color = newStr;
                  globalSettings.run.save();
                  setState(() {});
                },
                title: "Time zones",
                value: globalSettings.run.color,
                link: "https://www.google.com/search?q=color+picker+online",
                tooltip: "Time Zone Converter",
                info: "Default is t and it converts to your local time.",
                example: <String>[
                  "t 10 pm EEST",
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  bool tryRegex(String regex) {
    bool worked = true;
    try {
      RegExp(regex, caseSensitive: false).hasMatch("Ciulama");
    } catch (e) {
      worked = false;
      print(e);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: Regex Failed!\n$e"), duration: const Duration(seconds: 4), backgroundColor: Colors.red.shade600));
    }
    return worked;
  }

  bool isNewValValid(String newVal) {
    if (newVal.isEmpty) return false;
    final List<String> listTriggers = newVal.split(';');
    if (listTriggers.length > 1) {
      if (!tryRegex(listTriggers.last)) return false;
    }
    return true;
  }
}
