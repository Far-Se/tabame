import 'dart:io';

import 'package:flutter/material.dart';

import '../../interface/changelog.dart';
import '../../../models/win32/win_utils.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/panel_header.dart';

const String _changelogUrl = 'https://github.com/Far-Se/tabame/blob/main/CHANGELOG.md';

void _openFullChangelog() {
  if (Platform.isWindows) {
    WinUtils.open(_changelogUrl);
  } else {
    //TODO: Implement multiplatform
  }
}

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
        const PanelHeader(
          title: 'Changelog',
          icon: Icons.newspaper,
          buttonPressed: _openFullChangelog,
          buttonIcon: Icons.open_in_new,
          buttonTooltip: 'Open full changelog',
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: const <Widget>[Changelog(showTitle: false, maxVersions: 6)],
          ),
        ),
      ],
    );
  }
}
