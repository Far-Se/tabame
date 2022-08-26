import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../models/classes/boxes.dart';
import '../../models/globals.dart';
import '../../models/settings.dart';

class Changelog extends StatefulWidget {
  const Changelog({Key? key}) : super(key: key);

  @override
  State<Changelog> createState() => _ChangelogState();
}

class _ChangelogState extends State<Changelog> {
  @override
  void reassemble() {
    super.reassemble();
  }

  @override
  void initState() {
    super.initState();
    if (globalSettings.lastChangelog != Globals.version) {
      globalSettings.lastChangelog = Globals.version;
      Boxes.updateSettings("lastChangelog", globalSettings.lastChangelog);
    }
  }

  @override
  Widget build(BuildContext context) {
    Map<String, String> changelog = <String, String>{
      '1.1': '''
## Added Views
With Views you can place and resize a window on the screen based on a grid. It is like PowerToys FancyZone, but you can control everything with your mouse.

### **Added Audio Tab**
All Audio Settings were spread over all tabs so I've moved them on their own tab.

Now you can set which type is changed when you change default Audio device (Multimedia, Console, Communications)

Now you can set default Volume for apps, for example if you open a game, and usually you keep your volume at 25, you can set that automatically.

### Other Features:
- You can load GitHub and GitLab repositories directly from Project Overview.

### Fixes:
- Fixed Wizardly ContextMenu. For some people it crashed because the Registry Path was missing.

''',
      '1.0': '''
### Public release with all main features implemented.
''',
    };
    return Padding(
      padding: const EdgeInsets.all(10.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text("Changelog", style: Theme.of(context).textTheme.headline4),
          const SizedBox(height: 10),
          ...List<Widget>.generate(
            changelog.length.clamp(0, 10),
            (int index) => Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text("Version ${changelog.keys.elementAt(index)}:", style: Theme.of(context).textTheme.headline6),
                Markdown(
                  shrinkWrap: true,
                  data: changelog.values.elementAt(index),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
