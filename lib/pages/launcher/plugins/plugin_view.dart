import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image/image.dart' as image;
import 'package:just_audio/just_audio.dart';
import 'package:markdown_widget/markdown_widget.dart';
import '../../../platform/clipboard_service.dart';
import '../../../platform/platform_models.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../../models/win32/win_utils.dart';
import '../../../widgets/widgets/windows_scroll.dart';
import '../result/result_row.dart';
import 'plugin_form_view.dart';
import 'plugin_icons.dart';
import 'plugin_protocol.dart';

/// Renders the live plugin UI described by a [PluginRenderFrame], replacing the
/// launcher's default results list while a plugin is active.
///
/// Supports every declarative plugin layout, including composite, calendar,
/// and gallery views. Selection is owned by the launcher and passed down as
/// [activeIndex]; taps and hovers are reported through [onTapItem] /
/// [onHoverItem]. The widget keeps the highlighted item scrolled into view.
class PluginView extends StatefulWidget {
  const PluginView({
    super.key,
    required this.frame,
    required this.activeIndex,
    required this.isRepeating,
    required this.onTapItem,
    required this.onHoverItem,
    required this.onFormSubmit,
    required this.onFormCancel,
    required this.onFormChange,
    required this.onFormValidate,
    required this.onLoadMore,
    required this.onEmptyAction,
    required this.onMetadataAction,
    required this.onFloatingAction,
    required this.selectedIdsFor,
    required this.onToggleSelection,
    required this.onToggleTree,
    required this.onChartSelect,
    required this.onChartRangeSelect,
    required this.onToolbarChange,
    required this.onTableSort,
    required this.onInlineEdit,
    required this.onDropFiles,
    required this.onCancelOperation,
    required this.onNavigate,
    required this.onNavigateBack,
    required this.canNavigateBack,
    required this.onKanbanMove,
    required this.onCalendarNavigate,
    this.onOpenActions,
    this.onMarkdownKeyEvent,
    this.onItemNavigation,
    this.detailScrollController,
  });

  final PluginRenderFrame frame;
  final int activeIndex;
  final bool isRepeating;

  /// [frame] is the top-level frame for ordinary views and the owning panel's
  /// nested frame for dashboard items.
  final void Function(PluginEventScope scope, PluginRenderFrame frame, int index) onTapItem;
  final void Function(PluginEventScope scope, PluginRenderFrame frame, int index) onHoverItem;

  /// Launcher-owned controller for the detail document, so arrow/page keys
  /// (handled by the launcher) can scroll it.
  final ScrollController? detailScrollController;

  /// Form view: the user pressed Enter/submit with these field values.
  /// [button] is the pressed `form.buttons` id, when the form declared any.
  final void Function(PluginEventScope scope, Map<String, Object?> values, {String? button}) onFormSubmit;

  /// Form view: the user pressed Escape.
  final void Function(PluginEventScope scope) onFormCancel;

  /// Form view: a `watch: true` field changed.
  final void Function(PluginEventScope scope, String fieldId, Map<String, Object?> values) onFormChange;
  final void Function(PluginEventScope scope, String fieldId, Map<String, Object?> values) onFormValidate;

  /// The user scrolled near the end of a `hasMore` list/grid.
  final void Function(PluginEventScope scope) onLoadMore;

  /// The empty state's call-to-action button was clicked.
  final void Function(PluginEventScope scope, PluginAction action) onEmptyAction;

  /// A metadata action button was clicked. Preview metadata belongs to its
  /// selected item; detail metadata uses an empty item id.
  final void Function(PluginEventScope scope, String itemId, PluginAction action) onMetadataAction;

  /// A bottom-right `floatingAction` button was pressed.
  final void Function(PluginEventScope scope, PluginAction action) onFloatingAction;
  final Set<String> Function(PluginEventScope scope) selectedIdsFor;
  final void Function(PluginEventScope scope, String id) onToggleSelection;
  final void Function(PluginEventScope scope, String id, bool expanded) onToggleTree;
  final void Function(PluginEventScope scope, String seriesId, int index, double value) onChartSelect;
  final void Function(PluginEventScope scope, int startIndex, int endIndex) onChartRangeSelect;
  final void Function(
    PluginEventScope scope,
    String id, {
    String? value,
    List<String>? values,
    String? direction,
  }) onToolbarChange;
  final void Function(PluginEventScope scope, String columnId, String direction) onTableSort;
  final void Function(PluginEventScope scope, String itemId, String field, Object? value) onInlineEdit;
  final void Function(PluginEventScope scope, String dropZoneId, List<String> paths) onDropFiles;
  final void Function(PluginEventScope scope, String operationId) onCancelOperation;
  final void Function(String targetPageId) onNavigate;
  final VoidCallback onNavigateBack;
  final bool canNavigateBack;
  final void Function(PluginEventScope scope, String id, String columnId, int index) onKanbanMove;
  final void Function(PluginEventScope scope, String date, String mode) onCalendarNavigate;

  /// Ctrl+K pressed inside a form (the launcher opens the actions palette).
  final VoidCallback? onOpenActions;

  /// Forwards shortcuts pressed while a selectable markdown region owns focus
  /// back to the launcher's plugin keyboard handler.
  final KeyEventResult Function(KeyEvent event)? onMarkdownKeyEvent;

  /// Lets the launcher restore its shortcut focus after an item opens a new
  /// plugin page with the mouse.
  final VoidCallback? onItemNavigation;

  @override
  State<PluginView> createState() => _PluginViewState();
}

class _PluginViewState extends State<PluginView> {
  static const String _previewWidthPercentSetting = 'pluginPreviewWidthPercent';

  final ScrollController _scrollController = ScrollController();
  final ScrollController _dashboardScrollController = ScrollController();
  final Map<String, ScrollController> _dashboardPanelScrollControllers = <String, ScrollController>{};
  final Map<(PluginRenderFrame, int), GlobalKey> _itemKeys = <(PluginRenderFrame, int), GlobalKey>{};
  final Map<String, double> _pageScrollOffsets = <String, double>{};
  final Map<String, double> _pageDetailOffsets = <String, double>{};
  final Map<String, Map<String, Object?>> _formStateByPage = <String, Map<String, Object?>>{};
  final Map<String, Map<String, double>> _tableWidths = <String, Map<String, double>>{};
  final Map<String, Set<String>> _hiddenTableColumns = <String, Set<String>>{};
  final Map<String, (String, String)> _tableSortState = <String, (String, String)>{};
  final Set<String> _dismissedBanners = <String>{};
  final AudioPlayer _mediaPlayer = AudioPlayer();
  final List<StreamSubscription<dynamic>> _mediaSubscriptions = <StreamSubscription<dynamic>>[];

  String? _activeMediaItemId;
  Duration _mediaPosition = Duration.zero;
  Duration? _mediaDuration;
  bool _mediaPlaying = false;
  bool _mediaLoading = false;
  String? _mediaError;
  bool _pageDropActive = false;
  (PluginRenderFrame, String, String)? _editingCell;
  TextEditingController? _editingController;

  PluginRenderFrame? _dashboardActiveFrame;
  int _dashboardActiveIndex = -1;

  // When the selection moves because the pointer hovered a new row, we must NOT
  // scroll it into view — recentering the list under the cursor makes it hover
  // yet another row, producing runaway auto-scroll. Only keyboard-driven
  // selection changes scroll; hovering leaves the scroll offset alone so the
  // user can scroll manually.
  bool _selectionFromHover = false;

  /// One `loadMore` per frame: set when the user nears the end of a `hasMore`
  /// list, cleared when the plugin answers with a different item count.
  bool _loadMoreRequested = false;
  bool _chatAwayFromBottom = false;
  bool _chatLoadMoreRequested = false;
  double? _chatLoadMorePreviousPixels;
  double? _chatLoadMorePreviousMaxExtent;
  double? _previewWidthPercent;

