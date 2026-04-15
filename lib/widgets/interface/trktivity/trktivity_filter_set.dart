import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';

class TrktivityFilterSet extends StatefulWidget {
  final TrktivityFilter filter;
  final Function(TrktivityFilter filter) onSaved;
  const TrktivityFilterSet({
    super.key,
    required this.filter,
    required this.onSaved,
  });
  @override
  TrktivityFilterSetState createState() => TrktivityFilterSetState();
}

class TrktivityFilterSetState extends State<TrktivityFilterSet> {
  final TextEditingController exeController = TextEditingController();
  final TextEditingController searchController = TextEditingController();
  final TextEditingController replaceController = TextEditingController();
  late TrktivityFilter filter;
  @override
  void initState() {
    super.initState();
    filter = widget.filter.copyWith();
    exeController.text = filter.exe;
    searchController.text = filter.titleSearch;
    replaceController.text = filter.titleReplace;
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Focus(
        onFocusChange: (bool f) {
          if (!f) {
            filter.exe = exeController.text;
            filter.titleSearch = searchController.text;
            filter.titleReplace = replaceController.text;
            widget.onSaved(filter);
          }
        },
        child: Row(
          children: <Widget>[
            // Match EXE
            Expanded(
              flex: 2,
              child: _buildCompactField(
                context,
                controller: exeController,
                hint: "Match EXE (regex)",
                icon: Icons.terminal_rounded,
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.arrow_forward_rounded, size: 16, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
            const SizedBox(width: 8),
            // Search Regex
            Expanded(
              flex: 3,
              child: _buildCompactField(
                context,
                controller: searchController,
                hint: "Search Title (regex)",
                icon: Icons.search_rounded,
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.repeat_rounded, size: 16, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
            const SizedBox(width: 8),
            // Replace With
            Expanded(
              flex: 2,
              child: _buildCompactField(
                context,
                controller: replaceController,
                hint: "Replace With",
                icon: Icons.edit_note_rounded,
              ),
            ),
            IconButton(
              onPressed: () {
                exeController.clear();
                filter.exe = "";
                widget.onSaved(filter);
              },
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              color: colorScheme.error.withValues(alpha: 0.7),
              tooltip: "Remove Rule",
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactField(
    BuildContext context, {
    required TextEditingController controller,
    required String hint,
    required IconData icon,
  }) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return TextField(
      controller: controller,
      style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 16, color: colorScheme.primary.withValues(alpha: 0.7)),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        filled: true,
        fillColor: colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colorScheme.primary.withValues(alpha: 0.3)),
        ),
      ),
    );
  }
}
