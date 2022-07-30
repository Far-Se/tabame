import 'package:animated_button_bar/animated_button_bar.dart';
import 'package:flutter/material.dart';

import '../../models/settings.dart';
import '../run/interface_converters.dart';
import '../run/interface_processors.dart';
import '../run/interface_utility.dart';
import '../widgets/info_text.dart';

class WizardPage {
  String title;
  Widget widget;
  String? tooltip;
  WizardPage({
    required this.title,
    required this.widget,
    this.tooltip = "",
  });
}

class RunSettings extends StatefulWidget {
  const RunSettings({Key? key}) : super(key: key);

  @override
  RunSettingsState createState() => RunSettingsState();
}

class RunSettingsState extends State<RunSettings> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  final List<WizardPage> pages = <WizardPage>[
    WizardPage(title: "Converters", widget: const InterfaceRunConverter(), tooltip: "Calculator, Currency, Color"),
    WizardPage(title: "Processors", widget: const InterfaceRunProcessors(), tooltip: "Regex, Lorem, Json, Encoders"),
    WizardPage(title: "Utility", widget: const InterfaceRunUtility(), tooltip: "Shortcuts, Timer"),
    // WizardPage(title: "Image Work", widget: Container()),
  ];
  int currentPage = 0;
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: Maa.start,
      mainAxisSize: MainAxisSize.max,
      children: <Widget>[
        SizedBox(
          height: 80,
          child: Padding(
            padding: const EdgeInsets.all(1),
            child: AnimatedButtonBar(
              foregroundColor: Theme.of(context).colorScheme.primary,
              radius: 8.0,
              padding: const EdgeInsets.all(16.0),
              invertedSelection: true,
              children: List<ButtonBarEntry>.generate(
                  pages.length,
                  (int i) => ButtonBarEntry(
                      onTap: () => setState(() => currentPage = i), child: Tooltip(message: pages[i].tooltip, verticalOffset: 20, child: Text(pages[i].title)))),
            ),
          ),
        ),
        const InfoText("On triggers, last one is always regex aware!"),
        currentPage < pages.length ? pages[currentPage].widget : Container(),
        const SizedBox(height: 20)
      ],
    );
  }
}
