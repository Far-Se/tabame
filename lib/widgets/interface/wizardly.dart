// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:math';

import 'package:flutter/material.dart';

import '../../models/settings.dart';
import '../wizardly/context_menu_cleaner.dart';
import '../wizardly/find_text.dart';
import '../wizardly/folder_size_scan.dart';
import '../wizardly/hosts_editor.dart';
import '../wizardly/project_overview.dart';
import '../wizardly/rename_files.dart';
import '../wizardly/wallpaper_scheduler.dart';

class Wizardly extends StatefulWidget {
  const Wizardly({super.key});

  @override
  WizardlyState createState() => WizardlyState();
}

class WizardPage {
  String title;
  Widget Function() widget;
  IconData icon;
  String? tooltip;
  bool isFullPage;
  WizardPage({
    required this.title,
    required this.widget,
    required this.icon,
    this.tooltip = "",
    this.isFullPage = false,
  });
}

class WizardlyState extends State<Wizardly> {
  int wizzardID = 1;
  @override
  void initState() {
    super.initState();
    if (!userSettings.args.contains("-wizardly")) {
      pages.add(WizardPage(
          title: "Hosts Editor",
          widget: () => const HostsEditor(),
          icon: Icons.dns_rounded,
          isFullPage: false,
          tooltip: "Edit hosts File"));
    }
    wizzardID = Random().nextInt(4) + 1;
  }

  @override
  void dispose() {
    super.dispose();
  }

  final List<WizardPage> pages = <WizardPage>[
    WizardPage(
        title: "Search Text",
        widget: () => const SearchTextWidget(),
        icon: Icons.search_rounded,
        isFullPage: true,
        tooltip: "Find Text in folders"),
    WizardPage(
        title: "Project Overview",
        widget: () => const ProjectOverviewWidget(),
        icon: Icons.analytics_rounded,
        isFullPage: true,
        tooltip: "Count line of Code\nView project breakdown"),
    WizardPage(
        title: "Rename Files",
        widget: () => const FileNameWidget(),
        icon: Icons.drive_file_rename_outline_rounded,
        isFullPage: false,
        tooltip: "Rename files in bulk"),
    WizardPage(
        title: "Folder Size Scan",
        widget: () => const FileSizeWidget(),
        icon: Icons.aspect_ratio_rounded,
        isFullPage: false,
        tooltip: "See how big folders and subfolder are"),
    WizardPage(
        title: "Context Menu Cleaner",
        widget: () => const ContextMenuCleaner(),
        icon: Icons.cleaning_services_rounded,
        isFullPage: true,
        tooltip: "Manage app-added context menu items"),
    WizardPage(
        title: "Wallpaper Scheduler",
        widget: () => const WallpaperScheduler(),
        icon: Icons.schedule_rounded,
        isFullPage: true,
        tooltip: "Automate wallpapers per monitor"),
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
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: List<Widget>.generate(
                      pages.length,
                      (int i) => ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: userSettings.themeColors.accent.withAlpha(currentPage == i ? 50 : 12),
                          foregroundColor: userSettings.themeColors.accent,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: Icon(pages[i].icon, size: 16),
                        label: Text(
                          pages[i].title,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onPressed: () => setState(() => currentPage = i),
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
              ? pages[currentPage].isFullPage
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10.0),
                      child: pages[currentPage].widget(),
                    )
                  : SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10.0),
                        child: pages[currentPage].widget(),
                      ),
                    )
              : Container(),
        ),
      ],
    );
  }
}