  @override
  void initState() {
    super.initState();
    _previewWidthPercent = Boxes.pref.getDouble(_previewWidthPercentSetting)?.clamp(0.0, 100.0).toDouble();
    _mediaSubscriptions.addAll(<StreamSubscription<dynamic>>[
      _mediaPlayer.positionStream.listen((Duration value) {
        if (mounted) setState(() => _mediaPosition = value);
      }),
      _mediaPlayer.durationStream.listen((Duration? value) {
        if (mounted) setState(() => _mediaDuration = value);
      }),
      _mediaPlayer.playerStateStream.listen((PlayerState value) {
        if (!mounted) return;
        setState(() {
          _mediaPlaying = value.playing;
          _mediaLoading =
              value.processingState == ProcessingState.loading || value.processingState == ProcessingState.buffering;
        });
      }),
      _mediaPlayer.errorStream.listen((PlayerException value) {
        if (mounted) setState(() => _mediaError = value.message);
      }),
    ]);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _dashboardScrollController.dispose();
    for (final ScrollController controller in _dashboardPanelScrollControllers.values) {
      controller.dispose();
    }
    for (final StreamSubscription<dynamic> subscription in _mediaSubscriptions) {
      subscription.cancel();
    }
    unawaited(_mediaPlayer.dispose());
    _editingController?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PluginView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeIndex != widget.activeIndex) {
      final bool fromHover = _selectionFromHover;
      _selectionFromHover = false;
      if (!fromHover) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollActiveIntoView());
      }
    }
    if (oldWidget.frame.items.length != widget.frame.items.length) _loadMoreRequested = false;
    if (widget.frame.view == PluginViewType.chat &&
        _chatLoadMoreRequested &&
        (oldWidget.frame.items.length != widget.frame.items.length || !widget.frame.hasMore)) {
      final double? previousPixels = _chatLoadMorePreviousPixels;
      final double? previousMaxExtent = _chatLoadMorePreviousMaxExtent;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        if (previousPixels != null &&
            previousMaxExtent != null &&
            widget.frame.items.length > oldWidget.frame.items.length) {
          final double addedExtent =
              (_scrollController.position.maxScrollExtent - previousMaxExtent).clamp(0.0, double.infinity).toDouble();
          final double target = (previousPixels + addedExtent)
              .clamp(
                _scrollController.position.minScrollExtent,
                _scrollController.position.maxScrollExtent,
              )
              .toDouble();
          _scrollController.jumpTo(target);
        }
        if (mounted) {
          setState(() {
            _chatLoadMoreRequested = false;
            _chatLoadMorePreviousPixels = null;
            _chatLoadMorePreviousMaxExtent = null;
          });
        }
      });
    }
    if (!identical(oldWidget.frame, widget.frame)) {
      _dashboardActiveFrame = null;
      _dashboardActiveIndex = -1;
      _itemKeys.clear();
      if (oldWidget.frame.view != PluginViewType.chat || widget.frame.view != PluginViewType.chat) {
        _chatAwayFromBottom = false;
      }
    }
    _followStreamingDetail(oldWidget);
    _followChat(oldWidget);
    _followLog(oldWidget);
    _restorePageState(oldWidget.frame);
  }

  String _pageKey(PluginRenderFrame frame) => frame.page?.id ?? '__legacy__';

  void _restorePageState(PluginRenderFrame oldFrame) {
    final String oldKey = _pageKey(oldFrame);
    final String newKey = _pageKey(widget.frame);
    if (oldKey == newKey) return;
    if (_scrollController.hasClients) _pageScrollOffsets[oldKey] = _scrollController.offset;
    final ScrollController? detail = widget.detailScrollController;
    if (detail != null && detail.hasClients) _pageDetailOffsets[oldKey] = detail.offset;
    if (widget.frame.page?.preserveState == false) {
      _pageScrollOffsets.remove(newKey);
      _pageDetailOffsets.remove(newKey);
      _formStateByPage.remove(newKey);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(
          (_pageScrollOffsets[newKey] ?? 0).clamp(0.0, _scrollController.position.maxScrollExtent),
        );
      }
      if (detail != null && detail.hasClients) {
        detail.jumpTo((_pageDetailOffsets[newKey] ?? 0).clamp(0.0, detail.position.maxScrollExtent));
      }
    });
  }

  /// Streaming `detail.append`: when the document grew and the user was
  /// already reading its end, keep the view pinned to the bottom so new chunks
  /// stay visible (scrolling up detaches — no forced follow).
  void _followStreamingDetail(PluginView oldWidget) {
    if (widget.frame.view != PluginViewType.detail) return;
    final String previous = oldWidget.frame.detailMarkdown ?? '';
    final String next = widget.frame.detailMarkdown ?? '';
    if (next.isEmpty) return;
    final ScrollController? controller = widget.detailScrollController;

    // An empty loading frame followed by the real document is a replacement,
    // not a stream append. Start it at the top; otherwise the empty frame looks
    // "at bottom" and the follow logic jumps a newly opened email to its end.
    if (oldWidget.frame.view != PluginViewType.detail || previous.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || controller == null || !controller.hasClients) return;
        controller.jumpTo(0);
      });
      return;
    }

    if (next.length <= previous.length || !next.startsWith(previous)) return;
    if (controller == null || !controller.hasClients) return;
    final ScrollPosition position = controller.position;
    // Measured before this frame's content lands, so this is "was at bottom".
    if (position.pixels < position.maxScrollExtent - 60) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !controller.hasClients) return;
      controller.jumpTo(controller.position.maxScrollExtent);
    });
  }

  /// A chat starts at its newest message and stays there as new messages arrive
  /// unless the user has deliberately scrolled back through the conversation.
  bool _chatIsAtBottom(ScrollController controller) {
    if (!controller.hasClients) return true;
    final ScrollPosition position = controller.position;
    return position.pixels >= position.maxScrollExtent - 72;
  }

  void _followChat(PluginView oldWidget) {
    if (widget.frame.view != PluginViewType.chat) return;
    final bool enteredChat = oldWidget.frame.view != PluginViewType.chat;
    final bool frameChanged = !identical(oldWidget.frame, widget.frame);
    if (!enteredChat && !frameChanged) return;
    // Network images can grow the chat after its first layout. Pin a few times
    // while entering an empty chat so its actual last message—not the initial
    // pre-image layout—ends up on screen.
    final bool openingConversation = enteredChat || oldWidget.frame.items.isEmpty;
    final bool wasAtBottom = openingConversation || (!_chatAwayFromBottom && _chatIsAtBottom(_scrollController));
    void pinToEnd() {
      if (!mounted || !_scrollController.hasClients) return;
      // Use the position from before the new frame landed. Once a new message
      // is laid out, maxScrollExtent grows, so checking "at bottom" here would
      // incorrectly classify a user who was at the bottom as scrolled away.
      if (!wasAtBottom || _chatAwayFromBottom) return;
      if (openingConversation && !_chatIsAtBottom(_scrollController)) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      if (_chatAwayFromBottom && mounted) setState(() => _chatAwayFromBottom = false);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => pinToEnd());
    if (openingConversation) {
      Timer(const Duration(milliseconds: 180), pinToEnd);
      Timer(const Duration(milliseconds: 650), pinToEnd);
    }
  }

  void _pinChatToEndIfFollowing(ScrollController controller) {
    if (!mounted || _chatAwayFromBottom || !controller.hasClients || !_chatIsAtBottom(controller)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _chatAwayFromBottom || !controller.hasClients) return;
      controller.jumpTo(controller.position.maxScrollExtent);
    });
  }

  void _followLog(PluginView oldWidget) {
    if (widget.frame.view != PluginViewType.log || !widget.frame.logFollow) return;
    final bool enteredLog = oldWidget.frame.view != PluginViewType.log;
    final bool gainedLines = widget.frame.logLines.length > oldWidget.frame.logLines.length;
    if (!enteredLog && !gainedLines) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final ScrollPosition position = _scrollController.position;
      if (!enteredLog && position.pixels < position.maxScrollExtent - 60) return;
      _scrollController.jumpTo(position.maxScrollExtent);
    });
  }

  /// Fires `loadMore` when the user scrolls near the end of a `hasMore` frame.
  bool _onScrollNotification(PluginRenderFrame frame, ScrollNotification notification) {
    if (!frame.hasMore || _loadMoreRequested) return false;
    final ScrollMetrics metrics = notification.metrics;
    if (metrics.axis != Axis.vertical) return false;
    if (metrics.pixels >= metrics.maxScrollExtent - 200) {
      _loadMoreRequested = true;
      widget.onLoadMore(_scopeFor(frame));
    }
    return false;
  }

  /// Reports a hover selection to the launcher, flagging the resulting
  /// [activeIndex] change so [didUpdateWidget] skips the auto-scroll.
  void _hoverSelect(PluginRenderFrame frame, int index) {
    if (identical(frame, widget.frame)) {
      if (index != widget.activeIndex) _selectionFromHover = true;
    } else if (!identical(_dashboardActiveFrame, frame) || _dashboardActiveIndex != index) {
      setState(() {
        _dashboardActiveFrame = frame;
        _dashboardActiveIndex = index;
      });
    }
    widget.onHoverItem(_scopeFor(frame), frame, index);
  }

  void _tapItem(PluginRenderFrame frame, int index) {
    // Selection-mode frames use pointer taps to toggle batch membership. Enter
    // still fires the primary action for the highlighted item, so plugins can
    // offer an explicit batch command without accidental navigation.
    if (frame.multiSelect) {
      widget.onToggleSelection(_scopeFor(frame), frame.items[index].id);
      return;
    }
    if (!identical(frame, widget.frame)) {
      setState(() {
        _dashboardActiveFrame = frame;
        _dashboardActiveIndex = index;
      });
    }
    widget.onTapItem(_scopeFor(frame), frame, index);
    widget.onItemNavigation?.call();
  }

  bool _isSelected(PluginRenderFrame frame, int index) => identical(frame, widget.frame)
      ? index == widget.activeIndex
      : identical(frame, _dashboardActiveFrame) && index == _dashboardActiveIndex;

  void _scrollActiveIntoView() {
    if (!mounted) return;
    final BuildContext? itemContext = _itemKeys[(widget.frame, widget.activeIndex)]?.currentContext;
    if (itemContext == null) return;
    Scrollable.ensureVisible(
      itemContext,
      alignment: 0.5,
      duration: widget.isRepeating ? Duration.zero : const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
    );
  }

  GlobalKey _keyFor(PluginRenderFrame frame, int index) => _itemKeys.putIfAbsent((frame, index), () => GlobalKey());

  ScrollController _dashboardPanelController(String panelId) =>
      _dashboardPanelScrollControllers.putIfAbsent(panelId, ScrollController.new);

  String? _panelIdFor(PluginRenderFrame frame) {
    for (final PluginDashboardPanel panel in widget.frame.dashboardPanels) {
      if (identical(panel.frame, frame)) return panel.id;
    }
    return null;
  }

  String _surfaceKey(PluginRenderFrame frame) => <String>[
        widget.frame.page?.id ?? frame.page?.id ?? '__legacy__',
        _panelIdFor(frame) ?? '',
        frame.elementId ?? '',
      ].join(':');

  PluginEventScope _scopeFor(PluginRenderFrame frame) => PluginEventScope(
        pageId: widget.frame.page?.id ?? frame.page?.id,
        panelId: identical(frame, widget.frame) ? null : _panelIdFor(frame),
        elementId: frame.elementId,
      );

  Set<String> _selectedIds(PluginRenderFrame frame) => widget.selectedIdsFor(_scopeFor(frame));

  @override
  Widget build(BuildContext context) {
    final PluginRenderFrame frame = widget.frame;
    if (frame.view == PluginViewType.operation) {
      final Widget operation = frame.operation == null
          ? _buildEmptyOrLoading(frame)
          : Column(children: <Widget>[
              _PluginOperationBar(
                operation: frame.operation!,
                onCancel: () => widget.onCancelOperation(_scopeFor(frame), frame.operation!.id),
              ),
            ]);
      return _decorateFrame(operation, frame, _scopeFor(frame), includeOperation: false);
    }

    Widget body;
    if (frame.view == PluginViewType.form) {
      final PluginForm? form = frame.form;
      final PluginEventScope scope = _scopeFor(frame);
      body = form == null
          ? _buildEmptyOrLoading(frame)
          : PluginFormView(
              form: form,
              initialValues: _formStateByPage[_pageKey(frame)] ?? const <String, Object?>{},
              onStateChanged: (Map<String, Object?> values) => _formStateByPage[_pageKey(frame)] = values,
              onSubmit: (Map<String, Object?> values, {String? button}) =>
                  widget.onFormSubmit(scope, values, button: button),
              onCancel: () => widget.onFormCancel(scope),
              onChanged: (String fieldId, Map<String, Object?> values) => widget.onFormChange(scope, fieldId, values),
              onValidate: (String fieldId, Map<String, Object?> values) =>
                  widget.onFormValidate(scope, fieldId, values),
              onOpenActions: widget.onOpenActions,
            );
    } else if (frame.view == PluginViewType.dashboard) {
      body = _buildDashboard(frame);
    } else if (frame.view == PluginViewType.chart) {
      body = _buildChart(frame);
    } else if (frame.view == PluginViewType.detail) {
      body = _buildDetail(frame.detailMarkdown ?? '', frame.detailMetadata, scope: _scopeFor(frame));
    } else if (frame.view == PluginViewType.chat) {
      body = frame.items.isEmpty ? _buildEmptyOrLoading(frame) : _buildChat(frame);
    } else if (frame.view == PluginViewType.diff) {
      body = _buildDiff(frame);
    } else if (frame.view == PluginViewType.log) {
      body = _buildLog(frame);
    } else if (frame.view == PluginViewType.kanban) {
      body = _buildKanban(frame);
    } else if (frame.view == PluginViewType.calendar) {
      body = _buildCalendar(frame);
    } else if (frame.view == PluginViewType.gallery) {
      body = frame.items.isEmpty ? _buildEmptyOrLoading(frame) : _buildGallery(frame);
    } else if (frame.items.isEmpty) {
      body = _buildEmptyOrLoading(frame);
    } else {
      final Widget itemsPane = switch (frame.view) {
        PluginViewType.grid => _buildGrid(frame),
        PluginViewType.table => _buildTable(frame),
        PluginViewType.tree => _buildTree(frame),
        PluginViewType.timeline => _buildTimeline(frame),
        _ => _buildList(frame),
      };
      if (!frame.hasPreview) {
        body = itemsPane;
      } else {
        final int idx = widget.activeIndex.clamp(0, frame.items.length - 1);
        body = _buildSplitPreview(frame, itemsPane, frame.items[idx]);
      }
    }
    final PluginEventScope scope = _scopeFor(frame);
    return _decorateFrame(body, frame, scope);
  }

  Widget _decorateFrame(
    Widget child,
    PluginRenderFrame frame,
    PluginEventScope scope, {
    bool includeOperation = true,
  }) {
    Widget result = child;
    if (frame.dropZone != null) result = _withPageDropZone(result, frame, scope);
    if (frame.toolbarControls.isNotEmpty) result = _withToolbar(result, frame, scope);
    if (frame.banners.isNotEmpty) result = _withBanners(result, frame, scope);
    if (includeOperation) result = _withOperation(result, frame.operation, scope);
    result = _withPageChrome(result, frame);
    return _withFloatingActions(result, frame, scope);
  }

  Widget _buildSplitPreview(PluginRenderFrame frame, Widget itemsPane, PluginItem item) {
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
      final double fallback = frame.previewInitialWidth ?? constraints.maxWidth * 0.44;
      final double appWidth =
          MediaQuery.sizeOf(context).width > 0 ? MediaQuery.sizeOf(context).width : constraints.maxWidth;
      final double availableMax = (constraints.maxWidth - 180).clamp(160, frame.previewMaxWidth).toDouble();
      final double minWidth = frame.previewMinWidth.clamp(160, availableMax).toDouble();
      final double maxWidth = frame.previewMaxWidth.clamp(minWidth, availableMax).toDouble();
      final double preferredWidth = _previewWidthPercent == null ? fallback : appWidth * _previewWidthPercent! / 100;
      final double width = preferredWidth.clamp(minWidth, maxWidth).toDouble();
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        Expanded(child: itemsPane),
        MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (DragUpdateDetails details) {
              final double resizedWidth = (width - details.delta.dx).clamp(minWidth, maxWidth).toDouble();
              setState(() => _previewWidthPercent = resizedWidth / appWidth * 100);
            },
            onHorizontalDragEnd: (_) => _persistPreviewWidthPercent(),
            onHorizontalDragCancel: _persistPreviewWidthPercent,
            child: SizedBox(
              width: 12,
              child: Center(child: Container(width: 1, color: Design.accent.withAlpha(45))),
            ),
          ),
        ),
        SizedBox(width: width, child: _buildPreviewPane(item, scope: _scopeFor(frame))),
      ]);
    });
  }

  void _persistPreviewWidthPercent() {
    final double? percent = _previewWidthPercent;
    if (percent == null) return;
    unawaited(Boxes.updateSettings(_previewWidthPercentSetting, percent));
  }

  Widget _withFloatingActions(Widget child, PluginRenderFrame frame, PluginEventScope scope) {
    if (frame.floatingActions.isEmpty) return child;
    return Stack(
      children: <Widget>[
        Positioned.fill(child: child),
        Positioned(
          right: 14,
          bottom: 12,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: <Widget>[
              for (final PluginAction action in frame.floatingActions)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    backgroundColor: action.destructive ? const Color(0xFFE5534B) : Design.accent,
                    foregroundColor: action.destructive ? Colors.white : null,
                    elevation: 5,
                  ),
                  onPressed: () => widget.onFloatingAction(scope, action),
                  icon: Icon(PluginIcons.resolve(action.icon), size: 17),
                  label: Text(action.title,
                      style: TextStyle(fontSize: Design.baseFontSize + 3.5, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _withOperation(Widget child, PluginOperation? operation, PluginEventScope scope) {
    if (operation == null) return child;
    return Column(children: <Widget>[
      _PluginOperationBar(operation: operation, onCancel: () => widget.onCancelOperation(scope, operation.id)),
      Expanded(child: child),
    ]);
  }

  Widget _withToolbar(Widget child, PluginRenderFrame frame, PluginEventScope scope) {
    return Column(children: <Widget>[
      Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: Design.text.withAlpha(5),
          border: Border(bottom: BorderSide(color: Design.text.withAlpha(18))),
        ),
        child: Row(children: <Widget>[
          for (final PluginToolbarControl control in frame.toolbarControls) ...<Widget>[
            if (control.type == 'view')
              _PluginViewToggle(
                control: control,
                onSelected: (String value) => widget.onToolbarChange(scope, control.id, value: value),
              )
            else
              _PluginToolbarMenu(
                control: control,
                onSelected: (String value) {
                  if (control.multiple) {
                    final Set<String> next = control.values.toSet();
                    next.contains(value) ? next.remove(value) : next.add(value);
                    widget.onToolbarChange(scope, control.id, values: next.toList(growable: false));
                  } else {
                    widget.onToolbarChange(
                      scope,
                      control.id,
                      value: value,
                      direction: control.type == 'sort' ? control.direction : null,
                    );
                  }
                },
              ),
            if (control.type == 'sort')
              IconButton(
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                tooltip: control.direction == 'desc' ? 'Descending' : 'Ascending',
                icon: Icon(control.direction == 'desc' ? Icons.south_rounded : Icons.north_rounded, size: 14),
                onPressed: () => widget.onToolbarChange(
                  scope,
                  control.id,
                  value: control.value,
                  direction: control.direction == 'desc' ? 'asc' : 'desc',
                ),
              ),
            const SizedBox(width: 6),
          ],
          const Spacer(),
        ]),
      ),
      Expanded(child: child),
    ]);
  }

  Widget _withBanners(Widget child, PluginRenderFrame frame, PluginEventScope scope) {
    final List<PluginBanner> visible = frame.banners
        .where((PluginBanner banner) => !_dismissedBanners.contains('${_surfaceKey(frame)}:${banner.id}'))
        .toList(growable: false);
    if (visible.isEmpty) return child;
    return Column(children: <Widget>[
      for (final PluginBanner banner in visible)
        _PluginBannerView(
          banner: banner,
          onAction: (PluginAction action) => widget.onMetadataAction(scope, '', action),
          onDismiss: banner.dismissible
              ? () => setState(() => _dismissedBanners.add('${_surfaceKey(frame)}:${banner.id}'))
              : null,
        ),
      Expanded(child: child),
    ]);
  }

  Widget _withPageDropZone(Widget child, PluginRenderFrame frame, PluginEventScope scope) {
    final PluginDropZone zone = frame.dropZone!;
    bool accepted(String path) {
      if (zone.extensions.isEmpty || Directory(path).existsSync()) return true;
      final String lower = path.toLowerCase();
      return zone.extensions
          .any((String extension) => lower.endsWith(extension.startsWith('.') ? extension : '.$extension'));
    }

    return DropTarget(
      onDragEntered: (_) => setState(() => _pageDropActive = true),
      onDragExited: (_) => setState(() => _pageDropActive = false),
      onDragDone: (DropDoneDetails details) {
        setState(() => _pageDropActive = false);
        List<String> paths =
            details.files.map((DropItem file) => file.path).where(accepted).take(zone.maxFiles).toList();
        if (!zone.multiple && paths.isNotEmpty) paths = <String>[paths.first];
        if (paths.isNotEmpty) widget.onDropFiles(scope, zone.id, paths);
      },
      child: Column(children: <Widget>[
        AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          height: _pageDropActive ? 54 : 38,
          margin: const EdgeInsets.fromLTRB(8, 7, 8, 0),
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: _pageDropActive ? Design.accent.withAlpha(24) : Design.text.withAlpha(6),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: _pageDropActive ? Design.accent.withAlpha(145) : Design.text.withAlpha(22)),
          ),
          child: Row(children: <Widget>[
            Icon(Icons.file_download_outlined,
                size: 16, color: _pageDropActive ? Design.accent : Design.text.withAlpha(120)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(_pageDropActive ? 'Release to attach' : zone.label,
                        style: TextStyle(
                            fontSize: Design.baseFontSize + 1.5,
                            fontWeight: FontWeight.w600,
                            color: Design.text.withAlpha(190))),
                    if (zone.hint.isNotEmpty)
                      Text(zone.hint,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(90))),
                  ]),
            ),
          ]),
        ),
        Expanded(child: child),
      ]),
    );
  }

  Widget _withPageChrome(Widget child, PluginRenderFrame frame) {
    final PluginPageInfo? page = frame.page;
    if (page == null && !widget.canNavigateBack) return child;
    final List<PluginBreadcrumb> breadcrumbs = page?.breadcrumbs ?? const <PluginBreadcrumb>[];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Container(
        padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
        decoration: BoxDecoration(
          color: Design.text.withAlpha(5),
          border: Border(bottom: BorderSide(color: Design.text.withAlpha(18))),
        ),
        child: Row(children: <Widget>[
          if (widget.canNavigateBack)
            IconButton(
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 28, height: 26),
              padding: EdgeInsets.zero,
              tooltip: 'Back',
              onPressed: widget.onNavigateBack,
              icon: Icon(Icons.arrow_back_rounded, size: 15, color: Design.text.withAlpha(160)),
            ),
          for (int index = 0; index < breadcrumbs.length; index++) ...<Widget>[
            if (index > 0) Icon(Icons.chevron_right_rounded, size: 13, color: Design.text.withAlpha(70)),
            InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () => widget.onNavigate(breadcrumbs[index].id),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                child: Text(breadcrumbs[index].label,
                    style: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text.withAlpha(115))),
              ),
            ),
          ],
          if (page != null && page.title.isNotEmpty) ...<Widget>[
            if (breadcrumbs.isNotEmpty) Icon(Icons.chevron_right_rounded, size: 13, color: Design.text.withAlpha(70)),
            Flexible(
              child: Text(page.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: Design.baseFontSize + 1,
                      fontWeight: FontWeight.w700,
                      color: Design.text.withAlpha(190))),
            ),
          ],
        ]),
      ),
      Expanded(child: child),
    ]);
  }

  /// A dashboard is deliberately composition-only: each panel carries the same
  /// view payload it would use as a top-level frame. `stack` gives a report-like
  /// scrollable result; `tabs` lets a plugin expose the same panels compactly.
  Widget _buildDashboard(PluginRenderFrame frame) {
    final List<PluginDashboardPanel> panels = frame.dashboardPanels;
    if (panels.isEmpty) return _buildEmptyOrLoading(frame);
    if (frame.dashboardLayout == 'tabs') {
      return DefaultTabController(
        length: panels.length,
        child: Column(children: <Widget>[
          Material(
            color: Colors.transparent,
            child: TabBar(
              isScrollable: true,
              dividerColor: Design.text.withAlpha(20),
              labelColor: Design.accent,
              unselectedLabelColor: Design.text.withAlpha(135),
              tabs: <Widget>[for (final PluginDashboardPanel panel in panels) Tab(text: panel.title)],
            ),
          ),
          Expanded(
              child: TabBarView(children: <Widget>[
            for (final PluginDashboardPanel panel in panels) _dashboardPanel(panel, fill: true)
          ])),
        ]),
      );
    }
    return WindowsScrollView(
      controller: _dashboardScrollController,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[for (final PluginDashboardPanel panel in panels) _dashboardPanel(panel)],
        ),
      ),
    );
  }

  Widget _dashboardPanel(PluginDashboardPanel panel, {bool fill = false}) {
    final PluginRenderFrame frame = panel.frame;
    final PluginEventScope scope = _scopeFor(frame);
    final ScrollController scrollController = _dashboardPanelController(panel.id);
    if (frame.view == PluginViewType.operation && frame.operation != null) {
      final Widget operation = Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _PluginOperationBar(
          operation: frame.operation!,
          onCancel: () => widget.onCancelOperation(scope, frame.operation!.id),
        ),
      );
      final double height = panel.height ?? 58;
      return fill
          ? Align(alignment: Alignment.topCenter, child: SizedBox(height: height, child: operation))
          : SizedBox(height: height, child: operation);
    }
    final bool itemView = frame.view == PluginViewType.list ||
        frame.view == PluginViewType.grid ||
        frame.view == PluginViewType.table ||
        frame.view == PluginViewType.tree ||
        frame.view == PluginViewType.timeline ||
        frame.view == PluginViewType.kanban ||
        frame.view == PluginViewType.gallery;
    final Widget body = itemView && frame.items.isEmpty
        ? _buildEmptyOrLoading(frame)
        : switch (frame.view) {
            PluginViewType.detail => _buildDetail(frame.detailMarkdown ?? '', frame.detailMetadata,
                controller: scrollController, scope: scope),
            PluginViewType.chat => _buildChat(frame, controller: scrollController),
            PluginViewType.form => frame.form == null
                ? _buildEmptyOrLoading(frame)
                : PluginFormView(
                    form: frame.form!,
                    scrollController: scrollController,
                    draggable: true,
                    initialValues:
                        _formStateByPage['${_pageKey(widget.frame)}:${panel.id}'] ?? const <String, Object?>{},
                    onStateChanged: (Map<String, Object?> values) =>
                        _formStateByPage['${_pageKey(widget.frame)}:${panel.id}'] = values,
                    onSubmit: (Map<String, Object?> values, {String? button}) =>
                        widget.onFormSubmit(scope, values, button: button),
                    onCancel: () => widget.onFormCancel(scope),
                    onChanged: (String fieldId, Map<String, Object?> values) =>
                        widget.onFormChange(scope, fieldId, values),
                    onValidate: (String fieldId, Map<String, Object?> values) =>
                        widget.onFormValidate(scope, fieldId, values),
                    onOpenActions: widget.onOpenActions,
                  ),
            PluginViewType.table => _buildTable(frame, controller: scrollController),
            PluginViewType.tree => _buildTree(frame, controller: scrollController),
            PluginViewType.timeline => _buildTimeline(frame, controller: scrollController),
            PluginViewType.chart => _buildChart(frame),
            PluginViewType.kanban => _buildKanban(frame, controller: scrollController),
            PluginViewType.diff => _buildDiff(frame, controller: scrollController),
            PluginViewType.log => _buildLog(frame, controller: scrollController),
            PluginViewType.calendar => _buildCalendar(frame, controller: scrollController),
            PluginViewType.gallery => _buildGallery(frame, controller: scrollController),
            PluginViewType.operation => _buildEmptyOrLoading(frame),
            PluginViewType.grid => _buildGrid(frame, controller: scrollController),
            _ => _buildList(frame, controller: scrollController),
          };
    Widget panelBody = body;
    if (frame.dropZone != null) panelBody = _withPageDropZone(panelBody, frame, scope);
    if (frame.toolbarControls.isNotEmpty) panelBody = _withToolbar(panelBody, frame, scope);
    if (frame.banners.isNotEmpty) panelBody = _withBanners(panelBody, frame, scope);
    panelBody = _withOperation(panelBody, frame.operation, scope);
    final double height = panel.height ?? (frame.view == PluginViewType.operation ? 64 : 240);
    final Widget card = Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Design.text.withAlpha(7),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Design.text.withAlpha(18)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 6, 2),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(panel.title,
                      style: TextStyle(
                          fontSize: Design.baseFontSize + 1,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.7,
                          color: Design.text.withAlpha(140))),
                ),
                for (final PluginAction action in frame.frameActions)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                    padding: EdgeInsets.zero,
                    tooltip: action.title,
                    icon: Icon(PluginIcons.resolve(action.icon), size: 15),
                    color: action.destructive ? const Color(0xFFE5534B) : Design.text.withAlpha(155),
                    onPressed: () => widget.onMetadataAction(scope, '', action),
                  ),
              ],
            ),
          ),
          Expanded(child: _withFloatingActions(panelBody, frame, scope)),
        ]),
      ),
    );
    return fill ? SizedBox.expand(child: card) : SizedBox(height: height, child: card);
  }

  Widget _buildEmptyOrLoading(PluginRenderFrame frame) {
    if (frame.loading) {
      if (frame.loadingStyle == 'skeleton') {
        return _PluginSkeleton(view: frame.view, count: frame.skeletonCount);
      }
      final String? caption = frame.loadingText;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, value: frame.loadingProgress),
            ),
            if (caption != null && caption.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  caption,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: Design.baseFontSize + 3.5, color: Design.text.withAlpha(150)),
                ),
              ),
            ],
          ],
        ),
      );
    }
    final PluginEmptyState? empty = frame.empty;
    if (empty == null) {
      return Center(
        child: Text(frame.emptyText,
            style: TextStyle(fontSize: Design.baseFontSize + 2.5, color: Design.text.withAlpha(120))),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (empty.icon != null) ...<Widget>[
            Icon(PluginIcons.resolve(empty.icon), size: 26, color: Design.accent.withAlpha(140)),
            const SizedBox(height: 8),
          ],
          if (empty.title.isNotEmpty)
            Text(
              empty.title,
              style: TextStyle(
                  fontSize: Design.baseFontSize + 2.5, fontWeight: FontWeight.w600, color: Design.text.withAlpha(190)),
            ),
          if (empty.hint.isNotEmpty) ...<Widget>[
            const SizedBox(height: 3),
            Text(empty.hint, style: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text.withAlpha(110))),
          ],
          if (empty.action != null) ...<Widget>[
            const SizedBox(height: 10),
            _EmptyActionButton(
              action: empty.action!,
              onTap: () => widget.onEmptyAction(_scopeFor(frame), empty.action!),
            ),
          ],
        ],
      ),
    );
  }

  /// A slim uppercase section header, rendered whenever an item's `section`
  /// differs from the previous item's.
  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 2),
      child: Row(
        children: <Widget>[
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: Design.baseFontSize,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: Design.text.withAlpha(120),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Container(height: 1, color: Design.text.withAlpha(18))),
        ],
      ),
    );
  }

  /// A dimmed "loading more…" row at the end of a `hasMore` list/grid.
  Widget _loadMoreFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: 11,
            height: 11,
            child: CircularProgressIndicator(strokeWidth: 1.5, color: Design.accent.withAlpha(150)),
          ),
          const SizedBox(width: 8),
          Text('Loading more…', style: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text.withAlpha(110))),
        ],
      ),
    );
  }

  Widget _buildList(PluginRenderFrame frame, {ScrollController? controller}) {
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification notification) => _onScrollNotification(frame, notification),
      child: WindowsScrollView(
        controller: controller ?? _scrollController,
        draggable: controller != null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (int i = 0; i < frame.items.length; i++) ...<Widget>[
              if (frame.items[i].section != null && (i == 0 || frame.items[i].section != frame.items[i - 1].section))
                _sectionHeader(frame.items[i].section!),
              KeyedSubtree(
                key: _keyFor(frame, i),
                child: Column(
                  children: <Widget>[
                    _buildListItemRow(frame, i),
                    if (frame.items[i].progress != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 4),
                        child: _PluginProgressBar(value: frame.items[i].progress!),
                      ),
                  ],
                ),
              ),
            ],
            if (frame.hasMore) _loadMoreFooter(),
          ],
        ),
      ),
    );
  }

  /// Conversation surface. Each item is one message: `title` is the author,
  /// `subtitle` the message body, `icon` an optional avatar, and accessories
  /// (normally a timestamp) sit beside the author name.
  Widget _buildChat(PluginRenderFrame frame, {ScrollController? controller}) {
    final ScrollController chatController = controller ?? _scrollController;
    return Stack(
      children: <Widget>[
        NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification notification) {
            if (notification.metrics.axis != Axis.vertical) return false;
            if (frame.hasMore &&
                !_chatLoadMoreRequested &&
                notification.metrics.pixels <= notification.metrics.minScrollExtent + 120) {
              _chatLoadMoreRequested = true;
              _chatLoadMorePreviousPixels = notification.metrics.pixels;
              _chatLoadMorePreviousMaxExtent = notification.metrics.maxScrollExtent;
              widget.onLoadMore(_scopeFor(frame));
            }
            final bool away = notification.metrics.maxScrollExtent > 0 &&
                notification.metrics.pixels < notification.metrics.maxScrollExtent - 72;
            if (away != _chatAwayFromBottom && mounted) setState(() => _chatAwayFromBottom = away);
            return false;
          },
          child: WindowsScrollView(
            controller: chatController,
            draggable: controller != null,
            child: _selectableContent(
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (frame.hasMore) _loadMoreFooter(),
                    for (int i = 0; i < frame.items.length; i++) ...<Widget>[
                      if (frame.items[i].section != null &&
                          (i == 0 || frame.items[i].section != frame.items[i - 1].section))
                        _chatDateDivider(frame.items[i].section!),
                      KeyedSubtree(
                        key: _keyFor(frame, i),
                        child: _PluginChatMessage(
                          item: frame.items[i],
                          grouped: i > 0 &&
                              frame.items[i].section == frame.items[i - 1].section &&
                              frame.items[i].title == frame.items[i - 1].title,
                          onContentSizeChanged: () => _pinChatToEndIfFollowing(chatController),
                          onAction: (PluginAction action) =>
                              widget.onMetadataAction(_scopeFor(frame), frame.items[i].id, action),
                        ),
                      ),
                    ],
                    if (frame.typing != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(50, 5, 8, 0),
                        child: Text(
                          frame.typing!,
                          style: TextStyle(
                            fontSize: Design.baseFontSize + 1,
                            color: Design.text.withAlpha(105),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_chatAwayFromBottom)
          Positioned(
            right: 16,
            bottom: 12,
            child: _PluginChatJumpButton(
              onTap: () {
                if (!chatController.hasClients) return;
                chatController.animateTo(
                  chatController.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _chatDateDivider(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 13, 8, 5),
      child: Row(
        children: <Widget>[
          Expanded(child: Container(height: 1, color: Design.text.withAlpha(20))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              label,
              style: TextStyle(
                  fontSize: Design.baseFontSize, fontWeight: FontWeight.w700, color: Design.text.withAlpha(115)),
            ),
          ),
          Expanded(child: Container(height: 1, color: Design.text.withAlpha(20))),
        ],
      ),
    );
  }

  Widget? _accessoryBadge(PluginRenderFrame frame, PluginItem item, {bool multiSelect = false}) {
    if (item.accessories.isEmpty && !multiSelect) return null;
    final Set<String> selectedIds = _selectedIds(frame);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (multiSelect)
          GestureDetector(
            onTap: () => widget.onToggleSelection(_scopeFor(frame), item.id),
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(selectedIds.contains(item.id) ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 16, color: selectedIds.contains(item.id) ? Design.accent : Design.text.withAlpha(100)),
            ),
          ),
        for (final PluginAccessory accessory in item.accessories)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: LauncherSereneBadge(
              icon: accessory.icon != null ? PluginIcons.resolve(accessory.icon) : Icons.label_important_rounded,
              label: accessory.text,
              color: accessory.color ?? Design.accent,
            ),
          ),
      ],
    );
  }

  Widget _buildGrid(PluginRenderFrame frame, {ScrollController? controller}) {
    // Partition the items into runs sharing a `section`, each run its own grid
    // under a header (sections are ignored inside a run — keep them adjacent,
    // like the list view).
    final List<(String?, int, int)> runs = <(String?, int, int)>[]; // (section, start, end-exclusive)
    for (int i = 0; i < frame.items.length; i++) {
      final String? section = frame.items[i].section;
      if (runs.isEmpty || runs.last.$1 != section) {
        runs.add((section, i, i + 1));
      } else {
        runs[runs.length - 1] = (section, runs.last.$2, i + 1);
      }
    }

    Widget gridFor(int start, int end) {
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: end - start,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: frame.gridColumns,
          childAspectRatio: frame.gridAspectRatio,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
        ),
        itemBuilder: (BuildContext context, int offset) {
          final int i = start + offset;
          return KeyedSubtree(
            key: _keyFor(frame, i),
            child: _PluginGridTile(
              item: frame.items[i],
              isSelected: _isSelected(frame, i),
              onTap: () => _tapItem(frame, i),
              onHover: () => _hoverSelect(frame, i),
            ),
          );
        },
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification notification) => _onScrollNotification(frame, notification),
      child: WindowsScrollView(
        controller: controller ?? _scrollController,
        draggable: controller != null,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final (String?, int, int) run in runs) ...<Widget>[
                if (run.$1 != null) _sectionHeader(run.$1!),
                gridFor(run.$2, run.$3),
              ],
              if (frame.hasMore) _loadMoreFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTable(PluginRenderFrame frame, {ScrollController? controller}) {
    final List<PluginTableColumn> declaredColumns = frame.columns.isEmpty
        ? const <PluginTableColumn>[
            PluginTableColumn(id: 'title', label: 'Name'),
            PluginTableColumn(id: 'subtitle', label: 'Details')
          ]
        : frame.columns;
    final String pageKey = _surfaceKey(frame);
    final Set<String> hidden = _hiddenTableColumns.putIfAbsent(
      pageKey,
      () => declaredColumns
          .where((PluginTableColumn column) => !column.visible)
          .map((PluginTableColumn column) => column.id)
          .toSet(),
    );
    final List<PluginTableColumn> columns =
        declaredColumns.where((PluginTableColumn column) => !hidden.contains(column.id)).toList(growable: false);
    final Map<String, double> widths = _tableWidths.putIfAbsent(pageKey, () => <String, double>{});
    for (final PluginTableColumn column in declaredColumns) {
      widths.putIfAbsent(
        column.id,
        () => (column.width ?? 150).clamp(column.minWidth, column.maxWidth).toDouble(),
      );
    }
    if (frame.tableSortColumn != null) {
      _tableSortState[pageKey] = (frame.tableSortColumn!, frame.tableSortDirection);
    }
    final (String, String)? sort = _tableSortState[pageKey];

    Widget headerCell(PluginTableColumn column) {
      final bool active = sort?.$1 == column.id;
      return SizedBox(
        width: widths[column.id]!,
        child: Row(children: <Widget>[
          Expanded(
            child: InkWell(
              onTap: column.sortable
                  ? () {
                      final String direction = active && sort?.$2 == 'asc' ? 'desc' : 'asc';
                      setState(() => _tableSortState[pageKey] = (column.id, direction));
                      widget.onTableSort(_scopeFor(frame), column.id, direction);
                    }
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                child: Row(children: <Widget>[
                  Expanded(
                    child: Text(
                      column.label.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: Design.baseFontSize,
                        fontWeight: FontWeight.w700,
                        color: active ? Design.accent : Design.text.withAlpha(120),
                      ),
                    ),
                  ),
                  if (active)
                    Icon(sort!.$2 == 'desc' ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                        size: 11, color: Design.accent),
                ]),
              ),
            ),
          ),
          if (frame.tableResizable)
            MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (DragUpdateDetails details) {
                  setState(() {
                    widths[column.id] =
                        (widths[column.id]! + details.delta.dx).clamp(column.minWidth, column.maxWidth).toDouble();
                  });
                },
                child: SizedBox(
                    width: 7, child: Center(child: Container(width: 1, height: 18, color: Design.text.withAlpha(28)))),
              ),
            ),
        ]),
      );
    }

    Widget dataCell(PluginItem item, PluginTableColumn column) {
      final String value = _tableValue(item, column.id);
      final bool editable = column.editable || item.editableFields.contains(column.id);
      final bool editing = _editingCell?.$1 == frame && _editingCell?.$2 == item.id && _editingCell?.$3 == column.id;
      return SizedBox(
        width: widths[column.id]!,
        child: editing
            ? TextField(
                controller: _editingController,
                autofocus: true,
                style: TextStyle(fontSize: Design.baseFontSize + 1.5, color: Design.text),
                decoration: const InputDecoration(
                    isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 7, vertical: 5)),
                onSubmitted: (_) => _commitInlineEdit(frame, item.id, column.id),
                onEditingComplete: () => _commitInlineEdit(frame, item.id, column.id),
              )
            : GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: editable ? () => _beginInlineEdit(frame, item.id, column.id, value) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: column.align == 'end'
                        ? TextAlign.right
                        : column.align == 'center'
                            ? TextAlign.center
                            : TextAlign.left,
                    style: TextStyle(fontSize: Design.baseFontSize + 1.5, color: Design.text.withAlpha(200)),
                  ),
                ),
              ),
      );
    }

    return LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
      final double contentWidth = columns
          .fold<double>(0, (double total, PluginTableColumn column) => total + widths[column.id]!)
          .clamp(constraints.maxWidth - (frame.tableColumnVisibility ? 38 : 16), double.infinity)
          .toDouble();
      final Widget header = Container(
        height: 32,
        color: Design.text.withAlpha(10),
        child: Row(children: <Widget>[for (final PluginTableColumn column in columns) headerCell(column)]),
      );
      final Widget rows = WindowsScrollView(
        controller: controller ?? _scrollController,
        draggable: controller != null,
        child: Column(children: <Widget>[
          if (!frame.tableStickyHeader) header,
          for (int i = 0; i < frame.items.length; i++)
            KeyedSubtree(
              key: _keyFor(frame, i),
              child: _PluginStructuredRow(
                selected: _isSelected(frame, i),
                marked: _selectedIds(frame).contains(frame.items[i].id),
                multiSelect: frame.multiSelect,
                onTap: () => _tapItem(frame, i),
                onHover: () => _hoverSelect(frame, i),
                onToggle: () => widget.onToggleSelection(_scopeFor(frame), frame.items[i].id),
                child: Row(children: <Widget>[
                  for (final PluginTableColumn column in columns) dataCell(frame.items[i], column),
                ]),
              ),
            ),
          if (frame.hasMore) _loadMoreFooter(),
        ]),
      );
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Row(children: <Widget>[
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: contentWidth,
                height: constraints.maxHeight - 16,
                child: Column(children: <Widget>[
                  if (frame.tableStickyHeader) header,
                  Expanded(child: rows),
                ]),
              ),
            ),
          ),
          if (frame.tableColumnVisibility)
            Align(
              alignment: Alignment.topCenter,
              child: PopupMenuButton<String>(
                tooltip: 'Columns',
                icon: Icon(Icons.view_column_outlined, size: 16, color: Design.text.withAlpha(140)),
                onSelected: (String id) => setState(() {
                  if (hidden.contains(id)) {
                    hidden.remove(id);
                  } else if (columns.length > 1) {
                    hidden.add(id);
                  }
                }),
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  for (final PluginTableColumn column in declaredColumns)
                    CheckedPopupMenuItem<String>(
                      value: column.id,
                      checked: !hidden.contains(column.id),
                      child: Text(column.label),
                    ),
                ],
              ),
            ),
        ]),
      );
    });
  }

  Widget _buildListItemRow(PluginRenderFrame frame, int index) {
    final PluginItem item = frame.items[index];
    final String? editableField = item.editableFields.contains('title')
        ? 'title'
        : item.editableFields.contains('subtitle')
            ? 'subtitle'
            : null;
    final bool editing = _editingCell?.$1 == frame && _editingCell?.$2 == item.id && _editingCell?.$3 == editableField;
    if (editing && editableField != null) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: Design.accent.withAlpha(26),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Design.accent.withAlpha(80)),
        ),
        child: Row(children: <Widget>[
          _PluginIcon(name: item.icon, accent: Design.accent),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _editingController,
              autofocus: true,
              style: TextStyle(fontSize: Design.baseFontSize + 3.5, color: Design.text),
              decoration: InputDecoration(
                isDense: true,
                hintText: editableField == 'title' ? 'Title' : 'Subtitle',
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              ),
              onSubmitted: (_) => _commitInlineEdit(frame, item.id, editableField),
            ),
          ),
          IconButton(
            tooltip: 'Save',
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.check_rounded, size: 15),
            onPressed: () => _commitInlineEdit(frame, item.id, editableField),
          ),
        ]),
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onDoubleTap: editableField == null
          ? null
          : () => _beginInlineEdit(frame, item.id, editableField, _tableValue(item, editableField)),
      child: LauncherResultRow(
        isSelected: _isSelected(frame, index),
        isRepeating: widget.isRepeating,
        accent: Design.accent,
        onSurface: Design.text,
        onTap: () => _tapItem(frame, index),
        onHover: () => _hoverSelect(frame, index),
        icon: _PluginIcon(name: item.icon, accent: Design.accent),
        title: item.title,
        subtitle: item.subtitle,
        badge: _listBadge(frame, item),
        inlineMarkup: true,
        subtitleMaxLines: item.subtitleLines,
      ),
    );
  }

  Widget? _listBadge(PluginRenderFrame frame, PluginItem item) {
    final Widget? accessories = _accessoryBadge(frame, item, multiSelect: frame.multiSelect);
    final List<String> editable = <String>[
      if (item.editableFields.contains('title')) 'title',
      if (item.editableFields.contains('subtitle')) 'subtitle',
    ];
    if (editable.length < 2) return accessories;
    return Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
      if (accessories != null) accessories,
      PopupMenuButton<String>(
        tooltip: 'Edit field',
        iconSize: 15,
        padding: EdgeInsets.zero,
        onSelected: (String field) => _beginInlineEdit(frame, item.id, field, _tableValue(item, field)),
        itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
          for (final String field in editable)
            PopupMenuItem<String>(
              value: field,
              child: Text('Edit ${field == 'title' ? 'title' : 'subtitle'}'),
            ),
        ],
      ),
    ]);
  }

  String _tableValue(PluginItem item, String field) => field == 'title'
      ? item.title
      : field == 'subtitle'
          ? item.subtitle
          : item.cells[field] ?? '';

  void _beginInlineEdit(PluginRenderFrame frame, String itemId, String field, String value) {
    _editingController?.dispose();
    setState(() {
      _editingCell = (frame, itemId, field);
      _editingController = TextEditingController(text: value);
    });
  }

  void _commitInlineEdit(PluginRenderFrame frame, String itemId, String field) {
    if (_editingCell?.$1 != frame || _editingCell?.$2 != itemId || _editingCell?.$3 != field) return;
    final String value = _editingController?.text ?? '';
    widget.onInlineEdit(_scopeFor(frame), itemId, field, value);
    _editingController?.dispose();
    setState(() {
      _editingCell = null;
      _editingController = null;
    });
  }

  Widget _buildTree(PluginRenderFrame frame, {ScrollController? controller}) => WindowsScrollView(
        controller: controller ?? _scrollController,
        draggable: controller != null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(children: <Widget>[
            for (int i = 0; i < frame.items.length; i++)
              KeyedSubtree(
                  key: _keyFor(frame, i),
                  child: _PluginStructuredRow(
                    selected: _isSelected(frame, i),
                    marked: _selectedIds(frame).contains(frame.items[i].id),
                    multiSelect: frame.multiSelect,
                    onTap: () => _tapItem(frame, i),
                    onHover: () => _hoverSelect(frame, i),
                    onToggle: () => widget.onToggleSelection(_scopeFor(frame), frame.items[i].id),
                    child: Row(children: <Widget>[
                      SizedBox(width: frame.items[i].depth * 18.0),
                      GestureDetector(
                          onTap: () =>
                              widget.onToggleTree(_scopeFor(frame), frame.items[i].id, !frame.items[i].expanded),
                          child: Icon(frame.items[i].expanded ? Icons.expand_more : Icons.chevron_right,
                              size: 17, color: Design.text.withAlpha(145))),
                      const SizedBox(width: 5),
                      _PluginIcon(name: frame.items[i].icon, accent: Design.accent, size: 16),
                      const SizedBox(width: 7),
                      Expanded(
                          child: Text(frame.items[i].title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  TextStyle(fontSize: Design.baseFontSize + 3.5, color: Design.text.withAlpha(210)))),
                      if (frame.items[i].subtitle.isNotEmpty)
                        Text(frame.items[i].subtitle,
                            style: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text.withAlpha(120))),
                    ]),
                  )),
            if (frame.hasMore) _loadMoreFooter(),
          ]),
        ),
      );

  Widget _buildTimeline(PluginRenderFrame frame, {ScrollController? controller}) => WindowsScrollView(
        controller: controller ?? _scrollController,
        draggable: controller != null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(children: <Widget>[
            for (int i = 0; i < frame.items.length; i++)
              _PluginTimelineRow(
                item: frame.items[i],
                selected: _isSelected(frame, i),
                marked: _selectedIds(frame).contains(frame.items[i].id),
                multiSelect: frame.multiSelect,
                onTap: () => _tapItem(frame, i),
                onHover: () => _hoverSelect(frame, i),
                onToggle: () => widget.onToggleSelection(_scopeFor(frame), frame.items[i].id),
              ),
            if (frame.hasMore) _loadMoreFooter(),
          ]),
        ),
      );

  Widget _buildChart(PluginRenderFrame frame) => _PluginChart(
        title: frame.chartTitle,
        series: frame.chartSeries,
        options: frame.chartOptions,
        onSelect: (String seriesId, int index, double value) =>
            widget.onChartSelect(_scopeFor(frame), seriesId, index, value),
        onRangeSelect: (int startIndex, int endIndex) =>
            widget.onChartRangeSelect(_scopeFor(frame), startIndex, endIndex),
      );

  Widget _buildKanban(PluginRenderFrame frame, {ScrollController? controller}) {
    final List<PluginKanbanColumn> columns = frame.kanbanColumns.isNotEmpty
        ? frame.kanbanColumns
        : <PluginKanbanColumn>[
            for (final String id in frame.items.map((PluginItem item) => item.column ?? 'default').toSet())
              PluginKanbanColumn(id: id, title: id),
          ];
    if (columns.isEmpty) return _buildEmptyOrLoading(frame);
    final PluginEventScope scope = _scopeFor(frame);

    Widget dropTarget(PluginKanbanColumn column, int index, {Widget? child}) {
      return DragTarget<String>(
        onWillAcceptWithDetails: (DragTargetDetails<String> details) =>
            frame.items.any((PluginItem item) => item.id == details.data),
        onAcceptWithDetails: (DragTargetDetails<String> details) =>
            widget.onKanbanMove(scope, details.data, column.id, index),
        builder: (BuildContext context, List<String?> candidates, List<dynamic> rejected) => AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          height: child == null ? (candidates.isEmpty ? 7 : 28) : null,
          decoration: BoxDecoration(
            color: candidates.isEmpty ? Colors.transparent : Design.accent.withAlpha(24),
            borderRadius: BorderRadius.circular(5),
          ),
          child: child,
        ),
      );
    }

    return SingleChildScrollView(
      controller: controller ?? _scrollController,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final PluginKanbanColumn column in columns) ...<Widget>[
            SizedBox(
              width: 248,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Design.text.withAlpha(6),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Design.text.withAlpha(18)),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
                  child: Builder(builder: (BuildContext context) {
                    final List<(int, PluginItem)> cards = <(int, PluginItem)>[
                      for (int index = 0; index < frame.items.length; index++)
                        if ((frame.items[index].column ?? 'default') == column.id) (index, frame.items[index]),
                    ];
                    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                      Row(children: <Widget>[
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(color: column.color ?? Design.accent, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(column.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: Design.baseFontSize + 1,
                                  fontWeight: FontWeight.w700,
                                  color: Design.text.withAlpha(190))),
                        ),
                        Text(
                          column.limit == null ? '${cards.length}' : '${cards.length}/${column.limit}',
                          style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(90)),
                        ),
                      ]),
                      const SizedBox(height: 6),
                      for (int cardIndex = 0; cardIndex < cards.length; cardIndex++) ...<Widget>[
                        dropTarget(column, cardIndex),
                        Draggable<String>(
                          data: cards[cardIndex].$2.id,
                          feedback: Material(
                            color: Colors.transparent,
                            child: SizedBox(width: 232, child: _PluginKanbanCard(item: cards[cardIndex].$2)),
                          ),
                          childWhenDragging: Opacity(
                            opacity: 0.35,
                            child: _PluginKanbanCard(item: cards[cardIndex].$2),
                          ),
                          child: KeyedSubtree(
                            key: _keyFor(frame, cards[cardIndex].$1),
                            child: _PluginKanbanCard(
                              item: cards[cardIndex].$2,
                              selected: _isSelected(frame, cards[cardIndex].$1),
                              onTap: () => _tapItem(frame, cards[cardIndex].$1),
                              onHover: () => _hoverSelect(frame, cards[cardIndex].$1),
                            ),
                          ),
                        ),
                      ],
                      dropTarget(column, cards.length),
                    ]);
                  }),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildDiff(PluginRenderFrame frame, {ScrollController? controller}) {
    if (frame.diffLines.isEmpty) return _buildEmptyOrLoading(frame);
    return WindowsScrollView(
      controller: controller ?? _scrollController,
      draggable: controller != null,
      child: SelectionArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
          child: _buildDiffContent(
            frame.diffLines,
            mode: frame.diffMode,
            oldLabel: frame.diffOldLabel,
            newLabel: frame.diffNewLabel,
          ),
        ),
      ),
    );
  }

  Widget _buildDiffContent(
    List<PluginDiffLine> lines, {
    required String mode,
    required String oldLabel,
    required String newLabel,
  }) {
    final bool split = mode == 'split';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      if (split)
        Row(children: <Widget>[
          Expanded(child: _diffHeader(oldLabel)),
          const SizedBox(width: 1),
          Expanded(child: _diffHeader(newLabel)),
        ]),
      for (final PluginDiffLine line in lines)
        split ? _PluginSplitDiffRow(line: line) : _PluginUnifiedDiffRow(line: line),
    ]);
  }

  Widget _diffHeader(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        color: Design.text.withAlpha(10),
        child: Text(label,
            style: TextStyle(
                fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.w700, color: Design.text.withAlpha(150))),
      );

  Widget _buildLog(PluginRenderFrame frame, {ScrollController? controller}) {
    if (frame.logLines.isEmpty) return _buildEmptyOrLoading(frame);
    return WindowsScrollView(
      controller: controller ?? _scrollController,
      draggable: controller != null,
      child: SelectionArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final PluginLogLine line in frame.logLines) _PluginLogRow(line: line, wrap: frame.logWrap),
            ],
          ),
        ),
      ),
    );
  }

  DateTime _calendarAnchor(PluginRenderFrame frame) {
    final DateTime value = frame.calendarDate ?? DateTime.now();
    return DateTime(value.year, value.month, value.day);
  }

  String _calendarDateValue(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  bool _sameCalendarDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _buildCalendar(PluginRenderFrame frame, {ScrollController? controller}) {
    final DateTime anchor = _calendarAnchor(frame);
    final String mode = frame.calendarMode;
    final PluginEventScope scope = _scopeFor(frame);
    void navigate(DateTime date, String nextMode) =>
        widget.onCalendarNavigate(scope, _calendarDateValue(date), nextMode);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _PluginCalendarHeader(
          date: anchor,
          mode: mode,
          onPrevious: () => navigate(
            mode == 'month' ? DateTime(anchor.year, anchor.month - 1) : anchor.subtract(const Duration(days: 7)),
            mode,
          ),
          onNext: () => navigate(
            mode == 'month' ? DateTime(anchor.year, anchor.month + 1) : anchor.add(const Duration(days: 7)),
            mode,
          ),
          onToday: () => navigate(DateTime.now(), mode),
          onModeChanged: (String nextMode) => navigate(anchor, nextMode),
        ),
        Expanded(
          child: mode == 'agenda'
              ? _buildAgenda(frame, anchor, controller: controller)
              : _buildMonthCalendar(frame, anchor),
        ),
      ],
    );
  }

  Widget _buildMonthCalendar(PluginRenderFrame frame, DateTime anchor) {
    final DateTime first = DateTime(anchor.year, anchor.month);
    final int leading = (first.weekday - frame.calendarWeekStart + 7) % 7;
    final DateTime gridStart = first.subtract(Duration(days: leading));
    final List<String> weekdays = frame.calendarWeekStart == DateTime.sunday
        ? const <String>['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
        : const <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final DateTime today = DateTime.now();

    return Column(children: <Widget>[
      SizedBox(
        height: 22,
        child: Row(
          children: <Widget>[
            for (final String weekday in weekdays)
              Expanded(
                child: Center(
                  child: Text(
                    weekday.toUpperCase(),
                    style: TextStyle(
                      fontSize: Design.baseFontSize - 0.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: Design.text.withAlpha(95),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      Expanded(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double cellWidth = constraints.maxWidth / 7;
            final double cellHeight = constraints.maxHeight / 6;
            return GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(7, 0, 7, 7),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: cellWidth / cellHeight,
                mainAxisSpacing: 1,
                crossAxisSpacing: 1,
              ),
              itemCount: 42,
              itemBuilder: (BuildContext context, int dayOffset) {
                final DateTime day = gridStart.add(Duration(days: dayOffset));
                final List<(int, PluginItem)> events = <(int, PluginItem)>[
                  for (int index = 0; index < frame.items.length; index++)
                    if (frame.items[index].calendar != null &&
                        _sameCalendarDay(frame.items[index].calendar!.start, day))
                      (index, frame.items[index]),
                ];
                events.sort(((int, PluginItem) a, (int, PluginItem) b) {
                  final bool selectedA = _isSelected(frame, a.$1);
                  final bool selectedB = _isSelected(frame, b.$1);
                  if (selectedA != selectedB) return selectedA ? -1 : 1;
                  return a.$2.calendar!.start.compareTo(b.$2.calendar!.start);
                });
                final int visibleCount = cellHeight >= 66
                    ? 2
                    : cellHeight >= 38
                        ? 1
                        : 0;
                return _PluginCalendarDayCell(
                  day: day,
                  inMonth: day.month == anchor.month,
                  today: _sameCalendarDay(day, today),
                  eventCount: events.length,
                  visibleCount: visibleCount,
                  eventBuilder: (int eventIndex) {
                    final (int index, PluginItem item) = events[eventIndex];
                    return KeyedSubtree(
                      key: _keyFor(frame, index),
                      child: _PluginCalendarEventChip(
                        item: item,
                        selected: _isSelected(frame, index),
                        onTap: () => _tapItem(frame, index),
                        onHover: () => _hoverSelect(frame, index),
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    ]);
  }

  Widget _buildAgenda(PluginRenderFrame frame, DateTime anchor, {ScrollController? controller}) {
    final DateTime end = anchor.add(Duration(days: frame.calendarDays));
    final List<(int, PluginItem)> events = <(int, PluginItem)>[
      for (int index = 0; index < frame.items.length; index++)
        if (frame.items[index].calendar != null &&
            !frame.items[index].calendar!.start.isBefore(anchor) &&
            frame.items[index].calendar!.start.isBefore(end))
          (index, frame.items[index]),
    ]..sort(((int, PluginItem) a, (int, PluginItem) b) => a.$2.calendar!.start.compareTo(b.$2.calendar!.start));
    if (events.isEmpty) return _buildEmptyOrLoading(frame);

    final List<Widget> children = <Widget>[];
    DateTime? previousDay;
    for (final (int index, PluginItem item) in events) {
      final DateTime day = item.calendar!.start;
      if (previousDay == null || !_sameCalendarDay(previousDay, day)) {
        children.add(_PluginAgendaDayHeader(date: day));
        previousDay = day;
      }
      children.add(
        KeyedSubtree(
          key: _keyFor(frame, index),
          child: _PluginAgendaEventRow(
            item: item,
            selected: _isSelected(frame, index),
            onTap: () => _tapItem(frame, index),
            onHover: () => _hoverSelect(frame, index),
          ),
        ),
      );
    }
    return WindowsScrollView(
      controller: controller ?? _scrollController,
      draggable: controller != null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
    );
  }

  Widget _buildGallery(PluginRenderFrame frame, {ScrollController? controller}) {
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification notification) => _onScrollNotification(frame, notification),
      child: WindowsScrollView(
        controller: controller ?? _scrollController,
        draggable: controller != null,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(children: <Widget>[
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: frame.items.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: frame.galleryColumns,
                childAspectRatio: frame.galleryAspectRatio,
                mainAxisSpacing: 7,
                crossAxisSpacing: 7,
              ),
              itemBuilder: (BuildContext context, int index) => KeyedSubtree(
                key: _keyFor(frame, index),
                child: _PluginGalleryTile(
                  item: frame.items[index],
                  selected: _isSelected(frame, index),
                  marked: _selectedIds(frame).contains(frame.items[index].id),
                  showLabels: frame.galleryShowLabels,
                  fit: frame.galleryFit == 'contain' ? BoxFit.contain : BoxFit.cover,
                  onTap: () => _tapItem(frame, index),
                  onHover: () => _hoverSelect(frame, index),
                  onToggle: frame.multiSelect
                      ? () => widget.onToggleSelection(_scopeFor(frame), frame.items[index].id)
                      : null,
                  mediaActive: _activeMediaItemId == frame.items[index].id,
                  mediaPlaying: _activeMediaItemId == frame.items[index].id && _mediaPlaying,
                  mediaLoading: _activeMediaItemId == frame.items[index].id && _mediaLoading,
                  mediaProgress: _activeMediaItemId == frame.items[index].id &&
                          _mediaDuration != null &&
                          _mediaDuration! > Duration.zero
                      ? (_mediaPosition.inMilliseconds / _mediaDuration!.inMilliseconds).clamp(0.0, 1.0)
                      : 0,
                  mediaError: _activeMediaItemId == frame.items[index].id ? _mediaError : null,
                  onPlayPause: frame.items[index].media?.type == 'audio' || frame.items[index].media?.type == 'video'
                      ? () => _toggleMedia(frame.items[index])
                      : null,
                  onSeek: (double progress) => _seekMedia(progress),
                ),
              ),
            ),
            if (frame.hasMore) _loadMoreFooter(),
          ]),
        ),
      ),
    );
  }

  Future<void> _toggleMedia(PluginItem item) async {
    final PluginMediaInfo? media = item.media;
    if (media == null || (media.type != 'audio' && media.type != 'video')) return;
    if (_activeMediaItemId == item.id) {
      if (_mediaPlaying) {
        await _mediaPlayer.pause();
      } else {
        await _mediaPlayer.play();
      }
      return;
    }
    setState(() {
      _activeMediaItemId = item.id;
      _mediaPosition = Duration.zero;
      _mediaDuration = null;
      _mediaError = null;
      _mediaLoading = true;
    });
    try {
      final Uri uri = Uri.parse(media.url);
      if (uri.scheme == 'file') {
        await _mediaPlayer.setFilePath(uri.toFilePath(windows: Platform.isWindows));
      } else {
        await _mediaPlayer.setUrl(media.url);
      }
      await _mediaPlayer.play();
    } on PlayerException catch (error) {
      if (mounted) setState(() => _mediaError = error.message);
    } catch (error) {
      if (mounted) setState(() => _mediaError = error.toString());
    } finally {
      if (mounted) setState(() => _mediaLoading = false);
    }
  }

  void _seekMedia(double progress) {
    final Duration? duration = _mediaDuration;
    if (duration == null) return;
    unawaited(_mediaPlayer.seek(Duration(milliseconds: (duration.inMilliseconds * progress).round())));
  }

  Widget _buildDetail(String markdown, List<PluginMetadataEntry> metadata,
      {ScrollController? controller, required PluginEventScope scope}) {
    final bool hasMarkdown = markdown.trim().isNotEmpty;
    final String renderedMarkdown = _normalizeLocalMarkdownImageUris(markdown);
    return WindowsScrollView(
      controller: controller ?? widget.detailScrollController,
      draggable: controller != null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: !hasMarkdown && metadata.isEmpty
            ? Text('No content',
                style: TextStyle(fontSize: Design.baseFontSize + 2.5, color: Design.text.withAlpha(120)))
            // Cap the measure in the widened window — full-width prose lines
            // are unreadable at 1080px.
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  // Selectable: detail documents are the "answer" surface —
                  // users copy from them constantly.
                  child: _selectableContent(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (hasMarkdown) MarkdownBlock(data: renderedMarkdown, config: _markdownConfig()),
                        if (metadata.isNotEmpty)
                          _PluginMetadataPane(
                            entries: metadata,
                            topGap: hasMarkdown,
                            onAction: (PluginAction action) => widget.onMetadataAction(scope, '', action),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildPreviewPane(PluginItem item, {required PluginEventScope scope}) {
    final String markdown = item.previewMarkdown ?? '';
    final bool hasMarkdown = markdown.trim().isNotEmpty;
    final bool hasDiff = item.previewDiffLines.isNotEmpty;
    final String renderedMarkdown = _normalizeLocalMarkdownImageUris(markdown);
    return WindowsScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: !hasMarkdown && !hasDiff && item.previewImageUrl == null && item.previewMetadata.isEmpty
            ? Text('No preview',
                style: TextStyle(fontSize: Design.baseFontSize + 3.5, color: Design.text.withAlpha(90)))
            : _selectableContent(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (hasDiff)
                      SizedBox(
                        width: double.infinity,
                        child: _buildDiffContent(
                          item.previewDiffLines,
                          mode: item.previewDiffMode,
                          oldLabel: item.previewDiffOldLabel,
                          newLabel: item.previewDiffNewLabel,
                        ),
                      ),
                    if (hasDiff && (hasMarkdown || item.previewImageUrl != null)) const SizedBox(height: 10),
                    if (hasMarkdown || item.previewImageUrl != null)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          if (hasMarkdown)
                            Expanded(
                                child:
                                    MarkdownBlock(data: renderedMarkdown, config: _markdownConfig(maxImageWidth: 220))),
                          if (hasMarkdown && item.previewImageUrl != null) const SizedBox(width: 10),
                          if (item.previewImageUrl != null)
                            Image.network(
                              item.previewImageUrl!,
                              width: item.previewImageWidth ?? 160,
                              fit: BoxFit.contain,
                              errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) =>
                                  const SizedBox.shrink(),
                            ),
                        ],
                      ),
                    if (item.previewMetadata.isNotEmpty)
                      _PluginMetadataPane(
                        entries: item.previewMetadata,
                        topGap: hasDiff || hasMarkdown || item.previewImageUrl != null,
                        onAction: (PluginAction action) => widget.onMetadataAction(scope, item.id, action),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  /// Keeps native selection/copy available while delegating launcher shortcuts
  /// when selectable plugin content becomes the primary focus after a mouse
  /// selection.
  Widget _selectableContent(Widget child) {
    return Focus(
      onKeyEvent: (_, KeyEvent event) => widget.onMarkdownKeyEvent?.call(event) ?? KeyEventResult.ignored,
      child: SelectionArea(child: child),
    );
  }

  /// Markdown requires spaces in link destinations to be percent-encoded.
  /// Plugin authors commonly provide Windows `file://` URLs directly, where
  /// the user's profile or a plugin folder can contain spaces. Normalize only
  /// image destinations so the markdown parser preserves the full local URI.
  String _normalizeLocalMarkdownImageUris(String markdown) {
    final RegExp localImage = RegExp(
      r'(!\[[^\]\r\n]*\]\()(file://[^)\r\n]*)(\))',
      caseSensitive: false,
    );
    return markdown.replaceAllMapped(localImage, (Match match) {
      final String url = match.group(2)!;
      return '${match.group(1)}${url.replaceAll(' ', '%20')}${match.group(3)}';
    });
  }

  /// Markdown styling tied to the active theme. Every block type is retinted
  /// with [Design] colors — the package defaults render headings, list bullets,
  /// checkboxes, rules and syntax tokens with hardcoded light-mode grays/blacks
  /// (e.g. a 32px black `# H1` under a `#d7dde3` underline) that are unreadable
  /// and visually foreign against the launcher's themed backdrop.
  MarkdownConfig _markdownConfig({double maxImageWidth = double.infinity}) {
    final Color text = Design.text;
    final Color accent = Design.accent;

    // Compact heading scale sized for the launcher's density, not the package's
    // article-page defaults. Level headings share w700 and the theme text
    // color, stepping down in size/opacity; h1/h2 keep a hairline rule.
    _MdHeadingConfig heading(
      MarkdownTag tag,
      double size, {
      int alpha = 255,
      double spacing = 0,
      HeadingDivider? divider,
      EdgeInsets padding = const EdgeInsets.only(top: 10, bottom: 3),
    }) =>
        _MdHeadingConfig(
          tag: tag.name,
          style: TextStyle(
            color: text.withAlpha(alpha),
            fontSize: size,
            height: 1.3,
            fontWeight: FontWeight.w700,
            letterSpacing: spacing,
          ),
          divider: divider,
          padding: padding,
        );

    // Syntax palette derived from the accent hue so highlighted code reads as
    // part of the theme (and adapts to any accent) instead of GitHub-light
    // colors. Unlisted tokens fall through to [text] via styleNotMatched.
    final Map<String, TextStyle> codeTheme = <String, TextStyle>{
      'root': TextStyle(color: text, backgroundColor: Colors.transparent),
      'comment': TextStyle(color: text.withAlpha(105), fontStyle: FontStyle.italic),
      'quote': TextStyle(color: text.withAlpha(105), fontStyle: FontStyle.italic),
      'meta': TextStyle(color: text.withAlpha(150)),
      'keyword': TextStyle(color: accent),
      'selector-tag': TextStyle(color: accent),
      'built_in': TextStyle(color: accent),
      'tag': TextStyle(color: accent),
      'type': TextStyle(color: Design.accentHue(-40)),
      'number': TextStyle(color: Design.accentHue(-40)),
      'literal': TextStyle(color: Design.accentHue(-40)),
      'string': TextStyle(color: Design.accentHue(120, saturation: 0.85)),
      'attr': TextStyle(color: Design.accentHue(120, saturation: 0.85)),
      'title': TextStyle(color: Design.accentHue(45)),
      'section': TextStyle(color: Design.accentHue(45)),
      'function': TextStyle(color: Design.accentHue(45)),
    };

    return MarkdownConfig(
      configs: <WidgetConfig>[
        PConfig(textStyle: TextStyle(color: text, fontSize: Design.baseFontSize + 2.5, height: 1.5)),
        heading(MarkdownTag.h1, 18,
            spacing: -0.2,
            divider: HeadingDivider(color: text.withAlpha(28), space: 6, height: 1),
            padding: const EdgeInsets.only(top: 12, bottom: 5)),
        heading(MarkdownTag.h2, 15.5,
            divider: HeadingDivider(color: text.withAlpha(20), space: 5, height: 1),
            padding: const EdgeInsets.only(top: 12, bottom: 4)),
        heading(MarkdownTag.h3, 14),
        heading(MarkdownTag.h4, 13, alpha: 225),
        heading(MarkdownTag.h5, 12, alpha: 195),
        heading(MarkdownTag.h6, 11.5, alpha: 150, spacing: 0.3),
        // `---` as a launcher hairline rather than the default 2px light bar.
        HrConfig(height: 1, color: text.withAlpha(28)),
        // Tighter indent + accent bullets (the default marker inherits a
        // theme text color that renders near-black on a dark backdrop).
        const ListConfig(marginLeft: 22, marker: _mdListMarker),
        // Task lists: accent check / muted empty box instead of a black icon.
        CheckBoxConfig(
          builder: (bool checked) => Padding(
            padding: const EdgeInsets.only(right: 5, top: 1),
            child: Icon(
              checked ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
              size: 15,
              color: checked ? accent : text.withAlpha(120),
            ),
          ),
        ),
        // Inline `code`: accent text on a faint accent fill.
        CodeConfig(
          style: TextStyle(
            color: accent,
            backgroundColor: accent.withAlpha(28),
            fontFamily: 'Consolas',
            fontSize: Design.baseFontSize + 3.5,
          ),
        ),
        // Fenced code blocks: theme-tinted syntax over a subtle panel, with a
        // hover copy button in the corner.
        PreConfig(
          textStyle: TextStyle(fontFamily: 'Consolas', fontSize: Design.baseFontSize + 3.5, height: 1.45),
          styleNotMatched: TextStyle(color: text),
          theme: codeTheme,
          decoration: BoxDecoration(
            color: text.withAlpha(14),
            border: Border.all(color: accent.withAlpha(30)),
            borderRadius: BorderRadius.circular(6),
          ),
          padding: const EdgeInsets.all(10),
          wrapper: (Widget child, String code, String language) => _CodeBlockWrapper(code: code, child: child),
        ),
        BlockquoteConfig(
          sideColor: accent.withAlpha(150),
          sideWith: 3,
          textColor: text.withAlpha(205),
          padding: const EdgeInsets.fromLTRB(12, 2, 0, 2),
        ),
        // Tables: the package default draws full-opacity text-colored grid
        // lines — soften to the launcher's hairline style with a tinted header.
        TableConfig(
          border: TableBorder.all(color: text.withAlpha(40)),
          headerRowDecoration: BoxDecoration(color: accent.withAlpha(18)),
          headerStyle: TextStyle(fontSize: Design.baseFontSize + 3.5, fontWeight: FontWeight.w700, color: accent),
          bodyStyle: TextStyle(fontSize: Design.baseFontSize + 3.5, color: text),
          headPadding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
          bodyPadding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
        ),
        LinkConfig(
          style: TextStyle(color: accent, decoration: TextDecoration.underline),
          onTap: (String url) {
            final String target = url.trim();
            if (target.isNotEmpty) WinUtils.open(target);
          },
        ),
        // The package default only loads http rasters / Flutter assets;
        // plugins reference local `file://` images (including generated SVGs).
        ImgConfig(builder: (String url, Map<String, String> attributes) => _markdownImage(url, maxImageWidth)),
      ],
    );
  }

  /// Renders a markdown image from a `file://` path or http(s) URL, with SVG
  /// support via flutter_svg. Rasters render at intrinsic size, capped at the
  /// pane width and [maxImageWidth]; SVGs scale to fill that width. Clicking
  /// or right-clicking opens an image action menu.
  Widget _markdownImage(String url, double maxImageWidth) {
    final String value = url.trim();
    final Widget broken = Icon(Icons.broken_image_rounded, size: 16, color: Design.text.withAlpha(90));
    final bool isSvg = Uri.tryParse(value)?.path.toLowerCase().endsWith('.svg') ?? false;
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
      double? width;
      if (constraints.maxWidth.isFinite) {
        width = constraints.maxWidth > maxImageWidth ? maxImageWidth : constraints.maxWidth;
      } else if (maxImageWidth.isFinite) {
        width = maxImageWidth;
      }
      Widget? image;
      if (value.startsWith('http://') || value.startsWith('https://')) {
        image = isSvg
            ? SvgPicture.network(value, width: width, errorBuilder: (_, __, ___) => broken)
            : Image.network(value, errorBuilder: (_, __, ___) => broken);
      } else if (value.startsWith('file://')) {
        final File file = File(Uri.parse(value).toFilePath(windows: true));
        if (!file.existsSync()) return broken;
        image = isSvg
            ? SvgPicture.file(file, width: width, errorBuilder: (_, __, ___) => broken)
            : Image.file(file, errorBuilder: (_, __, ___) => broken);
      }
      if (image == null) return broken;
      // Rasters scale down to fit the pane but never upscale past their
      // intrinsic size — a 96px avatar must not stretch across the detail pane.
      // SVGs keep filling [width]: plugin-generated vector charts rely on it.
      if (!isSvg && width != null) {
        image = ConstrainedBox(constraints: BoxConstraints(maxWidth: width), child: image);
      }
      return MouseRegion(
        cursor: SystemMouseCursors.zoomIn,
        child: GestureDetector(
          onTapDown: (TapDownDetails details) => _openImageLightbox(context, url, isSvg: isSvg),
          onSecondaryTapDown: (TapDownDetails details) => _showImageMenu(
            context,
            details.globalPosition,
            value,
            isSvg: isSvg,
          ),
          child: image,
        ),
      );
    });
  }

  /// Shows the image's primary actions at the pointer, for both normal and
  /// secondary clicks. Copying produces a Windows-native bitmap for raster
  /// images; SVGs retain their useful source URL on the clipboard.
  Future<void> _showImageMenu(BuildContext context, Offset globalPosition, String url, {required bool isSvg}) async {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final String? action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: const <PopupMenuEntry<String>>[
        PopupMenuItem<String>(value: 'open', child: Text('Open image')),
        PopupMenuItem<String>(value: 'copy', child: Text('Copy image')),
      ],
    );
    if (!mounted || action == null) return;
    if (action == 'open') {
      _openImageLightbox(context, url, isSvg: isSvg);
    } else if (action == 'copy') {
      await _copyMarkdownImage(url, isSvg: isSvg);
    }
  }

  Future<void> _copyMarkdownImage(String url, {required bool isSvg}) async {
    if (isSvg) {
      await ClipboardService.instance.writeText(url);
      return;
    }
    try {
      final List<int> bytes;
      if (url.startsWith('file://')) {
        bytes = await File(Uri.parse(url).toFilePath(windows: true)).readAsBytes();
      } else {
        final HttpClientRequest request = await HttpClient().getUrl(Uri.parse(url));
        final HttpClientResponse response = await request.close();
        if (response.statusCode != HttpStatus.ok) throw HttpException('Unable to load image', uri: Uri.parse(url));
        bytes = await response.fold<List<int>>(<int>[], (List<int> data, List<int> chunk) => data..addAll(chunk));
      }
      final image.Image? decoded = image.decodeImage(Uint8List.fromList(bytes));
      if (decoded == null) throw const FormatException('Unsupported image format');
      // Keep the adapter responsible for any platform-specific image format conversion.
      await ClipboardService.instance.writeContent(
        PlatformClipboardContent(imageBytes: Uint8List.fromList(bytes)),
      );
    } catch (_) {
      // Preserve a useful result when an image cannot be decoded or fetched.
      await ClipboardService.instance.writeText(url);
    }
  }

  /// Shows [url] full-size over a dimmed backdrop: pinch/scroll to zoom, and
  /// Escape / Enter / click anywhere to dismiss.
  void _openImageLightbox(BuildContext context, String url, {required bool isSvg}) {
    Widget full;
    if (url.startsWith('file://')) {
      final File file = File(Uri.parse(url).toFilePath(windows: true));
      full = isSvg ? SvgPicture.file(file) : Image.file(file, filterQuality: FilterQuality.medium);
    } else {
      full = isSvg ? SvgPicture.network(url) : Image.network(url, filterQuality: FilterQuality.medium);
    }
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withAlpha(190),
      builder: (BuildContext dialogContext) => _ImageLightbox(child: full),
    );
  }
}

/// Fullscreen zoomable image overlay used by [_PluginViewState._openImageLightbox].
class _ImageLightbox extends StatefulWidget {
  const _ImageLightbox({required this.child});

  final Widget child;

  @override
  State<_ImageLightbox> createState() => _ImageLightboxState();
}

class _ImageLightboxState extends State<_ImageLightbox> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKey,
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: InteractiveViewer(
            maxScale: 8,
            child: Center(child: widget.child),
          ),
        ),
      ),
    );
  }
}

/// Hover shell around a fenced code block adding a copy-to-clipboard button in
/// the top-right corner (flips to a check for a moment after copying).
class _CodeBlockWrapper extends StatefulWidget {
  const _CodeBlockWrapper({required this.code, required this.child});

  final String code;
  final Widget child;

  @override
  State<_CodeBlockWrapper> createState() => _CodeBlockWrapperState();
}

class _CodeBlockWrapperState extends State<_CodeBlockWrapper> {
  bool _hovered = false;
  bool _copied = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  void _copy() {
    unawaited(ClipboardService.instance.writeText(widget.code));
    setState(() => _copied = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(milliseconds: 1400), () {
      _resetTimer = null;
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Stack(
        children: <Widget>[
          widget.child,
          Positioned(
            top: 6,
            right: 6,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 100),
              opacity: _hovered || _copied ? 1 : 0,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: _copy,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Design.background.withAlpha(220),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: Design.accent.withAlpha(_copied ? 150 : 50)),
                    ),
                    child: Icon(
                      _copied ? Icons.check_rounded : Icons.copy_rounded,
                      size: 13,
                      color: _copied ? Design.accent : Design.text.withAlpha(170),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The empty state's call-to-action ("No config found → Set up").
class _EmptyActionButton extends StatelessWidget {
  const _EmptyActionButton({required this.action, required this.onTap});

  final PluginAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: Design.accent.withAlpha(30),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Design.accent.withAlpha(120)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (action.icon != null) ...<Widget>[
                Icon(PluginIcons.resolve(action.icon), size: 13, color: Design.accent),
                const SizedBox(width: 6),
              ],
              Text(
                action.title,
                style:
                    TextStyle(fontSize: Design.baseFontSize + 3.5, fontWeight: FontWeight.w700, color: Design.accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A [HeadingConfig] with a caller-supplied tag, style, divider and padding —
/// the package's built-in `H1Config`…`H6Config` bake in article-sized styles
/// and a fixed light-gray underline, none of which suit the launcher.
class _MdHeadingConfig extends HeadingConfig {
  const _MdHeadingConfig({
    required this.tag,
    required this.style,
    this.divider,
    this.padding = const EdgeInsets.only(top: 10, bottom: 3),
  });

  @override
  final String tag;
  @override
  final TextStyle style;
  @override
  final HeadingDivider? divider;
  @override
  final EdgeInsets padding;
}

/// Accent-tinted list markers: a filled dot / hollow ring / small square by
/// nesting depth for bullets, and dimmed accent numerals for ordered lists.
/// Vertical offsets are tuned to the 13px/1.5 body line so markers sit on the
/// first text line.
Widget _mdListMarker(bool isOrdered, int depth, int index) {
  if (isOrdered) {
    return Container(
      alignment: Alignment.topRight,
      padding: const EdgeInsets.only(right: 6, top: 1),
      child: Text(
        '${index + 1}.',
        style: TextStyle(
          fontSize: Design.baseFontSize + 3.5,
          height: 1.5,
          fontWeight: FontWeight.w600,
          color: Design.accent.withAlpha(210),
        ),
      ),
    );
  }
  final Color color = Design.accent.withAlpha(210);
  final BoxDecoration decoration = depth == 0
      ? BoxDecoration(color: color, shape: BoxShape.circle)
      : depth == 1
          ? BoxDecoration(border: Border.all(color: color, width: 1.2), shape: BoxShape.circle)
          : BoxDecoration(color: color.withAlpha(150), borderRadius: BorderRadius.circular(1));
  return Padding(
    padding: const EdgeInsets.only(right: 8, top: 7),
    child: Align(
      alignment: Alignment.topRight,
      child: Container(width: 5, height: 5, decoration: decoration),
    ),
  );
}

/// Resolves a plugin icon string to a widget: a `#RRGGBB` color swatch, a
/// Material icon name, an inline `data:image/...` URI, a local `file://` image,
/// or a remote `https://` raster or SVG image (images fall back to the icon on
/// error).
class _PluginIcon extends StatelessWidget {
  const _PluginIcon({required this.name, required this.accent, this.size = 16});
  final String? name;
  final Color accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    final String? value = name?.trim();
    final Color? swatch = parsePluginColor(value);
    if (swatch != null) {
      return Container(
        width: size + 4,
        height: size + 4,
        decoration: BoxDecoration(
          color: swatch,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: Design.text.withAlpha(40)),
        ),
      );
    }
    if (value != null && value.startsWith('data:image/')) {
      final Widget fallback = Icon(PluginIcons.fallback, size: size, color: accent);
      // Inline icons are decoded synchronously during build, so reject
      // unexpectedly large plugin payloads before allocating their bytes.
      if (value.length > 2 * 1024 * 1024) return fallback;
      try {
        final UriData data = UriData.parse(value);
        final Uint8List bytes = data.contentAsBytes();
        if (bytes.isEmpty) return fallback;
        final bool isSvg = data.mimeType.toLowerCase() == 'image/svg+xml';
        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: isSvg
              ? SvgPicture.memory(
                  bytes,
                  width: size + 6,
                  height: size + 6,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => fallback,
                )
              : Image.memory(
                  bytes,
                  width: size + 6,
                  height: size + 6,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => fallback,
                ),
        );
      } catch (_) {
        return fallback;
      }
    }
    if (value != null && (value.startsWith('http://') || value.startsWith('https://'))) {
      final Widget fallback = Icon(PluginIcons.fallback, size: size, color: accent);
      final bool isSvg = Uri.tryParse(value)?.path.toLowerCase().endsWith('.svg') ?? false;
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: isSvg
            ? SvgPicture.network(
                value,
                width: size + 6,
                height: size + 6,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => fallback,
              )
            : Image.network(
                value,
                width: size + 6,
                height: size + 6,
                fit: BoxFit.cover,
                // Some favicon endpoints return SVG without a `.svg` path.
                // If raster decoding fails, let flutter_svg inspect the same
                // URL before falling back to the generic plugin icon.
                errorBuilder: (_, __, ___) => SvgPicture.network(
                  value,
                  width: size + 6,
                  height: size + 6,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => fallback,
                ),
              ),
      );
    }
    if (value != null && value.startsWith('file://')) {
      final String path = Uri.parse(value).toFilePath(windows: true);
      final File file = File(path);
      if (file.existsSync()) {
        final Widget fallback = Icon(PluginIcons.fallback, size: size, color: accent);
        final bool isSvg = file.path.toLowerCase().endsWith('.svg');
        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: isSvg
              ? SvgPicture.file(
                  file,
                  width: size + 6,
                  height: size + 6,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => fallback,
                )
              : Image.file(
                  file,
                  width: size + 6,
                  height: size + 6,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => fallback,
                ),
        );
      }
    }
    return Icon(PluginIcons.resolve(value), size: size, color: accent);
  }
}

class _PluginChatJumpButton extends StatelessWidget {
  const _PluginChatJumpButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Design.background.withAlpha(235),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Design.accent.withAlpha(110)),
          ),
          child: Icon(Icons.keyboard_double_arrow_down_rounded, size: 17, color: Design.accent),
        ),
      ),
    );
  }
}

