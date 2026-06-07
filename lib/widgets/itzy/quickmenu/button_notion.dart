import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../../models/win32/win_utils.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/panel_header.dart';
import '../../widgets/windows_scroll.dart';

class NotionResult {
  final String id;
  final String title;
  final String url;
  final String objectType;
  final String? emojiIcon;
  final bool isWorkspaceRoot;

  NotionResult({
    required this.id,
    required this.title,
    required this.url,
    required this.objectType,
    this.emojiIcon,
    this.isWorkspaceRoot = false,
  });

  factory NotionResult.fromJson(Map<String, dynamic> json) {
    String title = "Untitled";
    try {
      // Databases have a top-level 'title' array
      final List<dynamic>? databaseTitle = json['title'] as List<dynamic>?;
      if (databaseTitle != null && databaseTitle.isNotEmpty) {
        title = (databaseTitle[0]['plain_text'] ?? "Untitled").toString();
      } else {
        // Pages have title inside properties
        final Map<String, dynamic>? properties = json['properties'] as Map<String, dynamic>?;
        if (properties != null) {
          for (final dynamic value in properties.values) {
            if (value is Map && value['type'] == 'title') {
              final List<dynamic>? titleArr = value['title'] as List<dynamic>?;
              if (titleArr != null && titleArr.isNotEmpty) {
                title = (titleArr[0]['plain_text'] ?? "Untitled").toString();
              }
              break;
            }
          }
        }
      }
    } catch (_) {}

    String? emoji;
    try {
      final Map<String, dynamic>? icon = json['icon'] as Map<String, dynamic>?;
      if (icon != null && icon['type'] == 'emoji') {
        emoji = icon['emoji'] as String?;
      }
    } catch (_) {}

    bool isRoot = false;
    try {
      final dynamic parent = json['parent'];
      if (parent is Map && parent['workspace'] == true) {
        isRoot = true;
      }
    } catch (_) {}

    return NotionResult(
      id: (json['id'] ?? "").toString(),
      title: title,
      url: (json['url'] ?? "").toString(),
      objectType: (json['object'] ?? "page").toString(),
      emojiIcon: emoji,
      isWorkspaceRoot: isRoot,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'url': url,
      'objectType': objectType,
      'emojiIcon': emojiIcon,
      'isWorkspaceRoot': isWorkspaceRoot,
    };
  }

  factory NotionResult.fromMap(Map<String, dynamic> map) {
    return NotionResult(
      id: (map['id'] ?? "").toString(),
      title: (map['title'] ?? "").toString(),
      url: (map['url'] ?? "").toString(),
      objectType: (map['objectType'] ?? "page").toString(),
      emojiIcon: map['emojiIcon'] as String?,
      isWorkspaceRoot: map['isWorkspaceRoot'] as bool? ?? false,
    );
  }
}

class NotionSearchCache {
  static const String apiKeyKey = "notionApiKey";

  /// Single flat map of every page/database ever seen, keyed by Notion page id.
  /// This is what gets persisted to disk — one deduplicated catalogue of all items.
  static final Map<String, NotionResult> allItems = <String, NotionResult>{};

  /// Browse cache is still keyed by parent-page id so the browse tree works.
  static final Map<String, List<NotionResult>> browseCache = <String, List<NotionResult>>{};

  static bool _loaded = false;

  static String get apiKey => (Boxes.pref.getString(apiKeyKey) ?? "").trim();
  static String get cachePath => "${WinUtils.getTabameAppDataFolder()}\\cache\\notion.json";

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final File file = File(cachePath);
      if (!await file.exists()) return;

