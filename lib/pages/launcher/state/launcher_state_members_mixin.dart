part of '../../launcher.dart';

// ignore_for_file: annotate_overrides, unused_element, unused_element_parameter

// ---------------------------------------------------------------------------
// LauncherState member contract
// ---------------------------------------------------------------------------

// Dart requires a mixin's superclass constraint to be a superclass of the
// class applying it. This shared contract exposes LauncherState's existing
// members to the concern mixins without changing LauncherState's public type.
mixin _LauncherStateMembersMixin on State<Launcher> {
  LauncherSearchToken get _searchToken;
  TextEditingController get _controller;
  FocusNode get _searchFocusNode;
  FocusNode get _resultsFocusNode;
  ScrollController get _scrollController;
  ValueNotifier<int> get _activeIndexNotifier;
  ValueNotifier<bool> get _isRepeatingKey;
  Map<String, GlobalKey> get _quickActionKeys;
  Map<String, GlobalKey> get _resultKeys;
  String? get _infoText;
  set _infoText(String? value);
  IconData? get _infoIcon;
  set _infoIcon(IconData? value);
  Timer? get _infoTimer;
  set _infoTimer(Timer? value);
  String? get _quickActionSplashId;
  set _quickActionSplashId(String? value);
  bool get _mouseSelectionEnabled;
  set _mouseSelectionEnabled(bool value);
  Offset? get _lastMousePosition;
  set _lastMousePosition(Offset? value);
  Timer? get _quickActionSplashTimer;
  set _quickActionSplashTimer(Timer? value);
  Timer? get _keyRepeatTimer;
  set _keyRepeatTimer(Timer? value);
  Timer? get _launcherFocusRetryTimer;
  set _launcherFocusRetryTimer(Timer? value);
  LogicalKeyboardKey? get _lastPressedKey;
  set _lastPressedKey(LogicalKeyboardKey? value);
  bool get _isRepairingFileIndex;
  set _isRepairingFileIndex(bool value);
  List<String> get _copiedFiles;
  LauncherDesign get _design;
  set _design(LauncherDesign value);
  double get _resultsMaxHeight;
  set _resultsMaxHeight(double value);
  bool get _isResizeHandleHovered;
  set _isResizeHandleHovered(bool value);
  bool get _isResizingResults;
  set _isResizingResults(bool value);
  bool get _isFilePreviewVisible;
  set _isFilePreviewVisible(bool value);
  double? get _previewWidthPercent;
  set _previewWidthPercent(double? value);
  Map<String, PlatformWindowPreview> get _windowPreviewCache;
  Map<String, Future<PlatformWindowPreview?>> get _windowPreviewCaptures;
  ValueNotifier<int> get _windowPreviewCacheVersion;
  Set<String> get _queuedWindowPreviewIds;
  int get _windowPreviewPrefetchGeneration;
  set _windowPreviewPrefetchGeneration(int value);
  int get _windowPreviewPrefetchRun;
  set _windowPreviewPrefetchRun(int value);
  String? get _lastHoveredWindowPreviewId;
  set _lastHoveredWindowPreviewId(String? value);
  List<String> get _folderBrowsingStack;
  List<String> get _folderBrowsingQueryStack;
  List<LauncherSearchResultItem> get _results;
  set _results(List<LauncherSearchResultItem> value);
  String? get _keyboardSelectedResultId;
  set _keyboardSelectedResultId(String? value);
  int get _keyboardSelectedResultIndex;
  set _keyboardSelectedResultIndex(int value);
  bool get _isSearching;
  set _isSearching(bool value);
  bool get _canConsumePendingInput;
  set _canConsumePendingInput(bool value);
  LauncherSearchMode get _searchMode;
  set _searchMode(LauncherSearchMode value);
  LauncherPluginHost get _pluginHost;
  PluginManifest? get _activePlugin;
  set _activePlugin(PluginManifest? value);
  PluginRenderFrame? get _pluginFrame;
  set _pluginFrame(PluginRenderFrame? value);
  Map<String, Set<String>> get _pluginSelectedIdsByScope;
  Map<String, String> get _pluginPageSelectionIds;
  List<String> get _pluginPageHistory;
  String? get _pluginKeyboardSelectedItemId;
  set _pluginKeyboardSelectedItemId(String? value);
  int get _pluginKeyboardSelectedIndex;
  set _pluginKeyboardSelectedIndex(int value);
  Timer? get _pluginQueryDebounce;
  set _pluginQueryDebounce(Timer? value);
  bool get _launcherAnimatedOnce;
  set _launcherAnimatedOnce(bool value);
  bool get _pluginSubmitPending;
  set _pluginSubmitPending(bool value);
  bool get _pluginWindowWidened;
  set _pluginWindowWidened(bool value);
  bool get _pluginWindowUserResized;
  set _pluginWindowUserResized(bool value);
  Timer? get _pluginWidthCollapseTimer;
  set _pluginWidthCollapseTimer(Timer? value);
  AnimationController get _pluginWindowTransitionController;
  double get _pluginWindowOpacity;
  set _pluginWindowOpacity(double value);
  int get _pluginWindowTransitionVersion;
  set _pluginWindowTransitionVersion(int value);
  String? get _pluginToast;
  set _pluginToast(String? value);
  Timer? get _pluginToastTimer;
  set _pluginToastTimer(Timer? value);
  String get _pluginToastStyle;
  set _pluginToastStyle(String value);
  double? get _pluginToastProgress;
  set _pluginToastProgress(double? value);
  String? get _pluginLastSubmittedQuery;
  set _pluginLastSubmittedQuery(String? value);
  ScrollController get _pluginDetailScroll;
  String? get _pendingLauncherQuickAction;
  set _pendingLauncherQuickAction(String? value);
  int get _pendingLauncherQuickActionAttempt;
  set _pendingLauncherQuickActionAttempt(int value);
  List<_LauncherFunctionCommand> get _functionCommands;
  List<LauncherSearchResultItem> get _launcherShortcuts;
  Timer? get _searchDebounce;
  set _searchDebounce(Timer? value);
  Timer? get _windowRefreshTimer;
  set _windowRefreshTimer(Timer? value);
  String get _lastScrollResetQuery;
  set _lastScrollResetQuery(String value);
  DateTime? get _lastFolderSyncTime;
  set _lastFolderSyncTime(DateTime? value);
  bool get _isFolderSyncing;
  set _isFolderSyncing(bool value);
  int get _searchGeneration;
  set _searchGeneration(int value);
  bool get _hasKeyboardNavigatedCurrentQuery;
  set _hasKeyboardNavigatedCurrentQuery(bool value);
  String get _keyboardNavigationQuery;
  set _keyboardNavigationQuery(String value);
  String? get _resultsQuery;
  set _resultsQuery(String? value);

  void _copyItem();
  void _clearCopiedFiles();
  void _openActionsForActiveResult();
  void _routeToPlugin(PluginManifest plugin, String query);
  void _deactivatePlugin();
  void _exitPlugin();
  void _onPluginFrame(PluginRenderFrame frame);
  bool _isPluginItemListAppend(List<PluginItem> previous, List<PluginItem> next);
  bool _sameItemIds(List<PluginItem> a, List<PluginItem> b);
  void _updatePluginPageHistory(PluginRenderFrame? previous, PluginRenderFrame next);
  Set<String> _selectedIdsFor(PluginEventScope scope);
  PluginRenderFrame? _frameForScope(PluginEventScope scope);
  void _prunePluginSelections(PluginRenderFrame frame);
  void _sendPluginBack();
  void _onPluginFormSubmit(PluginEventScope scope, Map<String, Object?> values, {String? button});
  void _onPluginFormChange(PluginEventScope scope, String fieldId, Map<String, Object?> values);
  void _onPluginFormCancel(PluginEventScope scope);
  void _onPluginCommand(PluginCommand command);
  void _setPluginQuery(String text);
  void _showPluginToast(String message, {String style = 'success', double? progress});
  Future<void> _pastePluginText(String text);
  void _onPluginWindowResize();
  void _onPluginWindowResized();
  void _applyPluginWindowWidth(bool wide);
  void _restorePluginWindowWidth({bool animate = true});
  Future<void> _animatePluginWindowWidth(double targetWidth);
  Future<bool> _fadePluginWindowTo(double targetOpacity, int transitionVersion, {required Curve curve});
  Future<void> _setPluginWindowWidth(double width, {bool finalize = false});
  void _setPluginSelection(int index, {bool fromKeyboard = false});
  void _submitPluginItem();
  void _submitPluginItemAction(PluginItem item, {required PluginEventScope scope});
  Future<void> _firePluginAction(PluginEventScope scope, String itemId, PluginAction action);
  void _togglePluginSelection(PluginEventScope scope, String id);
  void _openPluginActions();
  Future<void> _openPluginReadme(PluginManifest plugin, File readme);
  bool _handlePluginShortcut(KeyEvent event);
  Future<void> _handleLauncherWindowAction();
  KeyEventResult _handlePluginKey(KeyEvent event);
  KeyEventResult _scrollPluginDetail(LogicalKeyboardKey key, {required bool isRepeat});
  List<LauncherSearchResultItem> _shortcutResults();
  List<LauncherSearchResultItem>? _pluginKeywordSuggestions(String query);
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event);
  KeyEventResult _handleResultEditingKey(KeyEvent event);
  void _enterResultBrowsing(LogicalKeyboardKey key);
  void _enterPluginResultBrowsing(LogicalKeyboardKey key);
  Future<void> _pasteIntoSearch();
  void _replaceSearchSelection(String replacement);
  void _deleteFromSearch({required bool backwards});
  TextSelection _validSearchSelection();
  Future<void> _refreshLauncherCatalogs();
  void _requestLauncherFocus({bool focusWindow = false});
  void _requestPluginNavigationFocus();
  void _onFocusManagerChanged();
  void _flashQuickActionResult(String id);
  void _handleKeyStep(LogicalKeyboardKey key, {bool initial = false});
  bool _handleRaycastShortcutKey(FocusNode node, KeyEvent event);
  void _scrollToActiveIndex();
  void _scrollToActiveIndexFallback(int index);
  void _scrollResultToCenter(int index);
  bool _centerRenderedResult(int index);
  void _moveResultListTo(double offset, {required bool animated});
  void _startWindowRefreshLoop();
  void _refreshVisibleWindowResults();
  void _consumePendingQuickMenuSearchInput();
  void _focusSearch();
  void _rememberKeyboardResultSelection();
  void _onSearchChanged(String query);
  Duration _debounceForMode(LauncherSearchMode mode, String normalizedQuery);
  bool _isActiveSearch(int gen);
  void _runSearch(int requestId, String query, String normalizedQuery, LauncherSearchMode searchMode);
  void _handlePluginListSearch(LauncherSearchContext context);
  bool _isCurrencyShorthand(String query);
  Future<void> _handleCurrencyShorthand(LauncherSearchContext context);
  bool _isMathShorthand(String query);
  Future<void> _handleMathShorthand(LauncherSearchContext context);
  bool _isMathCurrencyShorthand(String query);
  Future<void> _handleMathCurrencyShorthand(LauncherSearchContext context);
  Future<void> _syncChangedFoldersAndRefresh(
    String query,
    String normalizedQuery,
    LauncherSearchMode searchMode,
  );
  void _handleBookmarkKindSearch(LauncherSearchContext context, BookmarkResultKind kind);
  String? _parseBookmarkAddTarget(String normalizedQuery);
  void _handleBookmarkAddCommand(LauncherSearchContext context, String target);
  LauncherSearchResultItem _buildBookmarkAddCategoryRow(BookmarkGroup group, String target);
  Future<void> _addBookmarkToCategory(String categoryTitle, String rawTarget);
  bool _looksLikeWebsite(String target);
  String _deriveBookmarkTitle(String target, bool isWebsite);
  void _flashLauncherInfo(String text, {IconData icon = Icons.check_circle_outline_rounded});
  void _handleAppSearch(LauncherSearchContext context);
  void _handleTimerCommand(LauncherSearchContext context);
  _ParsedLauncherTimer? _parseTimerCommand(String query);
  QuickActionMenuEntry _buildTimerQuickAction(_ParsedLauncherTimer timer);
  void _handleMediaCommand(LauncherSearchContext context);
  QuickActionMenuEntry _buildMediaCommandAction(_MediaCommandAction action, int? audioIndex);
  void _executeMediaCommand(_MediaCommandAction action, int? audioIndex);
  Future<void> _handleSpotifyCommand(LauncherSearchContext context);
  QuickActionMenuEntry _buildSpotifyNowPlaying(PlatformMediaSession session);
  void _executeSpotifyCommand(PlatformMediaSession session, String command);
  void _createLauncherTimer(_ParsedLauncherTimer timer);
  void _finishLauncherFunctionExecution();
  Future<void> _handleFunctionCommand(LauncherSearchContext context);
  _LauncherFunctionCommand? _findFunctionCommand(String name);
  List<LauncherSearchResultItem> _buildFunctionSuggestions(String query);
  QuickActionMenuEntry _buildFunctionSuggestionAction(_LauncherFunctionCommand command);
  Future<List<LauncherSearchResultItem>> _buildFunctionTimerResults(String input);
  _ParsedLauncherTimer? _parseFunctionTimerCommand(String input);
  Future<List<LauncherSearchResultItem>> _buildFunctionClearResults(String input);
  Future<void> _clearCacheFolder(String folder);
  Future<List<LauncherSearchResultItem>> _buildFunctionReloadSettingsResults(String input);
  Future<List<LauncherSearchResultItem>> _buildFunctionReindexResults(String input);
  Future<List<LauncherSearchResultItem>> _buildFunctionCalculatorResults(String input);
  Future<List<LauncherSearchResultItem>> _buildFunctionDesignResults(String input);
  Future<List<LauncherSearchResultItem>> _buildFunctionSystemResults(String input);
  Future<List<LauncherSearchResultItem>> _buildFunctionUnitResults(String input);
  Future<List<LauncherSearchResultItem>> _buildFunctionCurrencyResults(String input);
  Future<List<LauncherSearchResultItem>> _buildParserFunctionResults({
    required String idPrefix,
    required String input,
    required String emptyHelp,
    required IconData icon,
    required Future<ParserResult> Function(String input) parser,
    bool stripAssignmentPrefix = false,
    bool closeAfterCopy = true,
  });
  Future<void> _streamFunctionTranslateResults(String input, LauncherSearchContext context);
  _ParsedTranslateCommand? _parseTranslateCommand(String input);
  String _loadTranslatorFrom();
  List<String> _loadTranslatorTargets();
  String _stripQuotes(String value);
  QuickActionMenuEntry _buildCopyFunctionAction({
    required String id,
    required String title,
    required String subtitle,
    required IconData icon,
    required String value,
    bool closeAfterExecute = true,
  });
  String _stripMathAssignmentPrefix(String value);
  QuickActionMenuEntry _buildFunctionAction({
    required String id,
    required String title,
    required String subtitle,
    required IconData icon,
    required List<String> searchTerms,
    required VoidCallback onExecute,
  });
  Future<void> _handleNotionSearch(LauncherSearchContext context);
  Future<void> _handleObsidianSearch(LauncherSearchContext context);
  Future<void> _handleSteamSearch(LauncherSearchContext context);
  Future<void> _handleTerminalSearch(LauncherSearchContext context);
  void _handleWorkspacesSearch(LauncherSearchContext context);
  QuickActionMenuEntry _buildWorkspaceQuickAction(Workspace workspace);
  void _launchWorkspaceFromLauncher(Workspace workspace);
  QuickActionMenuEntry _buildTerminalQuickAction(TerminalProfile profile);
  void _launchTerminalProfile(TerminalProfile profile);
  void _setSearching(bool value);
  void _scrollResultsToTopForQuery(String query);
  void _setResults(
    List<LauncherSearchResultItem> results, {
    bool resetSelection = true,
    bool? isSearching,
  });
  int _activeDesignResultIndex(List<LauncherSearchResultItem> results);
  Future<void> _pruneStaleFileResults(List<LauncherSearchResultItem> snapshot);
  void _maybeExecutePendingLauncherQuickAction();
  void _onShortcutPressed(LauncherShortcut shortcut);
  void _onSubmitted(String query);
  void _executeLauncherActionResult(QuickActionMenuEntry action);
  void _openBookmarkResult(BookmarkSearchResult result);
  void _openFile(String path, {int? nodeId});
  void _browseFolder(String folderPath);
  void _goBackDesktopFolder();
  void _openFolderInExplorer(String folderPath);
  void _openSelectedFolderInExplorer();
  void _openAppResult(LauncherAppResult app, {int? nodeId});
  Future<void> _recordFileOpen(int nodeId);
  bool _isMalformedFileIndexError(Object error);
  Future<void> _repairFileIndexInBackground();
  Future<void> _openWindow(PlatformWindow window);
  Future<void> _openBrowserTab(BrowserTab browserTab);
  void _openNotionResult(NotionResult result);
  void _openObsidianResult(ObsidianNote result);
  void _openSteamResult(SteamGame result);
  String _resultKeyId(LauncherSearchResultItem result, int index);
  void _syncQuickActionKeys(List<LauncherSearchResultItem> results);
  void _syncResultKeys(List<LauncherSearchResultItem> results);
  Future<PlatformWindowPreview?> _captureWindowPreview(
    PlatformWindow window, {
    bool force = false,
  });
  void _prefetchWindowPreviews(List<LauncherSearchResultItem> results);
  void _selectWindowResultFromMouse(int index, PlatformWindow window);
  void _selectResultFromPointerHover(PointerHoverEvent event, int index);
  void _selectResultFromMouse(int index);
  void _runQuickAction(QuickActionMenuEntry entry);
  LauncherSearchResultItem? _previewResultAt(int index);
  void initState();
  Future<void> onQuickMenuSwitchedPage(QuickMenuPage newType, QuickMenuPage oldType, bool visible);
  Future<void> onQuickMenuToggled(bool visible, QuickMenuPage type);
  void dispose();
  void onQuickActionExecute(String actionName);
  Future<void> refreshQuickMenu();
  void requestQuickMenuFocus();
  void requestFocusIfNeeded(bool focusWindow);
  void _persistPreviewWidthPercent();
  Widget? _buildTrailingBadge(Color accent, Color onSurface);
  Widget _buildPluginBody();
  Widget _buildPluginToast(String message);
  Widget _buildShortcutResult(BuildContext context, ThemeData theme, LauncherShortcut shortcut, int index,
      bool isSelected, bool isRepeatingKey);
  Widget _buildBookmarkResult(BuildContext context, ThemeData theme, BookmarkSearchResult result, int index,
      bool isSelected, bool isRepeatingKey);
  Widget _buildFileResult(BuildContext context, ThemeData theme, FileSystemEntity entity, int? nodeId, int index,
      bool isSelected, bool isRepeatingKey);
  Widget _buildAppResult(BuildContext context, ThemeData theme, LauncherAppResult app, int? nodeId, int index,
      bool isSelected, bool isRepeatingKey);
  Widget _buildNotionResult(
      BuildContext context, ThemeData theme, NotionResult result, int index, bool isSelected, bool isRepeatingKey);
  Widget _buildObsidianResult(
      BuildContext context, ThemeData theme, ObsidianNote result, int index, bool isSelected, bool isRepeatingKey);
  Widget _buildSteamResult(
      BuildContext context, ThemeData theme, SteamGame result, int index, bool isSelected, bool isRepeatingKey);
  Widget _buildInfoResult(BuildContext context, ThemeData theme, LauncherInfoResult result, int index, bool isSelected,
      bool isRepeatingKey);
  Widget _buildQuickActionResult(BuildContext context, ThemeData theme, QuickActionMenuEntry quickAction, int index,
      bool isSelected, bool isRepeatingKey);
  Widget _buildWindowResult(
      BuildContext context, ThemeData theme, PlatformWindow window, int index, bool isSelected, bool isRepeatingKey);
  Widget _buildBrowserTabResult(
      BuildContext context, ThemeData theme, BrowserTab browserTab, int index, bool isSelected, bool isRepeatingKey);
  Widget build(BuildContext context);
  Widget _buildLauncherAppearanceFrame(Widget frame);
  Widget _buildHeightResizeHandle(Color accent, Color onSurface);
  Widget _buildResultsHeaderWithBadges(Color accent, Color onSurface);
  Widget _buildCopiedFilesBubble(Color accent, Color onSurface);
  Widget _buildInfoBadge(Color accent, Color onSurface);
  bool get _pluginCanGoBack;
  bool get _pluginOwnsFormFocus;
  bool get _canFocusLauncher;
  double get _pluginPreviewWidth;
  PluginAction get _launcherWindowAction;
  PluginEventScope get _topPluginScope;
  void _openLauncherPanel(BuildContext context, Widget child);
}
