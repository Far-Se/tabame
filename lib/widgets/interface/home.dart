import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../models/util/markdown_text.dart';
import '../../models/settings.dart';

class Home extends StatefulWidget {
  const Home({Key? key}) : super(key: key);

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(10),
          child: Material(
            type: MaterialType.transparency,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Expanded(
                  flex: 2,
                  child: Markdown(
                    controller: ScrollController(),
                    physics: const NeverScrollableScrollPhysics(),
                    shrinkWrap: true,
                    selectable: false,
                    data: markdownHomeLeft,
                    imageBuilder: (Uri uri, String? str1, String? str2) {
                      if (uri.path != "") {
                        if (uri.path == "logo") {
                          return Image.asset(globalSettings.logo, width: 20);
                        } else {
                          return Image.asset(uri.path, width: 20);
                        }
                      }
                      final Map<String, IconData> icons = <String, IconData>{
                        "quickMenu": Icons.apps,
                        "runWindow": Icons.drag_handle,
                        "views": Icons.view_agenda,
                        "wizardly": Icons.auto_fix_high,
                      };
                      if (icons.containsKey(str2)) return Icon(icons[str2]);
                      return const Icon(Icons.home);
                    },
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Markdown(
                    // controller: controller,
                    selectable: false,
                    controller: ScrollController(),
                    physics: const NeverScrollableScrollPhysics(),
                    shrinkWrap: true,

                    data: markdownHomeRight,
                    imageBuilder: (Uri uri, String? str1, String? str2) {
                      final Map<String, IconData> icons = <String, IconData>{
                        "tips": Icons.tips_and_updates,
                        "remap": Icons.keyboard,
                        "projects": Icons.folder_copy,
                        "trktivty": Icons.scatter_plot,
                        "tasks": Icons.task_alt,
                      };
                      if (icons.containsKey(str2)) return Icon(icons[str2]);
                      return const Icon(Icons.home);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
