import 'package:animated_button_bar/animated_button_bar.dart';
import 'package:flutter/material.dart';

import '../../models/settings.dart';
import 'quickactions_settings.dart';
import 'quickmenu_settings.dart';
import 'quickrun_settings.dart';

class AllQuickMenu extends StatefulWidget {
  const AllQuickMenu({super.key});
  @override
  AllQuickMenuState createState() => AllQuickMenuState();
}

class WizardPage {
  String title;
  Widget widget;
  String? tooltip;
  WizardPage({
    required this.title,
    required this.widget,
  });
}

class AllQuickMenuState extends State<AllQuickMenu> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  final List<WizardPage> pages = <WizardPage>[
    WizardPage(title: "QuickMenu", widget: const QuickmenuSettings()),
    WizardPage(title: "QuickRun", widget: const RunSettings()),
    WizardPage(title: "QuickActions", widget: const QuickActionsSettings()),
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
              children: List<ButtonBarEntry>.generate(pages.length, (int i) => ButtonBarEntry(onTap: () => setState(() => currentPage = i), child: Text(pages[i].title))),
            ),
          ),
        ),
        currentPage < pages.length ? pages[currentPage].widget : Container(),
      ],
    );
  }
}
