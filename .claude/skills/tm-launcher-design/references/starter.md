# Minimal launcher design pieces

Read this when creating a new design and a small implementation example is useful. These are neutral starting pieces, not a visual specification or a complete registration patch. Replace `Example`/`example` with the chosen name, develop its appearance, and complete the registration map in `SKILL.md`.

## Frame and search

Create `lib/pages/launcher/launcher_designs/example_launcher_design.dart`. This is a part of the builder library; it has no imports of its own. Its owner already imports Material, launcher tokens/settings, and corner helpers.

```dart
part of '../launcher_design_builder.dart';

BoxDecoration _exampleOuterDecoration(Color surface, Color accent) => BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: accent.withAlpha(48)),
    );

class _ExampleSearchBar extends StatelessWidget {
  const _ExampleSearchBar(this.content);

  final _LauncherSearchBarContent content;

  @override
  Widget build(BuildContext context) {
    final Color accent = LauncherTheme.accentOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(children: <Widget>[
        content.dragHandle,
        const SizedBox(width: 10),
        Expanded(child: _LauncherSearchField(content)),
        if (content.isSearching)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: accent),
            ),
          ),
      ]),
    );
  }
}

class ExampleLauncherFrame extends StatelessWidget {
  const ExampleLauncherFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LauncherSurface(
        decoration: _exampleOuterDecoration(
          Theme.of(context).colorScheme.surface,
          LauncherTheme.accentOf(context),
        ),
        child: child,
      );
}
```

Connect the declarations with a `part` directive and the builder's existing dispatch points:

```dart
// In LauncherDesignBuilder.outerDecoration:
LauncherDesign.example => _exampleOuterDecoration(surface, accent),
// In LauncherDesignBuilder.buildSearchBar:
LauncherDesign.example => _ExampleSearchBar(content),
// In _LauncherLayoutMixin._buildLauncherFrame:
LauncherDesign.example => ExampleLauncherFrame(child: buildBody()),
```

## Result row

Create `lib/pages/launcher/result/designs/example_result_row.dart`. This uses the palette passed to the shared row and preserves custom content, markup, badges, movement-only hover, and selection semantics. A distinctive design can replace the text styles with its shared token helpers.

```dart
part of '../result_row.dart';

extension _ExampleResultRow on LauncherResultRow {
  Widget _buildExample(BuildContext context) {
    final Color surface = Theme.of(context).colorScheme.surface;
    final TextStyle titleStyle = launcherTextStyle(TextStyle(
      color: onSurface,
      fontSize: Design.baseFontSize + 4,
      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
    ));
    final TextStyle subtitleStyle = titleStyle.copyWith(
      color: Color.alphaBlend(onSurface.withAlpha(180), surface),
      fontSize: Design.baseFontSize + 2,
      fontWeight: FontWeight.w400,
    );
    return _interactive(
      behavior: HitTestBehavior.opaque,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Color.alphaBlend(accent.withAlpha(28), surface) : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: isSelected ? accent.withAlpha(110) : Colors.transparent),
        ).withLauncherCorners(),
        child: Row(children: <Widget>[
          SizedBox(width: 28, height: 28, child: Center(child: icon)),
          const SizedBox(width: 12),
          Expanded(
            child: content ??
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _titleText(titleStyle),
                    if ((subtitle ?? '').isNotEmpty) ...<Widget>[
                      const SizedBox(height: 2),
                      _subtitleText(subtitleStyle),
                    ],
                  ],
                ),
          ),
          if (badge != null) Padding(padding: const EdgeInsets.only(left: 8), child: badge),
          const SizedBox(width: 8),
          SizedBox(
            width: 16,
            child: isSelected ? Icon(Icons.keyboard_return_rounded, size: 15, color: onSurface) : null,
          ),
        ]),
      ),
    );
  }
}
```

Add `part 'designs/example_result_row.dart';` in `result_row.dart` and dispatch `LauncherDesign.example => _buildExample(context)` from its build switch. The row intentionally has no animation; introduce one only if it benefits the requested design and handles `isRepeating` and reduced motion.

These snippets do not add the enum, presets, palette, config, section header, or font/dialog integration. Complete those in the owning files using the main guide before validation.