/// One message in a plugin `chat` view. Consecutive messages from the same
/// author collapse into a Discord-style group, while item actions appear only
/// when the pointer is over the row.
class _PluginChatMessage extends StatefulWidget {
  const _PluginChatMessage({
    required this.item,
    required this.grouped,
    required this.onContentSizeChanged,
    required this.onAction,
  });

  final PluginItem item;
  final bool grouped;
  final VoidCallback onContentSizeChanged;
  final ValueChanged<PluginAction> onAction;

  @override
  State<_PluginChatMessage> createState() => _PluginChatMessageState();
}

class _PluginChatMessageState extends State<_PluginChatMessage> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final PluginItem item = widget.item;
    final String? avatar = item.icon?.trim();
    final Widget avatarWidget = avatar != null && (avatar.startsWith('http://') || avatar.startsWith('https://'))
        ? ClipOval(
            child: Image.network(
              avatar,
              width: 32,
              height: 32,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _chatAvatarFallback(),
            ),
          )
        : _chatAvatarFallback();
    final List<PluginAccessory> headerAccessories =
        item.accessories.where((PluginAccessory accessory) => accessory.icon != 'heart').toList();
    final List<PluginAccessory> reactions =
        item.accessories.where((PluginAccessory accessory) => accessory.icon == 'heart').toList();
    final bool hasActions = item.actions.isNotEmpty;

    return MouseRegion(
      onEnter: (_) {
        if (hasActions && mounted) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (_hovered && mounted) setState(() => _hovered = false);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        padding: EdgeInsets.fromLTRB(8, widget.grouped ? 1 : 9, 8, reactions.isEmpty ? 3 : 5),
        color: _hovered ? Design.text.withAlpha(8) : Colors.transparent,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (widget.grouped)
              const SizedBox(width: 42)
            else ...<Widget>[
              SizedBox(width: 32, height: 32, child: avatarWidget),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Padding(
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (!widget.grouped)
                          Row(
                            children: <Widget>[
                              Flexible(
                                child: Text(
                                  item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: Design.baseFontSize + 1,
                                    fontWeight: FontWeight.w700,
                                    color: Design.text.withAlpha(230),
                                  ),
                                ),
                              ),
                              for (final PluginAccessory accessory in headerAccessories) ...<Widget>[
                                const SizedBox(width: 7),
                                Text(
                                  accessory.text,
                                  style: TextStyle(
                                    fontSize: accessory.icon == 'clock' ? 10 : Design.baseFontSize,
                                    color: accessory.color ?? Design.text.withAlpha(105),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        if (item.reply != null) _DiscordReplyPreview(reply: item.reply!),
                        if (item.subtitle.isNotEmpty) ...<Widget>[
                          if (!widget.grouped) const SizedBox(height: 2),
                          _DiscordChatBody(text: item.subtitle, onImageLoaded: widget.onContentSizeChanged),
                        ],
                        for (final String imageUrl in item.chatImageUrls) ...<Widget>[
                          const SizedBox(height: 7),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 460, maxHeight: 320),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Design.text.withAlpha(6),
                                  border: Border.all(color: Design.text.withAlpha(16)),
                                ),
                                child: Image.network(
                                  imageUrl,
                                  width: 460,
                                  fit: BoxFit.contain,
                                  alignment: Alignment.centerLeft,
                                  frameBuilder:
                                      (BuildContext context, Widget child, int? frame, bool wasSynchronouslyLoaded) {
                                    if (frame != null || wasSynchronouslyLoaded) {
                                      WidgetsBinding.instance.addPostFrameCallback((_) {
                                        if (mounted) widget.onContentSizeChanged();
                                      });
                                    }
                                    return child;
                                  },
                                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                                ),
                              ),
                            ),
                          ),
                        ],
                        if (reactions.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: <Widget>[
                                for (final PluginAccessory reaction in reactions)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: (reaction.color ?? Design.accent).withAlpha(22),
                                      borderRadius: BorderRadius.circular(5),
                                      border: Border.all(color: (reaction.color ?? Design.accent).withAlpha(65)),
                                    ),
                                    child: Text(
                                      reaction.text,
                                      style: TextStyle(
                                          fontSize: Design.baseFontSize + 1,
                                          color: reaction.color ?? Design.text.withAlpha(175)),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_hovered && hasActions)
                    Positioned(
                      top: -7,
                      right: 0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Design.background.withAlpha(245),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Design.text.withAlpha(34)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            for (final PluginAction action in item.actions)
                              IconButton(
                                tooltip: action.title,
                                visualDensity: VisualDensity.compact,
                                constraints: const BoxConstraints.tightFor(width: 27, height: 27),
                                padding: EdgeInsets.zero,
                                icon: Icon(
                                  PluginIcons.resolve(action.icon),
                                  size: 14,
                                  color: action.destructive ? const Color(0xFFE5534B) : Design.text.withAlpha(175),
                                ),
                                onPressed: () => widget.onAction(action),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chatAvatarFallback() {
    final String name = widget.item.title.trim();
    final String initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return Container(
      decoration: BoxDecoration(color: Design.accent.withAlpha(42), shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
            fontSize: Design.baseFontSize + 3.5, fontWeight: FontWeight.w700, color: Design.accent.withAlpha(225)),
      ),
    );
  }
}

class _DiscordReplyPreview extends StatelessWidget {
  const _DiscordReplyPreview({required this.reply});

  final PluginReplyPreview reply;

  @override
  Widget build(BuildContext context) {
    final String? avatar = reply.icon?.trim();
    final bool hasAvatar = avatar != null && (avatar.startsWith('http://') || avatar.startsWith('https://'));
    return Padding(
      padding: const EdgeInsets.only(top: 3, bottom: 4),
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: Design.accent.withAlpha(125), width: 2)),
        ),
        padding: const EdgeInsets.only(left: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (hasAvatar) ...<Widget>[
              ClipOval(
                child: Image.network(
                  avatar,
                  width: 15,
                  height: 15,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
              const SizedBox(width: 5),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    reply.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: Design.baseFontSize + 1,
                      fontWeight: FontWeight.w700,
                      color: Design.accent.withAlpha(205),
                    ),
                  ),
                  _DiscordChatBody(
                    text: reply.text,
                    maxLines: 2,
                    style:
                        TextStyle(fontSize: Design.baseFontSize + 1, height: 1.25, color: Design.text.withAlpha(135)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Discord represents custom emoji as `<:name:id>` / `<a:name:id>`. Render
/// those tokens and the common inline emphasis forms while leaving normal
/// Unicode emoji alone.
class _DiscordChatBody extends StatelessWidget {
  const _DiscordChatBody({required this.text, this.onImageLoaded, this.maxLines, this.style});

  static final RegExp _inlineToken = RegExp(
    r'<(a?):[A-Za-z0-9_]+:(\d+)>'
    r'|(\*\*[^*\n]+\*\*)|(__[^_\n]+__)|(`[^`\n]+`)|(\*[^*\n]+\*)|(_[^_\n]+_)',
  );

  final String text;
  final VoidCallback? onImageLoaded;
  final int? maxLines;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final TextStyle bodyStyle =
        style ?? TextStyle(fontSize: Design.baseFontSize + 3.5, height: 1.4, color: Design.text.withAlpha(205));
    final List<InlineSpan> spans = <InlineSpan>[];
    int offset = 0;
    for (final RegExpMatch match in _inlineToken.allMatches(text)) {
      if (match.start > offset) spans.add(TextSpan(text: text.substring(offset, match.start)));
      if (match.group(1) != null) {
        final bool animated = match.group(1) == 'a';
        final String id = match.group(2)!;
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Image.network(
              'https://cdn.discordapp.com/emojis/$id.${animated ? 'gif' : 'png'}?size=48&quality=lossless',
              width: 20,
              height: 20,
              frameBuilder: (BuildContext context, Widget child, int? frame, bool wasSynchronouslyLoaded) {
                if ((frame != null || wasSynchronouslyLoaded) && onImageLoaded != null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) => onImageLoaded!());
                }
                return child;
              },
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        );
      } else {
        final String token = match.group(0)!;
        final bool bold = token.startsWith('**') || token.startsWith('__');
        final bool code = token.startsWith('`');
        final bool italic = !bold && !code;
        final int trim = bold || code ? 2 : 1;
        spans.add(
          TextSpan(
            text: token.substring(trim, token.length - trim),
            style: TextStyle(
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
              fontStyle: italic ? FontStyle.italic : FontStyle.normal,
              fontFamily: code ? 'Consolas' : null,
              color: code ? Design.text.withAlpha(225) : null,
              backgroundColor: code ? Design.text.withAlpha(18) : null,
            ),
          ),
        );
      }
      offset = match.end;
    }
    if (offset < text.length) spans.add(TextSpan(text: text.substring(offset)));
    return Text.rich(
      TextSpan(style: bodyStyle, children: spans.isEmpty ? <InlineSpan>[TextSpan(text: text)] : spans),
      maxLines: maxLines,
      overflow: maxLines == null ? TextOverflow.clip : TextOverflow.ellipsis,
    );
  }
}

const List<String> _pluginMonthNames = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const List<String> _pluginWeekdayNames = <String>[
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String _pluginClock(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

class _PluginCalendarHeader extends StatelessWidget {
  const _PluginCalendarHeader({
    required this.date,
    required this.mode,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
    required this.onModeChanged,
  });

  final DateTime date;
  final String mode;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final ValueChanged<String> onModeChanged;

  @override
  Widget build(BuildContext context) {
    final String title = mode == 'month'
        ? '${_pluginMonthNames[date.month - 1]} ${date.year}'
        : '${_pluginMonthNames[date.month - 1]} ${date.day}, ${date.year}';
    return Container(
      height: 39,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Design.text.withAlpha(18)))),
      child: Row(children: <Widget>[
        _PluginCalendarIconButton(icon: Icons.chevron_left_rounded, tooltip: 'Previous', onTap: onPrevious),
        _PluginCalendarIconButton(icon: Icons.chevron_right_rounded, tooltip: 'Next', onTap: onNext),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: Design.baseFontSize + 3.5, fontWeight: FontWeight.w700, color: Design.text.withAlpha(220)),
          ),
        ),
        _PluginCalendarTextButton(label: 'Today', selected: false, onTap: onToday),
        const SizedBox(width: 5),
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: Design.text.withAlpha(8),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Design.text.withAlpha(18)),
          ),
          child: Row(children: <Widget>[
            _PluginCalendarTextButton(
              label: 'Month',
              selected: mode == 'month',
              onTap: () => onModeChanged('month'),
            ),
            _PluginCalendarTextButton(
              label: 'Agenda',
              selected: mode == 'agenda',
              onTap: () => onModeChanged('agenda'),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _PluginCalendarIconButton extends StatelessWidget {
  const _PluginCalendarIconButton({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 27, height: 27),
        padding: EdgeInsets.zero,
        onPressed: onTap,
        icon: Icon(icon, size: 16, color: Design.text.withAlpha(150)),
      );
}

class _PluginCalendarTextButton extends StatelessWidget {
  const _PluginCalendarTextButton({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: selected ? Design.accent.withAlpha(32) : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: Design.baseFontSize,
                fontWeight: FontWeight.w700,
                color: selected ? Design.accent : Design.text.withAlpha(125),
              ),
            ),
          ),
        ),
      );
}

class _PluginCalendarDayCell extends StatelessWidget {
  const _PluginCalendarDayCell({
    required this.day,
    required this.inMonth,
    required this.today,
    required this.eventCount,
    required this.visibleCount,
    required this.eventBuilder,
  });

  final DateTime day;
  final bool inMonth;
  final bool today;
  final int eventCount;
  final int visibleCount;
  final Widget Function(int index) eventBuilder;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(4, 3, 4, 2),
        decoration: BoxDecoration(
          color: inMonth ? Design.text.withAlpha(3) : Design.text.withAlpha(1),
          border: Border.all(color: Design.text.withAlpha(inMonth ? 15 : 8)),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              width: 19,
              height: 19,
              alignment: Alignment.center,
              decoration: today ? BoxDecoration(color: Design.accent, shape: BoxShape.circle) : null,
              child: Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: Design.baseFontSize,
                  fontWeight: today ? FontWeight.w800 : FontWeight.w600,
                  color: today ? Colors.white : Design.text.withAlpha(inMonth ? 155 : 55),
                ),
              ),
            ),
          ),
          for (int index = 0; index < eventCount && index < visibleCount; index++) eventBuilder(index),
          if (eventCount > visibleCount)
            Padding(
              padding: const EdgeInsets.only(left: 3, top: 1),
              child: Text(
                '+${eventCount - visibleCount} more',
                maxLines: 1,
                style: TextStyle(
                    fontSize: Design.baseFontSize - 0.5, fontWeight: FontWeight.w600, color: Design.text.withAlpha(85)),
              ),
            ),
        ]),
      );
}