      final String content = await file.readAsString();
      final dynamic decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) return;

      // Load flat all-items catalogue.
      final dynamic itemsData = decoded['items'];
      if (itemsData is List) {
        for (final dynamic e in itemsData) {
          final NotionResult r = NotionResult.fromMap(e as Map<String, dynamic>);
          if (r.id.isNotEmpty) allItems[r.id] = r;
        }
      }

      // Load browse cache.
      final dynamic browseData = decoded['browse'];
      if (browseData is Map<String, dynamic>) {
        browseData.forEach((String key, dynamic value) {
          if (value is List) {
            browseCache[key] = value.map((dynamic e) => NotionResult.fromMap(e as Map<String, dynamic>)).toList();
          }
        });
      }
    } catch (e) {
      Debug.add("Notion: Error loading cache: $e");
    }
  }

  static Future<void> save() async {
    try {
      final File file = File(cachePath);
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }

      // Trim browse cache to 20 entries max.
      if (browseCache.length > 20) {
        final List<String> toRemove = browseCache.keys.take(browseCache.length - 20).toList();
        for (final String k in toRemove) {
          browseCache.remove(k);
        }
      }

      final Map<String, dynamic> data = <String, dynamic>{
        'items': allItems.values.map((NotionResult e) => e.toMap()).toList(),
        'browse': browseCache.map((String k, List<NotionResult> v) =>
            MapEntry<String, dynamic>(k, v.map((NotionResult e) => e.toMap()).toList())),
      };

      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      Debug.add("Notion: Error saving cache: $e");
    }
  }

  static Future<void> clear() async {
    try {
      final File file = File(cachePath);
      if (await file.exists()) await file.delete();
      allItems.clear();
      browseCache.clear();
      _loaded = false;
    } catch (e) {
      Debug.add("Notion: Error clearing cache: $e");
    }
  }

  // ---------------------------------------------------------------------------
  // Search — returns fresh API results and merges them into allItems.
  // ---------------------------------------------------------------------------

  static Future<List<NotionResult>> search(String query) async {
    await load();
    if (apiKey.isEmpty) return cachedSearch(query);

    final String queryTrimmed = query.trim();
    final Uri uri = Uri.parse("https://api.notion.com/v1/search");

    final Map<String, NotionResult> freshMap = <String, NotionResult>{};
    String? cursor;
    do {
      final Map<String, dynamic> requestBody = <String, dynamic>{
        "query": queryTrimmed,
        "page_size": 100,
      };
      if (cursor != null) requestBody["start_cursor"] = cursor;

      final http.Response response = await http.post(
        uri,
        headers: <String, String>{
          "Authorization": "Bearer $apiKey",
          "Notion-Version": "2022-06-28",
          "Content-Type": "application/json",
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode != 200) {
        throw Exception("Error: ${response.statusCode} - ${response.reasonPhrase}");
      }

      final Map<String, dynamic> data = jsonDecode(response.body);
      // print(query);
      // print(data);
      final List<dynamic>? rawResults = data['results'] as List<dynamic>?;
      for (final dynamic e in rawResults ?? <dynamic>[]) {
        final NotionResult r = NotionResult.fromJson(e as Map<String, dynamic>);
        freshMap[r.id] = r;
      }

      final bool hasMore = (data['has_more'] as bool?) ?? false;
      cursor = hasMore ? (data['next_cursor'] as String?) : null;
    } while (cursor != null);

    final List<NotionResult> results = freshMap.values.toList();

    // Merge into the global catalogue — never remove items, only add/update.
    if (results.isNotEmpty) {
      allItems.addAll(freshMap);
      await save();
    }

    return results;
  }

  /// Returns all cached items whose title contains [query] (case-insensitive).
  /// Used as the instant result while the real API call is in flight.
  static List<NotionResult> cachedSearch(String query) {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) return allItems.values.toList();
    return allItems.values.where((NotionResult r) => r.title.toLowerCase().contains(q)).toList();
  }
}

class NotionButton extends StatelessWidget {
  const NotionButton({super.key});
  @override
  Widget build(BuildContext context) {
    return ModalButton(
      actionName: "Notion",
      icon: const Icon(Icons.description_rounded),
      child: () => const NotionWidget(),
    );
  }
}

class NotionWidget extends StatefulWidget {
  const NotionWidget({super.key});

  @override
  State<NotionWidget> createState() => _NotionWidgetState();
}

/// A breadcrumb entry for the Browse navigation trail.
class _BreadcrumbEntry {
  const _BreadcrumbEntry({
    required this.id,
    required this.title,
    required this.emoji,
    required this.url,
    this.objectType = 'page',
  });
  final String id; // empty string = root
  final String title;
  final String? emoji;
  final String? url;

  /// 'page', 'database', or '' for the workspace root.
  final String objectType;
}

class _NotionWidgetState extends State<NotionWidget> {
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  String _apiKey = "";
  bool _isSetupMode = false;
  bool _isBrowseMode = false;

  bool _isLoading = false;
  String _currentQuery = "";
  List<NotionResult> _results = <NotionResult>[];
  String? _errorMessage;

  final Map<String, List<NotionResult>> _browseCache = <String, List<NotionResult>>{};
  Timer? _debounceTimer;

  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _searchKeyboardFocusNode = FocusNode(canRequestFocus: false);
  final FocusNode _browseFocusNode = FocusNode();
  final ScrollController _listScrollController = ScrollController();
  int _selectedIndex = -1;

  // Browse mode state
  List<NotionResult> _browseItems = <NotionResult>[];
  bool _browseLoading = false;
  String? _browseError;
  final List<_BreadcrumbEntry> _breadcrumbs = <_BreadcrumbEntry>[
    const _BreadcrumbEntry(id: '', title: 'Workspace', emoji: null, url: ''),
  ];

