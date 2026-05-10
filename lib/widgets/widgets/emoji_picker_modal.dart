import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/settings.dart';
import 'custom_tooltip.dart';
import 'panel_header.dart';

const String _emojiPackageAssetPath = 'packages/emoji_selector/data/emoji.json';

Future<List<_EmojiEntry>>? _emojiEntriesFuture;

Future<String?> showEmojiPickerModal(
  BuildContext context, {
  String title = 'Pick Emoji',
  String initialValue = '',
  Color? barrierColor,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierColor: barrierColor ?? Colors.black.withValues(alpha: 0.16),
    builder: (BuildContext context) {
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: EmojiPickerModal(title: title, initialValue: initialValue),
        ),
      );
    },
  );
}

class EmojiPickerTextField extends StatelessWidget {
  const EmojiPickerTextField({
    super.key,
    required this.controller,
    required this.decoration,
    this.autofocus = false,
    this.dialogTitle = 'Pick Emoji',
    this.textAlign = TextAlign.start,
  });

  final TextEditingController controller;
  final InputDecoration decoration;
  final bool autofocus;
  final String dialogTitle;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final Color accent = userSettings.themeColors.accentColor;

    return TextField(
      controller: controller,
      autofocus: autofocus,
      textAlign: textAlign,
      decoration: decoration.copyWith(
        suffixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 34),
        suffixIcon: Padding(
          padding: const EdgeInsets.only(right: 4),
          child: IconButton(
            tooltip: 'Open emoji picker',
            padding: EdgeInsets.zero,
            icon: Icon(Icons.mood_rounded, size: 18, color: accent),
            onPressed: () async {
              final String? emoji = await showEmojiPickerModal(
                context,
                title: dialogTitle,
                initialValue: controller.text,
              );
              if (emoji == null) return;
              controller.text = emoji;
              controller.selection = TextSelection.collapsed(offset: controller.text.length);
            },
          ),
        ),
      ),
    );
  }
}

class EmojiPickerModal extends StatefulWidget {
  const EmojiPickerModal({
    super.key,
    this.title = 'Pick Emoji',
    this.initialValue = '',
  });

  final String title;
  final String initialValue;

  @override
  State<EmojiPickerModal> createState() => _EmojiPickerModalState();
}

class _EmojiPickerModalState extends State<EmojiPickerModal> {
  late final TextEditingController _searchController;
  late final TextEditingController _customController;
  late final ScrollController _scrollController;
  late final Future<List<_EmojiEntry>> _emojiFuture;

  int _selectedCategoryIndex = 0;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _customController = TextEditingController(text: widget.initialValue);
    _scrollController = ScrollController();
    _emojiFuture = _loadEmojiEntries();
    _syncCategoryFromInitialValue();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _customController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _syncCategoryFromInitialValue() async {
    final String currentValue = widget.initialValue.trim();
    if (currentValue.isEmpty) return;

    final List<_EmojiEntry> entries = await _emojiFuture;
    if (!mounted) return;

    for (final _EmojiEntry entry in entries) {
      if (entry.char != currentValue) continue;
      setState(() {
        _selectedCategoryIndex = _categoryIndexFor(entry.category);
      });
      return;
    }
  }

