import 'package:flutter/material.dart';
import '../quickmenu/top_bar.dart';

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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [TopBar()],
        ),
      ),
    );
  }
}
