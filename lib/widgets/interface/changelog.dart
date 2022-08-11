import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

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
  Widget build(BuildContext context) {
    Map<String, String> changelog = <String, String>{
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
