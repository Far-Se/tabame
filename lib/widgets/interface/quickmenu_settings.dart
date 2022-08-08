import 'dart:io';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';
import '../../models/classes/boxes.dart';
import '../../models/settings.dart';
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
    return ListTileTheme(
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
          const SizedBox(height: 10),
          Center(child: Text("QuickMenu", style: Theme.of(context).textTheme.headline6)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    CheckboxListTile(
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text("Put Pinned Apps and TrayBar in one row at the bottom"),
                      value: globalSettings.quickMenuPinnedWithTrayAtBottom,
                      onChanged: (bool? newValue) async {
                        globalSettings.quickMenuPinnedWithTrayAtBottom = newValue ?? false;
                        Boxes.updateSettings("quickMenuPinnedWithTrayAtBottom", globalSettings.quickMenuPinnedWithTrayAtBottom);
                        if (!mounted) return;
                        setState(() {});
                      },
                    ),
                    CheckboxListTile(
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text("Hide QuickMenu when unfocusing"),
                      value: globalSettings.hideTabameOnUnfocus,
                      onChanged: (bool? newValue) async {
                        globalSettings.hideTabameOnUnfocus = newValue ?? false;
                        Boxes.updateSettings("hideTabameOnUnfocus", globalSettings.hideTabameOnUnfocus);
                        if (mounted) setState(() {});
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                  child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  CheckboxListTile(
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text("Change Icon on QuickMenu"),
                    value: globalSettings.customLogo != "",
                    onChanged: (bool? newValue) async {
                      newValue ??= false;
                      if (!newValue) {
                        globalSettings.customLogo = "";
                      } else {
                        final OpenFilePicker file = OpenFilePicker()
                          ..filterSpecification = <String, String>{'PNG Image (*.png)': '*.png'}
                          ..defaultFilterIndex = 0
                          ..defaultExtension = 'png'
                          ..title = 'Select an image';

                        final File? result = file.getFile();
                        if (result != null) {
                          globalSettings.customLogo = result.path;
                        }
                      }
                      Boxes.updateSettings("customLogo", globalSettings.customLogo);
                      if (!mounted) return;
                      setState(() {});
                    },
                    secondary: Padding(
                      padding: const EdgeInsets.all(5),
                      child: globalSettings.customLogo == "" ? Image.asset(globalSettings.logo) : Image.file(File(globalSettings.customLogo)),
                    ),
                  ),
                  CheckboxListTile(
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text("Add Spash Image above QuickMenu"),
                    value: globalSettings.customSpash != "",
                    onChanged: (bool? newValue) async {
                      newValue ??= false;
                      if (!newValue) {
                        globalSettings.customSpash = "";
                      } else {
                        final OpenFilePicker file = OpenFilePicker()
                          ..filterSpecification = <String, String>{'PNG Image (*.png)': '*.png'}
                          ..defaultFilterIndex = 0
                          ..defaultExtension = 'png'
                          ..title = 'Select an image';

                        final File? result = file.getFile();
                        if (result != null) {
                          globalSettings.customSpash = result.path;
                        }
                      }
                      Boxes.updateSettings("customSpash", globalSettings.customSpash);
                      if (!mounted) return;
                      setState(() {});
                    },
                    secondary: Padding(
                      padding: const EdgeInsets.all(5),
                      child: globalSettings.customSpash == "" ? null : Image.file(File(globalSettings.customSpash)),
                    ),
                  )
                ],
              ))
            ],
          ),
          const SizedBox(height: 10),
          const Divider(thickness: 2, height: 10),
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
    );
  }
}
