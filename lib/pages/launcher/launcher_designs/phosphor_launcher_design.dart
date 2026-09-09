// ignore_for_file: unused_element

part of '../launcher_design_builder.dart';

class PhosphorSearchBar extends StatelessWidget {
  const PhosphorSearchBar(
      {super.key,
      required this.dragHandle,
      required this.textField,
      required this.trailingBadge,
      required this.isSearching});
  final Widget dragHandle;
  final Widget textField;
  final Widget? trailingBadge;
  final bool isSearching;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(20, 8, 4, 8),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: PhosphorTokens.border))),
        child: Row(children: <Widget>[
          DragToMoveArea(
              child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(r'C:\>', style: PhosphorTokens.font(size: 18, color: PhosphorTokens.accent)))),
          const SizedBox(width: 20),
          Expanded(child: textField),
          if (trailingBadge != null) trailingBadge!,
          if (isSearching)
            const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: PhosphorTokens.accent))),
          const SizedBox(width: 8),
          // _windowButton('Minimize', Icons.remove, () {
          //   windowManager.minimize();
          // }),
          // _windowButton('Maximize / restore', Icons.crop_square, () async {
          //   if (await windowManager.isMaximized()) {
          //     await windowManager.unmaximize();
          //   } else {
          //     await windowManager.maximize();
          //   }
          // }),
          // _windowButton('Hide launcher', Icons.close, () {
          //   windowManager.hide();
          // }),
        ]),
      );

  Widget _windowButton(String label, IconData icon, VoidCallback onPressed) => SizedBox(
      width: 44,
      child:
          IconButton(tooltip: label, onPressed: onPressed, icon: Icon(icon, size: 18), color: PhosphorTokens.accent));
}

class PhosphorLauncherFrame extends StatelessWidget {
  const PhosphorLauncherFrame(
      {super.key,
      required this.surface,
      required this.accent,
      required this.onSurface,
      required this.resultCount,
      required this.child});
  final Color surface;
  final Color accent;
  final Color onSurface;
  final int resultCount;
  final Widget child;

  @override
  Widget build(BuildContext context) => LauncherTheme(
        data: const LauncherThemeData(design: LauncherDesign.phosphor),
        child: Container(
            decoration: LauncherDesign.phosphor.outerDecoration(surface: surface, accent: accent),
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              Flexible(fit: FlexFit.loose, child: child),
              Container(
                  height: 44,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: PhosphorTokens.border))),
                  child: LayoutBuilder(
                      builder: (BuildContext context, BoxConstraints constraints) => Row(children: <Widget>[
                            Expanded(
                                child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(children: <Widget>[
                                      _hint('Ctrl + P', 'Preview'),
                                      _hint('? ?', 'Navigate'),
                                      _hint('Enter', 'Open'),
                                      if (constraints.maxWidth > 720) ...<Widget>[
                                        _hint('Ctrl + C', 'Copy path'),
                                        _hint('Ctrl + O', 'Open folder')
                                      ],
                                    ]))),
                            const SizedBox(width: 12),
                            Text('$resultCount results',
                                style: PhosphorTokens.font(size: 12, color: PhosphorTokens.accent)),
                          ]))),
            ])),
      );

  Widget _hint(String key, String label) => Padding(
      padding: const EdgeInsets.only(right: 20),
      child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(border: Border.all(color: PhosphorTokens.accent.withAlpha(160))),
            child: Text(key, style: PhosphorTokens.font(size: 11, color: PhosphorTokens.accent))),
        const SizedBox(width: 12),
        Text(label, style: PhosphorTokens.font(size: 11, color: PhosphorTokens.dim)),
      ]));
}

class PhosphorResultsPanel extends StatelessWidget {
  const PhosphorResultsPanel({super.key, required this.enabled, required this.child});
  final bool enabled;
  final Widget child;
  @override
  Widget build(BuildContext context) => enabled
      ? Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(border: Border.all(color: PhosphorTokens.border)),
          child: child)
      : child;
}
