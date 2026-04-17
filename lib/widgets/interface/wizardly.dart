// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../models/settings.dart';
import '../wizardly/hosts_editor.dart';
import '../wizardly/rename_files.dart';
import '../wizardly/folder_size_scan.dart';
import '../wizardly/project_overview.dart';
import '../wizardly/find_text.dart';

class Wizardly extends StatefulWidget {
  const Wizardly({super.key});

  @override
  WizardlyState createState() => WizardlyState();
}

class WizardPage {
  String title;
  Widget widget;
  IconData icon;
  String? tooltip;
  WizardPage({
    required this.title,
    required this.widget,
    required this.icon,
    this.tooltip = "",
  });
}

class WizardlyState extends State<Wizardly> {
  int wizzardID = 1;
  final ScrollController _scrollController = ScrollController();
  @override
  void initState() {
    super.initState();
    if (!globalSettings.args.contains("-wizardly")) {
      pages.add(WizardPage(
          title: "Hosts Editor", widget: const HostsEditor(), icon: Icons.dns_rounded, tooltip: "Edit hosts File"));
    }
    wizzardID = Random().nextInt(4) + 1;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  final List<WizardPage> pages = <WizardPage>[
    WizardPage(
        title: "Search Text",
        widget: const SearchTextWidget(),
        icon: Icons.search_rounded,
        tooltip: "Find Text in folders"),
    WizardPage(
        title: "Project Overview",
        widget: const ProjectOverviewWidget(),
        icon: Icons.analytics_rounded,
        tooltip: "Count line of Code\nView project breakdown"),
    WizardPage(
        title: "Rename Files",
        widget: const FileNameWidget(),
        icon: Icons.drive_file_rename_outline_rounded,
        tooltip: "Rename files in bulk"),
    WizardPage(
        title: "Folder Size Scan",
        widget: const FileSizeWidget(),
        icon: Icons.aspect_ratio_rounded,
        tooltip: "See how big folders and subfolder are"),
  ];
  int currentPage = 0;
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      mainAxisSize: MainAxisSize.max,
      children: <Widget>[
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 40,
                child: Transform.scale(
                  scale: 2.5,
                  child: Image.asset("resources/wizzard$wizzardID.png"),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Container(
                  height: 70,
                  padding: const EdgeInsets.all(4).copyWith(top: 15),
                  child: Listener(
                    onPointerSignal: (PointerSignalEvent pointerSignal) {
                      if (pointerSignal is PointerScrollEvent) {
                        _scrollController.jumpTo(
                          (_scrollController.offset + pointerSignal.scrollDelta.dy).clamp(
                            0.0,
                            _scrollController.position.maxScrollExtent,
                          ),
                        );
                      }
                    },
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: List<Widget>.generate(
                          pages.length * 2,
                          (int i) => i % 2 != 0
                              ? const SizedBox(width: 10)
                              : ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Color(globalSettings.theme.accentColor)
                                        .withAlpha(currentPage == i ~/ 2 ? 50 : 10),
                                    foregroundColor: Color(globalSettings.theme.accentColor),
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  icon: Icon(pages[i ~/ 2].icon, size: 20),
                                  label: Center(
                                    child: Text(
                                      pages[i ~/ 2].title.replaceFirst(" ", "\n"),
                                      maxLines: 2,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                  onPressed: () => setState(() => currentPage = i ~/ 2),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: currentPage < pages.length
              ? (pages[currentPage].widget is SearchTextWidget || pages[currentPage].widget is ProjectOverviewWidget)
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10.0),
                      child: pages[currentPage].widget,
                    )
                  : SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10.0),
                        child: pages[currentPage].widget,
                      ),
                    )
              : Container(),
        ),
      ],
    );
  }
}