class _PluginCalendarEventChip extends StatelessWidget {
  const _PluginCalendarEventChip({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.onHover,
  });

  final PluginItem item;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final Color color = item.calendar?.color ?? Design.accent;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onHover: (PointerHoverEvent event) {
        if (event.delta != Offset.zero) onHover();
      },
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 16,
          margin: const EdgeInsets.only(top: 2),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: color.withAlpha(selected ? 48 : 23),
            borderRadius: BorderRadius.circular(3),
            border: Border(left: BorderSide(color: color, width: 2)),
          ),
          child: Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: Design.baseFontSize - 0.5, fontWeight: FontWeight.w600, color: Design.text.withAlpha(190)),
          ),
        ),
      ),
    );
  }
}

class _PluginAgendaDayHeader extends StatelessWidget {
  const _PluginAgendaDayHeader({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(5, 9, 5, 4),
        child: Text(
          '${_pluginWeekdayNames[date.weekday - 1]}, ${_pluginMonthNames[date.month - 1]} ${date.day}',
          style: TextStyle(
            fontSize: Design.baseFontSize,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
            color: Design.text.withAlpha(120),
          ),
        ),
      );
}

class _PluginAgendaEventRow extends StatelessWidget {
  const _PluginAgendaEventRow({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.onHover,
  });

