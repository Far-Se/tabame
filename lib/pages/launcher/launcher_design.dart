import 'package:flutter/material.dart';

import '../../models/settings.dart';

@immutable
class LauncherThemeData {
  const LauncherThemeData({required this.design});

  final LauncherDesign design;

  bool get isSerene => design == LauncherDesign.serene;
  bool get isClassic => design == LauncherDesign.classic;

  double get searchIconSize => isSerene ? 22.0 : 20.0;

  bool get searchIconUsesOnSurface => isSerene;

  double get searchFontSize => isSerene ? 16.0 : 15.0;
  FontWeight? get searchFontWeight => isSerene ? FontWeight.w400 : null;

  double get frameRadius => isSerene ? 14.0 : 18.0;

  EdgeInsets get resultsListPadding => const EdgeInsets.all(8.0);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LauncherThemeData && runtimeType == other.runtimeType && design == other.design;

  @override
  int get hashCode => design.hashCode;
}

class LauncherTheme extends InheritedWidget {
  const LauncherTheme({
    super.key,
    required this.data,
    required super.child,
  });

  final LauncherThemeData data;

  static LauncherThemeData of(BuildContext context) {
    final LauncherTheme? theme = context.dependOnInheritedWidgetOfExactType<LauncherTheme>();
    assert(theme != null, 'No LauncherTheme found in context');
    return theme!.data;
  }

  static LauncherThemeData? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LauncherTheme>()?.data;

  @override
  bool updateShouldNotify(LauncherTheme oldWidget) => data != oldWidget.data;
}
