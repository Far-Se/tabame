import 'package:flutter/material.dart';

import '../../interface/changelog.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/panel_header.dart';

class CheckChangelogButton extends StatelessWidget {
  const CheckChangelogButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ModalButton(
      actionName: "See what's new!",
      icon: const Icon(Icons.newspaper),
      child: () => const ChangelogPanel(),
      onTap: () {
        // QuickMenuFunctions.refreshQuickMenu();
      },
    );
  }
}

class ChangelogPanel extends StatelessWidget {
  const ChangelogPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const PanelHeader(title: 'Changelog', icon: Icons.newspaper),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: const <Widget>[Changelog(showTitle: false)],
          ),
        ),
      ],
    );
  }
}