  final PluginItem item;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final PluginCalendarItem calendar = item.calendar!;
    final Color color = calendar.color ?? Design.accent;
    final String time = calendar.allDay
        ? 'ALL DAY'
        : calendar.end == null
            ? _pluginClock(calendar.start)
            : '${_pluginClock(calendar.start)}–${_pluginClock(calendar.end!)}';
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onHover: (PointerHoverEvent event) {
        if (event.delta != Offset.zero) onHover();
      },
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 3),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? Design.accent.withAlpha(24) : Design.text.withAlpha(5),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: selected ? Design.accent.withAlpha(70) : Design.text.withAlpha(14)),
          ),
          child: Row(children: <Widget>[
            Container(
                width: 3, height: 31, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            SizedBox(
              width: 78,
              child: Text(
                time,
                style: TextStyle(
                    fontSize: Design.baseFontSize, fontWeight: FontWeight.w700, color: Design.text.withAlpha(100)),
              ),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: Design.baseFontSize + 1.5,
                      fontWeight: FontWeight.w700,
                      color: Design.text.withAlpha(210)),
                ),
                if (item.subtitle.isNotEmpty || calendar.location.isNotEmpty)
                  Text(
                    <String>[item.subtitle, calendar.location].where((String value) => value.isNotEmpty).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(105)),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _PluginToolbarMenu extends StatelessWidget {
  const _PluginToolbarMenu({required this.control, required this.onSelected});

  final PluginToolbarControl control;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final PluginToolbarOption selected = control.options.firstWhere(
      (PluginToolbarOption option) => option.value == control.value,
      orElse: () => control.options.first,
    );
    final int activeCount = control.multiple ? control.values.length : (control.value == null ? 0 : 1);
    return PopupMenuButton<String>(
      tooltip: control.label.isEmpty ? control.type : control.label,
      onSelected: onSelected,
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        for (final PluginToolbarOption option in control.options)
          CheckedPopupMenuItem<String>(
            value: option.value,
            checked: control.multiple ? control.values.contains(option.value) : option.value == control.value,
            child: Row(children: <Widget>[
              if (option.icon != null) ...<Widget>[
                Icon(PluginIcons.resolve(option.icon), size: 14),
                const SizedBox(width: 7),
              ],
              Text(option.label),
            ]),
          ),
      ],
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Design.text.withAlpha(8),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: Design.text.withAlpha(24)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Icon(
            switch (control.type) {
              'scope' => Icons.adjust_rounded,
              'sort' => Icons.sort_rounded,
              _ => Icons.filter_alt_outlined,
            },
            size: 13,
            color: activeCount > 0 ? Design.accent : Design.text.withAlpha(120),
          ),
          const SizedBox(width: 5),
          Text(
            control.multiple && activeCount > 0
                ? '${control.label.isEmpty ? 'Filter' : control.label} ($activeCount)'
                : selected.label,
            style: TextStyle(
                fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.w600, color: Design.text.withAlpha(185)),
          ),
          const SizedBox(width: 4),
          Icon(Icons.expand_more_rounded, size: 13, color: Design.text.withAlpha(90)),
        ]),
      ),
    );
  }
}

