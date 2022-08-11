// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:animated_button_bar/animated_button_bar.dart';
import 'package:flutter/material.dart';

import '../../models/settings.dart';
import '../wizardly/rename_files.dart';
import '../wizardly/folder_size_scan.dart';
import '../wizardly/project_overview.dart';
import '../wizardly/find_text.dart';

class Wizardly extends StatefulWidget {
  const Wizardly({Key? key}) : super(key: key);

  @override
  WizardlyState createState() => WizardlyState();
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

class WizardlyState extends State<Wizardly> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  final List<WizardPage> pages = <WizardPage>[
    WizardPage(title: "Find Text in Folder", widget: const SearchTextWidget(), tooltip: "Find Text in folders"),
    WizardPage(title: "Project Overview", widget: const ProjectOverviewWidget(), tooltip: "Count line of Code\nView project breakdown"),
    WizardPage(title: "Rename Files", widget: const FileNameWidget(), tooltip: "Rename files in bulk"),
    WizardPage(title: "Folder Size Scan", widget: const FileSizeWidget(), tooltip: "See how big folders and subfolder are"),
    // WizardPage(title: "Image Work", widget: Container()),
  ];
  int currentPage = 0;
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: Maa.start,
      mainAxisSize: MainAxisSize.max,
      children: <Widget>[
        // ...List<Widget>.generate(globalSettings.args.length, (int index) => InfoText(globalSettings.args[index])),
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
        currentPage < pages.length
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10.0),
                child: pages[currentPage].widget,
              )
            : Container(),
      ],
    );
  }
}
