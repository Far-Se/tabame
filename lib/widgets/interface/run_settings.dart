import 'package:animated_button_bar/animated_button_bar.dart';
import 'package:flutter/material.dart';

import '../../models/settings.dart';
import '../run/interface_api_setup.dart';
import '../run/interface_general.dart';

class RunSettings extends StatefulWidget {
  const RunSettings({Key? key}) : super(key: key);

  @override
  RunSettingsState createState() => RunSettingsState();
}

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
    WizardPage(title: "General", widget: const InterfaceGeneral(), tooltip: "General Settings"),
    WizardPage(title: "API Setup", widget: InterfaceApiSetup(), tooltip: "Set up API"),
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
              foregroundColor: Color(globalSettings.theme.accentColor),
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
        currentPage < pages.length ? pages[currentPage].widget : Container(),
      ],
    );
  }
}