class _PluginViewToggle extends StatelessWidget {
  const _PluginViewToggle({required this.control, required this.onSelected});

  final PluginToolbarControl control;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => Container(
        height: 28,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: Design.text.withAlpha(9),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Design.text.withAlpha(22)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          for (final PluginToolbarOption option in control.options)
            Tooltip(
              message: option.label,
              child: InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () => onSelected(option.value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  width: 25,
                  height: 23,
                  decoration: BoxDecoration(
                    color: option.value == control.value ? Design.accent.withAlpha(42) : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(
                    PluginIcons.resolve(option.icon ?? option.value),
                    size: 14,
                    color: option.value == control.value ? Design.accent : Design.text.withAlpha(110),
                  ),
                ),
              ),
            ),
        ]),
      );
}

class _PluginBannerView extends StatelessWidget {
  const _PluginBannerView({required this.banner, required this.onAction, this.onDismiss});

  final PluginBanner banner;
  final ValueChanged<PluginAction> onAction;
  final VoidCallback? onDismiss;

  Color get _color => switch (banner.style) {
        'success' => const Color(0xFF4FB477),
        'warning' => const Color(0xFFD49A3A),
        'error' => const Color(0xFFE5534B),
        _ => Design.accent,
      };

  IconData get _icon => switch (banner.style) {
        'success' => Icons.check_circle_outline_rounded,
        'warning' => Icons.warning_amber_rounded,
        'error' => Icons.error_outline_rounded,
        _ => Icons.info_outline_rounded,
      };

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(8, 7, 8, 0),
        padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
        decoration: BoxDecoration(
          color: _color.withAlpha(18),
          borderRadius: BorderRadius.circular(7),
          border: Border(
              left: BorderSide(color: _color, width: 3),
              top: BorderSide(color: _color.withAlpha(45)),
              right: BorderSide(color: _color.withAlpha(45)),
              bottom: BorderSide(color: _color.withAlpha(45))),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Icon(banner.icon == null ? _icon : PluginIcons.resolve(banner.icon), size: 16, color: _color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              if (banner.title.isNotEmpty)
                Text(banner.title,
                    style: TextStyle(
                        fontSize: Design.baseFontSize + 1.5,
                        fontWeight: FontWeight.w700,
                        color: Design.text.withAlpha(220))),
              if (banner.message.isNotEmpty)
                Text(banner.message,
                    style:
                        TextStyle(fontSize: Design.baseFontSize + 1, height: 1.3, color: Design.text.withAlpha(145))),
              if (banner.actions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Wrap(
                    spacing: 6,
                    children: <Widget>[
                      for (final PluginAction action in banner.actions)
                        TextButton(
                          style: TextButton.styleFrom(
                            minimumSize: const Size(0, 26),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            foregroundColor: action.destructive ? const Color(0xFFE5534B) : _color,
                          ),
                          onPressed: () => onAction(action),
                          child: Text(action.title,
                              style: TextStyle(fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.w700)),
                        ),
                    ],
                  ),
                ),
            ]),
          ),
          if (onDismiss != null)
            IconButton(
              tooltip: 'Dismiss',
              constraints: const BoxConstraints.tightFor(width: 26, height: 26),
              padding: EdgeInsets.zero,
              onPressed: onDismiss,
              icon: Icon(Icons.close_rounded, size: 14, color: Design.text.withAlpha(100)),
            ),
        ]),
      );
}

