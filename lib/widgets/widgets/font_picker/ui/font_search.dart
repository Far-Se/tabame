import 'package:flutter/material.dart';

import '../constants/translations.dart' show translations;

class FontSearch extends StatefulWidget {
  final ValueChanged<String> onSearchTextChanged;
  const FontSearch({super.key, required this.onSearchTextChanged});

  @override
  State<FontSearch> createState() => _FontSearchState();
}

class _FontSearchState extends State<FontSearch> {
  bool _isSearchFocused = false;
  TextEditingController searchController = TextEditingController();
  @override
  Widget build(BuildContext context) {
    return FocusScope(
      child: Focus(
        onFocusChange: (bool focus) {
          setState(() {
            _isSearchFocused = focus;
          });
        },
        child: TextField(
          controller: searchController,
          decoration: InputDecoration(
            prefixIcon: const Icon(
              Icons.search,
            ),
            suffixIcon: _isSearchFocused
                ? IconButton(
                    icon: const Icon(Icons.cancel),
                    onPressed: () {
                      FocusScope.of(context).unfocus();
                      searchController.clear();
                      widget.onSearchTextChanged('');
                    },
                  )
                : null,
            hintText: translations.d["search"],
            hintStyle: const TextStyle(fontSize: 14.0),
            border: const OutlineInputBorder(),
            focusedBorder: const OutlineInputBorder(),
            enabledBorder: const OutlineInputBorder(),
            errorBorder: const OutlineInputBorder(),
            disabledBorder: const OutlineInputBorder(),
          ),
          onChanged: widget.onSearchTextChanged,
        ),
      ),
    );
  }
}
