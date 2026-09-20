part of '../launcher_design_builder.dart';

/// Input and status shared by every search-bar presentation.
@immutable
class _LauncherSearchBarContent {
  const _LauncherSearchBarContent({
    required this.dragHandle,
    required this.textField,
    required this.trailingBadge,
    required this.isSearching,
  });

  final Widget dragHandle;
  final Widget textField;
  final Widget? trailingBadge;
  final bool isSearching;
}

/// Overlays the optional status badge without changing the input's width.
class _LauncherSearchField extends StatelessWidget {
  const _LauncherSearchField(this.content, {this.badgePadding = 4});

  final _LauncherSearchBarContent content;
  final double badgePadding;

  @override
  Widget build(BuildContext context) {
    final Widget? badge = content.trailingBadge;
    return Stack(
      alignment: Alignment.centerRight,
      children: <Widget>[
        content.textField,
        if (badge != null)
          if (badgePadding == 0) badge else Padding(padding: EdgeInsets.only(right: badgePadding), child: badge),
      ],
    );
  }
}
