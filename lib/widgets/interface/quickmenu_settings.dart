import 'package:flutter/material.dart';
import '../itzy/interface/quickmenu_bottom_bar.dart';
import '../itzy/interface/quickmenu_pinned_apps.dart';
import '../itzy/interface/quickmenu_taskbar.dart';
import '../itzy/interface/quickmenu_quickactions.dart';

class QuickmenuSettings extends StatefulWidget {
  const QuickmenuSettings({Key? key}) : super(key: key);

  @override
  QuickmenuSettingsState createState() => QuickmenuSettingsState();
}

class QuickmenuSettingsState extends State<QuickmenuSettings> {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: constraints.maxHeight),
        child: ListTileTheme(
          data: Theme.of(context).listTileTheme.copyWith(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                dense: true,
                visualDensity: VisualDensity.compact,
                style: ListTileStyle.drawer,
              ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(child: Text("Top Bar", style: Theme.of(context).textTheme.headline6)),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Expanded(child: QuickmenuTopbar()),
                  const Expanded(child: QuickmenuPinnedApps()),
                ],
              ),
              const Divider(thickness: 2, height: 10),
              Center(child: Text("Task Bar", style: Theme.of(context).textTheme.headline6)),
              const QuickmenuTaskbar(),
              const Divider(thickness: 2, height: 10),
              Center(child: Text("Bottom Bar", style: Theme.of(context).textTheme.headline6)),
              const QuickmenuBottomBar()
            ],
          ),
        ),
      ),
    );
  }
}