  void _submitCustomValue() {
    final String value = _customController.text.trim();
    if (value.isEmpty) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color accent = userSettings.themeColors.accentColor;
    final Color borderColor = scheme.onSurface.withValues(alpha: 0.1);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              PanelHeader(
                title: widget.title,
                accent: accent,
                icon: Icons.emoji_emotions_outlined,
                buttonPressed: () => Navigator.of(context).pop(),
                buttonIcon: Icons.close_rounded,
                buttonTooltip: 'Close',
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _buildSearchField(accent, scheme),
                    const SizedBox(height: 10),
                    _buildCustomInput(accent, scheme),
                    const SizedBox(height: 12),
                    _buildCategoryBar(accent, scheme),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: FutureBuilder<List<_EmojiEntry>>(
                    future: _emojiFuture,
                    builder: (BuildContext context, AsyncSnapshot<List<_EmojiEntry>> snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return _buildLoadingState(accent, scheme);
                      }
                      if (snapshot.hasError || !snapshot.hasData) {
                        return _buildErrorState(accent, scheme);
                      }

                      final List<_EmojiEntry> visibleEntries = _visibleEntries(snapshot.data!);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          _buildResultsHeader(
                            accent,
                            scheme,
                            count: visibleEntries.length,
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: visibleEntries.isEmpty
                                ? _buildEmptyState(accent, scheme)
                                : _buildEmojiGrid(visibleEntries, accent, scheme),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField(Color accent, ColorScheme scheme) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: <Widget>[
          const SizedBox(width: 10),
          Icon(Icons.search_rounded, size: 18, color: accent),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _searchController,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Search emoji names or paste the emoji itself',
                hintStyle: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurface.withValues(alpha: 0.45),
                ),
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ),
          if (_searchController.text.isNotEmpty)
            IconButton(
              tooltip: 'Clear search',
              onPressed: () {
                setState(() {
                  _searchController.clear();
                });
              },
              icon: Icon(
                Icons.close_rounded,
                size: 18,
                color: scheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCustomInput(Color accent, ColorScheme scheme) {
    final String previewValue = _customController.text.trim();

    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  previewValue.isEmpty ? '?' : previewValue,
                  style: TextStyle(
                    fontSize: previewValue.isEmpty ? 18 : 22,
                    color: previewValue.isEmpty ? accent.withValues(alpha: 0.6) : scheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: _customController,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submitCustomValue(),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Type or paste your own emoji / custom token',
                hintStyle: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurface.withValues(alpha: 0.45),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ),
          if (previewValue.isNotEmpty)
            IconButton(
              tooltip: 'Use current value',
              onPressed: _submitCustomValue,
              icon: Icon(Icons.check_rounded, size: 18, color: accent),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Icon(
                Icons.keyboard_rounded,
                size: 18,
                color: scheme.onSurface.withValues(alpha: 0.3),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCategoryBar(Color accent, ColorScheme scheme) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List<Widget>.generate(_emojiCategoryGroups.length, (int index) {
          final _EmojiCategoryGroup category = _emojiCategoryGroups[index];
          final bool selected = index == _selectedCategoryIndex;

          return Padding(
            padding: EdgeInsets.only(right: index == _emojiCategoryGroups.length - 1 ? 0 : 8),
            child: InkWell(
              onTap: () {
                setState(() {
                  _selectedCategoryIndex = index;
                });
                if (_scrollController.hasClients) {
                  _scrollController.jumpTo(0);
                }
              },
              borderRadius: BorderRadius.circular(999),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? accent.withValues(alpha: 0.12) : scheme.onSurface.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: selected ? accent.withValues(alpha: 0.30) : scheme.onSurface.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      category.icon,
                      size: 16,
                      color: selected ? accent : scheme.onSurface.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      category.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                        color: selected ? accent : scheme.onSurface.withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildResultsHeader(
    Color accent,
    ColorScheme scheme, {
    required int count,
  }) {
    final String query = _normalizedText(_searchController.text);
    final String label = query.isEmpty
        ? '${_emojiCategoryGroups[_selectedCategoryIndex].label} - $count emoji'
        : 'Search results - $count match${count == 1 ? '' : 'es'}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: accent.withValues(alpha: 0.9),
            ),
          ),
          const Spacer(),
          Text(
            'Tap to use immediately',
            style: TextStyle(
              fontSize: 10,
              color: scheme.onSurface.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState(Color accent, ColorScheme scheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2, color: accent),
          ),
          const SizedBox(height: 12),
          Text(
            'Loading emoji catalog...',
            style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(Color accent, ColorScheme scheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.error_outline_rounded, size: 26, color: accent.withValues(alpha: 0.8)),
          const SizedBox(height: 10),
          Text(
            'Emoji data could not be loaded.',
            style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.72)),
          ),
          const SizedBox(height: 4),
          Text(
            'You can still paste your own emoji above.',
            style: TextStyle(fontSize: 11, color: scheme.onSurface.withValues(alpha: 0.48)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(Color accent, ColorScheme scheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.search_off_rounded, size: 28, color: accent.withValues(alpha: 0.7)),
          const SizedBox(height: 10),
          Text(
            'No emoji matched your search.',
            style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.72)),
          ),
          const SizedBox(height: 4),
          Text(
            'Paste your own emoji or custom token above instead.',
            style: TextStyle(fontSize: 11, color: scheme.onSurface.withValues(alpha: 0.48)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmojiGrid(List<_EmojiEntry> entries, Color accent, ColorScheme scheme) {
    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      child: GridView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.only(right: 4),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 48,
          mainAxisExtent: 44,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
        ),
        itemCount: entries.length,
        itemBuilder: (BuildContext context, int index) {
          final _EmojiEntry entry = entries[index];
          return _EmojiTile(
            entry: entry,
            accent: accent,
            onSurface: scheme.onSurface,
            onTap: () => Navigator.of(context).pop(entry.char),
          );
        },
      ),
    );
  }

  List<_EmojiEntry> _visibleEntries(List<_EmojiEntry> entries) {
    final String query = _normalizedText(_searchController.text);
    if (query.isEmpty) {
      final _EmojiCategoryGroup category = _emojiCategoryGroups[_selectedCategoryIndex];
      return entries.where((_EmojiEntry entry) => category.categories.contains(entry.category)).toList();
    }

    final List<_EmojiEntry> matches = entries.where((_EmojiEntry entry) {
      return entry.char.contains(query) || entry.searchIndex.contains(query);
    }).toList();

    matches.sort((_EmojiEntry a, _EmojiEntry b) {
      final int comparison = _searchRank(a, query).compareTo(_searchRank(b, query));
      if (comparison != 0) return comparison;
      return a.sortOrder.compareTo(b.sortOrder);
    });

    return matches;
  }
}

class _EmojiTile extends StatefulWidget {
  const _EmojiTile({
    required this.entry,
    required this.accent,
    required this.onSurface,
    required this.onTap,
  });

  final _EmojiEntry entry;
  final Color accent;
  final Color onSurface;
  final VoidCallback onTap;

  @override
  State<_EmojiTile> createState() => _EmojiTileState();
}

class _EmojiTileState extends State<_EmojiTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return CustomTooltip(
      message: '${widget.entry.name}\n${widget.entry.category}',
      waitDuration: const Duration(milliseconds: 150),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hovering
                  ? userSettings.themeColors.accentColor.withValues(alpha: 0.14)
                  : userSettings.themeColors.accentColor.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _hovering
                    ? userSettings.themeColors.accentColor.withValues(alpha: 0.34)
                    : userSettings.themeColors.accentColor.withValues(alpha: 0.10),
              ),
            ),
            child: Text(
              widget.entry.char,
              style: TextStyle(
                fontSize: 20,
                color: _hovering ? userSettings.themeColors.accentColor : widget.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmojiEntry {
  const _EmojiEntry({
    required this.char,
    required this.category,
    required this.name,
    required this.shortName,
    required this.sortOrder,
    required this.searchIndex,
  });

  final String char;
  final String category;
  final String name;
  final String shortName;
  final int sortOrder;
  final String searchIndex;
}

class _EmojiCategoryGroup {
  const _EmojiCategoryGroup({
    required this.label,
    required this.icon,
    required this.categories,
  });

  final String label;
  final IconData icon;
  final List<String> categories;
}

const List<_EmojiCategoryGroup> _emojiCategoryGroups = <_EmojiCategoryGroup>[
  _EmojiCategoryGroup(
    label: 'Smileys',
    icon: Icons.emoji_emotions_outlined,
    categories: <String>['Smileys & Emotion', 'People & Body'],
  ),
  _EmojiCategoryGroup(
    label: 'Animals',
    icon: Icons.pets_outlined,
    categories: <String>['Animals & Nature'],
  ),
  _EmojiCategoryGroup(
    label: 'Food',
    icon: Icons.restaurant_outlined,
    categories: <String>['Food & Drink'],
  ),
  _EmojiCategoryGroup(
    label: 'Activity',
    icon: Icons.sports_basketball_outlined,
    categories: <String>['Activities'],
  ),
  _EmojiCategoryGroup(
    label: 'Travel',
    icon: Icons.travel_explore_outlined,
    categories: <String>['Travel & Places'],
  ),
  _EmojiCategoryGroup(
    label: 'Objects',
    icon: Icons.lightbulb_outline_rounded,
    categories: <String>['Objects'],
  ),
  _EmojiCategoryGroup(
    label: 'Symbols',
    icon: Icons.stars_rounded,
    categories: <String>['Symbols'],
  ),
  _EmojiCategoryGroup(
    label: 'Flags',
    icon: Icons.flag_outlined,
    categories: <String>['Flags'],
  ),
];

Future<List<_EmojiEntry>> _loadEmojiEntries() {
  return _emojiEntriesFuture ??= _readEmojiEntries();
}

Future<List<_EmojiEntry>> _readEmojiEntries() async {
  final String rawData = await rootBundle.loadString(_emojiPackageAssetPath);
  final List<dynamic> decoded = jsonDecode(rawData) as List<dynamic>;

  final List<_EmojiEntry> entries = decoded
      .map<_EmojiEntry>((dynamic dynamicEntry) {
        final Map<String, dynamic> entry = Map<String, dynamic>.from(dynamicEntry as _EmojiJsonEntry);
        final String char = _unicodeToString((entry['unified'] as String?) ?? '');
        final String category = (entry['category'] as String?) ?? 'Objects';
        final String name = ((entry['name'] as String?) ?? '').trim();
        final String shortName = ((entry['short_name'] as String?) ?? '').trim();
        final int sortOrder = (entry['sort_order'] as num?)?.toInt() ?? 999999;
        final String normalizedShortName = shortName.replaceAll('_', ' ');
        final String searchIndex = _normalizedText('$name $normalizedShortName $category $char');

        return _EmojiEntry(
          char: char,
          category: category,
          name: name.isEmpty ? normalizedShortName : name,
          shortName: normalizedShortName,
          sortOrder: sortOrder,
          searchIndex: searchIndex,
        );
      })
      .where((_EmojiEntry entry) => entry.char.isNotEmpty)
      .toList()
    ..sort((_EmojiEntry a, _EmojiEntry b) => a.sortOrder.compareTo(b.sortOrder));

  return entries;
}

int _categoryIndexFor(String category) {
  for (int index = 0; index < _emojiCategoryGroups.length; index++) {
    if (_emojiCategoryGroups[index].categories.contains(category)) return index;
  }
  return 0;
}

int _searchRank(_EmojiEntry entry, String query) {
  final String normalizedQuery = _normalizedText(query);
  final String shortName = _normalizedText(entry.shortName);
  final String name = _normalizedText(entry.name);
  final String category = _normalizedText(entry.category);

  if (entry.char == normalizedQuery) return 0;
  if (shortName == normalizedQuery) return 1;
  if (name == normalizedQuery) return 2;
  if (shortName.startsWith(normalizedQuery)) return 3;
  if (name.startsWith(normalizedQuery)) return 4;
  if (category.startsWith(normalizedQuery)) return 5;
  if (shortName.contains(normalizedQuery)) return 6;
  if (name.contains(normalizedQuery)) return 7;
  if (category.contains(normalizedQuery)) return 8;
  return 9;
}

String _normalizedText(String value) {
  return value.toLowerCase().replaceAll('_', ' ').trim();
}

String _unicodeToString(String unified) {
  if (unified.isEmpty) return '';
  return String.fromCharCodes(
    unified.split('-').map((String code) => int.parse(code, radix: 16)),
  );
}

typedef _EmojiJsonEntry = Map<dynamic, dynamic>;
