import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:tabamewin32/tabamewin32.dart';

import '../../models/classes/boxes.dart';
import '../../models/settings.dart';

class Trktivity extends StatefulWidget {
  const Trktivity({Key? key}) : super(key: key);
  @override
  TrktivityState createState() => TrktivityState();
}

class TrktivityState extends State<Trktivity> {
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
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        CheckboxListTile(
          onChanged: (bool? e) => setState(() {
            globalSettings.trktivityEnabled = !globalSettings.trktivityEnabled;
            Boxes.updateSettings("trktivityEnabled", globalSettings.trktivityEnabled);
            enableTrcktivity(globalSettings.trktivityEnabled);
          }),
          controlAffinity: ListTileControlAffinity.leading,
          value: globalSettings.trktivityEnabled,
          title: const Text("Trktivity"),
        ),
        if (!globalSettings.trktivityEnabled)
          const Markdown(
            shrinkWrap: true,
            data: '''
With Trktivity you can track your activity per minute/hour/day/week. 

It records keystrokes, mouse movement and active Window.
''',
          ),
      ],
    );
  }
}