class _PluginSkeleton extends StatefulWidget {
  const _PluginSkeleton({required this.view, required this.count});

  final PluginViewType view;
  final int count;

  @override
  State<_PluginSkeleton> createState() => _PluginSkeletonState();
}

class _PluginSkeletonState extends State<_PluginSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _block({double? width, required double height, double radius = 4}) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(color: Design.text.withAlpha(18), borderRadius: BorderRadius.circular(radius)),
      );

  Widget _row(int index) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        child: Row(children: <Widget>[
          _block(width: 30, height: 30, radius: 7),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              FractionallySizedBox(widthFactor: index.isEven ? 0.54 : 0.7, child: _block(height: 9)),
              const SizedBox(height: 7),
              FractionallySizedBox(widthFactor: index.isEven ? 0.78 : 0.46, child: _block(height: 7)),
            ]),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) => Opacity(
          opacity: 0.42 + _controller.value * 0.34,
          child: child,
        ),
        child: widget.view == PluginViewType.grid || widget.view == PluginViewType.gallery
            ? GridView.count(
                padding: const EdgeInsets.all(10),
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children: <Widget>[
                  for (int index = 0; index < widget.count; index++) _block(height: 80, radius: 7),
                ],
              )
            : ListView(children: <Widget>[
                for (int index = 0; index < widget.count; index++) _row(index),
              ]),
      );
}

Widget _pluginGalleryVisual(PluginItem item, BoxFit fit) {
  final PluginMediaInfo? media = item.media;
  final Widget fallback = Container(
    color: Design.text.withAlpha(7),
    alignment: Alignment.center,
    child: _PluginIcon(name: item.icon ?? media?.type, accent: Design.accent, size: 28),
  );
  if (media == null || (media.type != 'image' && media.thumbnail == null)) return fallback;
  final String source = media.displaySource;
  final bool isSvg =
      source.startsWith('data:image/svg+xml') || (Uri.tryParse(source)?.path.toLowerCase().endsWith('.svg') ?? false);
  if (source.startsWith('data:image/')) {
    if (source.length > 2 * 1024 * 1024) return fallback;
    try {
      final Uint8List bytes = UriData.parse(source).contentAsBytes();
      return isSvg
          ? SvgPicture.memory(bytes, fit: fit, errorBuilder: (_, __, ___) => fallback)
          : Image.memory(bytes, fit: fit, errorBuilder: (_, __, ___) => fallback);
    } catch (_) {
      return fallback;
    }
  }
  if (source.startsWith('file://')) {
    try {
      final File file = File(Uri.parse(source).toFilePath(windows: true));
      if (!file.existsSync()) return fallback;
      return isSvg
          ? SvgPicture.file(file, fit: fit, errorBuilder: (_, __, ___) => fallback)
          : Image.file(file, fit: fit, filterQuality: FilterQuality.medium, errorBuilder: (_, __, ___) => fallback);
    } catch (_) {
      return fallback;
    }
  }
  return isSvg
      ? SvgPicture.network(source, fit: fit, errorBuilder: (_, __, ___) => fallback)
      : Image.network(source, fit: fit, filterQuality: FilterQuality.medium, errorBuilder: (_, __, ___) => fallback);
}

class _PluginGalleryTile extends StatelessWidget {
  const _PluginGalleryTile({
    required this.item,
    required this.selected,
    required this.marked,
    required this.showLabels,
    required this.fit,
    required this.onTap,
    required this.onHover,
    required this.mediaActive,
    required this.mediaPlaying,
    required this.mediaLoading,
    required this.mediaProgress,
    required this.mediaError,
    required this.onSeek,
    this.onToggle,
    this.onPlayPause,
  });

  final PluginItem item;
  final bool selected;
  final bool marked;
  final bool showLabels;
  final BoxFit fit;
  final VoidCallback onTap;
  final VoidCallback onHover;
  final VoidCallback? onToggle;
  final bool mediaActive;
  final bool mediaPlaying;
  final bool mediaLoading;
  final double mediaProgress;
  final String? mediaError;
  final ValueChanged<double> onSeek;
  final VoidCallback? onPlayPause;

  IconData get _typeIcon => switch (item.media?.type) {
        'video' => Icons.play_arrow_rounded,
        'audio' => Icons.graphic_eq_rounded,
        'file' => Icons.insert_drive_file_rounded,
        _ => Icons.image_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final PluginMediaInfo? media = item.media;
    final String dimensions = media?.width != null && media?.height != null ? '${media!.width}×${media.height}' : '';
    final String meta = <String>[media?.duration ?? '', media?.size ?? '', dimensions]
        .where((String value) => value.isNotEmpty)
        .join(' · ');
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onHover: (PointerHoverEvent event) {
        if (event.delta != Offset.zero) onHover();
      },
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: selected ? Design.accent.withAlpha(20) : Design.text.withAlpha(5),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: selected ? Design.accent.withAlpha(125) : Design.text.withAlpha(18),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Stack(fit: StackFit.expand, children: <Widget>[
                  ColoredBox(color: Design.text.withAlpha(7), child: _pluginGalleryVisual(item, fit)),
                  if (media?.type != null && media!.type != 'image')
                    Positioned(
                      left: 5,
                      top: 5,
                      child: Container(
                        width: 23,
                        height: 23,
                        decoration: BoxDecoration(color: Colors.black.withAlpha(145), shape: BoxShape.circle),
                        child: Icon(_typeIcon, size: 14, color: Colors.white),
                      ),
                    ),
                  if (media?.duration.isNotEmpty == true)
                    Positioned(
                      right: 5,
                      bottom: 5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration:
                            BoxDecoration(color: Colors.black.withAlpha(165), borderRadius: BorderRadius.circular(3)),
                        child: Text(media!.duration,
                            style: TextStyle(
                                fontSize: Design.baseFontSize - 0.5, fontWeight: FontWeight.w700, color: Colors.white)),
                      ),
                    ),
                  if (onPlayPause != null)
                    Center(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onPlayPause,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(mediaActive ? 190 : 145),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white.withAlpha(80)),
                          ),
                          child: mediaLoading
                              ? const Padding(
                                  padding: EdgeInsets.all(11),
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : Icon(
                                  mediaPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                  size: 23,
                                  color: Colors.white,
                                ),
                        ),
                      ),
                    ),
                  if (mediaActive)
                    Positioned(
                      left: 5,
                      right: 5,
                      bottom: 4,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (TapDownDetails details) {
                          final RenderBox box = context.findRenderObject()! as RenderBox;
                          onSeek((details.localPosition.dx / box.size.width).clamp(0.0, 1.0));
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            minHeight: 4,
                            value: mediaProgress,
                            color: Design.accent,
                            backgroundColor: Colors.black.withAlpha(150),
                          ),
                        ),
                      ),
                    ),
                  if (mediaActive && mediaError != null)
                    Positioned(
                      left: 5,
                      right: 5,
                      bottom: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        color: const Color(0xFFD94B45).withAlpha(220),
                        child: Text(
                          mediaError!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: Design.baseFontSize - 0.5, color: Colors.white),
                        ),
                      ),
                    ),
                  if (onToggle != null)
                    Positioned(
                      right: 5,
                      top: 5,
                      child: GestureDetector(
                        onTap: onToggle,
                        child: Icon(
                          marked ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                          size: 18,
                          color: marked ? Design.accent : Colors.white.withAlpha(210),
                          shadows: const <Shadow>[Shadow(color: Colors.black54, blurRadius: 3)],
                        ),
                      ),
                    ),
                ]),
              ),
            ),
            if (showLabels && (item.title.isNotEmpty || item.subtitle.isNotEmpty || meta.isNotEmpty))
              Padding(
                padding: const EdgeInsets.fromLTRB(3, 5, 3, 1),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  if (item.title.isNotEmpty)
                    Text(item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: Design.baseFontSize + 1,
                            fontWeight: FontWeight.w700,
                            color: Design.text.withAlpha(205))),
                  if (item.subtitle.isNotEmpty || meta.isNotEmpty)
                    Text(
                      item.subtitle.isNotEmpty ? item.subtitle : meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: Design.baseFontSize - 0.5, color: Design.text.withAlpha(95)),
                    ),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}

class _PluginKanbanCard extends StatelessWidget {
  const _PluginKanbanCard({required this.item, this.selected = false, this.onTap, this.onHover});

  final PluginItem item;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onHover;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: onTap == null ? SystemMouseCursors.grabbing : SystemMouseCursors.click,
        onHover: onHover == null
            ? null
            : (PointerHoverEvent event) {
                if (event.delta != Offset.zero) onHover!();
              },
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.only(bottom: 2),
            padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
            decoration: BoxDecoration(
              color: selected ? Design.accent.withAlpha(30) : Design.text.withAlpha(10),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: selected ? Design.accent.withAlpha(80) : Design.text.withAlpha(20)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Row(children: <Widget>[
                _PluginIcon(name: item.icon, accent: Design.accent, size: 14),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: Design.baseFontSize + 1.5,
                          fontWeight: FontWeight.w600,
                          color: Design.text.withAlpha(220))),
                ),
              ]),
              if (item.subtitle.isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                Text(item.subtitle,
                    maxLines: item.subtitleLines,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: Design.baseFontSize + 1, height: 1.3, color: Design.text.withAlpha(125))),
              ],
              if (item.accessories.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: <Widget>[
                    for (final PluginAccessory accessory in item.accessories)
                      Text(accessory.text,
                          style: TextStyle(
                              fontSize: Design.baseFontSize,
                              fontWeight: FontWeight.w600,
                              color: accessory.color ?? Design.accent)),
                  ],
                ),
              ],
            ]),
          ),
        ),
      );
}

Color _diffTint(String type) => switch (type) {
      'add' => const Color(0xFF3FB950),
      'remove' => const Color(0xFFF85149),
      'header' => Design.accent,
      _ => Design.text,
    };

class _PluginUnifiedDiffRow extends StatelessWidget {
  const _PluginUnifiedDiffRow({required this.line});

  final PluginDiffLine line;

  @override
  Widget build(BuildContext context) {
    final Color tint = _diffTint(line.type);
    return Container(
      color: tint.withAlpha(line.type == 'context' ? 3 : 16),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        SizedBox(
          width: 42,
          child: Text(line.oldLine?.toString() ?? '',
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontFamily: 'Consolas', fontSize: Design.baseFontSize + 1, color: Design.text.withAlpha(70))),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 42,
          child: Text(line.newLine?.toString() ?? '',
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontFamily: 'Consolas', fontSize: Design.baseFontSize + 1, color: Design.text.withAlpha(70))),
        ),
        const SizedBox(width: 8),
        Text(
            line.type == 'add'
                ? '+'
                : line.type == 'remove'
                    ? '-'
                    : ' ',
            style: TextStyle(fontFamily: 'Consolas', fontSize: Design.baseFontSize + 1.5, color: tint)),
        const SizedBox(width: 5),
        Expanded(
          child: Text(line.text,
              style: TextStyle(
                  fontFamily: 'Consolas',
                  fontSize: Design.baseFontSize + 1.5,
                  height: 1.35,
                  color: Design.text.withAlpha(205))),
        ),
      ]),
    );
  }
}

class _PluginSplitDiffRow extends StatelessWidget {
  const _PluginSplitDiffRow({required this.line});

  final PluginDiffLine line;

  @override
  Widget build(BuildContext context) {
    if (line.type == 'header') return _PluginUnifiedDiffRow(line: line);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Expanded(child: _cell(show: line.type != 'add', lineNumber: line.oldLine)),
      Container(width: 1, height: 24, color: Design.text.withAlpha(16)),
      Expanded(child: _cell(show: line.type != 'remove', lineNumber: line.newLine)),
    ]);
  }

  Widget _cell({required bool show, required int? lineNumber}) {
    final Color tint = _diffTint(line.type);
    return Container(
      constraints: const BoxConstraints(minHeight: 24),
      color: show ? tint.withAlpha(line.type == 'context' ? 3 : 16) : Design.text.withAlpha(3),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: show
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              SizedBox(
                width: 34,
                child: Text(lineNumber?.toString() ?? '',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontFamily: 'Consolas', fontSize: Design.baseFontSize + 1, color: Design.text.withAlpha(70))),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(line.text,
                    style: TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: Design.baseFontSize + 1,
                        height: 1.35,
                        color: Design.text.withAlpha(205))),
              ),
            ])
          : const SizedBox.shrink(),
    );
  }
}

class _PluginLogRow extends StatelessWidget {
  const _PluginLogRow({required this.line, required this.wrap});

  final PluginLogLine line;
  final bool wrap;

  Color get _tint => switch (line.level) {
        'error' => const Color(0xFFF85149),
        'warn' => const Color(0xFFD29922),
        'success' => const Color(0xFF3FB950),
        'debug' || 'trace' => Design.text.withAlpha(110),
        _ => Design.accent,
      };

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        color: _tint.withAlpha(line.level == 'info' ? 2 : 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          if (line.timestamp.isNotEmpty)
            SizedBox(
              width: 82,
              child: Text(line.timestamp,
                  style: TextStyle(
                      fontFamily: 'Consolas', fontSize: Design.baseFontSize + 1, color: Design.text.withAlpha(80))),
            ),
          SizedBox(
            width: 52,
            child: Text(line.level.toUpperCase(),
                style: TextStyle(
                    fontFamily: 'Consolas', fontSize: Design.baseFontSize, fontWeight: FontWeight.w700, color: _tint)),
          ),
          if (line.source.isNotEmpty)
            SizedBox(
              width: 92,
              child: Text(line.source,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontFamily: 'Consolas', fontSize: Design.baseFontSize + 1, color: Design.text.withAlpha(105))),
            ),
          Expanded(
            child: Text(line.text,
                maxLines: wrap ? null : 1,
                softWrap: wrap,
                overflow: wrap ? TextOverflow.visible : TextOverflow.ellipsis,
                style: TextStyle(
                    fontFamily: 'Consolas',
                    fontSize: Design.baseFontSize + 1.8,
                    height: 1.35,
                    color: Design.text.withAlpha(205))),
          ),
        ]),
      );
}

/// A thin determinate bar shown under a list row that carries `"progress"`.
class _PluginOperationBar extends StatelessWidget {
  const _PluginOperationBar({required this.operation, required this.onCancel});
  final PluginOperation operation;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 7, 10, 7),
        color: Design.accent.withAlpha(18),
        child: Row(children: <Widget>[
          SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 1.5, value: operation.progress, color: Design.accent)),
          const SizedBox(width: 8),
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(operation.title,
                style: TextStyle(
                    fontSize: Design.baseFontSize + 1.5,
                    fontWeight: FontWeight.w700,
                    color: Design.text.withAlpha(220))),
            if (operation.detail.isNotEmpty)
              Text(operation.detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text.withAlpha(130))),
          ])),
          if (operation.cancellable) TextButton(onPressed: onCancel, child: const Text('Cancel')),
        ]),
      );
}

class _PluginStructuredRow extends StatelessWidget {
  const _PluginStructuredRow(
      {required this.selected,
      required this.marked,
      required this.multiSelect,
      required this.onTap,
      required this.onHover,
      required this.onToggle,
      required this.child});
  final bool selected, marked, multiSelect;
  final VoidCallback onTap, onHover, onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onHover: (PointerHoverEvent event) {
          if (event.delta != Offset.zero) onHover();
        },
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 1),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
                color: selected ? Design.accent.withAlpha(34) : Colors.transparent,
                borderRadius: BorderRadius.circular(5)),
            child: Row(children: <Widget>[
              if (multiSelect)
                GestureDetector(
                    onTap: onToggle,
                    child: Padding(
                        padding: const EdgeInsets.only(right: 7),
                        child: Icon(marked ? Icons.check_box : Icons.check_box_outline_blank,
                            size: 16, color: marked ? Design.accent : Design.text.withAlpha(100)))),
              Expanded(child: child),
            ]),
          ),
        ),
      );
}