  @override
  void initState() {
    super.initState();
    _apiKey = NotionSearchCache.apiKey;
    _apiKeyController.text = _apiKey;
    if (_apiKey.isEmpty) {
      _isSetupMode = true;
    } else {
      _loadCache().then((_) {
        final bool isBrowsingNotion = Boxes.pref.getBool("isBrowsingNotion") ?? false;
        if (isBrowsingNotion) return _enterBrowseMode();
        return _fetchResults("");
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_isBrowseMode) {
        _browseFocusNode.requestFocus();
      } else {
        _searchFocusNode.requestFocus();
      }
    });
  }

  // String get _cachePath => NotionSearchCache.cachePath;

  Future<void> _loadCache() async {
    await NotionSearchCache.load();
    _browseCache
      ..clear()
      ..addAll(NotionSearchCache.browseCache);
    // Show every known item as the initial list before the first API call.
    if (NotionSearchCache.allItems.isNotEmpty && mounted) {
      setState(() => _results = NotionSearchCache.allItems.values.toList());
    }
  }

  Future<void> _saveCache() async {
    NotionSearchCache.browseCache
      ..clear()
      ..addAll(_browseCache);
    await NotionSearchCache.save();
  }

  Future<void> _clearCache() async {
    try {
      await NotionSearchCache.clear();
      setState(() {
        _browseCache.clear();
        _results = <NotionResult>[];
        _browseItems = <NotionResult>[];
        _errorMessage = "Cache cleared";
      });
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _errorMessage = null);
      });
    } catch (e) {
      Debug.add("Notion: Error clearing cache: $e");
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchKeyboardFocusNode.dispose();
    _browseFocusNode.dispose();
    _listScrollController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Browse mode helpers
  // ---------------------------------------------------------------------------

  Future<void> _enterSearchMode() async {
    setState(() {
      _isBrowseMode = false;
      _selectedIndex = _results.isEmpty ? -1 : _selectedIndex.clamp(0, _results.length - 1);
    });
    Boxes.pref.setBool("isBrowsingNotion", false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  Future<void> _enterBrowseMode() async {
    Boxes.pref.setBool("isBrowsingNotion", true);
    setState(() {
      _isBrowseMode = true;
      _selectedIndex = -1;
      _breadcrumbs
        ..clear()
        ..add(const _BreadcrumbEntry(id: '', title: 'Workspace', emoji: null, url: null));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _browseFocusNode.requestFocus();
    });
    await _browseLoad('');
  }

  Future<void> _browseLoad(String pageId, {String objectType = 'page'}) async {
    if (!mounted || _apiKey.isEmpty) return;

    final String cacheKey = pageId.isEmpty ? 'root' : pageId;

    // Show cached version immediately.
    if (_browseCache.containsKey(cacheKey)) {
      setState(() {
        _browseItems = _browseCache[cacheKey]!;
        _selectedIndex = _browseItems.isEmpty ? -1 : _selectedIndex.clamp(0, _browseItems.length - 1);
      });
    }

    setState(() {
      _browseLoading = true;
      _browseError = null;
    });

    try {
      List<NotionResult> freshItems;
      if (pageId.isEmpty) {
        freshItems = await _fetchTopLevel();
      } else if (objectType == 'database') {
        freshItems = await _fetchDatabaseEntries(pageId);
      } else {
        freshItems = await _fetchChildPages(pageId);
      }

      if (!mounted) return;

      // If a non-root page came back empty the page itself has no sub-pages,
      // so open it in Notion and navigate back.
      if (freshItems.isEmpty && pageId.isNotEmpty) {
        final _BreadcrumbEntry last = _breadcrumbs.last;
        if (last.id == pageId) {
          if (last.url != null) {
            WinUtils.open(last.url!);
            if (kReleaseMode) QuickMenuFunctions.hideQuickMenu();
          }
          setState(() {
            _breadcrumbs.removeLast();
            final _BreadcrumbEntry prev = _breadcrumbs.last;
            final String prevKey = prev.id.isEmpty ? 'root' : prev.id;
            _browseItems = _browseCache[prevKey] ?? <NotionResult>[];
            _browseLoading = false;
          });
          return;
        }
      }

      // Merge fresh items with whatever was cached so items never vanish
      // mid-session due to API ordering differences.
      final Map<String, NotionResult> merged = <String, NotionResult>{
        for (final NotionResult r in _browseCache[cacheKey] ?? <NotionResult>[]) r.id: r,
        for (final NotionResult r in freshItems) r.id: r,
      };
      final List<NotionResult> mergedList = merged.values.toList();

      final bool changed = !_isSameList(_browseCache[cacheKey] ?? <NotionResult>[], mergedList);
      if (changed) {
        setState(() {
          _browseItems = mergedList;
          _browseCache[cacheKey] = mergedList;
          _selectedIndex = mergedList.isEmpty ? -1 : _selectedIndex.clamp(0, mergedList.length - 1);
        });
        _saveCache();
      }

      setState(() => _browseLoading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _browseError = e.toString();
        _browseLoading = false;
      });
    }
  }

  bool _isSameList(List<NotionResult> a, List<NotionResult> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].title != b[i].title) return false;
    }
    return true;
  }

  /// Returns all pages AND databases accessible by the integration, merged and sorted by title.
  Future<List<NotionResult>> _fetchTopLevel() async {
    final List<NotionResult> results = await _searchByObjectType('page');
    // Only show items that are actually at the top level of the workspace
    final List<NotionResult> roots = results.where((NotionResult item) => item.isWorkspaceRoot).toList()
      ..sort((NotionResult a, NotionResult b) => a.title.compareTo(b.title));

    return roots;
  }

  Future<List<NotionResult>> _searchByObjectType(String type) async {
    final Map<String, NotionResult> mergeMap = <String, NotionResult>{};
    String? cursor;
    do {
      final Map<String, dynamic> body = <String, dynamic>{
        'sort': <String, String>{'direction': 'descending', 'timestamp': 'last_edited_time'},
        'page_size': 100,
      };
      if (cursor != null) body['start_cursor'] = cursor;

      final http.Response response = await http.post(
        Uri.parse('https://api.notion.com/v1/search'),
        headers: <String, String>{
          'Authorization': 'Bearer $_apiKey',
          'Notion-Version': '2022-06-28',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
      if (response.statusCode != 200) break;

      final Map<String, dynamic> data = jsonDecode(response.body);
      final List<dynamic> raw = (data['results'] as List<dynamic>?) ?? <dynamic>[];
      for (final dynamic e in raw) {
        final NotionResult r = NotionResult.fromJson(e as Map<String, dynamic>);
        if (r.title.isNotEmpty) mergeMap[r.id] = r;
      }

      final bool hasMore = (data['has_more'] as bool?) ?? false;
      cursor = hasMore ? (data['next_cursor'] as String?) : null;
    } while (cursor != null);

    return mergeMap.values.toList();
  }

  /// Returns rows (pages) inside a Notion database.
  Future<List<NotionResult>> _fetchDatabaseEntries(String databaseId) async {
    final List<NotionResult> entries = <NotionResult>[];
    String? cursor;
    do {
      final Map<String, dynamic> body = <String, dynamic>{'page_size': 50};
      if (cursor != null) body['start_cursor'] = cursor;
      final http.Response response = await http.post(
        Uri.parse('https://api.notion.com/v1/databases/$databaseId/query'),
        headers: <String, String>{
          'Authorization': 'Bearer $_apiKey',
          'Notion-Version': '2022-06-28',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
      if (response.statusCode != 200) break;
      final Map<String, dynamic> data = jsonDecode(response.body);
      final List<dynamic> raw = (data['results'] as List<dynamic>?) ?? <dynamic>[];
      for (final dynamic row in raw) {
        final NotionResult r = NotionResult.fromJson(row as Map<String, dynamic>);
        if (r.title.isNotEmpty) entries.add(r);
      }
      final bool hasMore = (data['has_more'] as bool?) ?? false;
      cursor = hasMore ? (data['next_cursor'] as String?) : null;
    } while (cursor != null);
    return entries;
  }

  /// Returns child page and database blocks inside a given page.
  Future<List<NotionResult>> _fetchChildPages(String pageId) async {
    final List<NotionResult> children = <NotionResult>[];
    String? cursor;
    do {
      final Map<String, String> queryParams = <String, String>{'page_size': '50'};
      if (cursor != null) queryParams['start_cursor'] = cursor;
      final http.Response response = await http.get(
        Uri.parse('https://api.notion.com/v1/blocks/$pageId/children').replace(queryParameters: queryParams),
        headers: <String, String>{
          'Authorization': 'Bearer $_apiKey',
          'Notion-Version': '2022-06-28',
        },
      );
      if (response.statusCode != 200) break;

      final Map<String, dynamic> data = jsonDecode(response.body);
      final Map<String, NotionResult> cacheValues = NotionSearchCache.allItems;
      final List<dynamic> raw = (data['results'] as List<dynamic>?) ?? <dynamic>[];
      for (final dynamic block in raw) {
        final Map<String, dynamic> b = block as Map<String, dynamic>;
        final String type = b['type'] as String? ?? '';
        if (type != 'child_page' && type != 'child_database') continue;

        final String id = (b['id'] ?? '') as String;
        final String title = type == 'child_page'
            ? ((b['child_page'] as Map<String, dynamic>?)?['title'] ?? 'Untitled') as String
            : ((b['child_database'] as Map<String, dynamic>?)?['title'] ?? 'Untitled Database') as String;

        String? emoji;
        try {
          final Map<String, dynamic>? icon = b['icon'] as Map<String, dynamic>?;
          if (icon != null && icon['type'] == 'emoji') emoji = icon['emoji'] as String?;
        } catch (_) {}
        if (emoji == null) {
          final NotionResult? found = cacheValues[id];
          if (found != null) emoji = found.emojiIcon;
        }

        children.add(NotionResult(
          id: id,
          title: title,
          url: 'https://notion.so/${id.replaceAll('-', '')}',
          objectType: type == 'child_page' ? 'page' : 'database',
          emojiIcon: emoji,
        ));
      }
      final bool hasMore = (data['has_more'] as bool?) ?? false;
      cursor = hasMore ? (data['next_cursor'] as String?) : null;
    } while (cursor != null);
    return children;
  }

  void _browseDrillInto(NotionResult item) {
    setState(() {
      _selectedIndex = -1;
      _breadcrumbs.add(_BreadcrumbEntry(
        id: item.id,
        title: item.title,
        emoji: item.emojiIcon,
        url: item.url,
        objectType: item.objectType,
      ));
    });
    _browseLoad(item.id, objectType: item.objectType);
  }

  void _browseNavigateTo(int breadcrumbIndex) {
    if (breadcrumbIndex >= _breadcrumbs.length - 1) return;
    setState(() {
      _selectedIndex = -1;
      _breadcrumbs.removeRange(breadcrumbIndex + 1, _breadcrumbs.length);
    });
    final _BreadcrumbEntry crumb = _breadcrumbs[breadcrumbIndex];
    _browseLoad(crumb.id, objectType: crumb.objectType);
  }

  Future<void> _fetchResults(String query) async {
    if (!mounted || _apiKey.isEmpty) return;

    final String queryTrimmed = query.trim();

    // Clear immediately when the query changes so stale results from the
    // previous query never bleed into the new one.
    setState(() {
      _results = <NotionResult>[];
      _selectedIndex = -1;
      _isLoading = true;
      _errorMessage = null;
    });

    // Show cached results for THIS query right away so the UI isn't blank.
    final List<NotionResult> cachedResults = NotionSearchCache.cachedSearch(queryTrimmed);
    if (cachedResults.isNotEmpty && mounted) {
      setState(() {
        _results = cachedResults;
        _selectedIndex = 0;
      });
    }

    try {
      final List<NotionResult> fresh = await NotionSearchCache.search(queryTrimmed);
      if (!mounted) return;

      // Merge cache + fresh only for THIS query so new pages that appeared
      // since the cache was written are included, but nothing from other
      // queries ever leaks in.
      // Preserve cached order: update existing entries in-place, append new ones at the end.
      final Map<String, NotionResult> freshMap = <String, NotionResult>{
        for (final NotionResult r in fresh) r.id: r,
      };
      final List<NotionResult> merged = <NotionResult>[
        // Keep cached items in their original order (updated with fresh data if available).
        for (final NotionResult r in cachedResults) freshMap[r.id] ?? r,
        // Append items that are new (not present in the cached results).
        for (final NotionResult r in fresh)
          if (!cachedResults.any((NotionResult c) => c.id == r.id)) r,
      ];

      setState(() {
        _results = merged;
        _selectedIndex = _results.isEmpty ? -1 : _selectedIndex.clamp(0, _results.length - 1);
      });
    } catch (e) {
      if (!mounted) return;
      // Keep whatever is already shown for this query; just surface the error.
      setState(() {
        _errorMessage = "Network error: ${e.toString()}";
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onSearchChanged(String value) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 350), () {
      _currentQuery = value;
      _fetchResults(_currentQuery);
    });
  }

  void _saveSetup() {
    final String val = _apiKeyController.text.trim();
    if (val.isNotEmpty) {
      Boxes.updateSettings(NotionSearchCache.apiKeyKey, val);
      setState(() {
        _apiKey = val;
        _isSetupMode = false;
      });
      _fetchResults(_currentQuery);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = userSettings.themeColors.accent;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    String headerTitle = 'Notion';
    if (_isBrowseMode) headerTitle = 'Browse';
    if (_isSetupMode) headerTitle = 'API Setup';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PanelHeader(
          title: headerTitle,
          accent: accent,
          icon: _isBrowseMode
              ? Icons.folder_open_rounded
              : _isSetupMode
                  ? Icons.vpn_key_rounded
                  : Icons.description_rounded,
          buttonIcon: _isSetupMode
              ? Icons.close_rounded
              : _isBrowseMode
                  ? Icons.search_rounded
                  : Icons.account_tree_rounded,
          buttonTooltip: _isSetupMode
              ? 'Close'
              : _isBrowseMode
                  ? 'Search'
                  : 'Browse',
          buttonPressed: () {
            if (_isSetupMode) {
              if (_apiKey.isNotEmpty) setState(() => _isSetupMode = false);
            } else if (_isBrowseMode) {
              _enterSearchMode();
            } else {
              _enterBrowseMode();
            }
          },
          extraActions: _isSetupMode || _isBrowseMode
              ? null
              : <Widget>[
                  _HeaderIconButton(
                    icon: Icons.settings_rounded,
                    tooltip: 'Settings',
                    accent: accent,
                    onTap: () => setState(() => _isSetupMode = true),
                  ),
                ],
        ),
        (_isLoading || _browseLoading)
            ? LinearProgressIndicator(
                minHeight: 1.5, color: accent.withValues(alpha: 0.2), backgroundColor: Colors.transparent)
            : const SizedBox(height: 1.8),
        Flexible(
          child: Material(
            type: MaterialType.transparency,
            child: _isSetupMode
                ? _buildSetupMode(accent, onSurface)
                : _isBrowseMode
                    ? _buildBrowseMode(accent, onSurface)
                    : _buildSearchMode(accent, onSurface),
          ),
        ),
      ],
    );
  }

  void _onKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_results.isEmpty) return;
      setState(() {
        _selectedIndex = (_selectedIndex + 1).clamp(0, _results.length - 1);
      });
      _scrollToIndex();
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_results.isEmpty) return;
      setState(() {
        _selectedIndex = (_selectedIndex - 1).clamp(0, _results.length - 1);
      });
      _scrollToIndex();
    } else if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_selectedIndex >= 0 && _selectedIndex < _results.length) {
        _openItem(_results[_selectedIndex]);
      }
    }
  }

  KeyEventResult _onBrowseKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_browseItems.isEmpty) return KeyEventResult.handled;
      setState(() {
        _selectedIndex = (_selectedIndex + 1).clamp(0, _browseItems.length - 1);
      });
      _scrollToIndex();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_browseItems.isEmpty) return KeyEventResult.handled;
      setState(() {
        _selectedIndex = (_selectedIndex - 1).clamp(0, _browseItems.length - 1);
      });
      _scrollToIndex();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (_selectedIndex >= 0 && _selectedIndex < _browseItems.length) {
        _browseDrillInto(_browseItems[_selectedIndex]);
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.backspace || event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (_breadcrumbs.length > 1) {
        _browseNavigateTo(_breadcrumbs.length - 2);
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _scrollToIndex() {
    if (_selectedIndex < 0) return;
    const double itemHeight = 44.0; // container + margin
    final double offset = _selectedIndex * itemHeight;
    const double viewportHeight = 300.0; // Approximate flexible height
    if (!_listScrollController.hasClients) return;

    if (offset < _listScrollController.offset) {
      _listScrollController.jumpTo(offset.clamp(0.0, _listScrollController.position.maxScrollExtent));
    } else if (offset + itemHeight > _listScrollController.offset + viewportHeight) {
      _listScrollController
          .jumpTo((offset + itemHeight - viewportHeight).clamp(0.0, _listScrollController.position.maxScrollExtent));
    }
  }

  void _openItem(NotionResult item) {
    if (item.url.isNotEmpty) {
      if (kReleaseMode) QuickMenuFunctions.hideQuickMenu();
      WinUtils.open(item.url);
    }
  }

  Widget _buildSetupMode(Color accent, Color onSurface) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            "Enter your Notion Internal Integration Bearer Token to enable search.\nMake sure your integration has 'Content Access' enabled.",
            style: TextStyle(fontSize: Design.baseFontSize + 2, color: onSurface.withAlpha(150)),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              onTap: () => WinUtils.open("https://www.notion.so/profile/integrations/internal"),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2.0),
                child: Text(
                  "Create API Key ->",
                  style: TextStyle(
                    fontSize: Design.baseFontSize + 1,
                    color: accent,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _apiKeyController,
            obscureText: true,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.vpn_key_rounded, size: 16),
              labelText: "Integration Secret",
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onSubmitted: (_) => _saveSetup(),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _saveSetup,
            child: const Text("Save & Connect"),
          ),
          const SizedBox(height: 24),
          Divider(color: onSurface.withAlpha(30)),
          const SizedBox(height: 12),
          Text(
            "Cache Management",
            style: TextStyle(
                fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.bold, color: onSurface.withAlpha(150)),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _clearCache,
            icon: const Icon(Icons.delete_sweep_rounded, size: 16),
            label: const Text("Clear Local Cache"),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              side: BorderSide(color: Colors.redAccent.withAlpha(100)),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Browse mode UI
  // ---------------------------------------------------------------------------

  Widget _buildBrowseMode(Color accent, Color onSurface) {
    return Focus(
      autofocus: true,
      focusNode: _browseFocusNode,
      onKeyEvent: _onBrowseKeyEvent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Breadcrumb trail
          _buildBreadcrumbs(accent, onSurface),
          // Error strip
          if (_browseError != null)
            Container(
              margin: const EdgeInsets.fromLTRB(10, 6, 10, 0),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.redAccent.withAlpha(28),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_browseError!, style: TextStyle(fontSize: Design.baseFontSize + 1, color: Colors.redAccent)),
            ),
          // List
          Flexible(
            child: _browseLoading && _browseItems.isEmpty
                ? const SizedBox()
                : _browseItems.isEmpty && !_browseLoading
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Center(
                          child: Text(
                            'No sub-pages found here.',
                            style: TextStyle(fontSize: Design.baseFontSize + 2, color: onSurface.withAlpha(120)),
                          ),
                        ),
                      )
                    : WindowsScrollView(
                        child: ListView.builder(
                          controller: _listScrollController,
                          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                          shrinkWrap: true,
                          itemCount: _browseItems.length,
                          itemBuilder: (BuildContext context, int index) {
                            final NotionResult item = _browseItems[index];
                            return _BrowseRow(
                              item: item,
                              selected: index == _selectedIndex,
                              accent: accent,
                              onSurface: onSurface,
                              onHover: () => setState(() => _selectedIndex = index),
                              onDrillIn: () => _browseDrillInto(item),
                              onOpen: () => _openItem(item),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumbs(Color accent, Color onSurface) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            for (int i = 0; i < _breadcrumbs.length; i++) ...<Widget>[
              if (i > 0) Icon(Icons.chevron_right_rounded, size: 14, color: onSurface.withAlpha(80)),
              InkWell(
                onTap: i < _breadcrumbs.length - 1 ? () => _browseNavigateTo(i) : null,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (_breadcrumbs[i].emoji != null) ...<Widget>[
                        Text(_breadcrumbs[i].emoji!, style: TextStyle(fontSize: Design.baseFontSize + 2)),
                        const SizedBox(width: 3),
                      ] else if (i == 0) ...<Widget>[
                        Icon(Icons.home_rounded,
                            size: 12, color: i == _breadcrumbs.length - 1 ? accent : onSurface.withAlpha(130)),
                        const SizedBox(width: 3),
                      ],
                      Text(
                        _breadcrumbs[i].title,
                        style: TextStyle(
                          fontSize: Design.baseFontSize + 1,
                          fontWeight: i == _breadcrumbs.length - 1 ? FontWeight.w700 : FontWeight.w500,
                          color: i == _breadcrumbs.length - 1 ? accent : onSurface.withAlpha(150),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSearchMode(Color accent, Color onSurface) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: KeyboardListener(
            focusNode: _searchKeyboardFocusNode,
            onKeyEvent: _onKeyEvent,
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: _onSearchChanged,
              autofocus: true,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.search_rounded, size: 16, color: onSurface.withAlpha(150)),
                hintText: "Search pages, databases...",
                isDense: true,
                filled: true,
                fillColor: onSurface.withAlpha(8),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: onSurface.withAlpha(20)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: onSurface.withAlpha(20)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: accent.withAlpha(100)),
                ),
              ),
            ),
          ),
        ),
        if (_errorMessage != null)
          Container(
            padding: const EdgeInsets.all(8),
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.redAccent.withAlpha(30),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _errorMessage!,
              style: TextStyle(fontSize: Design.baseFontSize + 1, color: Colors.redAccent),
            ),
          ),
        Flexible(
          child: _results.isEmpty && !_isLoading
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(
                      _currentQuery.isEmpty ? "No recent items" : "No results found for '$_currentQuery'",
                      style: TextStyle(fontSize: Design.baseFontSize + 2, color: onSurface.withAlpha(120)),
                    ),
                  ),
                )
              : WindowsScrollView(
                  child: ListView.builder(
                    controller: _listScrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    shrinkWrap: true,
                    itemCount: _results.length,
                    itemBuilder: (BuildContext context, int index) {
                      final NotionResult item = _results[index];
                      final bool isSelected = index == _selectedIndex;
                      return MouseRegion(
                        onHover: (PointerHoverEvent event) {
                          if (event.delta != Offset.zero) {
                            setState(() {
                              _selectedIndex = index;
                            });
                          }
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          decoration: BoxDecoration(
                            color: isSelected ? accent.withAlpha(40) : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => _openItem(item),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                child: Row(
                                  children: <Widget>[
                                    Container(
                                      width: 24,
                                      height: 24,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: accent.withAlpha(20),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: item.emojiIcon != null
                                          ? Text(item.emojiIcon!, style: const TextStyle(fontSize: 14))
                                          : Icon(
                                              item.objectType == 'database'
                                                  ? Icons.table_chart_outlined
                                                  : Icons.insert_drive_file_outlined,
                                              size: 14,
                                              color: accent.withAlpha(200),
                                            ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Row(
                                            children: <Widget>[
                                              Flexible(
                                                child: Text(
                                                  item.title,
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w500,
                                                    color: onSurface,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (item.objectType == 'database') ...<Widget>[
                                                const SizedBox(width: 5),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                  decoration: BoxDecoration(
                                                    color: accent.withAlpha(22),
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(color: accent.withAlpha(40)),
                                                  ),
                                                  child: Text(
                                                    'DB',
                                                    style: TextStyle(
                                                      fontSize: 9,
                                                      fontWeight: FontWeight.w800,
                                                      color: accent,
                                                      letterSpacing: 0.3,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          Text(
                                            item.objectType.toUpperCase(),
                                            style: TextStyle(
                                              fontSize: Design.baseFontSize,
                                              color: onSurface.withAlpha(120),
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(Icons.open_in_new_rounded, size: 14, color: onSurface.withAlpha(80)),
                                    const SizedBox(width: 4),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Browse row widget
// ---------------------------------------------------------------------------

class _BrowseRow extends StatefulWidget {
  const _BrowseRow({
    required this.item,
    required this.selected,
    required this.accent,
    required this.onSurface,
    required this.onHover,
    required this.onDrillIn,
    required this.onOpen,
  });
  final NotionResult item;
  final bool selected;
  final Color accent;
  final Color onSurface;
  final VoidCallback onHover;
  final VoidCallback onDrillIn;
  final VoidCallback onOpen;

  @override
  State<_BrowseRow> createState() => _BrowseRowState();
}

class _BrowseRowState extends State<_BrowseRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        setState(() => _hovered = true);
        widget.onHover();
      },
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: widget.selected
              ? widget.accent.withAlpha(40)
              : _hovered
                  ? widget.accent.withAlpha(18)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: widget.selected
                ? widget.accent.withAlpha(55)
                : _hovered
                    ? widget.accent.withAlpha(30)
                    : Colors.transparent,
          ),
        ),
        child: InkWell(
          onTap: widget.onDrillIn,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 7, 6, 7),
            child: Row(
              children: <Widget>[
                // Icon
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: widget.accent.withAlpha(20),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: widget.item.emojiIcon != null
                      ? Text(widget.item.emojiIcon!, style: const TextStyle(fontSize: 14))
                      : Icon(
                          widget.item.objectType == 'database'
                              ? Icons.table_chart_outlined
                              : Icons.description_outlined,
                          size: 14,
                          color: widget.accent.withAlpha(200),
                        ),
                ),
                const SizedBox(width: 10),
                // Title + optional DB badge
                Expanded(
                  child: Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          widget.item.title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: widget.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.item.objectType == 'database') ...<Widget>[
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: widget.accent.withAlpha(22),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: widget.accent.withAlpha(40)),
                          ),
                          child: Text(
                            'DB',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: widget.accent,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                // Open button
                AnimatedOpacity(
                  opacity: _hovered || widget.selected ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 120),
                  child: InkWell(
                    onTap: widget.onOpen,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                      decoration: BoxDecoration(
                        color: widget.accent.withAlpha(22),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: widget.accent.withAlpha(40)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(Icons.open_in_new_rounded, size: 11, color: widget.accent),
                          const SizedBox(width: 3),
                          Text(
                            'Open',
                            style: TextStyle(
                              fontSize: Design.baseFontSize,
                              fontWeight: FontWeight.w700,
                              color: widget.accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Drill-in arrow
                Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: _hovered || widget.selected ? widget.accent.withAlpha(180) : widget.onSurface.withAlpha(60),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small header icon button helper
// ---------------------------------------------------------------------------

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.accent,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, size: 15, color: accent),
        ),
      ),
    );
  }
}
