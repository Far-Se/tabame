// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:animated_button_bar/animated_button_bar.dart';
import 'package:flutter/material.dart';

import '../../models/utils.dart';
import '../wizardly/file_name_widget.dart';
import '../wizardly/file_size_widget.dart';
import '../wizardly/search_text_widget.dart';

class Wizardly extends StatefulWidget {
  const Wizardly({Key? key}) : super(key: key);

  @override
  WizardlyState createState() => WizardlyState();
}

enum Wizards { folder, name, image, find, cloc }

class WizardPage {
  String title;
  Widget widget;
  WizardPage({
    required this.title,
    required this.widget,
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
    WizardPage(title: "Folder Size", widget: const FileSizeWidget()),
    WizardPage(title: "File Name", widget: const FileNameWidget()),
    WizardPage(title: "Image Work", widget: Container()),
    WizardPage(title: "Find Text", widget: const SearchTextWidget()),
    WizardPage(title: "CLOC", widget: Container()),
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
              children: <ButtonBarEntry>[
                for (int i = 0; i < pages.length; i++)
                  ButtonBarEntry(
                      onTap: () {
                        currentPage = i;
                        setState(() {});
                      },
                      child: Text(pages[i].title)),
              ],
            ),
          ),
        ),
        currentPage < pages.length ? pages[currentPage].widget : Container(),
      ],
    );
  }
}
