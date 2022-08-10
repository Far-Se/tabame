import 'package:flutter/material.dart';

import '../../models/classes/boxes.dart';
import '../../models/settings.dart';
import '../widgets/info_text.dart';

class ViewsInterface extends StatefulWidget {
  const ViewsInterface({Key? key}) : super(key: key);

  @override
  ViewsInterfaceState createState() => ViewsInterfaceState();
}

class ViewsInterfaceState extends State<ViewsInterface> {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        CheckboxListTile(
          value: globalSettings.viewsEnabled,
          controlAffinity: ListTileControlAffinity.leading,
          onChanged: (bool? e) => setState(
            () {
              globalSettings.viewsEnabled = !globalSettings.viewsEnabled;
              Boxes.updateSettings("viewsEnabled", globalSettings.viewsEnabled);
            },
          ),
          title: Text("Views", style: Theme.of(context).textTheme.headline6),
          subtitle: const InfoText("With views, you can organize windows on your screen"),
        ),
        if (globalSettings.viewsEnabled)
          Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[],
          )
      ],
    );
  }
}
