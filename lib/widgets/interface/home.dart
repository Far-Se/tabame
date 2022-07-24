import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../models/util/markdown_text.dart';
import '../../models/utils.dart';

class Home extends StatefulWidget {
  const Home({Key? key}) : super(key: key);

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  String updateResponse = "Click Here to check for updates";
  final ScrollController controller = ScrollController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ListTile(
          leading: const Tooltip(message: "Check for update", child: Icon(Icons.refresh)),
          title: Text("Current Version: v${globalSettings.currentVersion}"),
          subtitle: Text("$updateResponse"),
          onTap: () {
            updateResponse = "Latest version already installed!";
            setState(() {});
            //globalSettings.checkForUpdate(context);
          },
        ),
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
                        return Image.asset(uri.path, width: 20);
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
                        "trktivty": Icons.celebration,
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