class _PluginTimelineRow extends StatelessWidget {
  const _PluginTimelineRow(
      {required this.item,
      required this.selected,
      required this.marked,
      required this.multiSelect,
      required this.onTap,
      required this.onHover,
      required this.onToggle});
  final PluginItem item;
  final bool selected, marked, multiSelect;
  final VoidCallback onTap, onHover, onToggle;

  @override
  Widget build(BuildContext context) => _PluginStructuredRow(
        selected: selected,
        marked: marked,
        multiSelect: multiSelect,
        onTap: onTap,
        onHover: onHover,
        onToggle: onToggle,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          SizedBox(
              width: 78,
              child: Text(item.timestamp ?? '',
                  style: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text.withAlpha(125)))),
          Column(children: <Widget>[
            Container(width: 9, height: 9, decoration: BoxDecoration(color: Design.accent, shape: BoxShape.circle)),
            Container(width: 1, height: 30, color: Design.text.withAlpha(35))
          ]),
          const SizedBox(width: 10),
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(item.title,
                style: TextStyle(
                    fontSize: Design.baseFontSize + 2, fontWeight: FontWeight.w600, color: Design.text.withAlpha(220))),
            if (item.subtitle.isNotEmpty)
              Text(item.subtitle,
                  maxLines: item.subtitleLines,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text.withAlpha(145)))
          ])),
        ]),
      );
}

class _PluginChart extends StatefulWidget {
  const _PluginChart({
    required this.title,
    required this.series,
    required this.options,
    required this.onSelect,
    required this.onRangeSelect,
  });

  final String? title;
  final List<PluginChartSeries> series;
  final PluginChartOptions options;
  final void Function(String seriesId, int index, double value) onSelect;
  final void Function(int startIndex, int endIndex) onRangeSelect;

  @override
  State<_PluginChart> createState() => _PluginChartState();
}

class _PluginChartState extends State<_PluginChart> {
  int? _rangeStart;
  int? _rangeEnd;

  int get _pointCount => widget.series.isEmpty
      ? 0
      : widget.series.map((PluginChartSeries series) => series.values.length).reduce((int a, int b) => a > b ? a : b);

  Color _seriesColor(int index) =>
      widget.series[index].color ??
      (index == 0 ? Design.accent : Design.text.withAlpha(100 + (index * 30).clamp(0, 100)));

  String _xLabel(int index) =>
      index >= 0 && index < widget.options.xLabels.length ? widget.options.xLabels[index] : index.toString();

  FlTitlesData _titles() {
    final bool show = widget.options.showAxes;
    return FlTitlesData(
      show: show,
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        axisNameWidget: widget.options.yTitle == null
            ? null
            : Text(widget.options.yTitle!,
                style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(100))),
        sideTitles: SideTitles(
          showTitles: show,
          reservedSize: 42,
          getTitlesWidget: (double value, TitleMeta meta) => Text(
            value.abs() >= 1000 ? value.toStringAsFixed(0) : value.toStringAsFixed(value.abs() < 10 ? 1 : 0),
            style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(95)),
          ),
        ),
      ),
      bottomTitles: AxisTitles(
        axisNameWidget: widget.options.xTitle == null
            ? null
            : Text(widget.options.xTitle!,
                style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(100))),
        sideTitles: SideTitles(
          showTitles: show,
          reservedSize: 28,
          interval: (_pointCount / 6).ceil().clamp(1, 999).toDouble(),
          getTitlesWidget: (double value, TitleMeta meta) {
            final int index = value.round();
            if (index < 0 || index >= _pointCount) return const SizedBox.shrink();
            return SideTitleWidget(
              meta: meta,
              space: 7,
              child: Text(
                _xLabel(index),
                maxLines: 1,
                style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(95)),
              ),
            );
          },
        ),
      ),
    );
  }

  FlGridData _grid() => FlGridData(
        show: widget.options.showGrid,
        drawVerticalLine: true,
        getDrawingHorizontalLine: (_) => FlLine(color: Design.text.withAlpha(16), strokeWidth: 1),
        getDrawingVerticalLine: (_) => FlLine(color: Design.text.withAlpha(9), strokeWidth: 1),
      );

  (double, double) _yBounds() {
    final List<double> values = widget.series.expand((PluginChartSeries series) => series.values).toList();
    final double rawMin = values.reduce((double a, double b) => a < b ? a : b);
    final double rawMax = values.reduce((double a, double b) => a > b ? a : b);
    final double padding =
        rawMax == rawMin ? (rawMax.abs() * 0.08).clamp(1, double.infinity).toDouble() : (rawMax - rawMin) * 0.08;
    return (widget.options.minY ?? rawMin - padding, widget.options.maxY ?? rawMax + padding);
  }

  Widget _lineChart() {
    final (double, double) bounds = _yBounds();
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (_pointCount - 1).toDouble(),
        minY: bounds.$1,
        maxY: bounds.$2,
        borderData: FlBorderData(show: false),
        gridData: _grid(),
        titlesData: _titles(),
        lineTouchData: LineTouchData(
          enabled: widget.options.tooltips,
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (List<LineBarSpot> spots) => spots
                .map((LineBarSpot spot) => LineTooltipItem(
                      '${widget.series[spot.barIndex].label}\n${_xLabel(spot.x.round())}: ${spot.y}',
                      TextStyle(
                          fontSize: Design.baseFontSize + 1,
                          fontWeight: FontWeight.w600,
                          color: _seriesColor(spot.barIndex)),
                    ))
                .toList(growable: false),
          ),
        ),
        lineBarsData: <LineChartBarData>[
          for (int seriesIndex = 0; seriesIndex < widget.series.length; seriesIndex++)
            LineChartBarData(
              spots: <FlSpot>[
                for (int index = 0; index < widget.series[seriesIndex].values.length; index++)
                  FlSpot(index.toDouble(), widget.series[seriesIndex].values[index]),
              ],
              isCurved: widget.options.type == 'area',
              curveSmoothness: 0.2,
              color: _seriesColor(seriesIndex),
              barWidth: 2,
              dotData: FlDotData(show: widget.series[seriesIndex].values.length <= 16),
              belowBarData: BarAreaData(
                show: widget.options.type == 'area',
                color: _seriesColor(seriesIndex).withAlpha(28),
              ),
            ),
        ],
      ),
    );
  }

  Widget _barChart() {
    final (double, double) bounds = _yBounds();
    return BarChart(
      BarChartData(
        minY: bounds.$1 > 0 ? 0 : bounds.$1,
        maxY: bounds.$2,
        borderData: FlBorderData(show: false),
        gridData: _grid(),
        titlesData: _titles(),
        alignment: BarChartAlignment.spaceAround,
        barTouchData: BarTouchData(
          enabled: widget.options.tooltips,
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (BarChartGroupData group, int groupIndex, BarChartRodData rod, int rodIndex) {
              if (rodIndex >= widget.series.length) return null;
              return BarTooltipItem(
                '${widget.series[rodIndex].label}\n${_xLabel(group.x)}: ${rod.toY}',
                TextStyle(
                    fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.w600, color: _seriesColor(rodIndex)),
              );
            },
          ),
        ),
        barGroups: <BarChartGroupData>[
          for (int index = 0; index < _pointCount; index++)
            BarChartGroupData(
              x: index,
              barsSpace: 2,
              barRods: <BarChartRodData>[
                for (int seriesIndex = 0; seriesIndex < widget.series.length; seriesIndex++)
                  if (index < widget.series[seriesIndex].values.length)
                    BarChartRodData(
                      toY: widget.series[seriesIndex].values[index],
                      width: (22 / widget.series.length).clamp(3, 12).toDouble(),
                      color: _seriesColor(seriesIndex),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                    ),
              ],
            ),
        ],
      ),
    );
  }

  int _indexAt(double x, double width) => (x / width * (_pointCount - 1)).round().clamp(0, _pointCount - 1).toInt();

  @override
  Widget build(BuildContext context) {
    if (widget.series.isEmpty) {
      return Center(child: Text('No chart data', style: TextStyle(color: Design.text.withAlpha(120))));
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        if (widget.title != null)
          Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(widget.title!,
                  style:
                      TextStyle(fontSize: Design.baseFontSize + 2.5, fontWeight: FontWeight.w700, color: Design.text))),
        Expanded(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) => GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapUp: (TapUpDetails details) {
                final PluginChartSeries selected = widget.series.first;
                final int index = _indexAt(details.localPosition.dx, constraints.maxWidth)
                    .clamp(0, selected.values.length - 1)
                    .toInt();
                widget.onSelect(selected.id, index, selected.values[index]);
              },
              onHorizontalDragStart: widget.options.selectableRange
                  ? (DragStartDetails details) {
                      final int index = _indexAt(details.localPosition.dx, constraints.maxWidth);
                      setState(() {
                        _rangeStart = index;
                        _rangeEnd = index;
                      });
                    }
                  : null,
              onHorizontalDragUpdate: widget.options.selectableRange
                  ? (DragUpdateDetails details) =>
                      setState(() => _rangeEnd = _indexAt(details.localPosition.dx, constraints.maxWidth))
                  : null,
              onHorizontalDragEnd: widget.options.selectableRange
                  ? (_) {
                      if (_rangeStart == null || _rangeEnd == null) return;
                      widget.onRangeSelect(
                        _rangeStart! < _rangeEnd! ? _rangeStart! : _rangeEnd!,
                        _rangeStart! > _rangeEnd! ? _rangeStart! : _rangeEnd!,
                      );
                    }
                  : null,
              child: Stack(children: <Widget>[
                Positioned.fill(child: widget.options.type == 'bar' ? _barChart() : _lineChart()),
                if (_rangeStart != null && _rangeEnd != null)
                  Positioned(
                    left: ((_rangeStart! < _rangeEnd! ? _rangeStart! : _rangeEnd!) /
                            (_pointCount - 1) *
                            constraints.maxWidth)
                        .clamp(0, constraints.maxWidth),
                    width: (((_rangeStart! - _rangeEnd!).abs() + 1) / _pointCount * constraints.maxWidth)
                        .clamp(3, constraints.maxWidth),
                    top: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Design.accent.withAlpha(20),
                          border: Border.symmetric(vertical: BorderSide(color: Design.accent.withAlpha(100))),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ),
        if (widget.options.showLegend) ...<Widget>[
          const SizedBox(height: 8),
          Wrap(spacing: 14, runSpacing: 5, children: <Widget>[
            for (int index = 0; index < widget.series.length; index++)
              Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                Container(
                    width: 8, height: 8, decoration: BoxDecoration(color: _seriesColor(index), shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Text(widget.series[index].label,
                    style: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text.withAlpha(145))),
              ]),
          ]),
        ],
      ]),
    );
  }
}

class _PluginProgressBar extends StatelessWidget {
  const _PluginProgressBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 3,
        child: LinearProgressIndicator(
          value: value,
          backgroundColor: Design.text.withAlpha(20),
          valueColor: AlwaysStoppedAnimation<Color>(Design.accent.withAlpha(200)),
        ),
      ),
    );
  }
}

/// Axis-free inline mini-chart used by metadata entries with `"sparkline"`.
class _PluginSparkline extends StatelessWidget {
  const _PluginSparkline({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(90, 16),
      painter: _SparklinePainter(values: values, color: color),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    double min = values.first, max = values.first;
    for (final double v in values) {
      if (v < min) min = v;
      if (v > max) max = v;
    }
    final double range = max - min;
    // Inset vertically so the stroke doesn't clip at the extremes.
    const double inset = 1.5;
    final double drawHeight = size.height - inset * 2;
    final Path line = Path();
    for (int i = 0; i < values.length; i++) {
      final double x = size.width * i / (values.length - 1);
      final double normalized = range == 0 ? 0.5 : (values[i] - min) / range;
      final double y = inset + drawHeight * (1 - normalized);
      if (i == 0) {
        line.moveTo(x, y);
      } else {
        line.lineTo(x, y);
      }
    }
    // Faint fill under the line, then the line itself.
    final Path fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = color.withAlpha(26));
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter oldDelegate) =>
      oldDelegate.color != color || !listEquals(oldDelegate.values, values);
}

/// Dense key-value rows shown under preview/detail markdown: label column on
/// the left, value (with optional icon, image, tint, and link) on the right.
class _PluginMetadataPane extends StatelessWidget {
  const _PluginMetadataPane({required this.entries, required this.topGap, required this.onAction});

  final List<PluginMetadataEntry> entries;

  /// Whether markdown precedes the pane (adds a separating divider).
  final bool topGap;
  final void Function(PluginAction action) onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: topGap ? 10 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (topGap)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(height: 1, color: Design.text.withAlpha(18)),
            ),
          for (final PluginMetadataEntry entry in entries)
            if (entry.separator)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Container(height: 1, color: Design.text.withAlpha(18)),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2.5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: 90,
                      child: Text(
                        entry.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: Design.baseFontSize + 1,
                          fontWeight: FontWeight.w600,
                          color: Design.text.withAlpha(120),
                          height: 1.35,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: _value(entry)),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _value(PluginMetadataEntry entry) {
    final Color valueColor = entry.color ?? Design.text.withAlpha(210);
    final Widget text = Text(
      entry.text,
      style: TextStyle(
        fontSize: Design.baseFontSize + 1.5,
        fontWeight: FontWeight.w600,
        color: entry.url != null ? Design.accent : valueColor,
        decoration: entry.url != null ? TextDecoration.underline : null,
        height: 1.35,
      ),
    );
    final Widget value = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (entry.sparkline != null)
          Padding(
            padding: EdgeInsets.only(right: entry.text.isEmpty ? 0 : 6, top: 1),
            child: _PluginSparkline(values: entry.sparkline!, color: entry.color ?? Design.accent),
          ),
        if (entry.icon != null)
          Padding(
            padding: const EdgeInsets.only(right: 5, top: 1),
            child: Icon(PluginIcons.resolve(entry.icon), size: 12, color: entry.color ?? Design.accent),
          )
        else if (entry.color != null && entry.sparkline == null)
          Padding(
            padding: const EdgeInsets.only(right: 5, top: 4),
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: entry.color, shape: BoxShape.circle),
            ),
          ),
        Flexible(child: text),
      ],
    );
    final Widget visualContent = entry.image == null
        ? value
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  entry.image!,
                  width: entry.imageWidth ?? 132,
                  height: entry.height ?? 176,
                  fit: BoxFit.cover,
                  errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) => const SizedBox.shrink(),
                ),
              ),
              if (entry.text.isNotEmpty) const SizedBox(height: 4),
              value,
            ],
          );
    final Widget linkableContent = entry.url == null
        ? visualContent
        : MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => WinUtils.open(entry.url!.trim()),
              child: visualContent,
            ),
          );
    final Widget content = entry.actions.isEmpty
        ? linkableContent
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              linkableContent,
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: entry.actions
                    .map((PluginAction action) => _MetadataActionButton(action: action, onTap: () => onAction(action)))
                    .toList(growable: false),
              ),
            ],
          );
    return content;
  }
}

class _MetadataActionButton extends StatelessWidget {
  const _MetadataActionButton({required this.action, required this.onTap});

  final PluginAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = action.destructive ? const Color(0xFFE5534B) : Design.accent;
    return SelectionContainer.disabled(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: color.withAlpha(24),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: color.withAlpha(110)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (action.icon != null) ...<Widget>[
                  Icon(PluginIcons.resolve(action.icon), size: 12, color: color),
                  const SizedBox(width: 5),
                ],
                Text(action.title,
                    style: TextStyle(fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.w700, color: color)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Builds a cover-fit image for a grid tile whose `icon` is a raster URL/path
/// (poster/thumbnail), so it fills the tile instead of rendering as a small
/// centered icon. Returns null for named/emoji/color icons, SVGs and missing
/// files, which keep the default small-icon layout.
Widget? _pluginGridImage(String? name) {
  final String? value = name?.trim();
  if (value == null || value.isEmpty) return null;
  if (parsePluginColor(value) != null) return null;
  final bool isSvg = Uri.tryParse(value)?.path.toLowerCase().endsWith('.svg') ?? false;
  if (isSvg) return null;
  Widget fallback() => Container(
        alignment: Alignment.center,
        color: Design.text.withAlpha(10),
        child: Icon(PluginIcons.fallback, color: Design.text.withAlpha(90)),
      );
  if (value.startsWith('http://') || value.startsWith('https://')) {
    return Image.network(
      value,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => fallback(),
    );
  }
  if (value.startsWith('file://')) {
    final File file = File(Uri.parse(value).toFilePath(windows: true));
    if (!file.existsSync()) return null;
    return Image.file(
      file,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => fallback(),
    );
  }
  return null;
}

/// A single grid tile: icon over title/subtitle, with an accent selection
/// treatment matching the launcher's design language.
class _PluginGridTile extends StatelessWidget {
  const _PluginGridTile({
    required this.item,
    required this.isSelected,
    required this.onTap,
    required this.onHover,
  });

  final PluginItem item;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final Color accent = Design.accent;
    final Color onSurface = Design.text;

    // A tileColor turns the tile into a filled swatch: text flips to black or
    // white for contrast, and selection becomes a contrast ring (an accent
    // border would clash with arbitrary swatch colors).
    final Color? tile = item.tileColor;
    final Color labelColor = tile == null ? onSurface : (tile.computeLuminance() > 0.5 ? Colors.black : Colors.white);

    // A raster `icon` with no tileColor fills the tile as a cover image (a
    // poster-wall look) with the label beneath; named/emoji/color icons keep
    // the small centered-icon layout.
    final Widget? poster = tile == null ? _pluginGridImage(item.icon) : null;

    final Widget label = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (item.title.isNotEmpty)
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: Design.baseFontSize + 1,
              fontWeight: FontWeight.w600,
              color: isSelected ? labelColor : labelColor.withAlpha(210),
            ),
          ),
        if (item.subtitle.isNotEmpty)
          Text(
            item.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: Design.baseFontSize, color: labelColor.withAlpha(130)),
          ),
      ],
    );

    final Widget content = poster != null
        ? Column(
            children: <Widget>[
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: SizedBox(width: double.infinity, child: poster),
                ),
              ),
              if (item.title.isNotEmpty || item.subtitle.isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 4), child: label),
            ],
          )
        : Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (tile == null || item.icon != null) _PluginIcon(name: item.icon, accent: accent, size: 22),
              if (item.title.isNotEmpty || item.subtitle.isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                label,
              ],
            ],
          );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onHover: (PointerHoverEvent event) {
        if (event.delta != Offset.zero) onHover();
      },
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          padding: EdgeInsets.all(poster != null ? 4 : 6),
          decoration: BoxDecoration(
            color: tile ?? (isSelected ? accent.withAlpha(40) : onSurface.withAlpha(8)),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: tile != null
                  ? (isSelected ? labelColor.withAlpha(220) : labelColor.withAlpha(40))
                  : (isSelected ? accent.withAlpha(120) : onSurface.withAlpha(14)),
              width: tile != null && isSelected ? 2 : 1,
            ),
          ),
          child: content,
        ),
      ),
    );
  }
}
